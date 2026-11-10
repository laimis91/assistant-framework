#requires -Version 5.1
<#
.SYNOPSIS
Removes Assistant Framework items from one agent home on Windows.

.DESCRIPTION
Run from the framework checkout that installed the agent home. It proves every
framework-owned item (current skills, tools, eval docs, agent files, Codex
rules, the framework instruction block, and retired items) against this
checkout's Git history and removes only proven items. User files, modified
framework files and anything it cannot prove stay in place and are listed.

Run with -DryRun first. Removal needs either a typed confirmation of the agent
name in an interactive console, or -Yes with the plan digest from the dry run.

.PARAMETER Agent
Target agent: claude, codex, or gemini.

.PARAMETER DryRun
Report the plan and its digest without changing files.

.PARAMETER Yes
Remove without a prompt; requires -PlanDigest from a prior dry run.

.PARAMETER PlanDigest
The plan digest printed by the dry run.

.EXAMPLE
pwsh -NoProfile -File uninstall.ps1 -Agent codex -DryRun

.EXAMPLE
pwsh -NoProfile -File uninstall.ps1 -Agent codex -Yes -PlanDigest <digest>

Exit status: 0 done, 1 internal error, 2 refused (nothing changed),
3 completed with items kept.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Agent,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$PlanDigest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$entryPoint = Join-Path (Join-Path (Join-Path $PSScriptRoot 'tools') 'framework-ownership') 'ownership-checkout.ps1'
if (-not (Test-Path -LiteralPath $entryPoint -PathType Leaf)) {
    [Console]::Error.WriteLine("refused: $entryPoint is missing; run uninstall.ps1 from a complete framework checkout")
    exit 2
}

$arguments = New-Object System.Collections.ArrayList
[void]$arguments.Add('uninstall')
if ($PSBoundParameters.ContainsKey('Agent')) { [void]$arguments.AddRange(@('-Agent', $Agent)) }
if ($DryRun) { [void]$arguments.Add('-DryRun') }
if ($Yes) { [void]$arguments.Add('-Yes') }
if ($PSBoundParameters.ContainsKey('PlanDigest')) { [void]$arguments.AddRange(@('-PlanDigest', $PlanDigest)) }

# Run the checkout entry point in this PowerShell executable; it inherits the
# console so the typed confirmation reads from the same terminal.
$executable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
& $executable -NoProfile -File $entryPoint @($arguments.ToArray())
exit $LASTEXITCODE
