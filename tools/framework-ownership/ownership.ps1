#requires -Version 5.1
<#
.SYNOPSIS
Assistant Framework ownership helper for Windows agent homes.

.DESCRIPTION
Installed with the framework tools. It proves which items in an agent home the
framework retired and removes only those, after a typed confirmation of a
dry-run manifest. PowerShell port of ownership.py; same manifest and digest.

  dry-run -Agent <a> [-ManifestOut <file>]
      Report removable, ambiguous and unrelated retired items; never changes files.
  apply -Agent <a> -Manifest <file> -ManifestDigest <digest> [-Yes]
      Remove the confirmed manifest items, re-proving each one first.
  list-retired [-Layout windows|unix] [-Json]
      Print the installers' exact-name list (tab separated, or JSON).
  validate
      Validate the inventory and content-proof data.

Exit status: 0 done, 1 internal error, 2 refused (nothing changed),
3 completed with items kept or skipped.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:OwnershipToolDirectory = $PSScriptRoot
. (Join-Path $script:OwnershipToolDirectory 'installer-primitives.ps1')
. (Join-Path $script:OwnershipToolDirectory 'ownership-core.ps1')

function Invoke-OwnershipDryRun {
    param([string[]]$Arguments)
    $values = ConvertFrom-OwnershipArguments -Arguments $Arguments -Spec @{ '-Agent' = $true; '-ManifestOut' = $true }
    $agent = Get-OwnershipRequiredAgent $values
    Assert-OwnershipCodexStopped -Agent $agent
    $homes = Resolve-OwnershipHomes -Agent $agent
    $data = Read-OwnershipData -Directory $script:OwnershipToolDirectory
    $target = $null
    if ($values.ContainsKey('-ManifestOut')) { $target = Get-OwnershipManifestOutPath -Path $values['-ManifestOut'] -Homes $homes }
    $planner = New-OwnershipPlanner -Data $data -Agent $agent -Operation 'cleanup' -Homes $homes
    $findings = Invoke-OwnershipPlan -Planner $planner
    $manifest = New-OwnershipManifest -Planner $planner -Findings $findings
    Write-OwnershipReport -Planner $planner -Findings $findings -Manifest $manifest -Title 'Assistant Framework cleanup dry run'
    $serialized = ConvertTo-OwnershipManifestText -Manifest $manifest
    if ($null -ne $target) {
        Write-OwnershipNewFile -LiteralPath $target -Data $script:OwnershipUtf8.GetBytes($serialized)
        Write-OwnershipOut "Manifest written to: $target`n"
    }
    else {
        Write-OwnershipOut ("BEGIN MANIFEST`n" + $serialized + "END MANIFEST`n")
    }
    return $script:OwnershipExitOk
}

function Invoke-OwnershipApplyCommand {
    param([string[]]$Arguments, [scriptblock]$BeforeDelete = $null)
    $values = ConvertFrom-OwnershipArguments -Arguments $Arguments -Spec @{ '-Agent' = $true; '-Manifest' = $true; '-ManifestDigest' = $true; '-Yes' = $false }
    $agent = Get-OwnershipRequiredAgent $values
    if (-not $values.ContainsKey('-Manifest') -or -not $values.ContainsKey('-ManifestDigest')) {
        Stop-OwnershipRefusal 'apply requires -Manifest and -ManifestDigest from a prior dry run'
    }
    Assert-OwnershipCodexStopped -Agent $agent
    $homes = Resolve-OwnershipHomes -Agent $agent
    $data = Read-OwnershipData -Directory $script:OwnershipToolDirectory
    $planner = New-OwnershipPlanner -Data $data -Agent $agent -Operation 'cleanup' -Homes $homes
    $manifestPath = $values['-Manifest']
    if (-not [System.IO.Path]::IsPathRooted($manifestPath)) { $manifestPath = Join-Path ((Get-Location).ProviderPath) $manifestPath }
    $manifest = (Read-OwnershipJsonFile -LiteralPath $manifestPath -Label 'manifest').Value
    $items = Test-OwnershipManifest -Manifest $manifest -Planner $planner -ExpectedDigest $values['-ManifestDigest'] -AllowedOperations @('cleanup')
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append("Confirmed manifest for ${agent}: $($items.Count) item(s), digest $($manifest['manifest_digest'])`n")
    foreach ($item in $items) { [void]$builder.Append("  $($item['kind']): $($item['path'])`n") }
    Write-OwnershipOut $builder.ToString()
    if (-not $values['-Yes']) {
        if (-not (Test-OwnershipInteractive)) { Stop-OwnershipRefusal 'a non-interactive apply requires -Yes' }
        if (-not (Confirm-OwnershipByTyping -Agent $agent -Count $items.Count)) { Stop-OwnershipRefusal 'confirmation not given; nothing was removed' }
    }
    $result = Invoke-OwnershipApply -Planner $planner -Items $items -BeforeDelete $BeforeDelete
    Write-OwnershipApplyResult -Result $result
    if ($result.Skipped.Count -gt 0) { Write-OwnershipOut "Some items were kept; $($script:OwnershipCleanupPointer).`n" }
    return (Get-OwnershipApplyExitCode -Result $result)
}

function Invoke-OwnershipListRetired {
    param([string[]]$Arguments)
    $values = ConvertFrom-OwnershipArguments -Arguments $Arguments -Spec @{ '-Layout' = $true; '-Json' = $false }
    $layout = if ($values.ContainsKey('-Layout')) { $values['-Layout'] } else { 'windows' }
    if (-not (Test-OwnershipContainsOrdinal $script:OwnershipLayouts $layout)) { Stop-OwnershipRefusal '-Layout must be unix or windows' }
    $data = Read-OwnershipData -Directory $script:OwnershipToolDirectory
    $rows = Get-OwnershipInstallerList -Inventory $data.Inventory -Layout $layout
    if ($values['-Json']) {
        $document = New-OwnershipMap
        $document['schema_version'] = '1.0'
        $document['layout'] = $layout
        $document['items'] = $rows
        Write-OwnershipOut ((ConvertTo-OwnershipJson -Value $document -Indent 2) + "`n")
    }
    else {
        $builder = New-Object System.Text.StringBuilder
        foreach ($row in $rows) { [void]$builder.Append("$($row['kind'])`t$($row['node_type'])`t$($row['path'])`n") }
        Write-OwnershipOut $builder.ToString()
    }
    return $script:OwnershipExitOk
}

function Invoke-OwnershipValidate {
    param([string[]]$Arguments)
    [void](ConvertFrom-OwnershipArguments -Arguments $Arguments -Spec @{})
    $data = Read-OwnershipData -Directory $script:OwnershipToolDirectory
    Write-OwnershipOut "Inventory valid: $($data.Entries.Count) entries, digest $($data.InventoryDigest)`n"
    return $script:OwnershipExitOk
}

function Invoke-OwnershipHelperMain {
    param([string[]]$Arguments)
    $Arguments = @($Arguments)
    $commands = @('dry-run', 'apply', 'list-retired', 'validate', 'install')
    if ($Arguments.Count -eq 0 -or -not (Test-OwnershipContainsOrdinal $commands $Arguments[0])) {
        [Console]::Error.WriteLine('refused: the first argument must be one of: dry-run, apply, list-retired, validate')
        return $script:OwnershipExitRefused
    }
    $command = $Arguments[0]
    $rest = [string[]]@($Arguments | Select-Object -Skip 1)
    try {
        if ($command -eq 'install') { Stop-OwnershipRefusal 'the installed helper has no installer mode; installers run the checkout entry point' }
        if ($command -eq 'dry-run') { return (Invoke-OwnershipDryRun -Arguments $rest) }
        if ($command -eq 'apply') { return (Invoke-OwnershipApplyCommand -Arguments $rest) }
        if ($command -eq 'list-retired') { return (Invoke-OwnershipListRetired -Arguments $rest) }
        return (Invoke-OwnershipValidate -Arguments $rest)
    }
    catch {
        if (Test-OwnershipRefusal $_) {
            [Console]::Error.WriteLine("refused: $($_.Exception.Message)")
            return $script:OwnershipExitRefused
        }
        [Console]::Error.WriteLine("error: $($_.Exception.Message)")
        return $script:OwnershipExitInternal
    }
}

if (-not (Get-Variable -Name OwnershipHelperNoMain -ValueOnly -ErrorAction SilentlyContinue)) {
    exit (Invoke-OwnershipHelperMain -Arguments $args)
}
