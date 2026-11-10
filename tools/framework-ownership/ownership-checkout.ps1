#requires -Version 5.1
<#
.SYNOPSIS
Checkout-only Assistant Framework ownership entry point (Windows).

.DESCRIPTION
Never installed into an agent home: both installers exclude this file from the
tools sync. It reuses the installed helper's proof code (ownership-core.ps1)
and adds:

  install          Installer mode: remove proven-owned retired skills and agent
                   files. Called by install.ps1; takes no manifest, never prompts.
  uninstall        Remove every proven framework-owned item for one agent.
  build-primitives Regenerate installer-primitives.ps1 from install.ps1 by AST
                   extraction; -Check verifies the committed file.

It refuses to run unless it sits in a Git checkout whose root holds install.sh
and install.ps1, outside every agent home and ~/.agents. PowerShell 5.1 and 7.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:OwnershipToolDirectory = $PSScriptRoot
$script:OwnershipPrimitivesFile = Join-Path $script:OwnershipToolDirectory 'installer-primitives.ps1'
if (Test-Path -LiteralPath $script:OwnershipPrimitivesFile -PathType Leaf) { . $script:OwnershipPrimitivesFile }
. (Join-Path $script:OwnershipToolDirectory 'ownership-core.ps1')

# install.ps1 functions and script constants the ownership scripts reuse. The
# generator adds every install.ps1 function these call, in source order.
$script:OwnershipPrimitiveRoots = @(
    'Test-IsWindowsHost', 'Assert-CodexStopped', 'Assert-SafeConfiguredHomePathText', 'Get-FullPath',
    'Normalize-PathForComparison', 'Test-PathEqual', 'Assert-NoReparseTraversal', 'Assert-SafeManagedChild',
    'Assert-NoSourceTargetOverlap', 'Read-StrictUtf8Text', 'Write-AtomicText', 'Open-WindowsFileSecurityStream',
    'Get-WindowsFileIdentity', 'Get-WindowsFileLinkCount', 'Assert-JsonTextPropertyIdentitySafe',
    'Get-CommandExecutableToken', 'Normalize-HookPath', 'Test-ContainsExactMarkerLine', 'Get-CurrentPowerShellExecutable'
)
$script:OwnershipPrimitiveConstants = @(
    '$script:Utf8NoBom', '$script:Utf8Strict', '$script:MaxJsonInputBytes', '$script:MaxJsonIdentityDepth',
    '$script:MaxJsonIdentityProperties', '$script:MaxJsonIdentityValues'
)

# Top-level tools entries the installers never install (install.sh
# set_owned_sync_exclusions; install.ps1 $toolExclusions and source-only paths).
$script:OwnershipToolTopLevelExcludes = @('.DS_Store', 'memory-graph', 'context-budget-report.sh', 'plugins')
$script:OwnershipToolNameExcludes = @('.DS_Store', '.publish', 'bin', 'obj', '__pycache__')
# Tool-relative source paths the installers never sync (install.ps1
# $toolSyncExcludedExactPaths; install.sh OWNED_SYNC_EXACT_EXCLUDES for tools).
$script:OwnershipToolExactExcludes = @(
    'evals/run-codex-framework-evals.sh',
    'evals/finalize-workflow-kernel-review.sh',
    'evals/lib/context-budget-evidence.sh',
    'evals/validate-promotion-decision-schema.cjs',
    'evals/package.json',
    'evals/package-lock.json',
    'evals/node_modules',
    'framework-ownership/ownership-checkout.py',
    'framework-ownership/ownership-checkout.ps1'
)
$script:OwnershipCodexCommonTools = @('change-impact', 'progress')
$script:OwnershipCurrentBlockStart = '<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_START -->'
$script:OwnershipCurrentBlockEnd = '<!-- ASSISTANT_FRAMEWORK_AGENTS_MD_END -->'
$script:OwnershipCurrentInstructionFiles = @{ claude = 'CLAUDE.md'; codex = 'AGENTS.md' }
$script:OwnershipRulesNotice = "The framework's Codex execution-policy safeguards are no longer installed: the prompts " +
    'for git push, force push, git commit, git reset --hard, git branch -D and rm -rf ' +
    '(rules/workflow.rules).'

# ── Location checks ─────────────────────────────────────────────────────────

function Get-OwnershipCheckoutRoot {
    return ([System.IO.Path]::GetFullPath((Join-Path (Join-Path $script:OwnershipToolDirectory '..') '..')))
}

# Return why this entry point must not run here, or $null.
function Get-OwnershipLocationProblem {
    $root = Get-OwnershipCheckoutRoot
    foreach ($name in @('install.sh', 'install.ps1')) {
        if (-not [System.IO.File]::Exists((Join-Path $root $name))) { return "not inside a framework checkout ($name missing at $root)" }
    }
    $git = Join-Path $root '.git'
    if (-not [System.IO.File]::Exists($git) -and -not [System.IO.Directory]::Exists($git)) { return "not inside a Git checkout (no .git at $root)" }
    $homes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($userHome in @($env:USERPROFILE, $env:HOME)) {
        if ([string]::IsNullOrWhiteSpace($userHome)) { continue }
        foreach ($name in @('.claude', '.codex', '.gemini', '.agents')) { [void]$homes.Add((Join-Path $userHome $name)) }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { [void]$homes.Add($env:CODEX_HOME) }
    foreach ($agentHome in $homes) {
        try { $inside = Test-OwnershipSameOrInside $script:OwnershipToolDirectory $agentHome }
        catch { $inside = $false }
        if ($inside) { return "located inside an agent home or ~/.agents ($agentHome)" }
    }
    return $null
}

function Assert-OwnershipLocation {
    $problem = Get-OwnershipLocationProblem
    if ($problem) { Stop-OwnershipRefusal $problem }
}

# ── Processes and Git ───────────────────────────────────────────────────────

# Quote one argument for CreateProcess / the .NET argument parser.
function ConvertTo-OwnershipProcessArgument {
    param([string]$Value)
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $backslashes++; continue }
        if ($character -eq '"') { [void]$builder.Append(('\' * ($backslashes * 2 + 1)) + '"') }
        else { [void]$builder.Append(('\' * $backslashes) + $character) }
        $backslashes = 0
    }
    [void]$builder.Append(('\' * ($backslashes * 2)) + '"')
    return $builder.ToString()
}

# Run git with byte-level stdin and stdout. Returns @{Code; Output (bytes); Error}.
function Invoke-OwnershipGit {
    param([string]$Repository, [string[]]$Arguments, [byte[]]$InputBytes = $null, [switch]$NoCheck)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'git'
    $startInfo.Arguments = ((@('-C', $Repository) + $Arguments | ForEach-Object { ConvertTo-OwnershipProcessArgument ([string]$_) }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    # Windows PowerShell (.NET Framework) wraps the child's stdin in a writer
    # using the console input encoding and writes its preamble at start, so a
    # UTF-8 console sends a BOM before InputBytes. Use a BOM-free encoding with
    # the same code page while the process starts, then restore it.
    $savedInputEncoding = $null
    if ($PSVersionTable.PSEdition -ne 'Core') {
        try {
            $current = [Console]::InputEncoding
            if ($current.GetPreamble().Length -gt 0 -and $current.CodePage -eq 65001) {
                [Console]::InputEncoding = New-Object System.Text.UTF8Encoding $false
                $savedInputEncoding = $current
            }
        }
        catch { $savedInputEncoding = $null }
    }
    try { $process = [System.Diagnostics.Process]::Start($startInfo) }
    catch { Stop-OwnershipRefusal "git is unavailable: $($_.Exception.Message)" }
    finally {
        if ($null -ne $savedInputEncoding) { try { [Console]::InputEncoding = $savedInputEncoding } catch { } }
    }
    $buffer = New-Object System.IO.MemoryStream
    $copy = $process.StandardOutput.BaseStream.CopyToAsync($buffer)
    $errorTask = $process.StandardError.ReadToEndAsync()
    if ($null -ne $InputBytes) { $process.StandardInput.BaseStream.Write($InputBytes, 0, $InputBytes.Length) }
    $process.StandardInput.Close()
    $copy.Wait()
    $process.WaitForExit()
    $result = @{ Code = $process.ExitCode; Output = $buffer.ToArray(); Error = $errorTask.Result }
    $process.Dispose()
    if (-not $NoCheck -and $result.Code -ne 0) {
        $shown = @($Arguments | Select-Object -First 2) -join ' '
        Stop-OwnershipRefusal "git $shown failed: $($result.Error.Trim())"
    }
    return $result
}

function Get-OwnershipGitText {
    param([string]$Repository, [string[]]$Arguments)
    return $script:OwnershipUtf8.GetString((Invoke-OwnershipGit -Repository $Repository -Arguments $Arguments).Output)
}

function Get-OwnershipMainRef {
    param([string]$Repository, [switch]$Optional)
    foreach ($ref in @('refs/remotes/origin/main', 'refs/heads/main')) {
        if ((Invoke-OwnershipGit -Repository $Repository -Arguments @('rev-parse', '--verify', '--quiet', ($ref + '^{commit}')) -NoCheck).Code -eq 0) { return $ref }
    }
    if ($Optional) { return $null }
    Stop-OwnershipRefusal 'no main ref (refs/remotes/origin/main or refs/heads/main) in the checkout'
}

function Assert-OwnershipFullHistory {
    param([string]$Repository)
    if ((Get-OwnershipGitText -Repository $Repository -Arguments @('rev-parse', '--is-shallow-repository')).Trim() -eq 'true') {
        Stop-OwnershipRefusal 'shallow repository: content proof and retired_in checks need full Git history (fetch-depth: 0)'
    }
}

# Every (path, blob) version of the paths reachable from the revisions, plus HEAD's tree.
function Get-OwnershipHistoryBlobs {
    param([string]$Repository, [string[]]$Revisions, [string[]]$Paths, [bool]$IncludeHeadTree = $true)
    $found = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    if ($Paths.Count -eq 0) { return ,$found }
    if ($Revisions.Count -gt 0) {
        $arguments = @('log', '--raw', '--full-history', '--no-renames', '--no-abbrev', '-m', '--root', '--format=commit %H') + $Revisions + @('--') + $Paths
        foreach ($line in (Get-OwnershipGitText -Repository $Repository -Arguments $arguments).Split("`n")) {
            if (-not $line.StartsWith(':')) { continue }
            $tab = $line.IndexOf("`t")
            $fields = $line.Substring(0, $tab).Split(' ')
            $mode = $fields[1]; $blob = $fields[3]
            if (($mode -eq '100644' -or $mode -eq '100755') -and $blob.Trim('0').Length -gt 0) { [void]$found.Add($line.Substring($tab + 1) + "`t" + $blob) }
        }
    }
    if ($IncludeHeadTree) {
        foreach ($line in (Get-OwnershipGitText -Repository $Repository -Arguments (@('ls-tree', '-r', '--full-tree', 'HEAD', '--') + $Paths)).Split("`n")) {
            if (-not $line) { continue }
            $tab = $line.IndexOf("`t")
            $meta = $line.Substring(0, $tab).Split(' ')
            if ($meta[1] -eq 'blob' -and ($meta[0] -eq '100644' -or $meta[0] -eq '100755')) { [void]$found.Add($line.Substring($tab + 1) + "`t" + $meta[2]) }
        }
    }
    return ,$found
}

function Read-OwnershipBlobs {
    param([string]$Repository, [string[]]$Blobs)
    $contents = @{}
    $unique = Get-OwnershipSortedOrdinal -Values ([string[]]@($Blobs | Select-Object -Unique))
    if ($unique.Count -eq 0) { return $contents }
    $request = [System.Text.Encoding]::ASCII.GetBytes(($unique -join "`n") + "`n")
    $data = (Invoke-OwnershipGit -Repository $Repository -Arguments @('cat-file', '--batch') -InputBytes $request).Output
    $position = 0
    foreach ($blob in $unique) {
        $newline = [System.Array]::IndexOf($data, [byte]10, $position)
        if ($newline -lt 0) { Stop-OwnershipRefusal "git cat-file returned no header for $blob" }
        $header = [System.Text.Encoding]::ASCII.GetString($data, $position, $newline - $position).Split(' ')
        if ($header.Count -ne 3 -or $header[0] -cne $blob -or $header[1] -cne 'blob') {
            Stop-OwnershipRefusal "git cat-file did not return blob ${blob}: $($header -join ' ')"
        }
        $size = [int]$header[2]
        $start = $newline + 1
        if ($start + $size -gt $data.Length) { Stop-OwnershipRefusal "git cat-file returned a short body for $blob" }
        $bytes = New-Object byte[] $size
        [System.Array]::Copy($data, $start, $bytes, 0, $size)
        $contents[$blob] = $bytes
        $position = $start + $size + 1
    }
    return $contents
}

# Items: @{Key; Source; NodeType; Agents; Shim} -> proofs map as in content-proof.json.
function Get-OwnershipHistoryFingerprints {
    param([string]$Repository, $Items, [string[]]$Revisions, [bool]$IncludeHeadTree = $true)
    $paths = Get-OwnershipSortedOrdinal -Values ([string[]]@($Items | ForEach-Object { $_.Source } | Select-Object -Unique))
    $blobs = Get-OwnershipHistoryBlobs -Repository $Repository -Revisions $Revisions -Paths $paths -IncludeHeadTree $IncludeHeadTree
    $pairs = New-Object System.Collections.ArrayList
    foreach ($pair in $blobs) { $tab = $pair.LastIndexOf("`t"); [void]$pairs.Add(@($pair.Substring(0, $tab), $pair.Substring($tab + 1))) }
    $contents = Read-OwnershipBlobs -Repository $Repository -Blobs ([string[]]@($pairs | ForEach-Object { $_[1] }))
    $shimHash = Get-OwnershipSha256Hex -Bytes $script:OwnershipUtf8.GetBytes($script:OwnershipShimText)
    $sets = @{}
    foreach ($item in $Items) {
        if (-not $sets.ContainsKey($item.Key)) { $sets[$item.Key] = New-OwnershipMap }
        $files = $sets[$item.Key]
        foreach ($pair in $pairs) {
            $path = $pair[0]
            if ($item.NodeType -eq 'file') {
                if ($path -cne $item.Source) { continue }
                $relative = ''
            }
            else {
                if (-not $path.StartsWith($item.Source + '/', [System.StringComparison]::Ordinal)) { continue }
                $relative = $path.Substring($item.Source.Length + 1)
            }
            if (-not $files.Contains($relative)) { $files[$relative] = @{} }
            $perAgent = $files[$relative]
            $fingerprints = Get-OwnershipBlobFingerprints -Name $path -Data $contents[$pair[1]] -Agents ([string[]]$item.Agents)
            foreach ($agent in @($fingerprints.Keys)) {
                if (-not $perAgent.ContainsKey($agent)) { $perAgent[$agent] = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal) }
                $perAgent[$agent].UnionWith($fingerprints[$agent])
            }
        }
        if ($item.Shim) {
            if (-not $files.Contains('')) { $files[''] = @{} }
            foreach ($agent in $item.Agents) {
                if (-not $files[''].ContainsKey($agent)) { $files[''][$agent] = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal) }
                [void]$files[''][$agent].Add($shimHash)
            }
        }
    }
    $proofs = New-OwnershipMap
    foreach ($key in (Get-OwnershipSortedOrdinal -Values ([string[]]@($sets.Keys)))) {
        $files = New-OwnershipMap
        foreach ($relative in @($sets[$key].Keys)) {
            $perAgent = New-OwnershipMap
            foreach ($agent in (Get-OwnershipSortedOrdinal -Values ([string[]]@($sets[$key][$relative].Keys)))) {
                $hashes = New-Object System.Collections.ArrayList
                foreach ($hash in (Get-OwnershipSortedOrdinal -Values ([string[]]@($sets[$key][$relative][$agent])))) { [void]$hashes.Add($hash) }
                $perAgent[$agent] = $hashes
            }
            $files[$relative] = $perAgent
        }
        $value = New-OwnershipMap
        $value['files'] = $files
        $proofs[$key] = $value
    }
    return ,$proofs
}

function Get-OwnershipProofSource {
    param($Entry)
    if ($Entry['kind'] -eq 'source_only_tool') { return ('tools/' + (Get-OwnershipToolRelativePath $Entry)) }
    return $Entry['source_path']
}

# Proof items for every inventory content_proof key.
function Get-OwnershipProofItems {
    param($Inventory)
    $grouped = @{}
    foreach ($entry in $Inventory['entries']) {
        $key = Get-OwnershipValue $entry 'content_proof'
        if (-not $key) { continue }
        $source = Get-OwnershipProofSource $entry
        if (-not $grouped.ContainsKey($key)) {
            $grouped[$key] = @{ Key = $key; Source = $source; NodeType = $entry['node_type']; AgentSet = (New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)); Shim = ($entry['kind'] -eq 'hook_entrypoint') }
        }
        $current = $grouped[$key]
        if ($current.Source -cne $source -or $current.NodeType -cne $entry['node_type']) { Stop-OwnershipRefusal "content_proof key $key is shared by entries with different sources" }
        foreach ($agent in $entry['agents']) { [void]$current.AgentSet.Add($agent) }
    }
    $items = New-Object System.Collections.ArrayList
    foreach ($key in (Get-OwnershipSortedOrdinal -Values ([string[]]@($grouped.Keys)))) {
        $item = $grouped[$key]
        $item.Agents = Get-OwnershipSortedOrdinal -Values ([string[]]@($item.AgentSet))
        [void]$items.Add($item)
    }
    return ,$items
}

# ── build-primitives ────────────────────────────────────────────────────────

# installer-primitives.ps1 text extracted from install.ps1 by AST.
function Get-OwnershipPrimitivesText {
    param([string]$InstallerPath)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($InstallerPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { Stop-OwnershipRefusal "install.ps1 does not parse: $($errors[0].Message)" }
    $functions = New-OwnershipMap
    $constants = New-Object System.Collections.ArrayList
    foreach ($statement in $ast.EndBlock.Statements) {
        if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $functions[$statement.Name] = $statement; continue }
        if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst] -and (Test-OwnershipContainsOrdinal $script:OwnershipPrimitiveConstants $statement.Left.Extent.Text)) {
            [void]$constants.Add($statement)
        }
    }
    foreach ($name in $script:OwnershipPrimitiveConstants) {
        if (-not (@($constants | Where-Object { $_.Left.Extent.Text -ceq $name }).Count)) { Stop-OwnershipRefusal "install.ps1 no longer assigns $name" }
    }
    $selected = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($name in $script:OwnershipPrimitiveRoots) {
        if (-not $functions.Contains($name)) { Stop-OwnershipRefusal "install.ps1 no longer defines $name" }
        if ($selected.Add($name)) { $queue.Enqueue($name) }
    }
    while ($queue.Count -gt 0) {
        $function = $functions[$queue.Dequeue()]
        $commands = $function.Body.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($command in $commands) {
            $called = $command.GetCommandName()
            if ($called -and $functions.Contains($called) -and $selected.Add($called)) { $queue.Enqueue($called) }
        }
    }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append("# GENERATED FILE: do not edit. Regenerate with:`n")
    [void]$builder.Append("#   pwsh -NoProfile -File tools/framework-ownership/ownership-checkout.ps1 build-primitives`n")
    [void]$builder.Append("# Installer primitives extracted from install.ps1 by AST so the ownership`n")
    [void]$builder.Append("# helpers share the installer's path, reparse-point, DACL-preserving write,`n")
    [void]$builder.Append("# JSON identity and hook-path code. Dot-source only.`n`n")
    foreach ($statement in $constants) { [void]$builder.Append($statement.Extent.Text + "`n") }
    foreach ($name in @($functions.Keys)) {
        if (-not $selected.Contains($name)) { continue }
        [void]$builder.Append("`n" + $functions[$name].Extent.Text + "`n")
    }
    return $builder.ToString().Replace("`r`n", "`n")
}

function Invoke-OwnershipBuildPrimitives {
    param([string[]]$Arguments)
    $values = ConvertFrom-OwnershipArguments -Arguments $Arguments -Spec @{ '-Check' = $false }
    Assert-OwnershipLocation
    $text = Get-OwnershipPrimitivesText -InstallerPath (Join-Path (Get-OwnershipCheckoutRoot) 'install.ps1')
    if ($values['-Check']) {
        if (-not [System.IO.File]::Exists($script:OwnershipPrimitivesFile)) { Stop-OwnershipRefusal 'installer-primitives.ps1 missing; run build-primitives' }
        $actual = $script:OwnershipUtf8.GetString([System.IO.File]::ReadAllBytes($script:OwnershipPrimitivesFile)).Replace("`r`n", "`n")
        if ($actual -cne $text) { Stop-OwnershipRefusal 'installer-primitives.ps1 differs from a fresh extraction from install.ps1; run build-primitives' }
        Write-OwnershipOut "Installer primitives match install.ps1.`n"
        return $script:OwnershipExitOk
    }
    [System.IO.File]::WriteAllBytes($script:OwnershipPrimitivesFile, $script:OwnershipUtf8.GetBytes($text))
    Write-OwnershipOut "Wrote installer-primitives.ps1`n"
    return $script:OwnershipExitOk
}

# ── Installer mode ──────────────────────────────────────────────────────────

function Invoke-OwnershipInstall {
    param([string[]]$Arguments)
    $values = ConvertFrom-OwnershipArguments -Arguments $Arguments -Spec @{ '-Agent' = $true; '-DryRun' = $false }
    $agent = Get-OwnershipRequiredAgent $values
    Assert-OwnershipLocation
    $dryRun = [bool]$values['-DryRun']
    Assert-OwnershipCodexStopped -Agent $agent
    $homes = Resolve-OwnershipHomes -Agent $agent
    $data = Read-OwnershipData -Directory $script:OwnershipToolDirectory
    $planner = New-OwnershipPlanner -Data $data -Agent $agent -Operation 'install' -Homes $homes
    $findings = Invoke-OwnershipPlan -Planner $planner -Kinds $script:OwnershipInstallModeKinds
    $manifest = New-OwnershipManifest -Planner $planner -Findings $findings
    $removable = @($findings | Where-Object { $_.Status -eq 'removable' })
    $kept = @($findings | Where-Object { $_.Status -eq 'ambiguous' -or $_.Status -eq 'unrelated' })
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append("Retired skills and agents for ${agent}:`n")
    foreach ($finding in $removable) { [void]$builder.Append("  remove: $(Get-OwnershipDisplayPath $finding) ($($finding.Kind))`n") }
    foreach ($finding in $kept) {
        $label = if ($finding.Status -eq 'unrelated') { 'kept (unrelated)' } else { 'kept' }
        [void]$builder.Append("  ${label}: $(Get-OwnershipDisplayPath $finding): $($finding.Reason)`n")
    }
    [void]$builder.Append("  Retired-item plan digest: $($manifest['manifest_digest'])`n")
    Write-OwnershipOut $builder.ToString()
    if ($dryRun) {
        Write-OwnershipOut "  [dry-run] Retired items: $($removable.Count) to remove, $($kept.Count) kept.`n"
        if ($kept.Count -gt 0) { Write-OwnershipOut "  Kept items stay in place; $($script:OwnershipCleanupPointer).`n" }
        if ($kept.Count -gt 0) { return $script:OwnershipExitKept }
        return $script:OwnershipExitOk
    }
    $result = Invoke-OwnershipApply -Planner $planner -Items $manifest['items']
    $builder = New-Object System.Text.StringBuilder
    foreach ($item in $result.Removed) { [void]$builder.Append("  removed: $($item['path'])`n") }
    foreach ($pair in $result.Skipped) { [void]$builder.Append("  skipped: $($pair[0]['path']): $($pair[1])`n") }
    $totalKept = $kept.Count + $result.Skipped.Count
    [void]$builder.Append("  Retired items: $($result.Removed.Count) removed, $totalKept kept.`n")
    if ($totalKept -gt 0) { [void]$builder.Append("  Kept items stay in place; $($script:OwnershipCleanupPointer).`n") }
    Write-OwnershipOut $builder.ToString()
    if ($totalKept -gt 0) { return $script:OwnershipExitKept }
    return $script:OwnershipExitOk
}

# ── Uninstall ───────────────────────────────────────────────────────────────

function New-OwnershipCurrentSpec {
    param([string]$Kind, [string]$Root, [string]$Path, [string]$NodeType, [string]$Source, [bool]$BuildArtifacts = $false, [string[]]$LocationSubtrees = @())
    $spec = New-OwnershipMap
    $spec['id'] = "current/$Root/$Path"
    $spec['kind'] = $Kind
    $spec['root'] = $Root
    $spec['path'] = $Path
    $spec['node_type'] = $NodeType
    $spec['content_proof'] = 'current:' + $Source
    $spec['source'] = $Source
    $spec['current'] = $true
    if ($BuildArtifacts) {
        $spec['build_artifacts'] = $true
        $subtrees = New-Object System.Collections.ArrayList
        foreach ($subtree in $LocationSubtrees) { [void]$subtrees.Add($subtree) }
        $spec['location_subtrees'] = $subtrees
    }
    return $spec
}

function Get-OwnershipSortedNames {
    param([string]$Directory)
    if (-not [System.IO.Directory]::Exists($Directory)) { return ,([string[]]@()) }
    return (Get-OwnershipSortedOrdinal -Values (Get-OwnershipDirectoryNames -LiteralPath $Directory).ToArray())
}

function Test-OwnershipLinkPath {
    param([string]$LiteralPath)
    return (Test-OwnershipReparse ([System.IO.File]::GetAttributes($LiteralPath)))
}

# Current framework items install.ps1 writes for this agent (Windows layout).
function Get-OwnershipCurrentSpecs {
    param([string]$Repository, [string]$Agent)
    $specs = New-Object System.Collections.ArrayList
    $skills = Join-Path $Repository 'skills'
    foreach ($name in (Get-OwnershipSortedNames $skills)) {
        if ($name.StartsWith('assistant-', [System.StringComparison]::Ordinal) -and [System.IO.File]::Exists((Join-Path (Join-Path $skills $name) 'SKILL.md'))) {
            if ($Agent -eq 'codex') { [void]$specs.Add((New-OwnershipCurrentSpec 'current_skill_directory' 'agents_skills' $name 'directory' "skills/$name")) }
            else { [void]$specs.Add((New-OwnershipCurrentSpec 'current_skill_directory' 'agent_home' "skills/$name" 'directory' "skills/$name")) }
        }
    }
    $tools = Join-Path $Repository 'tools'
    foreach ($name in (Get-OwnershipSortedNames $tools)) {
        if ((Test-OwnershipContainsOrdinal $script:OwnershipToolTopLevelExcludes $name) -or (Test-OwnershipContainsOrdinal $script:OwnershipToolNameExcludes $name) -or $name.EndsWith('.pyc', [System.StringComparison]::Ordinal)) { continue }
        $absolute = Join-Path $tools $name
        if (Test-OwnershipLinkPath $absolute) { continue }
        if ([System.IO.Directory]::Exists($absolute)) {
            $subtrees = if ($name -eq 'evals') { @('node_modules') } else { @() }
            [void]$specs.Add((New-OwnershipCurrentSpec 'current_tool_entry' 'agent_home' "tools/$name" 'directory' "tools/$name" -BuildArtifacts $true -LocationSubtrees $subtrees))
        }
        else { [void]$specs.Add((New-OwnershipCurrentSpec 'current_tool_entry' 'agent_home' "tools/$name" 'file' "tools/$name")) }
    }
    if ($Agent -eq 'codex') {
        foreach ($name in $script:OwnershipCodexCommonTools) {
            if ([System.IO.Directory]::Exists((Join-Path $tools $name))) {
                [void]$specs.Add((New-OwnershipCurrentSpec 'current_tool_entry' 'agents_tools' $name 'directory' "tools/$name" -BuildArtifacts $true))
            }
        }
    }
    $evals = Join-Path (Join-Path $Repository 'docs') 'evals'
    foreach ($name in (Get-OwnershipSortedNames $evals)) {
        $absolute = Join-Path $evals $name
        if ($name -eq '.DS_Store' -or (Test-OwnershipLinkPath $absolute)) { continue }
        $nodeType = if ([System.IO.Directory]::Exists($absolute)) { 'directory' } else { 'file' }
        [void]$specs.Add((New-OwnershipCurrentSpec 'current_eval_doc_entry' 'agent_home' "docs/evals/$name" $nodeType "docs/evals/$name"))
    }
    if ($Agent -eq 'claude' -or $Agent -eq 'codex') {
        $folder = $Agent
        $suffix = if ($Agent -eq 'claude') { '.md' } else { '.toml' }
        $sourceDirectory = Join-Path (Join-Path $Repository 'agents') $folder
        foreach ($name in (Get-OwnershipSortedNames $sourceDirectory)) {
            if ($name.EndsWith($suffix, [System.StringComparison]::Ordinal) -and [System.IO.File]::Exists((Join-Path $sourceDirectory $name))) {
                [void]$specs.Add((New-OwnershipCurrentSpec 'current_agent_file' 'agent_home' "agents/$name" 'file' "agents/$folder/$name"))
            }
        }
    }
    if ($Agent -eq 'codex') {
        $rules = Join-Path $Repository 'codex-rules'
        foreach ($name in (Get-OwnershipSortedNames $rules)) {
            if ($name.EndsWith('.rules', [System.StringComparison]::Ordinal) -and [System.IO.File]::Exists((Join-Path $rules $name))) {
                [void]$specs.Add((New-OwnershipCurrentSpec 'current_codex_rule' 'agent_home' "rules/$name" 'file' "codex-rules/$name"))
            }
        }
    }
    if ($script:OwnershipCurrentInstructionFiles.ContainsKey($Agent)) {
        $name = $script:OwnershipCurrentInstructionFiles[$Agent]
        $spec = New-OwnershipMap
        $spec['id'] = "current/agent_home/$name"
        $spec['kind'] = 'current_instruction_block'
        $spec['root'] = 'agent_home'
        $spec['path'] = $name
        $markers = New-OwnershipMap
        $markers['start'] = $script:OwnershipCurrentBlockStart
        $markers['end'] = $script:OwnershipCurrentBlockEnd
        $spec['markers'] = $markers
        $spec['current'] = $true
        [void]$specs.Add($spec)
    }
    return ,$specs
}

function Get-OwnershipCurrentFingerprints {
    param([string]$Repository, [string]$Agent, $Specs)
    $items = New-Object System.Collections.ArrayList
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($spec in $Specs) {
        if (-not (Test-OwnershipHasKey $spec 'source')) { continue }
        if (-not $seen.Add($spec['content_proof'])) { continue }
        [void]$items.Add(@{ Key = $spec['content_proof']; Source = $spec['source']; NodeType = $spec['node_type']; Agents = @($Agent); Shim = $false })
    }
    $main = Get-OwnershipMainRef -Repository $Repository -Optional
    $revisions = if ($main) { @($main) } else { @('HEAD') }
    $proofs = Get-OwnershipHistoryFingerprints -Repository $Repository -Items $items -Revisions $revisions
    # A source file the installers never sync proves nothing about the home,
    # even when a byte-identical copy sits there.
    foreach ($spec in $Specs) {
        if ($spec['kind'] -ne 'current_tool_entry' -or -not $proofs.Contains($spec['content_proof'])) { continue }
        $name = ([string]$spec['source']).Substring('tools/'.Length)
        $files = $proofs[$spec['content_proof']]['files']
        foreach ($relative in @($files.Keys)) {
            $toolRelative = if ($relative) { "$name/$relative" } else { $name }
            if (Test-OwnershipInsideAny $toolRelative $script:OwnershipToolExactExcludes) { $files.Remove($relative) }
        }
    }
    return ,$proofs
}

function New-OwnershipUninstallPlanner {
    param([string]$Agent)
    Assert-OwnershipLocation
    $repository = Get-OwnershipCheckoutRoot
    Assert-OwnershipCodexStopped -Agent $Agent
    $homes = Resolve-OwnershipHomes -Agent $Agent -CheckoutDir $repository
    foreach ($root in @($homes.Roots.Values)) {
        if ((Test-OwnershipSameOrInside $root $repository) -or (Test-OwnershipSameOrInside $repository $root)) {
            Stop-OwnershipRefusal "the agent home and the framework checkout overlap: $root and $repository"
        }
    }
    Assert-OwnershipFullHistory -Repository $repository
    $data = Read-OwnershipData -Directory $script:OwnershipToolDirectory
    $specs = Get-OwnershipCurrentSpecs -Repository $repository -Agent $Agent
    $fingerprints = Get-OwnershipCurrentFingerprints -Repository $repository -Agent $Agent -Specs $specs
    return (New-OwnershipPlanner -Data $data -Agent $Agent -Operation 'uninstall' -Homes $homes -CheckoutDir $repository -CurrentSpecs $specs -CurrentFingerprints $fingerprints)
}

function Invoke-OwnershipUninstall {
    param([string[]]$Arguments, [scriptblock]$BeforeDelete = $null)
    $values = ConvertFrom-OwnershipArguments -Arguments $Arguments -Spec @{ '-Agent' = $true; '-DryRun' = $false; '-Yes' = $false; '-PlanDigest' = $true }
    $agent = Get-OwnershipRequiredAgent $values
    $planner = New-OwnershipUninstallPlanner -Agent $agent
    $findings = Invoke-OwnershipPlan -Planner $planner
    $manifest = New-OwnershipManifest -Planner $planner -Findings $findings
    Write-OwnershipReport -Planner $planner -Findings $findings -Manifest $manifest -Title 'Assistant Framework uninstall plan'
    if ($values['-DryRun']) {
        Write-OwnershipOut "Dry run: nothing was removed.`n"
        return $script:OwnershipExitOk
    }
    if ($values['-Yes']) {
        $given = $values['-PlanDigest']
        if (-not $given) { Stop-OwnershipRefusal '-Yes requires -PlanDigest from a prior dry run' }
        if ($given -cne $manifest['manifest_digest']) {
            Write-OwnershipOut "Current plan digest: $($manifest['manifest_digest'])`n"
            Stop-OwnershipRefusal 'the plan changed since the dry run (digest mismatch); review the new plan and rerun'
        }
    }
    elseif ($values.ContainsKey('-PlanDigest')) { Stop-OwnershipRefusal '-PlanDigest is used only with -Yes' }
    else {
        if (-not (Test-OwnershipInteractive)) { Stop-OwnershipRefusal 'a non-interactive uninstall requires -Yes and -PlanDigest' }
        if (-not (Confirm-OwnershipByTyping -Agent $agent -Count $manifest['items'].Count)) { Stop-OwnershipRefusal 'confirmation not given; nothing was removed' }
    }
    $result = Invoke-OwnershipApply -Planner $planner -Items $manifest['items'] -BeforeDelete $BeforeDelete
    Write-OwnershipApplyResult -Result $result
    foreach ($item in $result.Removed) {
        if ($item['kind'] -eq 'current_codex_rule' -and $item['path'] -ceq 'rules/workflow.rules') { Write-OwnershipOut ($script:OwnershipRulesNotice + "`n") }
    }
    $kept = @($findings | Where-Object { $_.Status -eq 'ambiguous' })
    if ($kept.Count -gt 0 -or $result.Skipped.Count -gt 0) {
        Write-OwnershipOut "Completed with items kept; they are listed above.`n"
        return $script:OwnershipExitKept
    }
    return $script:OwnershipExitOk
}

# ── Main ────────────────────────────────────────────────────────────────────

function Invoke-OwnershipCheckoutMain {
    param([string[]]$Arguments)
    $Arguments = @($Arguments)
    $commands = @('install', 'uninstall', 'build-primitives')
    if ($Arguments.Count -eq 0 -or -not (Test-OwnershipContainsOrdinal $commands $Arguments[0])) {
        [Console]::Error.WriteLine('refused: the first argument must be one of: install, uninstall, build-primitives')
        return $script:OwnershipExitRefused
    }
    $command = $Arguments[0]
    $rest = [string[]]@($Arguments | Select-Object -Skip 1)
    try {
        if ($command -eq 'install') { return (Invoke-OwnershipInstall -Arguments $rest) }
        if ($command -eq 'uninstall') { return (Invoke-OwnershipUninstall -Arguments $rest) }
        return (Invoke-OwnershipBuildPrimitives -Arguments $rest)
    }
    catch {
        if (Test-OwnershipRefusal $_) {
            if ($command -eq 'install') { Write-OwnershipOut "  ownership helper refused: $($_.Exception.Message); kept`n" }
            [Console]::Error.WriteLine("refused: $($_.Exception.Message)")
            return $script:OwnershipExitRefused
        }
        [Console]::Error.WriteLine("error: $($_.Exception.Message)")
        return $script:OwnershipExitInternal
    }
}

if (-not (Get-Variable -Name OwnershipCheckoutNoMain -ValueOnly -ErrorAction SilentlyContinue)) {
    exit (Invoke-OwnershipCheckoutMain -Arguments $args)
}
