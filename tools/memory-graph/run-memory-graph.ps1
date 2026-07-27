#requires -Version 5.1
<#
.SYNOPSIS
Builds, caches, and starts the Assistant Framework Memory Graph MCP server.

.DESCRIPTION
Publishes the .NET project when the cached DLL is absent or stale, then
forwards every argument to the server without evaluating command text.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$forwardedArguments = @($args)

function Assert-SafePublishDirectory {
    param([string]$PublishDirectory, [string]$ScriptDirectory)
    $publishFull = [System.IO.Path]::GetFullPath($PublishDirectory).TrimEnd([char[]]@('\', '/'))
    $scriptFull = [System.IO.Path]::GetFullPath($ScriptDirectory).TrimEnd([char[]]@('\', '/'))
    $separator = [System.IO.Path]::DirectorySeparatorChar
    if (-not $publishFull.StartsWith($scriptFull + $separator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing publish directory outside the launcher directory: $publishFull"
    }
    $root = [System.IO.Path]::GetPathRoot($publishFull)
    if ([string]::Equals($publishFull, $scriptFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        (-not [string]::IsNullOrWhiteSpace($root) -and [string]::Equals($publishFull, $root.TrimEnd([char[]]@('\', '/')), [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing unsafe publish directory: $publishFull"
    }
    if (Test-Path -LiteralPath $publishFull) {
        $item = Get-Item -LiteralPath $publishFull -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing publish through a reparse point: $publishFull"
        }
        if (-not $item.PSIsContainer) {
            throw "Publish path exists but is not a directory: $publishFull"
        }
    }
    Assert-NoReparseTraversal -LiteralPath $publishFull -Purpose 'publish path' -TraversalRoot $scriptFull
    return $publishFull
}

function Assert-NoReparseTraversal {
    param([string]$LiteralPath, [string]$Purpose, [string]$TraversalRoot)
    $fullPath = [System.IO.Path]::GetFullPath($LiteralPath)
    if ([string]::IsNullOrWhiteSpace($TraversalRoot)) {
        $TraversalRoot = [System.IO.Path]::GetDirectoryName($fullPath)
    }
    $stopPath = [System.IO.Path]::GetFullPath($TraversalRoot).TrimEnd([char[]]@('\', '/'))
    $current = $fullPath
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing $Purpose through reparse-point ancestor: $current"
            }
        }
        if ([string]::Equals(
            $current.TrimEnd([char[]]@('\', '/')),
            $stopPath,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            break
        }
        $parent = [System.IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrWhiteSpace($parent) -or
            [string]::Equals($parent, $current, [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $current = $parent
    }
}

function Get-PublishMutexName {
    param([string]$ScriptDirectory)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($ScriptDirectory.ToLowerInvariant())
        $hash = [System.BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace('-', '')
        return 'AssistantFramework.MemoryGraph.' + $hash
    }
    finally {
        $sha256.Dispose()
    }
}

function Assert-NoReparseTree {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Container)) { return }
    $rootItem = Get-Item -LiteralPath $LiteralPath -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing a directory tree rooted at a reparse point: $LiteralPath"
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $LiteralPath -Force)) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing a directory tree containing a reparse point: $($item.FullName)"
        }
        if ($item.PSIsContainer) { Assert-NoReparseTree -LiteralPath $item.FullName }
    }
}

function Remove-SafeDirectoryTree {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Container)) { return }
    Assert-NoReparseTree -LiteralPath $LiteralPath
    foreach ($item in @(Get-ChildItem -LiteralPath $LiteralPath -Force)) {
        if ($item.PSIsContainer) { Remove-SafeDirectoryTree -LiteralPath $item.FullName }
        else { Remove-Item -LiteralPath $item.FullName -Force }
    }
    Remove-Item -LiteralPath $LiteralPath -Force
}

function Copy-SafeDirectoryTree {
    param([string]$SourceDirectory, [string]$TargetDirectory)
    Assert-NoReparseTree -LiteralPath $SourceDirectory
    [void][System.IO.Directory]::CreateDirectory($TargetDirectory)
    foreach ($item in @(Get-ChildItem -LiteralPath $SourceDirectory -Force)) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to copy publish output containing a reparse point: $($item.FullName)"
        }
        $target = Join-Path $TargetDirectory $item.Name
        if ($item.PSIsContainer) {
            Copy-SafeDirectoryTree -SourceDirectory $item.FullName -TargetDirectory $target
        }
        else {
            [System.IO.File]::Copy($item.FullName, $target, $false)
        }
    }
}

try {
    $scriptDirectory = [System.IO.Path]::GetFullPath($PSScriptRoot)
    $scriptDirectoryItem = Get-Item -LiteralPath $scriptDirectory -Force
    if (($scriptDirectoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing launcher directory reparse point: $scriptDirectory"
    }
    $projectDirectory = Join-Path (Join-Path $scriptDirectory 'src') 'MemoryGraph'
    $projectFile = Join-Path $projectDirectory 'MemoryGraph.csproj'
    $publishDirectory = Assert-SafePublishDirectory -PublishDirectory (Join-Path $scriptDirectory '.publish') -ScriptDirectory $scriptDirectory
    $dllPath = Join-Path $publishDirectory 'MemoryGraph.dll'

    if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
        throw "Memory Graph project not found: $projectFile"
    }
    Assert-NoReparseTree -LiteralPath $projectDirectory
    $dotnetApplication = Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $dotnetApplication) {
        throw 'The .NET 8 SDK/runtime is required to build and run Memory Graph.'
    }
    $dotnetPath = $dotnetApplication.Path
    if ([string]::IsNullOrWhiteSpace($dotnetPath) -or -not (Test-Path -LiteralPath $dotnetPath -PathType Leaf)) {
        throw 'Cannot resolve the dotnet executable to a literal file path.'
    }

    $publishMutex = $null
    $publishLockTaken = $false
    try {
        $mutexName = Get-PublishMutexName -ScriptDirectory $scriptDirectory
        $publishMutex = New-Object -TypeName System.Threading.Mutex -ArgumentList @($false, $mutexName)
        try {
            $publishLockTaken = $publishMutex.WaitOne(30000)
        }
        catch [System.Threading.AbandonedMutexException] {
            $publishLockTaken = $true
        }
        if (-not $publishLockTaken) {
            throw 'Timed out waiting 30 seconds for another Memory Graph build to finish.'
        }

        $needsBuild = -not (Test-Path -LiteralPath $dllPath -PathType Leaf)
        if (-not $needsBuild) {
            $dllTimestamp = (Get-Item -LiteralPath $dllPath).LastWriteTimeUtc
            foreach ($sourceFile in @(Get-ChildItem -LiteralPath $projectDirectory -File -Recurse | Where-Object { $_.Extension -eq '.cs' -or $_.Extension -eq '.csproj' })) {
                if ($sourceFile.LastWriteTimeUtc -gt $dllTimestamp) {
                    $needsBuild = $true
                    break
                }
            }
        }

        if ($needsBuild) {
            [Console]::Error.WriteLine('[memory-graph] Building...')
            $stageDirectory = Assert-SafePublishDirectory -PublishDirectory (Join-Path $scriptDirectory ('.publish.stage-' + [Guid]::NewGuid().ToString('N'))) -ScriptDirectory $scriptDirectory
            $backupDirectory = Assert-SafePublishDirectory -PublishDirectory (Join-Path $scriptDirectory ('.publish.backup-' + [Guid]::NewGuid().ToString('N'))) -ScriptDirectory $scriptDirectory
            $oldPublishMoved = $false
            try {
                [void][System.IO.Directory]::CreateDirectory($stageDirectory)
                Assert-NoReparseTraversal -LiteralPath $stageDirectory -Purpose 'publish staging directory'
                foreach ($generatedName in @('bin', 'obj')) {
                    $generatedDirectory = Join-Path $projectDirectory $generatedName
                    if (Test-Path -LiteralPath $generatedDirectory -PathType Container) {
                        Remove-SafeDirectoryTree -LiteralPath $generatedDirectory
                    }
                }
                & $dotnetPath publish $projectFile -c Release --nologo --tl:off -v quiet
                if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE." }
                $binDirectory = Join-Path $projectDirectory 'bin'
                if (-not (Test-Path -LiteralPath $binDirectory -PathType Container)) {
                    throw "dotnet publish did not create a contained bin directory: $binDirectory"
                }
                Assert-NoReparseTree -LiteralPath $binDirectory
                $publishDirectories = @(
                    Get-ChildItem -LiteralPath $binDirectory -Directory -Recurse |
                        Where-Object { $_.Name -eq 'publish' }
                )
                if ($publishDirectories.Count -ne 1) {
                    throw "Expected exactly one contained dotnet publish directory; found $($publishDirectories.Count)."
                }
                Copy-SafeDirectoryTree -SourceDirectory $publishDirectories[0].FullName -TargetDirectory $stageDirectory
                foreach ($generatedName in @('bin', 'obj')) {
                    $generatedDirectory = Join-Path $projectDirectory $generatedName
                    if (Test-Path -LiteralPath $generatedDirectory -PathType Container) {
                        Remove-SafeDirectoryTree -LiteralPath $generatedDirectory
                    }
                }
                $stagedDll = Join-Path $stageDirectory 'MemoryGraph.dll'
                if (-not (Test-Path -LiteralPath $stagedDll -PathType Leaf)) { throw "Staged Memory Graph DLL not found: $stagedDll" }
                Assert-NoReparseTree -LiteralPath $stageDirectory

                if (Test-Path -LiteralPath $publishDirectory -PathType Container) {
                    Assert-NoReparseTree -LiteralPath $publishDirectory
                    Move-Item -LiteralPath $publishDirectory -Destination $backupDirectory
                    $oldPublishMoved = $true
                }
                Move-Item -LiteralPath $stageDirectory -Destination $publishDirectory
                if ($oldPublishMoved -and (Test-Path -LiteralPath $backupDirectory -PathType Container)) {
                    Remove-SafeDirectoryTree -LiteralPath $backupDirectory
                    $oldPublishMoved = $false
                }
            }
            catch {
                if ($oldPublishMoved -and -not (Test-Path -LiteralPath $publishDirectory) -and (Test-Path -LiteralPath $backupDirectory -PathType Container)) {
                    Move-Item -LiteralPath $backupDirectory -Destination $publishDirectory
                    $oldPublishMoved = $false
                }
                throw
            }
            finally {
                if (Test-Path -LiteralPath $stageDirectory -PathType Container) { Remove-SafeDirectoryTree -LiteralPath $stageDirectory }
                if (Test-Path -LiteralPath $backupDirectory -PathType Container) { Remove-SafeDirectoryTree -LiteralPath $backupDirectory }
            }
            if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) { throw "Published Memory Graph DLL not found: $dllPath" }
            [Console]::Error.WriteLine('[memory-graph] Build complete.')
        }
    }
    finally {
        if ($publishLockTaken) { $publishMutex.ReleaseMutex() }
        if ($null -ne $publishMutex) { $publishMutex.Dispose() }
    }

    & $dotnetPath $dllPath @forwardedArguments
    $serverExitCode = $LASTEXITCODE
    exit $serverExitCode
}
catch {
    [Console]::Error.WriteLine('[memory-graph] Error: ' + $_.Exception.Message)
    exit 1
}
