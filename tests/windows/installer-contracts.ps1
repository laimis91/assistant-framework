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
        Restore-ProcessEnvironment -Saved $saved
    }
}

function Invoke-Installer {
    param([string[]]$Arguments)
    $allArguments = @('-NoLogo', '-NoProfile', '-File', $script:InstallerPath) + @($Arguments)
    $output = @(& $script:PowerShellExecutable @allArguments 2>&1)
    $exitCode = $LASTEXITCODE
    return (New-Object PSObject -Property @{
        ExitCode = $exitCode
        Output = ($output | Out-String)
    })
}

function Get-TreeFingerprint {
    param([string]$LiteralPath)
    $root = [System.IO.Path]::GetFullPath($LiteralPath).TrimEnd([char[]]@('\', '/'))
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($item in @(Get-ChildItem -LiteralPath $root -Force -Recurse | Sort-Object FullName)) {
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

    Invoke-Contract 'atomic replacement applies an existing ACL before temporary content is written' {
        $installer = [System.IO.File]::ReadAllText($script:InstallerPath)
        $functionStart = $installer.IndexOf('function Write-AtomicText', [System.StringComparison]::Ordinal)
        $functionEnd = $installer.IndexOf('function Clear-ManagedDirectory', $functionStart, [System.StringComparison]::Ordinal)
        Assert-True ($functionStart -ge 0 -and $functionEnd -gt $functionStart) 'Write-AtomicText function boundary was not found'
        $functionBody = $installer.Substring($functionStart, $functionEnd - $functionStart)
        $createIndex = $functionBody.IndexOf('[System.IO.FileMode]::CreateNew', [System.StringComparison]::Ordinal)
        $closeIndex = $functionBody.IndexOf('$stream.Dispose()', $createIndex, [System.StringComparison]::Ordinal)
        $aclIndex = $functionBody.IndexOf('Set-Acl -LiteralPath $tempPath -AclObject $originalAcl', [System.StringComparison]::Ordinal)
        $reopenIndex = $functionBody.IndexOf('[System.IO.FileMode]::Open', $aclIndex, [System.StringComparison]::Ordinal)
        $writeIndex = $functionBody.IndexOf('$writer.Write($Content)', [System.StringComparison]::Ordinal)
        Assert-True ($createIndex -ge 0) 'Atomic replacement does not create its temporary file exclusively'
        Assert-True ($closeIndex -gt $createIndex) 'Atomic replacement does not close its CreateNew handle before applying the ACL'
        Assert-True ($aclIndex -ge 0) 'Atomic replacement does not apply the existing ACL to its temporary file'
        Assert-True ($reopenIndex -gt $aclIndex) 'Atomic replacement does not reopen its secured temporary file for content'
        Assert-True ($writeIndex -ge 0) 'Atomic replacement content write was not found'
        Assert-True ($createIndex -lt $closeIndex -and $closeIndex -lt $aclIndex -and $aclIndex -lt $reopenIndex -and $reopenIndex -lt $writeIndex) 'Atomic replacement does not create, secure, reopen, and write its temporary file in the required order'
    }

    Invoke-Contract 'CLI validates help, agent, skill, and plugin combinations' {
        Use-IsolatedEnvironment 'cli validation' {
            param($root, $isolatedUserProfile)
            $help = Invoke-Installer -Arguments @('-Help')
            Assert-Equal 0 $help.ExitCode 'Help should succeed without -Agent'
            Assert-Contains $help.Output '-Agent <claude|codex|gemini>' 'Help omits supported agents'

            $missing = Invoke-Installer -Arguments @()
            Assert-True ($missing.ExitCode -ne 0) 'Missing -Agent should fail'
            $unknown = Invoke-Installer -Arguments @('-Agent', 'other')
            Assert-True ($unknown.ExitCode -ne 0) 'Unknown agent should fail'
            $unknownSkill = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-not-real')
            Assert-True ($unknownSkill.ExitCode -ne 0) 'Unknown skill should fail'
            $exclusive = Invoke-Installer -Arguments @('-Agent', 'codex', '-Skill', 'assistant-workflow', '-Plugin', 'assistant-dev')
            Assert-True ($exclusive.ExitCode -ne 0) '-Skill and -Plugin together should fail'
        }
    }

    Invoke-Contract 'Codex clean install uses split native destinations and structured MCP arguments' {
        Use-IsolatedEnvironment "codex clean [special] & semi; (quote')" {
            param($root, $isolatedUserProfile)
            $codexHome = Join-Path $root 'Codex Home [active]'
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

            $launcherFirstOutput = @(& $script:PowerShellExecutable -NoLogo -NoProfile -File $launcher '-h' 2>&1)
            $launcherFirstExit = $LASTEXITCODE
            Assert-Equal 0 $launcherFirstExit "Installed Memory Graph launcher failed: $($launcherFirstOutput | Out-String)"
            $publishedDll = Join-Path (Split-Path -Parent $launcher) '.publish\MemoryGraph.dll'
            Assert-True (Test-Path -LiteralPath $publishedDll -PathType Leaf) 'Memory Graph launcher did not create its private build cache'
            $firstPublishedTimestamp = (Get-Item -LiteralPath $publishedDll).LastWriteTimeUtc
            Start-Sleep -Milliseconds 1100
            $launcherSecondOutput = @(& $script:PowerShellExecutable -NoLogo -NoProfile -File $launcher '-h' 2>&1)
            $launcherSecondExit = $LASTEXITCODE
            Assert-Equal 0 $launcherSecondExit "Cached Memory Graph launcher failed: $($launcherSecondOutput | Out-String)"
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
                $agentsAclBefore = (Get-Acl -LiteralPath $agentsFile).Sddl
                $configAclBefore = (Get-Acl -LiteralPath $configFile).Sddl
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
                Assert-Equal $agentsAclBefore (Get-Acl -LiteralPath $agentsFile).Sddl 'AGENTS.md ACL changed during atomic replacement'
                Assert-Equal $configAclBefore (Get-Acl -LiteralPath $configFile).Sddl 'config.toml ACL changed during atomic replacement'
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
