#requires -Version 5.1
<#
.SYNOPSIS
Contracts for the PowerShell framework-ownership helpers and uninstall.ps1.

.DESCRIPTION
Runs under Windows PowerShell 5.1 and PowerShell 7. Every helper, installer
and uninstall invocation inherits a disposable USERPROFILE, HOME and (when
applicable) CODEX_HOME under the suite temporary directory. Uninstall cases run
from a temporary clone of this checkout, never from the checkout itself.
Windows-only behaviour (reparse points, DACLs, autocrlf checkouts, the Codex
process check and Windows PowerShell 5.1) skips elsewhere, and symbolic-link
cases skip on a Windows account that cannot create links; -FailOnSkip makes
every skip a failure.
#>

[CmdletBinding()]
param(
    [switch]$FailOnSkip,
    # Run only contracts whose name contains this text (local iteration).
    [string]$Only = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0
$script:FrameworkRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script:ToolDir = Join-Path (Join-Path $script:FrameworkRoot 'tools') 'framework-ownership'
$script:Helper = Join-Path $script:ToolDir 'ownership.ps1'
$script:CheckoutEntry = Join-Path $script:ToolDir 'ownership-checkout.ps1'
$script:PowerShellExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$script:IsWindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$suiteTempBase = [System.IO.Path]::GetTempPath()
if (-not $script:IsWindowsHost -and (Test-Path -LiteralPath '/private/tmp' -PathType Container)) {
    # macOS exposes /var and /tmp as symbolic links; the helpers refuse homes
    # below a link, so use the canonical private temporary root.
    $suiteTempBase = '/private/tmp'
}
$script:SuiteRoot = Join-Path $suiteTempBase ('afo-' + [Guid]::NewGuid().ToString('N'))
$script:Clone = $null

$script:FDFF = 'fdff2dc7cf5719e3c231e5c17f34c9207239c343'
$script:HOOKS = 'f68887c3d75c7e711e62749bcaf90aee2a11d312'
$script:PLUGINS = '36a59a5600b89058135cf37f26f0fb8aa00d9d52'
$script:D11756D = 'd11756d'
$script:Substituted = @('.md', '.yaml', '.yml', '.json', '.conf', '.toml')
$script:ShimText = "#!/usr/bin/env bash`n# Assistant Framework retired-hook compatibility shim.`nexit 0`n"
$script:Latin1 = [System.Text.Encoding]::GetEncoding(28591)
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $script:Helper -PathType Leaf)) {
    [Console]::Error.WriteLine('framework-ownership-contracts: ownership.ps1 not found')
    exit 1
}

# ── Harness ─────────────────────────────────────────────────────────────────

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -is [System.Array]) { $Expected = @($Expected) -join "`n" }
    if ($Actual -is [System.Array]) { $Actual = @($Actual) -join "`n" }
    if (-not [object]::Equals($Expected, $Actual)) { throw "$Message`nExpected: $Expected`nActual: $Actual" }
}

function Assert-Contains {
    param([string]$Text, [string]$Expected, [string]$Message)
    if ($null -eq $Text -or -not $Text.Contains($Expected)) { throw "$Message`n--- output ---`n$Text" }
}

function Assert-NotContains {
    param([string]$Text, [string]$Unexpected, [string]$Message)
    if ($null -ne $Text -and $Text.Contains($Unexpected)) { throw "$Message`n--- output ---`n$Text" }
}

function Invoke-Contract {
    param([string]$Name, [scriptblock]$Body)
    if ($Only -and -not $Name.Contains($Only)) { return }
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

# ── Files and Git ───────────────────────────────────────────────────────────

# Create a symbolic link. On Windows an account without elevation or Developer
# Mode cannot; return $false there so the caller skips (and -FailOnSkip fails).
function New-TestSymbolicLink {
    param([string]$Path, [string]$Target)
    try { [void](New-Item -ItemType SymbolicLink -Path $Path -Target $Target -ErrorAction Stop) }
    catch {
        if ($script:IsWindowsHost) { return $false }
        throw
    }
    return $true
}

function Write-TestBytes {
    param([string]$LiteralPath, $Data)
    $parent = [System.IO.Path]::GetDirectoryName($LiteralPath)
    if (-not [System.IO.Directory]::Exists($parent)) { [void][System.IO.Directory]::CreateDirectory($parent) }
    if ($Data -is [string]) { $Data = $script:Utf8.GetBytes($Data) }
    [System.IO.File]::WriteAllBytes($LiteralPath, [byte[]]$Data)
}

function Read-TestText {
    param([string]$LiteralPath)
    return $script:Utf8.GetString([System.IO.File]::ReadAllBytes($LiteralPath))
}

function Invoke-GitBytes {
    param([string]$Repository, [string[]]$Arguments)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'git'
    $quoted = @('-C', $Repository) + $Arguments | ForEach-Object { '"' + ([string]$_).Replace('"', '\"') + '"' }
    $startInfo.Arguments = ($quoted -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $buffer = New-Object System.IO.MemoryStream
    $errorTask = $process.StandardError.ReadToEndAsync()
    $process.StandardOutput.BaseStream.CopyTo($buffer)
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "git $($Arguments -join ' ') failed: $($errorTask.Result)" }
    return ,$buffer.ToArray()
}

function Get-GitFiles {
    param([string]$Revision, [string]$Path)
    $text = $script:Utf8.GetString((Invoke-GitBytes $script:FrameworkRoot @('ls-tree', '-r', '--name-only', $Revision, '--', $Path)))
    return @($text.Split("`n") | Where-Object { $_ })
}

function Get-InstalledBytes {
    param([string]$Revision, [string]$Path, [string]$Agent)
    $data = Invoke-GitBytes $script:FrameworkRoot @('show', "${Revision}:$Path")
    foreach ($extension in $script:Substituted) {
        if ($Path.EndsWith($extension, [System.StringComparison]::Ordinal)) {
            $data = $script:Latin1.GetBytes($script:Latin1.GetString($data).Replace('{agent_state_dir}', '.' + $Agent))
            break
        }
    }
    return ,$data
}

function Copy-SeedTree {
    param([string]$Revision, [string]$Source, [string]$Target, [string]$Agent)
    foreach ($path in (Get-GitFiles $Revision $Source)) {
        Write-TestBytes (Join-Path $Target ($path.Substring($Source.Length + 1))) (Get-InstalledBytes $Revision $path $Agent)
    }
}

function Copy-SeedFile {
    param([string]$Revision, [string]$Source, [string]$Target, [string]$Agent)
    Write-TestBytes $Target (Get-InstalledBytes $Revision $Source $Agent)
}

# Path, type, size, write time and content hash of every entry below Root.
function Get-TreeSnapshot {
    param([string]$Root)
    if (-not [System.IO.Directory]::Exists($Root) -and -not [System.IO.File]::Exists($Root)) { return '<absent>' }
    if ([System.IO.File]::Exists($Root)) { $items = @(Get-Item -LiteralPath $Root -Force) }
    else { $items = @(Get-ChildItem -LiteralPath $Root -Force -Recurse -ErrorAction Stop) }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $rows = foreach ($item in $items) {
        $relative = $item.FullName.Substring($Root.Length)
        # The child PowerShell processes keep their own startup cache and
        # telemetry id under HOME on Unix; they are not helper writes.
        if ($relative -match '[\\/]\.cache[\\/]powershell|[\\/]\.local[\\/]share[\\/]powershell|^[\\/]\.cache$|[\\/]home[\\/]\.cache$|^[\\/]\.local$|[\\/]\.local[\\/]share$|[\\/]home[\\/]\.local$') { continue }
        # On Windows the child hosts resolve their profile folders from the
        # disposable USERPROFILE: PowerShell 7 writes its startup cache under
        # AppData\Local\Microsoft\PowerShell and Windows PowerShell 5.1 creates
        # an empty AppData\Roaming. Only those host paths are skipped; any other
        # file under AppData still counts as a change.
        if ($relative -match '^([\\/]home)?[\\/]AppData[\\/]Local[\\/]Microsoft[\\/]PowerShell([\\/]|$)') { continue }
        if ($item.PSIsContainer -and $relative -match '^([\\/]home)?[\\/]AppData([\\/]Local([\\/]Microsoft)?|[\\/]Roaming)?$') { continue }
        $isLink = (([int]$item.Attributes -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0)
        if ($isLink) { "$relative|link|$($item.LastWriteTimeUtc.Ticks)" }
        elseif ($item.PSIsContainer) { "$relative|dir" }
        else {
            $hash = [System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($item.FullName)))
            "$relative|file|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)|$hash"
        }
    }
    $sha.Dispose()
    $sorted = [string[]]@($rows)
    [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    return ($sorted -join "`n")
}

# ── Disposable homes ────────────────────────────────────────────────────────

function New-TestHome {
    $base = Join-Path $script:SuiteRoot ('h' + [Guid]::NewGuid().ToString('N').Substring(0, 10))
    $userHome = Join-Path $base 'home'
    [void][System.IO.Directory]::CreateDirectory($userHome)
    $sentinel = Join-Path $base 'sentinel'
    Write-TestBytes (Join-Path $sentinel 'SKILL.md') "sentinel skill`n"
    Write-TestBytes (Join-Path $sentinel 'keep.bin') ([byte[]](0, 1, 98, 10))
    Write-TestBytes (Join-Path (Join-Path $base 'telos') 'purpose.md') "outside telos purpose`n"
    $testHome = @{ Base = $base; Home = $userHome; CodexHome = $null }
    $testHome.Outside = Get-OutsideSnapshot $testHome
    return $testHome
}

function Get-OutsideSnapshot {
    param($TestHome)
    return ((Get-TreeSnapshot (Join-Path $TestHome.Base 'sentinel')) + '#' + (Get-TreeSnapshot (Join-Path $TestHome.Base 'telos')) + '#' + (Get-TreeSnapshot (Join-Path $TestHome.Home '.claude.json')))
}

function Assert-OutsideUnchanged {
    param($TestHome)
    Assert-Equal $TestHome.Outside (Get-OutsideSnapshot $TestHome) 'a sentinel outside the agent home changed'
}

function Get-AgentHome {
    param($TestHome, [string]$Agent)
    if ($Agent -eq 'codex' -and $TestHome.CodexHome) { return $TestHome.CodexHome }
    return (Join-Path $TestHome.Home ('.' + $Agent))
}

function Add-Sentinels {
    param($TestHome, [string]$Agent)
    $agentHome = Get-AgentHome $TestHome $Agent
    Write-TestBytes (Join-Path $agentHome 'config.toml') "model = 'x'`n"
    Write-TestBytes (Join-Path $agentHome 'tools/company-custom-tool.txt') ([byte[]](0, 99, 10))
    Write-TestBytes (Join-Path $agentHome 'docs/evals/custom.md') "custom eval doc`n"
    Write-TestBytes (Join-Path $agentHome 'skills/my-skill/SKILL.md') "user skill`n"
    Write-TestBytes (Join-Path $agentHome 'telos/purpose.md') "telos purpose inside home`n"
    Write-TestBytes (Join-Path $agentHome 'rules/default.rules') "prefix_rule(pattern=['ls'], decision='allow')`n"
    Write-TestBytes (Join-Path $agentHome 'agents/my-agent.md') "user agent`n"
    Write-TestBytes (Join-Path $TestHome.Home '.claude.json') "{`"user`": true}`n"
    $TestHome.Outside = Get-OutsideSnapshot $TestHome
}

# Run a PowerShell script in a child process with the disposable home.
function Invoke-TestScript {
    param($TestHome, [string]$Script, [string[]]$Arguments = @(), [string]$CodexHome = $null, [string]$WorkingDirectory = $null, [string]$Command = $null)
    $saved = @{ USERPROFILE = $env:USERPROFILE; HOME = $env:HOME; CODEX_HOME = $env:CODEX_HOME }
    $errorFile = Join-Path $script:SuiteRoot ('err-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $savedLocation = Get-Location
    $savedPreference = $ErrorActionPreference
    $savedNative = $null
    $nativeVariable = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
    try {
        $env:USERPROFILE = $TestHome.Home
        $env:HOME = $TestHome.Home
        $env:CODEX_HOME = if ($CodexHome) { $CodexHome } else { $null }
        if ($WorkingDirectory) { Set-Location -LiteralPath $WorkingDirectory } else { Set-Location -LiteralPath $TestHome.Base }
        $ErrorActionPreference = 'Continue'
        if ($null -ne $nativeVariable) { $savedNative = $nativeVariable.Value; $global:PSNativeCommandUseErrorActionPreference = $false }
        if ($Command) { $lines = @(& $script:PowerShellExecutable -NoProfile -NonInteractive -Command $Command 2> $errorFile) }
        else { $lines = @('' | & $script:PowerShellExecutable -NoProfile -NonInteractive -File $Script @Arguments 2> $errorFile) }
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
        if ($null -ne $nativeVariable) { $global:PSNativeCommandUseErrorActionPreference = $savedNative }
        Set-Location -LiteralPath $savedLocation.ProviderPath
        $env:USERPROFILE = $saved.USERPROFILE
        $env:HOME = $saved.HOME
        $env:CODEX_HOME = $saved.CODEX_HOME
    }
    $errorText = if (Test-Path -LiteralPath $errorFile) { [System.IO.File]::ReadAllText($errorFile) } else { '' }
    Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
    $out = (@($lines | ForEach-Object { [string]$_ }) -join "`n") + "`n"
    return @{ Code = $code; Out = $out; Err = $errorText }
}

function Invoke-Helper {
    param($TestHome, [string[]]$Arguments, [string]$CodexHome = $null, [string]$Script = $script:Helper)
    return (Invoke-TestScript -TestHome $TestHome -Script $Script -Arguments $Arguments -CodexHome $CodexHome)
}

function Get-Digest {
    param([string]$Text, [string]$Label = 'Manifest digest: ')
    foreach ($line in $Text.Split("`n")) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith($Label, [System.StringComparison]::Ordinal)) { return $trimmed.Substring($Label.Length).Trim() }
    }
    throw "no digest in output:`n$Text"
}

function Get-ManifestText {
    param([string]$Text)
    $start = $Text.IndexOf("BEGIN MANIFEST`n")
    $end = $Text.IndexOf("END MANIFEST`n")
    if ($start -lt 0 -or $end -lt 0) { throw "no manifest in output:`n$Text" }
    $start += "BEGIN MANIFEST`n".Length
    return $Text.Substring($start, $end - $start)
}

function Invoke-DryRun {
    param($TestHome, [string]$Agent = 'claude', [string]$CodexHome = $null)
    $result = Invoke-Helper $TestHome @('dry-run', '-Agent', $Agent) -CodexHome $CodexHome
    Assert-Equal 0 $result.Code ("dry-run failed: " + $result.Out + $result.Err)
    return $result.Out
}

function Save-Manifest {
    param($TestHome, [string]$Out)
    $path = Join-Path $TestHome.Base ('manifest-' + [Guid]::NewGuid().ToString('N') + '.json')
    Write-TestBytes $path (Get-ManifestText $Out)
    return @{ Path = $path; Digest = (Get-Digest $Out) }
}

function Invoke-Apply {
    param($TestHome, $Saved, [string]$Agent = 'claude', [switch]$NoYes, [string]$CodexHome = $null)
    $arguments = @('apply', '-Agent', $Agent, '-Manifest', $Saved.Path, '-ManifestDigest', $Saved.Digest)
    if (-not $NoYes) { $arguments += '-Yes' }
    return (Invoke-Helper $TestHome $arguments -CodexHome $CodexHome)
}

function Add-Reflexion {
    param($TestHome, [string]$Agent = 'claude', [string]$Root = $null)
    if (-not $Root) { $Root = Join-Path (Get-AgentHome $TestHome $Agent) 'skills' }
    Copy-SeedTree $script:FDFF 'skills/assistant-reflexion' (Join-Path $Root 'assistant-reflexion') $Agent
}

function Find-Python {
    foreach ($candidate in @(@('py', '-3'), @('python3'), @('python'))) {
        $command = Get-Command -Name $candidate[0] -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) { return ,([string[]](@($command.Source) + @($candidate | Select-Object -Skip 1))) }
    }
    return $null
}

function Invoke-Python {
    param($TestHome, [string[]]$Arguments)
    $python = Find-Python
    $saved = @{ USERPROFILE = $env:USERPROFILE; HOME = $env:HOME; CODEX_HOME = $env:CODEX_HOME }
    $savedPreference = $ErrorActionPreference
    try {
        $env:USERPROFILE = $TestHome.Home; $env:HOME = $TestHome.Home; $env:CODEX_HOME = $null
        $ErrorActionPreference = 'Continue'
        $prefix = @($python | Select-Object -Skip 1)
        $lines = @(& $python[0] @prefix '-B' @Arguments 2>$null)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
        $env:USERPROFILE = $saved.USERPROFILE; $env:HOME = $saved.HOME; $env:CODEX_HOME = $saved.CODEX_HOME
    }
    return @{ Code = $code; Out = ((@($lines) -join "`n") + "`n") }
}

# ── Checkout clone for uninstall ────────────────────────────────────────────

function Get-CheckoutClone {
    if ($null -ne $script:Clone) { return $script:Clone }
    $base = Join-Path $script:SuiteRoot 'clone'
    $clone = Join-Path $base 'fw'
    [void][System.IO.Directory]::CreateDirectory($base)
    [void](Invoke-GitBytes $base @('clone', '-q', '--no-hardlinks', $script:FrameworkRoot, $clone))
    $head = $script:Utf8.GetString((Invoke-GitBytes $script:FrameworkRoot @('rev-parse', 'HEAD'))).Trim()
    [void](Invoke-GitBytes $clone @('checkout', '-q', '--detach', $head))
    $listing = $script:Utf8.GetString((Invoke-GitBytes $script:FrameworkRoot @('ls-files', '-z', '--cached', '--others', '--exclude-standard')))
    foreach ($relative in $listing.Split([char]0)) {
        if (-not $relative) { continue }
        $source = Join-Path $script:FrameworkRoot $relative
        $target = Join-Path $clone $relative
        if ([System.IO.File]::Exists($source)) {
            $parent = [System.IO.Path]::GetDirectoryName($target)
            if (-not [System.IO.Directory]::Exists($parent)) { [void][System.IO.Directory]::CreateDirectory($parent) }
            [System.IO.File]::Copy($source, $target, $true)
        }
        elseif (-not [System.IO.Directory]::Exists($source) -and [System.IO.File]::Exists($target)) {
            [System.IO.File]::Delete($target)
        }
    }
    [void](Invoke-GitBytes $clone @('add', '-A'))
    [void](Invoke-GitBytes $clone @('-c', 'user.email=t@example.invalid', '-c', 'user.name=t', '-c', 'core.autocrlf=false', 'commit', '-q', '--allow-empty', '-m', 'working tree'))
    $script:Clone = $clone
    return $clone
}

function Invoke-TestInstall {
    param($TestHome, [string]$Agent, [string]$Framework = $null, [string]$CodexHome = $null)
    if (-not $Framework) { $Framework = Get-CheckoutClone }
    $result = Invoke-TestScript -TestHome $TestHome -Script (Join-Path $Framework 'install.ps1') -Arguments @('-Agent', $Agent) -CodexHome $CodexHome
    Assert-Equal 0 $result.Code ("install failed: " + $result.Out + $result.Err)
    return $result
}

function Invoke-TestUninstall {
    param($TestHome, [string]$Agent, [string[]]$Arguments = @(), [string]$CodexHome = $null)
    $script = Join-Path (Get-CheckoutClone) 'uninstall.ps1'
    return (Invoke-TestScript -TestHome $TestHome -Script $script -Arguments (@('-Agent', $Agent) + $Arguments) -CodexHome $CodexHome)
}

function Get-PlanDigest {
    param($TestHome, [string]$Agent, [string]$CodexHome = $null)
    $result = Invoke-TestUninstall $TestHome $Agent @('-DryRun') -CodexHome $CodexHome
    Assert-Equal 0 $result.Code ("uninstall dry run failed: " + $result.Out + $result.Err)
    return @{ Digest = (Get-Digest $result.Out); Out = $result.Out }
}

function Invoke-ConfirmedUninstall {
    param($TestHome, [string]$Agent, [string]$CodexHome = $null)
    $plan = Get-PlanDigest $TestHome $Agent -CodexHome $CodexHome
    $result = Invoke-TestUninstall $TestHome $Agent @('-Yes', '-PlanDigest', $plan.Digest) -CodexHome $CodexHome
    return @{ Code = $result.Code; Out = ($plan.Out + $result.Out); Err = $result.Err }
}

# Framework items the Windows installer writes that are still present.
function Get-FrameworkItemsLeft {
    param($TestHome, [string]$AgentHome, [string]$Agent)
    $fw = Get-CheckoutClone
    $left = New-Object 'System.Collections.Generic.List[string]'
    $skillsRoot = if ($Agent -eq 'codex') { Join-Path (Join-Path $TestHome.Home '.agents') 'skills' } else { Join-Path $AgentHome 'skills' }
    foreach ($directory in [System.IO.Directory]::GetDirectories((Join-Path $fw 'skills'))) {
        $name = [System.IO.Path]::GetFileName($directory)
        if (Test-Path -LiteralPath (Join-Path $skillsRoot $name)) { [void]$left.Add("skills/$name") }
    }
    foreach ($entry in [System.IO.Directory]::GetFileSystemEntries((Join-Path $fw 'tools'))) {
        $name = [System.IO.Path]::GetFileName($entry)
        if (@('.DS_Store', 'memory-graph', 'context-budget-report.sh', 'plugins', '.publish', 'bin', 'obj', '__pycache__') -contains $name) { continue }
        if (Test-Path -LiteralPath (Join-Path (Join-Path $AgentHome 'tools') $name)) { [void]$left.Add("tools/$name") }
    }
    if ($Agent -eq 'codex') {
        foreach ($name in @('change-impact', 'progress')) {
            if (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $TestHome.Home '.agents') 'tools') $name)) { [void]$left.Add("<agents_tools>/$name") }
        }
    }
    foreach ($entry in [System.IO.Directory]::GetFileSystemEntries((Join-Path (Join-Path $fw 'docs') 'evals'))) {
        $name = [System.IO.Path]::GetFileName($entry)
        if (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $AgentHome 'docs') 'evals') $name)) { [void]$left.Add("docs/evals/$name") }
    }
    foreach ($pair in @(@('claude', '.md'), @('codex', '.toml'))) {
        foreach ($file in [System.IO.Directory]::GetFiles((Join-Path (Join-Path $fw 'agents') $pair[0]))) {
            $name = [System.IO.Path]::GetFileName($file)
            if ($name.EndsWith($pair[1]) -and (Test-Path -LiteralPath (Join-Path (Join-Path $AgentHome 'agents') $name))) { [void]$left.Add("agents/$name") }
        }
    }
    return ,$left
}

# ── Cases ───────────────────────────────────────────────────────────────────

[void][System.IO.Directory]::CreateDirectory($script:SuiteRoot)
try {

# T1/T3: inventory and helper commands.

Invoke-Contract 'validate accepts the committed inventory and data' {
    $h = New-TestHome
    $result = Invoke-Helper $h @('validate')
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-Contains $result.Out 'Inventory valid: ' 'validate did not report the inventory'
}

Invoke-Contract 'refused: unknown first argument' {
    $h = New-TestHome
    $result = Invoke-Helper $h @('frobnicate')
    Assert-Equal 2 $result.Code 'an unknown subcommand was not refused'
    Assert-Contains $result.Err 'refused: the first argument must be one of: dry-run, apply, list-retired, validate' 'wrong refusal text'
}

Invoke-Contract 'cleanup installed helper rejects install mode' {
    $h = New-TestHome
    $result = Invoke-Helper $h @('install', '-Agent', 'claude')
    Assert-Equal 2 $result.Code 'installer mode was not refused'
    Assert-Contains $result.Err 'the installed helper has no installer mode; installers run the checkout entry point' 'wrong refusal text'
}

Invoke-Contract 'list-retired -Json equals the Python windows installer list' {
    $h = New-TestHome
    $result = Invoke-Helper $h @('list-retired', '-Layout', 'windows', '-Json')
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    $parsed = $result.Out | ConvertFrom-Json
    Assert-Equal 'windows' $parsed.layout 'wrong layout'
    $rows = @($parsed.items | ForEach-Object { "$($_.kind)`t$($_.node_type)`t$($_.path)" })
    Assert-True ($rows -contains "managed_tool`tfile`tcleanup-memory-graph.ps1") 'cleanup-memory-graph.ps1 is missing from the windows list'
    Assert-True ($rows -contains "managed_tool_empty_directory`tdirectory`tplugins") 'plugins is missing from the windows list'
    $plain = Invoke-Helper $h @('list-retired', '-Layout', 'windows')
    Assert-Equal 0 $plain.Code ($plain.Out + $plain.Err)
    Assert-Equal ($rows -join "`n") ($plain.Out.TrimEnd("`n")) 'the JSON and tab-separated lists differ'
    if ($null -eq (Find-Python)) { Skip-Contract 'list-retired -Json equals the Python windows installer list' 'Python 3 unavailable'; return }
    $python = Invoke-Python $h @((Join-Path $script:ToolDir 'ownership.py'), 'list-retired', '--layout', 'windows')
    Assert-Equal 0 $python.Code 'python list-retired failed'
    Assert-Equal ($python.Out.TrimEnd("`n")) ($rows -join "`n") 'the PowerShell list differs from the Python list'
}

Invoke-Contract 'inventory error refuses everything' {
    $h = New-TestHome
    $copy = Join-Path $h.Base 'helper'
    [void][System.IO.Directory]::CreateDirectory($copy)
    foreach ($name in @('ownership.ps1', 'ownership-core.ps1', 'installer-primitives.ps1', 'content-proof.json')) {
        [System.IO.File]::Copy((Join-Path $script:ToolDir $name), (Join-Path $copy $name))
    }
    $inventory = Read-TestText (Join-Path $script:ToolDir 'retired-items.json')
    Write-TestBytes (Join-Path $copy 'retired-items.json') ($inventory.Replace('"schema_version": "1.0"', '"schema_version": "9.0"'))
    Add-Reflexion $h
    $before = Get-TreeSnapshot $h.Home
    foreach ($arguments in @(@('dry-run', '-Agent', 'claude'), @('list-retired', '-Layout', 'windows'), @('validate'))) {
        $result = Invoke-Helper $h $arguments -Script (Join-Path $copy 'ownership.ps1')
        Assert-Equal 2 $result.Code "inventory error did not refuse $($arguments[0])"
        Assert-Contains $result.Err 'unknown major version' 'wrong inventory refusal'
    }
    Assert-Equal $before (Get-TreeSnapshot $h.Home) 'a refused run changed the home'
}

# Cleanup dry run.

Invoke-Contract 'cleanup dry run is byte-for-byte non-mutating' {
    $h = New-TestHome
    Add-Sentinels $h 'claude'
    Add-Reflexion $h
    Copy-SeedFile $script:HOOKS 'hooks/scripts/session-start.sh' (Join-Path (Get-AgentHome $h 'claude') 'hooks/assistant/session-start.sh') 'claude'
    $before = Get-TreeSnapshot $h.Base
    $out = Invoke-DryRun $h
    Assert-Contains $out 'skill_directory: skills/assistant-reflexion' 'retired skill not offered'
    Assert-Contains $out 'hook_entrypoint: hooks/assistant/session-start.sh' 'retired hook not offered'
    Assert-Equal $before (Get-TreeSnapshot $h.Base) 'dry run changed the disposable home'
    Assert-OutsideUnchanged $h
}

Invoke-Contract 'cleanup dry run creates no hooks directory' {
    $h = New-TestHome
    [void][System.IO.Directory]::CreateDirectory((Get-AgentHome $h 'claude'))
    [void](Invoke-DryRun $h)
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Get-AgentHome $h 'claude') 'hooks'))) 'dry run created hooks'
}

Invoke-Contract 'cleanup keeps other product assistant-memory' {
    $h = New-TestHome
    $file = Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-memory/SKILL.md'
    Write-TestBytes $file "---`nname: assistant-memory`n---`nOther product`n"
    $out = Invoke-DryRun $h
    Assert-Contains $out 'skills/assistant-memory: content matches no framework revision' 'other product not reported unrelated'
    Assert-NotContains $out 'skill_directory: skills/assistant-memory' 'other product offered for removal'
    $saved = Save-Manifest $h $out
    $result = Invoke-Apply $h $saved
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-True (Test-Path -LiteralPath $file) 'other product removed'
}

Invoke-Contract 'cleanup retired skill plus user file ambiguous' {
    $h = New-TestHome
    Add-Reflexion $h
    Write-TestBytes (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-reflexion/notes.md') "my notes`n"
    $out = Invoke-DryRun $h
    Assert-Contains $out 'skills/assistant-reflexion: file does not match framework content: notes.md' 'user file not reported'
    $saved = Save-Manifest $h $out
    $before = Get-TreeSnapshot (Get-AgentHome $h 'claude')
    $result = Invoke-Apply $h $saved
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-Equal $before (Get-TreeSnapshot (Get-AgentHome $h 'claude')) 'ambiguous skill changed'
}

Invoke-Contract 'cleanup symbolic-link retired skill kept' {
    $h = New-TestHome
    $target = Join-Path $h.Base 'elsewhere'
    Add-Reflexion $h -Root $target
    $skills = Join-Path (Get-AgentHome $h 'claude') 'skills'
    [void][System.IO.Directory]::CreateDirectory($skills)
    if (-not (New-TestSymbolicLink -Path (Join-Path $skills 'assistant-reflexion') -Target (Join-Path $target 'assistant-reflexion'))) {
        Skip-Contract 'cleanup symbolic-link retired skill kept' 'this Windows account cannot create symbolic links (needs elevation or Developer Mode)'; return
    }
    $label = if ($script:IsWindowsHost) { 'reparse point' } else { 'symbolic link' }
    $out = Invoke-DryRun $h
    Assert-Contains $out "skills/assistant-reflexion: $label at skills/assistant-reflexion; not followed" 'link not kept'
    Assert-Contains $out 'Removable (0):' 'link offered'
}

Invoke-Contract 'cleanup junction retired skill kept' {
    if (-not $script:IsWindowsHost) { Skip-Contract 'cleanup junction retired skill kept' 'directory junctions exist only on Windows'; return }
    $h = New-TestHome
    $target = Join-Path $h.Base 'elsewhere'
    Add-Reflexion $h -Root $target
    $skills = Join-Path (Get-AgentHome $h 'claude') 'skills'
    [void][System.IO.Directory]::CreateDirectory($skills)
    [void](New-Item -ItemType Junction -Path (Join-Path $skills 'assistant-reflexion') -Target (Join-Path $target 'assistant-reflexion'))
    $out = Invoke-DryRun $h
    Assert-Contains $out 'skills/assistant-reflexion: reparse point at skills/assistant-reflexion; not followed' 'junction not kept'
    $saved = Save-Manifest $h $out
    [void](Invoke-Apply $h $saved)
    Assert-True (Test-Path -LiteralPath (Join-Path $target 'assistant-reflexion/SKILL.md')) 'junction target changed'
}

Invoke-Contract 'cleanup linked ancestor refused' {
    $h = New-TestHome
    $real = Join-Path $h.Base 'real-claude'
    Add-Reflexion $h -Root (Join-Path $real 'skills')
    $linkType = if ($script:IsWindowsHost) { 'Junction' } else { 'SymbolicLink' }
    [void](New-Item -ItemType $linkType -Path (Join-Path $h.Home '.claude') -Target $real)
    $result = Invoke-Helper $h @('dry-run', '-Agent', 'claude')
    Assert-Equal 2 $result.Code ('a linked agent home was not refused: ' + $result.Out)
    Assert-Contains $result.Err 'refused: unsafe agent home' 'wrong refusal'
    Assert-True (Test-Path -LiteralPath (Join-Path $real 'skills/assistant-reflexion/SKILL.md')) 'link target changed'
}

Invoke-Contract 'cleanup checkout-form registration kept ambiguous' {
    $h = New-TestHome
    $claude = Get-AgentHome $h 'claude'
    $settings = '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "/opt/fw/hooks/scripts/session-start.sh"}]}]}}'
    Write-TestBytes (Join-Path $claude 'settings.json') $settings
    $out = Invoke-DryRun $h
    Assert-Contains $out 'possible framework checkout path; run uninstall from that checkout or remove it by hand' 'checkout-form registration not kept'
    Assert-Contains $out 'Removable (0):' 'checkout-form registration offered'
}

Invoke-Contract 'cleanup malformed settings preserved' {
    $h = New-TestHome
    $claude = Get-AgentHome $h 'claude'
    Copy-SeedFile $script:HOOKS 'hooks/scripts/session-start.sh' (Join-Path $claude 'hooks/assistant/session-start.sh') 'claude'
    Write-TestBytes (Join-Path $claude 'settings.json') '{"hooks": {'
    $out = Invoke-DryRun $h
    Assert-Contains $out 'invalid JSON; preserved unchanged' 'malformed settings not reported'
    Assert-Contains $out 'hooks/assistant/session-start.sh: settings.json could not be read' 'entrypoint offered while settings unreadable'
    $saved = Save-Manifest $h $out
    [void](Invoke-Apply $h $saved)
    Assert-Equal '{"hooks": {' (Read-TestText (Join-Path $claude 'settings.json')) 'malformed settings changed'
}

Invoke-Contract 'cleanup registered shim kept until registration removed' {
    $h = New-TestHome
    $claude = Get-AgentHome $h 'claude'
    Write-TestBytes (Join-Path $claude 'hooks/assistant/session-start.sh') $script:ShimText
    $settings = '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "$HOME/.claude/hooks/assistant/session-start.sh"}]}]}, "model": "x"}'
    Write-TestBytes (Join-Path $claude 'settings.json') $settings
    $out = Invoke-DryRun $h
    Assert-Contains $out 'hook_registration: hooks/assistant/session-start.sh (registration settings.json/SessionStart/0)' 'registration not offered'
    Assert-Contains $out 'hooks/assistant/session-start.sh: still registered in settings.json' 'shim offered while registered'
    $result = Invoke-Apply $h (Save-Manifest $h $out)
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-Equal "{`n  `"hooks`": {},`n  `"model`": `"x`"`n}`n" (Read-TestText (Join-Path $claude 'settings.json')) 'settings not rewritten as expected'
    Assert-True (Test-Path -LiteralPath (Join-Path $claude 'hooks/assistant/session-start.sh')) 'shim removed in the same cleanup'
    $out = Invoke-DryRun $h
    Assert-Contains $out 'hook_entrypoint: hooks/assistant/session-start.sh' 'shim not offered after its registration was removed'
    $result = Invoke-Apply $h (Save-Manifest $h $out)
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $claude 'hooks/assistant/session-start.sh'))) 'shim kept'
}

Invoke-Contract 'cleanup registration index counts every command' {
    $h = New-TestHome
    $settings = '{"hooks": {"Stop": [{"hooks": [{"command": "echo a"}, {"command": "echo b"}]}, {"matcher": "x", "hooks": [{"command": "$HOME/.claude/hooks/assistant/stop-review.sh"}]}]}}'
    Write-TestBytes (Join-Path (Get-AgentHome $h 'claude') 'settings.json') $settings
    $out = Invoke-DryRun $h
    Assert-Contains $out '(registration settings.json/Stop/2)' 'index does not count every command'
}

Invoke-Contract 'cleanup two registrations in one event change together' {
    $h = New-TestHome
    $claude = Get-AgentHome $h 'claude'
    $settings = '{"hooks": {"Stop": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/stop-review.sh"}, {"command": "$HOME/.claude/hooks/assistant/session-end.sh"}, {"command": "echo keep"}]}], "Other": {"weird": true}}}'
    Write-TestBytes (Join-Path $claude 'settings.json') $settings
    $out = Invoke-DryRun $h
    $result = Invoke-Apply $h (Save-Manifest $h $out)
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    $expected = "{`n  `"hooks`": {`n    `"Stop`": [`n      {`n        `"hooks`": [`n          {`n            `"command`": `"echo keep`"`n          }`n        ]`n      }`n    ],`n    `"Other`": {`n      `"weird`": true`n    }`n  }`n}`n"
    Assert-Equal $expected (Read-TestText (Join-Path $claude 'settings.json')) 'unexpected settings rewrite'
}

# Cleanup apply refusals.

Invoke-Contract 'cleanup apply refuses without manifest' {
    $h = New-TestHome
    Add-Reflexion $h
    $before = Get-TreeSnapshot $h.Home
    $result = Invoke-Helper $h @('apply', '-Agent', 'claude', '-Yes')
    Assert-Equal 2 $result.Code 'apply without a manifest was not refused'
    Assert-Contains $result.Err 'apply requires -Manifest and -ManifestDigest from a prior dry run' 'wrong refusal'
    Assert-Equal $before (Get-TreeSnapshot $h.Home) 'refused apply changed the home'
}

Invoke-Contract 'cleanup apply refuses edited manifest' {
    $h = New-TestHome
    Add-Reflexion $h
    $saved = Save-Manifest $h (Invoke-DryRun $h)
    $text = Read-TestText $saved.Path
    Write-TestBytes $saved.Path ($text.Replace('"operation": "cleanup"', '"operation": "cleanup", "extra": 1'))
    $result = Invoke-Apply $h $saved
    Assert-Equal 2 $result.Code 'edited manifest accepted'
    Assert-Contains $result.Err 'manifest content does not match its manifest_digest' 'wrong refusal'
    Assert-True (Test-Path -LiteralPath (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-reflexion')) 'refused apply removed the skill'
}

Invoke-Contract 'cleanup apply refuses wrong digest' {
    $h = New-TestHome
    Add-Reflexion $h
    $saved = Save-Manifest $h (Invoke-DryRun $h)
    $saved.Digest = ('0' * 64)
    $result = Invoke-Apply $h $saved
    Assert-Equal 2 $result.Code 'wrong digest accepted'
    Assert-Contains $result.Err 'the confirmed digest does not match the manifest' 'wrong refusal'
}

Invoke-Contract 'cleanup apply refuses noninteractive without -Yes' {
    $h = New-TestHome
    Add-Reflexion $h
    $saved = Save-Manifest $h (Invoke-DryRun $h)
    $result = Invoke-Apply $h $saved -NoYes
    Assert-Equal 2 $result.Code 'noninteractive apply accepted'
    Assert-Contains $result.Err 'a non-interactive apply requires -Yes' 'wrong refusal'
    Assert-True (Test-Path -LiteralPath (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-reflexion')) 'refused apply removed the skill'
}

Invoke-Contract 'cleanup apply refuses install and uninstall and current kinds' {
    $h = New-TestHome
    Add-Reflexion $h
    $out = Invoke-DryRun $h
    $core = Join-Path $script:ToolDir 'ownership-core.ps1'
    $primitives = Join-Path $script:ToolDir 'installer-primitives.ps1'
    foreach ($case in @(@('install', 'skill_directory', 'a manifest with operation install cannot be applied here'), @('uninstall', 'skill_directory', 'a manifest with operation uninstall cannot be applied here'), @('cleanup', 'current_skill_directory', 'a cleanup manifest cannot list a current framework item'))) {
        $path = Join-Path $h.Base ('m-' + [Guid]::NewGuid().ToString('N') + '.json')
        Write-TestBytes (Join-Path $h.Base 'source.json') (Get-ManifestText $out)
        $command = ". '$primitives'; . '$core'; " +
            "`$m = (ConvertFrom-OwnershipJson -Text ([IO.File]::ReadAllText('$(Join-Path $h.Base 'source.json')'))); " +
            "`$m['operation'] = '$($case[0])'; foreach (`$i in `$m['items']) { `$i['kind'] = '$($case[1])' }; " +
            "`$m['manifest_digest'] = Get-OwnershipManifestDigest -Manifest `$m; " +
            "[IO.File]::WriteAllText('$path', (ConvertTo-OwnershipManifestText -Manifest `$m)); Write-Output `$m['manifest_digest']"
        $made = Invoke-TestScript -TestHome $h -Command $command
        Assert-Equal 0 $made.Code ('could not build the test manifest: ' + $made.Err)
        $result = Invoke-Apply $h @{ Path = $path; Digest = $made.Out.Trim() }
        Assert-Equal 2 $result.Code "operation $($case[0]) accepted"
        Assert-Contains $result.Err $case[2] 'wrong refusal'
    }
    Assert-True (Test-Path -LiteralPath (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-reflexion')) 'refused apply removed the skill'
}

Invoke-Contract 'cleanup apply skips item changed after report' {
    $h = New-TestHome
    Add-Reflexion $h
    $saved = Save-Manifest $h (Invoke-DryRun $h)
    $file = Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-reflexion/SKILL.md'
    Write-TestBytes $file ([System.IO.File]::ReadAllBytes($file) + $script:Utf8.GetBytes("edited`n"))
    $result = Invoke-Apply $h $saved
    Assert-Equal 3 $result.Code ($result.Out + $result.Err)
    Assert-Contains $result.Out 'skipped: skills/assistant-reflexion:' 'changed item not skipped'
    Assert-Contains $result.Out 'Some items were kept; run the assistant-cleanup skill to review kept items.' 'no cleanup pointer'
    Assert-True (Test-Path -LiteralPath $file) 'changed item removed'
}

Invoke-Contract 'cleanup apply ignores items added after report' {
    $h = New-TestHome
    Add-Reflexion $h
    $saved = Save-Manifest $h (Invoke-DryRun $h)
    Copy-SeedTree $script:FDFF 'skills/assistant-memory' (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-memory') 'claude'
    $result = Invoke-Apply $h $saved
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-Contains $result.Out 'not in the confirmed manifest: skills/assistant-memory' 'new item not reported'
    Assert-True (Test-Path -LiteralPath (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-memory')) 'unconfirmed item removed'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-reflexion'))) 'confirmed item kept'
}

Invoke-Contract 'cleanup before-delete change is skipped' {
    $h = New-TestHome
    Add-Reflexion $h
    $saved = Save-Manifest $h (Invoke-DryRun $h)
    $core = Join-Path $script:ToolDir 'ownership-core.ps1'
    $primitives = Join-Path $script:ToolDir 'installer-primitives.ps1'
    $skill = Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-reflexion'
    $command = "Set-StrictMode -Version 2.0; `$ErrorActionPreference = 'Stop'; . '$primitives'; . '$core'; " +
        "`$data = Read-OwnershipData -Directory '$($script:ToolDir)'; `$homes = Resolve-OwnershipHomes -Agent 'claude'; " +
        "`$planner = New-OwnershipPlanner -Data `$data -Agent 'claude' -Operation 'cleanup' -Homes `$homes; " +
        "`$manifest = (ConvertFrom-OwnershipJson -Text ([IO.File]::ReadAllText('$($saved.Path)'))); " +
        "`$result = Invoke-OwnershipApply -Planner `$planner -Items `$manifest['items'] -BeforeDelete { param(`$item) [IO.File]::AppendAllText('$skill/SKILL.md', 'late') }; " +
        "Write-OwnershipApplyResult -Result `$result"
    $result = Invoke-TestScript -TestHome $h -Command $command
    Assert-Equal 0 $result.Code $result.Err
    Assert-Contains $result.Out 'skipped: skills/assistant-reflexion:' 'late change not skipped'
    Assert-True (Test-Path -LiteralPath (Join-Path $skill 'SKILL.md')) 'changed skill removed'
}

Invoke-Contract 'cleanup interactive confirmation' {
    $h = New-TestHome
    Add-Reflexion $h
    $saved = Save-Manifest $h (Invoke-DryRun $h)
    foreach ($case in @(@('no', 2, $true), @('claude', 0, $false))) {
        $command = "`$OwnershipHelperNoMain = `$true; . '$($script:Helper)'; " +
            "function Test-OwnershipInteractive { `$true }; function Read-OwnershipConfirmationLine { '$($case[0])' }; " +
            "exit (Invoke-OwnershipHelperMain -Arguments @('apply', '-Agent', 'claude', '-Manifest', '$($saved.Path)', '-ManifestDigest', '$($saved.Digest)'))"
        $result = Invoke-TestScript -TestHome $h -Command $command
        Assert-Equal $case[1] $result.Code ("answer $($case[0]): " + $result.Out + $result.Err)
        Assert-Contains $result.Out 'Type the agent name (claude) to remove 1 item(s), anything else to abort: ' 'no typed confirmation prompt'
        Assert-Equal $case[2] (Test-Path -LiteralPath (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-reflexion')) "answer $($case[0]) gave the wrong result"
    }
}

# Cleanup scope.

Invoke-Contract 'cleanup custom codex home only' {
    $h = New-TestHome
    $custom = Join-Path $h.Base 'custom-codex'
    $h.CodexHome = $custom
    Add-Reflexion $h 'codex' -Root (Join-Path $h.Home '.agents/skills')
    Add-Reflexion $h 'codex' -Root (Join-Path $h.Home '.codex/skills')
    Copy-SeedFile $script:FDFF 'agents/codex/explorer.toml' (Join-Path $custom 'agents/explorer.toml') 'codex'
    $out = Invoke-DryRun $h 'codex' -CodexHome $custom
    Assert-Contains $out "Agent home: $custom" 'custom home not used'
    Assert-Contains $out 'skill_directory: <agents_skills>/assistant-reflexion' 'shared skills root not inspected'
    Assert-NotContains $out '.codex' 'the default codex home was inspected'
    $result = Invoke-Apply $h (Save-Manifest $h $out) 'codex' -CodexHome $custom
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-True (Test-Path -LiteralPath (Join-Path $h.Home '.codex/skills/assistant-reflexion')) 'default codex home changed'
}

Invoke-Contract 'cleanup second dry run idempotent' {
    $h = New-TestHome
    Add-Reflexion $h
    $first = Invoke-DryRun $h
    $second = Invoke-DryRun $h
    Assert-Equal $first $second 'two dry runs differ'
    $result = Invoke-Apply $h (Save-Manifest $h $first)
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-Contains (Invoke-DryRun $h) 'Removable (0):' 'second run still offers items'
}

Invoke-Contract 'cleanup output never contains file contents' {
    $h = New-TestHome
    Add-Reflexion $h
    Write-TestBytes (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-reflexion/secret.md') "SECRET-TOKEN-VALUE`n"
    $out = Invoke-DryRun $h
    Assert-NotContains $out 'SECRET-TOKEN-VALUE' 'file contents in the report'
}

Invoke-Contract 'cleanup dry run reports only inventory items' {
    $h = New-TestHome
    Add-Sentinels $h 'claude'
    $out = Invoke-DryRun $h
    foreach ($name in @('my-skill', 'company-custom-tool', 'config.toml', 'telos', 'my-agent')) { Assert-NotContains $out $name "non-inventory item reported: $name" }
}

Invoke-Contract 'cleanup manifest-out inside home refused' {
    $h = New-TestHome
    Add-Reflexion $h
    $inside = Join-Path (Get-AgentHome $h 'claude') 'manifest.json'
    $result = Invoke-Helper $h @('dry-run', '-Agent', 'claude', '-ManifestOut', $inside)
    Assert-Equal 2 $result.Code 'manifest inside home accepted'
    Assert-Contains $result.Err '-ManifestOut must be outside the agent home and every inventory root' 'wrong refusal'
    $outside = Join-Path $h.Base 'manifest.json'
    $result = Invoke-Helper $h @('dry-run', '-Agent', 'claude', '-ManifestOut', $outside)
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-Contains $result.Out "Manifest written to: $outside" 'manifest file not reported'
    $result = Invoke-Helper $h @('dry-run', '-Agent', 'claude', '-ManifestOut', $outside)
    Assert-Equal 2 $result.Code 'existing manifest file overwritten'
    Assert-Contains $result.Err '-ManifestOut must name a file that does not exist yet' 'wrong refusal'
}

Invoke-Contract 'cleanup stale tool bytes kept and framework copy removed' {
    $h = New-TestHome
    $tools = Join-Path (Get-AgentHome $h 'claude') 'tools'
    Copy-SeedFile '201709378bd87c868a6b326fc144d61ed500913c^' 'tools/cleanup-memory-graph.sh' (Join-Path $tools 'cleanup-memory-graph.sh') 'claude'
    Write-TestBytes (Join-Path $tools 'cleanup-memory-graph.ps1') "# my own script`n"
    $out = Invoke-DryRun $h
    Assert-Contains $out 'managed_tool: tools/cleanup-memory-graph.sh' 'framework copy not offered'
    Assert-Contains $out 'tools/cleanup-memory-graph.ps1: content matches no framework revision' 'user copy not kept'
}

Invoke-Contract 'cleanup node_modules proven by location and link kept' {
    $h = New-TestHome
    $modules = Join-Path (Get-AgentHome $h 'claude') 'tools/evals/node_modules'
    Write-TestBytes (Join-Path $modules 'ajv/index.js') "module.exports = 1`n"
    if (-not $script:IsWindowsHost) {
        [void][System.IO.Directory]::CreateDirectory((Join-Path $modules '.bin'))
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $modules '.bin/ajv') -Target '../ajv/index.js')
    }
    $out = Invoke-DryRun $h
    Assert-Contains $out 'source_only_tool: tools/evals/node_modules' 'node_modules not offered'
    $result = Invoke-Apply $h (Save-Manifest $h $out)
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-True (-not (Test-Path -LiteralPath $modules)) 'node_modules kept'
    $linkType = if ($script:IsWindowsHost) { 'Junction' } else { 'SymbolicLink' }
    [void](New-Item -ItemType $linkType -Path $modules -Target (Join-Path $h.Base 'sentinel'))
    $label = if ($script:IsWindowsHost) { 'reparse point' } else { 'symbolic link' }
    Assert-Contains (Invoke-DryRun $h) "tools/evals/node_modules: $label" 'linked node_modules not kept'
    Assert-OutsideUnchanged $h
}

Invoke-Contract 'cleanup hard-linked file kept' {
    $h = New-TestHome
    $tools = Join-Path (Get-AgentHome $h 'claude') 'tools'
    Copy-SeedFile '201709378bd87c868a6b326fc144d61ed500913c^' 'tools/cleanup-memory-graph.sh' (Join-Path $tools 'cleanup-memory-graph.sh') 'claude'
    [void](New-Item -ItemType HardLink -Path (Join-Path $h.Base 'second-link.sh') -Target (Join-Path $tools 'cleanup-memory-graph.sh'))
    $out = Invoke-DryRun $h
    Assert-Contains $out 'tools/cleanup-memory-graph.sh: hard-linked file; not removed' 'hard link not kept'
}

Invoke-Contract 'cleanup case variant name kept' {
    $h = New-TestHome
    Add-Reflexion $h -Root (Join-Path $h.Base 'stage')
    $skills = Join-Path (Get-AgentHome $h 'claude') 'skills'
    [void][System.IO.Directory]::CreateDirectory($skills)
    [System.IO.Directory]::Move((Join-Path $h.Base 'stage/assistant-reflexion'), (Join-Path $skills 'Assistant-Reflexion'))
    $out = Invoke-DryRun $h
    Assert-Contains $out 'name differs from the inventory path only by case or Unicode form: skills/Assistant-Reflexion' 'case variant not kept'
}

Invoke-Contract 'cleanup retired memory block removed with separator' {
    $h = New-TestHome
    $file = Join-Path (Get-AgentHome $h 'claude') 'CLAUDE.md'
    Write-TestBytes $file "# Mine`n`n<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->`nold protocol`n<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_END -->`n`nafter`n"
    $out = Invoke-DryRun $h
    Assert-Contains $out 'instruction_block: CLAUDE.md' 'block not offered'
    $result = Invoke-Apply $h (Save-Manifest $h $out)
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-Equal "# Mine`n`nafter`n" (Read-TestText $file) 'block not removed with its separator'
}

Invoke-Contract 'cleanup unbalanced block kept' {
    $h = New-TestHome
    $file = Join-Path (Get-AgentHome $h 'claude') 'CLAUDE.md'
    Write-TestBytes $file "# Mine`n<!-- ASSISTANT_FRAMEWORK_MEMORY_PROTOCOL_START -->`nold`n"
    $out = Invoke-DryRun $h
    Assert-Contains $out 'CLAUDE.md: ambiguous, duplicate or unbalanced markers; file preserved unchanged' 'unbalanced block not kept'
}

Invoke-Contract 'cleanup crlf copy is proven' {
    $h = New-TestHome
    $target = Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-reflexion'
    Add-Reflexion $h
    foreach ($file in [System.IO.Directory]::GetFiles($target, '*', [System.IO.SearchOption]::AllDirectories)) {
        $bytes = [System.IO.File]::ReadAllBytes($file)
        if ([System.Array]::IndexOf($bytes, [byte]0) -ge 0) { continue }
        Write-TestBytes $file ($script:Latin1.GetBytes($script:Latin1.GetString($bytes).Replace("`n", "`r`n")))
    }
    $out = Invoke-DryRun $h
    Assert-Contains $out 'skill_directory: skills/assistant-reflexion' 'CRLF copy not proven'
}

Invoke-Contract 'Windows autocrlf checkout copy is proven by fingerprint' {
    if (-not $script:IsWindowsHost) { Skip-Contract 'Windows autocrlf checkout copy is proven by fingerprint' 'core.autocrlf checkouts are exercised on Windows CI'; return }
    $h = New-TestHome
    $clone = Join-Path $h.Base 'autocrlf'
    [void](Invoke-GitBytes $h.Base @('-c', 'core.autocrlf=true', 'clone', '-q', '--no-checkout', '--no-hardlinks', $script:FrameworkRoot, $clone))
    [void](Invoke-GitBytes $clone @('-c', 'core.autocrlf=true', 'checkout', '-q', $script:FDFF, '--', 'skills/assistant-reflexion'))
    $target = Join-Path (Get-AgentHome $h 'claude') 'skills'
    [void][System.IO.Directory]::CreateDirectory($target)
    Copy-Item -LiteralPath (Join-Path $clone 'skills/assistant-reflexion') -Destination $target -Recurse
    $out = Invoke-DryRun $h
    Assert-Contains $out 'skill_directory: skills/assistant-reflexion' 'autocrlf copy not proven'
}

Invoke-Contract 'cleanup home equal to user home or root refused' {
    $h = New-TestHome
    foreach ($custom in @($h.Home, [System.IO.Path]::GetPathRoot($h.Home))) {
        $result = Invoke-Helper $h @('dry-run', '-Agent', 'codex') -CodexHome $custom
        Assert-Equal 2 $result.Code "CODEX_HOME=$custom accepted"
    }
}

Invoke-Contract 'cleanup refuses Codex work while Codex runs' {
    if (-not $script:IsWindowsHost) { Skip-Contract 'cleanup refuses Codex work while Codex runs' 'the Codex process check runs only on Windows'; return }
    $h = New-TestHome
    Add-Reflexion $h 'codex' -Root (Join-Path $h.Home '.agents/skills')
    # pwsh.exe cannot start away from its own folder, so the stand-in Codex
    # process is a copy of the self-contained Windows PowerShell executable.
    $fake = Join-Path $h.Base 'codex.exe'
    [System.IO.File]::Copy((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'), $fake)
    $process = Start-Process -FilePath $fake -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 120') -PassThru -WindowStyle Hidden
    try {
        Start-Sleep -Seconds 2
        Assert-True (-not $process.HasExited) 'the stand-in codex.exe process exited before the check'
        foreach ($arguments in @(@('dry-run', '-Agent', 'codex'), @('apply', '-Agent', 'codex', '-Manifest', 'x', '-ManifestDigest', 'y', '-Yes'))) {
            $result = Invoke-Helper $h $arguments
            Assert-Equal 2 $result.Code "$($arguments[0]) ran while Codex ran"
            Assert-Contains $result.Err 'Codex is running' 'wrong refusal'
        }
    }
    finally { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    Assert-True (Test-Path -LiteralPath (Join-Path $h.Home '.agents/skills/assistant-reflexion')) 'skill removed while Codex ran'
}

Invoke-Contract 'cleanup settings rewrite preserves the Windows DACL' {
    if (-not $script:IsWindowsHost) { Skip-Contract 'cleanup settings rewrite preserves the Windows DACL' 'DACLs exist only on Windows'; return }
    $h = New-TestHome
    $settingsFile = Join-Path (Get-AgentHome $h 'claude') 'settings.json'
    Write-TestBytes $settingsFile '{"hooks": {"Stop": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/stop-review.sh"}]}]}}'
    $acl = Get-Acl -LiteralPath $settingsFile
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule('Everyone', 'Read', 'Allow')
    $acl.SetAccessRuleProtection($true, $true)
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $settingsFile -AclObject $acl
    $before = (Get-Acl -LiteralPath $settingsFile).Sddl
    $result = Invoke-Apply $h (Save-Manifest $h (Invoke-DryRun $h))
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-Equal $before (Get-Acl -LiteralPath $settingsFile).Sddl 'settings DACL changed'
}

Invoke-Contract 'Windows PowerShell 5.1 runs the installed helper' {
    if (-not $script:IsWindowsHost) { Skip-Contract 'Windows PowerShell 5.1 runs the installed helper' 'Windows PowerShell 5.1 exists only on Windows'; return }
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $h = New-TestHome
    Add-Reflexion $h
    $saved = $script:PowerShellExecutable
    try {
        $script:PowerShellExecutable = $powershell
        $out = Invoke-DryRun $h
        Assert-Contains $out 'skill_directory: skills/assistant-reflexion' '5.1 dry run did not offer the skill'
        $result = Invoke-Apply $h (Save-Manifest $h $out)
        Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    }
    finally { $script:PowerShellExecutable = $saved }
}

# Cross-checks with the Python reference.

Invoke-Contract 'manifest digest canonical serialization matches Python' {
    $h = New-TestHome
    if ($null -eq (Find-Python)) { Skip-Contract 'manifest digest canonical serialization matches Python' 'Python 3 unavailable'; return }
    Add-Reflexion $h
    Copy-SeedFile $script:HOOKS 'hooks/scripts/session-start.sh' (Join-Path (Get-AgentHome $h 'claude') 'hooks/assistant/session-start.sh') 'claude'
    Write-TestBytes (Join-Path (Get-AgentHome $h 'claude') 'settings.json') "{`"hooks`": {`"Stop`": [{`"hooks`": [{`"command`": `"`$HOME/.claude/hooks/assistant/stop-review.sh`", `"timeout`": 1.50, `"n`": 1e2, `"u`": `"é☃`"}]}]}}"
    $python = Invoke-Python $h @((Join-Path $script:ToolDir 'ownership.py'), 'dry-run', '--agent', 'claude')
    Assert-Equal 0 $python.Code ('python dry-run failed: ' + $python.Out)
    $pythonManifest = Get-ManifestText $python.Out
    $out = Invoke-DryRun $h
    $core = Join-Path $script:ToolDir 'ownership-core.ps1'
    $primitives = Join-Path $script:ToolDir 'installer-primitives.ps1'
    Write-TestBytes (Join-Path $h.Base 'py.json') $pythonManifest
    Write-TestBytes (Join-Path $h.Base 'ps.json') (Get-ManifestText $out)
    $command = ". '$primitives'; . '$core'; foreach (`$name in @('py', 'ps')) { " +
        "`$m = ConvertFrom-OwnershipJson -Text ([IO.File]::ReadAllText('$($h.Base)/' + `$name + '.json')); " +
        "Write-Output (`$name + ' ' + (Get-OwnershipManifestDigest -Manifest `$m) + ' ' + `$m['manifest_digest']); " +
        "foreach (`$i in `$m['items']) { Write-Output ('item ' + `$name + ' ' + `$i['root'] + ' ' + `$i['path'] + ' ' + `$i['kind'] + ' ' + `$i['digest'] + ' ' + (`$i['id'] -replace '^[^#]*', '')) } }"
    $result = Invoke-TestScript -TestHome $h -Command $command
    Assert-Equal 0 $result.Code $result.Err
    $lines = @($result.Out.Split("`n") | Where-Object { $_ })
    $pyLine = @($lines | Where-Object { $_.StartsWith('py ') })[0].Split(' ')
    Assert-Equal $pyLine[2] $pyLine[1] 'PowerShell canonical digest of the Python manifest differs from Python'
    $psLine = @($lines | Where-Object { $_.StartsWith('ps ') })[0].Split(' ')
    Assert-Equal $psLine[2] $psLine[1] 'PowerShell manifest digest is not self-consistent'
    $pyItems = @($lines | Where-Object { $_.StartsWith('item py ') } | ForEach-Object { $_.Substring(8) })
    $psItems = @($lines | Where-Object { $_.StartsWith('item ps ') } | ForEach-Object { $_.Substring(8) })
    Assert-Equal ($pyItems -join "`n") ($psItems -join "`n") 'Python and PowerShell dry runs prove different items or digests'
    Assert-True ($psItems.Count -ge 3) 'cross-check proved too few items'
}

Invoke-Contract 'directory walk hashes files in chunks and keeps no file bytes' {
    $h = New-TestHome
    $root = Join-Path $h.Base 'walk'
    $chunk = 1048576
    $boundary = New-Object byte[] ($chunk + 4)
    for ($i = 0; $i -lt $chunk - 1; $i++) { $boundary[$i] = 97 }
    $boundary[$chunk - 1] = 13; $boundary[$chunk] = 10; $boundary[$chunk + 1] = 98; $boundary[$chunk + 2] = 13; $boundary[$chunk + 3] = 10
    $lateNul = New-Object byte[] ($chunk + 7)
    for ($i = 0; $i -lt $lateNul.Length - 1; $i++) { $lateNul[$i] = if ($i % 3 -eq 1) { 13 } elseif ($i % 3 -eq 2) { 10 } else { 120 } }
    Write-TestBytes (Join-Path $root 'boundary.md') $boundary
    Write-TestBytes (Join-Path $root 'late-nul.bin') $lateNul
    $command = "`$OwnershipCheckoutNoMain = `$true; . '$($script:CheckoutEntry)'; " +
        "foreach (`$entry in (Get-OwnershipDirectoryEntries -LiteralPath '$root')) { if (`$entry.Type -ne 'file') { continue }; " +
        "`$data = [System.IO.File]::ReadAllBytes((Join-Path '$root' `$entry.Relative)); " +
        "Write-Output ((`$entry.Value -is [string]) -and `$entry.Value -ceq (Get-OwnershipSha256Hex -Bytes `$data) -and `$entry.Content -ceq (Get-OwnershipContentHash -Data `$data)) }"
    $result = Invoke-TestScript -TestHome $h -Command $command
    Assert-Equal 0 $result.Code $result.Err
    $lines = @($result.Out.Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    Assert-Equal 'True|True' ($lines -join '|') 'streamed hashes differ from whole-file hashes'
}

Invoke-Contract 'PowerShell history derivation matches content-proof.json for seeded paths' {
    $h = New-TestHome
    $command = "`$OwnershipCheckoutNoMain = `$true; . '$($script:CheckoutEntry)'; " +
        "`$inventory = (Read-OwnershipJsonFile -LiteralPath '$($script:ToolDir)/retired-items.json' -Label 'inventory').Value; " +
        "`$proofs = Get-OwnershipHistoryFingerprints -Repository '$($script:FrameworkRoot)' -Items (Get-OwnershipProofItems -Inventory `$inventory) -Revisions @('refs/remotes/origin/main'); " +
        "`$committed = (Read-OwnershipJsonFile -LiteralPath '$($script:ToolDir)/content-proof.json' -Label 'proof').Value; " +
        "Write-Output (Get-OwnershipCanonicalDigest -Value `$proofs); Write-Output (Get-OwnershipCanonicalDigest -Value `$committed['proofs']); Write-Output `$proofs.Count; " +
        "foreach (`$key in @(`$committed['proofs'].Keys)) { foreach (`$relative in @(`$committed['proofs'][`$key]['files'].Keys)) { " +
        "`$left = if (`$proofs.Contains(`$key) -and `$proofs[`$key]['files'].Contains(`$relative)) { Get-OwnershipCanonicalDigest -Value `$proofs[`$key]['files'][`$relative] } else { 'missing' }; " +
        "if (`$left -cne (Get-OwnershipCanonicalDigest -Value `$committed['proofs'][`$key]['files'][`$relative])) { " +
        "`$shown = if (`$left -eq 'missing') { 'missing' } else { (@(foreach (`$agent in @(`$proofs[`$key]['files'][`$relative].Keys)) { `$agent + '=' + ((@(`$proofs[`$key]['files'][`$relative][`$agent]) | ForEach-Object { ([string]`$_).Substring(0, 8) }) -join ',') }) -join ' ') }; " +
        "`$expected = (@(foreach (`$agent in @(`$committed['proofs'][`$key]['files'][`$relative].Keys)) { `$agent + '=' + ((@(`$committed['proofs'][`$key]['files'][`$relative][`$agent]) | ForEach-Object { ([string]`$_).Substring(0, 8) }) -join ',') }) -join ' '); " +
        "Write-Output ('differs: ' + `$key + ' :: ' + `$relative + ' :: derived ' + `$shown + ' :: committed ' + `$expected) } } }; " +
        "foreach (`$key in @(`$proofs.Keys)) { foreach (`$relative in @(`$proofs[`$key]['files'].Keys)) { if (-not (`$committed['proofs'].Contains(`$key) -and `$committed['proofs'][`$key]['files'].Contains(`$relative))) { Write-Output ('extra: ' + `$key + ' :: ' + `$relative) } } }"
    $result = Invoke-TestScript -TestHome $h -Command $command
    Assert-Equal 0 $result.Code $result.Err
    $lines = @($result.Out.Split("`n") | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ })
    $differences = @($lines | Where-Object { $_ -like 'differs: *' -or $_ -like 'extra: *' } | Select-Object -First 10) -join '; '
    Assert-Equal $lines[1] $lines[0] ('PowerShell history fingerprints differ from content-proof.json: ' + $differences)
    Assert-True ([int]$lines[2] -gt 10) 'too few proof keys derived'
}

Invoke-Contract 'generated installer primitives equal a fresh AST extraction' {
    $h = New-TestHome
    Assert-True (Test-Path -LiteralPath (Join-Path $script:ToolDir 'installer-primitives.ps1')) 'installer-primitives.ps1 missing'
    $result = Invoke-Helper $h @('build-primitives', '-Check') -Script $script:CheckoutEntry
    Assert-Equal 0 $result.Code ('build-primitives -Check failed: ' + $result.Out + $result.Err)
}

# Installer mode (checkout entry point).

Invoke-Contract 'installer mode removes proven retired skills and keeps others' {
    $h = New-TestHome
    Add-Reflexion $h
    Write-TestBytes (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-memory/SKILL.md') "other product`n"
    $result = Invoke-Helper $h @('install', '-Agent', 'claude', '-DryRun') -Script $script:CheckoutEntry
    Assert-Equal 3 $result.Code ($result.Out + $result.Err)
    Assert-Contains $result.Out '  remove: skills/assistant-reflexion (skill_directory)' 'dry run did not list the removal'
    Assert-Contains $result.Out '  [dry-run] Retired items: 1 to remove, 1 kept.' 'wrong dry-run summary'
    Assert-True (Test-Path -LiteralPath (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-reflexion')) 'dry run removed the skill'
    $result = Invoke-Helper $h @('install', '-Agent', 'claude') -Script $script:CheckoutEntry
    Assert-Equal 3 $result.Code ($result.Out + $result.Err)
    Assert-Contains $result.Out '  removed: skills/assistant-reflexion' 'skill not removed'
    Assert-Contains $result.Out '  Retired items: 1 removed, 1 kept.' 'wrong summary'
    Assert-True (Test-Path -LiteralPath (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-memory/SKILL.md')) 'other product removed'
}

# Review fixes: path identity, deletes, strict rewrites, inventory ids.

function Get-CaseVariant {
    param([string]$Path)
    $leaf = [System.IO.Path]::GetFileName($Path)
    $variant = Join-Path ([System.IO.Path]::GetDirectoryName($Path)) $leaf.ToUpperInvariant()
    if ($variant -ceq $Path -or -not [System.IO.Directory]::Exists($variant)) { return $null }
    return $variant
}

Invoke-Contract 'inventory id with a hash mark refused' {
    $h = New-TestHome
    $copy = Join-Path $h.Base 'helper'
    [void][System.IO.Directory]::CreateDirectory($copy)
    foreach ($name in @('ownership.ps1', 'ownership-core.ps1', 'installer-primitives.ps1', 'content-proof.json')) {
        [System.IO.File]::Copy((Join-Path $script:ToolDir $name), (Join-Path $copy $name))
    }
    $inventory = Read-TestText (Join-Path $script:ToolDir 'retired-items.json')
    Assert-True ($inventory.Contains('"id": "skill/assistant-memory"')) 'fixture id not found'
    Write-TestBytes (Join-Path $copy 'retired-items.json') ($inventory.Replace('"id": "skill/assistant-memory"', '"id": "skill/assistant-memory#x"'))
    $result = Invoke-Helper $h @('validate') -Script (Join-Path $copy 'ownership.ps1')
    Assert-Equal 2 $result.Code 'an id with # was accepted'
    Assert-Contains $result.Err 'inventory entry id missing or invalid' 'wrong refusal'
}

Invoke-Contract 'user home refusal compares path identity' {
    $h = New-TestHome
    $aliases = New-Object System.Collections.ArrayList
    $variant = Get-CaseVariant $h.Home
    if ($null -ne $variant) { [void]$aliases.Add($variant) }
    $link = Join-Path $h.Base 'home-alias'
    $linkType = if ($script:IsWindowsHost) { 'Junction' } else { 'SymbolicLink' }
    [void](New-Item -ItemType $linkType -Path $link -Target $h.Home)
    [void]$aliases.Add($link)
    foreach ($alias in $aliases) {
        $result = Invoke-Helper $h @('dry-run', '-Agent', 'codex') -CodexHome $alias
        Assert-Equal 2 $result.Code ("an alias of the user home was accepted: $alias " + $result.Out)
        Assert-Contains $result.Err 'the agent home resolves to the user home itself' "wrong refusal for $alias"
    }
}

Invoke-Contract 'manifest-out containment follows links into the agent home' {
    $h = New-TestHome
    Add-Reflexion $h
    $link = Join-Path $h.Base 'into-home'
    if (-not (New-TestSymbolicLink -Path $link -Target (Get-AgentHome $h 'claude'))) {
        Skip-Contract 'manifest-out containment follows links into the agent home' 'this Windows account cannot create symbolic links (needs elevation or Developer Mode)'; return
    }
    $result = Invoke-Helper $h @('dry-run', '-Agent', 'claude', '-ManifestOut', (Join-Path $link 'manifest.json'))
    Assert-Equal 2 $result.Code 'a manifest inside the home through a link was accepted'
    Assert-Contains $result.Err '-ManifestOut must be outside the agent home and every inventory root' 'wrong refusal'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Get-AgentHome $h 'claude') 'manifest.json'))) 'manifest written into the home'
}

Invoke-Contract 'manifest-out containment follows junctions into the agent home' {
    if (-not $script:IsWindowsHost) { Skip-Contract 'manifest-out containment follows junctions into the agent home' 'directory junctions exist only on Windows'; return }
    $h = New-TestHome
    Add-Reflexion $h
    $link = Join-Path $h.Base 'into-home'
    [void](New-Item -ItemType Junction -Path $link -Target (Get-AgentHome $h 'claude'))
    $result = Invoke-Helper $h @('dry-run', '-Agent', 'claude', '-ManifestOut', (Join-Path $link 'manifest.json'))
    Assert-Equal 2 $result.Code 'a manifest inside the home through a junction was accepted'
}

Invoke-Contract 'parent chain check refuses a linked parent before delete' {
    $h = New-TestHome
    $root = Join-Path $h.Base 'root'
    Write-TestBytes (Join-Path $root 'a/b/file.txt') "x`n"
    $outside = Join-Path $h.Base 'outside'
    Write-TestBytes (Join-Path $outside 'b/file.txt') "y`n"
    $core = Join-Path $script:ToolDir 'ownership-core.ps1'
    $primitives = Join-Path $script:ToolDir 'installer-primitives.ps1'
    $linkType = if ($script:IsWindowsHost) { 'Junction' } else { 'SymbolicLink' }
    $command = "Set-StrictMode -Version 2.0; `$ErrorActionPreference = 'Stop'; . '$primitives'; . '$core'; " +
        "Assert-OwnershipParentChain -Root '$root' -LiteralPath '$root/a/b/file.txt'; Write-Output 'plain ok'; " +
        "[IO.Directory]::Move('$root/a', '$root/a-moved'); [void](New-Item -ItemType $linkType -Path '$root/a' -Target '$outside'); " +
        "try { Assert-OwnershipParentChain -Root '$root' -LiteralPath '$root/a/b/file.txt'; Write-Output 'linked ok' } catch { Write-Output ('linked refused: ' + `$_.Exception.Message) }"
    $result = Invoke-TestScript -TestHome $h -Command $command
    Assert-Equal 0 $result.Code $result.Err
    Assert-Contains $result.Out 'plain ok' 'a plain parent chain was refused'
    Assert-Contains $result.Out 'linked refused: ' 'a linked parent was accepted'
    Assert-Equal "y`n" (Read-TestText (Join-Path $outside 'b/file.txt')) 'link target changed'
}

Invoke-Contract 'settings rewrite refuses a linked ancestor below the home' {
    $h = New-TestHome
    $root = Join-Path $h.Base 'root'
    Write-TestBytes (Join-Path $root 'a/config/settings.json') "old`n"
    $outside = Join-Path $h.Base 'outside'
    Write-TestBytes (Join-Path $outside 'config/settings.json') "new`n"
    $core = Join-Path $script:ToolDir 'ownership-core.ps1'
    $primitives = Join-Path $script:ToolDir 'installer-primitives.ps1'
    $linkType = if ($script:IsWindowsHost) { 'Junction' } else { 'SymbolicLink' }
    $bytes = "([byte[]]@(110, 101, 119, 10))"
    $command = "Set-StrictMode -Version 2.0; `$ErrorActionPreference = 'Stop'; . '$primitives'; . '$core'; " +
        "Write-OwnershipRewrite -Root '$root' -LiteralPath '$root/a/config/settings.json' -Data $bytes -ExpectedBytes ([byte[]]@(111, 108, 100, 10)); Write-Output 'plain ok'; " +
        "[IO.Directory]::Move('$root/a', '$root/a-moved'); [void](New-Item -ItemType $linkType -Path '$root/a' -Target '$outside'); " +
        "try { Write-OwnershipRewrite -Root '$root' -LiteralPath '$root/a/config/settings.json' -Data ([byte[]]@(120, 10)) -ExpectedBytes $bytes; Write-Output 'linked ok' } catch { Write-Output ('linked refused: ' + `$_.Exception.Message) }"
    $result = Invoke-TestScript -TestHome $h -Command $command
    Assert-Equal 0 $result.Code $result.Err
    Assert-Contains $result.Out 'plain ok' 'a plain rewrite failed'
    Assert-Equal "new`n" (Read-TestText (Join-Path $root 'a-moved/config/settings.json')) 'plain rewrite wrote the wrong bytes'
    Assert-Contains $result.Out 'linked refused: ' 'a rewrite through a linked ancestor was accepted'
    Assert-Equal "new`n" (Read-TestText (Join-Path $outside 'config/settings.json')) 'link target changed'
}

Invoke-Contract 'settings rewrite that cannot be encoded strictly is skipped and leaves the file unchanged' {
    $h = New-TestHome
    $settingsFile = Join-Path (Get-AgentHome $h 'claude') 'settings.json'
    $text = '{"note": "\ud800", "hooks": {"Stop": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/stop-review.sh"}]}]}}'
    Write-TestBytes $settingsFile $text
    $before = [System.IO.File]::ReadAllBytes($settingsFile)
    $out = Invoke-DryRun $h
    Assert-Contains $out 'hook_registration: hooks/assistant/stop-review.sh (registration settings.json/Stop/0)' 'registration not offered'
    $result = Invoke-Apply $h (Save-Manifest $h $out)
    Assert-Equal 3 $result.Code ($result.Out + $result.Err)
    Assert-Contains $result.Out 'skipped: hooks/assistant/stop-review.sh:' 'unencodable rewrite not skipped'
    Assert-True ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before, [byte[]][System.IO.File]::ReadAllBytes($settingsFile))) 'settings file changed'
}

Invoke-Contract 'settings with non-finite numbers are preserved' {
    $h = New-TestHome
    $settingsFile = Join-Path (Get-AgentHome $h 'claude') 'settings.json'
    foreach ($number in @('1e9999', '-1e9999')) {
        $text = '{"limit": ' + $number + ', "hooks": {"Stop": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/stop-review.sh"}]}]}}'
        Write-TestBytes $settingsFile $text
        $before = [System.IO.File]::ReadAllBytes($settingsFile)
        $out = Invoke-DryRun $h
        Assert-True (-not $out.Contains('hook_registration: hooks/assistant/stop-review.sh (registration')) "registration offered with $number"
        Assert-Contains $out "number $number cannot be written back unchanged" "non-finite $number not reported"
        $result = Invoke-Apply $h (Save-Manifest $h $out)
        Assert-True ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before, [byte[]][System.IO.File]::ReadAllBytes($settingsFile))) "settings file changed with $number"
    }
}

Invoke-Contract 'uninstall checkout overlap compares path identity' {
    $h = New-TestHome
    $fw = Get-CheckoutClone
    $aliases = New-Object System.Collections.ArrayList
    $variant = Get-CaseVariant $fw
    if ($null -ne $variant) { [void]$aliases.Add((Join-Path $variant 'codex-home')) }
    $link = Join-Path $h.Base 'checkout-alias'
    $linkType = if ($script:IsWindowsHost) { 'Junction' } else { 'SymbolicLink' }
    [void](New-Item -ItemType $linkType -Path $link -Target (Join-Path $fw 'docs'))
    [void]$aliases.Add((Join-Path $link 'codex-home'))
    foreach ($alias in $aliases) {
        $result = Invoke-TestUninstall $h 'codex' @('-DryRun') -CodexHome $alias
        Assert-Equal 2 $result.Code ("an alias inside the checkout was accepted: $alias " + $result.Out)
        Assert-True ($result.Err.Contains('overlap') -or $result.Err.Contains('located inside an agent home')) ("wrong refusal for ${alias}: " + $result.Err)
    }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $fw 'docs/codex-home'))) 'uninstall created a home inside the checkout'
}

# T6: uninstall.

Invoke-Contract 'uninstall noninteractive without -Yes refuses' {
    $h = New-TestHome
    [void](Invoke-TestInstall $h 'claude')
    $before = Get-TreeSnapshot $h.Home
    $result = Invoke-TestUninstall $h 'claude'
    Assert-Equal 2 $result.Code ($result.Out + $result.Err)
    Assert-Contains $result.Err 'requires -Yes and -PlanDigest' 'wrong refusal'
    $result = Invoke-TestUninstall $h 'claude' @('-Yes')
    Assert-Equal 2 $result.Code 'bare -Yes accepted'
    Assert-Contains $result.Err '-Yes requires -PlanDigest' 'wrong refusal'
    Assert-Equal $before (Get-TreeSnapshot $h.Home) 'refused uninstall changed the home'
    $plan = Get-PlanDigest $h 'claude'
    Write-TestBytes (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-docs/extra.md') "x`n"
    $before = Get-TreeSnapshot $h.Home
    $result = Invoke-TestUninstall $h 'claude' @('-Yes', '-PlanDigest', $plan.Digest)
    Assert-Equal 2 $result.Code 'stale plan digest accepted'
    Assert-Contains $result.Out 'Current plan digest:' 'no current digest shown'
    Assert-Equal $before (Get-TreeSnapshot $h.Home) 'stale-digest uninstall changed the home'
}

Invoke-Contract 'uninstall claude complete removal' {
    $h = New-TestHome
    Add-Sentinels $h 'claude'
    [void](Invoke-TestInstall $h 'claude')
    $claude = Get-AgentHome $h 'claude'
    $userText = "# Mine`n<!-- CODEX_DEEPSEEK_WORKFLOW_GLOBAL_V1_START -->`nother tool`n<!-- CODEX_DEEPSEEK_WORKFLOW_GLOBAL_V1_END -->`n"
    $generated = Read-TestText (Join-Path $claude 'CLAUDE.md')
    Write-TestBytes (Join-Path $claude 'CLAUDE.md') ($generated + "`n" + $userText)
    $sentinels = @{}
    foreach ($path in @('tools/company-custom-tool.txt', 'docs/evals/custom.md', 'config.toml', 'skills/my-skill', 'telos', 'rules/default.rules', 'agents/my-agent.md')) { $sentinels[$path] = Get-TreeSnapshot (Join-Path $claude $path) }
    $result = Invoke-ConfirmedUninstall $h 'claude'
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-Equal '' ((Get-FrameworkItemsLeft $h $claude 'claude') -join ', ') 'framework items left'
    Assert-Equal $userText (Read-TestText (Join-Path $claude 'CLAUDE.md')) 'CLAUDE.md user text changed'
    foreach ($path in @($sentinels.Keys)) { Assert-Equal $sentinels[$path] (Get-TreeSnapshot (Join-Path $claude $path)) "sentinel changed: $path" }
    Assert-Contains (Get-PlanDigest $h 'claude').Out 'Removable (0):' 'second plan still removes items'
    Assert-OutsideUnchanged $h
}

Invoke-Contract 'uninstall codex rules and notice' {
    $h = New-TestHome
    [void](Invoke-TestInstall $h 'codex')
    $codex = Get-AgentHome $h 'codex'
    Write-TestBytes (Join-Path $codex 'rules/default.rules') "user rule`n"
    $result = Invoke-ConfirmedUninstall $h 'codex'
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $codex 'rules/workflow.rules'))) 'workflow.rules kept'
    Assert-Contains $result.Out 'no longer installed' 'no rules notice'
    Assert-Contains $result.Out 'git push' 'rules notice incomplete'
    Assert-Equal "user rule`n" (Read-TestText (Join-Path $codex 'rules/default.rules')) 'user rule changed'
    Assert-Equal '' ((Get-FrameworkItemsLeft $h $codex 'codex') -join ', ') 'framework items left'
}

Invoke-Contract 'uninstall modified rules file kept' {
    $h = New-TestHome
    [void](Invoke-TestInstall $h 'codex')
    $rules = Join-Path (Get-AgentHome $h 'codex') 'rules/workflow.rules'
    [System.IO.File]::AppendAllText($rules, "# mine`n")
    $result = Invoke-ConfirmedUninstall $h 'codex'
    Assert-Equal 3 $result.Code ($result.Out + $result.Err)
    Assert-True (Test-Path -LiteralPath $rules) 'modified rules removed'
    Assert-NotContains $result.Out 'no longer installed' 'notice shown for kept rules'
}

Invoke-Contract 'uninstall ambiguous AGENTS.md unchanged exit 3' {
    $h = New-TestHome
    [void](Invoke-TestInstall $h 'codex')
    $agentsMd = Join-Path (Get-AgentHome $h 'codex') 'AGENTS.md'
    [System.IO.File]::AppendAllText($agentsMd, "`n<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->`n")
    $before = [System.IO.File]::ReadAllBytes($agentsMd)
    $result = Invoke-ConfirmedUninstall $h 'codex'
    Assert-Equal 3 $result.Code ($result.Out + $result.Err)
    Assert-Contains $result.Out 'AGENTS.md: ambiguous, duplicate or unbalanced markers' 'AGENTS.md not kept'
    Assert-True ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before, [byte[]][System.IO.File]::ReadAllBytes($agentsMd))) 'AGENTS.md changed'
}

Invoke-Contract 'uninstall preflight refuses overlap' {
    $h = New-TestHome
    $fw = Get-CheckoutClone
    $before = Get-TreeSnapshot (Join-Path $fw 'skills')
    foreach ($custom in @($fw, [System.IO.Path]::GetDirectoryName($fw))) {
        $result = Invoke-TestUninstall $h 'codex' @('-DryRun') -CodexHome $custom
        Assert-Equal 2 $result.Code "overlapping CODEX_HOME=$custom accepted"
        Assert-True ($result.Err.Contains('overlap') -or $result.Err.Contains('located inside an agent home')) ('wrong refusal: ' + $result.Err)
    }
    Assert-Equal $before (Get-TreeSnapshot (Join-Path $fw 'skills')) 'checkout changed'
    $result = Invoke-TestUninstall $h 'codex' @('-DryRun') -CodexHome $h.Home
    Assert-Equal 2 $result.Code 'CODEX_HOME equal to the user home accepted'
}

Invoke-Contract 'uninstall custom codex home' {
    $h = New-TestHome
    $custom = Join-Path $h.Base 'custom-codex'
    $h.CodexHome = $custom
    [void](Invoke-TestInstall $h 'codex' -CodexHome $custom)
    $result = Invoke-ConfirmedUninstall $h 'codex' -CodexHome $custom
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-Equal '' ((Get-FrameworkItemsLeft $h $custom 'codex') -join ', ') 'framework items left'
}

Invoke-Contract 'uninstall proves copies installed by the d11756d installer' {
    $h = New-TestHome
    $old = Join-Path $h.Base 'old'
    $archive = Join-Path $h.Base 'old.zip'
    [void](Invoke-GitBytes $script:FrameworkRoot @('archive', '--format=zip', '-o', $archive, $script:D11756D))
    Expand-Archive -LiteralPath $archive -DestinationPath $old
    try {
        [void](Invoke-TestInstall $h 'claude' -Framework $old)
        $claude = Get-AgentHome $h 'claude'
        $result = Invoke-ConfirmedUninstall $h 'claude'
        Assert-True ($result.Code -eq 0 -or $result.Code -eq 3) ($result.Out + $result.Err)
        $left = @()
        if ([System.IO.Directory]::Exists((Join-Path $claude 'skills'))) { $left = @([System.IO.Directory]::GetFileSystemEntries((Join-Path $claude 'skills'))) }
        Assert-Equal '' ($left -join ', ') ('skills left: ' + $result.Out)
        Assert-Equal '' ((Get-FrameworkItemsLeft $h $claude 'claude') -join ', ') ('framework items left: ' + $result.Out)
    }
    finally { Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Contract 'uninstall of a home with no framework is a no-op' {
    $h = New-TestHome
    [void][System.IO.Directory]::CreateDirectory((Get-AgentHome $h 'gemini'))
    Add-Sentinels $h 'gemini'
    $before = Get-TreeSnapshot $h.Home
    $result = Invoke-ConfirmedUninstall $h 'gemini'
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-Contains $result.Out 'Removable (0):' 'items offered'
    Assert-Equal $before (Get-TreeSnapshot $h.Home) 'no-op uninstall changed the home'
}

Invoke-Contract 'uninstall of a used tool directory' {
    $h = New-TestHome
    [void](Invoke-TestInstall $h 'claude')
    $tool = Join-Path (Get-AgentHome $h 'claude') 'tools/cognitive-complexity'
    if (-not [System.IO.Directory]::Exists($tool)) { $tool = Join-Path (Get-AgentHome $h 'claude') 'tools/progress' }
    foreach ($name in @('bin/Debug/x.dll', 'obj/project.assets.json', '.publish/run', '__pycache__/x.cpython-39.pyc', 'loose.cpython-39.pyc')) { Write-TestBytes (Join-Path $tool $name) ([byte[]](0, 98, 10)) }
    $result = Invoke-ConfirmedUninstall $h 'claude'
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-True (-not (Test-Path -LiteralPath $tool)) 'used tool directory kept'
    [void](Invoke-TestInstall $h 'claude')
    Write-TestBytes (Join-Path $tool 'bin/x.dll') ([byte[]](0))
    Write-TestBytes (Join-Path $tool 'notes.md') "mine`n"
    $result = Invoke-ConfirmedUninstall $h 'claude'
    Assert-Equal 3 $result.Code ($result.Out + $result.Err)
    Assert-True (Test-Path -LiteralPath (Join-Path $tool 'notes.md')) 'user file removed'
    Assert-Contains $result.Out 'file does not match framework content: notes.md' 'user file not reported'
}

Invoke-Contract 'placeholder variants only for skill files' {
    $h = New-TestHome
    $command = "`$OwnershipCheckoutNoMain = `$true; . '$($script:CheckoutEntry)'; " +
        "`$data = `$script:OwnershipUtf8.GetBytes('state lives in {agent_state_dir}/memory' + [char]10); " +
        "foreach (`$name in @('skills/assistant-docs/SKILL.md', 'tools/framework-ownership/README.md', 'docs/evals/notes.md', 'agents/claude/x.md')) { " +
        "Write-Output (`$name + '=' + (Get-OwnershipBlobFingerprints -Name `$name -Data `$data -Agents @('claude'))['claude'].Count) }"
    $result = Invoke-TestScript -TestHome $h -Command $command
    Assert-Equal 0 $result.Code $result.Err
    Assert-Contains $result.Out 'skills/assistant-docs/SKILL.md=2' 'skill file lost its substituted variant'
    foreach ($name in @('tools/framework-ownership/README.md', 'docs/evals/notes.md', 'agents/claude/x.md')) {
        Assert-Contains $result.Out "$name=1" "$name gained a substituted variant"
    }
}

Invoke-Contract 'blob reader refuses a missing blob' {
    $h = New-TestHome
    $command = "`$OwnershipCheckoutNoMain = `$true; . '$($script:CheckoutEntry)'; " +
        "try { [void](Read-OwnershipBlobs -Repository '$($script:FrameworkRoot)' -Blobs @('$('0' * 39)1')); Write-Output 'read' } catch { Write-Output ('refused: ' + `$_.Exception.Message) }"
    $result = Invoke-TestScript -TestHome $h -Command $command
    Assert-Equal 0 $result.Code $result.Err
    Assert-Contains $result.Out 'refused: ' 'a missing blob was read as empty'
    Assert-Contains $result.Out 'did not return blob' 'wrong refusal'
}

Invoke-Contract 'uninstall keeps a linked evals node_modules' {
    $h = New-TestHome
    [void](Invoke-TestInstall $h 'claude')
    $evals = Join-Path (Get-AgentHome $h 'claude') 'tools/evals'
    Assert-True ([System.IO.Directory]::Exists($evals)) 'tools/evals not installed'
    $modules = Join-Path $evals 'node_modules'
    if (Test-Path -LiteralPath $modules) { Remove-Item -LiteralPath $modules -Recurse -Force }
    $elsewhere = Join-Path $h.Base 'shared-node-modules'
    Write-TestBytes (Join-Path $elsewhere 'pkg/index.js') "user`n"
    $linkType = if ($script:IsWindowsHost) { 'Junction' } else { 'SymbolicLink' }
    [void](New-Item -ItemType $linkType -Path $modules -Target $elsewhere)
    $result = Invoke-ConfirmedUninstall $h 'claude'
    Assert-Equal 3 $result.Code ($result.Out + $result.Err)
    Assert-Contains $result.Out 'symbolic link inside the item: node_modules' 'linked node_modules not reported'
    Assert-True (Test-Path -LiteralPath $modules) 'linked node_modules removed'
    Assert-Equal "user`n" (Read-TestText (Join-Path $elsewhere 'pkg/index.js')) 'link target changed'
}

Invoke-Contract 'uninstall keeps never-synced or edited tool files' {
    $h = New-TestHome
    [void](Invoke-TestInstall $h 'claude')
    $tool = Join-Path (Get-AgentHome $h 'claude') 'tools/framework-ownership'
    Assert-True ([System.IO.Directory]::Exists($tool)) 'tools/framework-ownership not installed'
    $copied = Join-Path $tool 'ownership-checkout.ps1'
    Write-TestBytes $copied ([System.IO.File]::ReadAllBytes((Join-Path (Get-CheckoutClone) 'tools/framework-ownership/ownership-checkout.ps1')))
    $result = Invoke-ConfirmedUninstall $h 'claude'
    Assert-Equal 3 $result.Code ($result.Out + $result.Err)
    Assert-Contains $result.Out 'tools/framework-ownership: file does not match framework content: ownership-checkout.ps1' 'checkout-only copy proven'
    Assert-True (Test-Path -LiteralPath $copied) 'checkout-only copy removed'
    Remove-Item -LiteralPath $copied -Force
    $readme = Join-Path $tool 'README.md'
    $text = Read-TestText $readme
    Assert-True ($text.Contains('{agent_state_dir}')) 'README holds no placeholder'
    Write-TestBytes $readme ($text.Replace('{agent_state_dir}', '.claude'))
    $result = Invoke-ConfirmedUninstall $h 'claude'
    Assert-Equal 3 $result.Code ($result.Out + $result.Err)
    Assert-Contains $result.Out 'tools/framework-ownership: file does not match framework content: README.md' 'edited README proven'
    Assert-True (Test-Path -LiteralPath $readme) 'edited README removed'
}

Invoke-Contract 'uninstall removes registration and shim in one run' {
    $h = New-TestHome
    $claude = Get-AgentHome $h 'claude'
    $fw = (Get-CheckoutClone).Replace('\', '/')
    Write-TestBytes (Join-Path $claude 'hooks/assistant/session-start.sh') $script:ShimText
    $settings = '{"hooks": {"SessionStart": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/session-start.sh"}, {"command": "' + $fw + '/hooks/scripts/session-start.sh"}]}], "Stop": [{"hooks": [{"command": "$HOME/.claude/hooks/assistant/session-start.sh"}]}]}, "mcpServers": {"a": {}}}'
    Write-TestBytes (Join-Path $claude 'settings.json') $settings
    $plan = Get-PlanDigest $h 'claude'
    foreach ($suffix in @('SessionStart/0', 'SessionStart/1', 'Stop/0')) { Assert-Contains $plan.Out "(registration settings.json/$suffix)" "registration $suffix not offered" }
    $result = Invoke-TestUninstall $h 'claude' @('-Yes', '-PlanDigest', $plan.Digest)
    Assert-Equal 0 $result.Code ($result.Out + $result.Err)
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $claude 'hooks/assistant/session-start.sh'))) 'shim kept'
    Assert-Equal "{`n  `"hooks`": {},`n  `"mcpServers`": {`n    `"a`": {}`n  }`n}`n" (Read-TestText (Join-Path $claude 'settings.json')) 'settings not rewritten as expected'
}

Invoke-Contract 'uninstall registration from another checkout kept' {
    $h = New-TestHome
    Write-TestBytes (Join-Path (Get-AgentHome $h 'claude') 'settings.json') '{"hooks": {"Stop": [{"hooks": [{"command": "/other/fw/hooks/scripts/session-start.sh"}]}]}}'
    $result = Invoke-TestUninstall $h 'claude' @('-DryRun')
    Assert-Contains $result.Out 'possible framework checkout path' 'another checkout registration offered'
}

Invoke-Contract 'uninstall keeps an unknown file inside a framework skill directory' {
    $h = New-TestHome
    [void](Invoke-TestInstall $h 'claude')
    $notes = Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-docs/notes.md'
    Write-TestBytes $notes "mine`n"
    $result = Invoke-ConfirmedUninstall $h 'claude'
    Assert-Equal 3 $result.Code ($result.Out + $result.Err)
    Assert-True (Test-Path -LiteralPath $notes) 'user file removed'
    Assert-Contains $result.Out 'skills/assistant-docs: file does not match framework content: notes.md' 'user file not reported'
    Assert-Contains $result.Out 'Completed with items kept; they are listed above.' 'no kept summary'
}

Invoke-Contract 'uninstall interactive confirmation' {
    $h = New-TestHome
    [void](Invoke-TestInstall $h 'claude')
    $entry = Join-Path (Get-CheckoutClone) 'tools/framework-ownership/ownership-checkout.ps1'
    foreach ($case in @(@('no', 2, $true), @('claude', 0, $false))) {
        $command = "`$OwnershipCheckoutNoMain = `$true; . '$entry'; " +
            "function Test-OwnershipInteractive { `$true }; function Read-OwnershipConfirmationLine { '$($case[0])' }; " +
            "exit (Invoke-OwnershipCheckoutMain -Arguments @('uninstall', '-Agent', 'claude'))"
        $result = Invoke-TestScript -TestHome $h -Command $command
        Assert-Equal $case[1] $result.Code ("answer $($case[0]): " + $result.Out + $result.Err)
        Assert-Contains $result.Out 'Type the agent name (claude) to remove' 'no typed confirmation prompt'
        Assert-Equal $case[2] (Test-Path -LiteralPath (Join-Path (Get-AgentHome $h 'claude') 'skills/assistant-docs')) "answer $($case[0]) gave the wrong result"
    }
}

}
finally {
    Remove-Item -LiteralPath $script:SuiteRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Framework ownership contracts: Passed $script:Passed, Failed $script:Failed, Skipped $script:Skipped"
if ($script:Failed -gt 0 -or ($FailOnSkip -and $script:Skipped -gt 0)) { exit 1 }
exit 0
