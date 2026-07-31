#requires -Version 5.1
<#
.SYNOPSIS
Retires the former Assistant Framework Memory Graph installation.

.DESCRIPTION
Removes only exact framework-owned registrations, skills, tools, and
ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START marker blocks. Provider memory data
is preserved unless -PurgeData is explicitly requested.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('claude', 'codex', 'gemini')]
    [string]$Agent,
    [switch]$DryRun,
    [switch]$PurgeData,
    [switch]$Help
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$maxJsonInputBytes = 4 * 1024 * 1024
$maxJsonIdentityDepth = 64
$maxJsonIdentityProperties = 10000
$maxJsonIdentityValues = 10000

function Show-Usage {
    Write-Host 'Usage: .\cleanup-memory-graph.ps1 [-Agent <claude, codex, gemini>] [-DryRun] [-PurgeData]'
}

function Get-FullPath { param([string]$LiteralPath) [System.IO.Path]::GetFullPath($LiteralPath) }

function Get-CanonicalPath {
    param([string]$LiteralPath)
    $full = Get-FullPath $LiteralPath
    if (([string]::Equals($full, '/var', [System.StringComparison]::Ordinal) -or $full.StartsWith('/var/', [System.StringComparison]::Ordinal)) -and (Test-Path -LiteralPath '/private/var')) {
        return '/private/var' + $full.Substring(4)
    }
    return $full
}

function Assert-RawConfiguredCodexHome {
    param([string]$LiteralPath)
    if ([string]::IsNullOrWhiteSpace($LiteralPath) -or -not [System.IO.Path]::IsPathRooted($LiteralPath) -or
        $LiteralPath.StartsWith('\\?\') -or $LiteralPath.StartsWith('\\.\') -or $LiteralPath.StartsWith('//?/') -or $LiteralPath.StartsWith('//./')) {
        throw 'CODEX_HOME must be a non-root absolute path.'
    }
    $full = Get-FullPath $LiteralPath
    if (Test-PathEqual $full ([System.IO.Path]::GetPathRoot($full))) { throw 'CODEX_HOME must be a non-root absolute path.' }
    return $full
}

function Test-PathEqual {
    param([string]$Left, [string]$Right)
    [string]::Equals((Get-FullPath $Left).TrimEnd([char[]]'\/'), (Get-FullPath $Right).TrimEnd([char[]]'\/'), [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-SafeHome {
    param([string]$LiteralPath)
    if ([string]::IsNullOrWhiteSpace($LiteralPath) -or -not [System.IO.Path]::IsPathRooted($LiteralPath)) { throw 'HOME must be an absolute path.' }
    $full = Get-FullPath $LiteralPath
    if (Test-PathEqual $full ([System.IO.Path]::GetPathRoot($full))) { throw 'HOME cannot be a filesystem root.' }
    if (Test-Path -LiteralPath $full) {
        $item = Get-Item -LiteralPath $full -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing reparse-point HOME: $full" }
    }
    $full
}

function Assert-NoReparseTraversal {
    param([string]$LiteralPath, [string]$Purpose)
    $full = Get-FullPath $LiteralPath
    $retirementHome = if (Get-Variable -Name RetirementUserHome -Scope Script -ErrorAction SilentlyContinue) { $script:RetirementUserHome } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($retirementHome) -and $full.StartsWith($retirementHome.TrimEnd([char[]]'\\/') + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        $current = $retirementHome
        $parts = @($full.Substring($retirementHome.TrimEnd([char[]]'\\/').Length) -split '[\\/]' | Where-Object { $_ })
    }
    else {
        $root = [System.IO.Path]::GetPathRoot($full)
        $current = $root
        $parts = @($full.Substring($root.Length) -split '[\\/]' | Where-Object { $_ })
    }
    foreach ($part in $parts) {
        $current = Join-Path $current $part
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing $Purpose through reparse point: $current" }
        }
    }
    $full
}

function Assert-SafeChild {
    param([string]$Root, [string]$LiteralPath, [string]$Purpose, [string]$UserHome)
    $rootFull = (Get-FullPath $Root).TrimEnd([char[]]'\\/')
    $target = Get-FullPath $LiteralPath
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if (-not $target.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or (Test-PathEqual $target $UserHome)) {
        throw "Refusing unsafe $Purpose target: $target"
    }
    Assert-NoReparseTraversal -LiteralPath $target -Purpose $Purpose
}

function Assert-FileAvailableForExclusiveUpdate {
    param([string]$LiteralPath, [string]$Purpose)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { return }
    $probe = $null
    try {
        $probe = New-Object System.IO.FileStream($LiteralPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    }
    catch {
        throw "Locked-file preflight failed for $Purpose at '$LiteralPath'. Close Codex App and rerun the installer. No installation changes were made. Cause: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $probe) { $probe.Dispose() }
    }
}

function Assert-RegularFileNoFollow {
    param([string]$LiteralPath, [string]$Purpose)
    try { $item = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop }
    catch { throw "Refusing non-regular ${Purpose}: $LiteralPath" }
    if ($item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Refusing non-regular ${Purpose}: $LiteralPath"
    }
    if (-not (Test-IsWindowsHost)) {
        $unixStat = $item.PSObject.Properties['UnixStat'].Value
        if ($null -eq $unixStat -or $unixStat.ItemType -ne 1) { throw "Refusing non-regular ${Purpose}: $LiteralPath" }
    }
}

function Read-StrictUtf8Document {
    param([string]$LiteralPath)
    Assert-RegularFileNoFollow -LiteralPath $LiteralPath -Purpose 'structured configuration'
    $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    try { $text = $utf8Strict.GetString($bytes, $offset, $bytes.Length - $offset) }
    catch { throw "Invalid UTF-8 in $LiteralPath; preserved unchanged." }
    [PSCustomObject]@{ Text = $text; HasBom = $hasBom }
}

function Read-StrictUtf8 { param([string]$LiteralPath) (Read-StrictUtf8Document $LiteralPath).Text }

function Test-IsWindowsHost { [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT }

function Get-UnixFileModeExact {
    param([string]$LiteralPath)
    $method = [System.IO.File].GetMethod('GetUnixFileMode', [Type[]]@([string]))
    if ($null -eq $method) { throw "Unix file-mode APIs are unavailable for $LiteralPath; preserved unchanged." }
    return $method.Invoke($null, [object[]]@($LiteralPath))
}

function Set-UnixFileModeExact {
    param([string]$LiteralPath, $Mode)
    $method = [System.IO.File].GetMethod('SetUnixFileMode', [Type[]]@([string], $Mode.GetType()))
    if ($null -eq $method) { throw "Unix file-mode APIs are unavailable for $LiteralPath; preserved unchanged." }
    [void]$method.Invoke($null, [object[]]@($LiteralPath, $Mode))
}

function Test-ByteArraysEqual {
    param([byte[]]$Expected, [byte[]]$Actual)
    if ($null -eq $Expected -or $null -eq $Actual -or $Expected.Length -ne $Actual.Length) { return $false }
    for ($index = 0; $index -lt $Expected.Length; $index++) {
        if ($Expected[$index] -ne $Actual[$index]) { return $false }
    }
    return $true
}

function Get-FileSystemAclExtensionsType {
    $type = [Type]::GetType('System.IO.FileSystemAclExtensions, System.IO.FileSystem.AccessControl', $false)
    if ($null -eq $type) {
        try { $type = ([Reflection.Assembly]::Load('System.IO.FileSystem.AccessControl')).GetType('System.IO.FileSystemAclExtensions', $false) }
        catch { $type = $null }
    }
    return $type
}

function Get-FileStreamAcl {
    param([System.IO.FileStream]$Stream)
    $method = $Stream.GetType().GetMethod('GetAccessControl', [Type[]]@())
    if ($null -ne $method) { return $method.Invoke($Stream, @()) }
    $type = Get-FileSystemAclExtensionsType
    if ($null -eq $type) { throw 'File-system ACL APIs are unavailable.' }
    $method = $type.GetMethod('GetAccessControl', [Type[]]@([System.IO.FileStream]))
    if ($null -eq $method) { throw 'Compatible FileSystemAclExtensions.GetAccessControl API was not found.' }
    return $method.Invoke($null, [object[]]@($Stream))
}

function Set-FileStreamAcl {
    param([System.IO.FileStream]$Stream, [System.Security.AccessControl.FileSecurity]$Acl)
    $method = $Stream.GetType().GetMethod('SetAccessControl', [Type[]]@([System.Security.AccessControl.FileSecurity]))
    if ($null -ne $method) { [void]$method.Invoke($Stream, [object[]]@($Acl)); return }
    $type = Get-FileSystemAclExtensionsType
    if ($null -eq $type) { throw 'File-system ACL APIs are unavailable.' }
    $method = $type.GetMethod('SetAccessControl', [Type[]]@([System.IO.FileStream], [System.Security.AccessControl.FileSecurity]))
    if ($null -eq $method) { throw 'Compatible FileSystemAclExtensions.SetAccessControl API was not found.' }
    [void]$method.Invoke($null, [object[]]@($Stream, $Acl))
}

function Get-OwnerGroupDaclDifferences {
    param([System.Security.AccessControl.FileSecurity]$Expected, [System.Security.AccessControl.FileSecurity]$Actual)
    $differences = New-Object 'System.Collections.Generic.List[string]'
    $expectedRaw = [System.Security.AccessControl.RawSecurityDescriptor]::new($Expected.GetSecurityDescriptorBinaryForm(), 0)
    $actualRaw = [System.Security.AccessControl.RawSecurityDescriptor]::new($Actual.GetSecurityDescriptorBinaryForm(), 0)
    if ($expectedRaw.Owner.Value -cne $actualRaw.Owner.Value) { $differences.Add('owner') }
    if ($expectedRaw.Group.Value -cne $actualRaw.Group.Value) { $differences.Add('group') }
    if ($Expected.AreAccessRulesProtected -ne $Actual.AreAccessRulesProtected) { $differences.Add('protection') }
    if (-not $Expected.AreAccessRulesCanonical -or -not $Actual.AreAccessRulesCanonical) { $differences.Add('noncanonical') }
    if ($null -eq $expectedRaw.DiscretionaryAcl -or $null -eq $actualRaw.DiscretionaryAcl) { $differences.Add('null_dacl') }
    else {
        $expectedDacl = New-Object byte[] $expectedRaw.DiscretionaryAcl.BinaryLength
        $actualDacl = New-Object byte[] $actualRaw.DiscretionaryAcl.BinaryLength
        $expectedRaw.DiscretionaryAcl.GetBinaryForm($expectedDacl, 0)
        $actualRaw.DiscretionaryAcl.GetBinaryForm($actualDacl, 0)
        if (-not (Test-ByteArraysEqual -Expected $expectedDacl -Actual $actualDacl)) { $differences.Add('dacl') }
    }
    return $differences.ToArray()
}

function New-BinaryDaclFileSecurity {
    param([System.Security.AccessControl.FileSecurity]$ReferenceAcl)
    $raw = [System.Security.AccessControl.RawSecurityDescriptor]::new($ReferenceAcl.GetSecurityDescriptorBinaryForm(), 0)
    if ($null -eq $raw.DiscretionaryAcl -or -not $ReferenceAcl.AreAccessRulesCanonical) { throw 'Cannot safely preserve a null or noncanonical DACL.' }
    $accessOnly = New-Object System.Security.AccessControl.FileSecurity
    $accessOnly.SetSecurityDescriptorBinaryForm($ReferenceAcl.GetSecurityDescriptorBinaryForm(), [System.Security.AccessControl.AccessControlSections]::Access)
    return $accessOnly
}

function New-SecuredCreateNewStream {
    param([string]$LiteralPath, [System.Security.AccessControl.FileSecurity]$FileSecurity)
    $rights = [System.Security.AccessControl.FileSystemRights]([System.Security.AccessControl.FileSystemRights]::ReadData -bor [System.Security.AccessControl.FileSystemRights]::WriteData -bor [System.Security.AccessControl.FileSystemRights]::ReadPermissions -bor [System.Security.AccessControl.FileSystemRights]::Synchronize)
    $types = [Type[]]@([string], [System.IO.FileMode], [System.Security.AccessControl.FileSystemRights], [System.IO.FileShare], [int], [System.IO.FileOptions], [System.Security.AccessControl.FileSecurity])
    $constructor = [System.IO.FileStream].GetConstructor($types)
    if ($null -ne $constructor) { return $constructor.Invoke([object[]]@($LiteralPath, [System.IO.FileMode]::CreateNew, $rights, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::None, $FileSecurity)) }
    $type = Get-FileSystemAclExtensionsType
    if ($null -eq $type) { throw 'File-system ACL APIs are unavailable.' }
    $create = @($type.GetMethods() | Where-Object { $_.Name -eq 'Create' -and $_.GetParameters().Count -eq 7 -and $_.GetParameters()[0].ParameterType -eq [System.IO.FileInfo] } | Select-Object -First 1)
    if ($create.Count -ne 1) { throw 'Compatible FileSystemAclExtensions.Create API was not found.' }
    return $create[0].Invoke($null, [object[]]@([System.IO.FileInfo]::new($LiteralPath), [System.IO.FileMode]::CreateNew, $rights, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::None, $FileSecurity))
}

function Initialize-WindowsFileIdentityInterop {
    if ($null -ne ('AssistantFrameworkCleanup.NativeFileIdentity' -as [Type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace AssistantFrameworkCleanup {
    public static class NativeFileIdentity {
        private const uint GenericRead = 0x80000000u;
        private const uint ReadControl = 0x00020000u;
        private const uint WriteDac = 0x00040000u;
        private const uint OpenExisting = 3u;
        private const uint FileAttributeNormal = 0x00000080u;
        [StructLayout(LayoutKind.Sequential)] private struct FileTime { public uint LowDateTime; public uint HighDateTime; }
        [StructLayout(LayoutKind.Sequential)] private struct Info { public uint Attributes; public FileTime Creation; public FileTime Access; public FileTime Write; public uint Volume; public uint SizeHigh; public uint SizeLow; public uint NumberOfLinks; public uint IndexHigh; public uint IndexLow; }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern SafeFileHandle CreateFileW(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError=true)] private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out Info info);
        private static SafeFileHandle OpenChecked(string path, uint access, uint disposition) { var handle = CreateFileW(path, access, 0u, IntPtr.Zero, disposition, FileAttributeNormal, IntPtr.Zero); if (handle.IsInvalid) { var error = Marshal.GetLastWin32Error(); handle.Dispose(); throw new Win32Exception(error); } return handle; }
        public static SafeFileHandle OpenReadSecurityExclusive(string path) { return OpenChecked(path, GenericRead | ReadControl, OpenExisting); }
        public static SafeFileHandle OpenReadWriteDaclExclusive(string path) { return OpenChecked(path, GenericRead | ReadControl | WriteDac, OpenExisting); }
        public static uint GetLinkCount(SafeFileHandle handle) { Info information; if (!GetFileInformationByHandle(handle, out information)) throw new Win32Exception(Marshal.GetLastWin32Error()); return information.NumberOfLinks; }
    }
}
'@
}

function New-FileStreamFromSafeFileHandle {
    param($SafeFileHandle)
    try { return New-Object System.IO.FileStream($SafeFileHandle, [System.IO.FileAccess]::Read) }
    catch { $SafeFileHandle.Dispose(); throw }
}

function Open-WindowsFileSecurityStream {
    param([string]$LiteralPath)
    Initialize-WindowsFileIdentityInterop
    return New-FileStreamFromSafeFileHandle ([AssistantFrameworkCleanup.NativeFileIdentity]::OpenReadSecurityExclusive($LiteralPath))
}

function Open-WindowsFileDaclWriteStream {
    param([string]$LiteralPath)
    Initialize-WindowsFileIdentityInterop
    return New-FileStreamFromSafeFileHandle ([AssistantFrameworkCleanup.NativeFileIdentity]::OpenReadWriteDaclExclusive($LiteralPath))
}

function Get-WindowsFileLinkCount {
    param($SafeFileHandle)
    Initialize-WindowsFileIdentityInterop
    return [AssistantFrameworkCleanup.NativeFileIdentity]::GetLinkCount($SafeFileHandle)
}

function Write-AtomicUtf8 {
    param([string]$LiteralPath, [string]$Content, [bool]$HasBom, [byte[]]$ExpectedBaseBytes)
    $directory = Split-Path -Parent $LiteralPath
    $temp = Join-Path $directory ('.assistant-framework-retire-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $backup = $temp + '.bak'
    $rollback = $temp + '.rollback'
    Assert-RegularFileNoFollow -LiteralPath $LiteralPath -Purpose 'atomic replacement destination'
    Assert-NoReparseTraversal -LiteralPath $LiteralPath -Purpose 'atomic replacement'
    $originalItem = Get-Item -LiteralPath $LiteralPath -Force
    if (($originalItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing atomic replacement through reparse point: $LiteralPath" }
    $originalAttributes = $originalItem.Attributes
    $originalBytes = [System.IO.File]::ReadAllBytes($LiteralPath)
    if (-not (Test-ByteArraysEqual -Expected $ExpectedBaseBytes -Actual $originalBytes)) { throw "Atomic replacement source changed before commit: $LiteralPath" }
    $isWindowsHost = Test-IsWindowsHost
    $originalMode = if (-not $isWindowsHost) { Get-UnixFileModeExact -LiteralPath $LiteralPath } else { $null }
    $originalAcl = $null
    if ($isWindowsHost) {
        $originalStream = $null
        try {
            $originalStream = Open-WindowsFileSecurityStream -LiteralPath $LiteralPath
            $originalAcl = Get-FileStreamAcl -Stream $originalStream
            if (@(Get-OwnerGroupDaclDifferences -Expected $originalAcl -Actual $originalAcl).Count -ne 0) { throw "Cannot safely preserve existing owner, group, and DACL for $LiteralPath" }
        }
        finally { if ($null -ne $originalStream) { $originalStream.Dispose() } }
    }
    $contentBytes = $utf8NoBom.GetBytes($Content)
    if ($HasBom) {
        $bytes = New-Object byte[] ($contentBytes.Length + 3)
        $bytes[0] = 0xEF; $bytes[1] = 0xBB; $bytes[2] = 0xBF
        [Array]::Copy($contentBytes, 0, $bytes, 3, $contentBytes.Length)
        $expectedBytes = $bytes
    }
    else { $expectedBytes = $contentBytes }
    try {
        $tempStream = $null
        try {
            if ($isWindowsHost) {
                $tempStream = New-SecuredCreateNewStream -LiteralPath $temp -FileSecurity $originalAcl
                [System.IO.File]::SetAttributes($temp, $originalAttributes)
            }
            else {
                $tempStream = [System.IO.File]::Open($temp, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                [System.IO.File]::SetAttributes($temp, $originalAttributes)
                Set-UnixFileModeExact -LiteralPath $temp -Mode $originalMode
                if ((Get-UnixFileModeExact -LiteralPath $temp) -ne $originalMode) { throw "Temporary mode verification failed for $LiteralPath" }
            }
            $tempStream.Write($expectedBytes, 0, $expectedBytes.Length)
            $tempStream.Flush($true)
        }
        finally { if ($null -ne $tempStream) { $tempStream.Dispose() } }
        [System.IO.File]::Replace($temp, $LiteralPath, $backup, $false)
        if (-not (Test-ByteArraysEqual -Expected $ExpectedBaseBytes -Actual ([System.IO.File]::ReadAllBytes($backup)))) { throw "Atomic replacement backup verification failed for $LiteralPath" }
        if (-not (Test-ByteArraysEqual -Expected $expectedBytes -Actual ([System.IO.File]::ReadAllBytes($LiteralPath)))) {
            throw "Atomic replacement content verification failed for $LiteralPath"
        }
        if ((Get-Item -LiteralPath $LiteralPath -Force).Attributes -ne $originalAttributes) {
            throw "Atomic replacement attributes verification failed for $LiteralPath"
        }
        if (-not $isWindowsHost -and (Get-UnixFileModeExact -LiteralPath $LiteralPath) -ne $originalMode) {
            throw "Atomic replacement mode verification failed for $LiteralPath"
        }
        if ($isWindowsHost) {
            $committedStream = $null
            try {
                $committedStream = Open-WindowsFileDaclWriteStream -LiteralPath $LiteralPath
                if ((Get-WindowsFileLinkCount -SafeFileHandle $committedStream.SafeFileHandle) -ne 1) { throw "Atomic replacement link-count verification failed for $LiteralPath" }
                $committedAcl = Get-FileStreamAcl -Stream $committedStream
                $differences = @(Get-OwnerGroupDaclDifferences -Expected $originalAcl -Actual $committedAcl)
                if ($differences -contains 'owner' -or $differences -contains 'group' -or $differences -contains 'noncanonical' -or $differences -contains 'null_dacl') { throw "Atomic replacement owner, group, and DACL verification failed for $LiteralPath" }
                if ($differences.Count -ne 0) { Set-FileStreamAcl -Stream $committedStream -Acl (New-BinaryDaclFileSecurity -ReferenceAcl $originalAcl) }
                if (@(Get-OwnerGroupDaclDifferences -Expected $originalAcl -Actual (Get-FileStreamAcl -Stream $committedStream)).Count -ne 0) { throw "Atomic replacement owner, group, and DACL verification failed for $LiteralPath" }
            }
            finally { if ($null -ne $committedStream) { $committedStream.Dispose() } }
        }
    }
    catch {
        $replacementError = $_
        if (Test-Path -LiteralPath $backup -PathType Leaf) {
            try {
                if (Test-Path -LiteralPath $LiteralPath -PathType Leaf) { [System.IO.File]::Move($LiteralPath, $rollback) }
                [System.IO.File]::Move($backup, $LiteralPath)
                $restoredBytes = [System.IO.File]::ReadAllBytes($LiteralPath)
                if (-not (Test-ByteArraysEqual -Expected $originalBytes -Actual $restoredBytes)) { throw "Atomic rollback byte verification failed for $LiteralPath" }
                if ((Get-Item -LiteralPath $LiteralPath -Force).Attributes -ne $originalAttributes) { throw "Atomic rollback attributes verification failed for $LiteralPath" }
                if (-not $isWindowsHost -and (Get-UnixFileModeExact -LiteralPath $LiteralPath) -ne $originalMode) { throw "Atomic rollback mode verification failed for $LiteralPath" }
                if ($isWindowsHost) {
                    $restoredStream = $null
                    try {
                        $restoredStream = Open-WindowsFileSecurityStream -LiteralPath $LiteralPath
                        if (@(Get-OwnerGroupDaclDifferences -Expected $originalAcl -Actual (Get-FileStreamAcl -Stream $restoredStream)).Count -ne 0) { throw "Atomic rollback ACL verification failed for $LiteralPath" }
                    }
                    finally { if ($null -ne $restoredStream) { $restoredStream.Dispose() } }
                }
                if (Test-Path -LiteralPath $rollback -PathType Leaf) { Remove-Item -LiteralPath $rollback -Force }
            }
            catch { throw "Atomic replacement failed and rollback could not be verified for ${LiteralPath}: $($_.Exception.Message)" }
        }
        throw $replacementError
    }
    finally {
        if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force }
    }
    if (Test-Path -LiteralPath $backup -PathType Leaf) { Remove-Item -LiteralPath $backup -Force }
}

function Get-TomlBasicKey {
    param([string]$Raw)
    $value = New-Object System.Text.StringBuilder
    $index = 0
    while ($index -lt $Raw.Length) {
        $character = $Raw[$index]
        if ($character -ne '\\') { [void]$value.Append($character); $index++; continue }
        $index++
        if ($index -ge $Raw.Length) { throw 'Ambiguous TOML basic key escape; preserved unchanged.' }
        $escape = $Raw[$index]
        $index++
        switch ($escape) {
            'b' { [void]$value.Append([char]8); continue }
            't' { [void]$value.Append("`t"); continue }
            'n' { [void]$value.Append("`n"); continue }
            'f' { [void]$value.Append([char]12); continue }
            'r' { [void]$value.Append("`r"); continue }
            '"' { [void]$value.Append('"'); continue }
            '\\' { [void]$value.Append('\\'); continue }
            'u' { $width = 4; break }
            'U' { $width = 8; break }
            default { throw 'Ambiguous TOML basic key escape; preserved unchanged.' }
        }
        $digits = $Raw.Substring($index, [Math]::Min($width, $Raw.Length - $index))
        if ($digits.Length -ne $width -or $digits -notmatch ('^[0-9A-Fa-f]{' + $width + '}$')) { throw 'Ambiguous TOML basic key escape; preserved unchanged.' }
        [void]$value.Append([char]::ConvertFromUtf32([Convert]::ToInt32($digits, 16)))
        $index += $width
    }
    $value.ToString()
}

function Get-TomlTablePath {
    param([string]$Body)
    $index = 0
    $segments = New-Object 'System.Collections.Generic.List[string]'
    while ($true) {
        while ($index -lt $Body.Length -and [char]::IsWhiteSpace($Body[$index])) { $index++ }
        if ($index -ge $Body.Length) { throw 'Ambiguous TOML table identity; preserved unchanged.' }
        if ($Body[$index] -eq '"') {
            $index++
            $start = $index
            $escaped = $false
            while ($index -lt $Body.Length) {
                $character = $Body[$index]
                if ($character -eq '"' -and -not $escaped) { break }
                if ($character -eq '\\' -and -not $escaped) { $escaped = $true } else { $escaped = $false }
                $index++
            }
            if ($index -ge $Body.Length) { throw 'Ambiguous TOML table identity; preserved unchanged.' }
            [void]$segments.Add((Get-TomlBasicKey $Body.Substring($start, $index - $start)))
            $index++
        }
        elseif ($Body[$index] -eq "'") {
            $index++
            $end = $Body.IndexOf("'", $index)
            if ($end -lt 0) { throw 'Ambiguous TOML table identity; preserved unchanged.' }
            [void]$segments.Add($Body.Substring($index, $end - $index))
            $index = $end + 1
        }
        else {
            $match = [regex]::Match($Body.Substring($index), '^[A-Za-z0-9_-]+')
            if (-not $match.Success) { throw 'Ambiguous TOML table identity; preserved unchanged.' }
            [void]$segments.Add($match.Value)
            $index += $match.Length
        }
        while ($index -lt $Body.Length -and [char]::IsWhiteSpace($Body[$index])) { $index++ }
        if ($index -eq $Body.Length) { return [string]::Join('.', [string[]]$segments.ToArray()) }
        if ($Body[$index] -ne '.') { throw 'Ambiguous TOML table identity; preserved unchanged.' }
        $index++
    }
}

function Get-TomlLineState {
    param([string]$Line, [string]$Active)
    $code = New-Object System.Text.StringBuilder
    $index = 0
    $state = $Active
    $quote = $null
    $escaped = $false
    while ($index -lt $Line.Length) {
        if (-not [string]::IsNullOrEmpty($state)) {
            $delimiter = if ($state -eq 'basic') { '"""' } else { "'''" }
            if ($index + 2 -lt $Line.Length -and $Line.Substring($index, 3) -eq $delimiter) {
                if ($state -eq 'basic' -and $index -gt 0 -and $Line[$index - 1] -eq '\\') { $index++; continue }
                $state = $null; $index += 3; continue
            }
            $index++; continue
        }
        if (-not [string]::IsNullOrEmpty($quote)) {
            $character = $Line[$index]
            [void]$code.Append($character)
            if ($quote -eq 'basic' -and $character -eq '\\' -and -not $escaped) { $escaped = $true }
            elseif ((($quote -eq 'basic' -and $character -eq '"') -or ($quote -eq 'literal' -and $character -eq "'")) -and -not $escaped) { $quote = $null }
            else { $escaped = $false }
            $index++; continue
        }
        if ($Line[$index] -eq '#') { break }
        if ($index + 2 -lt $Line.Length -and $Line.Substring($index, 3) -eq '"""') { $state = 'basic'; $index += 3; continue }
        if ($index + 2 -lt $Line.Length -and $Line.Substring($index, 3) -eq "'''") { $state = 'literal'; $index += 3; continue }
        if ($Line[$index] -eq '"') { $quote = 'basic' }
        elseif ($Line[$index] -eq "'") { $quote = 'literal' }
        [void]$code.Append($Line[$index]); $index++
    }
    if (-not [string]::IsNullOrEmpty($quote)) { throw 'Ambiguous TOML string syntax; preserved unchanged.' }
    [PSCustomObject]@{ Code = $code.ToString(); Active = $state }
}

function Get-TomlTableName {
    param([string]$Code)
    $Code = $Code.TrimStart([char[]]@([char]0xFEFF))
    $match = [regex]::Match($Code, '^\s*(\[\[?|\[)(.*?)(\]\]|\])\s*$')
    if (-not $match.Success -or (($match.Groups[1].Value -eq '[[') -ne ($match.Groups[3].Value -eq ']]'))) { return $null }
    Get-TomlTablePath $match.Groups[2].Value
}

function Get-CodexMcpNames {
    param([string]$Text, [string]$LiteralPath)
    $codex = Get-Command codex -ErrorAction SilentlyContinue
    if ($null -eq $codex) { throw "Codex CLI semantic validation is unavailable for $LiteralPath; preserved unchanged." }
    $validationRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('assistant-framework-toml-' + [Guid]::NewGuid().ToString('N'))
    $validationHome = Join-Path $validationRoot 'home'
    $outputFile = $null
    $isolatedEnvironment = @('CODEX_HOME', 'HOME', 'USERPROFILE', 'NPM_CONFIG_CACHE', 'XDG_CACHE_HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP')
    $savedEnvironment = @{}
    try {
        [System.IO.Directory]::CreateDirectory($validationHome) | Out-Null
        # Older installer output may contain a UTF-8 signature at the start of
        # every preserved line. It is retained in the edit plan, but is not a
        # TOML token passed to the authoritative validator.
        $validatorText = [regex]::Replace($Text, '(?m)^' + [char]0xFEFF, '')
        [System.IO.File]::WriteAllBytes((Join-Path $validationHome 'config.toml'), $utf8NoBom.GetBytes($validatorText))
        $outputFile = Join-Path $validationRoot 'mcp-list.json'
        foreach ($name in $isolatedEnvironment) {
            $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, [EnvironmentVariableTarget]::Process)
            [Environment]::SetEnvironmentVariable($name, $validationHome, [EnvironmentVariableTarget]::Process)
        }
        $oldTerm = [Environment]::GetEnvironmentVariable('TERM', [EnvironmentVariableTarget]::Process)
        try {
            [Environment]::SetEnvironmentVariable('TERM', 'xterm-256color', [EnvironmentVariableTarget]::Process)
            & $codex.Source mcp list --json *> $outputFile
            if ($LASTEXITCODE -ne 0) { throw "Codex CLI semantic validation rejected $LiteralPath; preserved unchanged." }
            $output = [System.IO.File]::ReadAllText($outputFile)
        }
        finally {
            foreach ($name in $isolatedEnvironment) {
                [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], [EnvironmentVariableTarget]::Process)
            }
            [Environment]::SetEnvironmentVariable('TERM', $oldTerm, [EnvironmentVariableTarget]::Process)
        }
        try {
            Assert-JsonTextPropertyIdentitySafe -Text $output
            $outputIndex = 0
            $outputIndexRef = [ref]$outputIndex
            $root = Read-JsonLexicalValue -Text $output -Index $outputIndexRef -Depth 0
            Skip-JsonIdentityWhitespace -Text $output -Index $outputIndexRef
            if ($root.Kind -ne 'array' -or $outputIndex -ne $output.Length) { throw 'Unexpected MCP list JSON root.' }
            if ($output.Substring($root.Start, $root.End - $root.Start) -ceq '[]') {
                $payload = @()
            }
            else {
                $parsedPayload = $output | ConvertFrom-Json -ErrorAction Stop
                $payload = @($parsedPayload)
            }
        }
        catch { throw (New-Object System.IO.InvalidDataException "Invalid Codex CLI JSON output for $LiteralPath; preserved unchanged.") }
        $names = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        $foldedNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($item in $payload) {
            if ($null -eq $item) { throw (New-Object System.IO.InvalidDataException "Invalid Codex CLI JSON output for $LiteralPath; preserved unchanged.") }
            $properties = @($item.PSObject.Properties | Where-Object { [string]::Equals($_.Name, 'name', [System.StringComparison]::Ordinal) })
            if ($properties.Count -ne 1 -or $properties[0].Value -isnot [string]) {
                throw (New-Object System.IO.InvalidDataException "Invalid Codex CLI MCP identity for $LiteralPath; preserved unchanged.")
            }
            $name = [string]$properties[0].Value
            if ([string]::IsNullOrEmpty($name) -or $name.Trim() -cne $name -or @($name.ToCharArray() | Where-Object { [int][char]$_ -lt 0x20 -or [int][char]$_ -eq 0x7F }).Count -ne 0) {
                throw (New-Object System.IO.InvalidDataException "Invalid Codex CLI MCP identity for $LiteralPath; preserved unchanged.")
            }
            if (-not $names.Add($name) -or -not $foldedNames.Add($name)) { throw (New-Object System.IO.InvalidDataException "Ambiguous Codex CLI MCP identity for $LiteralPath; preserved unchanged.") }
        }
        return ,$names
    }
    finally {
        if (Test-Path -LiteralPath $validationRoot) { Remove-Item -LiteralPath $validationRoot -Recurse -Force }
    }
}

function Get-TextLineTokens {
    param([string]$Text)
    @([regex]::Matches($Text, '[^\r\n]*(?:\r\n|\n|\r|$)') | Where-Object { $_.Length -gt 0 })
}

function Get-TomlHeaders {
    param([string]$Text, [string]$LiteralPath)
    $headers = New-Object 'System.Collections.Generic.List[object]'
    $active = $null
    foreach ($lineMatch in Get-TextLineTokens $Text) {
        $line = $lineMatch.Value.TrimEnd("`r", "`n")
        $state = Get-TomlLineState -Line $line -Active $active
        if ([string]::IsNullOrEmpty($active)) {
            $table = Get-TomlTableName -Code $state.Code
            if ($null -ne $table) {
                [void]$headers.Add([PSCustomObject]@{ Name = $table; Start = $lineMatch.Index })
            }
        }
        $active = $state.Active
    }
    if (-not [string]::IsNullOrEmpty($active)) { throw "Ambiguous TOML multiline string in $LiteralPath; preserved unchanged." }
    return $headers
}

function Assert-TomlSourceLexicallyBalanced {
    param([string]$Text, [string]$LiteralPath)
    $arrayDepth = 0
    $inlineDepth = 0
    $active = $null
    foreach ($lineMatch in [regex]::Matches($Text, '(?m)^.*(?:\r\n|\n|\r|$)')) {
        if ($lineMatch.Length -eq 0) { continue }
        $line = $lineMatch.Value.TrimEnd("`r", "`n")
        $state = Get-TomlLineState -Line $line -Active $active
        if ([string]::IsNullOrEmpty($active) -and $null -ne (Get-TomlTableName -Code $state.Code)) {
            $active = $state.Active
            continue
        }
        $code = $state.Code
        $inBasic = $false
        $inLiteral = $false
        for ($index = 0; $index -lt $code.Length; $index++) {
            if ($inBasic) {
                if ($code[$index] -eq '\\') { $index++; continue }
                if ($code[$index] -eq '"') { $inBasic = $false }
                continue
            }
            if ($inLiteral) {
                if ($code[$index] -eq "'") { $inLiteral = $false }
                continue
            }
            if ($code[$index] -eq '"') { $inBasic = $true; continue }
            if ($code[$index] -eq "'") { $inLiteral = $true; continue }
            if ($code[$index] -eq '[') { $arrayDepth++; continue }
            if ($code[$index] -eq ']') { $arrayDepth--; continue }
            if ($code[$index] -eq '{') { $inlineDepth++; continue }
            if ($code[$index] -eq '}') { $inlineDepth--; continue }
            if ($arrayDepth -lt 0 -or $inlineDepth -lt 0) { throw "Invalid TOML syntax in $LiteralPath; preserved unchanged." }
        }
        if ($inBasic -or $inLiteral) { throw "Invalid TOML syntax in $LiteralPath; preserved unchanged." }
        $active = $state.Active
    }
    if ($arrayDepth -ne 0 -or $inlineDepth -ne 0 -or -not [string]::IsNullOrEmpty($active)) {
        throw "Invalid TOML syntax in $LiteralPath; preserved unchanged."
    }
}

function Get-WithoutMemoryGraphToml {
    param([string]$LiteralPath)
    $document = Read-StrictUtf8Document $LiteralPath
    $text = $document.Text
    $headers = @(Get-TomlHeaders -Text $text -LiteralPath $LiteralPath)
    foreach ($header in $headers) {
        $header | Add-Member -MemberType NoteProperty -Name IsOwned -Value ([string]::Equals($header.Name, 'mcp_servers.memory-graph', [System.StringComparison]::Ordinal) -or $header.Name.StartsWith('mcp_servers.memory-graph.', [System.StringComparison]::Ordinal))
    }
    $hasOwnedSpans = @($headers | Where-Object { $_.IsOwned }).Count -ne 0
    $sourceNames = $null
    $sourceAuthorityError = $null
    try { $sourceNames = Get-CodexMcpNames -Text $text -LiteralPath $LiteralPath }
    catch [System.IO.InvalidDataException] { throw }
    catch { $sourceAuthorityError = $_ }
    if ($null -ne $sourceNames) {
        $sourceHasMemoryGraph = $sourceNames.Contains('memory-graph')
        if ($hasOwnedSpans -and -not $sourceHasMemoryGraph) {
            throw "Ambiguous TOML retirement plan in $LiteralPath; preserved unchanged."
        }
        if (-not $hasOwnedSpans) {
            if ($sourceHasMemoryGraph) { throw "Ambiguous TOML retirement plan in $LiteralPath; preserved unchanged." }
            return [PSCustomObject]@{ Outcome = 'proven_absent' }
        }
    }
    elseif (-not $hasOwnedSpans) {
        throw $sourceAuthorityError
    }
    $candidate = $text
    for ($index = $headers.Count - 1; $index -ge 0; $index--) {
        $header = $headers[$index]
        if (-not $header.IsOwned) { continue }
        $end = if ($index + 1 -lt $headers.Count) { $headers[$index + 1].Start } else { $text.Length }
        $candidate = $candidate.Remove($header.Start, $end - $header.Start)
    }
    try {
        $candidateNames = Get-CodexMcpNames -Text $candidate -LiteralPath $LiteralPath
        if ($candidateNames.Contains('memory-graph')) { throw 'Owned TOML registration remains.' }
        $remaining = @(Get-TomlHeaders -Text $candidate -LiteralPath $LiteralPath | Where-Object { [string]::Equals($_.Name, 'mcp_servers.memory-graph', [System.StringComparison]::Ordinal) -or $_.Name.StartsWith('mcp_servers.memory-graph.', [System.StringComparison]::Ordinal) })
        if ($remaining.Count -ne 0) { throw 'Owned TOML registration remains.' }
    }
    catch { throw "Ambiguous TOML retirement plan in $LiteralPath; preserved unchanged." }
    if ($document.HasBom -and $candidate.StartsWith([string][char]0xFEFF, [System.StringComparison]::Ordinal)) {
        $candidate = $candidate.Substring(1)
    }
    [PSCustomObject]@{ Outcome = 'removed'; Content = $candidate; HasBom = $document.HasBom }
}

function New-JsonOrdinalDictionary {
    New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::Ordinal)
}

function Skip-JsonIdentityWhitespace {
    param([string]$Text, [ref]$Index)
    while ($Index.Value -lt $Text.Length -and ($Text[$Index.Value] -eq ' ' -or $Text[$Index.Value] -eq "`t" -or $Text[$Index.Value] -eq "`r" -or $Text[$Index.Value] -eq "`n")) {
        $Index.Value++
    }
}

function Read-JsonIdentityString {
    param([string]$Text, [ref]$Index, [switch]$Decode)
    if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne '"') {
        throw 'Invalid JSON identity scan: expected a string.'
    }
    $value = New-Object System.Text.StringBuilder
    $Index.Value++
    while ($Index.Value -lt $Text.Length) {
        $character = $Text[$Index.Value]
        $Index.Value++
        if ([int][char]$character -lt 0x20) { throw 'Invalid JSON identity scan: raw control character in string.' }
        if ($character -eq '\') {
            if ($Index.Value -ge $Text.Length) { throw 'Invalid JSON identity scan: incomplete escape.' }
            $escape = $Text[$Index.Value]
            $Index.Value++
            switch ($escape) {
                '"' { if ($Decode) { [void]$value.Append('"') }; continue }
                '\' { if ($Decode) { [void]$value.Append('\') }; continue }
                '/' { if ($Decode) { [void]$value.Append('/') }; continue }
                'b' { if ($Decode) { [void]$value.Append([char]8) }; continue }
                'f' { if ($Decode) { [void]$value.Append([char]12) }; continue }
                'n' { if ($Decode) { [void]$value.Append("`n") }; continue }
                'r' { if ($Decode) { [void]$value.Append("`r") }; continue }
                't' { if ($Decode) { [void]$value.Append("`t") }; continue }
                'u' {
                    if ($Index.Value + 4 -gt $Text.Length) { throw 'Invalid JSON identity scan: incomplete unicode escape.' }
                    $digits = $Text.Substring($Index.Value, 4)
                    if ($digits -notmatch '^[0-9A-Fa-f]{4}$') { throw 'Invalid JSON identity scan: invalid unicode escape.' }
                    $codeUnit = [Convert]::ToInt32($digits, 16)
                    $Index.Value += 4
                    if ($codeUnit -ge 0xD800 -and $codeUnit -le 0xDBFF) {
                        if ($Index.Value + 6 -gt $Text.Length -or $Text[$Index.Value] -ne '\' -or $Text[$Index.Value + 1] -ne 'u') { throw 'Invalid JSON identity scan: unpaired unicode surrogate.' }
                        $lowDigits = $Text.Substring($Index.Value + 2, 4)
                        if ($lowDigits -notmatch '^[0-9A-Fa-f]{4}$') { throw 'Invalid JSON identity scan: invalid unicode escape.' }
                        $low = [Convert]::ToInt32($lowDigits, 16)
                        if ($low -lt 0xDC00 -or $low -gt 0xDFFF) { throw 'Invalid JSON identity scan: unpaired unicode surrogate.' }
                        if ($Decode) { [void]$value.Append([char]::ConvertFromUtf32(0x10000 + (($codeUnit - 0xD800) * 0x400) + ($low - 0xDC00))) }
                        $Index.Value += 6
                        continue
                    }
                    if ($codeUnit -ge 0xDC00 -and $codeUnit -le 0xDFFF) { throw 'Invalid JSON identity scan: unpaired unicode surrogate.' }
                    if ($Decode) { [void]$value.Append([char]$codeUnit) }
                    continue
                }
                default { throw 'Invalid JSON identity scan: invalid string escape.' }
            }
        }
        if ($character -eq '"') {
            if ($Decode) { return (New-Object PSObject -Property @{ Value = $value.ToString() }) }
            return
        }
        if ($Decode) { [void]$value.Append($character) }
    }
    throw 'Invalid JSON identity scan: unterminated string.'
}

function Read-JsonStrictScalar {
    param([string]$Text, [ref]$Index)
    $start = $Index.Value
    while ($Index.Value -lt $Text.Length) {
        $character = $Text[$Index.Value]
        if ($character -eq ',' -or $character -eq '}' -or $character -eq ']' -or $character -eq ' ' -or $character -eq "`t" -or $character -eq "`r" -or $character -eq "`n") { break }
        $Index.Value++
    }
    if ($Index.Value -eq $start) { throw 'Invalid JSON lexical scan: missing scalar.' }
    $token = $Text.Substring($start, $Index.Value - $start)
    if ($token -ne 'true' -and $token -ne 'false' -and $token -ne 'null' -and $token -notmatch '^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$') {
        throw 'Invalid JSON lexical scan: invalid RFC JSON scalar.'
    }
    return [PSCustomObject]@{ Kind = 'scalar'; Start = $start; End = $Index.Value }
}

function Throw-JsonPropertyIdentityError {
    param([string]$PropertyName, [string]$Kind)
    throw "Unsafe JSON property identity: $Kind member '$PropertyName'."
}

function Throw-JsonComplexityError {
    param([string]$Reason)
    throw "Unsafe JSON complexity: $Reason"
}

function Assert-JsonFileResourceBudget {
    param([string]$LiteralPath)
    if ((Get-Item -LiteralPath $LiteralPath -Force).Length -gt $maxJsonInputBytes) {
        Throw-JsonComplexityError -Reason "input exceeds $($maxJsonInputBytes) bytes."
    }
}

function Read-JsonIdentityValue {
    param([string]$Text, [ref]$Index, $Context, [int]$Depth)
    if ($Depth -gt $maxJsonIdentityDepth) {
        Throw-JsonComplexityError -Reason "nesting exceeds $($maxJsonIdentityDepth) levels."
    }
    $Context.ValueCount++
    if ($Context.ValueCount -gt $maxJsonIdentityValues) {
        Throw-JsonComplexityError -Reason "value count exceeds $($maxJsonIdentityValues)."
    }
    Skip-JsonIdentityWhitespace -Text $Text -Index $Index
    if ($Index.Value -ge $Text.Length) { throw 'Invalid JSON identity scan: missing value.' }
    $character = $Text[$Index.Value]
    if ($character -eq '{') { Read-JsonIdentityObject -Text $Text -Index $Index -Context $Context -Depth $Depth; return }
    if ($character -eq '[') { Read-JsonIdentityArray -Text $Text -Index $Index -Context $Context -Depth $Depth; return }
    if ($character -eq '"') { [void](Read-JsonIdentityString -Text $Text -Index $Index); return }
    [void](Read-JsonStrictScalar -Text $Text -Index $Index)
}

function Read-JsonIdentityObject {
    param([string]$Text, [ref]$Index, $Context, [int]$Depth)
    $Index.Value++
    $exactKeys = New-JsonOrdinalDictionary
    $foldedKeys = New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
    Skip-JsonIdentityWhitespace -Text $Text -Index $Index
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq '}') { $Index.Value++; return }
    while ($Index.Value -lt $Text.Length) {
        $keyToken = Read-JsonIdentityString -Text $Text -Index $Index -Decode
        $key = $keyToken.Value
        $Context.PropertyCount++
        if ($Context.PropertyCount -gt $maxJsonIdentityProperties) {
            Throw-JsonComplexityError -Reason "property count exceeds $($maxJsonIdentityProperties)."
        }
        if ($exactKeys.ContainsKey($key)) { Throw-JsonPropertyIdentityError -PropertyName $key -Kind 'duplicate' }
        if ($foldedKeys.ContainsKey($key)) { Throw-JsonPropertyIdentityError -PropertyName $key -Kind 'case-colliding' }
        $exactKeys.Add($key, $true)
        $foldedKeys.Add($key, $true)
        Skip-JsonIdentityWhitespace -Text $Text -Index $Index
        if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne ':') { throw 'Invalid JSON identity scan: expected a colon.' }
        $Index.Value++
        Read-JsonIdentityValue -Text $Text -Index $Index -Context $Context -Depth ($Depth + 1)
        Skip-JsonIdentityWhitespace -Text $Text -Index $Index
        if ($Index.Value -ge $Text.Length) { throw 'Invalid JSON identity scan: unterminated object.' }
        if ($Text[$Index.Value] -eq '}') { $Index.Value++; return }
        if ($Text[$Index.Value] -ne ',') { throw 'Invalid JSON identity scan: expected an object separator.' }
        $Index.Value++
        Skip-JsonIdentityWhitespace -Text $Text -Index $Index
    }
    throw 'Invalid JSON identity scan: unterminated object.'
}

function Read-JsonIdentityArray {
    param([string]$Text, [ref]$Index, $Context, [int]$Depth)
    $Index.Value++
    Skip-JsonIdentityWhitespace -Text $Text -Index $Index
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq ']') { $Index.Value++; return }
    while ($Index.Value -lt $Text.Length) {
        Read-JsonIdentityValue -Text $Text -Index $Index -Context $Context -Depth ($Depth + 1)
        Skip-JsonIdentityWhitespace -Text $Text -Index $Index
        if ($Index.Value -ge $Text.Length) { throw 'Invalid JSON identity scan: unterminated array.' }
        if ($Text[$Index.Value] -eq ']') { $Index.Value++; return }
        if ($Text[$Index.Value] -ne ',') { throw 'Invalid JSON identity scan: expected an array separator.' }
        $Index.Value++
        Skip-JsonIdentityWhitespace -Text $Text -Index $Index
    }
    throw 'Invalid JSON identity scan: unterminated array.'
}

function Assert-JsonTextPropertyIdentitySafe {
    param([string]$Text)
    if ($utf8Strict.GetByteCount($Text) -gt $maxJsonInputBytes) {
        Throw-JsonComplexityError -Reason "input exceeds $($maxJsonInputBytes) bytes."
    }
    $index = 0
    $indexRef = [ref]$index
    $context = New-Object PSObject -Property @{ PropertyCount = 0; ValueCount = 0 }
    Read-JsonIdentityValue -Text $Text -Index $indexRef -Context $context -Depth 0
    Skip-JsonIdentityWhitespace -Text $Text -Index $indexRef
    if ($index -ne $Text.Length) { throw 'Invalid JSON identity scan: trailing content.' }
}

function Read-JsonLexicalValue {
    param([string]$Text, [ref]$Index, [int]$Depth)
    if ($Depth -gt $maxJsonIdentityDepth) { Throw-JsonComplexityError -Reason "nesting exceeds $maxJsonIdentityDepth levels." }
    Skip-JsonIdentityWhitespace -Text $Text -Index $Index
    $start = $Index.Value
    if ($start -ge $Text.Length) { throw 'Invalid JSON lexical scan: missing value.' }
    $character = $Text[$start]
    if ($character -eq '{') { return Read-JsonLexicalObject -Text $Text -Index $Index -Depth $Depth }
    if ($character -eq '[') { return Read-JsonLexicalArray -Text $Text -Index $Index -Depth $Depth }
    if ($character -eq '"') {
        [void](Read-JsonIdentityString -Text $Text -Index $Index)
        return [PSCustomObject]@{ Kind = 'scalar'; Start = $start; End = $Index.Value }
    }
    return (Read-JsonStrictScalar -Text $Text -Index $Index)
}

function Read-JsonLexicalObject {
    param([string]$Text, [ref]$Index, [int]$Depth)
    $start = $Index.Value
    $Index.Value++
    Skip-JsonIdentityWhitespace -Text $Text -Index $Index
    $properties = New-Object 'System.Collections.Generic.List[object]'
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq '}') {
        $Index.Value++
        return [PSCustomObject]@{ Kind = 'object'; Start = $start; End = $Index.Value; Properties = $properties }
    }
    while ($Index.Value -lt $Text.Length) {
        $propertyStart = $Index.Value
        $keyToken = Read-JsonIdentityString -Text $Text -Index $Index -Decode
        Skip-JsonIdentityWhitespace -Text $Text -Index $Index
        if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne ':') { throw 'Invalid JSON lexical scan: expected a colon.' }
        $Index.Value++
        $value = Read-JsonLexicalValue -Text $Text -Index $Index -Depth ($Depth + 1)
        Skip-JsonIdentityWhitespace -Text $Text -Index $Index
        $property = [PSCustomObject]@{ Name = $keyToken.Value; Start = $propertyStart; End = $value.End; Comma = -1; Value = $value }
        [void]$properties.Add($property)
        if ($Index.Value -ge $Text.Length) { throw 'Invalid JSON lexical scan: unterminated object.' }
        if ($Text[$Index.Value] -eq '}') {
            $Index.Value++
            return [PSCustomObject]@{ Kind = 'object'; Start = $start; End = $Index.Value; Properties = $properties }
        }
        if ($Text[$Index.Value] -ne ',') { throw 'Invalid JSON lexical scan: expected an object separator.' }
        $property.Comma = $Index.Value
        $Index.Value++
        Skip-JsonIdentityWhitespace -Text $Text -Index $Index
    }
    throw 'Invalid JSON lexical scan: unterminated object.'
}

function Read-JsonLexicalArray {
    param([string]$Text, [ref]$Index, [int]$Depth)
    $start = $Index.Value
    $Index.Value++
    Skip-JsonIdentityWhitespace -Text $Text -Index $Index
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq ']') {
        $Index.Value++
        return [PSCustomObject]@{ Kind = 'array'; Start = $start; End = $Index.Value }
    }
    while ($Index.Value -lt $Text.Length) {
        [void](Read-JsonLexicalValue -Text $Text -Index $Index -Depth ($Depth + 1))
        Skip-JsonIdentityWhitespace -Text $Text -Index $Index
        if ($Index.Value -ge $Text.Length) { throw 'Invalid JSON lexical scan: unterminated array.' }
        if ($Text[$Index.Value] -eq ']') {
            $Index.Value++
            return [PSCustomObject]@{ Kind = 'array'; Start = $start; End = $Index.Value }
        }
        if ($Text[$Index.Value] -ne ',') { throw 'Invalid JSON lexical scan: expected an array separator.' }
        $Index.Value++
        Skip-JsonIdentityWhitespace -Text $Text -Index $Index
    }
    throw 'Invalid JSON lexical scan: unterminated array.'
}

function Get-WithoutMemoryGraphJson {
    param([string]$LiteralPath)
    $utf8Document = Read-StrictUtf8Document $LiteralPath
    $text = $utf8Document.Text
    if ((Get-Item -LiteralPath $LiteralPath -Force).Length -gt $maxJsonInputBytes) { throw "Unsafe JSON complexity in $LiteralPath; preserved unchanged." }
    $rootIndex = 0
    $rootIndexRef = [ref]$rootIndex
    Skip-JsonIdentityWhitespace -Text $text -Index $rootIndexRef
    if ($rootIndex -ge $text.Length -or $text[$rootIndex] -ne '{') { throw "JSON root in $LiteralPath is not an object; preserved unchanged." }
    try { Assert-JsonTextPropertyIdentitySafe -Text $text } catch { throw "Invalid or ambiguous JSON in $LiteralPath; preserved unchanged." }
    $index = 0
    $indexRef = [ref]$index
    try { $document = Read-JsonLexicalValue -Text $text -Index $indexRef -Depth 0 } catch { throw "Invalid JSON in $LiteralPath; preserved unchanged." }
    if ($document.Kind -ne 'object') { throw "JSON root in $LiteralPath is not an object; preserved unchanged." }
    $servers = $null
    foreach ($property in $document.Properties) { if ([string]::Equals($property.Name, 'mcpServers', [System.StringComparison]::Ordinal)) { $servers = $property; break } }
    if ($null -eq $servers) { return [PSCustomObject]@{ Outcome = 'proven_absent' } }
    if ($servers.Value.Kind -ne 'object') { throw "JSON mcpServers in $LiteralPath is not an object; preserved unchanged." }
    $entryIndex = -1
    for ($propertyIndex = 0; $propertyIndex -lt $servers.Value.Properties.Count; $propertyIndex++) {
        if ([string]::Equals($servers.Value.Properties[$propertyIndex].Name, 'memory-graph', [System.StringComparison]::Ordinal)) { $entryIndex = $propertyIndex; break }
    }
    if ($entryIndex -lt 0) { return [PSCustomObject]@{ Outcome = 'proven_absent' } }
    $entry = $servers.Value.Properties[$entryIndex]
    if ($servers.Value.Properties.Count -eq 1) {
        $deleteStart = $entry.Start; $deleteEnd = $entry.End
    }
    elseif ($entryIndex -gt 0) {
        $deleteStart = $servers.Value.Properties[$entryIndex - 1].Comma; $deleteEnd = $entry.End
    }
    else {
        $deleteStart = $entry.Start; $deleteEnd = $entry.Comma + 1
    }
    $candidate = $text.Remove($deleteStart, $deleteEnd - $deleteStart)
    try {
        Assert-JsonTextPropertyIdentitySafe -Text $candidate
        $candidateIndex = 0
        $candidateIndexRef = [ref]$candidateIndex
        $candidateDocument = Read-JsonLexicalValue -Text $candidate -Index $candidateIndexRef -Depth 0
        $candidateServers = @($candidateDocument.Properties | Where-Object { [string]::Equals($_.Name, 'mcpServers', [System.StringComparison]::Ordinal) })
        if ($candidateServers.Count -eq 1 -and $candidateServers[0].Value.Kind -eq 'object' -and @($candidateServers[0].Value.Properties | Where-Object { [string]::Equals($_.Name, 'memory-graph', [System.StringComparison]::Ordinal) }).Count -ne 0) {
            throw 'Owned JSON registration remains.'
        }
    }
    catch { throw "Ambiguous JSON retirement plan in $LiteralPath; preserved unchanged." }
    [PSCustomObject]@{ Outcome = 'removed'; Content = $candidate; HasBom = $utf8Document.HasBom }
}

function Get-JsonPropertyInfoExact {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    foreach ($property in @($Object.PSObject.Properties)) {
        if ([string]::Equals($property.Name, $Name, [System.StringComparison]::Ordinal)) { return $property }
    }
    return $null
}

function Test-MemoryProtocolMarkerState {
    param($Lines, [string]$LiteralPath)
    $markers = New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::Ordinal)
    $markers.Add('<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->', @{ Kind = 'agents'; Action = 'start' })
    $markers.Add('<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->', @{ Kind = 'agents'; Action = 'end' })
    $markers.Add('<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->', @{ Kind = 'memory'; Action = 'start' })
    $markers.Add('<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->', @{ Kind = 'memory'; Action = 'end' })
    $counts = @{ agents = 0; memory = 0 }
    $open = $null
    foreach ($lineMatch in $Lines) {
        $trimmed = $lineMatch.Value.TrimEnd("`r", "`n").Trim()
        if (-not $markers.ContainsKey($trimmed)) { continue }
        $marker = $markers[$trimmed]
        if ([string]::Equals($marker.Action, 'start', [System.StringComparison]::Ordinal)) {
            $counts[$marker.Kind]++
            if ($counts[$marker.Kind] -ne 1 -or $null -ne $open) { throw "Ambiguous, duplicate, or unbalanced Assistant Framework markers in $LiteralPath; preserved unchanged." }
            $open = $marker.Kind
        }
        elseif ($null -eq $open -or -not [string]::Equals($open, $marker.Kind, [System.StringComparison]::Ordinal)) {
            throw "Ambiguous, duplicate, or unbalanced Assistant Framework markers in $LiteralPath; preserved unchanged."
        }
        else {
            $open = $null
        }
    }
    if ($null -ne $open) { throw "Ambiguous, duplicate, or unbalanced Assistant Framework markers in $LiteralPath; preserved unchanged." }
}

function Get-WithoutMemoryProtocol {
    param([string]$LiteralPath)
    $utf8Document = Read-StrictUtf8Document $LiteralPath
    $text = $utf8Document.Text
    $lines = Get-TextLineTokens $text
    Test-MemoryProtocolMarkerState -Lines $lines -LiteralPath $LiteralPath
    $start = @($lines | Where-Object { [string]::Equals($_.Value.Trim(), '<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->', [System.StringComparison]::Ordinal) })
    $end = @($lines | Where-Object { [string]::Equals($_.Value.Trim(), '<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->', [System.StringComparison]::Ordinal) })
    if ($start.Count -eq 0 -and $end.Count -eq 0) { return $null }
    if ($start.Count -ne 1 -or $end.Count -ne 1 -or $start[0].Index -gt $end[0].Index) { throw "Ambiguous Memory Graph instruction markers in $LiteralPath; preserved unchanged." }
    $removeStart = $start[0].Index
    $removeEnd = $end[0].Index + $end[0].Length
    [PSCustomObject]@{ Content = $text.Substring(0, $removeStart) + $text.Substring($removeEnd); HasBom = $utf8Document.HasBom }
}

function Invoke-Retirement {
    $userHome = Assert-SafeHome $env:USERPROFILE
    $script:RetirementUserHome = $userHome
    $agents = if ($Agent) { @($Agent) } else { @('claude', 'codex', 'gemini') }
    $plans = @()
    foreach ($agentName in $agents) {
        $hasConfiguredCodexHome = $agentName -eq 'codex' -and -not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)
        $agentHome = if ($hasConfiguredCodexHome) { Assert-RawConfiguredCodexHome $env:CODEX_HOME } else { Join-Path $userHome ('.' + $agentName) }
        if ((Test-PathEqual $agentHome $userHome) -or (Test-PathEqual $agentHome ([System.IO.Path]::GetPathRoot($agentHome)))) { throw "Agent home cannot be the user home or a filesystem root: $agentHome" }
        if ($hasConfiguredCodexHome) {
            $canonicalHome = Get-CanonicalPath $userHome
            $canonicalAgentHome = Get-CanonicalPath $agentHome
            $canonicalHomePrefix = $canonicalHome.TrimEnd([char[]]'\\/') + [System.IO.Path]::DirectorySeparatorChar
            $logicalHomePrefix = $userHome.TrimEnd([char[]]'\\/') + [System.IO.Path]::DirectorySeparatorChar
            if ([string]::Equals($canonicalAgentHome, $canonicalHome, [System.StringComparison]::OrdinalIgnoreCase) -or
                ($canonicalAgentHome.StartsWith($canonicalHomePrefix, [System.StringComparison]::OrdinalIgnoreCase) -and -not $agentHome.StartsWith($logicalHomePrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
                throw "Refusing CODEX_HOME with ambiguous physical identity: $agentHome"
            }
        }
        Assert-NoReparseTraversal -LiteralPath $agentHome -Purpose "$agentName agent home" | Out-Null
        $skillsRoots = if ($agentName -eq 'codex') {
            @(
                Assert-SafeChild $userHome (Join-Path $userHome '.agents/skills') 'Codex native skills root' $userHome
                Assert-SafeChild $agentHome (Join-Path $agentHome 'skills') 'Codex legacy skills root' $userHome
            )
        }
        else {
            @(Assert-SafeChild $agentHome (Join-Path $agentHome 'skills') 'agent skills root' $userHome)
        }
        $targets = @()
        foreach ($skillsRoot in $skillsRoots) {
            $targets += Assert-SafeChild $skillsRoot (Join-Path $skillsRoot 'assistant-memory') 'retired skill' $userHome
            $targets += Assert-SafeChild $skillsRoot (Join-Path $skillsRoot 'assistant-reflexion') 'retired skill' $userHome
        }
        $targets += Assert-SafeChild $agentHome (Join-Path $agentHome 'tools/memory-graph') 'retired tool' $userHome
        if ($PurgeData) { $targets += Assert-SafeChild $agentHome (Join-Path $agentHome 'memory') 'explicitly purged memory data' $userHome }
        $instruction = Assert-SafeChild $agentHome (Join-Path $agentHome (@{ claude = 'CLAUDE.md'; codex = 'AGENTS.md'; gemini = 'GEMINI.md' }[$agentName])) 'instructions' $userHome
        $configs = @()
        if ($agentName -eq 'codex') { $configs += @{ Path = Assert-SafeChild $agentHome (Join-Path $agentHome 'config.toml') 'Codex configuration' $userHome; Remove = 'toml' } }
        else {
            $configs += @{ Path = Assert-SafeChild $agentHome (Join-Path $agentHome 'settings.json') 'agent settings' $userHome; Remove = 'json' }
            if ($agentName -eq 'claude') { $configs += @{ Path = Assert-SafeChild $userHome (Join-Path $userHome '.claude.json') 'Claude configuration' $userHome; Remove = 'json' } }
        }
        $plans += @{ Agent = $agentName; Targets = $targets; Instruction = $instruction; Configs = $configs }
    }
    $updates = @()
    foreach ($plan in $plans) {
        foreach ($target in $plan.Targets) {
            if (Test-Path -LiteralPath $target) {
                $item = Get-Item -LiteralPath $target -Force
                if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or -not $item.PSIsContainer) { throw "Refusing unsafe retirement target: $target" }
            }
        }
        if ($null -ne (Get-Item -LiteralPath $plan.Instruction -Force -ErrorAction SilentlyContinue)) {
            Assert-RegularFileNoFollow -LiteralPath $plan.Instruction -Purpose 'agent instructions'
            Assert-FileAvailableForExclusiveUpdate -LiteralPath $plan.Instruction -Purpose 'agent instructions'
        }
        foreach ($config in $plan.Configs) {
            if ($null -ne (Get-Item -LiteralPath $config.Path -Force -ErrorAction SilentlyContinue)) {
                Assert-RegularFileNoFollow -LiteralPath $config.Path -Purpose 'agent configuration'
                Assert-FileAvailableForExclusiveUpdate -LiteralPath $config.Path -Purpose 'agent configuration'
            }
        }
        if ($null -ne (Get-Item -LiteralPath $plan.Instruction -Force -ErrorAction SilentlyContinue)) {
            $baseBytes = [System.IO.File]::ReadAllBytes($plan.Instruction)
            $replacement = Get-WithoutMemoryProtocol $plan.Instruction
            if ($null -ne $replacement) { $updates += @{ Path = $plan.Instruction; Content = $replacement.Content; HasBom = $replacement.HasBom; BaseBytes = $baseBytes } }
        }
        foreach ($config in $plan.Configs) {
            if ($null -ne (Get-Item -LiteralPath $config.Path -Force -ErrorAction SilentlyContinue)) {
                $baseBytes = [System.IO.File]::ReadAllBytes($config.Path)
                $replacement = if ($config.Remove -eq 'toml') { Get-WithoutMemoryGraphToml $config.Path } else { Get-WithoutMemoryGraphJson $config.Path }
                if ([string]::Equals($replacement.Outcome, 'removed', [System.StringComparison]::Ordinal)) {
                    $updates += @{ Path = $config.Path; Content = $replacement.Content; HasBom = $replacement.HasBom; BaseBytes = $baseBytes }
                }
                elseif (-not [string]::Equals($replacement.Outcome, 'proven_absent', [System.StringComparison]::Ordinal)) {
                    throw "Ambiguous retirement outcome in $($config.Path); preserved unchanged."
                }
            }
        }
    }
    if ($DryRun) { $plans | ForEach-Object { Write-Host ('[dry-run] Retire Memory Graph artifacts for ' + $_.Agent) }; return }
    foreach ($update in $updates) {
        Assert-RegularFileNoFollow -LiteralPath $update.Path -Purpose 'planned update'
        if (-not (Test-ByteArraysEqual -Expected $update.BaseBytes -Actual ([System.IO.File]::ReadAllBytes($update.Path)))) {
            throw "Planned update source changed before mutation: $($update.Path)"
        }
    }
    foreach ($update in $updates) { Write-AtomicUtf8 $update.Path $update.Content $update.HasBom $update.BaseBytes }
    foreach ($plan in $plans) {
        foreach ($target in $plan.Targets) {
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        }
    }
    Write-Host 'Retired Assistant Framework Memory Graph artifacts.'
}

if ($Help) { Show-Usage; return }
try { Invoke-Retirement } catch { [Console]::Error.WriteLine('Error: ' + $_.Exception.Message); exit 1 }
