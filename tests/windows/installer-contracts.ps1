#requires -Version 5.1
<#
.SYNOPSIS
Dependency-free native Windows contracts for install.ps1.

.DESCRIPTION
Runs under Windows PowerShell 5.1 and PowerShell 7. Every installer invocation
inherits an isolated USERPROFILE, HOME, and (when applicable) CODEX_HOME under
the suite temporary directory. The suite never targets the caller's real home.
#>

[CmdletBinding()]
param(
    [switch]$FailOnSkip
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0
$script:ActiveIsolatedUserProfile = $null
$script:FrameworkRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script:InstallerPath = Join-Path $script:FrameworkRoot 'install.ps1'
$script:MemoryLauncherPath = Join-Path $script:FrameworkRoot 'tools\memory-graph\run-memory-graph.ps1'
$script:PowerShellExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$suiteTempBase = [System.IO.Path]::GetTempPath()
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -and (Test-Path -LiteralPath '/private/tmp' -PathType Container)) {
    # macOS exposes /var as a symlink. Use its canonical private temp root so
    # the installer's deliberate ancestor-reparse rejection can still be tested.
    $suiteTempBase = '/private/tmp'
}
$script:SuiteRoot = Join-Path $suiteTempBase ('assistant-framework windows contracts ' + [Guid]::NewGuid().ToString('N'))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-False {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -is [System.Array]) { $Expected = @($Expected) -join "`n" }
    if ($Actual -is [System.Array]) { $Actual = @($Actual) -join "`n" }
    if (-not [object]::Equals($Expected, $Actual)) {
        throw "$Message`nExpected: $Expected`nActual: $Actual"
    }
}

function Assert-Contains {
    param([string]$Text, [string]$Expected, [string]$Message)
    if ($null -eq $Text -or -not $Text.Contains($Expected)) { throw $Message }
}

function Assert-NotContains {
    param([string]$Text, [string]$Unexpected, [string]$Message)
    if ($null -ne $Text -and $Text.Contains($Unexpected)) { throw $Message }
}

function Get-TestDaclBinaryFingerprint {
    param([Parameter(Mandatory = $true)][System.Security.AccessControl.RawAcl]$Dacl)
    $binary = [byte[]]::new($Dacl.BinaryLength)
    $Dacl.GetBinaryForm($binary, 0)
    return [Convert]::ToBase64String($binary)
}

function Assert-OwnerGroupDaclEquivalent {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $expectedBinary = $Expected.GetSecurityDescriptorBinaryForm()
    $actualBinary = $Actual.GetSecurityDescriptorBinaryForm()
    $expectedRaw = [System.Security.AccessControl.RawSecurityDescriptor]::new($expectedBinary, 0)
    $actualRaw = [System.Security.AccessControl.RawSecurityDescriptor]::new($actualBinary, 0)
    Assert-True ($null -ne $expectedRaw.DiscretionaryAcl -and $null -ne $actualRaw.DiscretionaryAcl) "${Message}: null DACL fidelity cannot be established"
    $expectedOwner = if ($null -eq $expectedRaw.Owner) { $null } else { $expectedRaw.Owner.Value }
    $actualOwner = if ($null -eq $actualRaw.Owner) { $null } else { $actualRaw.Owner.Value }
    Assert-True ([string]::Equals($expectedOwner, $actualOwner, [System.StringComparison]::Ordinal)) "${Message}: owner changed"
    $expectedGroup = if ($null -eq $expectedRaw.Group) { $null } else { $expectedRaw.Group.Value }
    $actualGroup = if ($null -eq $actualRaw.Group) { $null } else { $actualRaw.Group.Value }
    Assert-True ([string]::Equals($expectedGroup, $actualGroup, [System.StringComparison]::Ordinal)) "${Message}: group changed"
    Assert-True ($Expected.AreAccessRulesProtected -eq $Actual.AreAccessRulesProtected) "${Message}: DACL protection changed"
    Assert-True ($Expected.AreAccessRulesCanonical -and $Actual.AreAccessRulesCanonical) "${Message}: noncanonical DACL could not be compared safely"
    $expectedDacl = Get-TestDaclBinaryFingerprint -Dacl $expectedRaw.DiscretionaryAcl
    $actualDacl = Get-TestDaclBinaryFingerprint -Dacl $actualRaw.DiscretionaryAcl
    Assert-True ($expectedDacl -ceq $actualDacl) "${Message}: ordered DACL bytes changed"
}

function Get-LiteralCount {
    param([string]$Text, [string]$Needle)
    return [regex]::Matches($Text, [regex]::Escape($Needle)).Count
}

function Invoke-Contract {
    param([string]$Name, [scriptblock]$Body)
    try {
        $skippedBefore = $script:Skipped
        & $Body
        if ($script:Skipped -gt $skippedBefore) { return }
        $script:Passed++
        Write-Host "PASS: $Name"
    }
    catch {
        $script:Failed++
        [Console]::Error.WriteLine("FAIL: ${Name}: $($_.Exception.Message)")
    }
}

function Skip-Contract {
    param([string]$Name, [string]$Reason)
    $script:Skipped++
    Write-Host "SKIP: ${Name}: $Reason"
}

function Restore-ProcessEnvironment {
    param([hashtable]$Saved)
    foreach ($name in $Saved.Keys) {
        [Environment]::SetEnvironmentVariable($name, $Saved[$name], 'Process')
    }
}

function Use-IsolatedEnvironment {
    param([string]$Name, [scriptblock]$Body)
    $root = Join-Path $script:SuiteRoot $Name
    $isolatedUserProfile = Join-Path $root 'User Profile [isolated]'
    $savedActiveIsolatedUserProfile = $script:ActiveIsolatedUserProfile
    [void][System.IO.Directory]::CreateDirectory($isolatedUserProfile)
    $saved = @{
        USERPROFILE = [Environment]::GetEnvironmentVariable('USERPROFILE', 'Process')
        HOME = [Environment]::GetEnvironmentVariable('HOME', 'Process')
        CODEX_HOME = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
        APPDATA = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
        LOCALAPPDATA = [Environment]::GetEnvironmentVariable('LOCALAPPDATA', 'Process')
        XDG_CACHE_HOME = [Environment]::GetEnvironmentVariable('XDG_CACHE_HOME', 'Process')
        XDG_CONFIG_HOME = [Environment]::GetEnvironmentVariable('XDG_CONFIG_HOME', 'Process')
        XDG_DATA_HOME = [Environment]::GetEnvironmentVariable('XDG_DATA_HOME', 'Process')
        DOTNET_CLI_HOME = [Environment]::GetEnvironmentVariable('DOTNET_CLI_HOME', 'Process')
        DOTNET_CLI_TELEMETRY_OPTOUT = [Environment]::GetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT', 'Process')
        DOTNET_NOLOGO = [Environment]::GetEnvironmentVariable('DOTNET_NOLOGO', 'Process')
        NUGET_PACKAGES = [Environment]::GetEnvironmentVariable('NUGET_PACKAGES', 'Process')
        NUGET_HTTP_CACHE_PATH = [Environment]::GetEnvironmentVariable('NUGET_HTTP_CACHE_PATH', 'Process')
        NUGET_PLUGINS_CACHE_PATH = [Environment]::GetEnvironmentVariable('NUGET_PLUGINS_CACHE_PATH', 'Process')
        POWERSHELL_TELEMETRY_OPTOUT = [Environment]::GetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', 'Process')
        OS = [Environment]::GetEnvironmentVariable('OS', 'Process')
    }
    try {
        $script:ActiveIsolatedUserProfile = $isolatedUserProfile
        $hostRuntimeRoot = Join-Path $script:SuiteRoot '_child-powershell-runtime'
        [void][System.IO.Directory]::CreateDirectory($hostRuntimeRoot)
        [Environment]::SetEnvironmentVariable('USERPROFILE', $isolatedUserProfile, 'Process')
        [Environment]::SetEnvironmentVariable('HOME', $isolatedUserProfile, 'Process')
        [Environment]::SetEnvironmentVariable('CODEX_HOME', $null, 'Process')
        [Environment]::SetEnvironmentVariable('APPDATA', (Join-Path $hostRuntimeRoot 'appdata'), 'Process')
        [Environment]::SetEnvironmentVariable('LOCALAPPDATA', (Join-Path $hostRuntimeRoot 'localappdata'), 'Process')
        [Environment]::SetEnvironmentVariable('XDG_CACHE_HOME', (Join-Path $hostRuntimeRoot 'cache'), 'Process')
        [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', (Join-Path $hostRuntimeRoot 'config'), 'Process')
        [Environment]::SetEnvironmentVariable('XDG_DATA_HOME', (Join-Path $hostRuntimeRoot 'data'), 'Process')
        [Environment]::SetEnvironmentVariable('DOTNET_CLI_HOME', (Join-Path $hostRuntimeRoot 'dotnet'), 'Process')
        [Environment]::SetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT', '1', 'Process')
        [Environment]::SetEnvironmentVariable('DOTNET_NOLOGO', '1', 'Process')
        [Environment]::SetEnvironmentVariable('NUGET_PACKAGES', (Join-Path $hostRuntimeRoot 'nuget-packages'), 'Process')
        [Environment]::SetEnvironmentVariable('NUGET_HTTP_CACHE_PATH', (Join-Path $hostRuntimeRoot 'nuget-http-cache'), 'Process')
        [Environment]::SetEnvironmentVariable('NUGET_PLUGINS_CACHE_PATH', (Join-Path $hostRuntimeRoot 'nuget-plugin-cache'), 'Process')
        [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Process')
        foreach ($runtimeDirectory in @('appdata', 'localappdata', 'cache', 'config', 'data', 'dotnet', 'nuget-packages', 'nuget-http-cache', 'nuget-plugin-cache')) {
            [void][System.IO.Directory]::CreateDirectory((Join-Path $hostRuntimeRoot $runtimeDirectory))
        }
        & $Body $root $isolatedUserProfile
    }
    finally {
        $script:ActiveIsolatedUserProfile = $savedActiveIsolatedUserProfile
        Restore-ProcessEnvironment -Saved $saved
    }
}

function Invoke-Installer {
    param([string[]]$Arguments)
    $allArguments = @('-NoLogo', '-NoProfile', '-File', $script:InstallerPath) + @($Arguments)
    $savedErrorActionPreference = $ErrorActionPreference
    $nativePreferenceVariable = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $hasNativePreference = $null -ne $nativePreferenceVariable
    if ($hasNativePreference) {
        $savedNativePreference = $nativePreferenceVariable.Value
    }
    try {
        $ErrorActionPreference = 'Continue'
        if ($hasNativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false -Scope Local
        }
        $output = @(& $script:PowerShellExecutable @allArguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
        if ($hasNativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $savedNativePreference -Scope Local
        }
    }
    return (New-Object PSObject -Property @{
        ExitCode = $exitCode
        Output = ($output | Out-String)
    })
}

function Invoke-PowerShellFile {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [string[]]$Arguments = @()
    )
    $savedErrorActionPreference = $ErrorActionPreference
    $nativePreferenceVariable = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $hasNativePreference = $null -ne $nativePreferenceVariable
    if ($hasNativePreference) { $savedNativePreference = $nativePreferenceVariable.Value }
    try {
        $ErrorActionPreference = 'Continue'
        if ($hasNativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false -Scope Local
        }
        $output = @(& $script:PowerShellExecutable -NoLogo -NoProfile -File $LiteralPath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
        if ($hasNativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $savedNativePreference -Scope Local
        }
    }
    return (New-Object PSObject -Property @{
        ExitCode = $exitCode
        Output = ($output | Out-String)
    })
}

function Get-TreeFingerprint {
    param([string]$LiteralPath)
    $root = [System.IO.Path]::GetFullPath($LiteralPath).TrimEnd([char[]]@('\', '/'))
    $ignoredRuntimeDirectories = @()
    $ignoredRuntimeFiles = @()
    if (-not [string]::IsNullOrWhiteSpace($script:ActiveIsolatedUserProfile)) {
        $ignoredRuntimeDirectories = @(
            'AppData',
            'AppData/Local',
            'AppData/Local/Microsoft',
            'AppData/Local/Microsoft/PowerShell',
            'AppData/Local/Microsoft/Windows',
            'AppData/Local/Microsoft/Windows/PowerShell'
        ) | ForEach-Object {
            [System.IO.Path]::GetFullPath((Join-Path $script:ActiveIsolatedUserProfile $_))
        }
        $ignoredRuntimeFiles = @(
            'AppData/Local/Microsoft/PowerShell/StartupProfileData-NonInteractive',
            'AppData/Local/Microsoft/Windows/PowerShell/StartupProfileData-NonInteractive'
        ) | ForEach-Object {
            [System.IO.Path]::GetFullPath((Join-Path $script:ActiveIsolatedUserProfile $_))
        }
    }
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($item in @(Get-ChildItem -LiteralPath $root -Force -Recurse | Sort-Object FullName)) {
        $isIgnoredRuntimeEntry = $false
        $ignoredRuntimeEntriesForType = if ($item.PSIsContainer) { $ignoredRuntimeDirectories } else { $ignoredRuntimeFiles }
        foreach ($ignoredRuntimeEntry in $ignoredRuntimeEntriesForType) {
            if ([string]::Equals($item.FullName, $ignoredRuntimeEntry, [System.StringComparison]::OrdinalIgnoreCase)) {
                $isIgnoredRuntimeEntry = $true
                break
            }
        }
        if ($isIgnoredRuntimeEntry) { continue }
        $relative = $item.FullName.Substring($root.Length).TrimStart([char[]]@('\', '/'))
        if ($item.PSIsContainer) {
            $rows.Add('D|' + $relative)
        }
        else {
            $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
            $rows.Add('F|' + $relative + '|' + $item.Length + '|' + $hash)
        }
    }
    return ($rows -join "`n")
}

function Read-JsonFile {
    param([string]$LiteralPath)
    return (Get-Content -LiteralPath $LiteralPath -Raw | ConvertFrom-Json)
}

function Write-JsonFile {
    param([string]$LiteralPath, $Value)
    $parent = Split-Path -Parent $LiteralPath
    [void][System.IO.Directory]::CreateDirectory($parent)
    [System.IO.File]::WriteAllText($LiteralPath, (($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
}

function Get-InstalledSkillNames {
    param([string]$SkillsRoot)
    if (-not (Test-Path -LiteralPath $SkillsRoot -PathType Container)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $SkillsRoot -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
            ForEach-Object { $_.Name } |
            Sort-Object
    )
}

function Assert-ScriptsParse {
    foreach ($path in @($script:InstallerPath, $script:MemoryLauncherPath, $PSCommandPath)) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        Assert-Equal 0 @($errors).Count "PowerShell parser errors in ${path}: $(@($errors) -join '; ')"
    }
}

try {
    [void][System.IO.Directory]::CreateDirectory($script:SuiteRoot)

    Invoke-Contract 'PowerShell sources parse and avoid forbidden execution surfaces' {
        Assert-True (Test-Path -LiteralPath $script:InstallerPath -PathType Leaf) 'install.ps1 is missing'
        Assert-True (Test-Path -LiteralPath $script:MemoryLauncherPath -PathType Leaf) 'Memory Graph PowerShell launcher is missing'
        Assert-ScriptsParse
        $combined = [System.IO.File]::ReadAllText($script:InstallerPath) + "`n" + [System.IO.File]::ReadAllText($script:MemoryLauncherPath)
        foreach ($forbidden in @('Invoke-Expression', 'Set-ExecutionPolicy', 'ExecutionPolicy Bypass', 'Start-Process -Verb RunAs', 'ItemType SymbolicLink')) {
            Assert-NotContains $combined $forbidden "Forbidden PowerShell surface found: $forbidden"
        }
        Assert-Contains $combined '-LiteralPath' 'Literal-path operations are not present'
        Assert-Contains $combined 'ConvertTo-Json -Depth 100' 'Deep JSON preservation is not explicit'
    }

    Invoke-Contract 'atomic replacement keeps the exclusive temporary handle through private DACL creation and content write' {
        $installer = [System.IO.File]::ReadAllText($script:InstallerPath)
        $helperStart = $installer.IndexOf('function New-PrivateFileSecurity', [System.StringComparison]::Ordinal)
        $functionStart = $installer.IndexOf('function Write-AtomicText', [System.StringComparison]::Ordinal)
        $functionEnd = $installer.IndexOf('function Clear-ManagedDirectory', $functionStart, [System.StringComparison]::Ordinal)
        Assert-True ($helperStart -ge 0 -and $helperStart -lt $functionStart) 'Private temporary-file ACL helper was not found before Write-AtomicText'
        Assert-True ($functionStart -ge 0 -and $functionEnd -gt $functionStart) 'Write-AtomicText function boundary was not found'
        $aclSupportBody = $installer.Substring(0, $functionStart)
        $helperBody = $installer.Substring($helperStart, $functionStart - $helperStart)
        $functionBody = $installer.Substring($functionStart, $functionEnd - $functionStart)
        Assert-Contains $helperBody 'SetAccessRuleProtection($true, $false)' 'Temporary-file DACL is not protected from inherited access'
        Assert-Contains $helperBody '[System.Security.AccessControl.FileSystemRights]::FullControl' 'Temporary-file DACL does not grant the installing user full control'
        Assert-Contains $helperBody '[System.Security.Principal.WindowsIdentity]::GetCurrent().User' 'Temporary-file DACL is not scoped to the installing user'
        Assert-Contains $helperBody '$rules.Count -ne 1' 'Temporary-file DACL verification does not reject additional access rules'
        Assert-Contains $helperBody '-not $rule.IsInherited' 'Temporary-file DACL verification permits inherited access'
        Assert-Contains $aclSupportBody 'New-SecuredCreateNewStream' 'Atomic replacement lacks a cross-runtime secure-create helper'
        Assert-Contains $aclSupportBody 'FileSystemAclExtensions' 'Atomic replacement lacks the modern .NET secure-create path'
        Assert-Contains $aclSupportBody '[System.IO.FileInfo]::new($LiteralPath)' 'PowerShell 7 secure creation can pass a wrapped PSObject to the reflected FileInfo parameter'
        Assert-Contains $aclSupportBody '[object[]]::new(7)' 'PowerShell 7 secure creation does not build a raw typed reflection argument array'
        $createIndex = $aclSupportBody.IndexOf('[System.IO.FileMode]::CreateNew', [System.StringComparison]::Ordinal)
        $secureCreateIndex = $functionBody.IndexOf('New-SecuredCreateNewStream', [System.StringComparison]::Ordinal)
        $aclIndex = $functionBody.IndexOf('Get-FileStreamAcl -Stream $stream', $secureCreateIndex, [System.StringComparison]::Ordinal)
        $writeIndex = $functionBody.IndexOf('$writer.Write($Content)', [System.StringComparison]::Ordinal)
        $closeIndex = $functionBody.IndexOf('$stream.Dispose()', $writeIndex, [System.StringComparison]::Ordinal)
        $metadataPolicyIndex = $functionBody.IndexOf('$ignoreMetadataErrors = -not $preserveWindowsAcl', [System.StringComparison]::Ordinal)
        $replaceIndex = $functionBody.IndexOf('[System.IO.File]::Replace($tempPath, $fullPath, $backupPath, $ignoreMetadataErrors)', [System.StringComparison]::Ordinal)
        $verifyIndex = $functionBody.IndexOf('$committedAcl = Get-FileStreamAcl -Stream $committedStream', $replaceIndex, [System.StringComparison]::Ordinal)
        Assert-True ($createIndex -ge 0 -and $secureCreateIndex -ge 0) 'Atomic replacement does not create its secured temporary file exclusively'
        Assert-True ($aclIndex -gt $secureCreateIndex) 'Atomic replacement does not verify the private DACL through the exclusive CreateNew handle'
        Assert-True ($writeIndex -ge 0) 'Atomic replacement content write was not found'
        $identityBoundWindow = $functionBody.Substring($secureCreateIndex, ($writeIndex + '$writer.Write($Content)'.Length) - $secureCreateIndex)
        Assert-NotContains $identityBoundWindow '$stream.Dispose()' 'Atomic replacement closes the exclusive CreateNew handle before its content write'
        Assert-NotContains $identityBoundWindow '[System.IO.FileMode]::Open' 'Atomic replacement reopens the temporary path before its content write'
        Assert-True ($closeIndex -gt $writeIndex) 'Atomic replacement does not close its identity-bound handle after the content write'
        Assert-True ($metadataPolicyIndex -gt $writeIndex -and $replaceIndex -gt $metadataPolicyIndex) 'Atomic replacement does not fail closed on Windows ACL merge errors'
        Assert-True ($verifyIndex -gt $replaceIndex) 'Atomic replacement does not verify owner, group, and DACL before deleting the rollback backup'
        Assert-True ($secureCreateIndex -lt $aclIndex -and $aclIndex -lt $writeIndex -and $writeIndex -lt $closeIndex) 'Atomic replacement does not create, verify, write, and close one identity-bound temporary handle in the required order'
    }

    Invoke-Contract 'existing destination restores the exact DACL only through the verified committed handle' {
        $installer = [System.IO.File]::ReadAllText($script:InstallerPath)
        $functionStart = $installer.IndexOf('function Write-AtomicText', [System.StringComparison]::Ordinal)
        $functionEnd = $installer.IndexOf('function Clear-ManagedDirectory', $functionStart, [System.StringComparison]::Ordinal)
        Assert-True ($functionStart -ge 0 -and $functionEnd -gt $functionStart) 'Write-AtomicText function boundary was not found'
        $supportBody = $installer.Substring(0, $functionStart)
        $functionBody = $installer.Substring($functionStart, $functionEnd - $functionStart)
        Assert-Contains $supportBody 'Open-WindowsFileDaclWriteStream' 'Existing-destination commit lacks an exclusive READ_CONTROL and WRITE_DAC handle'
        Assert-Contains $supportBody 'function Set-FileStreamAcl' 'Existing-destination commit lacks a handle-bound DACL setter'
        Assert-Contains $supportBody 'function New-BinaryDaclFileSecurity' 'Existing-destination commit lacks a binary Access-section DACL copy'
        Assert-Contains $supportBody 'private const uint WriteDac = 0x00040000u;' 'Existing-destination mutable handle does not request the Windows WRITE_DAC right explicitly'
        Assert-Contains $supportBody 'return OpenChecked(path, GenericRead | ReadControl | WriteDac, OpenExisting);' 'Existing-destination mutable handle requests the wrong access rights'
        Assert-Contains $supportBody 'return information.NumberOfLinks;' 'Existing-destination mutation cannot reject a replacement object with multiple hard links'
        $setterStart = $supportBody.IndexOf('function Set-FileStreamAcl', [System.StringComparison]::Ordinal)
        $setterEnd = $supportBody.IndexOf('function New-BinaryDaclFileSecurity', $setterStart, [System.StringComparison]::Ordinal)
        $setterBody = $supportBody.Substring($setterStart, $setterEnd - $setterStart)
        Assert-Contains $setterBody '[System.IO.FileStream]$Stream' 'DACL setter is not bound to an open file stream'
        Assert-Contains $setterBody "'SetAccessControl'" 'DACL setter does not use the access-control API'
        Assert-Contains $setterBody '[System.IO.FileStream], [System.Security.AccessControl.FileSecurity]' 'PowerShell 7 DACL setter fallback is not bound to a FileStream'
        Assert-NotContains $setterBody 'Set-Acl' 'DACL setter reopens a path through Set-Acl'
        Assert-NotContains $setterBody '$Stream.Name' 'DACL setter derives a mutable path from the verified handle'
        $daclCopyStart = $supportBody.IndexOf('function New-BinaryDaclFileSecurity', [System.StringComparison]::Ordinal)
        $daclCopyEnd = $supportBody.IndexOf('function Initialize-WindowsFileIdentityInterop', $daclCopyStart, [System.StringComparison]::Ordinal)
        $daclCopyBody = $supportBody.Substring($daclCopyStart, $daclCopyEnd - $daclCopyStart)
        Assert-Contains $daclCopyBody 'GetSecurityDescriptorBinaryForm()' 'Existing-destination DACL copy does not originate from the complete binary descriptor'
        Assert-Contains $daclCopyBody '$daclOnly.SetSecurityDescriptorBinaryForm(' 'Existing-destination DACL copy does not import binary access-control state into the object passed to the setter'
        Assert-Contains $daclCopyBody '[System.Security.AccessControl.AccessControlSections]::Access' 'Existing-destination DACL copy can mutate owner or group instead of only the DACL'
        Assert-Contains $daclCopyBody 'Cannot safely preserve a null DACL' 'Existing-destination DACL copy does not reject a null source DACL'
        Assert-NotContains $daclCopyBody 'GetSecurityDescriptorSddlForm' 'Existing-destination DACL copy round-trips through SDDL and may lose opaque ACE data'
        Assert-NotContains $daclCopyBody 'SetSecurityDescriptorSddlForm' 'Existing-destination DACL copy imports a lossy SDDL representation'
        Assert-Contains $supportBody 'function Get-OwnerGroupDaclDifferences' 'Existing-destination commit lacks bounded semantic owner, group, and DACL comparison'
        Assert-Contains $supportBody 'AreAccessRulesProtected' 'Existing-destination DACL comparison does not preserve inheritance protection'
        Assert-Contains $supportBody 'AreAccessRulesCanonical' 'Existing-destination DACL comparison does not fail closed for noncanonical rules'
        Assert-Contains $supportBody '$Dacl.GetBinaryForm($binary, 0)' 'Existing-destination DACL comparison does not preserve ordered complete ACE bytes'
        $comparatorStart = $supportBody.IndexOf('function Get-OwnerGroupDaclDifferences', [System.StringComparison]::Ordinal)
        $comparatorEnd = $supportBody.IndexOf('function New-PrivateFileSecurity', $comparatorStart, [System.StringComparison]::Ordinal)
        $comparatorBody = $supportBody.Substring($comparatorStart, $comparatorEnd - $comparatorStart)
        Assert-Contains $comparatorBody 'GetSecurityDescriptorBinaryForm()' 'Existing-destination DACL comparison does not begin from the complete binary security descriptor'
        Assert-Contains $comparatorBody '[System.Security.AccessControl.RawSecurityDescriptor]::new($expectedBinary, 0)' 'Existing-destination DACL comparison does not parse the binary descriptor without normalization'
        Assert-NotContains $comparatorBody 'GetSecurityDescriptorSddlForm' 'Existing-destination DACL comparison round-trips through SDDL and may lose opaque ACE data'
        Assert-NotContains $comparatorBody 'Get-OwnerGroupDaclSddl' 'Existing-destination DACL comparison reintroduced the lossy SDDL helper'
        $originalOpenIndex = $functionBody.IndexOf('$originalStream = Open-WindowsFileSecurityStream -LiteralPath $fullPath', [System.StringComparison]::Ordinal)
        $originalBytesIndex = $functionBody.IndexOf('$originalBytes = Read-FileStreamBytes -Stream $originalStream', $originalOpenIndex, [System.StringComparison]::Ordinal)
        $originalAclIndex = $functionBody.IndexOf('$originalAcl = Get-FileStreamAcl -Stream $originalStream', $originalOpenIndex, [System.StringComparison]::Ordinal)
        $originalPreflightIndex = $functionBody.IndexOf('$originalAclIssues = @(Get-OwnerGroupDaclDifferences -Expected $originalAcl -Actual $originalAcl)', $originalAclIndex, [System.StringComparison]::Ordinal)
        $originalCloseIndex = $functionBody.IndexOf('$originalStream.Dispose()', $originalOpenIndex, [System.StringComparison]::Ordinal)
        $replaceIndex = $functionBody.IndexOf('[System.IO.File]::Replace($tempPath, $fullPath, $backupPath, $ignoreMetadataErrors)', [System.StringComparison]::Ordinal)
        $reopenIndex = $functionBody.IndexOf('$committedStream = Open-WindowsFileDaclWriteStream -LiteralPath $fullPath', $replaceIndex, [System.StringComparison]::Ordinal)
        $identityIndex = $functionBody.IndexOf('$committedFileIdentity = Get-WindowsFileIdentity -SafeFileHandle $committedStream.SafeFileHandle', $reopenIndex, [System.StringComparison]::Ordinal)
        $identityVerifyIndex = $functionBody.IndexOf('Test-WindowsFileIdentityEqual -Expected $tempFileIdentity -Actual $committedFileIdentity', $identityIndex, [System.StringComparison]::Ordinal)
        $identityGuardIndex = $functionBody.IndexOf('if (-not $identityMatches) {', $identityVerifyIndex, [System.StringComparison]::Ordinal)
        $identityFailureIndex = $functionBody.IndexOf('throw "Atomic replacement identity verification failed', $identityGuardIndex, [System.StringComparison]::Ordinal)
        $bytesIndex = $functionBody.IndexOf('$committedBytes = Read-FileStreamBytes -Stream $committedStream', $reopenIndex, [System.StringComparison]::Ordinal)
        $bytesGuardIndex = $functionBody.IndexOf('if (-not (Test-ByteArraysEqual -Expected $expectedBytes -Actual $committedBytes)) {', $bytesIndex, [System.StringComparison]::Ordinal)
        $bytesFailureIndex = $functionBody.IndexOf('throw "Atomic replacement content verification failed', $bytesGuardIndex, [System.StringComparison]::Ordinal)
        $linkCountIndex = $functionBody.IndexOf('$committedLinkCount = Get-WindowsFileLinkCount -SafeFileHandle $committedStream.SafeFileHandle', $bytesFailureIndex, [System.StringComparison]::Ordinal)
        $linkCountGuardIndex = $functionBody.IndexOf('if ($committedLinkCount -ne 1) {', $linkCountIndex, [System.StringComparison]::Ordinal)
        $linkCountFailureIndex = $functionBody.IndexOf('throw "Atomic replacement link-count verification failed', $linkCountGuardIndex, [System.StringComparison]::Ordinal)
        $aclReadIndex = $functionBody.IndexOf('$committedAcl = Get-FileStreamAcl -Stream $committedStream', $identityVerifyIndex, [System.StringComparison]::Ordinal)
        $daclCopyIndex = $functionBody.IndexOf('$originalDacl = New-BinaryDaclFileSecurity -ReferenceAcl $originalAcl', $aclReadIndex, [System.StringComparison]::Ordinal)
        $aclSetIndex = $functionBody.IndexOf('Set-FileStreamAcl -Stream $committedStream -Acl $originalDacl', $daclCopyIndex, [System.StringComparison]::Ordinal)
        $appliedAclReadIndex = $functionBody.IndexOf('$appliedAcl = Get-FileStreamAcl -Stream $committedStream', $aclSetIndex, [System.StringComparison]::Ordinal)
        $aclVerifyIndex = $functionBody.IndexOf('$aclDifferences = @(Get-OwnerGroupDaclDifferences -Expected $originalAcl -Actual $appliedAcl)', $appliedAclReadIndex, [System.StringComparison]::Ordinal)
        $closeIndex = $functionBody.IndexOf('$committedStream.Dispose()', $reopenIndex, [System.StringComparison]::Ordinal)
        Assert-True ($originalOpenIndex -ge 0 -and $originalBytesIndex -gt $originalOpenIndex -and $originalBytesIndex -lt $originalCloseIndex -and $originalAclIndex -gt $originalOpenIndex -and $originalPreflightIndex -gt $originalAclIndex -and $originalPreflightIndex -lt $originalCloseIndex -and $replaceIndex -gt $originalCloseIndex) 'Existing destination does not capture and preflight original bytes and ACL through one handle API before replacement'
        Assert-True ($reopenIndex -gt $replaceIndex) 'Existing destination is not reopened exclusively immediately after replacement'
        Assert-True ($identityIndex -gt $reopenIndex -and $identityVerifyIndex -gt $identityIndex -and $identityGuardIndex -gt $identityVerifyIndex -and $identityFailureIndex -gt $identityGuardIndex) 'Existing destination does not enforce committed identity equality before DACL mutation'
        Assert-True ($bytesIndex -gt $identityFailureIndex -and $bytesGuardIndex -gt $bytesIndex -and $bytesFailureIndex -gt $bytesGuardIndex -and $bytesFailureIndex -lt $aclSetIndex) 'Existing destination does not enforce exact bytes through the same exclusive committed handle before DACL mutation'
        Assert-True ($linkCountIndex -gt $bytesFailureIndex -and $linkCountGuardIndex -gt $linkCountIndex -and $linkCountFailureIndex -gt $linkCountGuardIndex -and $linkCountFailureIndex -lt $aclSetIndex) 'Existing destination does not reject multiple committed hard links before DACL mutation'
        Assert-True ($aclReadIndex -gt $linkCountFailureIndex -and $daclCopyIndex -gt $aclReadIndex -and $aclSetIndex -gt $daclCopyIndex) 'Existing destination does not inspect and restore the original binary DACL only after identity, byte, and link-count verification'
        Assert-True ($appliedAclReadIndex -gt $aclSetIndex -and $aclVerifyIndex -gt $appliedAclReadIndex -and $closeIndex -gt $aclVerifyIndex) 'Existing destination does not read back and exactly verify owner, group, protection, and ordered DACL bytes through the identity-bound committed handle'
        Assert-NotContains $functionBody 'Set-EquivalentFileStreamDacl -Stream $committedStream' 'Existing destination reintroduced a lossy SDDL-based DACL restoration path'
        Assert-NotContains $functionBody 'Set-EquivalentFileAcl -LiteralPath $fullPath' 'Existing destination still performs path-based ACL mutation after the temp handle closes'
        Assert-NotContains $functionBody 'Set-Acl' 'Existing destination performs a path-based DACL mutation inside the atomic write'
        Assert-NotContains $functionBody '[System.IO.File]::SetAccessControl' 'Existing destination performs a path-based .NET DACL mutation inside the atomic write'
    }

    Invoke-Contract 'Windows secure create applies exactly one private current-user ACE through the open handle' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Skip-Contract -Name 'Windows secure create applies exactly one private current-user ACE through the open handle' -Reason 'native Windows secure-create ACL verification requires Windows'
            return
        }
        Use-IsolatedEnvironment 'private secure create' {
            param($root, $isolatedUserProfile)
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:InstallerPath, [ref]$tokens, [ref]$errors)
            Assert-Equal 0 @($errors).Count "PowerShell parser errors prevented private secure-create verification: $(@($errors) -join '; ')"
            $functionSource = @(
                $ast.FindAll({
                    param($node)
                    return $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true) | ForEach-Object { $_.Extent.Text }
            ) -join "`r`n`r`n"
            $runnerPath = Join-Path $root 'private secure create runner.ps1'
            $runnerSource = @'
#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

__INSTALLER_FUNCTIONS__

function Assert-PrivateAclInvariant {
    param([Parameter(Mandatory = $true)]$Acl)
    if (-not $Acl.AreAccessRulesProtected) {
        throw 'Private secure-create DACL is not protected.'
    }
    $rules = @($Acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    if ($rules.Count -ne 1) {
        throw "Private secure-create DACL has $($rules.Count) access rules instead of exactly one."
    }
    $rule = $rules[0]
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($rule.IdentityReference -ne $currentUser -or
        $rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow -or
        $rule.FileSystemRights -ne [System.Security.AccessControl.FileSystemRights]::FullControl -or
        $rule.InheritanceFlags -ne [System.Security.AccessControl.InheritanceFlags]::None -or
        $rule.PropagationFlags -ne [System.Security.AccessControl.PropagationFlags]::None -or
        $rule.IsInherited) {
        throw 'Private secure-create DACL is not one explicit current-user FullControl allow rule.'
    }
}

function New-SddlFileSecurity {
    param([Parameter(Mandatory = $true)][string]$Sddl)
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetSecurityDescriptorSddlForm($Sddl, (Get-OwnerGroupDaclSections))
    return $acl
}

function New-RawDaclFileSecurity {
    param(
        [AllowNull()][System.Security.AccessControl.RawAcl]$Dacl,
        [System.Security.AccessControl.ControlFlags]$AdditionalControlFlags = [System.Security.AccessControl.ControlFlags]::None
    )
    $controlFlags = $AdditionalControlFlags
    if ($null -ne $Dacl) {
        $controlFlags = [System.Security.AccessControl.ControlFlags]::DiscretionaryAclPresent -bor $controlFlags
    }
    $descriptor = [System.Security.AccessControl.RawSecurityDescriptor]::new(
        $controlFlags,
        $currentUser,
        $currentUser,
        $null,
        $Dacl
    )
    $binary = [byte[]]::new($descriptor.BinaryLength)
    $descriptor.GetBinaryForm($binary, 0)
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetSecurityDescriptorBinaryForm($binary, (Get-OwnerGroupDaclSections))
    return $acl
}

function Assert-AclDifferenceCategory {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$Category
    )
    $differences = @(Get-OwnerGroupDaclDifferences -Expected $Expected -Actual $Actual)
    if ($differences -notcontains $Category) {
        throw "ACL comparator did not report ${Category}. Categories: $($differences -join ', ')"
    }
}

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$currentSid = $currentUser.Value
$alternateOwner = if ($currentSid -cne 'S-1-5-18') { 'S-1-5-18' } else { 'S-1-5-32-544' }
$alternateGroup = if ($currentSid -cne 'S-1-5-32-545') { 'S-1-5-32-545' } else { 'S-1-5-32-544' }
$descriptorPrefix = 'O:' + $currentSid + 'G:' + $currentSid
$fullControlAce = '(A;;FA;;;' + $currentSid + ')'
$controlFlagDacl = [System.Security.AccessControl.RawAcl]::new([byte]2, 1)
$controlFlagDacl.InsertAce(0, [System.Security.AccessControl.CommonAce]::new(
    [System.Security.AccessControl.AceFlags]::None,
    [System.Security.AccessControl.AceQualifier]::AccessAllowed,
    [int][System.Security.AccessControl.FileSystemRights]::FullControl,
    $currentUser,
    $false,
    $null
))
$expectedAcl = New-RawDaclFileSecurity -Dacl $controlFlagDacl -AdditionalControlFlags ([System.Security.AccessControl.ControlFlags]::DiscretionaryAclAutoInherited)
$controlFlagVariant = New-RawDaclFileSecurity -Dacl $controlFlagDacl
$expectedControlBinary = [Convert]::ToBase64String($expectedAcl.GetSecurityDescriptorBinaryForm())
$actualControlBinary = [Convert]::ToBase64String($controlFlagVariant.GetSecurityDescriptorBinaryForm())
if ($expectedControlBinary -ceq $actualControlBinary) {
    throw 'Benign auto-inheritance bookkeeping fixture did not produce distinct binary descriptors.'
}
if (@(Get-OwnerGroupDaclDifferences -Expected $expectedAcl -Actual $controlFlagVariant).Count -ne 0) {
    throw 'ACL comparator rejected an otherwise identical DACL because of benign auto-inheritance bookkeeping.'
}
$nullDaclVariant = New-RawDaclFileSecurity -Dacl $null
Assert-AclDifferenceCategory -Expected $controlFlagVariant -Actual $nullDaclVariant -Category 'null_dacl'
$ownerVariant = New-SddlFileSecurity -Sddl ('O:' + $alternateOwner + 'G:' + $currentSid + 'D:' + $fullControlAce)
Assert-AclDifferenceCategory -Expected $controlFlagVariant -Actual $ownerVariant -Category 'owner'
$groupVariant = New-SddlFileSecurity -Sddl ('O:' + $currentSid + 'G:' + $alternateGroup + 'D:' + $fullControlAce)
Assert-AclDifferenceCategory -Expected $controlFlagVariant -Actual $groupVariant -Category 'group'
$protectedVariant = New-SddlFileSecurity -Sddl ($descriptorPrefix + 'D:P' + $fullControlAce)
Assert-AclDifferenceCategory -Expected $controlFlagVariant -Actual $protectedVariant -Category 'protection'
$rightsVariant = New-SddlFileSecurity -Sddl ($descriptorPrefix + 'D:(A;;FR;;;' + $currentSid + ')')
Assert-AclDifferenceCategory -Expected $controlFlagVariant -Actual $rightsVariant -Category 'dacl'

$callbackAclA = [System.Security.AccessControl.RawAcl]::new([byte]2, 1)
$callbackAclB = [System.Security.AccessControl.RawAcl]::new([byte]2, 1)
$callbackAclA.InsertAce(0, [System.Security.AccessControl.CommonAce]::new(
    [System.Security.AccessControl.AceFlags]::None,
    [System.Security.AccessControl.AceQualifier]::AccessAllowed,
    1,
    $currentUser,
    $true,
    [byte[]]@(1, 2, 3, 4)
))
$callbackAclB.InsertAce(0, [System.Security.AccessControl.CommonAce]::new(
    [System.Security.AccessControl.AceFlags]::None,
    [System.Security.AccessControl.AceQualifier]::AccessAllowed,
    1,
    $currentUser,
    $true,
    [byte[]]@(1, 2, 3, 5)
))
$callbackSecurityA = New-RawDaclFileSecurity -Dacl $callbackAclA
$callbackSecurityB = New-RawDaclFileSecurity -Dacl $callbackAclB
Assert-AclDifferenceCategory -Expected $callbackSecurityA -Actual $callbackSecurityB -Category 'dacl'

$builtInUsers = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
$inheritedCurrentUserAce = [System.Security.AccessControl.CommonAce]::new(
    [System.Security.AccessControl.AceFlags]::Inherited,
    [System.Security.AccessControl.AceQualifier]::AccessAllowed,
    1,
    $currentUser,
    $false,
    $null
)
$inheritedUsersAce = [System.Security.AccessControl.CommonAce]::new(
    [System.Security.AccessControl.AceFlags]::Inherited,
    [System.Security.AccessControl.AceQualifier]::AccessAllowed,
    2,
    $builtInUsers,
    $false,
    $null
)
$orderedAcl = [System.Security.AccessControl.RawAcl]::new([byte]2, 2)
$orderedAcl.InsertAce(0, $inheritedCurrentUserAce)
$orderedAcl.InsertAce(1, $inheritedUsersAce)
$reorderedAcl = [System.Security.AccessControl.RawAcl]::new([byte]2, 2)
$reorderedAcl.InsertAce(0, $inheritedUsersAce)
$reorderedAcl.InsertAce(1, $inheritedCurrentUserAce)
$orderedSecurity = New-RawDaclFileSecurity -Dacl $orderedAcl
$reorderedSecurity = New-RawDaclFileSecurity -Dacl $reorderedAcl
Assert-AclDifferenceCategory -Expected $orderedSecurity -Actual $reorderedSecurity -Category 'dacl'

$path = $env:ASSISTANT_FRAMEWORK_PRIVATE_CREATE_TARGET
$privateFileSecurity = New-PrivateFileSecurity
Assert-PrivateAclInvariant -Acl $privateFileSecurity
$stream = $null
try {
    $stream = New-SecuredCreateNewStream -LiteralPath $path -FileSecurity $privateFileSecurity
    if ($stream -isnot [System.IO.FileStream]) {
        throw "Secure-create returned an unexpected type: $($stream.GetType().FullName)"
    }
    Assert-PrivateAclInvariant -Acl (Get-FileStreamAcl -Stream $stream)
    $stream.WriteByte(65)
    $stream.Flush($true)
}
finally {
    if ($null -ne $stream) { $stream.Dispose() }
}
if ([System.IO.File]::ReadAllBytes($path).Length -ne 1) {
    throw 'Secure-created stream was not writable through the original handle.'
}
[System.IO.File]::Delete($path)
'private secure create passed'
'@
            $runnerSource = $runnerSource.Replace('__INSTALLER_FUNCTIONS__', $functionSource)
            [System.IO.File]::WriteAllText($runnerPath, $runnerSource, (New-Object System.Text.UTF8Encoding($false)))
            $target = Join-Path $root 'private secure create target.txt'
            $savedTarget = [Environment]::GetEnvironmentVariable('ASSISTANT_FRAMEWORK_PRIVATE_CREATE_TARGET', 'Process')
            try {
                [Environment]::SetEnvironmentVariable('ASSISTANT_FRAMEWORK_PRIVATE_CREATE_TARGET', $target, 'Process')
                $result = Invoke-PowerShellFile -LiteralPath $runnerPath
                Assert-Equal 0 $result.ExitCode "Private secure-create runner failed: $($result.Output)"
                Assert-False (Test-Path -LiteralPath $target) 'Private secure-create runner left its probe file behind'
            }
            finally {
                [Environment]::SetEnvironmentVariable('ASSISTANT_FRAMEWORK_PRIVATE_CREATE_TARGET', $savedTarget, 'Process')
            }
        }
    }

    Invoke-Contract 'Windows first-install atomic commit verifies stable identity bytes and owner group DACL through one destination handle' {
        $installer = [System.IO.File]::ReadAllText($script:InstallerPath)
        $functionStart = $installer.IndexOf('function Write-AtomicText', [System.StringComparison]::Ordinal)
        $functionEnd = $installer.IndexOf('function Clear-ManagedDirectory', $functionStart, [System.StringComparison]::Ordinal)
        Assert-True ($functionStart -ge 0 -and $functionEnd -gt $functionStart) 'Write-AtomicText function boundary was not found'
        $identitySupportBody = $installer.Substring(0, $functionStart)
        $functionBody = $installer.Substring($functionStart, $functionEnd - $functionStart)

        Assert-Contains $identitySupportBody 'CreateFileW' 'Windows file identity support does not reopen the committed destination without following a substituted path entry'
        Assert-Contains $identitySupportBody 'GetFileInformationByHandle' 'Windows file identity support does not query stable volume and file-index identity from an open handle'
        Assert-Contains $identitySupportBody 'Microsoft.Win32.SafeHandles.SafeFileHandle' 'Windows file identity support does not own native handles safely across PowerShell 5.1 and PowerShell 7'
        Assert-Contains $identitySupportBody 'const uint' 'Windows file identity P/Invoke declarations do not keep their native constants dependency-free and immutable'
        Assert-Contains $identitySupportBody 'Add-Type -TypeDefinition' 'Windows file identity support is not compiled from a dependency-free constant P/Invoke bridge'

        $createIndex = $functionBody.IndexOf('[System.IO.FileMode]::CreateNew', [System.StringComparison]::Ordinal)
        $captureIdentityIndex = $functionBody.IndexOf('$tempFileIdentity = Get-WindowsFileIdentity -SafeFileHandle $stream.SafeFileHandle', $createIndex, [System.StringComparison]::Ordinal)
        $captureAclIndex = $functionBody.IndexOf('$openedTempAcl = Get-FileStreamAcl -Stream $stream', $createIndex, [System.StringComparison]::Ordinal)
        $closeIndex = $functionBody.IndexOf('$stream = $null', $createIndex, [System.StringComparison]::Ordinal)
        $moveIndex = $functionBody.IndexOf('[System.IO.File]::Move($tempPath, $fullPath)', $closeIndex, [System.StringComparison]::Ordinal)
        $reopenIndex = $functionBody.IndexOf('$committedStream = Open-WindowsFileReadStream -LiteralPath $fullPath', $moveIndex, [System.StringComparison]::Ordinal)
        $committedIdentityIndex = $functionBody.IndexOf('$committedFileIdentity = Get-WindowsFileIdentity -SafeFileHandle $committedStream.SafeFileHandle', $reopenIndex, [System.StringComparison]::Ordinal)
        $identityVerifyIndex = $functionBody.IndexOf('Test-WindowsFileIdentityEqual -Expected $tempFileIdentity -Actual $committedFileIdentity', $committedIdentityIndex, [System.StringComparison]::Ordinal)
        $bytesReadIndex = $functionBody.IndexOf('$committedBytes = Read-FileStreamBytes -Stream $committedStream', $reopenIndex, [System.StringComparison]::Ordinal)
        $aclReadIndex = $functionBody.IndexOf('$committedAcl = Get-FileStreamAcl -Stream $committedStream', $reopenIndex, [System.StringComparison]::Ordinal)
        $aclVerifyIndex = $functionBody.IndexOf('$aclDifferences = @(Get-OwnerGroupDaclDifferences -Expected $openedTempAcl -Actual $committedAcl)', $aclReadIndex, [System.StringComparison]::Ordinal)
        $committedCloseIndex = $functionBody.IndexOf('$committedStream.Dispose()', $reopenIndex, [System.StringComparison]::Ordinal)

        Assert-True ($captureIdentityIndex -gt $createIndex -and $captureIdentityIndex -lt $closeIndex) 'First-install atomic write does not capture the created temporary file identity through its still-open handle'
        Assert-True ($captureAclIndex -gt $createIndex -and $captureAclIndex -lt $closeIndex) 'First-install atomic write does not capture the created temporary file owner, group, and DACL through its still-open handle'
        Assert-True ($moveIndex -gt $closeIndex) 'First-install atomic write does not move the verified temporary file into the destination after closing its write handle'
        Assert-True ($reopenIndex -gt $moveIndex) 'First-install atomic write does not reopen the committed destination exclusively after its move'
        Assert-True ($committedIdentityIndex -gt $reopenIndex -and $identityVerifyIndex -gt $committedIdentityIndex) 'First-install atomic write does not verify that the committed destination is the same Windows file object created through the temporary handle'
        Assert-True ($bytesReadIndex -gt $reopenIndex -and $bytesReadIndex -lt $committedCloseIndex) 'First-install atomic write does not verify exact bytes through the exclusive committed-destination handle'
        Assert-True ($aclReadIndex -gt $reopenIndex -and $aclVerifyIndex -gt $aclReadIndex -and $aclVerifyIndex -lt $committedCloseIndex) 'First-install atomic write does not verify complete binary owner, group, and DACL semantics through the exclusive committed-destination handle'
        Assert-NotContains $functionBody '$tempAccessSddl' 'First-install atomic write still retains a lossy SDDL representation for committed-handle comparison'
        Assert-True ($committedCloseIndex -gt $identityVerifyIndex -and $committedCloseIndex -gt $bytesReadIndex -and $committedCloseIndex -gt $aclReadIndex) 'First-install atomic write closes the committed-destination handle before all identity, byte, and owner/group/DACL checks finish'

        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Skip-Contract -Name 'Windows first-install atomic commit verifies stable identity bytes and owner group DACL through one destination handle' -Reason 'native first-install identity verification requires Windows'
            return
        }
        Use-IsolatedEnvironment 'atomic first install normal path' {
            param($root, $isolatedUserProfile)
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:InstallerPath, [ref]$tokens, [ref]$errors)
            Assert-Equal 0 @($errors).Count "PowerShell parser errors prevented first-install atomic verification: $(@($errors) -join '; ')"
            $functionSource = @(
                $ast.FindAll({
                    param($node)
                    return $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true) | ForEach-Object { $_.Extent.Text }
            ) -join "`r`n`r`n"
            $runnerPath = Join-Path $root 'atomic first install runner.ps1'
            $runnerSource = @'
#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

__INSTALLER_FUNCTIONS__

$target = $env:ASSISTANT_FRAMEWORK_ATOMIC_FIRST_INSTALL_TARGET
$reference = Join-Path (Split-Path -Parent $target) 'first-install-reference.txt'
[System.IO.File]::WriteAllText($reference, 'reference', $script:Utf8NoBom)
$referenceAccessSddl = Get-OwnerGroupDaclSddl -Acl (Get-Acl -LiteralPath $reference)
$expectedContent = "first-install bytes`r`n"
Write-AtomicText -LiteralPath $target -Content $expectedContent
if ([System.IO.File]::ReadAllText($target) -cne $expectedContent) {
    throw 'First-install atomic write did not commit the exact requested bytes.'
}
$committedAccessSddl = Get-OwnerGroupDaclSddl -Acl (Get-Acl -LiteralPath $target)
if ($committedAccessSddl -cne $referenceAccessSddl) {
    throw "First-install atomic write changed inherited owner, group, or DACL.`nExpected: $referenceAccessSddl`nActual: $committedAccessSddl"
}
$debris = @(Get-ChildItem -LiteralPath (Split-Path -Parent $target) -Force | Where-Object { $_.Name -like '.assistant-framework-*' })
if ($debris.Count -ne 0) {
    throw "First-install atomic write left temporary debris: $($debris.Name -join ', ')"
}
'atomic first-install normal path passed'
'@
            $runnerSource = $runnerSource.Replace('__INSTALLER_FUNCTIONS__', $functionSource)
            [System.IO.File]::WriteAllText($runnerPath, $runnerSource, (New-Object System.Text.UTF8Encoding($false)))
            $target = Join-Path $root 'atomic first install target.txt'
            $savedTarget = [Environment]::GetEnvironmentVariable('ASSISTANT_FRAMEWORK_ATOMIC_FIRST_INSTALL_TARGET', 'Process')
            try {
                [Environment]::SetEnvironmentVariable('ASSISTANT_FRAMEWORK_ATOMIC_FIRST_INSTALL_TARGET', $target, 'Process')
                $result = Invoke-PowerShellFile -LiteralPath $runnerPath
                Assert-Equal 0 $result.ExitCode "First-install atomic normal-path runner failed: $($result.Output)"
            }
            finally {
                [Environment]::SetEnvironmentVariable('ASSISTANT_FRAMEWORK_ATOMIC_FIRST_INSTALL_TARGET', $savedTarget, 'Process')
            }
        }
    }

    Invoke-Contract 'atomic rollback restores and verifies original bytes and owner group DACL before recovery cleanup' {
        $installer = [System.IO.File]::ReadAllText($script:InstallerPath)
        $functionStart = $installer.IndexOf('function Write-AtomicText', [System.StringComparison]::Ordinal)
        $functionEnd = $installer.IndexOf('function Clear-ManagedDirectory', $functionStart, [System.StringComparison]::Ordinal)
        Assert-True ($functionStart -ge 0 -and $functionEnd -gt $functionStart) 'Write-AtomicText function boundary was not found'
        $functionBody = $installer.Substring($functionStart, $functionEnd - $functionStart)
        $replaceIndex = $functionBody.IndexOf('[System.IO.File]::Replace($tempPath, $fullPath, $backupPath, $ignoreMetadataErrors)', [System.StringComparison]::Ordinal)
        $rollbackStart = $functionBody.IndexOf('catch {', $replaceIndex, [System.StringComparison]::Ordinal)
        $rollbackEnd = $functionBody.IndexOf('throw $replacementError', $rollbackStart, [System.StringComparison]::Ordinal)
        Assert-True ($replaceIndex -ge 0 -and $rollbackStart -gt $replaceIndex -and $rollbackEnd -gt $rollbackStart) 'Atomic replacement rollback boundary was not found'
        $rollbackBody = $functionBody.Substring($rollbackStart, $rollbackEnd - $rollbackStart)
        Assert-Contains $functionBody '$originalBytes' 'Atomic replacement does not retain the original bytes for rollback verification'
        Assert-NotContains $rollbackBody '[System.IO.File]::Replace($backupPath, $fullPath' 'Atomic rollback merges failed destination metadata into the original backup'
        Assert-Contains $rollbackBody '[System.IO.File]::Move($backupPath, $fullPath)' 'Atomic rollback does not restore the original backup file by metadata-preserving move'
        Assert-Contains $rollbackBody '$restoredBytes' 'Atomic rollback does not read back restored bytes before cleanup'
        Assert-Contains $rollbackBody '$restoredAcl' 'Atomic rollback does not read back restored owner, group, and DACL before cleanup'
        Assert-Contains $rollbackBody '$restoredStream = Open-WindowsFileSecurityStream -LiteralPath $fullPath' 'Atomic rollback does not capture restored bytes and ACL through the same handle API as the original snapshot'
        Assert-Contains $rollbackBody 'Get-OwnerGroupDaclDifferences -Expected $originalAcl -Actual $restoredAcl' 'Atomic rollback verifies owner, group, and DACL through a lossy representation instead of the binary comparator'
        $byteVerifyIndex = $rollbackBody.IndexOf('$restoredBytes', [System.StringComparison]::Ordinal)
        $aclVerifyIndex = $rollbackBody.IndexOf('$restoredAcl', [System.StringComparison]::Ordinal)
        $recoveryDeleteIndex = $rollbackBody.IndexOf('[System.IO.File]::Delete($rollbackDiscard)', [System.StringComparison]::Ordinal)
        $releaseBackupIndex = $rollbackBody.IndexOf('$retainBackupOnFailure = $false', [System.StringComparison]::Ordinal)
        Assert-True ($byteVerifyIndex -ge 0 -and $aclVerifyIndex -ge 0) 'Atomic rollback restoration verification is incomplete'
        Assert-True ($recoveryDeleteIndex -gt $byteVerifyIndex -and $recoveryDeleteIndex -gt $aclVerifyIndex) 'Atomic rollback deletes recovery material before restoration verification'
        Assert-True ($releaseBackupIndex -gt $byteVerifyIndex -and $releaseBackupIndex -gt $aclVerifyIndex) 'Atomic rollback releases its recovery backup before restoration verification'
        Assert-Contains $rollbackBody '$recoveryLocations' 'Atomic rollback failure diagnostics do not track recovery locations by state'
        Assert-Contains $rollbackBody '$backupRestored' 'Atomic rollback failure diagnostics do not distinguish a consumed backup from an unverified restored destination'
        Assert-Contains $rollbackBody '$rollbackVerified' 'Atomic rollback diagnostics do not distinguish verified restoration from failed verification or cleanup'
        Assert-Contains $rollbackBody '$diagnosticState = if ($rollbackVerified)' 'Atomic rollback diagnostics do not branch on verified restoration before cleanup failure'
        Assert-Contains $rollbackBody 'The original was restored and verified, but failed-replacement cleanup did not complete.' 'Atomic rollback cleanup failure is mislabeled as restoration-verification failure'
        Assert-Contains $rollbackBody 'Replacement error: $($replacementError.Exception.Message)' 'Atomic rollback diagnostics omit the original replacement failure'
        Assert-Contains $rollbackBody 'Test-Path -LiteralPath $fullPath' 'Atomic rollback diagnostics can report a destination that does not exist'
        Assert-Contains $rollbackBody 'Test-Path -LiteralPath $backupPath' 'Atomic rollback diagnostics can report a backup that does not exist'
        Assert-Contains $rollbackBody 'Test-Path -LiteralPath $rollbackDiscard' 'Atomic rollback diagnostics can report a failed-replacement artifact that does not exist'
    }

    Invoke-Contract 'post-replace ACL failure restores original bytes and owner group DACL on Windows' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Skip-Contract -Name 'post-replace ACL failure restores original bytes and owner group DACL on Windows' -Reason 'native Windows ACL fault injection requires Windows'
            return
        }
        Use-IsolatedEnvironment 'atomic rollback fault injection' {
            param($root, $isolatedUserProfile)
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:InstallerPath, [ref]$tokens, [ref]$errors)
            Assert-Equal 0 @($errors).Count "PowerShell parser errors prevented atomic rollback fault injection: $(@($errors) -join '; ')"
            $functionSource = @(
                $ast.FindAll({
                    param($node)
                    return $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true) | ForEach-Object { $_.Extent.Text }
            ) -join "`r`n`r`n"
            $runnerPath = Join-Path $root 'atomic rollback fault runner.ps1'
            $runnerSource = @'
#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

__INSTALLER_FUNCTIONS__

$target = $env:ASSISTANT_FRAMEWORK_ATOMIC_FAULT_TARGET
$fixtureBytes = $script:Utf8NoBom.GetBytes("original bytes`r`n")
$fixtureStream = New-SecuredCreateNewStream -LiteralPath $target -FileSecurity (New-PrivateFileSecurity)
try {
    $fixtureStream.Write($fixtureBytes, 0, $fixtureBytes.Length)
    $fixtureStream.Flush($true)
    $expectedAcl = Get-FileStreamAcl -Stream $fixtureStream
}
finally {
    $fixtureStream.Dispose()
}

$script:OriginalGetFileStreamAcl = ${function:Get-FileStreamAcl}
$script:OriginalSetFileStreamAcl = ${function:Set-FileStreamAcl}
$script:FileStreamAclReadCount = 0
$script:FileStreamAclSetCount = 0
$script:AclReadIdentities = New-Object 'System.Collections.Generic.List[string]'
$script:AclSetIdentities = New-Object 'System.Collections.Generic.List[string]'
$script:InjectedAclReadNumbers = @(3)
function Get-FileStreamAcl {
    param([Parameter(Mandatory = $true)][System.IO.FileStream]$Stream)
    $script:FileStreamAclReadCount++
    $script:AclReadIdentities.Add((Get-WindowsFileIdentity -SafeFileHandle $Stream.SafeFileHandle))
    $acl = & $script:OriginalGetFileStreamAcl -Stream $Stream
    if ($script:InjectedAclReadNumbers -contains $script:FileStreamAclReadCount) {
        $builtInUsers = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
        $readRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $builtInUsers,
            [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        [void]$acl.AddAccessRule($readRule)
        & $script:OriginalSetFileStreamAcl -Stream $Stream -Acl $acl
        $acl = & $script:OriginalGetFileStreamAcl -Stream $Stream
    }
    return $acl
}
function Set-FileStreamAcl {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileStream]$Stream,
        [Parameter(Mandatory = $true)][System.Security.AccessControl.FileSecurity]$Acl
    )
    $script:FileStreamAclSetCount++
    $script:AclSetIdentities.Add((Get-WindowsFileIdentity -SafeFileHandle $Stream.SafeFileHandle))
    & $script:OriginalSetFileStreamAcl -Stream $Stream -Acl $Acl
}

Write-AtomicText -LiteralPath $target -Content "first replacement bytes`r`n"
if ($script:FileStreamAclReadCount -ne 4 -or $script:FileStreamAclSetCount -ne 1) {
    throw "Atomic write did not perform one verified DACL repair. ACL reads: $script:FileStreamAclReadCount; writes: $script:FileStreamAclSetCount"
}
if ($script:AclReadIdentities.Count -ne 4 -or
    (Test-WindowsFileIdentityEqual -Expected $script:AclReadIdentities[0] -Actual $script:AclReadIdentities[1]) -or
    -not (Test-WindowsFileIdentityEqual -Expected $script:AclReadIdentities[1] -Actual $script:AclReadIdentities[2]) -or
    -not (Test-WindowsFileIdentityEqual -Expected $script:AclReadIdentities[2] -Actual $script:AclReadIdentities[3]) -or
    -not (Test-WindowsFileIdentityEqual -Expected $script:AclReadIdentities[1] -Actual $script:AclSetIdentities[0])) {
    throw 'Atomic DACL repair did not remain bound to the committed temporary-file identity.'
}
$positiveStream = Open-WindowsFileSecurityStream -LiteralPath $target
try {
    $positiveAcl = & $script:OriginalGetFileStreamAcl -Stream $positiveStream
}
finally {
    $positiveStream.Dispose()
}
$positiveDifferences = @(Get-OwnerGroupDaclDifferences -Expected $expectedAcl -Actual $positiveAcl)
if ($positiveDifferences.Count -gt 0) {
    throw "Atomic DACL repair did not preserve the expected descriptor. Difference categories: $($positiveDifferences -join ', ')"
}

$originalBytes = [System.IO.File]::ReadAllBytes($target)
$script:FileStreamAclReadCount = 0
$script:FileStreamAclSetCount = 0
$script:AclReadIdentities.Clear()
$script:AclSetIdentities.Clear()
$script:InjectedAclReadNumbers = @(3, 4)

$caught = $null
try {
    Write-AtomicText -LiteralPath $target -Content "second replacement bytes`r`n"
}
catch {
    $caught = $_.Exception.Message
}
if ($caught -notlike '*Atomic replacement owner, group, and DACL verification failed*') {
    throw "Atomic write did not surface the injected failure: $caught"
}
if ($script:FileStreamAclReadCount -ne 5 -or $script:FileStreamAclSetCount -ne 1) {
    throw "Atomic write did not inject one post-set ACL mismatch before rollback. ACL reads: $script:FileStreamAclReadCount; writes: $script:FileStreamAclSetCount"
}
if ($script:AclReadIdentities.Count -ne 5 -or
    (Test-WindowsFileIdentityEqual -Expected $script:AclReadIdentities[0] -Actual $script:AclReadIdentities[1]) -or
    -not (Test-WindowsFileIdentityEqual -Expected $script:AclReadIdentities[1] -Actual $script:AclReadIdentities[2]) -or
    -not (Test-WindowsFileIdentityEqual -Expected $script:AclReadIdentities[2] -Actual $script:AclReadIdentities[3]) -or
    -not (Test-WindowsFileIdentityEqual -Expected $script:AclReadIdentities[0] -Actual $script:AclReadIdentities[4]) -or
    -not (Test-WindowsFileIdentityEqual -Expected $script:AclReadIdentities[1] -Actual $script:AclSetIdentities[0])) {
    throw 'Atomic rollback ACL reads or write were not bound to the expected original and committed file identities.'
}
$restoredBytes = [System.IO.File]::ReadAllBytes($target)
if ([Convert]::ToBase64String($restoredBytes) -cne [Convert]::ToBase64String($originalBytes)) {
    throw 'Atomic rollback did not restore the original bytes.'
}
$restoredStream = Open-WindowsFileSecurityStream -LiteralPath $target
try {
    $restoredAcl = & $script:OriginalGetFileStreamAcl -Stream $restoredStream
}
finally {
    $restoredStream.Dispose()
}
$restoredDifferences = @(Get-OwnerGroupDaclDifferences -Expected $expectedAcl -Actual $restoredAcl)
if ($restoredDifferences.Count -gt 0) {
    throw "Atomic rollback did not restore owner, group, and DACL. Difference categories: $($restoredDifferences -join ', ')"
}
$debris = @(Get-ChildItem -LiteralPath (Split-Path -Parent $target) -Force | Where-Object { $_.Name -like '.assistant-framework-*' })
if ($debris.Count -ne 0) {
    throw "Atomic rollback left recovery debris: $($debris.Name -join ', ')"
}
'atomic rollback fault injection passed'
'@
            $runnerSource = $runnerSource.Replace('__INSTALLER_FUNCTIONS__', $functionSource)
            [System.IO.File]::WriteAllText($runnerPath, $runnerSource, (New-Object System.Text.UTF8Encoding($false)))
            $target = Join-Path $root 'atomic rollback target.txt'
            $savedFaultTarget = [Environment]::GetEnvironmentVariable('ASSISTANT_FRAMEWORK_ATOMIC_FAULT_TARGET', 'Process')
            try {
                [Environment]::SetEnvironmentVariable('ASSISTANT_FRAMEWORK_ATOMIC_FAULT_TARGET', $target, 'Process')
                $savedErrorActionPreference = $ErrorActionPreference
                $nativePreferenceVariable = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
                $hasNativePreference = $null -ne $nativePreferenceVariable
                if ($hasNativePreference) { $savedNativePreference = $nativePreferenceVariable.Value }
                try {
                    $ErrorActionPreference = 'Continue'
                    if ($hasNativePreference) { Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false -Scope Local }
                    $output = @(& $script:PowerShellExecutable -NoLogo -NoProfile -File $runnerPath 2>&1)
                    $exitCode = $LASTEXITCODE
                }
                finally {
                    $ErrorActionPreference = $savedErrorActionPreference
                    if ($hasNativePreference) { Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $savedNativePreference -Scope Local }
                }
                Assert-Equal 0 $exitCode "Atomic rollback fault-injection runner failed: $($output | Out-String)"
            }
            finally {
                [Environment]::SetEnvironmentVariable('ASSISTANT_FRAMEWORK_ATOMIC_FAULT_TARGET', $savedFaultTarget, 'Process')
            }
        }
    }

    Invoke-Contract 'rollback verification failure reports only recovery paths that still exist' {
        $installer = [System.IO.File]::ReadAllText($script:InstallerPath)
        $functionStart = $installer.IndexOf('function Write-AtomicText', [System.StringComparison]::Ordinal)
        $functionEnd = $installer.IndexOf('function Clear-ManagedDirectory', $functionStart, [System.StringComparison]::Ordinal)
        Assert-True ($functionStart -ge 0 -and $functionEnd -gt $functionStart) 'Write-AtomicText function boundary was not found'
        $functionBody = $installer.Substring($functionStart, $functionEnd - $functionStart)
        Assert-NotContains $functionBody 'Original backup: $backupPath. Failed replacement: $rollbackDiscard.' 'Atomic rollback diagnostics unconditionally report backup and failed-replacement paths after those paths may have moved or disappeared'

        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Skip-Contract -Name 'rollback verification failure reports only recovery paths that still exist' -Reason 'native rollback verification fault injection requires Windows'
            return
        }
        Use-IsolatedEnvironment 'atomic rollback diagnostic fault injection' {
            param($root, $isolatedUserProfile)
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:InstallerPath, [ref]$tokens, [ref]$errors)
            Assert-Equal 0 @($errors).Count "PowerShell parser errors prevented rollback diagnostic fault injection: $(@($errors) -join '; ')"
            $functionSource = @(
                $ast.FindAll({
                    param($node)
                    return $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true) | ForEach-Object { $_.Extent.Text }
            ) -join "`r`n`r`n"
            $runnerPath = Join-Path $root 'atomic rollback diagnostic runner.ps1'
            $runnerSource = @'
#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

__INSTALLER_FUNCTIONS__

$target = $env:ASSISTANT_FRAMEWORK_ATOMIC_DIAGNOSTIC_TARGET
[System.IO.File]::WriteAllText($target, "original diagnostic bytes`r`n", $script:Utf8NoBom)
function Test-ByteArraysEqual {
    param(
        [AllowNull()][byte[]]$Expected,
        [AllowNull()][byte[]]$Actual
    )
    return $false
}

$caught = $null
try {
    Write-AtomicText -LiteralPath $target -Content "replacement diagnostic bytes`r`n"
}
catch {
    $caught = $_.Exception.Message
}
if ([string]::IsNullOrWhiteSpace($caught)) {
    throw 'Atomic write did not surface the injected rollback verification failure.'
}
if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    throw 'Rollback diagnostic fault injection did not leave the restored original at the destination.'
}
$parent = Split-Path -Parent $target
$backups = @(Get-ChildItem -LiteralPath $parent -Force | Where-Object { $_.Name -like '.assistant-framework-*.bak' })
$failedReplacements = @(Get-ChildItem -LiteralPath $parent -Force | Where-Object { $_.Name -like '.assistant-framework-*.rollback' })
if ($backups.Count -ne 0) {
    throw "Rollback diagnostic fixture expected the backup to have moved to the destination, but found: $($backups.FullName -join ', ')"
}
if ($failedReplacements.Count -ne 1) {
    throw "Rollback diagnostic fixture expected one failed-replacement recovery file, but found $($failedReplacements.Count)."
}
if (-not $caught.Contains($target)) {
    throw "Rollback failure diagnostic omitted the existing restored destination: $caught"
}
if ($caught -match '\.assistant-framework-[0-9a-f]+\.bak') {
    throw "Rollback failure diagnostic reported a backup path that no longer exists: $caught"
}
if (-not $caught.Contains($failedReplacements[0].FullName)) {
    throw "Rollback failure diagnostic omitted the existing failed-replacement recovery path: $caught"
}
'atomic rollback diagnostics passed'
'@
            $runnerSource = $runnerSource.Replace('__INSTALLER_FUNCTIONS__', $functionSource)
            [System.IO.File]::WriteAllText($runnerPath, $runnerSource, (New-Object System.Text.UTF8Encoding($false)))
            $target = Join-Path $root 'atomic rollback diagnostic target.txt'
            $savedTarget = [Environment]::GetEnvironmentVariable('ASSISTANT_FRAMEWORK_ATOMIC_DIAGNOSTIC_TARGET', 'Process')
            try {
                [Environment]::SetEnvironmentVariable('ASSISTANT_FRAMEWORK_ATOMIC_DIAGNOSTIC_TARGET', $target, 'Process')
                $result = Invoke-PowerShellFile -LiteralPath $runnerPath
                Assert-Equal 0 $result.ExitCode "Atomic rollback diagnostic runner failed: $($result.Output)"
            }
            finally {
                [Environment]::SetEnvironmentVariable('ASSISTANT_FRAMEWORK_ATOMIC_DIAGNOSTIC_TARGET', $savedTarget, 'Process')
            }
        }
    }

    Invoke-Contract 'tree fingerprints ignore only PowerShell startup cache churn' {
        Use-IsolatedEnvironment 'fingerprint runtime artifact' {
            param($root, $isolatedUserProfile)
            $runtimePaths = @(
                (Join-Path $isolatedUserProfile 'AppData/Local/Microsoft/PowerShell/StartupProfileData-NonInteractive'),
                (Join-Path $isolatedUserProfile 'AppData/Local/Microsoft/Windows/PowerShell/StartupProfileData-NonInteractive')
            )
            $lookalike = $runtimePaths[0] + '.installer-owned'
            $sentinel = Join-Path $root 'installer-owned-sentinel.txt'
            [System.IO.File]::WriteAllText($sentinel, 'sentinel-before')

            $before = Get-TreeFingerprint -LiteralPath $root
            foreach ($runtimePath in $runtimePaths) {
                [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $runtimePath))
                [System.IO.File]::WriteAllText($runtimePath, 'runtime-before')
            }
            Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) 'PowerShell-owned startup cache creation changed the installer fingerprint'

            [System.IO.File]::WriteAllText($lookalike, 'lookalike-before')
            $withLookalike = Get-TreeFingerprint -LiteralPath $root
            foreach ($runtimePath in $runtimePaths) {
                [System.IO.File]::WriteAllText($runtimePath, 'runtime-after')
            }
            Assert-Equal $withLookalike (Get-TreeFingerprint -LiteralPath $root) 'PowerShell-owned startup cache churn changed the installer fingerprint'

            [System.IO.File]::Delete($runtimePaths[1])
            [void][System.IO.Directory]::CreateDirectory($runtimePaths[1])
            Assert-False ($withLookalike -eq (Get-TreeFingerprint -LiteralPath $root)) 'Fingerprint ignored a wrong-type directory at an exact runtime file path'
            [System.IO.Directory]::Delete($runtimePaths[1])
            [System.IO.File]::WriteAllText($runtimePaths[1], 'runtime-after')
            [System.IO.File]::WriteAllText($lookalike, 'lookalike-after')
            Assert-False ($withLookalike -eq (Get-TreeFingerprint -LiteralPath $root)) 'Fingerprint ignored an adjacent lookalike runtime artifact'
            [System.IO.File]::WriteAllText($lookalike, 'lookalike-before')
            [System.IO.File]::WriteAllText($sentinel, 'sentinel-after')
            Assert-False ($withLookalike -eq (Get-TreeFingerprint -LiteralPath $root)) 'Fingerprint ignored an installer-owned sentinel mutation'
        }
    }

    Invoke-Contract 'CLI validates help, agent, skill, and plugin combinations' {
        Use-IsolatedEnvironment 'cli validation' {
            param($root, $isolatedUserProfile)
            $help = Invoke-Installer -Arguments @('-Help')
            Assert-Equal 0 $help.ExitCode 'Help should succeed without -Agent'
            Assert-Contains $help.Output '-Agent <claude|codex|gemini>' 'Help omits supported agents'

            $errorActionPreferenceBefore = $ErrorActionPreference
            $nativePreferenceBefore = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
            $nativePreferenceExistedBefore = $null -ne $nativePreferenceBefore
            if ($nativePreferenceExistedBefore) { $nativePreferenceValueBefore = $nativePreferenceBefore.Value }
            $missing = Invoke-Installer -Arguments @()
            Assert-True ($missing.ExitCode -ne 0) 'Missing -Agent should fail'
            Assert-Contains $missing.Output 'Missing -Agent' 'Missing -Agent stderr was not returned as structured installer output'
            Assert-Equal $errorActionPreferenceBefore $ErrorActionPreference 'Invoke-Installer did not restore ErrorActionPreference after an expected child failure'
            $nativePreferenceAfter = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
            Assert-Equal $nativePreferenceExistedBefore ($null -ne $nativePreferenceAfter) 'Invoke-Installer changed whether PSNativeCommandUseErrorActionPreference exists'
            if ($nativePreferenceExistedBefore) {
                Assert-Equal $nativePreferenceValueBefore $nativePreferenceAfter.Value 'Invoke-Installer did not restore PSNativeCommandUseErrorActionPreference after an expected child failure'
            }
            $harnessSource = [System.IO.File]::ReadAllText($PSCommandPath)
            $invokeStart = $harnessSource.IndexOf('function Invoke-Installer', [System.StringComparison]::Ordinal)
            $invokeEnd = $harnessSource.IndexOf('function Get-TreeFingerprint', $invokeStart, [System.StringComparison]::Ordinal)
            Assert-True ($invokeStart -ge 0 -and $invokeEnd -gt $invokeStart) 'Invoke-Installer function boundary was not found'
            $invokeBody = $harnessSource.Substring($invokeStart, $invokeEnd - $invokeStart)
            Assert-Contains $invokeBody '$ErrorActionPreference = $savedErrorActionPreference' 'Invoke-Installer lacks explicit ErrorActionPreference restoration'
            Assert-Contains $invokeBody 'PSNativeCommandUseErrorActionPreference -Value $savedNativePreference' 'Invoke-Installer lacks explicit native-error preference restoration when that preference exists'
            $unknown = Invoke-Installer -Arguments @('-Agent', 'other')
            Assert-True ($unknown.ExitCode -ne 0) 'Unknown agent should fail'
            $unknownSkill = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-not-real')
            Assert-True ($unknownSkill.ExitCode -ne 0) 'Unknown skill should fail'
            $exclusive = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow', '-Plugin', 'assistant-dev')
            Assert-True ($exclusive.ExitCode -ne 0) '-Skill and -Plugin together should fail'
        }
    }

    Invoke-Contract 'Codex clean install uses split native destinations and structured MCP arguments' {
        Use-IsolatedEnvironment 'codex clean structured arguments' {
            param($root, $isolatedUserProfile)
            $codexHome = Join-Path $root "Codex Home [active] & semi; (quote')"
            [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')
            $result = Invoke-Installer -Arguments @('-Agent', 'CoDeX', '-Skill', 'assistant-workflow', '-NoHooks')
            Assert-Equal 0 $result.ExitCode "Codex clean install failed: $($result.Output)"

            $skillRoot = Join-Path $isolatedUserProfile '.agents\skills\assistant-workflow'
            Assert-True (Test-Path -LiteralPath (Join-Path $skillRoot 'SKILL.md') -PathType Leaf) 'Codex skill was not installed under USERPROFILE\.agents\skills'
            Assert-False (Test-Path -LiteralPath (Join-Path $codexHome 'skills\assistant-workflow')) 'Codex skill was incorrectly installed under CODEX_HOME\skills'
            Assert-True (Test-Path -LiteralPath (Join-Path $codexHome 'rules\workflow.rules') -PathType Leaf) 'Codex execution rules are missing'
            Assert-True (Test-Path -LiteralPath (Join-Path $codexHome 'agents') -PathType Container) 'Codex agent definitions are missing'
            Assert-True (Test-Path -LiteralPath (Join-Path $codexHome 'memory\graph.jsonl') -PathType Leaf) 'First-install graph seed is missing'

            $launcher = Join-Path $codexHome 'tools\memory-graph\run-memory-graph.ps1'
            $memory = Join-Path $codexHome 'memory'
            $config = [System.IO.File]::ReadAllText((Join-Path $codexHome 'config.toml'))
            Assert-Contains $config '[mcp_servers.memory-graph]' 'Codex Memory Graph table is missing'
            Assert-Contains $config '"-NoProfile"' 'MCP args omit -NoProfile'
            Assert-Contains $config '"-File"' 'MCP args omit structured -File'
            Assert-Contains $config ($launcher | ConvertTo-Json -Compress) 'MCP args omit the literal launcher path'
            Assert-Contains $config ($memory | ConvertTo-Json -Compress) 'MCP args omit the literal memory path'
            Assert-NotContains $config 'ExecutionPolicy' 'MCP config weakens execution policy'
            Assert-NotContains $config '"-Command"' 'MCP config uses command-text execution'

            $launcherFirst = Invoke-PowerShellFile -LiteralPath $launcher -Arguments @('-h')
            Assert-Equal 0 $launcherFirst.ExitCode "Installed Memory Graph launcher failed: $($launcherFirst.Output)"
            $publishedDll = Join-Path (Split-Path -Parent $launcher) '.publish\MemoryGraph.dll'
            Assert-True (Test-Path -LiteralPath $publishedDll -PathType Leaf) 'Memory Graph launcher did not create its private build cache'
            $firstPublishedTimestamp = (Get-Item -LiteralPath $publishedDll).LastWriteTimeUtc
            Start-Sleep -Milliseconds 1100
            $launcherSecond = Invoke-PowerShellFile -LiteralPath $launcher -Arguments @('-h')
            Assert-Equal 0 $launcherSecond.ExitCode "Cached Memory Graph launcher failed: $($launcherSecond.Output)"
            Assert-Equal $firstPublishedTimestamp (Get-Item -LiteralPath $publishedDll).LastWriteTimeUtc 'Unchanged Memory Graph sources rebuilt instead of reusing the cache'

            foreach ($excluded in @('context-budget-report.sh', 'evals\run-codex-framework-evals.sh', 'evals\finalize-workflow-kernel-review.sh', 'evals\lib\context-budget-evidence.sh')) {
                Assert-False (Test-Path -LiteralPath (Join-Path (Join-Path $codexHome 'tools') $excluded)) "Source-only tool was installed: $excluded"
            }
        }
    }

    Invoke-Contract 'full inventory, plugin profile, and single-skill selection remain bounded' {
        Use-IsolatedEnvironment 'inventory selection' {
            param($root, $isolatedUserProfile)
            $full = Invoke-Installer -Arguments @('-Agent', 'gemini', '-AcceptMemoryProtocol')
            Assert-Equal 0 $full.ExitCode "Full inventory install failed: $($full.Output)"
            $expected = @(
                Get-ChildItem -LiteralPath (Join-Path $script:FrameworkRoot 'skills') -Directory -Filter 'assistant-*' |
                    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
                    ForEach-Object { $_.Name } |
                    Sort-Object
            )
            $actual = Get-InstalledSkillNames -SkillsRoot (Join-Path $isolatedUserProfile '.gemini\skills')
            Assert-Equal $expected $actual 'Full Windows inventory differs from root assistant-* inventory'

            $profileHome = Join-Path $root 'Profile User'
            [void][System.IO.Directory]::CreateDirectory($profileHome)
            [Environment]::SetEnvironmentVariable('USERPROFILE', $profileHome, 'Process')
            [Environment]::SetEnvironmentVariable('HOME', $profileHome, 'Process')
            $profile = Invoke-Installer -Arguments @('-Agent', 'gemini', '-Plugin', 'assistant-core', '-AcceptMemoryProtocol')
            Assert-Equal 0 $profile.ExitCode "Profile install failed: $($profile.Output)"
            $profileSkills = Get-InstalledSkillNames -SkillsRoot (Join-Path $profileHome '.gemini\skills')
            $expectedCore = @('assistant-clarify', 'assistant-memory', 'assistant-reflexion', 'assistant-telos')
            Assert-Equal $expectedCore $profileSkills 'assistant-core differs from the canonical plugin boundary'

            $singleHome = Join-Path $root 'Single User'
            [void][System.IO.Directory]::CreateDirectory($singleHome)
            [Environment]::SetEnvironmentVariable('USERPROFILE', $singleHome, 'Process')
            [Environment]::SetEnvironmentVariable('HOME', $singleHome, 'Process')
            $single = Invoke-Installer -Arguments @('-Agent', 'claude', '-Skill', 'assistant-workflow', '-AcceptMemoryProtocol')
            Assert-Equal 0 $single.ExitCode "Single-skill install failed: $($single.Output)"
            Assert-Equal @('assistant-workflow') (Get-InstalledSkillNames -SkillsRoot (Join-Path $singleHome '.claude\skills')) 'Single-skill install copied additional skills'
        }
    }

    Invoke-Contract 'shared tools and eval-doc roots preserve unrelated siblings' {
        Use-IsolatedEnvironment 'shared root preservation' {
            param($root, $isolatedUserProfile)
            $codexHome = Join-Path $root 'Codex Shared Roots Home'
            $customTool = Join-Path $codexHome 'tools\company-custom-tool.txt'
            $customEval = Join-Path $codexHome 'docs\evals\company-custom-eval.txt'
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $customTool))
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $customEval))
            $toolBytes = [byte[]](0, 1, 2, 13, 10, 255)
            $evalBytes = [byte[]](255, 10, 13, 3, 2, 1)
            [System.IO.File]::WriteAllBytes($customTool, $toolBytes)
            [System.IO.File]::WriteAllBytes($customEval, $evalBytes)
            [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')

            $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
            Assert-Equal 0 $result.ExitCode "Install into shared roots failed: $($result.Output)"
            Assert-Equal $toolBytes ([System.IO.File]::ReadAllBytes($customTool)) 'Unrelated tools sibling changed or was deleted'
            Assert-Equal $evalBytes ([System.IO.File]::ReadAllBytes($customEval)) 'Unrelated eval-doc sibling changed or was deleted'
            Assert-True (Test-Path -LiteralPath (Join-Path $codexHome 'tools\memory-graph\run-memory-graph.ps1') -PathType Leaf) 'Owned Memory Graph tool was not installed'
        }
    }

    Invoke-Contract 'reinstall retires exact source-only tools and preserves unrelated top-level siblings' {
        Use-IsolatedEnvironment 'source-only upgrade cleanup' {
            param($root, $isolatedUserProfile)
            $codexHome = Join-Path $root 'Codex Source-Only Upgrade Home'
            $toolsRoot = Join-Path $codexHome 'tools'
            $sourceOnlyTargets = @(
                'context-budget-report.sh',
                'evals\run-codex-framework-evals.sh',
                'evals\finalize-workflow-kernel-review.sh',
                'evals\lib\context-budget-evidence.sh'
            )
            foreach ($relativePath in $sourceOnlyTargets) {
                $target = Join-Path $toolsRoot $relativePath
                [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $target))
                [System.IO.File]::WriteAllText($target, 'legacy source-only artifact', (New-Object System.Text.UTF8Encoding($false)))
            }
            $sentinel = Join-Path $toolsRoot 'company-custom-tool.txt'
            $sentinelBytes = [byte[]](0, 1, 2, 13, 10, 255)
            [System.IO.File]::WriteAllBytes($sentinel, $sentinelBytes)
            [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')

            $dryRun = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow', '-DryRun')
            Assert-Equal 0 $dryRun.ExitCode "Source-only cleanup dry run failed: $($dryRun.Output)"
            Assert-Contains $dryRun.Output 'Remove source-only installed target' 'Dry run omitted exact source-only cleanup'
            foreach ($relativePath in $sourceOnlyTargets) {
                Assert-True (Test-Path -LiteralPath (Join-Path $toolsRoot $relativePath) -PathType Leaf) "Dry run removed source-only target: $relativePath"
            }
            Assert-Equal $sentinelBytes ([System.IO.File]::ReadAllBytes($sentinel)) 'Dry run changed unrelated tools sibling'

            $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
            Assert-Equal 0 $result.ExitCode "Source-only cleanup reinstall failed: $($result.Output)"
            foreach ($relativePath in $sourceOnlyTargets) {
                Assert-False (Test-Path -LiteralPath (Join-Path $toolsRoot $relativePath)) "Source-only target survived reinstall: $relativePath"
            }
            Assert-Equal $sentinelBytes ([System.IO.File]::ReadAllBytes($sentinel)) 'Reinstall changed unrelated top-level tools sibling'
        }
    }

    Invoke-Contract 'reinstall preserves graph data, custom instructions, and unrelated TOML exactly once' {
        Use-IsolatedEnvironment 'idempotent reinstall' {
            param($root, $isolatedUserProfile)
            $codexHome = Join-Path $root 'Codex Reinstall Home'
            [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')
            $first = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
            Assert-Equal 0 $first.ExitCode "Initial install failed: $($first.Output)"

            $graph = Join-Path $codexHome 'memory\graph.jsonl'
            [System.IO.File]::WriteAllText($graph, "user-owned-graph`n")
            $agentsFile = Join-Path $codexHome 'AGENTS.md'
            [System.IO.File]::AppendAllText($agentsFile, "`nCUSTOM USER INSTRUCTION`n")
            $configFile = Join-Path $codexHome 'config.toml'
            $firstConfig = [System.IO.File]::ReadAllText($configFile)
            $staleConfig = (New-Object regex '(?m)^command\s*=.*$').Replace($firstConfig, 'command = "stale"', 1)
            [System.IO.File]::WriteAllText($configFile, ($staleConfig.TrimEnd() + "`n`n[mcp_servers.memory-graphical]`ncommand = `"keep-similar`"`n`n[MCP_SERVERS.MEMORY-GRAPH]`ncommand = `"keep-uppercase`"`n"), (New-Object System.Text.UTF8Encoding($false)))
            $agentsAclBefore = $null
            $configAclBefore = $null
            $isWindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
            if ($isWindowsHost) {
                $protectedConfigAcl = Get-Acl -LiteralPath $configFile
                $protectedConfigAcl.SetAccessRuleProtection($true, $false)
                foreach ($rule in @($protectedConfigAcl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))) {
                    [void]$protectedConfigAcl.RemoveAccessRuleSpecific($rule)
                }
                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
                $currentUserRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $currentUser,
                    [System.Security.AccessControl.FileSystemRights]::FullControl,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                [void]$protectedConfigAcl.AddAccessRule($currentUserRule)
                $builtInUsers = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
                $readRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $builtInUsers,
                    [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                [void]$protectedConfigAcl.AddAccessRule($readRule)
                Set-Acl -LiteralPath $configFile -AclObject $protectedConfigAcl
                $agentsAclBefore = Get-Acl -LiteralPath $agentsFile
                $configAclBefore = Get-Acl -LiteralPath $configFile
                Assert-True (Get-Acl -LiteralPath $configFile).AreAccessRulesProtected 'Restrictive config ACL fixture is not protected'
                Assert-True (@((Get-Acl -LiteralPath $configFile).GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier])).Count -ge 2) 'Restrictive config owner/group/DACL fixture lacks multiple explicit access rules'
                [Environment]::SetEnvironmentVariable('OS', 'spoofed-by-contract', 'Process')
            }

            $second = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
            Assert-Equal 0 $second.ExitCode "Reinstall failed: $($second.Output)"
            Assert-Equal "user-owned-graph`n" ([System.IO.File]::ReadAllText($graph)) 'Existing graph seed was overwritten'

            $agents = [System.IO.File]::ReadAllText($agentsFile)
            Assert-Contains $agents 'CUSTOM USER INSTRUCTION' 'Custom Codex instruction was lost'
            Assert-Equal 1 (Get-LiteralCount $agents 'ASSISTANT_FRAMEWORK_AGENTS_MD_START') 'Codex guidance start marker is duplicated'
            Assert-Equal 1 (Get-LiteralCount $agents 'ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START') 'Memory protocol start marker is duplicated'
            if ($isWindowsHost) {
                Assert-OwnerGroupDaclEquivalent -Expected $agentsAclBefore -Actual (Get-Acl -LiteralPath $agentsFile) -Message 'AGENTS.md owner, group, DACL protection, or effective rules changed during atomic replacement'
                Assert-OwnerGroupDaclEquivalent -Expected $configAclBefore -Actual (Get-Acl -LiteralPath $configFile) -Message 'config.toml owner, group, DACL protection, or effective rules changed during atomic replacement'
                Assert-True (Get-Acl -LiteralPath $configFile).AreAccessRulesProtected 'config.toml DACL lost inheritance protection during atomic replacement'
            }

            $config = [System.IO.File]::ReadAllText($configFile)
            Assert-Contains $config '[mcp_servers.memory-graphical]' 'Similar unrelated TOML table was removed'
            Assert-Contains $config 'keep-similar' 'Similar unrelated TOML value was removed'
            Assert-Contains $config '[MCP_SERVERS.MEMORY-GRAPH]' 'Case-variant unrelated TOML table was removed'
            Assert-Contains $config 'keep-uppercase' 'Case-variant unrelated TOML value was removed'
            Assert-Equal 1 (Get-LiteralCount $config '[mcp_servers.memory-graph]') 'Canonical Memory Graph TOML table is not unique'
            Assert-NotContains $config 'command = "stale"' 'Stale Memory Graph TOML table survived refresh'
            $codexCommand = Get-Command codex -ErrorAction SilentlyContinue
            if ($null -ne $codexCommand) {
                $parseOutput = @(& $codexCommand.Source mcp list 2>&1)
                Assert-Equal 0 $LASTEXITCODE "Refreshed supported TOML was rejected by Codex: $($parseOutput | Out-String)"
            }
        }
    }

    Invoke-Contract 'JSON updates preserve deep custom data and use argument arrays' {
        Use-IsolatedEnvironment 'json preservation' {
            param($root, $isolatedUserProfile)
            $claudeConfig = Join-Path $isolatedUserProfile '.claude.json'
            $deep = New-Object PSObject
            $cursor = $deep
            for ($i = 0; $i -lt 35; $i++) {
                $next = New-Object PSObject
                $cursor | Add-Member -MemberType NoteProperty -Name ('level' + $i) -Value $next
                $cursor = $next
            }
            $cursor | Add-Member -MemberType NoteProperty -Name 'sentinel' -Value 'deep-value'
            $fixture = New-Object PSObject -Property @{
                custom = $deep
                mcpServers = (New-Object PSObject -Property @{ customServer = (New-Object PSObject -Property @{ command = 'keep-command' }) })
            }
            Write-JsonFile -LiteralPath $claudeConfig -Value $fixture

            $settingsFile = Join-Path $isolatedUserProfile '.claude\settings.json'
            $settings = New-Object PSObject -Property @{
                customSetting = 'keep-setting'
                mcpServers = (New-Object PSObject -Property @{
                    'memory-graph' = (New-Object PSObject -Property @{ command = 'stale' })
                    customSettingsServer = (New-Object PSObject -Property @{ command = 'keep-settings-command' })
                })
            }
            Write-JsonFile -LiteralPath $settingsFile -Value $settings

            $result = Invoke-Installer -Arguments @('-Agent', 'claude', '-Skill', 'assistant-workflow', '-AcceptMemoryProtocol')
            Assert-Equal 0 $result.ExitCode "Claude JSON install failed: $($result.Output)"
            $updated = Read-JsonFile -LiteralPath $claudeConfig
            $deepCursor = $updated.custom
            for ($i = 0; $i -lt 35; $i++) { $deepCursor = $deepCursor.PSObject.Properties['level' + $i].Value }
            Assert-Equal 'deep-value' $deepCursor.sentinel 'Deep custom JSON data was truncated'
            Assert-Equal 'keep-command' $updated.mcpServers.customServer.command 'Unrelated MCP server was lost'
            Assert-True ($updated.mcpServers.'memory-graph'.args -is [System.Array]) 'Memory Graph args are not a JSON array'
            Assert-True (@($updated.mcpServers.'memory-graph'.args) -contains '-File') 'Memory Graph args omit -File'
            Assert-False (@($updated.mcpServers.'memory-graph'.args) -contains '-Command') 'Memory Graph args use -Command'

            $updatedSettings = Read-JsonFile -LiteralPath $settingsFile
            Assert-Equal 'keep-setting' $updatedSettings.customSetting 'Claude settings custom property was lost'
            Assert-Equal 'keep-settings-command' $updatedSettings.mcpServers.customSettingsServer.command 'Claude settings custom MCP server was lost'
            Assert-True ($null -eq $updatedSettings.mcpServers.PSObject.Properties['memory-graph']) 'Stale Claude settings Memory Graph entry was not retired'
        }
    }

    Invoke-Contract 'invalid duplicate and ambiguous Codex TOML remain byte-identical' {
        Use-IsolatedEnvironment 'toml fail closed' {
            param($root, $isolatedUserProfile)
            $fixtures = @(
                "[broken-table`r`nkey = `"value`"`r`n",
                "[mcp_servers.memory-graph]`r`ncommand = `"one`"`r`n[mcp_servers.`"memory-graph`"]`r`ncommand = `"two`"`r`n",
                "[custom]`r`nvalue = 1`r`nvalue = 2`r`n",
                "[custom]`r`nvalue = ???`r`n",
                "a = 1`r`n[a]`r`nb = 2`r`n",
                "a = 1`r`n[a.b]`r`nc = 2`r`n",
                "custom = { a = 1, a.b = 2 }`r`n",
                "a = 1`r`n`"\u0061`" = 2`r`n",
                "[custom]`r`nd = 2026-99-99`r`n",
                "`"bad\q`" = 1`r`n",
                "`"a\\b`" = 1`r`n'a\b' = 2`r`n",
                "custom = `"\uD800`"`r`n",
                "custom = `"\U00110000`"`r`n",
                "n = 999999999999999999999999999999`r`n",
                "n = +0x1`r`n",
                "n = 1e9999`r`n",
                "n = 0xFFFFFFFFFFFFFFFF`r`n"
            )
            for ($index = 0; $index -lt $fixtures.Count; $index++) {
                $codexHome = Join-Path $root ('Codex TOML Fixture ' + $index)
                [void][System.IO.Directory]::CreateDirectory($codexHome)
                $configFile = Join-Path $codexHome 'config.toml'
                $original = $fixtures[$index]
                [System.IO.File]::WriteAllText($configFile, $original, (New-Object System.Text.UTF8Encoding($false)))
                [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')
                $warmup = Invoke-Installer -Arguments @('-Help')
                Assert-Equal 0 $warmup.ExitCode 'PowerShell warm-up help invocation failed'
                $before = Get-TreeFingerprint -LiteralPath $root
                $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
                Assert-True ($result.ExitCode -ne 0) "Fail-closed TOML install reported success: $($result.Output)"
                Assert-Equal $original ([System.IO.File]::ReadAllText($configFile)) "Unsafe TOML fixture $index changed"
                Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) "Unsafe TOML fixture $index caused project mutation"
                Assert-Contains $result.Output 'TOML' "Unsafe TOML fixture $index lacked a diagnostic"
            }
        }
    }

    Invoke-Contract 'valid unsupported Codex TOML shapes remain byte-identical' {
        Use-IsolatedEnvironment 'valid unsupported toml' {
            param($root, $isolatedUserProfile)
            $fixtures = @(
                "mcp_servers = { existing = { command = `"echo`" } }`r`n",
                "[mcp_servers]`r`nmemory-graph = { command = `"echo`" }`r`n",
                "[`"mcp_servers`".`"memory-graph`"]`r`ncommand = `"old`"`r`n",
                "mcp_servers.memory-graph.command = `"old`"`r`n",
                "[mcp_servers.`"memory\u002dgraph`"]`r`ncommand = `"old`"`r`n",
                "[`"mcp\u005fservers`".memory-graph]`r`ncommand = `"old`"`r`n",
                "foo.bar = 1`r`n",
                "[custom]`r`nvalues = [`r`n  `"one`",`r`n  `"two`",`r`n]`r`n"
            )
            $codexCommand = Get-Command codex -ErrorAction SilentlyContinue
            for ($index = 0; $index -lt $fixtures.Count; $index++) {
                $codexHome = Join-Path $root ('Codex Valid Unsupported TOML Fixture ' + $index)
                [void][System.IO.Directory]::CreateDirectory($codexHome)
                $configFile = Join-Path $codexHome 'config.toml'
                $original = $fixtures[$index]
                [System.IO.File]::WriteAllText($configFile, $original, (New-Object System.Text.UTF8Encoding($false)))
                [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')

                if ($null -ne $codexCommand) {
                    $parseOutput = @(& $codexCommand.Source mcp list 2>&1)
                    Assert-Equal 0 $LASTEXITCODE "Original valid TOML fixture $index was rejected by Codex: $($parseOutput | Out-String)"
                }

                $warmup = Invoke-Installer -Arguments @('-Help')
                Assert-Equal 0 $warmup.ExitCode 'PowerShell warm-up help invocation failed'
                $before = Get-TreeFingerprint -LiteralPath $root
                $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
                Assert-True ($result.ExitCode -ne 0) "Fail-closed TOML install reported success: $($result.Output)"
                Assert-Equal $original ([System.IO.File]::ReadAllText($configFile)) "Valid unsupported TOML fixture $index changed"
                Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) "Valid unsupported TOML fixture $index caused project mutation"
                Assert-Contains $result.Output 'TOML' "Valid unsupported TOML fixture $index lacked a diagnostic"
            }

            $supportedHome = Join-Path $root 'Codex Supported Escaped Project Key'
            [void][System.IO.Directory]::CreateDirectory($supportedHome)
            $supportedConfig = Join-Path $supportedHome 'config.toml'
            $projectTable = "[projects.`"C:\\Users\\Laimis\\repo`"]`r`ntrust_level = `"trusted`"`r`n`r`n[mcp_servers]`r`nexisting = { command = `"echo`" }`r`n"
            [System.IO.File]::WriteAllText($supportedConfig, $projectTable, (New-Object System.Text.UTF8Encoding($false)))
            [Environment]::SetEnvironmentVariable('CODEX_HOME', $supportedHome, 'Process')
            if ($null -ne $codexCommand) {
                $parseOutput = @(& $codexCommand.Source mcp list 2>&1)
                Assert-Equal 0 $LASTEXITCODE "Unrelated escaped project key was rejected by Codex: $($parseOutput | Out-String)"
            }
            $supportedResult = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
            Assert-Equal 0 $supportedResult.ExitCode "Unrelated escaped project key blocked installation: $($supportedResult.Output)"
            $supportedUpdated = [System.IO.File]::ReadAllText($supportedConfig)
            Assert-Contains $supportedUpdated '[projects."C:\\Users\\Laimis\\repo"]' 'Unrelated escaped project key was not preserved'
            Assert-Contains $supportedUpdated 'trust_level = "trusted"' 'Unrelated escaped project value was not preserved'
            Assert-Contains $supportedUpdated 'existing = { command = "echo" }' 'Unrelated inline MCP sibling was not preserved'
            Assert-Equal 1 (Get-LiteralCount $supportedUpdated '[mcp_servers.memory-graph]') 'Supported escaped-key config did not register Memory Graph exactly once'
        }
    }

    Invoke-Contract 'invalid and wrong-root JSON remain byte-identical' {
        Use-IsolatedEnvironment 'invalid json' {
            param($root, $isolatedUserProfile)
            $settingsFile = Join-Path $isolatedUserProfile '.gemini\settings.json'
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $settingsFile))
            $invalid = "{ invalid json [ fixture ]`r`n"
            [System.IO.File]::WriteAllText($settingsFile, $invalid, (New-Object System.Text.UTF8Encoding($false)))
            $result = Invoke-Installer -Arguments @('-Agent', 'gemini', '-Skill', 'assistant-workflow')
            Assert-Equal 0 $result.ExitCode "Invalid JSON should warn and continue: $($result.Output)"
            Assert-Equal $invalid ([System.IO.File]::ReadAllText($settingsFile)) 'Invalid JSON bytes changed'

            $wrongHome = Join-Path $root 'Wrong Root User'
            [void][System.IO.Directory]::CreateDirectory((Join-Path $wrongHome '.gemini'))
            [Environment]::SetEnvironmentVariable('USERPROFILE', $wrongHome, 'Process')
            [Environment]::SetEnvironmentVariable('HOME', $wrongHome, 'Process')
            $wrongFile = Join-Path $wrongHome '.gemini\settings.json'
            $wrongRoot = "[`r`n  { `"keep`": true }`r`n]`r`n"
            [System.IO.File]::WriteAllText($wrongFile, $wrongRoot, (New-Object System.Text.UTF8Encoding($false)))
            $wrongResult = Invoke-Installer -Arguments @('-Agent', 'gemini', '-Skill', 'assistant-workflow')
            Assert-Equal 0 $wrongResult.ExitCode "Wrong-root JSON should warn and continue: $($wrongResult.Output)"
            Assert-Equal $wrongRoot ([System.IO.File]::ReadAllText($wrongFile)) 'Wrong-root JSON bytes changed'
        }
    }

    Invoke-Contract 'case-variant JSON identities are preserved exactly' {
        Use-IsolatedEnvironment 'json exact update identity' {
            param($root, $isolatedUserProfile)
            $configFile = Join-Path $isolatedUserProfile '.claude.json'
            $fixtures = @(
                '{"McpServers":{"custom":{"command":"keep"}},"keep":true}',
                '{"mcpServers":{"Memory-Graph":{"command":"keep"}},"keep":true}',
                '{"mcpServers":{"first":{"command":"keep"}},"mcpServers":{"second":{"command":"keep"}}}',
                '{"custom":{"Name":1,"name":2}}',
                '{"mcpServers":{"custom":{"command":"one","command":"two"}}}'
            )
            $warmup = Invoke-Installer -Arguments @('-Help')
            Assert-Equal 0 $warmup.ExitCode 'PowerShell warm-up help invocation failed'
            for ($index = 0; $index -lt $fixtures.Count; $index++) {
                $original = $fixtures[$index]
                [System.IO.File]::WriteAllText($configFile, $original, (New-Object System.Text.UTF8Encoding($false)))
                $before = Get-TreeFingerprint -LiteralPath $root
                $result = Invoke-Installer -Arguments @('-Agent', 'claude', '-Skill', 'assistant-workflow', '-AcceptMemoryProtocol')
                Assert-True ($result.ExitCode -ne 0) "Case-variant JSON fixture $index was accepted: $($result.Output)"
                Assert-Equal $original ([System.IO.File]::ReadAllText($configFile)) "Case-variant JSON fixture $index changed"
                Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) "Case-variant JSON fixture $index caused project mutation"
                Assert-Contains $result.Output 'JSON property' "Case-variant JSON fixture $index lacked an exact-identity diagnostic"
            }
        }

        Use-IsolatedEnvironment 'json exact removal identity' {
            param($root, $isolatedUserProfile)
            $claudeConfig = Join-Path $isolatedUserProfile '.claude.json'
            [System.IO.File]::WriteAllText($claudeConfig, '{}', (New-Object System.Text.UTF8Encoding($false)))
            $settingsFile = Join-Path $isolatedUserProfile '.claude\settings.json'
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $settingsFile))
            $originalSettings = '{"mcpServers":{"Memory-Graph":{"command":"keep"}},"Hooks":{"Custom":[{"hooks":[{"command":"$HOME/.claude/hooks/assistant/session-start.sh"}]}]}}'
            [System.IO.File]::WriteAllText($settingsFile, $originalSettings, (New-Object System.Text.UTF8Encoding($false)))
            $result = Invoke-Installer -Arguments @('-Agent', 'claude', '-Skill', 'assistant-workflow', '-AcceptMemoryProtocol')
            Assert-Equal 0 $result.ExitCode "Exact-identity removal install failed: $($result.Output)"
            Assert-Equal $originalSettings ([System.IO.File]::ReadAllText($settingsFile)) 'Case-variant stale MCP or hook identity was modified'
        }
    }

    Invoke-Contract 'malformed UTF-8 configuration bytes fail before mutation' {
        Use-IsolatedEnvironment 'invalid utf8 json' {
            param($root, $isolatedUserProfile)
            $configFile = Join-Path $isolatedUserProfile '.claude.json'
            $invalidBytes = [byte[]](0x7B, 0x22, 0x78, 0x22, 0x3A, 0x22, 0xC3, 0x28, 0x22, 0x7D)
            [System.IO.File]::WriteAllBytes($configFile, $invalidBytes)
            $warmup = Invoke-Installer -Arguments @('-Help')
            Assert-Equal 0 $warmup.ExitCode 'PowerShell warm-up help invocation failed'
            $before = Get-TreeFingerprint -LiteralPath $root
            $result = Invoke-Installer -Arguments @('-Agent', 'claude', '-Skill', 'assistant-workflow', '-AcceptMemoryProtocol')
            Assert-True ($result.ExitCode -ne 0) 'Malformed UTF-8 JSON was accepted'
            Assert-Equal ([Convert]::ToBase64String($invalidBytes)) ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($configFile))) 'Malformed UTF-8 JSON bytes changed'
            Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) 'Malformed UTF-8 JSON caused project mutation'
        }

        Use-IsolatedEnvironment 'invalid utf8 toml' {
            param($root, $isolatedUserProfile)
            $codexHome = Join-Path $root 'Codex Invalid UTF8 Home'
            [void][System.IO.Directory]::CreateDirectory($codexHome)
            $configFile = Join-Path $codexHome 'config.toml'
            $invalidBytes = [byte[]](0x6B, 0x20, 0x3D, 0x20, 0x22, 0xC3, 0x28, 0x22, 0x0A)
            [System.IO.File]::WriteAllBytes($configFile, $invalidBytes)
            [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')
            $warmup = Invoke-Installer -Arguments @('-Help')
            Assert-Equal 0 $warmup.ExitCode 'PowerShell warm-up help invocation failed'
            $before = Get-TreeFingerprint -LiteralPath $root
            $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
            Assert-True ($result.ExitCode -ne 0) 'Malformed UTF-8 TOML was accepted'
            Assert-Equal ([Convert]::ToBase64String($invalidBytes)) ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($configFile))) 'Malformed UTF-8 TOML bytes changed'
            Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) 'Malformed UTF-8 TOML caused project mutation'
        }
    }

    Invoke-Contract 'JSON preflight rejects excessive nesting and values before mutation' {
        Use-IsolatedEnvironment 'json nesting budget' {
            param($root, $isolatedUserProfile)
            $configFile = Join-Path $isolatedUserProfile '.claude.json'
            $depth = 140
            $original = '{"custom":' + ('[' * $depth) + '0' + (']' * $depth) + '}'
            [System.IO.File]::WriteAllText($configFile, $original, (New-Object System.Text.UTF8Encoding($false)))
            $warmup = Invoke-Installer -Arguments @('-Help')
            Assert-Equal 0 $warmup.ExitCode 'PowerShell warm-up help invocation failed'
            $before = Get-TreeFingerprint -LiteralPath $root
            $result = Invoke-Installer -Arguments @('-Agent', 'claude', '-Skill', 'assistant-workflow', '-AcceptMemoryProtocol')
            Assert-True ($result.ExitCode -ne 0) 'Over-nested JSON was accepted'
            Assert-Equal $original ([System.IO.File]::ReadAllText($configFile)) 'Over-nested JSON changed'
            Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) 'Over-nested JSON caused project mutation'
            Assert-Contains $result.Output 'JSON complexity' 'Over-nested JSON lacked a bounded-complexity diagnostic'
        }

        Use-IsolatedEnvironment 'json value budget' {
            param($root, $isolatedUserProfile)
            $configFile = Join-Path $isolatedUserProfile '.claude.json'
            $original = '{"custom":[' + [string]::Join(',', (0..10000)) + ']}'
            [System.IO.File]::WriteAllText($configFile, $original, (New-Object System.Text.UTF8Encoding($false)))
            $warmup = Invoke-Installer -Arguments @('-Help')
            Assert-Equal 0 $warmup.ExitCode 'PowerShell warm-up help invocation failed'
            $before = Get-TreeFingerprint -LiteralPath $root
            $result = Invoke-Installer -Arguments @('-Agent', 'claude', '-Skill', 'assistant-workflow', '-AcceptMemoryProtocol')
            Assert-True ($result.ExitCode -ne 0) 'Over-wide JSON was accepted'
            Assert-Equal $original ([System.IO.File]::ReadAllText($configFile)) 'Over-wide JSON changed'
            Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) 'Over-wide JSON caused project mutation'
            Assert-Contains $result.Output 'JSON complexity' 'Over-wide JSON lacked a bounded-complexity diagnostic'
        }
    }

    Invoke-Contract 'hook retirement removes only exact nested framework commands' {
        Use-IsolatedEnvironment 'exact hook retirement' {
            param($root, $isolatedUserProfile)
            $settingsFile = Join-Path $isolatedUserProfile '.gemini\settings.json'
            $fixture = New-Object PSObject -Property @{
                unrelatedTopLevel = (New-Object PSObject -Property @{ command = '$HOME/.gemini/hooks/assistant/session-start.sh --metadata' })
                hooks = (New-Object PSObject -Property @{
                    CustomEvent = @(
                        (New-Object PSObject -Property @{
                            matcher = 'nested-hooks'
                            command = '$HOME/.gemini/hooks/assistant/session-start.sh --group-metadata'
                            hooks = @(
                                (New-Object PSObject -Property @{ type = 'command'; command = '$HOME/.gemini/hooks/assistant/session-start.sh --retire' }),
                                (New-Object PSObject -Property @{ type = 'command'; command = '"$HOME/.gemini/hooks/assistant/stop-review.sh" --retire-quoted' }),
                                (New-Object PSObject -Property @{ type = 'command'; command = '%USERPROFILE%\.gemini\hooks\assistant\task-completed.sh --retire-mixed' }),
                                (New-Object PSObject -Property @{ type = 'command'; command = 'C:\external\hooks\assistant\session-start.sh --same-basename' }),
                                (New-Object PSObject -Property @{ type = 'command'; command = 'pwsh -File $HOME/.gemini/hooks/assistant/session-start.sh --wrapped' }),
                                (New-Object PSObject -Property @{ type = 'command'; command = '"$HOME/.gemini/hooks/assistant/stop-review.sh"suffix --keep-quoted-suffix' }),
                                (New-Object PSObject -Property @{ type = 'command'; command = 'prefix"$HOME/.gemini/hooks/assistant/stop-review.sh" --keep-quoted-prefix' }),
                                (New-Object PSObject -Property @{ type = 'metadata'; command = (New-Object PSObject -Property @{ keep = 'object-command' }) })
                            )
                        }),
                        (New-Object PSObject -Property @{
                            matcher = 'metadata-only-group'
                            command = '$HOME/.gemini/hooks/assistant/stop-review.sh --group-only'
                            custom = 'must-remain'
                        })
                    )
                })
            }
            Write-JsonFile -LiteralPath $settingsFile -Value $fixture
            $result = Invoke-Installer -Arguments @('-Agent', 'gemini', '-Skill', 'assistant-workflow')
            Assert-Equal 0 $result.ExitCode "Hook retirement install failed: $($result.Output)"

            $updated = Read-JsonFile -LiteralPath $settingsFile
            Assert-Contains $updated.unrelatedTopLevel.command '--metadata' 'Top-level command metadata was changed'
            $groups = @($updated.hooks.CustomEvent)
            Assert-True (@($groups | Where-Object { $_.matcher -eq 'metadata-only-group' }).Count -eq 1) 'Hook group without nested hooks was incorrectly deleted'
            $nested = @($groups | Where-Object { $_.matcher -eq 'nested-hooks' } | Select-Object -First 1)
            $commands = @($nested[0].hooks | ForEach-Object { if ($_.command -is [string]) { $_.command } })
            Assert-False (@($commands | Where-Object { $_ -like '*--retire*' }).Count -gt 0) 'An exact direct framework hook command survived retirement'
            Assert-True (@($commands | Where-Object { $_ -like 'C:\external\*' }).Count -eq 1) 'Same-basename external hook was removed'
            Assert-True (@($commands | Where-Object { $_ -like 'pwsh -File*' }).Count -eq 1) 'Wrapped hook command was removed'
            Assert-True (@($commands | Where-Object { $_ -like '*--keep-quoted-suffix' }).Count -eq 1) 'Quoted-suffix lookalike hook command was removed'
            Assert-True (@($commands | Where-Object { $_ -like '*--keep-quoted-prefix' }).Count -eq 1) 'Quoted-prefix lookalike hook command was removed'
        }
    }

    Invoke-Contract 'unbalanced installer markers preserve the original instruction file' {
        Use-IsolatedEnvironment 'unbalanced markers' {
            param($root, $isolatedUserProfile)
            $codexHome = Join-Path $root 'Codex Marker Home'
            [void][System.IO.Directory]::CreateDirectory($codexHome)
            [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')
            $instructions = Join-Path $codexHome 'AGENTS.md'
            $original = "CUSTOM BEFORE`n<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->`nTRUNCATED FRAMEWORK BLOCK`nCUSTOM AFTER MUST SURVIVE`n"
            [System.IO.File]::WriteAllText($instructions, $original, (New-Object System.Text.UTF8Encoding($false)))
            $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
            Assert-Equal $original ([System.IO.File]::ReadAllText($instructions)) 'Unbalanced marker handling changed or truncated user-owned instructions'
            Assert-True ($result.Output -match 'WARNING|Error') 'Ambiguous markers were preserved without a diagnostic'
        }
    }

    Invoke-Contract 'marker prose is preserved and interleaved marker blocks fail closed' {
        Use-IsolatedEnvironment 'marker prose and ordering' {
            param($root, $isolatedUserProfile)
            $proseHome = Join-Path $root 'Codex Marker Prose Home'
            [void][System.IO.Directory]::CreateDirectory($proseHome)
            [Environment]::SetEnvironmentVariable('CODEX_HOME', $proseHome, 'Process')
            $proseFile = Join-Path $proseHome 'AGENTS.md'
            $prose = "CUSTOM prose mentions ASSISTANT_FRAMEWORK_AGENTS_MD_START but is not a marker line.`n"
            [System.IO.File]::WriteAllText($proseFile, $prose, (New-Object System.Text.UTF8Encoding($false)))
            $proseResult = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
            Assert-Equal 0 $proseResult.ExitCode "Prose-marker install failed: $($proseResult.Output)"
            Assert-Contains ([System.IO.File]::ReadAllText($proseFile)) $prose.Trim() 'Prose marker substring was removed as an installer block'

            $caseHome = Join-Path $root 'Codex Case Variant Marker Home'
            [void][System.IO.Directory]::CreateDirectory($caseHome)
            [Environment]::SetEnvironmentVariable('CODEX_HOME', $caseHome, 'Process')
            $caseFile = Join-Path $caseHome 'AGENTS.md'
            $caseBlock = "<!-- assistant_framework_agents_md_start -->`r`nCUSTOM CASE-VARIANT BLOCK`r`n<!-- assistant_framework_agents_md_end -->`r`n"
            [System.IO.File]::WriteAllText($caseFile, $caseBlock, (New-Object System.Text.UTF8Encoding($false)))
            $caseResult = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
            Assert-Equal 0 $caseResult.ExitCode "Case-variant marker install failed: $($caseResult.Output)"
            $caseUpdated = [System.IO.File]::ReadAllText($caseFile)
            Assert-Contains $caseUpdated '<!-- assistant_framework_agents_md_start -->' 'Case-variant user marker start was removed'
            Assert-Contains $caseUpdated 'CUSTOM CASE-VARIANT BLOCK' 'Case-variant user marker content was removed'
            Assert-Contains $caseUpdated '<!-- assistant_framework_agents_md_end -->' 'Case-variant user marker end was removed'
            Assert-Contains $caseUpdated '<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->' 'Canonical installer marker was not added separately'

            $memoryProseHome = Join-Path $root 'Gemini Memory Marker Prose Home'
            [void][System.IO.Directory]::CreateDirectory((Join-Path $memoryProseHome '.gemini'))
            [Environment]::SetEnvironmentVariable('USERPROFILE', $memoryProseHome, 'Process')
            [Environment]::SetEnvironmentVariable('HOME', $memoryProseHome, 'Process')
            [Environment]::SetEnvironmentVariable('CODEX_HOME', $null, 'Process')
            $memoryProseFile = Join-Path $memoryProseHome '.gemini\GEMINI.md'
            $memoryProse = "CUSTOM prose mentions ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START but is not a marker line.`r`n"
            [System.IO.File]::WriteAllText($memoryProseFile, $memoryProse, (New-Object System.Text.UTF8Encoding($false)))
            $memoryProseResult = Invoke-Installer -Arguments @('-Agent', 'gemini', '-Skill', 'assistant-workflow')
            Assert-Equal 0 $memoryProseResult.ExitCode "Memory-prose install failed: $($memoryProseResult.Output)"
            Assert-Equal $memoryProse ([System.IO.File]::ReadAllText($memoryProseFile)) 'Memory marker prose was treated as an installed opt-in block'

            $interleavedHome = Join-Path $root 'Codex Interleaved Marker Home'
            [void][System.IO.Directory]::CreateDirectory($interleavedHome)
            [Environment]::SetEnvironmentVariable('USERPROFILE', $isolatedUserProfile, 'Process')
            [Environment]::SetEnvironmentVariable('HOME', $isolatedUserProfile, 'Process')
            [Environment]::SetEnvironmentVariable('CODEX_HOME', $interleavedHome, 'Process')
            $interleavedFile = Join-Path $interleavedHome 'AGENTS.md'
            $interleaved = "<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->`r`nA`r`n<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->`r`nM`r`n<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->`r`n<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->`r`nCUSTOM`r`n"
            [System.IO.File]::WriteAllText($interleavedFile, $interleaved, (New-Object System.Text.UTF8Encoding($false)))
            $interleavedResult = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
            Assert-Equal $interleaved ([System.IO.File]::ReadAllText($interleavedFile)) 'Interleaved marker blocks changed user-owned instructions'
            Assert-Contains $interleavedResult.Output 'WARNING: Ambiguous, duplicate, or unbalanced' 'Interleaved markers lacked a diagnostic'
        }
    }

    Invoke-Contract 'dry-run is byte-for-byte non-mutating' {
        Use-IsolatedEnvironment 'dry run' {
            param($root, $isolatedUserProfile)
            $codexHome = Join-Path $root 'Dry Run Codex Home'
            [void][System.IO.Directory]::CreateDirectory($codexHome)
            [System.IO.File]::WriteAllText((Join-Path $codexHome 'sentinel.txt'), 'do not change')
            [System.IO.File]::WriteAllText((Join-Path $isolatedUserProfile 'home-sentinel.txt'), 'do not change home')
            [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')
            # Warm the child PowerShell host before the snapshot. PowerShell Core
            # may create its own first-run cache under HOME; that is not an
            # installer mutation and should not produce a false failure.
            $warmup = Invoke-Installer -Arguments @('-Help')
            Assert-Equal 0 $warmup.ExitCode 'PowerShell warm-up help invocation failed'
            $before = Get-TreeFingerprint -LiteralPath $root
            $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow', '-DryRun')
            Assert-Equal 0 $result.ExitCode "Dry-run failed: $($result.Output)"
            $after = Get-TreeFingerprint -LiteralPath $root
            Assert-Equal $before $after 'Dry-run changed the isolated filesystem'
            Assert-Contains $result.Output '[dry-run]' 'Dry-run output does not identify planned operations'
        }
    }

    Invoke-Contract 'dangerous CODEX_HOME targets fail before mutation' {
        Use-IsolatedEnvironment 'dangerous targets' {
            param($root, $isolatedUserProfile)
            foreach ($target in @([System.IO.Path]::GetPathRoot($root), $script:FrameworkRoot, $isolatedUserProfile)) {
                [Environment]::SetEnvironmentVariable('CODEX_HOME', $target, 'Process')
                $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
                Assert-True ($result.ExitCode -ne 0) "Dangerous CODEX_HOME was accepted: $target"
            }
        }
    }

    Invoke-Contract 'relative and device-namespace CODEX_HOME values fail before mutation' {
        Use-IsolatedEnvironment 'configured home path text' {
            param($root, $isolatedUserProfile)
            [System.IO.File]::WriteAllText((Join-Path $root 'sentinel.bin'), 'unchanged')
            $warmup = Invoke-Installer -Arguments @('-Help')
            Assert-Equal 0 $warmup.ExitCode 'PowerShell warm-up help invocation failed'
            $before = Get-TreeFingerprint -LiteralPath $root
            foreach ($target in @('relative-codex-home', '\\?\C:\assistant-framework-device-home')) {
                [Environment]::SetEnvironmentVariable('CODEX_HOME', $target, 'Process')
                $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
                Assert-True ($result.ExitCode -ne 0) "Unsafe CODEX_HOME text was accepted: $target"
                Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) "Unsafe CODEX_HOME text mutated the isolated tree: $target"
            }
        }
    }

    Invoke-Contract 'Windows rooted but drive-relative CODEX_HOME values fail before path resolution' {
        $installer = [System.IO.File]::ReadAllText($script:InstallerPath)
        Assert-Contains $installer 'must be a fully qualified path.' 'Installer lacks explicit fully-qualified home validation'
        Assert-Contains $installer "-VariableName 'CODEX_HOME'" 'Installer does not identify CODEX_HOME at the shared path gate'
        Assert-True ($installer -match '\^\[A-Za-z\]\:\[\\\\/\]') 'Installer lacks a PowerShell 5.1-compatible drive-absolute path check'
        Assert-Contains $installer '[Environment]::OSVersion.Platform' 'Installer does not use a trusted host-platform API'
        Assert-NotContains $installer '$env:OS' 'Installer trusts mutable OS environment text for security decisions'

        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return }
        Use-IsolatedEnvironment 'drive-relative configured home path text' {
            param($root, $isolatedUserProfile)
            [System.IO.File]::WriteAllText((Join-Path $root 'sentinel.bin'), 'unchanged')
            $warmup = Invoke-Installer -Arguments @('-Help')
            Assert-Equal 0 $warmup.ExitCode 'PowerShell warm-up help invocation failed'
            $before = Get-TreeFingerprint -LiteralPath $root
            [Environment]::SetEnvironmentVariable('OS', 'spoofed-by-contract', 'Process')
            foreach ($target in @('C:relative-home', 'C:', '\relative-home')) {
                [Environment]::SetEnvironmentVariable('CODEX_HOME', $target, 'Process')
                $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
                Assert-True ($result.ExitCode -ne 0) "Drive-relative CODEX_HOME text was accepted: $target"
                Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) "Drive-relative CODEX_HOME mutated the isolated tree: $target"
            }
        }
    }

    Invoke-Contract 'unsafe USERPROFILE values fail before path resolution or mutation' {
        Use-IsolatedEnvironment 'configured user home path text' {
            param($root, $isolatedUserProfile)
            [System.IO.File]::WriteAllText((Join-Path $root 'sentinel.bin'), 'unchanged')
            $warmup = Invoke-Installer -Arguments @('-Help')
            Assert-Equal 0 $warmup.ExitCode 'PowerShell warm-up help invocation failed'
            $before = Get-TreeFingerprint -LiteralPath $root
            $targets = @('relative-user-home', '\\?\C:\assistant-framework-device-home', [System.IO.Path]::GetPathRoot($root))
            if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                $targets += @('C:relative-user-home', 'C:', '\relative-user-home')
            }
            foreach ($target in $targets) {
                [Environment]::SetEnvironmentVariable('USERPROFILE', $target, 'Process')
                [Environment]::SetEnvironmentVariable('CODEX_HOME', $null, 'Process')
                $result = Invoke-Installer -Arguments @('-Agent', 'gemini', '-Skill', 'assistant-workflow')
                Assert-True ($result.ExitCode -ne 0) "Unsafe USERPROFILE was accepted: $target"
                Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) "Unsafe USERPROFILE mutated the isolated tree: $target"
            }
        }
    }

    Invoke-Contract 'CODEX_HOME cannot overlap the shared Codex skills tree' {
        Use-IsolatedEnvironment 'agent home skills overlap' {
            param($root, $isolatedUserProfile)
            $agentHome = Join-Path $isolatedUserProfile '.agents\skills\nested-codex-home'
            [void][System.IO.Directory]::CreateDirectory($agentHome)
            $sentinel = Join-Path $agentHome 'sentinel.bin'
            $sentinelBytes = [byte[]](0, 13, 10, 255, 42)
            [System.IO.File]::WriteAllBytes($sentinel, $sentinelBytes)
            [Environment]::SetEnvironmentVariable('CODEX_HOME', $agentHome, 'Process')
            $warmup = Invoke-Installer -Arguments @('-Help')
            Assert-Equal 0 $warmup.ExitCode 'PowerShell warm-up help invocation failed'
            $before = Get-TreeFingerprint -LiteralPath $root
            $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
            Assert-True ($result.ExitCode -ne 0) 'CODEX_HOME nested under the shared skills root was accepted'
            Assert-Equal $sentinelBytes ([System.IO.File]::ReadAllBytes($sentinel)) 'Overlap sentinel bytes changed'
            Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) 'Overlap rejection occurred after filesystem mutation'
        }
    }

    Invoke-Contract 'managed targets reject ancestor junctions without touching the external tree' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Skip-Contract -Name 'managed targets reject ancestor junctions without touching the external tree' -Reason 'junction contract is Windows-only'
            return
        }
        Use-IsolatedEnvironment 'junction containment' {
            param($root, $isolatedUserProfile)
            $external = Join-Path $root 'external-target'
            [void][System.IO.Directory]::CreateDirectory($external)
            $sentinel = Join-Path $external 'sentinel.txt'
            [System.IO.File]::WriteAllText($sentinel, 'external-data')
            $junction = Join-Path $isolatedUserProfile '.agents'
            try {
                try {
                    [void](New-Item -ItemType Junction -Path $junction -Target $external -ErrorAction Stop)
                }
                catch {
                    Skip-Contract -Name 'managed targets reject ancestor junctions without touching the external tree' -Reason "junction creation unavailable: $($_.Exception.Message)"
                    return
                }
                $codexHome = Join-Path $root 'Codex Junction Home'
                [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')
                $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
                Assert-True ($result.ExitCode -ne 0) 'Installer followed a .agents ancestor junction'
                Assert-Equal 'external-data' ([System.IO.File]::ReadAllText($sentinel)) 'External sentinel content changed through junction'
                Assert-False (Test-Path -LiteralPath (Join-Path $external 'skills\assistant-workflow')) 'Installer copied managed files through junction'
            }
            finally {
                if (Test-Path -LiteralPath $junction) { Remove-Item -LiteralPath $junction -Force }
            }

            $managedTarget = Join-Path $isolatedUserProfile '.agents\skills\assistant-workflow'
            [void][System.IO.Directory]::CreateDirectory($managedTarget)
            $nestedJunction = Join-Path $managedTarget 'external-link'
            try {
                [void](New-Item -ItemType Junction -Path $nestedJunction -Target $external -ErrorAction Stop)
                $codexHome = Join-Path $root 'Codex Dry Run Junction Home'
                [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')
                $dryRun = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow', '-DryRun')
                Assert-True ($dryRun.ExitCode -ne 0) 'Dry-run accepted a nested managed-target junction'
                Assert-Equal 'external-data' ([System.IO.File]::ReadAllText($sentinel)) 'Dry-run changed external sentinel content through junction'
            }
            finally {
                if (Test-Path -LiteralPath $nestedJunction) { Remove-Item -LiteralPath $nestedJunction -Force }
            }

            $preflightHome = Join-Path $root 'Codex User File Preflight Home'
            [void][System.IO.Directory]::CreateDirectory($preflightHome)
            foreach ($relativeLeaf in @('config.toml', 'AGENTS.md', 'hooks.json', 'memory\graph.jsonl')) {
                $leafJunction = Join-Path $preflightHome $relativeLeaf
                [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $leafJunction))
                try {
                    [void](New-Item -ItemType Junction -Path $leafJunction -Target $external -ErrorAction Stop)
                    [Environment]::SetEnvironmentVariable('CODEX_HOME', $preflightHome, 'Process')
                    $before = Get-TreeFingerprint -LiteralPath $root
                    $dryRun = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow', '-DryRun')
                    Assert-True ($dryRun.ExitCode -ne 0) "Dry-run accepted reparse-point user file $relativeLeaf"
                    Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) "Dry-run mutated the tree for reparse-point user file $relativeLeaf"
                    $real = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
                    Assert-True ($real.ExitCode -ne 0) "Installer accepted reparse-point user file $relativeLeaf"
                    Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) "Installer mutated before rejecting reparse-point user file $relativeLeaf"
                    Assert-Equal 'external-data' ([System.IO.File]::ReadAllText($sentinel)) "External sentinel changed through $relativeLeaf"
                }
                finally {
                    if (Test-Path -LiteralPath $leafJunction) { Remove-Item -LiteralPath $leafJunction -Force }
                }
            }
        }
    }

    Invoke-Contract 'legacy hook cleanup rejects nested junctions before settings or external mutation' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Skip-Contract -Name 'legacy hook cleanup rejects nested junctions before settings or external mutation' -Reason 'junction contract is Windows-only'
            return
        }
        Use-IsolatedEnvironment 'legacy hook nested junction' {
            param($root, $isolatedUserProfile)
            $codexHome = Join-Path $root 'Codex Legacy Hook Home'
            $hooksTarget = Join-Path $codexHome 'hooks\assistant'
            [void][System.IO.Directory]::CreateDirectory($hooksTarget)
            $external = Join-Path $root 'external-legacy-hook-tree'
            [void][System.IO.Directory]::CreateDirectory($external)
            $externalSentinel = Join-Path $external 'path-policy.sh'
            $sentinelBytes = [byte[]](35, 33, 13, 10, 0, 255)
            [System.IO.File]::WriteAllBytes($externalSentinel, $sentinelBytes)
            $settingsFile = Join-Path $codexHome 'hooks.json'
            $settingsBytes = [System.Text.Encoding]::UTF8.GetBytes('{"hooks":{"CustomEvent":[{"hooks":[{"type":"command","command":"$HOME/.codex/hooks/assistant/session-start.sh --retire"}]}]}}')
            [System.IO.File]::WriteAllBytes($settingsFile, $settingsBytes)
            $junction = Join-Path $hooksTarget 'workflow-guard.d'
            try {
                try {
                    [void](New-Item -ItemType Junction -Path $junction -Target $external -ErrorAction Stop)
                }
                catch {
                    Skip-Contract -Name 'legacy hook cleanup rejects nested junctions before settings or external mutation' -Reason "junction creation unavailable: $($_.Exception.Message)"
                    return
                }
                [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')
                $dryRun = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow', '-DryRun')
                Assert-True ($dryRun.ExitCode -ne 0) 'Dry-run accepted a nested legacy-hook junction'
                Assert-Equal $sentinelBytes ([System.IO.File]::ReadAllBytes($externalSentinel)) 'Dry-run changed the external legacy-hook sentinel'
                Assert-Equal $settingsBytes ([System.IO.File]::ReadAllBytes($settingsFile)) 'Dry-run changed legacy hook settings before junction rejection'
                $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
                Assert-True ($result.ExitCode -ne 0) 'Installer accepted a nested legacy-hook junction'
                Assert-Equal $sentinelBytes ([System.IO.File]::ReadAllBytes($externalSentinel)) 'External legacy-hook sentinel changed through junction'
                Assert-Equal $settingsBytes ([System.IO.File]::ReadAllBytes($settingsFile)) 'Legacy hook settings changed before junction rejection'
            }
            finally {
                if (Test-Path -LiteralPath $junction) { Remove-Item -LiteralPath $junction -Force }
            }


            $wrongType = Join-Path $hooksTarget 'session-start.sh'
            [void][System.IO.Directory]::CreateDirectory($wrongType)
            try {
                $before = Get-TreeFingerprint -LiteralPath $root
                $dryRun = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow', '-DryRun')
                Assert-True ($dryRun.ExitCode -ne 0) 'Dry-run accepted a legacy hook file represented by a directory'
                Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) 'Dry-run mutated before rejecting a wrong-type legacy hook file'
                $real = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
                Assert-True ($real.ExitCode -ne 0) 'Installer accepted a legacy hook file represented by a directory'
                Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) 'Installer mutated before rejecting a wrong-type legacy hook file'
            }
            finally {
                if (Test-Path -LiteralPath $wrongType) { Remove-Item -LiteralPath $wrongType -Force }
            }
        }
    }

    Invoke-Contract 'managed file replacement does not write through external hard links' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Skip-Contract -Name 'managed file replacement does not write through external hard links' -Reason 'hard-link contract is Windows-only'
            return
        }
        Use-IsolatedEnvironment 'managed file hard link' {
            param($root, $isolatedUserProfile)
            $codexHome = Join-Path $root 'Codex Hard Link Home'
            $agentsTarget = Join-Path $codexHome 'agents'
            [void][System.IO.Directory]::CreateDirectory($agentsTarget)
            $externalSentinel = Join-Path $root 'external-agent-sentinel.toml'
            $sentinelBytes = [byte[]](0, 13, 10, 255, 77, 31)
            [System.IO.File]::WriteAllBytes($externalSentinel, $sentinelBytes)
            $managedFile = Join-Path $agentsTarget 'code-writer.toml'
            $externalDirectory = Join-Path $root 'external-agent-directory'
            [void][System.IO.Directory]::CreateDirectory($externalDirectory)
            [System.IO.File]::WriteAllText((Join-Path $externalDirectory 'sentinel.txt'), 'external-agent-data')
            try {
                [void](New-Item -ItemType Junction -Path $managedFile -Target $externalDirectory -ErrorAction Stop)
                [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')
                $before = Get-TreeFingerprint -LiteralPath $root
                $dryRun = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow', '-DryRun')
                Assert-True ($dryRun.ExitCode -ne 0) 'Dry-run accepted a reparse-point managed file destination'
                Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) 'Dry-run mutated before rejecting a managed file reparse point'
                $real = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
                Assert-True ($real.ExitCode -ne 0) 'Installer accepted a reparse-point managed file destination'
                Assert-Equal $before (Get-TreeFingerprint -LiteralPath $root) 'Installer mutated before rejecting a managed file reparse point'
                Assert-Equal 'external-agent-data' ([System.IO.File]::ReadAllText((Join-Path $externalDirectory 'sentinel.txt'))) 'Managed file reparse preflight changed external content'
            }
            finally {
                if (Test-Path -LiteralPath $managedFile) { Remove-Item -LiteralPath $managedFile -Force }
            }
            try {
                try {
                    [void](New-Item -ItemType HardLink -Path $managedFile -Target $externalSentinel -ErrorAction Stop)
                }
                catch {
                    Skip-Contract -Name 'managed file replacement does not write through external hard links' -Reason "hard-link creation unavailable: $($_.Exception.Message)"
                    return
                }
                [Environment]::SetEnvironmentVariable('CODEX_HOME', $codexHome, 'Process')
                $result = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow')
                Assert-Equal 0 $result.ExitCode "Installer failed while safely replacing a managed hard link: $($result.Output)"
                Assert-Equal $sentinelBytes ([System.IO.File]::ReadAllBytes($externalSentinel)) 'Managed artifact copy wrote through the external hard link'
                Assert-False ([Convert]::ToBase64String($sentinelBytes) -eq [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($managedFile))) 'Managed artifact hard-link entry was not replaced'
            }
            finally {
                if (Test-Path -LiteralPath $managedFile) { Remove-Item -LiteralPath $managedFile -Force }
            }
        }
    }

    Invoke-Contract 'Memory Graph launcher uses staged cache and structured forwarding' {
        $launcher = [System.IO.File]::ReadAllText($script:MemoryLauncherPath)
        Assert-Contains $launcher '.publish.stage-' 'Launcher lacks isolated staged publish directory'
        Assert-Contains $launcher '$needsBuild' 'Launcher lacks cache freshness decision'
        Assert-Contains $launcher 'LastWriteTimeUtc' 'Launcher does not compare source and cache timestamps'
        Assert-Contains $launcher '& $dotnetPath publish $projectFile' 'Launcher does not invoke dotnet publish structurally'
        Assert-Contains $launcher '& $dotnetPath $dllPath @forwardedArguments' 'Launcher does not forward server arguments as an array'
        Assert-NotContains $launcher 'Invoke-Expression' 'Launcher evaluates command text'
        Assert-NotContains $launcher 'ExecutionPolicy' 'Launcher changes or bypasses execution policy'
    }
}
finally {
    if (Test-Path -LiteralPath $script:SuiteRoot) {
        Remove-Item -LiteralPath $script:SuiteRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Windows installer contracts: Passed $($script:Passed), Failed $($script:Failed), Skipped $($script:Skipped)"
if ($script:Failed -gt 0) { exit 1 }
if ($FailOnSkip -and $script:Skipped -gt 0) { exit 1 }
exit 0
