# GENERATED FILE: do not edit. Regenerate with:
#   pwsh -NoProfile -File tools/framework-ownership/ownership-checkout.ps1 build-primitives
# Installer primitives extracted from install.ps1 by AST so the ownership
# helpers share the installer's path, reparse-point, DACL-preserving write,
# JSON identity and hook-path code. Dot-source only.

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$script:MaxJsonInputBytes = 4 * 1024 * 1024
$script:MaxJsonIdentityDepth = 64
$script:MaxJsonIdentityProperties = 10000
$script:MaxJsonIdentityValues = 10000

function Test-IsWindowsHost {
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Assert-CodexStopped {
    if (-not (Test-IsWindowsHost)) { return }
    # Enumerate without -Name so an absent process is a normal empty result,
    # while enumeration failures still stop installation. CLI sessions share
    # this process name and must also be closed before updating their skills.
    $running = @(Get-Process -ErrorAction Stop | Where-Object { $_.ProcessName -ieq 'codex' })
    if ($running.Count -gt 0) {
        throw 'Codex is running. Close Codex App and any Codex CLI sessions, then rerun the installer. No installation files have been changed.'
    }
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

function Test-ContainsExactMarkerLine {
    param([string]$Text, [string]$MarkerLine)
    foreach ($line in @($Text -split '\r?\n')) {
        if ([string]::Equals($line.Trim(), $MarkerLine, [System.StringComparison]::Ordinal)) { return $true }
    }
    return $false
}
