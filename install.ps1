#requires -Version 5.1
<#
.SYNOPSIS
Installs Assistant Framework for Claude Code, Codex, or Gemini on Windows.

.DESCRIPTION
Performs a native PowerShell installation without WSL, remote downloads,
execution-policy changes, or symbolic-link creation. Existing user-authored
configuration is preserved while installer-owned sections are refreshed.

.PARAMETER Agent
Target agent: claude, codex, or gemini. Agent names are case-insensitive.

.PARAMETER Skill
Install one root assistant-* skill instead of the complete inventory.

.PARAMETER Plugin
Install an assistant-core, assistant-research, or assistant-dev profile.

.PARAMETER DryRun
Validate and report the planned work without changing the filesystem.

.PARAMETER NoHooks
Deprecated compatibility switch. All installs are hookless.

.EXAMPLE
.\install.ps1 -Agent codex

.EXAMPLE
.\install.ps1 -Agent claude -Skill assistant-workflow

.EXAMPLE
.\install.ps1 -Agent codex -Plugin assistant-dev -DryRun
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Agent,
    [string]$Skill,
    [string]$Plugin,
    [switch]$DryRun,
    [switch]$NoHooks,
    [Alias('h')]
    [switch]$Help
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$script:MaxJsonInputBytes = 4 * 1024 * 1024
$script:MaxJsonIdentityDepth = 64
$script:MaxJsonIdentityProperties = 10000
$script:MaxJsonIdentityValues = 10000
$script:SupportedPluginProfiles = @('assistant-core', 'assistant-research', 'assistant-dev')
$script:LegacyHookEntrypoints = @(
    'session-start.sh',
    'skill-router.sh',
    'learning-signals.sh',
    'workflow-enforcer.sh',
    'workflow-guard.sh',
    'stop-review.sh',
    'harness-gate.sh',
    'subagent-monitor.sh',
    'pre-compress.sh',
    'post-compact.sh',
    'session-end.sh',
    'post-tool-context.sh',
    'tool-failure-advisor.sh',
    'task-completed.sh'
)
$script:LegacyHookHelpers = @(
    'task-journal-resolver.sh',
    'workflow-phase-gates.sh',
    'hook-runtime.sh'
)
$script:LegacyHookModules = @(
    'workflow-phase-gates.d/learning-controller.sh',
    'workflow-phase-gates.d/metrics.sh',
    'workflow-phase-gates.d/qa-controller.sh',
    'workflow-phase-gates.d/review-controller.sh',
    'workflow-phase-gates.d/subagent-evidence.sh',
    'workflow-phase-gates.d/subagent-orchestration.sh',
    'workflow-guard.d/path-policy.sh',
    'workflow-guard.d/shell-write-parser.sh',
    'workflow-guard.d/workflow-state-artifacts.sh'
)

function Show-Usage {
    @'
Usage: .\install.ps1 -Agent <claude|codex|gemini> [options]

Options:
  -Skill <name>             Install one assistant-* skill
  -Plugin <name>            Install assistant-core, assistant-research, or assistant-dev
  -DryRun                   Validate and show work without changing files
  -NoHooks                  Deprecated no-op; installs are hookless
  -Help                     Show this help

The installer mirrors managed skill, tool, and eval-doc directories. Files
added manually inside those managed directories may be removed on reinstall.
'@ | Write-Host
}

function Write-Info {
    param([string]$Message)
    Write-Host ('  ' + $Message)
}

function Write-Ok {
    param([string]$Message)
    Write-Host ('  OK: ' + $Message)
}

function Write-DryRun {
    param([string]$Message)
    Write-Host ('  [dry-run] ' + $Message)
}

function Test-IsWindowsHost {
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function New-OrdinalDictionary {
    return [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
}

function Read-StrictUtf8Text {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $offset = 3
    }
    return $script:Utf8Strict.GetString($bytes, $offset, $bytes.Length - $offset)
}

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    return [System.IO.Path]::GetFullPath($LiteralPath)
}

function Normalize-PathForComparison {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $fullPath = Get-FullPath -LiteralPath $LiteralPath
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    $trimmedPath = $fullPath.TrimEnd([char[]]@('\', '/'))
    $trimmedRoot = $pathRoot.TrimEnd([char[]]@('\', '/'))
    if ([string]::IsNullOrEmpty($trimmedPath) -or
        [string]::Equals($trimmedPath, $trimmedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $pathRoot
    }
    return $trimmedPath
}

function Test-PathEqual {
    param([string]$Left, [string]$Right)
    return [string]::Equals(
        (Normalize-PathForComparison -LiteralPath $Left),
        (Normalize-PathForComparison -LiteralPath $Right),
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Assert-NoReparseTraversal {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Purpose,
        [string]$TraversalRoot
    )

    $fullPath = Get-FullPath -LiteralPath $LiteralPath
    if ([string]::IsNullOrWhiteSpace($TraversalRoot)) {
        $TraversalRoot = [System.IO.Path]::GetDirectoryName($fullPath)
    }
    $stopPath = Normalize-PathForComparison -LiteralPath $TraversalRoot
    $pathForComparison = Normalize-PathForComparison -LiteralPath $fullPath
    $isSame = [string]::Equals($pathForComparison, $stopPath, [System.StringComparison]::OrdinalIgnoreCase)
    $directorySeparator = [string][System.IO.Path]::DirectorySeparatorChar
    $alternateSeparator = [string][System.IO.Path]::AltDirectorySeparatorChar
    $rootWithSeparator = if ($stopPath.EndsWith($directorySeparator) -or
        $stopPath.EndsWith($alternateSeparator)) { $stopPath } else { $stopPath + $directorySeparator }
    if (-not $isSame -and -not $pathForComparison.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing $Purpose outside traversal root '$stopPath': $fullPath"
    }

    $relative = if ($isSame) { '' } else { $pathForComparison.Substring($rootWithSeparator.Length) }
    $current = $stopPath
    $pathsToCheck = New-Object System.Collections.Generic.List[string]
    $pathsToCheck.Add($current)
    foreach ($segment in @($relative -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $current = Join-Path $current $segment
        $pathsToCheck.Add($current)
    }
    foreach ($currentPath in $pathsToCheck) {
        if (Test-Path -LiteralPath $currentPath) {
            $item = Get-Item -LiteralPath $currentPath -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing $Purpose through reparse-point ancestor: $currentPath"
            }
        }
    }
}

function Assert-SafeManagedChild {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [Parameter(Mandatory = $true)][string]$Purpose
    )

    $fullPath = Get-FullPath -LiteralPath $LiteralPath
    $fullRoot = Get-FullPath -LiteralPath $ManagedRoot
    $rootComparison = Normalize-PathForComparison -LiteralPath $fullRoot
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $alternate = [System.IO.Path]::AltDirectorySeparatorChar
    $managedRootFilesystemRoot = [System.IO.Path]::GetPathRoot($fullRoot)
    $rootIsFilesystemRoot = Test-PathEqual -Left $fullRoot -Right $managedRootFilesystemRoot
    if ($rootIsFilesystemRoot) {
        $prefixes = @($fullRoot)
    }
    else {
        $prefixes = @($rootComparison + $separator)
        if ($alternate -ne $separator) {
            $prefixes += ($rootComparison + $alternate)
        }
    }

    $isDescendant = $false
    foreach ($prefix in $prefixes) {
        if ($fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $isDescendant = $true
            break
        }
    }

    if (-not $isDescendant) {
        throw "Refusing $Purpose outside managed root '$rootComparison': $fullPath"
    }

    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    if ((Test-PathEqual -Left $fullPath -Right $fullRoot) -or
        (-not [string]::IsNullOrEmpty($pathRoot) -and (Test-PathEqual -Left $fullPath -Right $pathRoot)) -or
        (Test-PathEqual -Left $fullPath -Right $script:UserHome)) {
        throw "Refusing unsafe $Purpose target: $fullPath"
    }

    Assert-NoReparseTraversal -LiteralPath $fullPath -Purpose $Purpose -TraversalRoot $fullRoot

    return $fullPath
}

function Assert-NoSourceTargetOverlap {
    param([string]$Source, [string]$Target, [string]$Purpose)
    $sourceFull = (Get-FullPath -LiteralPath $Source).TrimEnd([char[]]@('\', '/'))
    $targetFull = (Get-FullPath -LiteralPath $Target).TrimEnd([char[]]@('\', '/'))
    $separator = [System.IO.Path]::DirectorySeparatorChar
    if ([string]::Equals($sourceFull, $targetFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $sourceFull.StartsWith($targetFull + $separator, [System.StringComparison]::OrdinalIgnoreCase) -or
        $targetFull.StartsWith($sourceFull + $separator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing overlapping source and target for ${Purpose}: '$sourceFull' and '$targetFull'"
    }
}

function Assert-FileAvailableForExclusiveUpdate {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Purpose
    )
    $probe = $null
    try {
        $probe = [System.IO.File]::Open(
            $LiteralPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
    }
    catch {
        throw "Locked-file preflight failed for $Purpose at '$LiteralPath'. Close Codex App and rerun the installer. No installation changes were made. Cause: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $probe) { $probe.Dispose() }
    }
}

function Assert-SafeUserFile {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [Parameter(Mandatory = $true)][string]$Purpose,
        [switch]$RequireExclusiveUpdatePreflight
    )
    $safeFile = Assert-SafeManagedChild -LiteralPath $LiteralPath -ManagedRoot $ManagedRoot -Purpose $Purpose
    if (Test-Path -LiteralPath $safeFile) {
        $item = Get-Item -LiteralPath $safeFile -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.PSIsContainer) {
            throw "Refusing unsafe $Purpose file: $safeFile"
        }
        if ($RequireExclusiveUpdatePreflight) {
            Assert-FileAvailableForExclusiveUpdate -LiteralPath $safeFile -Purpose $Purpose
        }
        [void](Read-StrictUtf8Text -LiteralPath $safeFile)
    }
    return $safeFile
}

function Assert-SafeConfiguredHomePathText {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [string]$VariableName = 'Configured home'
    )
    if ($LiteralPath -match '^(?:\\\\[?.]\\|//[?.]/|\\\?\?\\)') {
        throw "$VariableName cannot use a Windows device namespace."
    }
    if (-not [System.IO.Path]::IsPathRooted($LiteralPath)) {
        throw "$VariableName must be a fully qualified path."
    }
    if (Test-IsWindowsHost) {
        $isDriveAbsolute = $LiteralPath -match '^[A-Za-z]:[\\/]'
        $isUncAbsolute = $LiteralPath -match '^(?:\\\\[^\\/?]+\\[^\\/?]+(?:\\|$)|//[^/?]+/[^/?]+(?:/|$))'
        if (-not $isDriveAbsolute -and -not $isUncAbsolute) {
            # Path.IsPathRooted accepts drive-relative forms such as C:folder
            # and current-drive-relative forms such as \folder on Windows.
            throw "$VariableName must be a fully qualified path."
        }
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    Assert-NoReparseTraversal -LiteralPath $LiteralPath -Purpose 'directory creation'
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Container)) {
        [void][System.IO.Directory]::CreateDirectory((Get-FullPath -LiteralPath $LiteralPath))
    }
    Assert-NoReparseTraversal -LiteralPath $LiteralPath -Purpose 'directory creation'
}

function Get-OwnerGroupDaclSections {
    return [System.Security.AccessControl.AccessControlSections](
        [System.Security.AccessControl.AccessControlSections]::Owner -bor
        [System.Security.AccessControl.AccessControlSections]::Group -bor
        [System.Security.AccessControl.AccessControlSections]::Access
    )
}

function Get-OwnerGroupDaclSddl {
    param([Parameter(Mandatory = $true)]$Acl)
    return $Acl.GetSecurityDescriptorSddlForm((Get-OwnerGroupDaclSections))
}

function Get-DaclBinaryFingerprint {
    param([Parameter(Mandatory = $true)][System.Security.AccessControl.RawAcl]$Dacl)
    $binary = [byte[]]::new($Dacl.BinaryLength)
    $Dacl.GetBinaryForm($binary, 0)
    return [Convert]::ToBase64String($binary)
}

function Get-AceBinaryFingerprint {
    param(
        [Parameter(Mandatory = $true)][System.Security.AccessControl.GenericAce]$Ace,
        [switch]$IgnoreInheritedFlag
    )
    $binary = [byte[]]::new($Ace.BinaryLength)
    $Ace.GetBinaryForm($binary, 0)
    if ($IgnoreInheritedFlag -and $binary.Length -gt 1) {
        $binary[1] = $binary[1] -band 0xEF
    }
    return [Convert]::ToBase64String($binary)
}

function Get-DaclMismatchCategory {
    param(
        [Parameter(Mandatory = $true)][System.Security.AccessControl.RawAcl]$Expected,
        [Parameter(Mandatory = $true)][System.Security.AccessControl.RawAcl]$Actual
    )
    if ($Expected.Count -ne $Actual.Count) {
        return 'dacl_count'
    }

    $expectedSequence = @()
    $actualSequence = @()
    $expectedWithoutInherited = @()
    $actualWithoutInherited = @()
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        $expectedSequence += Get-AceBinaryFingerprint -Ace $Expected[$index]
        $actualSequence += Get-AceBinaryFingerprint -Ace $Actual[$index]
        $expectedWithoutInherited += Get-AceBinaryFingerprint -Ace $Expected[$index] -IgnoreInheritedFlag
        $actualWithoutInherited += Get-AceBinaryFingerprint -Ace $Actual[$index] -IgnoreInheritedFlag
    }

    $expectedOrdered = $expectedSequence -join '|'
    $actualOrdered = $actualSequence -join '|'
    if ($expectedOrdered -ceq $actualOrdered) {
        return 'dacl_header'
    }

    $expectedSorted = @($expectedSequence | Sort-Object)
    $actualSorted = @($actualSequence | Sort-Object)
    if (($expectedSorted -join '|') -ceq ($actualSorted -join '|')) {
        return 'dacl_order'
    }

    $expectedWithoutInheritedOrdered = $expectedWithoutInherited -join '|'
    $actualWithoutInheritedOrdered = $actualWithoutInherited -join '|'
    if ($expectedWithoutInheritedOrdered -ceq $actualWithoutInheritedOrdered) {
        return 'dacl_inherited_flag'
    }

    $expectedWithoutInheritedSorted = @($expectedWithoutInherited | Sort-Object)
    $actualWithoutInheritedSorted = @($actualWithoutInherited | Sort-Object)
    if (($expectedWithoutInheritedSorted -join '|') -ceq ($actualWithoutInheritedSorted -join '|')) {
        return 'dacl_inherited_flag_order'
    }
    return 'dacl_content'
}

function Get-OwnerGroupDaclDifferences {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual
    )

    $differences = New-Object System.Collections.Generic.List[string]
    $expectedBinary = $Expected.GetSecurityDescriptorBinaryForm()
    $actualBinary = $Actual.GetSecurityDescriptorBinaryForm()
    $expectedRaw = [System.Security.AccessControl.RawSecurityDescriptor]::new($expectedBinary, 0)
    $actualRaw = [System.Security.AccessControl.RawSecurityDescriptor]::new($actualBinary, 0)

    $expectedOwner = if ($null -eq $expectedRaw.Owner) { $null } else { $expectedRaw.Owner.Value }
    $actualOwner = if ($null -eq $actualRaw.Owner) { $null } else { $actualRaw.Owner.Value }
    if (-not [string]::Equals($expectedOwner, $actualOwner, [System.StringComparison]::Ordinal)) {
        $differences.Add('owner')
    }
    $expectedGroup = if ($null -eq $expectedRaw.Group) { $null } else { $expectedRaw.Group.Value }
    $actualGroup = if ($null -eq $actualRaw.Group) { $null } else { $actualRaw.Group.Value }
    if (-not [string]::Equals($expectedGroup, $actualGroup, [System.StringComparison]::Ordinal)) {
        $differences.Add('group')
    }
    if ($Expected.AreAccessRulesProtected -ne $Actual.AreAccessRulesProtected) {
        $differences.Add('protection')
    }
    if (-not $Expected.AreAccessRulesCanonical -or -not $Actual.AreAccessRulesCanonical) {
        $differences.Add('noncanonical')
    }

    if ($null -eq $expectedRaw.DiscretionaryAcl -or $null -eq $actualRaw.DiscretionaryAcl) {
        $differences.Add('null_dacl')
    }
    else {
        $expectedDacl = Get-DaclBinaryFingerprint -Dacl $expectedRaw.DiscretionaryAcl
        $actualDacl = Get-DaclBinaryFingerprint -Dacl $actualRaw.DiscretionaryAcl
        if ($expectedDacl -cne $actualDacl) {
            $differences.Add('dacl')
            $differences.Add((Get-DaclMismatchCategory -Expected $expectedRaw.DiscretionaryAcl -Actual $actualRaw.DiscretionaryAcl))
        }
    }
    return $differences.ToArray()
}

function New-PrivateFileSecurity {
    $privateAcl = New-Object -TypeName System.Security.AccessControl.FileSecurity
    $privateAcl.SetAccessRuleProtection($true, $false)
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $fullControl = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
        $currentUser,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    [void]$privateAcl.AddAccessRule($fullControl)
    return $privateAcl
}

function Test-PrivateFileSecurity {
    param(
        [Parameter(Mandatory = $true)]$Acl,
        [Parameter(Mandatory = $true)][System.Security.Principal.SecurityIdentifier]$CurrentUser
    )
    if (-not $Acl.AreAccessRulesProtected) { return $false }
    $rules = @($Acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    if ($rules.Count -ne 1) { return $false }
    $rule = $rules[0]
    return $rule.IdentityReference -eq $CurrentUser -and
        $rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and
        $rule.FileSystemRights -eq [System.Security.AccessControl.FileSystemRights]::FullControl -and
        $rule.InheritanceFlags -eq [System.Security.AccessControl.InheritanceFlags]::None -and
        $rule.PropagationFlags -eq [System.Security.AccessControl.PropagationFlags]::None -and
        -not $rule.IsInherited
}

function Get-FileSystemAclExtensionsType {
    $extensionType = [Type]::GetType(
        'System.IO.FileSystemAclExtensions, System.IO.FileSystem.AccessControl',
        $false
    )
    if ($null -eq $extensionType) {
        try {
            $assembly = [Reflection.Assembly]::Load('System.IO.FileSystem.AccessControl')
            $extensionType = $assembly.GetType('System.IO.FileSystemAclExtensions', $false)
        }
        catch {
            $extensionType = $null
        }
    }
    return $extensionType
}

function Get-FileStreamAcl {
    param([Parameter(Mandatory = $true)][System.IO.FileStream]$Stream)

    $instanceMethod = $Stream.GetType().GetMethod('GetAccessControl', [Type[]]@())
    if ($null -ne $instanceMethod) {
        return $instanceMethod.Invoke($Stream, @())
    }
    $extensionType = Get-FileSystemAclExtensionsType
    if ($null -eq $extensionType) {
        throw 'File-system ACL APIs are unavailable on this Windows runtime.'
    }
    $extensionMethod = $extensionType.GetMethod('GetAccessControl', [Type[]]@([System.IO.FileStream]))
    if ($null -eq $extensionMethod) {
        throw 'Compatible FileSystemAclExtensions.GetAccessControl API was not found.'
    }
    return $extensionMethod.Invoke($null, [object[]]@($Stream))
}

function Set-FileStreamAcl {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileStream]$Stream,
        [Parameter(Mandatory = $true)][System.Security.AccessControl.FileSecurity]$Acl
    )

    $instanceMethod = $Stream.GetType().GetMethod(
        'SetAccessControl',
        [Type[]]@([System.Security.AccessControl.FileSecurity])
    )
    if ($null -ne $instanceMethod) {
        [void]$instanceMethod.Invoke($Stream, [object[]]@($Acl))
        return
    }
    $extensionType = Get-FileSystemAclExtensionsType
    if ($null -eq $extensionType) {
        throw 'File-system ACL APIs are unavailable on this Windows runtime.'
    }
    $extensionMethod = $extensionType.GetMethod(
        'SetAccessControl',
        [Type[]]@([System.IO.FileStream], [System.Security.AccessControl.FileSecurity])
    )
    if ($null -eq $extensionMethod) {
        throw 'Compatible FileSystemAclExtensions.SetAccessControl API was not found.'
    }
    [void]$extensionMethod.Invoke($null, [object[]]@($Stream, $Acl))
}

function New-BinaryDaclFileSecurity {
    param([Parameter(Mandatory = $true)][System.Security.AccessControl.FileSecurity]$ReferenceAcl)

    $binary = $ReferenceAcl.GetSecurityDescriptorBinaryForm()
    $rawDescriptor = [System.Security.AccessControl.RawSecurityDescriptor]::new($binary, 0)
    if ($null -eq $rawDescriptor.DiscretionaryAcl) {
        throw 'Cannot safely preserve a null DACL during atomic replacement.'
    }
    $daclOnly = New-Object -TypeName System.Security.AccessControl.FileSecurity
    $daclOnly.SetSecurityDescriptorBinaryForm(
        $binary,
        [System.Security.AccessControl.AccessControlSections]::Access
    )
    return $daclOnly
}

function Initialize-WindowsFileIdentityInterop {
    if ($null -ne ('AssistantFrameworkInstaller.NativeFileIdentity' -as [Type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace AssistantFrameworkInstaller
{
    public static class NativeFileIdentity
    {
        private const uint GenericRead = 0x80000000u;
        private const uint GenericWrite = 0x40000000u;
        private const uint ReadControl = 0x00020000u;
        private const uint WriteDac = 0x00040000u;
        private const uint CreateNew = 1u;
        private const uint OpenExisting = 3u;
        private const uint FileAttributeNormal = 0x00000080u;

        [StructLayout(LayoutKind.Sequential)]
        private struct ByHandleFileInformation
        {
            public uint FileAttributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(
            SafeFileHandle file,
            out ByHandleFileInformation information);

        public static SafeFileHandle CreateNewReadWrite(string path)
        {
            return OpenChecked(path, GenericRead | GenericWrite | ReadControl, CreateNew);
        }

        public static SafeFileHandle OpenReadExclusive(string path)
        {
            return OpenChecked(path, GenericRead | ReadControl, OpenExisting);
        }

        public static SafeFileHandle OpenReadSecurityExclusive(string path)
        {
            return OpenChecked(path, GenericRead | ReadControl, OpenExisting);
        }

        public static SafeFileHandle OpenReadWriteDaclExclusive(string path)
        {
            return OpenChecked(path, GenericRead | ReadControl | WriteDac, OpenExisting);
        }

        private static SafeFileHandle OpenChecked(string path, uint access, uint disposition)
        {
            SafeFileHandle handle = CreateFileW(
                path,
                access,
                0u,
                IntPtr.Zero,
                disposition,
                FileAttributeNormal,
                IntPtr.Zero);
            if (handle.IsInvalid)
            {
                int error = Marshal.GetLastWin32Error();
                handle.Dispose();
                throw new Win32Exception(error);
            }
            return handle;
        }

        public static string GetIdentity(SafeFileHandle handle)
        {
            ByHandleFileInformation information;
            if (!GetFileInformationByHandle(handle, out information))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            return String.Format(
                "{0:X8}:{1:X8}:{2:X8}",
                information.VolumeSerialNumber,
                information.FileIndexHigh,
                information.FileIndexLow);
        }

        public static uint GetLinkCount(SafeFileHandle handle)
        {
            ByHandleFileInformation information;
            if (!GetFileInformationByHandle(handle, out information))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            return information.NumberOfLinks;
        }
    }
}
'@
}

function New-FileStreamFromSafeFileHandle {
    param(
        [Parameter(Mandatory = $true)]$SafeFileHandle,
        [Parameter(Mandatory = $true)][System.IO.FileAccess]$FileAccess
    )
    $constructor = [System.IO.FileStream].GetConstructor([Type[]]@(
        [Microsoft.Win32.SafeHandles.SafeFileHandle],
        [System.IO.FileAccess]
    ))
    if ($null -eq $constructor) {
        $SafeFileHandle.Dispose()
        throw 'Compatible SafeFileHandle FileStream constructor was not found.'
    }
    try {
        return $constructor.Invoke([object[]]@($SafeFileHandle, $FileAccess))
    }
    catch {
        $SafeFileHandle.Dispose()
        throw
    }
}

function New-WindowsDefaultCreateNewStream {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    Initialize-WindowsFileIdentityInterop
    $handle = [AssistantFrameworkInstaller.NativeFileIdentity]::CreateNewReadWrite($LiteralPath)
    return New-FileStreamFromSafeFileHandle -SafeFileHandle $handle -FileAccess ([System.IO.FileAccess]::ReadWrite)
}

function Open-WindowsFileReadStream {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    Initialize-WindowsFileIdentityInterop
    $handle = [AssistantFrameworkInstaller.NativeFileIdentity]::OpenReadExclusive($LiteralPath)
    return New-FileStreamFromSafeFileHandle -SafeFileHandle $handle -FileAccess ([System.IO.FileAccess]::Read)
}

function Open-WindowsFileSecurityStream {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    Initialize-WindowsFileIdentityInterop
    $handle = [AssistantFrameworkInstaller.NativeFileIdentity]::OpenReadSecurityExclusive($LiteralPath)
    return New-FileStreamFromSafeFileHandle -SafeFileHandle $handle -FileAccess ([System.IO.FileAccess]::Read)
}

function Open-WindowsFileDaclWriteStream {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    Initialize-WindowsFileIdentityInterop
    $handle = [AssistantFrameworkInstaller.NativeFileIdentity]::OpenReadWriteDaclExclusive($LiteralPath)
    return New-FileStreamFromSafeFileHandle -SafeFileHandle $handle -FileAccess ([System.IO.FileAccess]::Read)
}

function Get-WindowsFileIdentity {
    param([Parameter(Mandatory = $true)]$SafeFileHandle)
    Initialize-WindowsFileIdentityInterop
    return [AssistantFrameworkInstaller.NativeFileIdentity]::GetIdentity($SafeFileHandle)
}

function Get-WindowsFileLinkCount {
    param([Parameter(Mandatory = $true)]$SafeFileHandle)
    Initialize-WindowsFileIdentityInterop
    return [AssistantFrameworkInstaller.NativeFileIdentity]::GetLinkCount($SafeFileHandle)
}

function Test-WindowsFileIdentityEqual {
    param(
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Actual
    )
    return [string]::Equals($Expected, $Actual, [System.StringComparison]::Ordinal)
}

function Read-FileStreamBytes {
    param([Parameter(Mandatory = $true)][System.IO.FileStream]$Stream)
    $memory = New-Object System.IO.MemoryStream
    try {
        $Stream.CopyTo($memory)
        return ,$memory.ToArray()
    }
    finally {
        $memory.Dispose()
    }
}

function New-SecuredCreateNewStream {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][System.Security.AccessControl.FileSecurity]$FileSecurity
    )

    $rights = [System.Security.AccessControl.FileSystemRights](
        [System.Security.AccessControl.FileSystemRights]::ReadData -bor
        [System.Security.AccessControl.FileSystemRights]::WriteData -bor
        [System.Security.AccessControl.FileSystemRights]::ReadPermissions -bor
        [System.Security.AccessControl.FileSystemRights]::Synchronize
    )
    $constructorTypes = [Type[]]@(
        [string],
        [System.IO.FileMode],
        [System.Security.AccessControl.FileSystemRights],
        [System.IO.FileShare],
        [int],
        [System.IO.FileOptions],
        [System.Security.AccessControl.FileSecurity]
    )
    $constructor = [System.IO.FileStream].GetConstructor($constructorTypes)
    if ($null -ne $constructor) {
        return $constructor.Invoke([object[]]@(
            $LiteralPath,
            [System.IO.FileMode]::CreateNew,
            $rights,
            [System.IO.FileShare]::None,
            4096,
            [System.IO.FileOptions]::None,
            $FileSecurity
        ))
    }

    $extensionType = Get-FileSystemAclExtensionsType
    if ($null -eq $extensionType) {
        throw 'File-system ACL APIs are unavailable on this Windows runtime.'
    }
    $createMethod = @($extensionType.GetMethods() | Where-Object {
        if ($_.Name -ne 'Create') { return $false }
        $parameters = $_.GetParameters()
        return $parameters.Count -eq 7 -and
            $parameters[0].ParameterType -eq [System.IO.FileInfo] -and
            $parameters[1].ParameterType -eq [System.IO.FileMode] -and
            $parameters[2].ParameterType -eq [System.Security.AccessControl.FileSystemRights] -and
            $parameters[3].ParameterType -eq [System.IO.FileShare] -and
            $parameters[4].ParameterType -eq [int] -and
            $parameters[5].ParameterType -eq [System.IO.FileOptions] -and
            $parameters[6].ParameterType -eq [System.Security.AccessControl.FileSecurity]
    } | Select-Object -First 1)
    if ($createMethod.Count -ne 1) {
        throw 'Compatible FileSystemAclExtensions.Create API was not found.'
    }
    $fileInfo = [System.IO.FileInfo]::new($LiteralPath)
    $arguments = [object[]]::new(7)
    $arguments[0] = $fileInfo
    $arguments[1] = [System.IO.FileMode]::CreateNew
    $arguments[2] = $rights
    $arguments[3] = [System.IO.FileShare]::None
    $arguments[4] = 4096
    $arguments[5] = [System.IO.FileOptions]::None
    $arguments[6] = $FileSecurity
    return $createMethod[0].Invoke($null, $arguments)
}

function Test-ByteArraysEqual {
    param(
        [AllowNull()][byte[]]$Expected,
        [AllowNull()][byte[]]$Actual
    )
    if ($null -eq $Expected -or $null -eq $Actual -or $Expected.Length -ne $Actual.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Expected.Length; $index++) {
        if ($Expected[$index] -ne $Actual[$index]) { return $false }
    }
    return $true
}

function Write-AtomicText {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [AllowEmptyString()][Parameter(Mandatory = $true)][string]$Content
    )

    $fullPath = Get-FullPath -LiteralPath $LiteralPath
    Assert-NoReparseTraversal -LiteralPath $fullPath -Purpose 'atomic write'
    $parent = Split-Path -Parent $LiteralPath
    if ([string]::IsNullOrWhiteSpace($parent)) {
        throw "Cannot determine parent directory for $LiteralPath"
    }
    Ensure-Directory -LiteralPath $parent
    Assert-NoReparseTraversal -LiteralPath $parent -Purpose 'atomic write parent'
    $tempPath = Join-Path $parent ('.assistant-framework-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = Join-Path $parent ('.assistant-framework-' + [Guid]::NewGuid().ToString('N') + '.bak')
    $originalAcl = $null
    $originalBytes = $null
    $retainBackupOnFailure = $false
    $destinationExisted = Test-Path -LiteralPath $fullPath -PathType Leaf
    $isWindowsHost = Test-IsWindowsHost
    $preserveWindowsAcl = $destinationExisted -and $isWindowsHost
    $expectedBytes = $script:Utf8NoBom.GetBytes($Content)
    $tempFileIdentity = $null
    $openedTempAcl = $null
    if ($destinationExisted) {
        if ($preserveWindowsAcl) {
            $originalStream = $null
            try {
                $originalStream = Open-WindowsFileSecurityStream -LiteralPath $fullPath
                $originalBytes = Read-FileStreamBytes -Stream $originalStream
                $originalAcl = Get-FileStreamAcl -Stream $originalStream
                $originalAclIssues = @(Get-OwnerGroupDaclDifferences -Expected $originalAcl -Actual $originalAcl)
                if ($originalAclIssues.Count -gt 0) {
                    throw "Cannot safely preserve the existing DACL for $LiteralPath. Difference categories: $($originalAclIssues -join ', ')"
                }
            }
            finally {
                if ($null -ne $originalStream) { $originalStream.Dispose() }
            }
        }
        else {
            $originalBytes = [System.IO.File]::ReadAllBytes($fullPath)
        }
    }
    $stream = $null
    $writer = $null
    try {
        if ($preserveWindowsAcl) {
            $privateFileSecurity = New-PrivateFileSecurity
            $stream = New-SecuredCreateNewStream -LiteralPath $tempPath -FileSecurity $privateFileSecurity
        }
        elseif ($isWindowsHost) {
            $stream = New-WindowsDefaultCreateNewStream -LiteralPath $tempPath
        }
        else {
            $stream = [System.IO.File]::Open(
                $tempPath,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None
            )
        }
        if ($isWindowsHost) {
            $tempFileIdentity = Get-WindowsFileIdentity -SafeFileHandle $stream.SafeFileHandle
            $openedTempAcl = Get-FileStreamAcl -Stream $stream
            if ($preserveWindowsAcl) {
                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
                if (-not (Test-PrivateFileSecurity -Acl $openedTempAcl -CurrentUser $currentUser)) {
                    throw "Could not secure the temporary file with a private DACL for $LiteralPath"
                }
            }
        }
        $writer = New-Object -TypeName System.IO.StreamWriter -ArgumentList @($stream, $script:Utf8NoBom)
        $writer.Write($Content)
        $writer.Flush()
        $stream.Flush($true)
        $writer.Dispose()
        $writer = $null
        $stream = $null
        if (-not (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
            throw "Temporary write validation failed for $LiteralPath"
        }
        $writtenContent = [System.IO.File]::ReadAllText($tempPath)
        if ($writtenContent -cne $Content) {
            throw "Temporary write content validation failed for $LiteralPath"
        }
        Assert-NoReparseTraversal -LiteralPath $fullPath -Purpose 'atomic replacement'
        if ($destinationExisted) {
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                throw "Atomic replacement destination changed before commit: $fullPath"
            }
            Assert-NoReparseTraversal -LiteralPath $backupPath -Purpose 'atomic backup'
            if (Test-Path -LiteralPath $backupPath) {
                throw "Atomic backup path unexpectedly exists: $backupPath"
            }
            try {
                $ignoreMetadataErrors = -not $preserveWindowsAcl
                [System.IO.File]::Replace($tempPath, $fullPath, $backupPath, $ignoreMetadataErrors)
                if ($preserveWindowsAcl) {
                    $committedStream = $null
                    try {
                        $committedStream = Open-WindowsFileDaclWriteStream -LiteralPath $fullPath
                        $committedFileIdentity = Get-WindowsFileIdentity -SafeFileHandle $committedStream.SafeFileHandle
                        $identityMatches = Test-WindowsFileIdentityEqual -Expected $tempFileIdentity -Actual $committedFileIdentity
                        if (-not $identityMatches) {
                            throw "Atomic replacement identity verification failed for $LiteralPath"
                        }
                        $committedBytes = Read-FileStreamBytes -Stream $committedStream
                        if (-not (Test-ByteArraysEqual -Expected $expectedBytes -Actual $committedBytes)) {
                            throw "Atomic replacement content verification failed for $LiteralPath"
                        }
                        $committedLinkCount = Get-WindowsFileLinkCount -SafeFileHandle $committedStream.SafeFileHandle
                        if ($committedLinkCount -ne 1) {
                            throw "Atomic replacement link-count verification failed for $LiteralPath"
                        }
                        $committedAcl = Get-FileStreamAcl -Stream $committedStream
                        $committedAclDifferences = @(Get-OwnerGroupDaclDifferences -Expected $originalAcl -Actual $committedAcl)
                        if ($committedAclDifferences.Count -gt 0) {
                            $hasNonRepairableDifference =
                                $committedAclDifferences -contains 'owner' -or
                                $committedAclDifferences -contains 'group' -or
                                $committedAclDifferences -contains 'noncanonical' -or
                                $committedAclDifferences -contains 'null_dacl'
                            $hasRepairableDifference =
                                $committedAclDifferences -contains 'dacl' -or
                                $committedAclDifferences -contains 'protection'
                            if ($hasNonRepairableDifference -or -not $hasRepairableDifference) {
                                throw "Atomic replacement owner, group, and DACL verification failed for $LiteralPath. Difference categories: $($committedAclDifferences -join ', ')"
                            }
                            $originalDacl = New-BinaryDaclFileSecurity -ReferenceAcl $originalAcl
                            Set-FileStreamAcl -Stream $committedStream -Acl $originalDacl
                        }
                        $appliedAcl = Get-FileStreamAcl -Stream $committedStream
                        $aclDifferences = @(Get-OwnerGroupDaclDifferences -Expected $originalAcl -Actual $appliedAcl)
                        if ($aclDifferences.Count -gt 0) {
                            throw "Atomic replacement owner, group, and DACL verification failed for $LiteralPath. Difference categories: $($aclDifferences -join ', ')"
                        }
                    }
                    finally {
                        if ($null -ne $committedStream) { $committedStream.Dispose() }
                    }
                }
                else {
                    $committedBytes = [System.IO.File]::ReadAllBytes($fullPath)
                    if (-not (Test-ByteArraysEqual -Expected $expectedBytes -Actual $committedBytes)) {
                        throw "Atomic replacement content verification failed for $LiteralPath"
                    }
                }
            }
            catch {
                $replacementError = $_
                if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                    $retainBackupOnFailure = $true
                    Assert-NoReparseTraversal -LiteralPath $backupPath -Purpose 'atomic rollback backup'
                    $rollbackDiscard = $null
                    $discardContainsFailedReplacement = $false
                    $backupRestored = $false
                    $rollbackVerified = $false
                    try {
                        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
                            $rollbackDiscard = Join-Path $parent ('.assistant-framework-' + [Guid]::NewGuid().ToString('N') + '.rollback')
                            Assert-NoReparseTraversal -LiteralPath $rollbackDiscard -Purpose 'atomic rollback discard'
                            if (Test-Path -LiteralPath $rollbackDiscard) {
                                throw "Atomic rollback discard unexpectedly exists: $rollbackDiscard"
                            }
                            [System.IO.File]::Move($fullPath, $rollbackDiscard)
                            $discardContainsFailedReplacement = $true
                        }
                        [System.IO.File]::Move($backupPath, $fullPath)
                        $backupRestored = $true
                        $restoredAcl = $null
                        if ($preserveWindowsAcl) {
                            $restoredStream = $null
                            try {
                                $restoredStream = Open-WindowsFileSecurityStream -LiteralPath $fullPath
                                $restoredBytes = Read-FileStreamBytes -Stream $restoredStream
                                $restoredAcl = Get-FileStreamAcl -Stream $restoredStream
                            }
                            finally {
                                if ($null -ne $restoredStream) { $restoredStream.Dispose() }
                            }
                        }
                        else {
                            $restoredBytes = [System.IO.File]::ReadAllBytes($fullPath)
                        }
                        $restoredBytesMatch = Test-ByteArraysEqual -Expected $originalBytes -Actual $restoredBytes
                        $restoredAclDifferences = @()
                        if ($preserveWindowsAcl) {
                            $restoredAclDifferences = @(Get-OwnerGroupDaclDifferences -Expected $originalAcl -Actual $restoredAcl)
                        }
                        if (-not $restoredBytesMatch -or $restoredAclDifferences.Count -gt 0) {
                            throw "Atomic rollback could not verify the restored bytes, owner, group, and DACL. Difference categories: $($restoredAclDifferences -join ', ')"
                        }
                        $rollbackVerified = $true
                        if ($discardContainsFailedReplacement -and (Test-Path -LiteralPath $rollbackDiscard -PathType Leaf)) {
                            [System.IO.File]::Delete($rollbackDiscard)
                        }
                        $retainBackupOnFailure = $false
                    }
                    catch {
                        $rollbackError = $_
                        if (-not $backupRestored -and
                            (Test-Path -LiteralPath $backupPath -PathType Leaf) -and
                            $discardContainsFailedReplacement -and
                            -not (Test-Path -LiteralPath $fullPath)) {
                            try {
                                [System.IO.File]::Move($rollbackDiscard, $fullPath)
                                $discardContainsFailedReplacement = $false
                            }
                            catch {
                                # Leave both recovery files in place for manual recovery.
                            }
                        }
                        $recoveryLocations = New-Object System.Collections.Generic.List[string]
                        if ($backupRestored -and (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                            $restorationState = if ($rollbackVerified) { 'Verified restored destination' } else { 'Unverified restored destination' }
                            $recoveryLocations.Add("${restorationState}: $fullPath")
                        }
                        elseif (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                            $recoveryLocations.Add("Original backup: $backupPath")
                        }
                        if (-not $backupRestored -and (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                            $recoveryLocations.Add("Current destination: $fullPath")
                        }
                        if ($null -ne $rollbackDiscard -and (Test-Path -LiteralPath $rollbackDiscard -PathType Leaf)) {
                            $recoveryLocations.Add("Failed replacement: $rollbackDiscard")
                        }
                        $recoverySummary = if ($recoveryLocations.Count -gt 0) {
                            $recoveryLocations -join '; '
                        }
                        else {
                            'No recovery path could be confirmed.'
                        }
                        $diagnosticState = if ($rollbackVerified) {
                            'The original was restored and verified, but failed-replacement cleanup did not complete.'
                        }
                        else {
                            'Rollback could not be verified.'
                        }
                        throw "Atomic replacement failed for $LiteralPath. $diagnosticState $recoverySummary. Replacement error: $($replacementError.Exception.Message). Rollback or cleanup error: $($rollbackError.Exception.Message)"
                    }
                }
                throw $replacementError
            }
            if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                [System.IO.File]::Delete($backupPath)
            }
        }
        else {
            [System.IO.File]::Move($tempPath, $fullPath)
            if ($isWindowsHost) {
                $committedStream = $null
                try {
                    $committedStream = Open-WindowsFileReadStream -LiteralPath $fullPath
                    $committedFileIdentity = Get-WindowsFileIdentity -SafeFileHandle $committedStream.SafeFileHandle
                    $committedBytes = Read-FileStreamBytes -Stream $committedStream
                    $committedAcl = Get-FileStreamAcl -Stream $committedStream
                    $identityMatches = Test-WindowsFileIdentityEqual -Expected $tempFileIdentity -Actual $committedFileIdentity
                    $bytesMatch = Test-ByteArraysEqual -Expected $expectedBytes -Actual $committedBytes
                    $aclDifferences = @(Get-OwnerGroupDaclDifferences -Expected $openedTempAcl -Actual $committedAcl)
                    if (-not $identityMatches -or -not $bytesMatch -or $aclDifferences.Count -gt 0) {
                        throw "First-install commit verification failed for $LiteralPath. Difference categories: $($aclDifferences -join ', '). The destination was retained for inspection."
                    }
                }
                finally {
                    if ($null -ne $committedStream) { $committedStream.Dispose() }
                }
            }
        }
    }
    finally {
        if ($null -ne $writer) { $writer.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
        if (-not $retainBackupOnFailure -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Assert-NoReparseTraversal -LiteralPath $backupPath -Purpose 'atomic backup cleanup'
            [System.IO.File]::Delete($backupPath)
        }
    }
}

function Clear-ManagedDirectory {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Container)) {
        return
    }

    foreach ($item in @(Get-ChildItem -LiteralPath $LiteralPath -Force)) {
        $isReparsePoint = ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        if ($isReparsePoint) {
            throw "Refusing to delete a managed tree containing a reparse point: $($item.FullName)"
        }
        if ($item.PSIsContainer) {
            Clear-ManagedDirectory -LiteralPath $item.FullName
            Remove-Item -LiteralPath $item.FullName -Force
        }
        else {
            Remove-Item -LiteralPath $item.FullName -Force
        }
    }
}

function Test-TargetTreeSafe {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return }
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Container)) {
        throw "Refusing to replace a non-directory managed target: $LiteralPath"
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $LiteralPath -Force)) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to replace a managed tree containing a reparse point: $($item.FullName)"
        }
        if ($item.PSIsContainer) { Test-TargetTreeSafe -LiteralPath $item.FullName }
    }
}

function Assert-ManagedFileCopySafe {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Managed file source not found: $Source"
    }
    $sourceItem = Get-Item -LiteralPath $Source -Force
    if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing managed file source reparse point: $Source"
    }
    Assert-NoReparseTraversal -LiteralPath $Destination -Purpose 'managed file copy'
    if (Test-Path -LiteralPath $Destination) {
        $existing = Get-Item -LiteralPath $Destination -Force
        if ($existing.PSIsContainer) {
            throw "Refusing to replace a directory with a managed file: $Destination"
        }
    }
}

function Copy-ManagedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    Assert-ManagedFileCopySafe -Source $Source -Destination $Destination
    if (Test-Path -LiteralPath $Destination) {
        # Deleting a hard-link directory entry does not write through its shared
        # data stream. Copying with overwrite disabled then fails closed if a
        # competing entry appears before creation.
        [System.IO.File]::Delete($Destination)
    }
    Assert-NoReparseTraversal -LiteralPath (Split-Path -Parent $Destination) -Purpose 'managed file copy parent'
    [System.IO.File]::Copy($Source, $Destination, $false)
}

function Test-ExcludedRelativePath {
    param(
        [string]$RelativePath,
        [string[]]$ExcludedNames,
        [string[]]$ExcludedExactPaths
    )

    $normalized = $RelativePath.Replace('\', '/').TrimStart('/')
    $segments = @($normalized -split '/')
    foreach ($name in $ExcludedNames) {
        if ($segments -contains $name) {
            return $true
        }
    }
    foreach ($exact in $ExcludedExactPaths) {
        if ([string]::Equals($normalized, $exact.Replace('\', '/').TrimStart('/'), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Copy-DirectoryTree {
    param(
        [string]$SourceRoot,
        [string]$CurrentSource,
        [string]$TargetRoot,
        [string[]]$ExcludedNames,
        [string[]]$ExcludedExactPaths
    )

    foreach ($item in @(Get-ChildItem -LiteralPath $CurrentSource -Force)) {
        $relative = $item.FullName.Substring($SourceRoot.TrimEnd([char[]]@('\', '/')).Length).TrimStart([char[]]@('\', '/'))
        if (Test-ExcludedRelativePath -RelativePath $relative -ExcludedNames $ExcludedNames -ExcludedExactPaths $ExcludedExactPaths) {
            continue
        }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to copy source reparse point: $($item.FullName)"
        }

        $destination = Join-Path $TargetRoot $relative
        if ($item.PSIsContainer) {
            Ensure-Directory -LiteralPath $destination
            Copy-DirectoryTree -SourceRoot $SourceRoot -CurrentSource $item.FullName -TargetRoot $TargetRoot -ExcludedNames $ExcludedNames -ExcludedExactPaths $ExcludedExactPaths
        }
        else {
            Ensure-Directory -LiteralPath (Split-Path -Parent $destination)
            Copy-ManagedFile -Source $item.FullName -Destination $destination
        }
    }
}

function Test-SourceTreeSafe {
    param(
        [string]$SourceRoot,
        [string]$CurrentSource,
        [string[]]$ExcludedNames,
        [string[]]$ExcludedExactPaths
    )
    foreach ($item in @(Get-ChildItem -LiteralPath $CurrentSource -Force)) {
        $relative = $item.FullName.Substring($SourceRoot.TrimEnd([char[]]@('\', '/')).Length).TrimStart([char[]]@('\', '/'))
        if (Test-ExcludedRelativePath -RelativePath $relative -ExcludedNames $ExcludedNames -ExcludedExactPaths $ExcludedExactPaths) {
            continue
        }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to copy source reparse point: $($item.FullName)"
        }
        if ($item.PSIsContainer) {
            Test-SourceTreeSafe -SourceRoot $SourceRoot -CurrentSource $item.FullName -ExcludedNames $ExcludedNames -ExcludedExactPaths $ExcludedExactPaths
        }
    }
}

function Assert-ManagedDirectoryCopySafe {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [string[]]$ExcludedNames = @('.DS_Store'),
        [string[]]$ExcludedExactPaths = @(),
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Source directory not found for ${Label}: $Source"
    }
    $sourceItem = Get-Item -LiteralPath $Source -Force
    if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing $Label source reparse point: $Source"
    }
    $safeTarget = Assert-SafeManagedChild -LiteralPath $Target -ManagedRoot $ManagedRoot -Purpose "$Label mirror"
    Assert-NoSourceTargetOverlap -Source $Source -Target $safeTarget -Purpose $Label
    Test-SourceTreeSafe -SourceRoot $Source -CurrentSource $Source -ExcludedNames $ExcludedNames -ExcludedExactPaths $ExcludedExactPaths
    Test-TargetTreeSafe -LiteralPath $safeTarget
    return $safeTarget
}

function Sync-ManagedDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [string[]]$ExcludedNames = @('.DS_Store'),
        [string[]]$ExcludedExactPaths = @(),
        [Parameter(Mandatory = $true)][string]$Label
    )

    $safeTarget = Assert-ManagedDirectoryCopySafe -Source $Source -Target $Target -ManagedRoot $ManagedRoot -ExcludedNames $ExcludedNames -ExcludedExactPaths $ExcludedExactPaths -Label $Label

    if ($DryRun) {
        Write-DryRun "Mirror $Source -> $safeTarget"
        return
    }

    Ensure-Directory -LiteralPath $ManagedRoot
    Ensure-Directory -LiteralPath $safeTarget
    Clear-ManagedDirectory -LiteralPath $safeTarget
    Copy-DirectoryTree -SourceRoot $Source -CurrentSource $Source -TargetRoot $safeTarget -ExcludedNames $ExcludedNames -ExcludedExactPaths $ExcludedExactPaths
    Write-Ok "$Label -> $safeTarget"
}

function Sync-ManagedTopLevelEntries {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [string[]]$ExcludedNames = @('.DS_Store'),
        [string[]]$ExcludedExactPaths = @(),
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Source directory not found for ${Label}: $Source"
    }
    $safeTarget = Assert-SafeManagedChild -LiteralPath $Target -ManagedRoot $ManagedRoot -Purpose "$Label root"
    Assert-NoSourceTargetOverlap -Source $Source -Target $safeTarget -Purpose $Label
    $sourceItem = Get-Item -LiteralPath $Source -Force
    if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing $Label source reparse point: $Source"
    }

    foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force | Sort-Object Name)) {
        if (Test-ExcludedRelativePath -RelativePath $item.Name -ExcludedNames $ExcludedNames -ExcludedExactPaths $ExcludedExactPaths) {
            continue
        }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing $Label source reparse point: $($item.FullName)"
        }
        $destination = Join-Path $safeTarget $item.Name
        if ($item.PSIsContainer) {
            $childExcludedExactPaths = @(
                foreach ($excludedPath in $ExcludedExactPaths) {
                    $normalizedExcluded = $excludedPath.Replace('\', '/').TrimStart('/')
                    $childPrefix = $item.Name + '/'
                    if ($normalizedExcluded.StartsWith($childPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $normalizedExcluded.Substring($childPrefix.Length)
                    }
                }
            )
            Sync-ManagedDirectory -Source $item.FullName -Target $destination -ManagedRoot $safeTarget -ExcludedNames $ExcludedNames -ExcludedExactPaths $childExcludedExactPaths -Label "$Label/$($item.Name)"
        }
        else {
            $safeFile = Assert-SafeManagedChild -LiteralPath $destination -ManagedRoot $safeTarget -Purpose "$Label file"
            Assert-ManagedFileCopySafe -Source $item.FullName -Destination $safeFile
            if ($DryRun) {
                Write-DryRun "Install $Label $($item.Name) -> $safeTarget"
                continue
            }
            Ensure-Directory -LiteralPath $safeTarget
            Copy-ManagedFile -Source $item.FullName -Destination $safeFile
        }
    }
    if (-not $DryRun) { Write-Ok "$Label owned entries -> $safeTarget" }
}

function Assert-ManagedTopLevelEntriesSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [string[]]$ExcludedNames = @('.DS_Store'),
        [string[]]$ExcludedExactPaths = @(),
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return }
    $safeTarget = Assert-SafeManagedChild -LiteralPath $Target -ManagedRoot $ManagedRoot -Purpose "$Label root"
    Assert-NoSourceTargetOverlap -Source $Source -Target $safeTarget -Purpose $Label
    $sourceItem = Get-Item -LiteralPath $Source -Force
    if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing $Label source reparse point: $Source"
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force | Sort-Object Name)) {
        if (Test-ExcludedRelativePath -RelativePath $item.Name -ExcludedNames $ExcludedNames -ExcludedExactPaths $ExcludedExactPaths) { continue }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing $Label source reparse point: $($item.FullName)"
        }
        $destination = Join-Path $safeTarget $item.Name
        if ($item.PSIsContainer) {
            $childExcludedExactPaths = @(
                foreach ($excludedPath in $ExcludedExactPaths) {
                    $normalizedExcluded = $excludedPath.Replace('\', '/').TrimStart('/')
                    $childPrefix = $item.Name + '/'
                    if ($normalizedExcluded.StartsWith($childPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $normalizedExcluded.Substring($childPrefix.Length)
                    }
                }
            )
            [void](Assert-ManagedDirectoryCopySafe -Source $item.FullName -Target $destination -ManagedRoot $safeTarget -ExcludedNames $ExcludedNames -ExcludedExactPaths $childExcludedExactPaths -Label "$Label/$($item.Name)")
        }
        else {
            $safeFile = Assert-SafeManagedChild -LiteralPath $destination -ManagedRoot $safeTarget -Purpose "$Label file"
            Assert-ManagedFileCopySafe -Source $item.FullName -Destination $safeFile
        }
    }
}

function Remove-ExactManagedFiles {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $safeTargetRoot = Assert-SafeManagedChild -LiteralPath $TargetRoot -ManagedRoot $ManagedRoot -Purpose "$Label root"
    $validatedFiles = New-Object System.Collections.Generic.List[string]
    foreach ($relativePath in $RelativePaths) {
        $normalized = $relativePath.Replace('\', '/').Trim('/')
        if ([string]::IsNullOrWhiteSpace($normalized) -or
            [System.IO.Path]::IsPathRooted($relativePath) -or
            @($normalized -split '/' | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
            throw "Refusing unsafe relative path for ${Label}: $relativePath"
        }

        $candidate = Join-Path $safeTargetRoot $relativePath
        $safeFile = Assert-SafeManagedChild -LiteralPath $candidate -ManagedRoot $safeTargetRoot -Purpose "$Label file"
        $item = Get-Item -LiteralPath $safeFile -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to remove a managed target for $Label that is a reparse point: $safeFile"
        }
        if ($item.PSIsContainer) {
            throw "Refusing to remove a managed target for $Label that is not a file: $safeFile"
        }
        $validatedFiles.Add($safeFile)
    }

    foreach ($safeFile in $validatedFiles) {
        if ($DryRun) {
            Write-DryRun "Remove managed installed target for ${Label}: $safeFile"
            continue
        }
        [void](Assert-SafeManagedChild -LiteralPath $safeFile -ManagedRoot $safeTargetRoot -Purpose "$Label deletion")
        $item = Get-Item -LiteralPath $safeFile -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.PSIsContainer) {
            throw "Refusing changed managed target for $Label before deletion: $safeFile"
        }
        [System.IO.File]::Delete($safeFile)
        Write-Ok "Removed managed installed target for ${Label}: $safeFile"
    }
}

function Get-JsonPropertyInfoExact {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    foreach ($property in @($Object.PSObject.Properties)) {
        if ([string]::Equals($property.Name, $Name, [System.StringComparison]::Ordinal)) {
            return $property
        }
    }
    return $null
}

function Get-JsonPropertyCaseVariant {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    foreach ($property in @($Object.PSObject.Properties)) {
        if (-not [string]::Equals($property.Name, $Name, [System.StringComparison]::Ordinal) -and
            [string]::Equals($property.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $property
        }
    }
    return $null
}

function Get-JsonProperty {
    param($Object, [string]$Name)
    $property = Get-JsonPropertyInfoExact -Object $Object -Name $Name
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-JsonProperty {
    param($Object, [string]$Name, $Value)
    $caseVariant = Get-JsonPropertyCaseVariant -Object $Object -Name $Name
    if ($null -ne $caseVariant) {
        throw "JSON property '$($caseVariant.Name)' conflicts with installer-owned exact property '$Name'."
    }
    $property = Get-JsonPropertyInfoExact -Object $Object -Name $Name
    if ($null -eq $property) {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
    else {
        $property.Value = $Value
    }
}

function Remove-JsonProperty {
    param($Object, [string]$Name)
    $property = Get-JsonPropertyInfoExact -Object $Object -Name $Name
    if ($null -ne $property) {
        $Object.PSObject.Properties.Remove($property.Name)
    }
}

function Convert-ToObjectArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value) }
    return @($Value)
}

function Skip-JsonIdentityWhitespace {
    param([string]$Text, [ref]$Index)
    while ($Index.Value -lt $Text.Length -and [char]::IsWhiteSpace($Text[$Index.Value])) {
        $Index.Value++
    }
}

function Read-JsonIdentityString {
    param([string]$Text, [ref]$Index, [switch]$Decode)
    if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne '"') {
        throw 'Invalid JSON identity scan: expected a string.'
    }
    $start = $Index.Value
    $Index.Value++
    $escaped = $false
    while ($Index.Value -lt $Text.Length) {
        $character = $Text[$Index.Value]
        $Index.Value++
        if ($escaped) { $escaped = $false; continue }
        if ($character -eq '\') { $escaped = $true; continue }
        if ($character -eq '"') {
            if (-not $Decode) { return }
            $raw = $Text.Substring($start, $Index.Value - $start)
            try {
                $decoded = $raw | ConvertFrom-Json
            }
            catch {
                throw 'Invalid JSON identity scan: invalid string escape.'
            }
            if ($decoded -isnot [string]) { throw 'Invalid JSON identity scan: invalid property string.' }
            return (New-Object PSObject -Property @{ Value = $decoded })
        }
    }
    throw 'Invalid JSON identity scan: unterminated string.'
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
    if ((Get-Item -LiteralPath $LiteralPath -Force).Length -gt $script:MaxJsonInputBytes) {
        Throw-JsonComplexityError -Reason "input exceeds $($script:MaxJsonInputBytes) bytes."
    }
}

function Read-JsonIdentityValue {
    param([string]$Text, [ref]$Index, $Context, [int]$Depth)
    if ($Depth -gt $script:MaxJsonIdentityDepth) {
        Throw-JsonComplexityError -Reason "nesting exceeds $($script:MaxJsonIdentityDepth) levels."
    }
    $Context.ValueCount++
    if ($Context.ValueCount -gt $script:MaxJsonIdentityValues) {
        Throw-JsonComplexityError -Reason "value count exceeds $($script:MaxJsonIdentityValues)."
    }
    Skip-JsonIdentityWhitespace -Text $Text -Index $Index
    if ($Index.Value -ge $Text.Length) { throw 'Invalid JSON identity scan: missing value.' }
    $character = $Text[$Index.Value]
    if ($character -eq '{') { Read-JsonIdentityObject -Text $Text -Index $Index -Context $Context -Depth $Depth; return }
    if ($character -eq '[') { Read-JsonIdentityArray -Text $Text -Index $Index -Context $Context -Depth $Depth; return }
    if ($character -eq '"') { [void](Read-JsonIdentityString -Text $Text -Index $Index); return }
    $start = $Index.Value
    while ($Index.Value -lt $Text.Length) {
        $character = $Text[$Index.Value]
        if ($character -eq ',' -or $character -eq '}' -or $character -eq ']' -or [char]::IsWhiteSpace($character)) { break }
        $Index.Value++
    }
    if ($Index.Value -eq $start) { throw 'Invalid JSON identity scan: invalid value.' }
}

function Read-JsonIdentityObject {
    param([string]$Text, [ref]$Index, $Context, [int]$Depth)
    $Index.Value++
    $exactKeys = New-OrdinalDictionary
    $foldedKeys = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Skip-JsonIdentityWhitespace -Text $Text -Index $Index
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq '}') { $Index.Value++; return }
    while ($Index.Value -lt $Text.Length) {
        $keyToken = Read-JsonIdentityString -Text $Text -Index $Index -Decode
        $key = $keyToken.Value
        $Context.PropertyCount++
        if ($Context.PropertyCount -gt $script:MaxJsonIdentityProperties) {
            Throw-JsonComplexityError -Reason "property count exceeds $($script:MaxJsonIdentityProperties)."
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
    if ($script:Utf8Strict.GetByteCount($Text) -gt $script:MaxJsonInputBytes) {
        Throw-JsonComplexityError -Reason "input exceeds $($script:MaxJsonInputBytes) bytes."
    }
    $index = 0
    $indexRef = [ref]$index
    $context = New-Object PSObject -Property @{ PropertyCount = 0; ValueCount = 0 }
    Read-JsonIdentityValue -Text $Text -Index $indexRef -Context $context -Depth 0
    Skip-JsonIdentityWhitespace -Text $Text -Index $indexRef
    if ($index -ne $Text.Length) { throw 'Invalid JSON identity scan: trailing content.' }
}

function Assert-JsonFilePropertyIdentitySafe {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { return }
    Assert-JsonFileResourceBudget -LiteralPath $LiteralPath
    $rawJson = Read-StrictUtf8Text -LiteralPath $LiteralPath
    try {
        Assert-JsonTextPropertyIdentitySafe -Text $rawJson
    }
    catch {
        if ($_.Exception.Message.StartsWith('Unsafe JSON property identity:', [System.StringComparison]::Ordinal) -or
            $_.Exception.Message.StartsWith('Unsafe JSON complexity:', [System.StringComparison]::Ordinal)) { throw }
        # Syntax errors retain the existing warn-and-preserve behavior in Read-JsonObject.
    }
}

function Read-JsonObject {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        return (New-Object PSObject)
    }
    Assert-JsonFileResourceBudget -LiteralPath $LiteralPath
    $rawJson = Read-StrictUtf8Text -LiteralPath $LiteralPath
    try {
        Assert-JsonTextPropertyIdentitySafe -Text $rawJson
        $trimmedJson = $rawJson.TrimStart()
        if ([string]::IsNullOrWhiteSpace($trimmedJson) -or -not $trimmedJson.StartsWith('{')) {
            throw 'The JSON root must be an object.'
        }
        $parsed = $rawJson | ConvertFrom-Json
        if ($null -eq $parsed -or $parsed -is [System.Array] -or $parsed -is [string] -or $parsed -is [ValueType]) {
            throw 'The JSON root must be an object.'
        }
        return $parsed
    }
    catch {
        if ($_.Exception.Message.StartsWith('Unsafe JSON property identity:', [System.StringComparison]::Ordinal) -or
            $_.Exception.Message.StartsWith('Unsafe JSON complexity:', [System.StringComparison]::Ordinal)) { throw }
        Write-Info "WARNING: Invalid JSON in $LiteralPath; preserved unchanged."
        return $null
    }
}

function Save-JsonObject {
    param([string]$LiteralPath, $Object)
    $json = $Object | ConvertTo-Json -Depth 100
    Write-AtomicText -LiteralPath $LiteralPath -Content ($json.TrimEnd() + [Environment]::NewLine)
}

function Get-PluginProfileSkills {
    param([string]$PluginName, [string]$SkillsSource)
    if ($script:SupportedPluginProfiles -notcontains $PluginName) {
        throw "Unknown or unsupported plugin profile: $PluginName. Supported: $($script:SupportedPluginProfiles -join ', ')"
    }
    $architectureFile = Join-Path $script:FrameworkDir 'docs/plugin-architecture.md'
    if (-not (Test-Path -LiteralPath $architectureFile -PathType Leaf)) {
        throw "Plugin architecture document not found: $architectureFile"
    }

    $inside = $false
    $profileLine = $null
    foreach ($line in Get-Content -LiteralPath $architectureFile) {
        if ($line -eq 'PLUGIN_BOUNDARY_START') { $inside = $true; continue }
        if ($line -eq 'PLUGIN_BOUNDARY_END') { $inside = $false; continue }
        if ($inside -and $line.StartsWith($PluginName + ':', [System.StringComparison]::Ordinal)) {
            $profileLine = $line
            break
        }
    }
    if ($null -eq $profileLine) {
        throw "Plugin profile '$PluginName' is missing from the exact PLUGIN_BOUNDARY block."
    }

    $result = @()
    $payload = $profileLine.Substring($profileLine.IndexOf(':') + 1).Trim()
    foreach ($candidate in @($payload -split '\s+')) {
        if ($candidate -like 'assistant-*') {
            $skillFile = Join-Path (Join-Path $SkillsSource $candidate) 'SKILL.md'
            if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
                throw "Plugin profile $PluginName references missing skill: $candidate"
            }
            $result += $candidate
        }
    }
    if ($result.Count -eq 0) {
        throw "Plugin profile $PluginName has no installable assistant skills."
    }
    return @($result)
}

function Test-PluginManifest {
    param([string]$PluginName, [string[]]$ProfileSkills)
    $manifest = Join-Path (Join-Path (Join-Path $script:FrameworkDir 'plugins') $PluginName) '.codex-plugin/plugin.json'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        throw "Plugin manifest not found: $manifest"
    }
    $document = Read-JsonObject -LiteralPath $manifest
    if ($null -eq $document) { throw "Plugin manifest is invalid JSON: $manifest" }
    if ((Get-JsonProperty -Object $document -Name 'name') -ne $PluginName) {
        throw "Plugin manifest $PluginName must declare name '$PluginName'."
    }
    if ((Get-JsonProperty -Object $document -Name 'skills') -ne './skills/') {
        throw "Plugin manifest $PluginName must declare skills './skills/'."
    }
    $pluginSkillsRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $manifest)) 'skills'
    if (-not (Test-Path -LiteralPath $pluginSkillsRoot -PathType Container)) {
        throw "Plugin skills directory not found: $pluginSkillsRoot"
    }
    $manifestSkills = @(
        Get-ChildItem -LiteralPath $pluginSkillsRoot -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
            ForEach-Object { $_.Name } |
            Sort-Object
    )
    $expected = @($ProfileSkills | Sort-Object)
    if (($manifestSkills -join "`n") -ne ($expected -join "`n")) {
        throw "Plugin manifest skills do not match profile boundary for $PluginName."
    }
    Write-DryRun "Validated plugin manifest $manifest"
}

function Replace-AgentStatePlaceholders {
    param([string]$SkillTarget, [string]$AgentName)
    $extensions = @('.md', '.yaml', '.yml', '.json', '.conf', '.toml')
    foreach ($file in @(Get-ChildItem -LiteralPath $SkillTarget -File -Recurse)) {
        if ($extensions -contains $file.Extension.ToLowerInvariant()) {
            $original = Read-StrictUtf8Text -LiteralPath $file.FullName
            $updated = $original.Replace('{agent_state_dir}', '.' + $AgentName)
            if ($updated -ne $original) {
                Write-AtomicText -LiteralPath $file.FullName -Content $updated
            }
        }
    }
}

function Install-Skills {
    param([string[]]$SkillNames, [string]$SourceRoot, [string]$TargetRoot, [string]$AgentName)
    foreach ($skillName in $SkillNames) {
        $source = Join-Path $SourceRoot $skillName
        $target = Join-Path $TargetRoot $skillName
        Sync-ManagedDirectory -Source $source -Target $target -ManagedRoot $TargetRoot -Label $skillName
        if ($DryRun) {
            Write-DryRun "Select $AgentName preset and substitute {agent_state_dir} in $skillName"
            continue
        }
        if ($AgentName -ne 'claude') {
            $preset = Join-Path (Join-Path $target 'agents') ($AgentName + '.conf')
            $agentConf = Join-Path $target 'agent.conf'
            if ((Test-Path -LiteralPath $preset -PathType Leaf) -and (Test-Path -LiteralPath $agentConf -PathType Leaf)) {
                Copy-ManagedFile -Source $preset -Destination $agentConf
            }
        }
        Replace-AgentStatePlaceholders -SkillTarget $target -AgentName $AgentName
    }
}

function Write-DependencyNotes {
    param([string[]]$SkillNames, [string]$SourceRoot, [string]$TargetRoot)
    foreach ($skillName in $SkillNames) {
        $skillFile = Join-Path (Join-Path $SourceRoot $skillName) 'SKILL.md'
        $inFrontmatter = $false
        $inRequires = $false
        foreach ($line in Get-Content -LiteralPath $skillFile) {
            if ($line -eq '---') {
                if ($inFrontmatter) { break }
                $inFrontmatter = $true
                continue
            }
            if (-not $inFrontmatter) { continue }
            if ($line -eq 'requires:') { $inRequires = $true; continue }
            if ($inRequires -and $line -match '^\s*-\s*(.+?)\s*$') {
                $dependency = $Matches[1]
                if (($SkillNames -notcontains $dependency) -and -not (Test-Path -LiteralPath (Join-Path $TargetRoot $dependency) -PathType Container)) {
                    Write-Info "NOTE: $skillName requires '$dependency', which is not selected or installed."
                }
            }
            elseif ($inRequires) {
                $inRequires = $false
            }
        }
    }
}

function Assert-FlatArtifactsSafe {
    param([string]$Source, [string]$Target, [string]$ManagedRoot, [string]$Filter, [string]$Label)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return }
    $sourceItem = Get-Item -LiteralPath $Source -Force
    if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing $Label source reparse point: $Source"
    }
    $safeTarget = Assert-SafeManagedChild -LiteralPath $Target -ManagedRoot $ManagedRoot -Purpose "$Label target"
    $files = @(Get-ChildItem -LiteralPath $Source -File -Filter $Filter | Sort-Object Name)
    foreach ($file in $files) {
        $destination = Assert-SafeManagedChild -LiteralPath (Join-Path $safeTarget $file.Name) -ManagedRoot $safeTarget -Purpose "$Label copy"
        Assert-ManagedFileCopySafe -Source $file.FullName -Destination $destination
    }
}

function Copy-FlatArtifacts {
    param([string]$Source, [string]$Target, [string]$ManagedRoot, [string]$Filter, [string]$Label)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return @() }
    Assert-FlatArtifactsSafe -Source $Source -Target $Target -ManagedRoot $ManagedRoot -Filter $Filter -Label $Label
    $safeTarget = Assert-SafeManagedChild -LiteralPath $Target -ManagedRoot $ManagedRoot -Purpose "$Label target"
    $files = @(Get-ChildItem -LiteralPath $Source -File -Filter $Filter | Sort-Object Name)
    if ($DryRun) {
        foreach ($file in $files) { Write-DryRun "Install $Label $($file.Name) -> $safeTarget" }
        return @($files)
    }
    Ensure-Directory -LiteralPath $safeTarget
    foreach ($file in $files) {
        $destination = Assert-SafeManagedChild -LiteralPath (Join-Path $safeTarget $file.Name) -ManagedRoot $safeTarget -Purpose "$Label copy"
        Copy-ManagedFile -Source $file.FullName -Destination $destination
    }
    if ($files.Count -gt 0) { Write-Ok "$Label -> $safeTarget ($($files.Count) files)" }
    return @($files)
}

function Get-CurrentPowerShellExecutable {
    $path = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Cannot determine the current PowerShell executable for MCP registration.'
    }
    return $path
}

function Get-CommandExecutableToken {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return '' }
    $text = $Command.Trim()
    if ($text.StartsWith('&')) { $text = $text.Substring(1).TrimStart() }
    if ($text.Length -eq 0) { return '' }
    if ($text[0] -eq '"' -or $text[0] -eq "'") {
        $quote = $text[0]
        $end = $text.IndexOf($quote, 1)
        if ($end -lt 1) { return '' }
        if ($end + 1 -lt $text.Length -and -not [char]::IsWhiteSpace($text[$end + 1])) { return '' }
        return $text.Substring(1, $end - 1)
    }
    $match = [regex]::Match($text, '^\S+')
    if ($match.Success) { return $match.Value }
    return ''
}

function Normalize-HookPath {
    param([string]$PathText)
    if ([string]::IsNullOrWhiteSpace($PathText)) { return '' }
    $value = $PathText.Trim().Trim([char[]]@('"', "'"))
    $homeNormalized = (Get-FullPath -LiteralPath $script:UserHome).Replace('\', '/').TrimEnd('/')
    $value = $value.Replace('${HOME}', $homeNormalized).Replace('$HOME', $homeNormalized).Replace('%USERPROFILE%', $homeNormalized)
    if ($value -eq '~') { $value = $homeNormalized }
    elseif ($value.StartsWith('~/') -or $value.StartsWith('~\')) { $value = $homeNormalized + '/' + $value.Substring(2) }
    $value = $value.Replace('\', '/')
    while ($value.Contains('//')) { $value = $value.Replace('//', '/') }
    return $value.TrimEnd('/').ToLowerInvariant()
}

function Test-LegacyFrameworkCommand {
    param([string]$Command, [string]$AgentName, [string]$HooksTarget)
    $token = Normalize-HookPath -PathText (Get-CommandExecutableToken -Command $Command)
    if ([string]::IsNullOrWhiteSpace($token)) { return $false }
    $frameworkHooks = Join-Path $script:FrameworkDir 'hooks/scripts'
    foreach ($name in @($script:LegacyHookEntrypoints + $script:LegacyHookHelpers)) {
        $candidates = @(
            (Join-Path $HooksTarget $name),
            (Join-Path $frameworkHooks $name),
            ('$HOME/.' + $AgentName + '/hooks/assistant/' + $name)
        )
        foreach ($candidate in $candidates) {
            if ($token -eq (Normalize-HookPath -PathText $candidate)) { return $true }
        }
    }
    return $false
}

function Remove-LegacyHookRegistrations {
    param([string]$SettingsFile, [string]$HooksTarget, [string]$AgentName)
    if (-not (Test-Path -LiteralPath $SettingsFile -PathType Leaf)) { return 0 }
    $document = Read-JsonObject -LiteralPath $SettingsFile
    if ($null -eq $document) { return 0 }
    $hooks = Get-JsonProperty -Object $document -Name 'hooks'
    if ($null -eq $hooks) { return 0 }
    if ($hooks -is [System.Array] -or $hooks -is [string] -or $hooks -is [ValueType]) {
        Write-Info "WARNING: hooks in $SettingsFile is not an object; preserved unchanged."
        return 0
    }

    $removed = 0
    foreach ($eventProperty in @($hooks.PSObject.Properties)) {
        $eventWasArray = $eventProperty.Value -is [System.Array]
        $eventRemoved = 0
        $keptGroups = New-Object System.Collections.ArrayList
        foreach ($group in @(Convert-ToObjectArray -Value $eventProperty.Value)) {
            if ($null -eq $group -or $group -is [string] -or $group -is [ValueType]) {
                [void]$keptGroups.Add($group)
                continue
            }
            $groupHooksProperty = Get-JsonPropertyInfoExact -Object $group -Name 'hooks'
            if ($null -eq $groupHooksProperty) {
                [void]$keptGroups.Add($group)
                continue
            }
            $groupHooks = $groupHooksProperty.Value
            $groupRemoved = 0
            $keptHooks = New-Object System.Collections.ArrayList
            foreach ($hook in @(Convert-ToObjectArray -Value $groupHooks)) {
                $command = if ($null -eq $hook -or $hook -is [string] -or $hook -is [ValueType]) { $null } else { Get-JsonProperty -Object $hook -Name 'command' }
                if ($command -is [string] -and (Test-LegacyFrameworkCommand -Command $command -AgentName $AgentName -HooksTarget $HooksTarget)) {
                    $groupRemoved++
                    $eventRemoved++
                    $removed++
                }
                else {
                    [void]$keptHooks.Add($hook)
                }
            }

            if ($groupRemoved -eq 0) {
                [void]$keptGroups.Add($group)
            }
            elseif ($keptHooks.Count -gt 0) {
                Set-JsonProperty -Object $group -Name 'hooks' -Value @($keptHooks.ToArray())
                [void]$keptGroups.Add($group)
            }
            else {
                $metadataProperties = @($group.PSObject.Properties | Where-Object {
                    -not [string]::Equals($_.Name, 'hooks', [System.StringComparison]::Ordinal)
                })
                if ($metadataProperties.Count -gt 0) {
                    Remove-JsonProperty -Object $group -Name 'hooks'
                    [void]$keptGroups.Add($group)
                }
            }
        }
        if ($eventRemoved -eq 0) {
            continue
        }
        if ($keptGroups.Count -eq 0) {
            $hooks.PSObject.Properties.Remove($eventProperty.Name)
        }
        elseif (-not $eventWasArray -and $keptGroups.Count -eq 1) {
            $eventProperty.Value = $keptGroups[0]
        }
        else {
            $eventProperty.Value = @($keptGroups.ToArray())
        }
    }
    if ($removed -gt 0) { Save-JsonObject -LiteralPath $SettingsFile -Object $document }
    return $removed
}

function Test-LegacyHookFilesExist {
    param([string]$HooksTarget)
    foreach ($relative in @($script:LegacyHookEntrypoints + $script:LegacyHookHelpers + $script:LegacyHookModules)) {
        if (Test-Path -LiteralPath (Join-Path $HooksTarget $relative)) { return $true }
    }
    return $false
}

function Assert-LegacyHookCleanupSafe {
    param([string]$HooksTarget)
    foreach ($relative in @($script:LegacyHookEntrypoints + $script:LegacyHookHelpers + $script:LegacyHookModules)) {
        $candidate = Join-Path $HooksTarget $relative
        Assert-NoReparseTraversal -LiteralPath $candidate -Purpose 'legacy hook cleanup' -TraversalRoot $HooksTarget
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.PSIsContainer) {
                throw "Refusing legacy hook file with an unsafe type: $candidate"
            }
        }
    }
    foreach ($relative in @('workflow-phase-gates.d', 'workflow-guard.d')) {
        $candidate = Join-Path $HooksTarget $relative
        Assert-NoReparseTraversal -LiteralPath $candidate -Purpose 'legacy hook cleanup' -TraversalRoot $HooksTarget
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or -not $item.PSIsContainer) {
                throw "Refusing legacy hook directory with an unsafe type: $candidate"
            }
        }
    }
}

function Retire-LegacyHooks {
    param([string]$SettingsFile, [string]$HooksTarget, [string]$HooksRoot, [string]$AgentName)
    $safeHooksTarget = Assert-SafeManagedChild -LiteralPath $HooksTarget -ManagedRoot $HooksRoot -Purpose 'legacy hook cleanup'
    Assert-LegacyHookCleanupSafe -HooksTarget $safeHooksTarget
    if ($DryRun) {
        Write-DryRun "Remove exact retired Assistant Framework hooks from $SettingsFile when present"
        Write-DryRun "Neutralize cached framework entrypoints under $safeHooksTarget only when legacy state exists"
        return
    }
    $legacyFiles = Test-LegacyHookFilesExist -HooksTarget $safeHooksTarget
    $removed = Remove-LegacyHookRegistrations -SettingsFile $SettingsFile -HooksTarget $safeHooksTarget -AgentName $AgentName
    if (-not $legacyFiles -and $removed -eq 0) { return }

    foreach ($relative in @($script:LegacyHookHelpers + $script:LegacyHookModules)) {
        $candidate = Join-Path $safeHooksTarget $relative
        if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Force }
    }
    Ensure-Directory -LiteralPath $safeHooksTarget
    foreach ($entrypoint in $script:LegacyHookEntrypoints) {
        $shim = Join-Path $safeHooksTarget $entrypoint
        Write-AtomicText -LiteralPath $shim -Content ("#!/usr/bin/env bash`n# Assistant Framework retired-hook compatibility shim.`nexit 0`n")
    }
    foreach ($directoryName in @('workflow-phase-gates.d', 'workflow-guard.d')) {
        $directory = Join-Path $safeHooksTarget $directoryName
        if ((Test-Path -LiteralPath $directory -PathType Container) -and @(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $directory -Force
        }
    }
    Write-Ok "Retired hook registrations removed for $AgentName; cached entrypoints replaced with inert shims"
}

function Remove-InstallerMarkedBlocks {
    param([string]$Text, [string]$StartMarker, [string]$EndMarker)
    $lines = @($Text -split '\r?\n')
    $kept = New-Object System.Collections.Generic.List[string]
    $skipping = $false
    $startLine = '<!-- ' + $StartMarker + ' -->'
    $endLine = '<!-- ' + $EndMarker + ' -->'
    foreach ($line in $lines) {
        if ([string]::Equals($line.Trim(), $startLine, [System.StringComparison]::Ordinal)) { $skipping = $true; continue }
        if ($skipping) {
            if ([string]::Equals($line.Trim(), $endLine, [System.StringComparison]::Ordinal)) { $skipping = $false }
            continue
        }
        $kept.Add($line)
    }
    return ($kept -join [Environment]::NewLine).Trim()
}

function Test-ContainsExactMarkerLine {
    param([string]$Text, [string]$MarkerLine)
    foreach ($line in @($Text -split '\r?\n')) {
        if ([string]::Equals($line.Trim(), $MarkerLine, [System.StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

function Test-InstructionMarkerState {
    param([string]$InstructionsFile)
    if (-not (Test-Path -LiteralPath $InstructionsFile -PathType Leaf)) { return $true }
    $text = Read-StrictUtf8Text -LiteralPath $InstructionsFile
    $markers = New-OrdinalDictionary
    $markers.Add('<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->', (New-Object PSObject -Property @{ Kind = 'agents'; Action = 'start' }))
    $markers.Add('<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->', (New-Object PSObject -Property @{ Kind = 'agents'; Action = 'end' }))
    $markers.Add('<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->', (New-Object PSObject -Property @{ Kind = 'memory'; Action = 'start' }))
    $markers.Add('<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->', (New-Object PSObject -Property @{ Kind = 'memory'; Action = 'end' }))
    $counts = @{ agents = 0; memory = 0 }
    $open = $null
    $valid = $true
    foreach ($line in @($text -split '\r?\n')) {
        $trimmed = $line.Trim()
        if (-not $markers.ContainsKey($trimmed)) { continue }
        $marker = $markers[$trimmed]
        if ($marker.Action -eq 'start') {
            $counts[$marker.Kind]++
            if ($counts[$marker.Kind] -ne 1 -or $null -ne $open) { $valid = $false; break }
            $open = $marker.Kind
        }
        elseif ($null -eq $open -or $open -ne $marker.Kind) {
            $valid = $false
            break
        }
        else {
            $open = $null
        }
    }
    if ($null -ne $open) { $valid = $false }
    if (-not $valid) {
        Write-Info "WARNING: Ambiguous, duplicate, or unbalanced Assistant Framework markers in $InstructionsFile; preserved unchanged."
        return $false
    }
    return $true
}

function Get-CodexGuidanceBlock {
    return @'
<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->
# AGENTS.md — Codex Agent Instructions

Codex uses installed skills through native skill routing. When a skill matches, read its `SKILL.md` and load only the references or contracts relevant to the current phase.

## Operating stance

- For small, low-risk, localized work, act as a hands-on worker: complete it directly with proportionate validation and a fresh self-review.
- For medium+ or elevated-risk development work, remain the orchestrator: own user communication, task state, scope, decisions, delegation, and final integration; route implementation and independent review through the matching workflow roles when required.
- Keep orchestration proportional—do not introduce delegation or ceremony when direct lightweight execution is sufficient.

## Boundaries

- Get plan approval before medium+ or risky edits.
- Use subagents when requested by the user or required by applicable project or skill instructions; do not ask for separate spawn consent.
- Preserve user-authored files and existing dirty work.
- Verify changes with repository commands and review the approved scope before handoff.
- Keep credentials, secrets, PII, and private endpoints out of code, logs, task state, and memory.
<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->
'@
}

function Update-CodexInstructions {
    param([string]$InstructionsFile)
    if ($DryRun) { Write-DryRun "Generate or update installer guidance in $InstructionsFile"; return }
    $existing = ''
    if (Test-Path -LiteralPath $InstructionsFile -PathType Leaf) { $existing = Read-StrictUtf8Text -LiteralPath $InstructionsFile }
    $custom = Remove-InstallerMarkedBlocks -Text $existing -StartMarker 'ASSISTANT_FRAMEWORK_AGENTS_MD_START' -EndMarker 'ASSISTANT_FRAMEWORK_AGENTS_MD_END'
    $updated = (Get-CodexGuidanceBlock).TrimEnd()
    if (-not [string]::IsNullOrWhiteSpace($custom)) { $updated += [Environment]::NewLine + [Environment]::NewLine + $custom }
    Write-AtomicText -LiteralPath $InstructionsFile -Content ($updated.TrimEnd() + [Environment]::NewLine)
    Write-Ok "Installer guidance refreshed in $InstructionsFile (user content preserved)"
}

function Invoke-AssistantFrameworkInstall {
    if ([string]::IsNullOrWhiteSpace($Agent)) { throw 'Missing -Agent. Supported: claude, codex, gemini.' }
    $agentName = $Agent.Trim().ToLowerInvariant()
    if (@('claude', 'codex', 'gemini') -notcontains $agentName) {
        throw "Unknown agent '$Agent'. Supported: claude, codex, gemini."
    }
    if (-not [string]::IsNullOrWhiteSpace($Skill) -and -not [string]::IsNullOrWhiteSpace($Plugin)) {
        throw 'Use either -Skill or -Plugin, not both.'
    }
    if ($NoHooks) { Write-Info 'WARNING: -NoHooks is deprecated; all Assistant Framework installs are hookless.' }

    $skillsSource = Join-Path $script:FrameworkDir 'skills'
    if (-not (Test-Path -LiteralPath $skillsSource -PathType Container)) { throw "Skills directory not found: $skillsSource" }
    foreach ($trustedSourceRoot in @($script:FrameworkDir, $skillsSource)) {
        $trustedSourceItem = Get-Item -LiteralPath $trustedSourceRoot -Force
        if (($trustedSourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing installer source reparse point: $trustedSourceRoot"
        }
    }
    $inventory = @(
        Get-ChildItem -LiteralPath $skillsSource -Directory -Filter 'assistant-*' |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
            ForEach-Object { $_.Name } |
            Sort-Object
    )
    if ($inventory.Count -eq 0) { throw 'No root assistant-* skills were discovered.' }

    $selectedSkills = @($inventory)
    if (-not [string]::IsNullOrWhiteSpace($Skill)) {
        if ($inventory -notcontains $Skill) { throw "Unknown skill '$Skill'. Available: $($inventory -join ', ')" }
        $selectedSkills = @($Skill)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Plugin)) {
        $selectedSkills = @(Get-PluginProfileSkills -PluginName $Plugin -SkillsSource $skillsSource)
        if ($DryRun) { Test-PluginManifest -PluginName $Plugin -ProfileSkills $selectedSkills }
    }

    if ($agentName -eq 'codex' -and -not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        Assert-SafeConfiguredHomePathText -LiteralPath $env:CODEX_HOME -VariableName 'CODEX_HOME'
        $agentHome = Get-FullPath -LiteralPath $env:CODEX_HOME
    }
    else {
        $agentHome = Get-FullPath -LiteralPath (Join-Path $script:UserHome ('.' + $agentName))
    }
    if (Test-PathEqual -Left $agentHome -Right $script:UserHome) { throw 'Agent home cannot be the user home itself.' }
    $agentHomeRoot = [System.IO.Path]::GetPathRoot($agentHome)
    if (-not [string]::IsNullOrWhiteSpace($agentHomeRoot) -and (Test-PathEqual -Left $agentHome -Right $agentHomeRoot)) {
        throw 'Agent home cannot be a drive or filesystem root.'
    }
    Assert-NoSourceTargetOverlap -Source $script:FrameworkDir -Target $agentHome -Purpose 'agent home'
    $userHomePrefix = $script:UserHome.TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
    if ($agentHome.StartsWith($userHomePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $agentHomeBoundary = $script:UserHome
    }
    else {
        $agentHomeBoundary = [System.IO.Path]::GetPathRoot($agentHome)
    }
    [void](Assert-SafeManagedChild -LiteralPath $agentHome -ManagedRoot $agentHomeBoundary -Purpose 'agent home')

    if ($agentName -eq 'codex') {
        $agentsRoot = Get-FullPath -LiteralPath (Join-Path $script:UserHome '.agents')
        $skillsTarget = Join-Path $agentsRoot 'skills'
        [void](Assert-SafeManagedChild -LiteralPath $skillsTarget -ManagedRoot $agentsRoot -Purpose 'Codex skills root')
        Assert-NoSourceTargetOverlap -Source $agentHome -Target $skillsTarget -Purpose 'Codex agent home and shared skills root'
    }
    else {
        $skillsTarget = Join-Path $agentHome 'skills'
        [void](Assert-SafeManagedChild -LiteralPath $skillsTarget -ManagedRoot $agentHome -Purpose "$agentName skills root")
    }
    $toolsTarget = Join-Path $agentHome 'tools'
    $evalDocsTarget = Join-Path (Join-Path $agentHome 'docs') 'evals'
    $hooksRoot = Join-Path $agentHome 'hooks'
    $hooksTarget = Join-Path $hooksRoot 'assistant'
    $settingsFile = Join-Path $agentHome 'settings.json'
    $legacySettings = if ($agentName -eq 'codex') { Join-Path $agentHome 'hooks.json' } else { $settingsFile }
    $instructionsFile = if ($agentName -eq 'codex') {
        Join-Path $agentHome 'AGENTS.md'
    }
    elseif ($agentName -eq 'claude') {
        Join-Path $agentHome 'CLAUDE.md'
    }
    else {
        Join-Path $agentHome 'GEMINI.md'
    }
    foreach ($ownedRoot in @($hooksRoot)) {
        [void](Assert-SafeManagedChild -LiteralPath $ownedRoot -ManagedRoot $agentHome -Purpose 'agent-owned root')
    }

    Write-Host "Installing Assistant Framework for: $agentName"
    Write-Info "Source: $script:FrameworkDir"
    if (-not [string]::IsNullOrWhiteSpace($Plugin)) { Write-Info "Plugin profile: $Plugin" }
    Write-Info "Skills target: $skillsTarget"

    $toolsSource = Join-Path $script:FrameworkDir 'tools'
    $toolExclusions = @('.DS_Store', '.publish', 'bin', 'obj')
    $evalDocsSource = Join-Path (Join-Path $script:FrameworkDir 'docs') 'evals'
    $sourceOnly = @(
        'context-budget-report.sh',
        'evals/run-codex-framework-evals.sh',
        'evals/finalize-workflow-kernel-review.sh',
        'evals/lib/context-budget-evidence.sh'
    )
    $retiredManagedTools = @(
        'cleanup-memory-graph.ps1',
        'cleanup-memory-graph.sh'
    )
    # Legacy hook retirement is the only remaining operation that reads agent
    # configuration. Do not inspect unrelated user-owned files such as Codex
    # config.toml or Claude's top-level .claude.json.
    [void](Assert-SafeUserFile -LiteralPath $legacySettings -ManagedRoot $agentHome -Purpose 'legacy hook settings')
    [void](Assert-SafeUserFile -LiteralPath $instructionsFile -ManagedRoot $agentHome -Purpose 'agent instructions' -RequireExclusiveUpdatePreflight:($agentName -eq 'codex'))
    Assert-JsonFilePropertyIdentitySafe -LiteralPath $legacySettings

    foreach ($skillName in $selectedSkills) {
        [void](Assert-ManagedDirectoryCopySafe -Source (Join-Path $skillsSource $skillName) -Target (Join-Path $skillsTarget $skillName) -ManagedRoot $skillsTarget -Label $skillName)
    }
    if (Test-Path -LiteralPath $toolsSource -PathType Container) {
        Assert-ManagedTopLevelEntriesSafe -Source $toolsSource -Target $toolsTarget -ManagedRoot $agentHome -ExcludedNames $toolExclusions -ExcludedExactPaths $sourceOnly -Label 'Tools'
    }
    if (Test-Path -LiteralPath $evalDocsSource -PathType Container) {
        Assert-ManagedTopLevelEntriesSafe -Source $evalDocsSource -Target $evalDocsTarget -ManagedRoot $agentHome -Label 'Eval docs'
    }
    if ($agentName -eq 'codex') {
        Assert-FlatArtifactsSafe -Source (Join-Path (Join-Path $script:FrameworkDir 'agents') 'codex') -Target (Join-Path $agentHome 'agents') -ManagedRoot $agentHome -Filter '*.toml' -Label 'Codex agent'
        Assert-FlatArtifactsSafe -Source (Join-Path $script:FrameworkDir 'codex-rules') -Target (Join-Path $agentHome 'rules') -ManagedRoot $agentHome -Filter '*.rules' -Label 'Codex rule'
    }
    elseif ($agentName -eq 'claude') {
        Assert-FlatArtifactsSafe -Source (Join-Path (Join-Path $script:FrameworkDir 'agents') 'claude') -Target (Join-Path $agentHome 'agents') -ManagedRoot $agentHome -Filter '*.md' -Label 'Claude agent'
    }
    Assert-LegacyHookCleanupSafe -HooksTarget $hooksTarget

    $installedAgentFiles = @()
    try {
        if (Test-Path -LiteralPath $toolsSource -PathType Container) {
            Remove-ExactManagedFiles -TargetRoot $toolsTarget -ManagedRoot $agentHome -RelativePaths $sourceOnly -Label 'source-only tools'
            Remove-ExactManagedFiles -TargetRoot $toolsTarget -ManagedRoot $agentHome -RelativePaths $retiredManagedTools -Label 'retired managed tools'
        }

        Install-Skills -SkillNames $selectedSkills -SourceRoot $skillsSource -TargetRoot $skillsTarget -AgentName $agentName
        Write-DependencyNotes -SkillNames $selectedSkills -SourceRoot $skillsSource -TargetRoot $skillsTarget

        if (Test-Path -LiteralPath $toolsSource -PathType Container) {
            Sync-ManagedTopLevelEntries -Source $toolsSource -Target $toolsTarget -ManagedRoot $agentHome -ExcludedNames $toolExclusions -ExcludedExactPaths $sourceOnly -Label 'Tools'
        }
        if (Test-Path -LiteralPath $evalDocsSource -PathType Container) {
            Sync-ManagedTopLevelEntries -Source $evalDocsSource -Target $evalDocsTarget -ManagedRoot $agentHome -Label 'Eval docs'
        }

        if ($agentName -eq 'codex') {
            $installedAgentFiles = @(Copy-FlatArtifacts -Source (Join-Path (Join-Path $script:FrameworkDir 'agents') 'codex') -Target (Join-Path $agentHome 'agents') -ManagedRoot $agentHome -Filter '*.toml' -Label 'Codex agent')
            [void](Copy-FlatArtifacts -Source (Join-Path $script:FrameworkDir 'codex-rules') -Target (Join-Path $agentHome 'rules') -ManagedRoot $agentHome -Filter '*.rules' -Label 'Codex rule')
        }
        elseif ($agentName -eq 'claude') {
            $installedAgentFiles = @(Copy-FlatArtifacts -Source (Join-Path (Join-Path $script:FrameworkDir 'agents') 'claude') -Target (Join-Path $agentHome 'agents') -ManagedRoot $agentHome -Filter '*.md' -Label 'Claude agent')
        }

        Retire-LegacyHooks -SettingsFile $legacySettings -HooksTarget $hooksTarget -HooksRoot $hooksRoot -AgentName $agentName

        if (Test-InstructionMarkerState -InstructionsFile $instructionsFile) {
            if ($agentName -eq 'codex') {
                Update-CodexInstructions -InstructionsFile $instructionsFile
            }
        }
    }
    catch {
        if ($DryRun) { throw }
        $originalCause = $_.Exception.Message
        throw "Partial installation: some managed Assistant Framework files may already have been updated. Resolve the cause, close Codex App if it is using these files, and rerun the same command; reinstall is safe. Cause: $originalCause"
    }

    Write-Host ''
    Write-Host "Done. Installed $($selectedSkills.Count) skill(s) for $agentName."
    foreach ($skillName in $selectedSkills) { Write-Host ('  ' + (Join-Path $skillsTarget $skillName)) }
    if (Test-Path -LiteralPath $toolsSource -PathType Container) { Write-Host "Tools: $toolsTarget" }
    if ($installedAgentFiles.Count -gt 0) { Write-Host "Agents: $(Join-Path $agentHome 'agents')" }
}

if ($Help) {
    Show-Usage
    return
}

try {
    $candidateHomeName = if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { 'USERPROFILE' } elseif (-not [string]::IsNullOrWhiteSpace($env:HOME)) { 'HOME' } else { 'HOME' }
    $candidateHome = if ($candidateHomeName -eq 'USERPROFILE') { $env:USERPROFILE } elseif (-not [string]::IsNullOrWhiteSpace($env:HOME)) { $env:HOME } else { $HOME }
    if ([string]::IsNullOrWhiteSpace($candidateHome)) { throw 'Cannot determine the user home directory.' }
    Assert-SafeConfiguredHomePathText -LiteralPath $candidateHome -VariableName $candidateHomeName
    $script:UserHome = Get-FullPath -LiteralPath $candidateHome
    if (Test-PathEqual -Left $script:UserHome -Right ([System.IO.Path]::GetPathRoot($script:UserHome))) {
        throw "$candidateHomeName cannot be a drive or filesystem root."
    }
    $script:FrameworkDir = Get-FullPath -LiteralPath $PSScriptRoot
    Invoke-AssistantFrameworkInstall
}
catch {
    [Console]::Error.WriteLine('Error: ' + $_.Exception.Message)
    exit 1
}
