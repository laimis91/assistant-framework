# Assistant Framework ownership proof library for Windows agent homes.
#
# Dot-sourced by ownership.ps1 (installed helper) and ownership-checkout.ps1
# (checkout-only entry point) after installer-primitives.ps1. It is the
# PowerShell port of tools/framework-ownership/ownership.py: the same inventory
# validation, content proof, manifest schema and canonical digest, report text
# and exit codes. Windows layout: Codex skills live under ~/.agents/skills and
# the common Codex tools under ~/.agents/tools.
#
# Requires: Set-StrictMode -Version 2.0 compatible; Windows PowerShell 5.1 and
# PowerShell 7.

$script:OwnershipExitOk = 0
$script:OwnershipExitInternal = 1
$script:OwnershipExitRefused = 2
$script:OwnershipExitKept = 3

$script:OwnershipInventoryMajor = '1'
$script:OwnershipProofMajor = '1'
$script:OwnershipManifestSchemaVersion = '1.0'
$script:OwnershipManifestMajor = '1'

$script:OwnershipAgents = @('claude', 'codex', 'gemini')
$script:OwnershipLayouts = @('unix', 'windows')
$script:OwnershipRoots = @('agent_home', 'agents_skills', 'agents_tools')
$script:OwnershipNodeTypes = @('file', 'directory')
$script:OwnershipRetiredKinds = @(
    'skill_directory', 'agent_file', 'hook_entrypoint', 'hook_helper', 'hook_module', 'hook_registration',
    'managed_tool', 'managed_tool_empty_directory', 'source_only_tool', 'instruction_block'
)
$script:OwnershipCurrentKinds = @(
    'current_skill_directory', 'current_tool_entry', 'current_eval_doc_entry', 'current_agent_file',
    'current_codex_rule', 'current_instruction_block'
)
$script:OwnershipManifestKinds = @($script:OwnershipRetiredKinds + $script:OwnershipCurrentKinds)
$script:OwnershipOperations = @('cleanup', 'uninstall', 'install')
$script:OwnershipToolKinds = @('source_only_tool', 'managed_tool', 'managed_tool_empty_directory')
$script:OwnershipHookFileKinds = @('hook_entrypoint', 'hook_helper', 'hook_module')
$script:OwnershipSourcePathKinds = @(
    'skill_directory', 'agent_file', 'hook_entrypoint', 'hook_helper', 'hook_module', 'managed_tool', 'managed_tool_empty_directory'
)
$script:OwnershipNoNodeTypeKinds = @('hook_registration', 'instruction_block')
$script:OwnershipInstallModeKinds = @('skill_directory', 'agent_file')

# Extensions whose {agent_state_dir} placeholder the installers substitute.
$script:OwnershipSubstitutedExtensions = @('.md', '.yaml', '.yml', '.json', '.conf', '.toml')
$script:OwnershipPlaceholder = '{agent_state_dir}'
# Bytes both installers write at each retired hook entrypoint path.
$script:OwnershipShimText = "#!/usr/bin/env bash`n# Assistant Framework retired-hook compatibility shim.`nexit 0`n"
# Build output the installers delete from managed tool directories on every
# reinstall. Uninstall removes these with a current tool directory.
$script:OwnershipBuildArtifactDirectories = @('bin', 'obj', '.publish', '__pycache__')

$script:OwnershipSegmentPattern = '^[A-Za-z0-9._-]+\z'
$script:OwnershipCommitPattern = '^[0-9a-f]{40}\z'
$script:OwnershipHashPattern = '^[0-9a-f]{64}\z'
$script:OwnershipVersionPattern = '^([0-9]+)\.([0-9]+)\z'
$script:OwnershipIdPattern = '^[a-z0-9][a-z0-9._/@-]*\z'

$script:OwnershipCleanupPointer = 'run the assistant-cleanup skill to review kept items'
$script:OwnershipCheckoutFormReason = 'possible framework checkout path; run uninstall from that checkout or remove it by hand'

$script:OwnershipLatin1 = [System.Text.Encoding]::GetEncoding(28591)
$script:OwnershipUtf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$script:OwnershipUtf8 = New-Object System.Text.UTF8Encoding($false)
$script:OwnershipInvariant = [System.Globalization.CultureInfo]::InvariantCulture

# ── Refusals ────────────────────────────────────────────────────────────────

# A refusal: nothing was changed and the exit status is 2. Refusals are the
# only System.ApplicationException instances these scripts throw.
function Stop-OwnershipRefusal {
    param([string]$Reason)
    throw (New-Object System.ApplicationException($Reason))
}

function Test-OwnershipRefusal {
    param($ErrorRecord)
    return ($null -ne $ErrorRecord -and $ErrorRecord.Exception -is [System.ApplicationException])
}

# ── Generic helpers ─────────────────────────────────────────────────────────

function New-OwnershipMap {
    return (New-Object System.Collections.Specialized.OrderedDictionary)
}

function New-OwnershipList {
    return ,(New-Object System.Collections.ArrayList)
}

function Get-OwnershipValue {
    param($Map, [string]$Key)
    if ($null -eq $Map -or -not ($Map -is [System.Collections.IDictionary])) { return $null }
    if ($Map -is [System.Collections.Specialized.OrderedDictionary] -or $Map -is [System.Collections.Hashtable]) {
        if ($Map.Contains($Key)) { return ,$Map[$Key] }
        return $null
    }
    if ($Map.ContainsKey($Key)) { return ,$Map[$Key] }
    return $null
}

function Test-OwnershipHasKey {
    param($Map, [string]$Key)
    if ($null -eq $Map -or -not ($Map -is [System.Collections.IDictionary])) { return $false }
    if ($Map -is [System.Collections.Specialized.OrderedDictionary] -or $Map -is [System.Collections.Hashtable]) {
        return $Map.Contains($Key)
    }
    return $Map.ContainsKey($Key)
}

function Test-OwnershipIsList {
    param($Value)
    return ($null -ne $Value -and $Value -isnot [string] -and $Value -is [System.Collections.IList] -and $Value -isnot [System.Collections.IDictionary])
}

function Test-OwnershipContainsOrdinal {
    param($Items, [string]$Value)
    foreach ($item in @($Items)) {
        if ($item -is [string] -and [string]::Equals($item, $Value, [System.StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

function Test-OwnershipStringList {
    param($Value, [string[]]$Allowed)
    if (-not (Test-OwnershipIsList $Value) -or $Value.Count -eq 0) { return $false }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($item in $Value) {
        if ($item -isnot [string]) { return $false }
        if (-not (Test-OwnershipContainsOrdinal $Allowed $item)) { return $false }
        if (-not $seen.Add($item)) { return $false }
    }
    return $true
}

function Test-OwnershipListEquals {
    param($Value, [string[]]$Expected)
    if (-not (Test-OwnershipIsList $Value) -or $Value.Count -ne $Expected.Count) { return $false }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ($Value[$index] -isnot [string] -or -not [string]::Equals($Value[$index], $Expected[$index], [System.StringComparison]::Ordinal)) { return $false }
    }
    return $true
}

function Get-OwnershipSortedOrdinal {
    param([string[]]$Values)
    $copy = [string[]]@($Values)
    [System.Array]::Sort($copy, [System.StringComparer]::Ordinal)
    return ,$copy
}

# Stable sort of objects by a string key (ordinal) or an integer key.
function Sort-OwnershipStable {
    param($Items, [scriptblock]$Key, [switch]$Descending)
    $array = @($Items)
    $keys = New-Object System.Collections.ArrayList
    foreach ($item in $array) { [void]$keys.Add((& $Key $item)) }
    $order = New-Object 'System.Collections.Generic.List[int]'
    for ($index = 0; $index -lt $array.Count; $index++) {
        $position = $order.Count
        while ($position -gt 0) {
            $previous = $keys[$order[$position - 1]]
            $current = $keys[$index]
            if ($current -is [string]) { $comparison = [string]::CompareOrdinal($previous, $current) }
            else { $comparison = ([long]$previous).CompareTo([long]$current) }
            if ($Descending) { $comparison = -$comparison }
            if ($comparison -le 0) { break }
            $position--
        }
        $order.Insert($position, $index)
    }
    $result = New-Object System.Collections.ArrayList
    foreach ($index in $order) { [void]$result.Add($array[$index]) }
    return ,$result
}

# ── Hashing and canonical forms ─────────────────────────────────────────────

function Get-OwnershipSha256Hex {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes) { $Bytes = [byte[]]@() }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($Bytes) }
    finally { $sha.Dispose() }
    return ([System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant())
}

function Get-OwnershipTextSha256Hex {
    param([string]$Text)
    return (Get-OwnershipSha256Hex -Bytes $script:OwnershipUtf8.GetBytes($Text))
}

# Normalize CRLF to LF for Git-text bytes (no NUL byte); keep binary raw.
function ConvertTo-OwnershipNormalizedBytes {
    param([byte[]]$Data)
    if ($null -eq $Data) { return ,([byte[]]@()) }
    if ([System.Array]::IndexOf($Data, [byte]0) -ge 0) { return ,$Data }
    if ([System.Array]::IndexOf($Data, [byte]13) -lt 0) { return ,$Data }
    $text = $script:OwnershipLatin1.GetString($Data).Replace("`r`n", "`n")
    return ,$script:OwnershipLatin1.GetBytes($text)
}

function Get-OwnershipContentHash {
    param([byte[]]$Data)
    return (Get-OwnershipSha256Hex -Bytes (ConvertTo-OwnershipNormalizedBytes -Data $Data))
}

function Test-OwnershipBytesEqual {
    param([byte[]]$Left, [byte[]]$Right)
    if ($null -eq $Left -or $null -eq $Right -or $Left.Length -ne $Right.Length) { return $false }
    return ([System.Collections.StructuralComparisons]::StructuralEqualityComparer.Equals($Left, $Right))
}

# Return @{agent = HashSet[string]} for one tracked blob as an installer could write it.
function Get-OwnershipBlobFingerprints {
    param([string]$Name, [byte[]]$Data, [string[]]$Agents)
    $base = ConvertTo-OwnershipNormalizedBytes -Data $Data
    $identity = Get-OwnershipSha256Hex -Bytes $base
    $result = @{}
    foreach ($agent in $Agents) {
        $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        [void]$set.Add($identity)
        $result[$agent] = $set
    }
    $lower = $Name.ToLowerInvariant()
    # The installers substitute the placeholder only in copied skill files.
    $substituted = $false
    if ($Name.StartsWith('skills/', [System.StringComparison]::Ordinal)) { foreach ($extension in $script:OwnershipSubstitutedExtensions) {
        if ($lower.EndsWith($extension, [System.StringComparison]::Ordinal)) { $substituted = $true }
    } }
    if ($substituted) {
        $text = $script:OwnershipLatin1.GetString($base)
        if ($text.Contains($script:OwnershipPlaceholder)) {
            foreach ($agent in $Agents) {
                $replaced = $text.Replace($script:OwnershipPlaceholder, '.' + $agent)
                [void]$result[$agent].Add((Get-OwnershipSha256Hex -Bytes $script:OwnershipLatin1.GetBytes($replaced)))
            }
        }
    }
    return $result
}

# ── JSON (Python json module compatible) ────────────────────────────────────

$script:OwnershipJsonToken = New-Object System.Text.RegularExpressions.Regex(
    '\G[ \t\n\r]*(?:([{}\[\]:,])|("(?:[^"\\\x00-\x1F]+|\\["\\/bfnrt]|\\u[0-9A-Fa-f]{4})*")|(-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)|(true|false|null))',
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
)
$script:OwnershipJsonTrailing = New-Object System.Text.RegularExpressions.Regex('\G[ \t\n\r]*\z')
$script:OwnershipJsonEscapeAscii = New-Object System.Text.RegularExpressions.Regex('[^\x20-\x7E]|["\\]')
$script:OwnershipJsonEscapeUnicode = New-Object System.Text.RegularExpressions.Regex('[\x00-\x1F"\\]')

function New-OwnershipJsonNumber {
    param([string]$Text)
    return (New-Object PSObject -Property @{ OwnershipJsonNumber = $Text })
}

function Test-OwnershipJsonNumber {
    param($Value)
    return ($Value -is [System.Management.Automation.PSCustomObject] -and $null -ne $Value.PSObject.Properties['OwnershipJsonNumber'])
}

$script:OwnershipNonFiniteMarker = 'non-finite JSON number: '

# Python repr() of the double parsed from Text.
function Format-OwnershipPythonFloat {
    param([string]$Text)
    $value = [double]::Parse($Text, [System.Globalization.NumberStyles]::Float, $script:OwnershipInvariant)
    if ([double]::IsPositiveInfinity($value)) { return 'Infinity' }
    if ([double]::IsNegativeInfinity($value)) { return '-Infinity' }
    $negative = [System.BitConverter]::DoubleToInt64Bits($value) -lt 0
    $sign = if ($negative) { '-' } else { '' }
    if ($value -eq 0) { return ($sign + '0.0') }
    $scientific = $null
    for ($precision = 1; $precision -le 17; $precision++) {
        $candidate = $value.ToString('E' + ($precision - 1), $script:OwnershipInvariant)
        if ([double]::Parse($candidate, [System.Globalization.NumberStyles]::Float, $script:OwnershipInvariant) -eq $value) {
            $scientific = $candidate
            break
        }
    }
    if ($null -eq $scientific) { $scientific = $value.ToString('E16', $script:OwnershipInvariant) }
    $parts = $scientific.TrimStart('-').Split('E')
    $digits = $parts[0].Replace('.', '').TrimEnd('0')
    if ($digits.Length -eq 0) { $digits = '0' }
    $exponent = [int]::Parse($parts[1], $script:OwnershipInvariant)
    $point = $exponent + 1
    if ($point -gt -4 -and $point -le 16) {
        if ($point -le 0) { return ($sign + '0.' + ('0' * (-$point)) + $digits) }
        if ($point -ge $digits.Length) { return ($sign + $digits + ('0' * ($point - $digits.Length)) + '.0') }
        return ($sign + $digits.Substring(0, $point) + '.' + $digits.Substring($point))
    }
    $mantissa = $digits.Substring(0, 1)
    if ($digits.Length -gt 1) { $mantissa += '.' + $digits.Substring(1) }
    $exponentSign = if ($exponent -lt 0) { '-' } else { '+' }
    $exponentDigits = ([System.Math]::Abs($exponent)).ToString($script:OwnershipInvariant).PadLeft(2, '0')
    return ($sign + $mantissa + 'e' + $exponentSign + $exponentDigits)
}

function ConvertFrom-OwnershipJsonString {
    param([string]$Token)
    $body = $Token.Substring(1, $Token.Length - 2)
    if ($body.IndexOf('\') -lt 0) { return $body }
    $builder = New-Object System.Text.StringBuilder
    $index = 0
    while ($index -lt $body.Length) {
        $character = $body[$index]
        if ($character -ne '\') { [void]$builder.Append($character); $index++; continue }
        $escape = $body[$index + 1]
        switch -CaseSensitive ([string]$escape) {
            '"' { [void]$builder.Append('"') }
            '\' { [void]$builder.Append('\') }
            '/' { [void]$builder.Append('/') }
            'b' { [void]$builder.Append([char]8) }
            'f' { [void]$builder.Append([char]12) }
            'n' { [void]$builder.Append([char]10) }
            'r' { [void]$builder.Append([char]13) }
            't' { [void]$builder.Append([char]9) }
            'u' {
                $code = [System.Convert]::ToInt32($body.Substring($index + 2, 4), 16)
                [void]$builder.Append([char]$code)
                $index += 4
            }
        }
        $index += 2
    }
    return $builder.ToString()
}

function Read-OwnershipJsonValue {
    param([int]$Depth)
    if ($Depth -gt 512) { throw 'JSON nesting is too deep' }
    $position = $script:OwnershipJsonPosition
    if ($position -ge $script:OwnershipJsonKinds.Count) { throw 'unexpected end of JSON' }
    $kind = $script:OwnershipJsonKinds[$position]
    $text = $script:OwnershipJsonTexts[$position]
    $script:OwnershipJsonPosition = $position + 1
    if ($kind -eq 1) { return (ConvertFrom-OwnershipJsonString -Token $text) }
    if ($kind -eq 2) {
        if ($text.IndexOf('.') -lt 0 -and $text.IndexOf('e') -lt 0 -and $text.IndexOf('E') -lt 0) {
            if ($text -eq '-0') { $text = '0' }
            return (New-OwnershipJsonNumber -Text $text)
        }
        # A number outside the double range overflows on .NET Framework and
        # becomes Infinity on .NET; neither can be written back as JSON.
        $formatted = $null
        try { $formatted = Format-OwnershipPythonFloat -Text $text } catch { $formatted = $null }
        if ($null -eq $formatted -or $formatted -eq 'Infinity' -or $formatted -eq '-Infinity') {
            throw (New-Object System.FormatException ($script:OwnershipNonFiniteMarker + $text))
        }
        return (New-OwnershipJsonNumber -Text $formatted)
    }
    if ($kind -eq 3) {
        if ($text -eq 'true') { return $true }
        if ($text -eq 'false') { return $false }
        return $null
    }
    if ($text -eq '{') {
        $map = New-OwnershipMap
        if ($script:OwnershipJsonTexts[$script:OwnershipJsonPosition] -eq '}' -and $script:OwnershipJsonKinds[$script:OwnershipJsonPosition] -eq 0) {
            $script:OwnershipJsonPosition++
            return ,$map
        }
        while ($true) {
            $keyPosition = $script:OwnershipJsonPosition
            if ($keyPosition -ge $script:OwnershipJsonKinds.Count -or $script:OwnershipJsonKinds[$keyPosition] -ne 1) { throw 'expected a JSON object key' }
            $key = ConvertFrom-OwnershipJsonString -Token $script:OwnershipJsonTexts[$keyPosition]
            $script:OwnershipJsonPosition = $keyPosition + 1
            if ($script:OwnershipJsonPosition -ge $script:OwnershipJsonKinds.Count -or $script:OwnershipJsonTexts[$script:OwnershipJsonPosition] -ne ':') { throw 'expected a colon' }
            $script:OwnershipJsonPosition++
            $value = Read-OwnershipJsonValue -Depth ($Depth + 1)
            $map[$key] = $value
            $separator = $script:OwnershipJsonPosition
            if ($separator -ge $script:OwnershipJsonKinds.Count -or $script:OwnershipJsonKinds[$separator] -ne 0) { throw 'unterminated JSON object' }
            $script:OwnershipJsonPosition = $separator + 1
            if ($script:OwnershipJsonTexts[$separator] -eq '}') { return ,$map }
            if ($script:OwnershipJsonTexts[$separator] -ne ',') { throw 'expected an object separator' }
        }
    }
    if ($text -eq '[') {
        $list = New-Object System.Collections.ArrayList
        if ($script:OwnershipJsonTexts[$script:OwnershipJsonPosition] -eq ']' -and $script:OwnershipJsonKinds[$script:OwnershipJsonPosition] -eq 0) {
            $script:OwnershipJsonPosition++
            return ,$list
        }
        while ($true) {
            $value = Read-OwnershipJsonValue -Depth ($Depth + 1)
            [void]$list.Add($value)
            $separator = $script:OwnershipJsonPosition
            if ($separator -ge $script:OwnershipJsonKinds.Count -or $script:OwnershipJsonKinds[$separator] -ne 0) { throw 'unterminated JSON array' }
            $script:OwnershipJsonPosition = $separator + 1
            if ($script:OwnershipJsonTexts[$separator] -eq ']') { return ,$list }
            if ($script:OwnershipJsonTexts[$separator] -ne ',') { throw 'expected an array separator' }
        }
    }
    throw 'unexpected JSON token'
}

# Parse JSON text as Python's json.loads does: objects keep key order (a
# repeated key keeps its first position and its last value), numbers keep
# Python's canonical text. Throws on invalid JSON.
function ConvertFrom-OwnershipJson {
    param([string]$Text)
    $kinds = New-Object 'System.Collections.Generic.List[int]'
    $texts = New-Object 'System.Collections.Generic.List[string]'
    $position = 0
    while ($true) {
        $match = $script:OwnershipJsonToken.Match($Text, $position)
        if (-not $match.Success) {
            if (-not $script:OwnershipJsonTrailing.Match($Text, $position).Success) { throw 'invalid JSON text' }
            break
        }
        for ($group = 1; $group -le 4; $group++) {
            if ($match.Groups[$group].Success) {
                [void]$kinds.Add($group - 1)
                [void]$texts.Add($match.Groups[$group].Value)
                break
            }
        }
        $position = $match.Index + $match.Length
    }
    [void]$kinds.Add(-1)
    [void]$texts.Add('')
    $script:OwnershipJsonKinds = $kinds
    $script:OwnershipJsonTexts = $texts
    $script:OwnershipJsonPosition = 0
    if ($kinds.Count -eq 1) { throw 'empty JSON text' }
    $value = Read-OwnershipJsonValue -Depth 0
    if ($script:OwnershipJsonPosition -ne $kinds.Count - 1) { throw 'trailing JSON content' }
    return ,$value
}

function ConvertTo-OwnershipJsonString {
    param([string]$Value, [bool]$EnsureAscii)
    $pattern = if ($EnsureAscii) { $script:OwnershipJsonEscapeAscii } else { $script:OwnershipJsonEscapeUnicode }
    if (-not $pattern.IsMatch($Value)) { return ('"' + $Value + '"') }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
        $code = [int]$character
        if ($character -eq '"') { [void]$builder.Append('\"') }
        elseif ($character -eq '\') { [void]$builder.Append('\\') }
        elseif ($code -eq 10) { [void]$builder.Append('\n') }
        elseif ($code -eq 13) { [void]$builder.Append('\r') }
        elseif ($code -eq 9) { [void]$builder.Append('\t') }
        elseif ($code -eq 8) { [void]$builder.Append('\b') }
        elseif ($code -eq 12) { [void]$builder.Append('\f') }
        elseif ($code -lt 32 -or ($EnsureAscii -and $code -gt 126)) { [void]$builder.Append('\u' + $code.ToString('x4')) }
        else { [void]$builder.Append($character) }
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Write-OwnershipJsonValue {
    param($Builder, $Value, [bool]$SortKeys, [bool]$EnsureAscii, [int]$Indent, [int]$Level)
    if ($null -eq $Value) { [void]$Builder.Append('null'); return }
    if ($Value -is [bool]) { [void]$Builder.Append($(if ($Value) { 'true' } else { 'false' })); return }
    if ($Value -is [string]) { [void]$Builder.Append((ConvertTo-OwnershipJsonString -Value $Value -EnsureAscii $EnsureAscii)); return }
    if (Test-OwnershipJsonNumber $Value) { [void]$Builder.Append($Value.OwnershipJsonNumber); return }
    if ($Value -is [int] -or $Value -is [long]) { [void]$Builder.Append($Value.ToString($script:OwnershipInvariant)); return }
    $itemSeparator = if ($Indent -gt 0) { ',' } else { ',' }
    $keySeparator = if ($Indent -gt 0) { ': ' } else { ':' }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = New-Object 'System.Collections.Generic.List[string]'
        foreach ($key in $Value.Keys) { [void]$keys.Add([string]$key) }
        if ($keys.Count -eq 0) { [void]$Builder.Append('{}'); return }
        $ordered = $keys.ToArray()
        if ($SortKeys) { [System.Array]::Sort($ordered, [System.StringComparer]::Ordinal) }
        [void]$Builder.Append('{')
        $first = $true
        foreach ($key in $ordered) {
            if (-not $first) { [void]$Builder.Append($itemSeparator) }
            $first = $false
            if ($Indent -gt 0) { [void]$Builder.Append("`n" + (' ' * ($Indent * ($Level + 1)))) }
            [void]$Builder.Append((ConvertTo-OwnershipJsonString -Value $key -EnsureAscii $EnsureAscii))
            [void]$Builder.Append($keySeparator)
            Write-OwnershipJsonValue -Builder $Builder -Value $Value[$key] -SortKeys $SortKeys -EnsureAscii $EnsureAscii -Indent $Indent -Level ($Level + 1)
        }
        if ($Indent -gt 0) { [void]$Builder.Append("`n" + (' ' * ($Indent * $Level))) }
        [void]$Builder.Append('}')
        return
    }
    if (Test-OwnershipIsList $Value) {
        if ($Value.Count -eq 0) { [void]$Builder.Append('[]'); return }
        [void]$Builder.Append('[')
        $first = $true
        foreach ($item in $Value) {
            if (-not $first) { [void]$Builder.Append($itemSeparator) }
            $first = $false
            if ($Indent -gt 0) { [void]$Builder.Append("`n" + (' ' * ($Indent * ($Level + 1)))) }
            Write-OwnershipJsonValue -Builder $Builder -Value $item -SortKeys $SortKeys -EnsureAscii $EnsureAscii -Indent $Indent -Level ($Level + 1)
        }
        if ($Indent -gt 0) { [void]$Builder.Append("`n" + (' ' * ($Indent * $Level))) }
        [void]$Builder.Append(']')
        return
    }
    throw "value of type $($Value.GetType().FullName) cannot be serialized"
}

# json.dumps(value, ...) with Python's separators: compact (",", ":") when
# Indent is 0, otherwise indented with (",", ": ").
function ConvertTo-OwnershipJson {
    param($Value, [switch]$SortKeys, [switch]$EnsureAscii, [int]$Indent = 0)
    $builder = New-Object System.Text.StringBuilder
    Write-OwnershipJsonValue -Builder $builder -Value $Value -SortKeys ([bool]$SortKeys) -EnsureAscii ([bool]$EnsureAscii) -Indent $Indent -Level 0
    return $builder.ToString()
}

# UTF-8 bytes of json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).
function Get-OwnershipCanonicalJsonBytes {
    param($Value)
    return ,$script:OwnershipUtf8.GetBytes((ConvertTo-OwnershipJson -Value $Value -SortKeys))
}

function Get-OwnershipCanonicalDigest {
    param($Value)
    return (Get-OwnershipSha256Hex -Bytes (Get-OwnershipCanonicalJsonBytes -Value $Value))
}

# ── Paths ───────────────────────────────────────────────────────────────────

function Test-OwnershipRelativePath {
    param($Value)
    if ($Value -isnot [string] -or $Value.Length -eq 0 -or $Value.StartsWith('/')) { return $false }
    foreach ($segment in $Value.Split('/')) {
        if ($segment -eq '' -or $segment -eq '.' -or $segment -eq '..' -or $segment -cnotmatch $script:OwnershipSegmentPattern) { return $false }
    }
    return $true
}

function Get-OwnershipFoldedName {
    param([string]$Name)
    try { $normalized = $Name.Normalize([System.Text.NormalizationForm]::FormC) }
    catch { $normalized = $Name }
    return $normalized.ToLowerInvariant()
}

function Join-OwnershipPath {
    param([string]$Root, [string]$Relative)
    $result = $Root
    foreach ($segment in $Relative.Split('/')) { $result = [System.IO.Path]::Combine($result, $segment) }
    return $result
}

# Windows path identity: volume serial and file index of the final target, and
# the final path name. Both follow junctions, symbolic links, subst drives and
# 8.3 short names, so aliases of one directory compare equal.
function Initialize-OwnershipPathIdentityInterop {
    if ($null -ne ('AssistantFrameworkOwnership.PathIdentity' -as [Type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace AssistantFrameworkOwnership
{
    public static class PathIdentity
    {
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
        private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out ByHandleFileInformation information);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandleW(SafeFileHandle handle, StringBuilder path, uint length, uint flags);

        // Attribute-only access, full sharing, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS
        // so directories open; reparse points are followed to the final target.
        private static SafeFileHandle Open(string path)
        {
            return CreateFileW(path, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero);
        }

        public static string GetIdentity(string path)
        {
            using (SafeFileHandle handle = Open(path))
            {
                if (handle.IsInvalid) { return null; }
                ByHandleFileInformation information;
                if (!GetFileInformationByHandle(handle, out information)) { return null; }
                return information.VolumeSerialNumber.ToString("x8") + ":" + information.FileIndexHigh.ToString("x8") + information.FileIndexLow.ToString("x8");
            }
        }

        public static string GetFinalPath(string path)
        {
            using (SafeFileHandle handle = Open(path))
            {
                if (handle.IsInvalid) { return null; }
                StringBuilder buffer = new StringBuilder(1024);
                uint length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
                if (length >= buffer.Capacity)
                {
                    buffer = new StringBuilder((int)length + 1);
                    length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
                }
                if (length == 0 || length >= buffer.Capacity) { return null; }
                string result = buffer.ToString(0, (int)length);
                if (result.StartsWith(@"\\?\UNC\", StringComparison.Ordinal)) { return @"\\" + result.Substring(8); }
                if (result.StartsWith(@"\\?\", StringComparison.Ordinal)) { return result.Substring(4); }
                return result;
            }
        }
    }
}
'@
}

function Test-OwnershipPathExists {
    param([string]$LiteralPath)
    return ([System.IO.Directory]::Exists($LiteralPath) -or [System.IO.File]::Exists($LiteralPath))
}

# Identity of an existing path's final target (following every link), or $null.
function Get-OwnershipPathIdentity {
    param([string]$LiteralPath)
    if (-not (Test-OwnershipPathExists $LiteralPath)) { return $null }
    try {
        if (Test-IsWindowsHost) {
            Initialize-OwnershipPathIdentityInterop
            return [AssistantFrameworkOwnership.PathIdentity]::GetIdentity($LiteralPath)
        }
        $item = Get-Item -LiteralPath $LiteralPath -Force
        $target = $item.ResolveLinkTarget($true)
        if ($null -ne $target) { $item = Get-Item -LiteralPath $target.FullName -Force }
        return ([string]$item.UnixStat.DeviceId + ':' + [string]$item.UnixStat.Inode)
    }
    catch { return $null }
}

# Final path of an existing path on a non-Windows host: every symbolic link in
# every component resolved.
function Resolve-OwnershipUnixFinalPath {
    param([string]$LiteralPath, [int]$Depth = 0)
    if ($Depth -gt 40) { return $null }
    $full = [System.IO.Path]::GetFullPath($LiteralPath)
    $current = '/'
    foreach ($segment in $full.Split([char]'/')) {
        if (-not $segment) { continue }
        $next = [System.IO.Path]::Combine($current, $segment)
        $info = New-Object System.IO.FileInfo($next)
        if (-not $info.Exists -and -not [System.IO.Directory]::Exists($next) -and $null -eq $info.LinkTarget) { return $null }
        if ($null -ne $info.LinkTarget) {
            $target = [string]$info.LinkTarget
            if (-not [System.IO.Path]::IsPathRooted($target)) { $target = [System.IO.Path]::Combine($current, $target) }
            $next = Resolve-OwnershipUnixFinalPath -LiteralPath $target -Depth ($Depth + 1)
            if ($null -eq $next) { return $null }
        }
        $current = $next
    }
    return $current
}

# Full path with its deepest existing ancestor replaced by that ancestor's
# final path; the missing tail is kept as text.
function Get-OwnershipResolvedPath {
    param([string]$LiteralPath)
    $full = Get-FullPath -LiteralPath $LiteralPath
    $tail = New-Object System.Collections.ArrayList
    $existing = $full
    while ($existing -and -not (Test-OwnershipPathExists $existing)) {
        $parent = [System.IO.Path]::GetDirectoryName($existing)
        if (-not $parent -or $parent -eq $existing) { return $full }
        $tail.Insert(0, [System.IO.Path]::GetFileName($existing))
        $existing = $parent
    }
    try {
        if (Test-IsWindowsHost) {
            Initialize-OwnershipPathIdentityInterop
            $final = [AssistantFrameworkOwnership.PathIdentity]::GetFinalPath($existing)
        }
        else { $final = Resolve-OwnershipUnixFinalPath -LiteralPath $existing }
    }
    catch { $final = $null }
    if (-not $final) { return $full }
    foreach ($segment in $tail) { $final = [System.IO.Path]::Combine($final, $segment) }
    return $final
}

function Test-OwnershipTextSameOrInside {
    param([string]$Candidate, [string]$Container)
    $left = (Normalize-PathForComparison -LiteralPath $Candidate)
    $right = (Normalize-PathForComparison -LiteralPath $Container)
    if ([string]::Equals($left, $right, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $prefix = $right.TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
    return $left.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

# True when Candidate is Container or lies inside it, comparing the paths as
# given, their final paths (links, junctions, subst drives, 8.3 names and case
# resolved), and the identity of every existing ancestor of the final path.
function Test-OwnershipSameOrInside {
    param([string]$Candidate, [string]$Container)
    if (Test-OwnershipTextSameOrInside $Candidate $Container) { return $true }
    $resolvedCandidate = Get-OwnershipResolvedPath -LiteralPath $Candidate
    $resolvedContainer = Get-OwnershipResolvedPath -LiteralPath $Container
    if (Test-OwnershipTextSameOrInside $resolvedCandidate $resolvedContainer) { return $true }
    $containerIdentity = Get-OwnershipPathIdentity -LiteralPath $resolvedContainer
    if ($null -eq $containerIdentity) { return $false }
    $current = $resolvedCandidate
    while ($current) {
        $identity = Get-OwnershipPathIdentity -LiteralPath $current
        if ($null -ne $identity -and $identity -ceq $containerIdentity) { return $true }
        $parent = [System.IO.Path]::GetDirectoryName($current)
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
    return $false
}

function Test-OwnershipSamePath {
    param([string]$Left, [string]$Right)
    if (Test-PathEqual -Left $Left -Right $Right) { return $true }
    $resolvedLeft = Get-OwnershipResolvedPath -LiteralPath $Left
    $resolvedRight = Get-OwnershipResolvedPath -LiteralPath $Right
    if (Test-PathEqual -Left $resolvedLeft -Right $resolvedRight) { return $true }
    $leftIdentity = Get-OwnershipPathIdentity -LiteralPath $resolvedLeft
    return ($null -ne $leftIdentity -and $leftIdentity -ceq (Get-OwnershipPathIdentity -LiteralPath $resolvedRight))
}

# Refuse a delete when any directory between Root and the entry's parent is no
# longer a plain directory (a link or junction swapped in since the proof).
function Assert-OwnershipParentChain {
    param([string]$Root, [string]$LiteralPath)
    $rootInfo = Get-OwnershipNodeInfo -LiteralPath $Root
    if ($rootInfo.Type -ne 'dir') { throw "the root is no longer a plain directory: $Root" }
    $rootText = $Root.TrimEnd([char[]]@('\', '/'))
    if (-not $LiteralPath.StartsWith($rootText + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::Ordinal) -and
        -not $LiteralPath.StartsWith($rootText + '/', [System.StringComparison]::Ordinal)) {
        throw "not below its root: $LiteralPath"
    }
    $segments = $LiteralPath.Substring($rootText.Length + 1).Split([char[]]@('\', '/'))
    $current = $rootText
    for ($index = 0; $index -lt $segments.Count - 1; $index++) {
        $current = [System.IO.Path]::Combine($current, $segments[$index])
        $info = Get-OwnershipNodeInfo -LiteralPath $current
        if ($info.Type -ne 'dir') { throw "parent directory is no longer a plain directory: $current" }
    }
}

# ── Inventory and proof data ────────────────────────────────────────────────

function Read-OwnershipJsonFile {
    param([string]$LiteralPath, [string]$Label)
    if (-not [System.IO.File]::Exists($LiteralPath)) {
        if ([System.IO.Directory]::Exists($LiteralPath)) { Stop-OwnershipRefusal "$Label unreadable: ${LiteralPath}: is a directory" }
        Stop-OwnershipRefusal "$Label missing: $LiteralPath"
    }
    try { $raw = [System.IO.File]::ReadAllBytes($LiteralPath) }
    catch { Stop-OwnershipRefusal "$Label unreadable: ${LiteralPath}: $($_.Exception.Message)" }
    try {
        $text = $script:OwnershipUtf8Strict.GetString($raw)
        $value = ConvertFrom-OwnershipJson -Text $text
    }
    catch { Stop-OwnershipRefusal "$Label is not valid UTF-8 JSON: $LiteralPath" }
    return @{ Value = $value; Raw = $raw }
}

function Assert-OwnershipVersion {
    param($Value, [string]$Major, [string]$Label)
    if ($Value -isnot [string]) { Stop-OwnershipRefusal "$Label schema_version missing or not a string" }
    $match = [regex]::Match($Value, $script:OwnershipVersionPattern)
    if (-not $match.Success) { Stop-OwnershipRefusal "$Label schema_version is not MAJOR.MINOR: $Value" }
    if ($match.Groups[1].Value -ne $Major) { Stop-OwnershipRefusal "$Label schema_version $Value has an unknown major version" }
}

function Get-OwnershipExpectedSourcePath {
    param($Entry)
    $kind = $Entry['kind']; $root = $Entry['root']; $path = $Entry['path']
    if ($kind -eq 'skill_directory') {
        if ($root -eq 'agents_skills') { return ('skills/' + $path) }
        return $path
    }
    if ($kind -eq 'agent_file') {
        $name = $path.Split('/', 2)[1]
        if ($name.EndsWith('.md', [System.StringComparison]::Ordinal)) { return ('agents/claude/' + $name) }
        return ('agents/codex/' + $name)
    }
    if (Test-OwnershipContainsOrdinal $script:OwnershipHookFileKinds $kind) { return ('hooks/scripts/' + $path.Substring('hooks/assistant/'.Length)) }
    if ($kind -eq 'managed_tool' -or $kind -eq 'managed_tool_empty_directory') {
        if ($root -eq 'agents_tools') { return ('tools/' + $path) }
        return $path
    }
    return $null
}

# Path of a tool entry relative to the agent's tools target.
function Get-OwnershipToolRelativePath {
    param($Entry)
    if ($Entry['root'] -eq 'agents_tools') { return $Entry['path'] }
    return $Entry['path'].Substring('tools/'.Length)
}

function Test-OwnershipEntry {
    param($Entry, $Proof)
    if (-not ($Entry -is [System.Collections.IDictionary])) { Stop-OwnershipRefusal 'inventory entry is not an object' }
    $entryId = Get-OwnershipValue $Entry 'id'
    if ($entryId -isnot [string] -or $entryId.Length -eq 0 -or $entryId -cne $entryId.ToLowerInvariant() -or $entryId -cnotmatch $script:OwnershipIdPattern) {
        $shown = if ($entryId -is [string]) { "'" + $entryId + "'" } else { 'None' }
        Stop-OwnershipRefusal "inventory entry id missing or invalid: $shown"
    }
    $prefix = "inventory entry ${entryId}: "
    $kind = Get-OwnershipValue $Entry 'kind'
    if ($kind -isnot [string] -or -not (Test-OwnershipContainsOrdinal $script:OwnershipRetiredKinds $kind)) { Stop-OwnershipRefusal ($prefix + "unknown kind '$kind'") }
    $root = Get-OwnershipValue $Entry 'root'
    if ($root -isnot [string] -or -not (Test-OwnershipContainsOrdinal $script:OwnershipRoots $root)) { Stop-OwnershipRefusal ($prefix + "unknown root '$root'") }
    $path = Get-OwnershipValue $Entry 'path'
    if (-not (Test-OwnershipRelativePath $path)) { Stop-OwnershipRefusal ($prefix + "invalid path '$path'") }
    $agents = Get-OwnershipValue $Entry 'agents'
    if (-not (Test-OwnershipStringList $agents $script:OwnershipAgents)) { Stop-OwnershipRefusal ($prefix + 'agents must be a non-empty list of claude, codex and gemini') }
    $layouts = Get-OwnershipValue $Entry 'layouts'
    if (-not (Test-OwnershipStringList $layouts $script:OwnershipLayouts)) { Stop-OwnershipRefusal ($prefix + 'layouts must be a non-empty list of unix and windows') }
    if ($root -ne 'agent_home' -and (-not (Test-OwnershipListEquals $agents @('codex')) -or -not (Test-OwnershipListEquals $layouts @('windows')))) {
        Stop-OwnershipRefusal ($prefix + "root $root applies only to codex on windows")
    }

    $nodeType = Get-OwnershipValue $Entry 'node_type'
    if (Test-OwnershipContainsOrdinal $script:OwnershipNoNodeTypeKinds $kind) {
        if (Test-OwnershipHasKey $Entry 'node_type') { Stop-OwnershipRefusal ($prefix + "node_type is not allowed for $kind") }
    }
    elseif ($nodeType -isnot [string] -or -not (Test-OwnershipContainsOrdinal $script:OwnershipNodeTypes $nodeType)) {
        Stop-OwnershipRefusal ($prefix + 'node_type must be file or directory')
    }

    $generated = $false
    if (Test-OwnershipHasKey $Entry 'installer_generated') { $generated = $Entry['installer_generated'] }
    if ($generated -isnot [bool]) { Stop-OwnershipRefusal ($prefix + 'installer_generated must be a boolean') }
    if ($generated -and $kind -ne 'source_only_tool') { Stop-OwnershipRefusal ($prefix + 'installer_generated is allowed only on source_only_tool') }

    $exact = New-OwnershipList
    if (Test-OwnershipHasKey $Entry 'installer_exact_removal') { $exact = $Entry['installer_exact_removal'] }
    $exactValid = Test-OwnershipIsList $exact
    if ($exactValid) {
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        foreach ($layout in $exact) {
            if ($layout -isnot [string] -or -not (Test-OwnershipContainsOrdinal @($layouts) $layout) -or -not $seen.Add($layout)) { $exactValid = $false }
        }
    }
    if (-not $exactValid) { Stop-OwnershipRefusal ($prefix + 'installer_exact_removal must be a subset of layouts') }
    if ($exact.Count -gt 0 -and -not (Test-OwnershipContainsOrdinal $script:OwnershipToolKinds $kind)) {
        Stop-OwnershipRefusal ($prefix + "installer_exact_removal is not allowed on $kind")
    }

    $needsSource = (Test-OwnershipContainsOrdinal $script:OwnershipSourcePathKinds $kind) -and -not $generated
    if ($needsSource) {
        $sourcePath = Get-OwnershipValue $Entry 'source_path'
        if (-not (Test-OwnershipRelativePath $sourcePath)) { Stop-OwnershipRefusal ($prefix + 'source_path missing or invalid') }
        if ($sourcePath -cne (Get-OwnershipExpectedSourcePath $Entry)) { Stop-OwnershipRefusal ($prefix + "source_path $sourcePath does not map from path $path") }
        $retiredIn = Get-OwnershipValue $Entry 'retired_in'
        if ($retiredIn -isnot [string] -or $retiredIn -cnotmatch $script:OwnershipCommitPattern) { Stop-OwnershipRefusal ($prefix + 'retired_in must be a full lowercase commit id') }
    }
    elseif ($generated) {
        foreach ($field in @('source_path', 'retired_in', 'content_proof')) {
            if (Test-OwnershipHasKey $Entry $field) { Stop-OwnershipRefusal ($prefix + "$field is not allowed on an installer_generated entry") }
        }
    }

    $needsProof = -not (Test-OwnershipContainsOrdinal $script:OwnershipNoNodeTypeKinds $kind) -and $kind -ne 'managed_tool_empty_directory' -and -not $generated
    if ($needsProof) {
        $key = Get-OwnershipValue $Entry 'content_proof'
        if ($key -isnot [string] -or $key.Length -eq 0) { Stop-OwnershipRefusal ($prefix + 'content_proof missing') }
        if (-not (Test-OwnershipHasKey $Proof['proofs'] $key)) { Stop-OwnershipRefusal ($prefix + "content_proof key does not resolve: $key") }
    }
    elseif (Test-OwnershipHasKey $Entry 'content_proof') {
        Stop-OwnershipRefusal ($prefix + "content_proof is not allowed on $kind")
    }

    if ($kind -eq 'instruction_block') {
        $markers = Get-OwnershipValue $Entry 'markers'
        if (-not ($markers -is [System.Collections.IDictionary])) { Stop-OwnershipRefusal ($prefix + 'markers missing') }
        $start = Get-OwnershipValue $markers 'start'
        $end = Get-OwnershipValue $markers 'end'
        foreach ($marker in @($start, $end)) {
            if ($marker -isnot [string] -or $marker.Trim().Length -eq 0 -or $marker.Contains("`n") -or $marker.Contains("`r")) {
                Stop-OwnershipRefusal ($prefix + 'markers.start and markers.end must be single-line strings')
            }
        }
        if ($start -ceq $end) { Stop-OwnershipRefusal ($prefix + 'markers.start and markers.end must differ') }
        if ($path.Contains('/')) { Stop-OwnershipRefusal ($prefix + 'instruction_block path must be an instruction file name') }
    }

    $segments = $path.Split('/')
    if ($kind -eq 'skill_directory') {
        if ($nodeType -ne 'directory') { Stop-OwnershipRefusal ($prefix + 'skill_directory must be a directory') }
        $expected = if ($root -eq 'agents_skills') { 1 } else { 2 }
        if ($segments.Count -ne $expected -or ($expected -eq 2 -and $segments[0] -cne 'skills')) { Stop-OwnershipRefusal ($prefix + 'skill_directory path must be skills/<name>') }
        if (-not $segments[$segments.Count - 1].StartsWith('assistant-', [System.StringComparison]::Ordinal)) { Stop-OwnershipRefusal ($prefix + 'skill_directory name must start with assistant-') }
    }
    elseif ($kind -eq 'agent_file') {
        if ($nodeType -ne 'file' -or $segments.Count -ne 2 -or $segments[0] -cne 'agents') { Stop-OwnershipRefusal ($prefix + 'agent_file path must be agents/<name>') }
        if ($segments[1].EndsWith('.md', [System.StringComparison]::Ordinal)) {
            if (-not (Test-OwnershipListEquals $agents @('claude'))) { Stop-OwnershipRefusal ($prefix + 'an agents/*.md file applies to claude only') }
        }
        elseif ($segments[1].EndsWith('.toml', [System.StringComparison]::Ordinal)) {
            if (-not (Test-OwnershipListEquals $agents @('codex'))) { Stop-OwnershipRefusal ($prefix + 'an agents/*.toml file applies to codex only') }
        }
        else { Stop-OwnershipRefusal ($prefix + 'agent_file must be a .md or .toml file') }
    }
    elseif ($kind -eq 'hook_entrypoint' -or $kind -eq 'hook_helper' -or $kind -eq 'hook_registration') {
        if ($segments.Count -ne 3 -or $segments[0] -cne 'hooks' -or $segments[1] -cne 'assistant') { Stop-OwnershipRefusal ($prefix + "$kind path must be hooks/assistant/<name>") }
    }
    elseif ($kind -eq 'hook_module') {
        if ($segments.Count -ne 4 -or $segments[0] -cne 'hooks' -or $segments[1] -cne 'assistant' -or -not $segments[2].EndsWith('.d', [System.StringComparison]::Ordinal)) {
            Stop-OwnershipRefusal ($prefix + 'hook_module path must be hooks/assistant/<directory>.d/<name>')
        }
    }
    elseif (Test-OwnershipContainsOrdinal $script:OwnershipToolKinds $kind) {
        if ($root -eq 'agent_home' -and ($segments[0] -cne 'tools' -or $segments.Count -lt 2)) { Stop-OwnershipRefusal ($prefix + "$kind path must be under tools/") }
        if ($kind -eq 'managed_tool_empty_directory' -and $nodeType -ne 'directory') { Stop-OwnershipRefusal ($prefix + 'managed_tool_empty_directory must be a directory') }
    }
    if ((Test-OwnershipContainsOrdinal $script:OwnershipHookFileKinds $kind) -and $nodeType -ne 'file') { Stop-OwnershipRefusal ($prefix + "$kind must be a file") }
}

function Test-OwnershipProofData {
    param($Proof)
    if (-not ($Proof -is [System.Collections.IDictionary])) { Stop-OwnershipRefusal 'content-proof data is not an object' }
    Assert-OwnershipVersion -Value (Get-OwnershipValue $Proof 'schema_version') -Major $script:OwnershipProofMajor -Label 'content-proof data'
    $proofs = Get-OwnershipValue $Proof 'proofs'
    if (-not ($proofs -is [System.Collections.IDictionary])) { Stop-OwnershipRefusal 'content-proof data has no proofs object' }
    foreach ($key in @($proofs.Keys)) {
        $value = $proofs[$key]
        $files = Get-OwnershipValue $value 'files'
        if (-not ($value -is [System.Collections.IDictionary]) -or -not ($files -is [System.Collections.IDictionary]) -or $files.Count -eq 0) {
            Stop-OwnershipRefusal "content-proof key $key has no files"
        }
        foreach ($relative in @($files.Keys)) {
            if ($relative -ne '' -and -not (Test-OwnershipRelativePath $relative)) { Stop-OwnershipRefusal "content-proof key $key has an invalid file path" }
            $perAgent = $files[$relative]
            if (-not ($perAgent -is [System.Collections.IDictionary])) { Stop-OwnershipRefusal "content-proof key $key file $relative is not an object" }
            foreach ($agent in @($perAgent.Keys)) {
                $hashes = $perAgent[$agent]
                if (-not (Test-OwnershipContainsOrdinal $script:OwnershipAgents $agent) -or -not (Test-OwnershipIsList $hashes) -or $hashes.Count -eq 0) {
                    Stop-OwnershipRefusal "content-proof key $key file $relative has an invalid agent list"
                }
                foreach ($hash in $hashes) {
                    if ($hash -isnot [string] -or $hash -cnotmatch $script:OwnershipHashPattern) { Stop-OwnershipRefusal "content-proof key $key has an invalid hash" }
                }
            }
        }
    }
}

function Test-OwnershipInventory {
    param($Inventory, $Proof)
    Test-OwnershipProofData -Proof $Proof
    if (-not ($Inventory -is [System.Collections.IDictionary])) { Stop-OwnershipRefusal 'inventory is not an object' }
    Assert-OwnershipVersion -Value (Get-OwnershipValue $Inventory 'schema_version') -Major $script:OwnershipInventoryMajor -Label 'inventory'
    $entries = Get-OwnershipValue $Inventory 'entries'
    if (-not (Test-OwnershipIsList $entries) -or $entries.Count -eq 0) { Stop-OwnershipRefusal 'inventory entries missing or empty' }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($entry in $entries) {
        Test-OwnershipEntry -Entry $entry -Proof $Proof
        if (-not $seen.Add($entry['id'])) { Stop-OwnershipRefusal "duplicate inventory id: $($entry['id'])" }
    }
}

# Validated inventory and content-proof data from Directory.
function Read-OwnershipData {
    param([string]$Directory)
    $inventory = Read-OwnershipJsonFile -LiteralPath (Join-Path $Directory 'retired-items.json') -Label 'inventory'
    $proof = Read-OwnershipJsonFile -LiteralPath (Join-Path $Directory 'content-proof.json') -Label 'content-proof data'
    Test-OwnershipInventory -Inventory $inventory.Value -Proof $proof.Value
    $byId = New-OwnershipMap
    foreach ($entry in $inventory.Value['entries']) { $byId[$entry['id']] = $entry }
    return @{
        Inventory = $inventory.Value
        InventoryDigest = (Get-OwnershipSha256Hex -Bytes $inventory.Raw)
        Proof = $proof.Value
        Entries = $inventory.Value['entries']
        ById = $byId
    }
}

# Rows of the installers' exact-name list for one layout: @{kind; node_type; path}.
function Get-OwnershipInstallerList {
    param($Inventory, [string]$Layout)
    $rows = New-Object System.Collections.ArrayList
    foreach ($entry in $Inventory['entries']) {
        $exact = Get-OwnershipValue $entry 'installer_exact_removal'
        if ((Test-OwnershipContainsOrdinal $script:OwnershipToolKinds $entry['kind']) -and $null -ne $exact -and (Test-OwnershipContainsOrdinal @($exact) $Layout)) {
            if ($entry['root'] -ne 'agent_home') { continue }
            [void]$rows.Add(@($entry, (Get-OwnershipToolRelativePath $entry)))
        }
    }
    foreach ($entry in $Inventory['entries']) {
        if ((Test-OwnershipContainsOrdinal $script:OwnershipHookFileKinds $entry['kind']) -and (Test-OwnershipContainsOrdinal @($entry['layouts']) $Layout)) {
            [void]$rows.Add(@($entry, $entry['path'].Substring('hooks/assistant/'.Length)))
        }
    }
    $result = New-Object System.Collections.ArrayList
    foreach ($row in $rows) {
        $entry = $row[0]
        $sorted = Get-OwnershipSortedOrdinal -Values ([string[]]@($entry['agents']))
        if (($sorted -join ',') -cne ($script:OwnershipAgents -join ',')) {
            Stop-OwnershipRefusal "inventory entry $($entry['id']) is not shared by every agent; the installer list cannot express it"
        }
        $item = New-OwnershipMap
        $item['kind'] = $entry['kind']
        $item['node_type'] = $entry['node_type']
        $item['path'] = $row[1]
        [void]$result.Add($item)
    }
    return ,$result
}

# ── Agent homes (Windows layout) ────────────────────────────────────────────

function Get-OwnershipUserHome {
    $name = if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { 'USERPROFILE' } else { 'HOME' }
    $value = if ($name -eq 'USERPROFILE') { $env:USERPROFILE } else { $env:HOME }
    if ([string]::IsNullOrWhiteSpace($value)) { Stop-OwnershipRefusal 'HOME is not set to an absolute path' }
    try { Assert-SafeConfiguredHomePathText -LiteralPath $value -VariableName $name }
    catch { Stop-OwnershipRefusal $_.Exception.Message }
    $full = Get-FullPath -LiteralPath $value
    if (Test-PathEqual -Left $full -Right ([System.IO.Path]::GetPathRoot($full))) { Stop-OwnershipRefusal "$name cannot be a drive or filesystem root." }
    return $full
}

# Return the inventory roots for one agent on Windows, refusing unsafe homes.
function Resolve-OwnershipHomes {
    param([string]$Agent, [string]$CheckoutDir = $null)
    $userHome = Get-OwnershipUserHome
    $script:UserHome = $userHome
    $textual = $null
    if ($Agent -eq 'codex' -and -not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        $textual = $env:CODEX_HOME
        try { Assert-SafeConfiguredHomePathText -LiteralPath $textual -VariableName 'CODEX_HOME' }
        catch { Stop-OwnershipRefusal 'CODEX_HOME must be an absolute path' }
        $agentHome = Get-FullPath -LiteralPath $textual
    }
    else {
        $agentHome = Get-FullPath -LiteralPath (Join-Path $userHome ('.' + $Agent))
    }
    if (Test-OwnershipSamePath -Left $agentHome -Right $userHome) { Stop-OwnershipRefusal 'the agent home resolves to the user home itself' }
    if ($CheckoutDir -and ((Test-OwnershipSameOrInside $agentHome $CheckoutDir) -or (Test-OwnershipSameOrInside $CheckoutDir $agentHome))) {
        Stop-OwnershipRefusal "the agent home and the framework checkout overlap: $agentHome and $CheckoutDir"
    }
    $pathRoot = [System.IO.Path]::GetPathRoot($agentHome)
    if (-not [string]::IsNullOrEmpty($pathRoot) -and (Test-PathEqual -Left $agentHome -Right $pathRoot)) { Stop-OwnershipRefusal 'the agent home resolves to a filesystem root' }
    $userHomePrefix = $userHome.TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
    $boundary = if ($agentHome.StartsWith($userHomePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { $userHome } else { $pathRoot }
    try { [void](Assert-SafeManagedChild -LiteralPath $agentHome -ManagedRoot $boundary -Purpose 'agent home') }
    catch { Stop-OwnershipRefusal ('unsafe agent home: ' + $_.Exception.Message) }
    $roots = New-OwnershipMap
    $roots['agent_home'] = $agentHome
    if ($Agent -eq 'codex') {
        $agentsRoot = Get-FullPath -LiteralPath (Join-Path $userHome '.agents')
        try {
            $roots['agents_skills'] = Assert-SafeManagedChild -LiteralPath (Join-Path $agentsRoot 'skills') -ManagedRoot $agentsRoot -Purpose 'Codex skills root'
            $roots['agents_tools'] = Assert-SafeManagedChild -LiteralPath (Join-Path $agentsRoot 'tools') -ManagedRoot $agentsRoot -Purpose 'Codex common tools root'
            Assert-NoSourceTargetOverlap -Source $agentHome -Target $roots['agents_skills'] -Purpose 'Codex agent home and shared skills root'
        }
        catch { Stop-OwnershipRefusal ('unsafe ~/.agents root: ' + $_.Exception.Message) }
    }
    $text = if ($null -ne $textual) { $textual } else { Join-Path $userHome ('.' + $Agent) }
    return @{ UserHome = $userHome; AgentHome = $agentHome; AgentHomeText = $text; Roots = $roots }
}

# SI-5: Codex dry runs and removals are refused while Codex runs on Windows.
function Assert-OwnershipCodexStopped {
    param([string]$Agent)
    if ($Agent -ne 'codex') { return }
    try { Assert-CodexStopped }
    catch { Stop-OwnershipRefusal ('Codex must be closed first: ' + $_.Exception.Message) }
}

# ── Filesystem inspection ───────────────────────────────────────────────────

function Test-OwnershipReparse {
    param($Attributes)
    return (([int]$Attributes -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-OwnershipDirectoryAttribute {
    param($Attributes)
    return (([int]$Attributes -band [int][System.IO.FileAttributes]::Directory) -ne 0)
}

# Describe one directory entry without following links: Type is absent, link,
# dir, file or other; Signature changes when the entry is replaced or changed;
# Links is the hard-link count of a file (Windows: read through a handle).
function Get-OwnershipNodeInfo {
    param([string]$LiteralPath, [switch]$WithHandle)
    try { $attributes = [System.IO.File]::GetAttributes($LiteralPath) }
    catch { return @{ Type = 'absent'; Signature = 'absent'; Links = 0 } }
    $info = New-Object System.IO.FileInfo($LiteralPath)
    if (Test-OwnershipReparse $attributes) {
        $target = ''
        $linkTarget = $info.PSObject.Properties['LinkTarget']
        if ($null -ne $linkTarget -and $null -ne $linkTarget.Value) { $target = [string]$linkTarget.Value }
        else {
            try { $target = [string](@((Get-Item -LiteralPath $LiteralPath -Force).Target) -join '') } catch { $target = '' }
        }
        return @{ Type = 'link'; Signature = ('link|' + [int]$attributes + '|' + $target); Links = 1; Target = $target; IsDirectory = (Test-OwnershipDirectoryAttribute $attributes) }
    }
    if (-not (Test-IsWindowsHost)) {
        try { $stat = (Get-Item -LiteralPath $LiteralPath -Force).UnixStat }
        catch { return @{ Type = 'absent'; Signature = 'absent'; Links = 0 } }
        $identity = [string]$stat.DeviceId + ':' + [string]$stat.Inode
        $itemType = [string]$stat.ItemType
        if ($itemType -eq 'Directory') { return @{ Type = 'dir'; Signature = ('dir|' + $identity); Links = 1 } }
        $type = if ($itemType -eq 'File') { 'file' } else { 'other' }
        $signature = $type + '|' + $identity + '|' + [string]$stat.Size + '|' + $stat.ModifiedTime.Ticks + '|' + [string]$stat.Mode + '|' + [string]$stat.HardlinkCount
        return @{ Type = $type; Signature = $signature; Links = [int]$stat.HardlinkCount }
    }
    if (Test-OwnershipDirectoryAttribute $attributes) {
        $directory = New-Object System.IO.DirectoryInfo($LiteralPath)
        return @{ Type = 'dir'; Signature = ('dir|' + $directory.CreationTimeUtc.Ticks + '|' + [int]$attributes); Links = 1 }
    }
    $identity = ''
    $links = 1
    if ($WithHandle) {
        $stream = $null
        try {
            $stream = Open-WindowsFileSecurityStream -LiteralPath $LiteralPath
            $identity = Get-WindowsFileIdentity -SafeFileHandle $stream.SafeFileHandle
            $links = [int](Get-WindowsFileLinkCount -SafeFileHandle $stream.SafeFileHandle)
        }
        catch { $identity = 'unopened'; $links = 0 }
        finally { if ($null -ne $stream) { $stream.Dispose() } }
    }
    $info.Refresh()
    $signature = 'file|' + $identity + '|' + $info.Length + '|' + $info.LastWriteTimeUtc.Ticks + '|' + [int]$attributes + '|' + $links
    return @{ Type = 'file'; Signature = $signature; Links = $links }
}

# Read a regular file and confirm it did not change while reading.
# Returns @{Data; Signature; Links}; throws when it is not a stable regular file.
function Read-OwnershipStableFile {
    param([string]$LiteralPath)
    $before = Get-OwnershipNodeInfo -LiteralPath $LiteralPath -WithHandle
    if ($before.Type -ne 'file') { throw 'not a regular file' }
    if ($before.Links -lt 1) { throw 'could not be opened for reading' }
    $data = [System.IO.File]::ReadAllBytes($LiteralPath)
    $after = Get-OwnershipNodeInfo -LiteralPath $LiteralPath -WithHandle
    if ($before.Signature -cne $after.Signature) { throw 'file changed while it was read' }
    return @{ Data = $data; Signature = $before.Signature; Links = $before.Links }
}

# Hash a regular file in chunks without keeping its bytes. Returns @{Raw; Content;
# Signature; Links}: Content equals Get-OwnershipContentHash of the whole file.
function Get-OwnershipStableFileHashes {
    param([string]$LiteralPath)
    $before = Get-OwnershipNodeInfo -LiteralPath $LiteralPath -WithHandle
    if ($before.Type -ne 'file') { throw 'not a regular file' }
    if ($before.Links -lt 1) { throw 'could not be opened for reading' }
    $raw = [System.Security.Cryptography.SHA256]::Create()
    $normalized = [System.Security.Cryptography.SHA256]::Create()
    $stream = $null
    try {
        $stream = New-Object System.IO.FileStream($LiteralPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $buffer = New-Object byte[] 1048576
        $hasNul = $false
        $pendingCr = $false
        while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            [void]$raw.TransformBlock($buffer, 0, $count, $null, 0)
            if (-not $hasNul -and [System.Array]::IndexOf($buffer, [byte]0, 0, $count) -ge 0) { $hasNul = $true }
            $text = $script:OwnershipLatin1.GetString($buffer, 0, $count)
            if ($pendingCr) { $text = "`r" + $text }
            $pendingCr = $text.EndsWith("`r", [System.StringComparison]::Ordinal)
            if ($pendingCr) { $text = $text.Substring(0, $text.Length - 1) }
            $bytes = $script:OwnershipLatin1.GetBytes($text.Replace("`r`n", "`n"))
            [void]$normalized.TransformBlock($bytes, 0, $bytes.Length, $null, 0)
        }
        $tail = New-Object byte[] ([int]$pendingCr)
        if ($pendingCr) { $tail[0] = 13 }
        [void]$normalized.TransformFinalBlock($tail, 0, $tail.Length)
        [void]$raw.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        $rawHex = [System.BitConverter]::ToString($raw.Hash).Replace('-', '').ToLowerInvariant()
        $content = if ($hasNul) { $rawHex } else { [System.BitConverter]::ToString($normalized.Hash).Replace('-', '').ToLowerInvariant() }
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        $raw.Dispose(); $normalized.Dispose()
    }
    $after = Get-OwnershipNodeInfo -LiteralPath $LiteralPath -WithHandle
    if ($before.Signature -cne $after.Signature) { throw 'file changed while it was read' }
    return @{ Raw = $rawHex; Content = $content; Signature = $before.Signature; Links = $before.Links }
}

function Get-OwnershipDirectoryNames {
    param([string]$LiteralPath)
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in [System.IO.Directory]::GetFileSystemEntries($LiteralPath)) {
        [void]$names.Add([System.IO.Path]::GetFileName($entry))
    }
    return ,$names
}

# Find Relative under Root by exact directory-entry names, never following links.
# Returns @{State = absent|problem|ok; Reason; Info}.
function Find-OwnershipPath {
    param([string]$Root, [string]$Relative)
    if (-not [System.IO.Directory]::Exists($Root)) { return @{ State = 'absent' } }
    $current = $Root
    $parts = $Relative.Split('/')
    $info = $null
    for ($index = 0; $index -lt $parts.Count; $index++) {
        $part = $parts[$index]
        try { $names = Get-OwnershipDirectoryNames -LiteralPath $current }
        catch { return @{ State = 'absent' } }
        $shown = ($parts[0..$index] -join '/')
        if (-not (Test-OwnershipContainsOrdinal $names $part)) {
            $folded = Get-OwnershipFoldedName $part
            $variants = @($names | Where-Object { [string]::Equals((Get-OwnershipFoldedName $_), $folded, [System.StringComparison]::Ordinal) })
            if ($variants.Count -gt 0) {
                $first = (Get-OwnershipSortedOrdinal -Values ([string[]]$variants))[0]
                $prefixParts = @()
                if ($index -gt 0) { $prefixParts = @($parts[0..($index - 1)]) }
                $prefix = (@($prefixParts) + @($first)) -join '/'
                return @{ State = 'problem'; Reason = "name differs from the inventory path only by case or Unicode form: $prefix" }
            }
            return @{ State = 'absent' }
        }
        $current = [System.IO.Path]::Combine($current, $part)
        $info = Get-OwnershipNodeInfo -LiteralPath $current
        if ($info.Type -eq 'absent') { return @{ State = 'absent' } }
        if ($info.Type -eq 'link') {
            $label = if (Test-IsWindowsHost) { 'reparse point' } else { 'symbolic link' }
            return @{ State = 'problem'; Reason = "$label at $shown; not followed" }
        }
        if ($index -lt $parts.Count - 1 -and $info.Type -ne 'dir') { return @{ State = 'absent' } }
    }
    return @{ State = 'ok'; Info = $info }
}

# List a directory tree without following links. Returns entries
# @{Relative; Type (file|dir|link|other); Value; Signature; Links} in ordinal order.
function Get-OwnershipDirectoryEntries {
    param([string]$LiteralPath)
    $entries = New-Object System.Collections.ArrayList
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push('')
    while ($stack.Count -gt 0) {
        $relativeDirectory = $stack.Pop()
        $absoluteDirectory = if ($relativeDirectory) { Join-OwnershipPath $LiteralPath $relativeDirectory } else { $LiteralPath }
        $names = Get-OwnershipSortedOrdinal -Values (Get-OwnershipDirectoryNames -LiteralPath $absoluteDirectory).ToArray()
        foreach ($name in $names) {
            $relative = if ($relativeDirectory) { $relativeDirectory + '/' + $name } else { $name }
            $absolute = [System.IO.Path]::Combine($absoluteDirectory, $name)
            $info = Get-OwnershipNodeInfo -LiteralPath $absolute
            if ($info.Type -eq 'link') {
                [void]$entries.Add(@{ Relative = $relative; Type = 'link'; Value = $info.Target; Signature = $info.Signature; Links = 1; IsDirectory = $info.IsDirectory })
            }
            elseif ($info.Type -eq 'dir') {
                [void]$entries.Add(@{ Relative = $relative; Type = 'dir'; Value = ''; Signature = $info.Signature; Links = 1 })
                $stack.Push($relative)
            }
            elseif ($info.Type -eq 'file') {
                $read = Get-OwnershipStableFileHashes -LiteralPath $absolute
                [void]$entries.Add(@{ Relative = $relative; Type = 'file'; Value = $read.Raw; Content = $read.Content; Signature = $read.Signature; Links = $read.Links })
            }
            elseif ($info.Type -eq 'absent') {
                throw "entry disappeared while it was read: $relative"
            }
            else {
                [void]$entries.Add(@{ Relative = $relative; Type = 'other'; Value = ''; Signature = $info.Signature; Links = 1 })
            }
        }
    }
    $sorted = Sort-OwnershipStable -Items $entries -Key { param($entry) $entry.Relative }
    return ,$sorted
}

function Get-OwnershipDirectoryDigest {
    param($Entries)
    $listing = New-Object System.Collections.ArrayList
    foreach ($entry in $Entries) {
        $row = New-Object System.Collections.ArrayList
        [void]$row.Add($entry.Relative)
        if ($entry.Type -eq 'file') { [void]$row.Add('file'); [void]$row.Add([string]$entry.Value) }
        elseif ($entry.Type -eq 'link') { [void]$row.Add('link'); [void]$row.Add([string]$entry.Value) }
        else { [void]$row.Add($entry.Type); [void]$row.Add('') }
        [void]$listing.Add($row)
    }
    return (Get-OwnershipCanonicalDigest -Value $listing)
}

function Test-OwnershipInsideAny {
    param([string]$Relative, $Prefixes)
    foreach ($prefix in @($Prefixes)) {
        if ($Relative -ceq $prefix -or $Relative.StartsWith($prefix + '/', [System.StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

# Relative paths of real build-artifact directories at any depth.
function Get-OwnershipArtifactPrefixes {
    param($Entries)
    $prefixes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in $Entries) {
        if ($entry.Type -ne 'dir') { continue }
        $leaf = $entry.Relative.Substring($entry.Relative.LastIndexOf('/') + 1)
        if ((Test-OwnershipContainsOrdinal $script:OwnershipBuildArtifactDirectories $leaf) -and -not (Test-OwnershipInsideAny $entry.Relative $prefixes)) {
            [void]$prefixes.Add($entry.Relative)
        }
    }
    return ,$prefixes
}

# ── Findings ────────────────────────────────────────────────────────────────

function New-OwnershipFinding {
    param([string]$Id, [string]$Root, [string]$Path, [string]$Kind, [string]$Status, [string]$Reason = '', $Digest = $null, $Spec = $null, $Detail = $null)
    if ($null -eq $Detail) { $Detail = @{} }
    return @{ Id = $Id; Root = $Root; Path = $Path; Kind = $Kind; Status = $Status; Reason = $Reason; Digest = $Digest; Spec = $Spec; Detail = $Detail }
}

function Get-OwnershipManifestItem {
    param($Finding)
    $item = New-OwnershipMap
    $item['id'] = $Finding.Id
    $item['root'] = $Finding.Root
    $item['path'] = $Finding.Path
    $item['kind'] = $Finding.Kind
    $item['digest'] = $Finding.Digest
    return $item
}

function Get-OwnershipSettingsFileName {
    param([string]$Agent)
    if ($Agent -eq 'codex') { return 'hooks.json' }
    return 'settings.json'
}

function Get-OwnershipAsList {
    param($Value)
    if ($null -eq $Value) { return ,@() }
    if (Test-OwnershipIsList $Value) { return ,@($Value) }
    return ,@($Value)
}

# One read of a hook settings file: bytes, parsed value and registrations.
function Read-OwnershipSettingsSnapshot {
    param([string]$AgentHome, [string]$Relative)
    $snapshot = @{ Path = (Join-Path $AgentHome $Relative); Relative = $Relative; Raw = $null; Value = $null; Problem = $null; Present = $false }
    $found = Find-OwnershipPath -Root $AgentHome -Relative $Relative
    if ($found.State -eq 'absent') { return $snapshot }
    $snapshot.Present = $true
    if ($found.State -eq 'problem') { $snapshot.Problem = $found.Reason; return $snapshot }
    if ($found.Info.Type -ne 'file') { $snapshot.Problem = 'not a regular file'; return $snapshot }
    try { $read = Read-OwnershipStableFile -LiteralPath $snapshot.Path }
    catch { $snapshot.Problem = 'invalid JSON; preserved unchanged'; return $snapshot }
    if ($read.Links -gt 1) { $snapshot.Problem = 'hard-linked file'; return $snapshot }
    $snapshot.Raw = $read.Data
    try {
        $text = $script:OwnershipUtf8Strict.GetString($read.Data)
        $value = ConvertFrom-OwnershipJson -Text $text
    }
    catch {
        $message = $_.Exception.Message
        $at = $message.IndexOf($script:OwnershipNonFiniteMarker, [System.StringComparison]::Ordinal)
        if ($at -ge 0) {
            $number = $message.Substring($at + $script:OwnershipNonFiniteMarker.Length)
            $snapshot.Problem = "number $number cannot be written back unchanged; preserved unchanged"
        }
        else { $snapshot.Problem = 'invalid JSON; preserved unchanged' }
        return $snapshot
    }
    try { Assert-JsonTextPropertyIdentitySafe -Text $text }
    catch { $snapshot.Problem = 'duplicate, case-colliding or oversized JSON properties; preserved unchanged'; return $snapshot }
    $hooks = Get-OwnershipValue $value 'hooks'
    if (-not ($value -is [System.Collections.IDictionary]) -or ($null -ne $hooks -and -not ($hooks -is [System.Collections.IDictionary]))) {
        $snapshot.Problem = 'not a JSON object with a hooks object; preserved unchanged'
        return $snapshot
    }
    $snapshot.Value = $value
    return $snapshot
}

# Each event's flattened hook list: @{Event; Index; Hook}.
function Get-OwnershipSettingsCommands {
    param($Snapshot)
    $result = New-Object System.Collections.ArrayList
    if ($null -eq $Snapshot.Value) { return ,$result }
    $hooks = Get-OwnershipValue $Snapshot.Value 'hooks'
    if ($null -eq $hooks) { return ,$result }
    foreach ($event in @($hooks.Keys)) {
        $index = 0
        foreach ($group in (Get-OwnershipAsList $hooks[$event])) {
            if (-not ($group -is [System.Collections.IDictionary])) { continue }
            foreach ($hook in (Get-OwnershipAsList (Get-OwnershipValue $group 'hooks'))) {
                [void]$result.Add(@{ Event = [string]$event; Index = $index; Hook = $hook })
                $index++
            }
        }
    }
    return ,$result
}

# Return a copy of settings with the targeted hooks (keys "event/index")
# removed. Only events that hold a target change; a group left with no hook
# and an event left with no group are dropped, as the installers drop them.
function Remove-OwnershipRegistrations {
    param($Value, $Targets)
    $output = New-OwnershipMap
    foreach ($key in @($Value.Keys)) { $output[$key] = $Value[$key] }
    $cleaned = New-OwnershipMap
    $hooks = Get-OwnershipValue $Value 'hooks'
    if ($null -ne $hooks) {
        foreach ($event in @($hooks.Keys)) {
            $hasTarget = $false
            foreach ($target in $Targets) { if ($target.StartsWith([string]$event + '/', [System.StringComparison]::Ordinal) -and $target.Substring(([string]$event).Length + 1) -match '^[0-9]+\z') { $hasTarget = $true } }
            if (-not $hasTarget) { $cleaned[$event] = $hooks[$event]; continue }
            $index = 0
            $keptGroups = New-Object System.Collections.ArrayList
            foreach ($group in (Get-OwnershipAsList $hooks[$event])) {
                if (-not ($group -is [System.Collections.IDictionary])) { [void]$keptGroups.Add($group); continue }
                $keptHooks = New-Object System.Collections.ArrayList
                $removedHere = 0
                foreach ($hook in (Get-OwnershipAsList (Get-OwnershipValue $group 'hooks'))) {
                    if (-not (Test-OwnershipContainsOrdinal $Targets ([string]$event + '/' + $index))) { [void]$keptHooks.Add($hook) } else { $removedHere++ }
                    $index++
                }
                if ($removedHere -eq 0) { [void]$keptGroups.Add($group); continue }
                if ($keptHooks.Count -gt 0) {
                    $keptGroup = New-OwnershipMap
                    foreach ($groupKey in @($group.Keys)) { $keptGroup[$groupKey] = $group[$groupKey] }
                    $keptGroup['hooks'] = $keptHooks
                    [void]$keptGroups.Add($keptGroup)
                }
            }
            if ($keptGroups.Count -gt 0) { $cleaned[$event] = $keptGroups }
        }
    }
    $output['hooks'] = $cleaned
    return ,$output
}

# Count exact marker lines as install.sh does; lines are Latin-1 decoded bytes.
function Get-OwnershipMarkerState {
    param($Lines, [string]$Start, [string]$End)
    $starts = 0; $ends = 0; $open = $false; $bad = $false; $first = $null; $last = $null
    for ($number = 0; $number -lt $Lines.Count; $number++) {
        $text = $Lines[$number].TrimEnd([char]10).TrimStart([char[]]@([char]32, [char]9)).TrimEnd([char[]]@([char]32, [char]9, [char]13))
        if ([string]::Equals($text, $Start, [System.StringComparison]::Ordinal)) {
            if ($open -or $starts -gt 0) { $bad = $true }
            $starts++; $open = $true; $first = $number
        }
        elseif ([string]::Equals($text, $End, [System.StringComparison]::Ordinal)) {
            if (-not $open) { $bad = $true }
            $ends++; $open = $false; $last = $number
        }
    }
    if ($bad -or $open -or $starts -gt 1 -or $ends -gt 1) { return @{ State = 'ambiguous' } }
    if ($starts -eq 1) { return @{ State = 'block'; First = $first; Last = $last } }
    return @{ State = 'none' }
}

# Return @{State; Removed (bytes); Remaining (bytes)} for one instruction file.
function Get-OwnershipBlockRemoval {
    param([byte[]]$Data, [string]$StartMarker, [string]$EndMarker)
    $text = $script:OwnershipLatin1.GetString($Data)
    $pieces = $text.Split([char]10)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    for ($index = 0; $index -lt $pieces.Count - 1; $index++) { [void]$lines.Add($pieces[$index] + "`n") }
    if ($pieces[$pieces.Count - 1].Length -gt 0) { [void]$lines.Add($pieces[$pieces.Count - 1]) }
    $start = $script:OwnershipLatin1.GetString($script:OwnershipUtf8.GetBytes($StartMarker))
    $end = $script:OwnershipLatin1.GetString($script:OwnershipUtf8.GetBytes($EndMarker))
    $state = Get-OwnershipMarkerState -Lines $lines -Start $start -End $end
    if ($state.State -ne 'block') { return @{ State = $state.State; Removed = $null; Remaining = $null } }
    $begin = $state.First
    $finish = $state.Last + 1
    if ($finish -lt $lines.Count -and ($lines[$finish] -ceq "`n" -or $lines[$finish] -ceq "`r`n")) { $finish++ }
    elseif ($begin -gt 0 -and ($lines[$begin - 1] -ceq "`n" -or $lines[$begin - 1] -ceq "`r`n")) { $begin-- }
    $removed = New-Object System.Text.StringBuilder
    $remaining = New-Object System.Text.StringBuilder
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($index -ge $begin -and $index -lt $finish) { [void]$removed.Append($lines[$index]) }
        else { [void]$remaining.Append($lines[$index]) }
    }
    return @{
        State = 'block'
        Removed = $script:OwnershipLatin1.GetBytes($removed.ToString())
        Remaining = $script:OwnershipLatin1.GetBytes($remaining.ToString())
    }
}

# ── Planning ────────────────────────────────────────────────────────────────

function New-OwnershipPlanner {
    param($Data, [string]$Agent, [string]$Operation, $Homes, [string]$Layout = 'windows', [string]$CheckoutDir = $null, $CurrentSpecs = $null, $CurrentFingerprints = $null)
    if ($null -eq $CurrentSpecs) { $CurrentSpecs = @() }
    if ($null -eq $CurrentFingerprints) { $CurrentFingerprints = @{} }
    return @{
        Data = $Data; Agent = $Agent; Operation = $Operation; Homes = $Homes; Layout = $Layout
        CheckoutDir = $CheckoutDir; CurrentSpecs = @($CurrentSpecs); CurrentFingerprints = $CurrentFingerprints; Roots = $Homes.Roots
    }
}

# Inventory entries that apply to this agent and layout.
function Get-OwnershipPlannerEntries {
    param($Planner, [string[]]$Kinds = $null)
    $result = New-Object System.Collections.ArrayList
    foreach ($entry in $Planner.Data.Entries) {
        if (-not (Test-OwnershipContainsOrdinal @($entry['agents']) $Planner.Agent) -or -not (Test-OwnershipContainsOrdinal @($entry['layouts']) $Planner.Layout)) { continue }
        if (-not (Test-OwnershipHasKey $Planner.Roots $entry['root'])) { continue }
        if ($null -ne $Kinds -and -not (Test-OwnershipContainsOrdinal $Kinds $entry['kind'])) { continue }
        [void]$result.Add($entry)
    }
    return ,$result
}

function Get-OwnershipSpecFingerprints {
    param($Planner, $Spec)
    $key = Get-OwnershipValue $Spec 'content_proof'
    if ($null -eq $key) { return (New-OwnershipMap) }
    if (Get-OwnershipValue $Spec 'current') {
        $value = Get-OwnershipValue $Planner.CurrentFingerprints $key
        if ($null -eq $value) { return (New-OwnershipMap) }
        return $value['files']
    }
    return $Planner.Data.Proof['proofs'][$key]['files']
}

function Test-OwnershipKnownHash {
    param($Files, [string]$Relative, [string]$Agent, [string]$Hash)
    $perAgent = Get-OwnershipValue $Files $Relative
    if ($null -eq $perAgent) { return $false }
    $hashes = Get-OwnershipValue $perAgent $Agent
    if ($null -eq $hashes) { return $false }
    return $hashes.Contains($Hash)
}

function Get-OwnershipPlannerSnapshot {
    param($Planner)
    return (Read-OwnershipSettingsSnapshot -AgentHome $Planner.Roots['agent_home'] -Relative (Get-OwnershipSettingsFileName $Planner.Agent))
}

function Get-OwnershipPathFinding {
    param($Planner, $Spec)
    $root = Get-OwnershipValue $Planner.Roots $Spec['root']
    if ($null -eq $root) { return $null }
    $found = Find-OwnershipPath -Root $root -Relative $Spec['path']
    if ($found.State -eq 'absent') { return $null }
    $id = $Spec['id']; $kind = $Spec['kind']
    if ($found.State -eq 'problem') { return (New-OwnershipFinding $id $Spec['root'] $Spec['path'] $kind 'ambiguous' $found.Reason -Spec $Spec) }
    $absolute = Join-OwnershipPath $root $Spec['path']
    if ($Spec['node_type'] -eq 'file') { return (Get-OwnershipFileFinding -Planner $Planner -Spec $Spec -Absolute $absolute -Info $found.Info) }
    if ($found.Info.Type -ne 'dir') { return (New-OwnershipFinding $id $Spec['root'] $Spec['path'] $kind 'ambiguous' 'not a directory' -Spec $Spec) }
    if ($kind -eq 'managed_tool_empty_directory') {
        return (New-OwnershipFinding $id $Spec['root'] $Spec['path'] $kind 'pending' -Digest (Get-OwnershipCanonicalDigest -Value (New-OwnershipList)) -Spec $Spec -Detail @{ Absolute = $absolute })
    }
    return (Get-OwnershipDirectoryFinding -Planner $Planner -Spec $Spec -Absolute $absolute)
}

function Get-OwnershipFileFinding {
    param($Planner, $Spec, [string]$Absolute, $Info)
    $id = $Spec['id']; $kind = $Spec['kind']; $root = $Spec['root']; $path = $Spec['path']
    if ($Info.Type -ne 'file') { return (New-OwnershipFinding $id $root $path $kind 'ambiguous' 'not a regular file' -Spec $Spec) }
    try { $read = Read-OwnershipStableFile -LiteralPath $Absolute }
    catch { return (New-OwnershipFinding $id $root $path $kind 'ambiguous' "unreadable: $($_.Exception.Message)" -Spec $Spec) }
    if ($read.Links -gt 1) { return (New-OwnershipFinding $id $root $path $kind 'ambiguous' 'hard-linked file; not removed' -Spec $Spec) }
    $digest = Get-OwnershipSha256Hex -Bytes $read.Data
    $files = New-Object System.Collections.ArrayList
    [void]$files.Add(@($Absolute, $read.Signature, $false))
    $detail = @{ Absolute = $Absolute; Files = $files; Dirs = (New-Object System.Collections.ArrayList) }
    if (Get-OwnershipValue $Spec 'installer_generated') { return (New-OwnershipFinding $id $root $path $kind 'removable' -Digest $digest -Spec $Spec -Detail $detail) }
    $known = Get-OwnershipSpecFingerprints -Planner $Planner -Spec $Spec
    $matched = Test-OwnershipKnownHash -Files $known -Relative '' -Agent $Planner.Agent -Hash (Get-OwnershipContentHash -Data $read.Data)
    if (-not $matched -and $kind -eq 'hook_entrypoint') {
        $matched = Test-OwnershipBytesEqual $read.Data $script:OwnershipUtf8.GetBytes($script:OwnershipShimText)
    }
    if ($matched) { return (New-OwnershipFinding $id $root $path $kind 'removable' -Digest $digest -Spec $Spec -Detail $detail) }
    return (New-OwnershipFinding $id $root $path $kind 'unrelated' 'content matches no framework revision' -Digest $digest -Spec $Spec)
}

function Get-OwnershipDirectoryFinding {
    param($Planner, $Spec, [string]$Absolute)
    $id = $Spec['id']; $kind = $Spec['kind']; $root = $Spec['root']; $path = $Spec['path']
    try { $entries = Get-OwnershipDirectoryEntries -LiteralPath $Absolute }
    catch { return (New-OwnershipFinding $id $root $path $kind 'ambiguous' "unreadable: $($_.Exception.Message)" -Spec $Spec) }
    $digest = Get-OwnershipDirectoryDigest -Entries $entries
    $files = New-Object System.Collections.ArrayList
    $dirs = New-Object System.Collections.ArrayList
    foreach ($entry in $entries) {
        $entryPath = Join-OwnershipPath $Absolute $entry.Relative
        if ($entry.Type -eq 'file') { [void]$files.Add(@($entryPath, $entry.Signature, $false)) }
        elseif ($entry.Type -eq 'link') { [void]$files.Add(@($entryPath, $entry.Signature, [bool]$entry.IsDirectory)) }
        elseif ($entry.Type -eq 'dir') { [void]$dirs.Add(@($entryPath, $entry.Signature, $true)) }
    }
    $detail = @{ Absolute = $Absolute; Files = $files; Dirs = $dirs }
    if (Get-OwnershipValue $Spec 'installer_generated') {
        foreach ($entry in $entries) {
            if ($entry.Type -eq 'other') { return (New-OwnershipFinding $id $root $path $kind 'ambiguous' 'holds a special file' -Spec $Spec) }
        }
        return (New-OwnershipFinding $id $root $path $kind 'removable' -Digest $digest -Spec $Spec -Detail $detail)
    }
    $known = Get-OwnershipSpecFingerprints -Planner $Planner -Spec $Spec
    $knownDirectories = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($relative in @($known.Keys)) {
        $parts = ([string]$relative).Split('/')
        for ($index = 1; $index -lt $parts.Count; $index++) { [void]$knownDirectories.Add(($parts[0..($index - 1)] -join '/')) }
    }
    $locationPrefixes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($subtree in @(Get-OwnershipValue $Spec 'location_subtrees')) { if ($subtree) { [void]$locationPrefixes.Add($subtree) } }
    if (Get-OwnershipValue $Spec 'build_artifacts') {
        foreach ($prefix in (Get-OwnershipArtifactPrefixes -Entries $entries)) { [void]$locationPrefixes.Add($prefix) }
    }
    $matched = 0
    $problems = New-Object 'System.Collections.Generic.List[string]'
    $contentOnly = $true
    foreach ($entry in $entries) {
        $relative = $entry.Relative
        if (Test-OwnershipInsideAny $relative $locationPrefixes) {
            if ($entry.Type -eq 'other') { [void]$problems.Add("special file: $relative"); $contentOnly = $false }
            elseif ($entry.Type -eq 'link' -and $locationPrefixes.Contains($relative)) {
                # A linked location root (such as node_modules) is not an installer-made subtree.
                [void]$problems.Add("symbolic link inside the item: $relative"); $contentOnly = $false
            }
            continue
        }
        if ((Get-OwnershipValue $Spec 'build_artifacts') -and $entry.Type -eq 'file' -and $entry.Links -le 1 -and $relative.EndsWith('.pyc', [System.StringComparison]::Ordinal)) {
            # Compiled Python bytecode the installers delete on reinstall.
            continue
        }
        if ($entry.Type -eq 'link') { [void]$problems.Add("symbolic link inside the item: $relative"); $contentOnly = $false }
        elseif ($entry.Type -eq 'dir') {
            if (-not $knownDirectories.Contains($relative)) { [void]$problems.Add("unknown directory: $relative") }
        }
        elseif ($entry.Type -eq 'file') {
            if ($entry.Links -gt 1) { [void]$problems.Add("hard-linked file: $relative"); $contentOnly = $false }
            elseif (Test-OwnershipKnownHash -Files $known -Relative $relative -Agent $Planner.Agent -Hash $entry.Content) { $matched++ }
            else { [void]$problems.Add("file does not match framework content: $relative") }
        }
        else { [void]$problems.Add("special file: $relative"); $contentOnly = $false }
    }
    if ($problems.Count -eq 0 -and $matched -eq 0) { return (New-OwnershipFinding $id $root $path $kind 'ambiguous' 'directory holds no framework file' -Digest $digest -Spec $Spec) }
    if ($problems.Count -eq 0) { return (New-OwnershipFinding $id $root $path $kind 'removable' -Digest $digest -Spec $Spec -Detail $detail) }
    if ($matched -eq 0 -and $contentOnly) { return (New-OwnershipFinding $id $root $path $kind 'unrelated' 'content matches no framework revision' -Digest $digest -Spec $Spec) }
    $reason = if ($problems.Count -eq 1) { $problems[0] } else { "$($problems[0]) (and $($problems.Count - 1) more)" }
    return (New-OwnershipFinding $id $root $path $kind 'ambiguous' $reason -Digest $digest -Spec $Spec)
}

# ── registrations ──

function Get-OwnershipRegistrationForms {
    param($Planner, [string]$Name)
    $hooksTarget = Join-Path (Join-Path $Planner.Homes.AgentHome 'hooks') 'assistant'
    $forms = @(
        ('$HOME/.' + $Planner.Agent + '/hooks/assistant/' + $Name),
        (Join-Path $hooksTarget $Name),
        ($Planner.Homes.AgentHomeText.TrimEnd([char[]]@('\', '/')) + '/hooks/assistant/' + $Name)
    )
    $normalized = New-Object 'System.Collections.Generic.List[string]'
    foreach ($form in $forms) { [void]$normalized.Add((Normalize-HookPath -PathText $form)) }
    return ,$normalized
}

# True when the normalized token is <checkout>/hooks/scripts/<name> for the running checkout.
function Test-OwnershipOwnCheckoutForm {
    param($Planner, [string]$Token, [string]$Name)
    if ($Planner.Operation -ne 'uninstall' -or [string]::IsNullOrEmpty($Planner.CheckoutDir)) { return $false }
    return ([string]::Equals($Token, (Normalize-HookPath -PathText (Join-Path (Join-Path (Join-Path $Planner.CheckoutDir 'hooks') 'scripts') $Name)), [System.StringComparison]::Ordinal))
}

function Get-OwnershipRegistrationFindings {
    param($Planner, $Snapshot)
    $findings = New-Object System.Collections.ArrayList
    if ($null -eq $Snapshot.Value) { return ,$findings }
    $entries = Get-OwnershipPlannerEntries -Planner $Planner -Kinds @('hook_registration')
    $forms = @{}
    foreach ($entry in $entries) {
        $name = $entry['path'].Substring($entry['path'].LastIndexOf('/') + 1)
        $forms[$entry['id']] = @{ Name = $name; Forms = (Get-OwnershipRegistrationForms -Planner $Planner -Name $name); Entry = $entry }
    }
    foreach ($command in (Get-OwnershipSettingsCommands -Snapshot $Snapshot)) {
        $hook = $command.Hook
        if (-not ($hook -is [System.Collections.IDictionary])) { continue }
        $text = Get-OwnershipValue $hook 'command'
        if ($text -isnot [string]) { continue }
        $token = Normalize-HookPath -PathText (Get-CommandExecutableToken -Command $text)
        if ([string]::IsNullOrEmpty($token)) { continue }
        foreach ($entry in $entries) {
            $candidate = $forms[$entry['id']]
            $itemId = $entry['id'] + '#' + $Snapshot.Relative + '/' + $command.Event + '/' + $command.Index
            $record = New-OwnershipMap
            $record['registration'] = $hook
            $record['settings_file'] = $Snapshot.Relative
            $record['event'] = $command.Event
            $record['index'] = [int]$command.Index
            $digest = Get-OwnershipCanonicalDigest -Value $record
            $detail = @{ Event = $command.Event; Index = $command.Index; Settings = $Snapshot.Relative }
            if ((Test-OwnershipContainsOrdinal $candidate.Forms $token) -or (Test-OwnershipOwnCheckoutForm -Planner $Planner -Token $token -Name $candidate.Name)) {
                [void]$findings.Add((New-OwnershipFinding $itemId $entry['root'] $entry['path'] 'hook_registration' 'removable' -Digest $digest -Spec $entry -Detail $detail))
                break
            }
            if ($token.EndsWith('/hooks/scripts/' + $candidate.Name.ToLowerInvariant(), [System.StringComparison]::Ordinal)) {
                [void]$findings.Add((New-OwnershipFinding $itemId $entry['root'] $entry['path'] 'hook_registration' 'ambiguous' $script:OwnershipCheckoutFormReason -Digest $digest -Spec $entry -Detail $detail))
                break
            }
        }
    }
    return ,$findings
}

function Get-OwnershipReferences {
    param($Snapshot, [string]$Name)
    $needle = ('/hooks/assistant/' + $Name).ToLowerInvariant()
    $found = New-Object 'System.Collections.Generic.List[string]'
    foreach ($command in (Get-OwnershipSettingsCommands -Snapshot $Snapshot)) {
        $text = if ($command.Hook -is [System.Collections.IDictionary]) { Get-OwnershipValue $command.Hook 'command' } else { $null }
        if ($text -is [string] -and $text.Replace('\', '/').ToLowerInvariant().Contains($needle)) {
            [void]$found.Add($command.Event + '/' + $command.Index)
        }
    }
    return ,$found
}

# P-8: entrypoints are offered only when no kept registration references them.
function Set-OwnershipEntrypointRule {
    param($Planner, $Finding, $Snapshot, $RemovableRegistrations)
    if ($null -eq $Finding -or $Finding.Kind -ne 'hook_entrypoint' -or $Finding.Status -ne 'removable') { return $Finding }
    if ($Snapshot.Present -and $null -eq $Snapshot.Value) {
        $Finding.Status = 'ambiguous'
        $Finding.Reason = "$($Snapshot.Relative) could not be read ($($Snapshot.Problem)); registration state unknown"
        return $Finding
    }
    $name = $Finding.Path.Substring($Finding.Path.LastIndexOf('/') + 1)
    $references = Get-OwnershipReferences -Snapshot $Snapshot -Name $name
    if ($references.Count -eq 0) { return $Finding }
    if ($Planner.Operation -eq 'uninstall') {
        $all = $true
        foreach ($reference in $references) { if (-not (Test-OwnershipContainsOrdinal @($RemovableRegistrations) $reference)) { $all = $false } }
        if ($all) { return $Finding }
    }
    $Finding.Status = 'ambiguous'
    $Finding.Reason = "still registered in $($Snapshot.Relative)"
    return $Finding
}

# ── instruction blocks ──

function Get-OwnershipBlockFinding {
    param($Planner, $Spec)
    $root = Get-OwnershipValue $Planner.Roots $Spec['root']
    $found = Find-OwnershipPath -Root $root -Relative $Spec['path']
    if ($found.State -eq 'absent') { return $null }
    $id = $Spec['id']; $kind = $Spec['kind']
    if ($found.State -eq 'problem') { return (New-OwnershipFinding $id $Spec['root'] $Spec['path'] $kind 'ambiguous' $found.Reason -Spec $Spec) }
    if ($found.Info.Type -ne 'file') { return (New-OwnershipFinding $id $Spec['root'] $Spec['path'] $kind 'ambiguous' 'not a regular file' -Spec $Spec) }
    $absolute = Join-OwnershipPath $root $Spec['path']
    try { $read = Read-OwnershipStableFile -LiteralPath $absolute }
    catch { return (New-OwnershipFinding $id $Spec['root'] $Spec['path'] $kind 'ambiguous' "unreadable: $($_.Exception.Message)" -Spec $Spec) }
    if ($read.Links -gt 1) { return (New-OwnershipFinding $id $Spec['root'] $Spec['path'] $kind 'ambiguous' 'hard-linked file; not changed' -Spec $Spec) }
    $markers = $Spec['markers']
    $removal = Get-OwnershipBlockRemoval -Data $read.Data -StartMarker $markers['start'] -EndMarker $markers['end']
    if ($removal.State -eq 'none') { return $null }
    if ($removal.State -eq 'ambiguous') {
        return (New-OwnershipFinding $id $Spec['root'] $Spec['path'] $kind 'ambiguous' 'ambiguous, duplicate or unbalanced markers; file preserved unchanged' -Spec $Spec)
    }
    return (New-OwnershipFinding $id $Spec['root'] $Spec['path'] $kind 'removable' -Digest (Get-OwnershipSha256Hex -Bytes $removal.Removed) -Spec $Spec -Detail @{ Absolute = $absolute })
}

# ── whole plan ──

# Path and block specs for this run: inventory entries plus current items.
function Get-OwnershipPlannerSpecs {
    param($Planner)
    $result = New-Object System.Collections.ArrayList
    foreach ($entry in (Get-OwnershipPlannerEntries -Planner $Planner)) {
        if ($entry['kind'] -eq 'hook_registration') { continue }
        [void]$result.Add($entry)
    }
    foreach ($spec in $Planner.CurrentSpecs) { [void]$result.Add($spec) }
    return ,$result
}

function Get-OwnershipSpecFinding {
    param($Planner, $Spec)
    if ($Spec['kind'] -eq 'instruction_block' -or $Spec['kind'] -eq 'current_instruction_block') { return (Get-OwnershipBlockFinding -Planner $Planner -Spec $Spec) }
    $finding = Get-OwnershipPathFinding -Planner $Planner -Spec $Spec
    if ($null -ne $finding -and (Get-OwnershipValue $Spec 'current') -and $finding.Status -eq 'unrelated') {
        # A current framework path the installer writes: content that matches no
        # framework revision is a modified framework item, kept as ambiguous.
        $finding.Status = 'ambiguous'
        $finding.Reason = 'modified framework item: ' + $finding.Reason
    }
    return $finding
}

function Invoke-OwnershipPlan {
    param($Planner, [string[]]$Kinds = $null)
    $snapshot = Get-OwnershipPlannerSnapshot -Planner $Planner
    $findings = New-Object System.Collections.ArrayList
    $registrations = New-Object System.Collections.ArrayList
    if ($null -eq $Kinds -or (Test-OwnershipContainsOrdinal $Kinds 'hook_registration')) {
        if ($snapshot.Problem -and $snapshot.Present) {
            [void]$findings.Add((New-OwnershipFinding ('settings/' + $snapshot.Relative) 'agent_home' $snapshot.Relative 'hook_registration' 'ambiguous' "$($snapshot.Relative): $($snapshot.Problem); registrations not inspected"))
        }
        $registrations = Get-OwnershipRegistrationFindings -Planner $Planner -Snapshot $snapshot
        foreach ($finding in $registrations) { [void]$findings.Add($finding) }
    }
    $removableRegistrations = New-Object 'System.Collections.Generic.List[string]'
    foreach ($finding in $registrations) {
        if ($finding.Status -eq 'removable') { [void]$removableRegistrations.Add($finding.Detail.Event + '/' + $finding.Detail.Index) }
    }
    foreach ($spec in (Get-OwnershipPlannerSpecs -Planner $Planner)) {
        if ($null -ne $Kinds -and -not (Test-OwnershipContainsOrdinal $Kinds $spec['kind'])) { continue }
        $finding = Get-OwnershipSpecFinding -Planner $Planner -Spec $spec
        if ($null -eq $finding) { continue }
        $finding = Set-OwnershipEntrypointRule -Planner $Planner -Finding $finding -Snapshot $snapshot -RemovableRegistrations $removableRegistrations
        [void]$findings.Add($finding)
    }
    Resolve-OwnershipEmptyDirectories -Findings $findings
    $kept = Remove-OwnershipNestedFindings -Findings $findings
    $sorted = Sort-OwnershipStable -Items $kept -Key { param($finding) $finding.Id }
    return ,$sorted
}

function Resolve-OwnershipEmptyDirectories {
    param($Findings)
    $removablePaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($finding in $Findings) { if ($finding.Status -eq 'removable') { [void]$removablePaths.Add($finding.Root + '|' + $finding.Path) } }
    foreach ($finding in $Findings) {
        if ($finding.Status -ne 'pending') { continue }
        try { $names = Get-OwnershipDirectoryNames -LiteralPath $finding.Detail.Absolute }
        catch { $finding.Status = 'ambiguous'; $finding.Reason = "unreadable: $($_.Exception.Message)"; continue }
        $remaining = @($names | Where-Object { -not $removablePaths.Contains($finding.Root + '|' + $finding.Path + '/' + $_) })
        if ($remaining.Count -gt 0) { $finding.Status = 'ambiguous'; $finding.Reason = 'directory is not empty' }
        else { $finding.Status = 'removable' }
    }
}

function Remove-OwnershipNestedFindings {
    param($Findings)
    $directories = New-Object System.Collections.ArrayList
    foreach ($finding in $Findings) {
        if ($finding.Status -eq 'removable' -and (Test-OwnershipContainsOrdinal @('current_tool_entry', 'current_eval_doc_entry', 'current_skill_directory') $finding.Kind) -and
            $null -ne $finding.Detail.Dirs -and $finding.Detail.Absolute -and [System.IO.Directory]::Exists($finding.Detail.Absolute)) {
            [void]$directories.Add(@($finding.Root, $finding.Path))
        }
    }
    $kept = New-Object System.Collections.ArrayList
    foreach ($finding in $Findings) {
        $nested = $false
        foreach ($directory in $directories) {
            if ($finding.Root -eq $directory[0] -and $finding.Path.StartsWith($directory[1] + '/', [System.StringComparison]::Ordinal)) { $nested = $true }
        }
        if (-not $nested) { [void]$kept.Add($finding) }
    }
    return ,$kept
}

# Prove one manifest item now (not registrations).
function Invoke-OwnershipReprove {
    param($Planner, $Item)
    $spec = $null
    foreach ($candidate in (Get-OwnershipPlannerSpecs -Planner $Planner)) {
        if ($candidate['id'] -ceq $Item['id']) { $spec = $candidate; break }
    }
    if ($null -eq $spec) { return $null }
    $finding = Get-OwnershipSpecFinding -Planner $Planner -Spec $spec
    if ($null -ne $finding -and $finding.Status -eq 'pending') { Resolve-OwnershipEmptyDirectories -Findings @($finding) }
    if ($null -ne $finding -and $finding.Kind -eq 'hook_entrypoint') {
        # Re-prove against the settings file as it is now: any remaining
        # reference keeps the entrypoint, whatever this run removed.
        $snapshot = Get-OwnershipPlannerSnapshot -Planner $Planner
        $finding = Set-OwnershipEntrypointRule -Planner $Planner -Finding $finding -Snapshot $snapshot -RemovableRegistrations @()
    }
    return $finding
}

# ── Manifest ────────────────────────────────────────────────────────────────

function Get-OwnershipManifestDigest {
    param($Manifest)
    $body = New-OwnershipMap
    foreach ($key in @($Manifest.Keys)) {
        if ($key -cne 'manifest_digest') { $body[$key] = $Manifest[$key] }
    }
    return (Get-OwnershipCanonicalDigest -Value $body)
}

function New-OwnershipManifest {
    param($Planner, $Findings)
    $items = New-Object System.Collections.ArrayList
    foreach ($finding in $Findings) { if ($finding.Status -eq 'removable') { [void]$items.Add((Get-OwnershipManifestItem $finding)) } }
    $sortedItems = Sort-OwnershipStable -Items $items -Key { param($item) $item['id'] }
    $manifest = New-OwnershipMap
    $manifest['schema_version'] = $script:OwnershipManifestSchemaVersion
    $manifest['operation'] = $Planner.Operation
    $manifest['agent'] = $Planner.Agent
    $manifest['layout'] = $Planner.Layout
    $manifest['agent_home'] = $Planner.Homes.AgentHome
    $manifest['inventory_digest'] = $Planner.Data.InventoryDigest
    $manifest['items'] = $sortedItems
    $manifest['manifest_digest'] = Get-OwnershipManifestDigest -Manifest $manifest
    return $manifest
}

# Refuse unless the manifest is well formed, bound and for this run.
function Test-OwnershipManifest {
    param($Manifest, $Planner, [string]$ExpectedDigest, [string[]]$AllowedOperations)
    if (-not ($Manifest -is [System.Collections.IDictionary])) { Stop-OwnershipRefusal 'manifest is not a JSON object' }
    Assert-OwnershipVersion -Value (Get-OwnershipValue $Manifest 'schema_version') -Major $script:OwnershipManifestMajor -Label 'manifest'
    $operation = Get-OwnershipValue $Manifest 'operation'
    if ($operation -isnot [string] -or -not (Test-OwnershipContainsOrdinal $script:OwnershipOperations $operation)) { Stop-OwnershipRefusal "manifest operation is unknown: '$operation'" }
    if (-not (Test-OwnershipContainsOrdinal $AllowedOperations $operation)) { Stop-OwnershipRefusal "a manifest with operation $operation cannot be applied here" }
    $recorded = Get-OwnershipValue $Manifest 'manifest_digest'
    if ($recorded -isnot [string] -or $recorded -cnotmatch $script:OwnershipHashPattern) { Stop-OwnershipRefusal 'manifest_digest missing or invalid' }
    $computed = Get-OwnershipManifestDigest -Manifest $Manifest
    if ($computed -cne $recorded) { Stop-OwnershipRefusal 'manifest content does not match its manifest_digest' }
    if ($ExpectedDigest -cne $computed) { Stop-OwnershipRefusal 'the confirmed digest does not match the manifest' }
    $expected = [ordered]@{ agent = $Planner.Agent; layout = $Planner.Layout; agent_home = $Planner.Homes.AgentHome; inventory_digest = $Planner.Data.InventoryDigest }
    foreach ($key in @($expected.Keys)) {
        $value = Get-OwnershipValue $Manifest $key
        if ($value -isnot [string] -or $value -cne $expected[$key]) { Stop-OwnershipRefusal "manifest $key does not match this run" }
    }
    $items = Get-OwnershipValue $Manifest 'items'
    if (-not (Test-OwnershipIsList $items)) { Stop-OwnershipRefusal 'manifest items missing' }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($item in $items) {
        if (-not ($item -is [System.Collections.IDictionary])) { Stop-OwnershipRefusal 'manifest item is not an object' }
        foreach ($field in @('id', 'root', 'path', 'kind', 'digest')) {
            if ((Get-OwnershipValue $item $field) -isnot [string]) { Stop-OwnershipRefusal "manifest item field $field missing" }
        }
        if (-not $seen.Add($item['id'])) { Stop-OwnershipRefusal "duplicate manifest item id: $($item['id'])" }
        if (-not (Test-OwnershipContainsOrdinal $script:OwnershipManifestKinds $item['kind'])) { Stop-OwnershipRefusal "unknown manifest kind: $($item['kind'])" }
        if (-not (Test-OwnershipContainsOrdinal $script:OwnershipRoots $item['root']) -or -not (Test-OwnershipRelativePath $item['path'])) { Stop-OwnershipRefusal "manifest item $($item['id']) has an invalid root or path" }
        if ($item['digest'] -cnotmatch $script:OwnershipHashPattern) { Stop-OwnershipRefusal "manifest item $($item['id']) has an invalid digest" }
        if ($operation -eq 'cleanup' -and (Test-OwnershipContainsOrdinal $script:OwnershipCurrentKinds $item['kind'])) { Stop-OwnershipRefusal "a cleanup manifest cannot list a current framework item: $($item['id'])" }
        if ($operation -eq 'install' -and -not (Test-OwnershipContainsOrdinal $script:OwnershipInstallModeKinds $item['kind'])) { Stop-OwnershipRefusal "an install manifest cannot list $($item['kind'])" }
        if (Test-OwnershipContainsOrdinal $script:OwnershipRetiredKinds $item['kind']) {
            $entryId = $item['id'].Split([char]'#')[0]
            $entry = Get-OwnershipValue $Planner.Data.ById $entryId
            if ($null -eq $entry -or $entry['kind'] -cne $item['kind'] -or $entry['root'] -cne $item['root'] -or $entry['path'] -cne $item['path']) {
                Stop-OwnershipRefusal "manifest item $($item['id']) does not match an inventory entry"
            }
            if (($item['kind'] -eq 'hook_registration') -ne $item['id'].Contains('#')) { Stop-OwnershipRefusal "manifest item $($item['id']) has an invalid registration id" }
        }
    }
    return ,$items
}

# ── Apply ───────────────────────────────────────────────────────────────────

function Test-OwnershipSignaturesUnchanged {
    param($Detail)
    $records = @()
    if ($null -ne $Detail.Files) { $records += @($Detail.Files) }
    if ($null -ne $Detail.Dirs) { $records += @($Detail.Dirs) }
    foreach ($record in $records) {
        $info = Get-OwnershipNodeInfo -LiteralPath $record[0] -WithHandle
        if ($info.Type -eq 'absent') { return $false }
        if ($info.Signature -cne $record[1]) {
            # Directory modification times are not compared; their entries are.
            if ($info.Type -eq 'dir' -and $record[1].StartsWith('dir|', [System.StringComparison]::Ordinal) -and (Test-IsWindowsHost)) {
                $before = $record[1].Split('|'); $after = $info.Signature.Split('|')
                if ($before[1] -eq $after[1]) { continue }
            }
            return $false
        }
    }
    return $true
}

function Remove-OwnershipEntry {
    param([string]$Root, [string]$LiteralPath, [bool]$IsDirectoryLink)
    Assert-OwnershipParentChain -Root $Root -LiteralPath $LiteralPath
    if ($IsDirectoryLink) { [System.IO.Directory]::Delete($LiteralPath, $false) }
    else { [System.IO.File]::Delete($LiteralPath) }
}

# Delete exactly the proven entries, deepest first; never follow links.
function Remove-OwnershipProven {
    param([string]$Root, $Detail)
    $depth = { param($record) [long]($record[0].Split([char[]]@('\', '/')).Count) }
    foreach ($record in (Sort-OwnershipStable -Items @($Detail.Files) -Key $depth -Descending)) { Remove-OwnershipEntry -Root $Root -LiteralPath $record[0] -IsDirectoryLink $record[2] }
    foreach ($record in (Sort-OwnershipStable -Items @($Detail.Dirs) -Key $depth -Descending)) { Assert-OwnershipParentChain -Root $Root -LiteralPath $record[0]; [System.IO.Directory]::Delete($record[0], $false) }
    $info = Get-OwnershipNodeInfo -LiteralPath $Detail.Absolute
    if ($info.Type -eq 'dir') { Assert-OwnershipParentChain -Root $Root -LiteralPath $Detail.Absolute; [System.IO.Directory]::Delete($Detail.Absolute, $false) }
}

# Replace a file with UTF-8 text only if its bytes still equal ExpectedBytes.
# Write-AtomicText keeps the Windows DACL of the replaced file.
function Write-OwnershipRewrite {
    param([string]$LiteralPath, [byte[]]$Data, [byte[]]$ExpectedBytes)
    $info = Get-OwnershipNodeInfo -LiteralPath $LiteralPath -WithHandle
    if ($info.Type -ne 'file' -or $info.Links -ne 1) { throw 'changed type or gained a hard link' }
    $current = (Read-OwnershipStableFile -LiteralPath $LiteralPath).Data
    if (-not (Test-OwnershipBytesEqual $current $ExpectedBytes)) { throw 'changed since it was read' }
    try { $text = $script:OwnershipUtf8Strict.GetString($Data) }
    catch { throw 'is not UTF-8 text; not rewritten' }
    if (-not (Test-OwnershipBytesEqual $script:OwnershipUtf8.GetBytes($text) $Data)) { throw 'cannot be rewritten byte for byte' }
    $current = (Read-OwnershipStableFile -LiteralPath $LiteralPath).Data
    if (-not (Test-OwnershipBytesEqual $current $ExpectedBytes)) { throw 'changed since it was read' }
    Write-AtomicText -LiteralPath $LiteralPath -Content $text
}

function New-OwnershipApplyResult {
    return @{
        Removed = (New-Object System.Collections.ArrayList)
        Skipped = (New-Object System.Collections.ArrayList)
        Unlisted = (New-Object System.Collections.ArrayList)
    }
}

function Get-OwnershipApplyExitCode {
    param($Result)
    if ($Result.Skipped.Count -gt 0) { return $script:OwnershipExitKept }
    return $script:OwnershipExitOk
}

# Remove the listed items with per-item re-proof.
function Invoke-OwnershipApply {
    param($Planner, $Items, [scriptblock]$BeforeDelete = $null)
    $result = New-OwnershipApplyResult
    $listed = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($item in $Items) { [void]$listed.Add($item['id']) }
    foreach ($finding in (Invoke-OwnershipPlan -Planner $Planner)) {
        if ($finding.Status -eq 'removable' -and -not $listed.Contains($finding.Id)) { [void]$result.Unlisted.Add($finding) }
    }
    $registrationItems = @($Items | Where-Object { $_['kind'] -eq 'hook_registration' })
    $blockItems = @($Items | Where-Object { $_['kind'] -eq 'instruction_block' -or $_['kind'] -eq 'current_instruction_block' })
    $emptyItems = @($Items | Where-Object { $_['kind'] -eq 'managed_tool_empty_directory' })
    $entrypointItems = @($Items | Where-Object { $_['kind'] -eq 'hook_entrypoint' })
    $special = @('hook_registration', 'instruction_block', 'current_instruction_block', 'managed_tool_empty_directory', 'hook_entrypoint')
    $pathItems = @($Items | Where-Object { -not (Test-OwnershipContainsOrdinal $special $_['kind']) })
    if ($registrationItems.Count -gt 0) { Invoke-OwnershipApplyRegistrations -Planner $Planner -Items $registrationItems -Result $result -BeforeDelete $BeforeDelete }
    foreach ($item in $blockItems) { Invoke-OwnershipApplyBlock -Planner $Planner -Item $item -Result $result -BeforeDelete $BeforeDelete }
    $ordered = Sort-OwnershipStable -Items $pathItems -Key { param($item) [long]($item['path'].Split('/').Count - 1) } -Descending
    foreach ($item in @(@($ordered) + $entrypointItems + $emptyItems)) {
        Invoke-OwnershipApplyPath -Planner $Planner -Item $item -Result $result -BeforeDelete $BeforeDelete
    }
    return $result
}

function Invoke-OwnershipApplyRegistrations {
    param($Planner, $Items, $Result, [scriptblock]$BeforeDelete)
    $snapshot = Get-OwnershipPlannerSnapshot -Planner $Planner
    if ($null -eq $snapshot.Value) {
        foreach ($item in $Items) { [void]$Result.Skipped.Add(@($item, "$($snapshot.Relative) could not be read")) }
        return
    }
    $current = @{}
    foreach ($finding in (Get-OwnershipRegistrationFindings -Planner $Planner -Snapshot $snapshot)) { $current[$finding.Id] = $finding }
    $failures = New-Object 'System.Collections.Generic.List[string]'
    $targets = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in $Items) {
        if ($null -ne $BeforeDelete) { & $BeforeDelete $item }
        $finding = $null
        foreach ($key in @($current.Keys)) { if ($key -ceq $item['id']) { $finding = $current[$key] } }
        if ($null -eq $finding -or $finding.Status -ne 'removable' -or $finding.Digest -cne $item['digest']) { [void]$failures.Add($item['id']) }
        else { [void]$targets.Add($finding.Detail.Event + '/' + $finding.Detail.Index) }
    }
    if ($failures.Count -gt 0) {
        foreach ($item in $Items) {
            $reason = if (Test-OwnershipContainsOrdinal $failures $item['id']) { 'changed since the report' } else { "another registration in $($snapshot.Relative) changed since the report" }
            [void]$Result.Skipped.Add(@($item, $reason))
        }
        return
    }
    $updated = Remove-OwnershipRegistrations -Value $snapshot.Value -Targets $targets
    try {
        # Strict encoding: text that is not valid Unicode (a lone surrogate) is
        # never rewritten with replacement characters; the file stays unchanged.
        try { $payload = $script:OwnershipUtf8Strict.GetBytes((ConvertTo-OwnershipJson -Value $updated -Indent 2) + "`n") }
        catch { throw 'holds text that cannot be encoded as UTF-8; not rewritten' }
        Write-OwnershipRewrite -LiteralPath $snapshot.Path -Data $payload -ExpectedBytes $snapshot.Raw
    }
    catch {
        if (Test-OwnershipRefusal $_) { throw }
        foreach ($item in $Items) { [void]$Result.Skipped.Add(@($item, "$($snapshot.Relative) $($_.Exception.Message)")) }
        return
    }
    foreach ($item in $Items) { [void]$Result.Removed.Add($item) }
}

function Invoke-OwnershipApplyBlock {
    param($Planner, $Item, $Result, [scriptblock]$BeforeDelete)
    if ($null -ne $BeforeDelete) { & $BeforeDelete $Item }
    $finding = Invoke-OwnershipReprove -Planner $Planner -Item $Item
    if ($null -eq $finding -or $finding.Status -ne 'removable' -or $finding.Digest -cne $Item['digest']) {
        [void]$Result.Skipped.Add(@($Item, 'changed since the report'))
        return
    }
    $absolute = $finding.Detail.Absolute
    try {
        $data = (Read-OwnershipStableFile -LiteralPath $absolute).Data
        $markers = $finding.Spec['markers']
        $removal = Get-OwnershipBlockRemoval -Data $data -StartMarker $markers['start'] -EndMarker $markers['end']
        if ($null -eq $removal.Removed -or (Get-OwnershipSha256Hex -Bytes $removal.Removed) -cne $Item['digest']) { throw 'changed since the report' }
        Write-OwnershipRewrite -LiteralPath $absolute -Data $removal.Remaining -ExpectedBytes $data
    }
    catch {
        if (Test-OwnershipRefusal $_) { throw }
        [void]$Result.Skipped.Add(@($Item, $_.Exception.Message))
        return
    }
    [void]$Result.Removed.Add($Item)
}

function Invoke-OwnershipApplyPath {
    param($Planner, $Item, $Result, [scriptblock]$BeforeDelete)
    if ($null -ne $BeforeDelete) { & $BeforeDelete $Item }
    $finding = Invoke-OwnershipReprove -Planner $Planner -Item $Item
    if ($null -eq $finding) { [void]$Result.Skipped.Add(@($Item, 'no longer present')); return }
    if ($finding.Status -ne 'removable' -or $finding.Digest -cne $Item['digest'] -or $finding.Kind -cne $Item['kind']) {
        $reason = if ($finding.Status -ne 'removable' -and $finding.Reason) { $finding.Reason } else { 'changed since the report' }
        [void]$Result.Skipped.Add(@($Item, $reason))
        return
    }
    $root = $Planner.Roots[$Item['root']]
    try {
        if ($Item['kind'] -eq 'managed_tool_empty_directory') {
            Assert-OwnershipParentChain -Root $root -LiteralPath $finding.Detail.Absolute
            [System.IO.Directory]::Delete($finding.Detail.Absolute, $false)
        }
        else {
            if (-not (Test-OwnershipSignaturesUnchanged -Detail $finding.Detail)) { throw 'changed during removal' }
            if ($finding.Spec['node_type'] -eq 'file') {
                Assert-OwnershipParentChain -Root $root -LiteralPath $finding.Detail.Absolute
                [System.IO.File]::Delete($finding.Detail.Absolute)
            }
            else { Remove-OwnershipProven -Root $root -Detail $finding.Detail }
        }
    }
    catch {
        if (Test-OwnershipRefusal $_) { throw }
        [void]$Result.Skipped.Add(@($Item, "not removed: $($_.Exception.Message)"))
        return
    }
    [void]$Result.Removed.Add($Item)
}

# ── Reporting ───────────────────────────────────────────────────────────────

function Write-OwnershipOut {
    param([string]$Text)
    [Console]::Out.Write($Text)
}

function Get-OwnershipDisplayPath {
    param($Finding)
    if ($Finding.Root -eq 'agent_home') { return $Finding.Path }
    return ('<' + $Finding.Root + '>/' + $Finding.Path)
}

function Get-OwnershipRegistrationSuffix {
    param($Finding)
    if ($Finding.Kind -eq 'hook_registration' -and $Finding.Id.Contains('#')) { return (' (registration ' + $Finding.Id.Split([char]'#', 2)[1] + ')') }
    return ''
}

function Write-OwnershipReport {
    param($Planner, $Findings, $Manifest, [string]$Title)
    $removable = @($Findings | Where-Object { $_.Status -eq 'removable' })
    $ambiguous = @($Findings | Where-Object { $_.Status -eq 'ambiguous' })
    $unrelated = @($Findings | Where-Object { $_.Status -eq 'unrelated' })
    $notes = @($Findings | Where-Object { $_.Status -eq 'info' })
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append("$Title for $($Planner.Agent) ($($Planner.Layout))`n")
    [void]$builder.Append("Agent home: $($Planner.Homes.AgentHome)`n")
    [void]$builder.Append("Removable ($($removable.Count)):`n")
    foreach ($finding in $removable) { [void]$builder.Append("  $($finding.Kind): $(Get-OwnershipDisplayPath $finding)$(Get-OwnershipRegistrationSuffix $finding)`n") }
    [void]$builder.Append("Kept, ambiguous ($($ambiguous.Count)):`n")
    foreach ($finding in $ambiguous) { [void]$builder.Append("  $(Get-OwnershipDisplayPath $finding)$(Get-OwnershipRegistrationSuffix $finding): $($finding.Reason)`n") }
    [void]$builder.Append("Kept, unrelated ($($unrelated.Count)):`n")
    foreach ($finding in $unrelated) { [void]$builder.Append("  $(Get-OwnershipDisplayPath $finding): $($finding.Reason)`n") }
    foreach ($finding in $notes) { [void]$builder.Append("Note: $(Get-OwnershipDisplayPath $finding): $($finding.Reason)`n") }
    [void]$builder.Append("Manifest digest: $($Manifest['manifest_digest'])`n")
    Write-OwnershipOut $builder.ToString()
}

function Write-OwnershipApplyResult {
    param($Result)
    $builder = New-Object System.Text.StringBuilder
    foreach ($item in $Result.Removed) {
        $suffix = if ($item['id'].Contains('#')) { ' (' + $item['id'].Split([char]'#', 2)[1] + ')' } else { '' }
        [void]$builder.Append("removed: $($item['kind']): $($item['path'])$suffix`n")
    }
    foreach ($pair in $Result.Skipped) { [void]$builder.Append("skipped: $($pair[0]['path']): $($pair[1])`n") }
    foreach ($finding in $Result.Unlisted) { [void]$builder.Append("not in the confirmed manifest: $($finding.Path)`n") }
    [void]$builder.Append("Removed $($Result.Removed.Count), skipped $($Result.Skipped.Count).`n")
    Write-OwnershipOut $builder.ToString()
}

# ── Confirmation ────────────────────────────────────────────────────────────

# Interactive means standard input and output are both a terminal.
function Test-OwnershipInteractive {
    try { return (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) }
    catch { return $false }
}

function Read-OwnershipConfirmationLine {
    return [Console]::In.ReadLine()
}

function Confirm-OwnershipByTyping {
    param([string]$Agent, [int]$Count)
    Write-OwnershipOut "Type the agent name ($Agent) to remove $Count item(s), anything else to abort: "
    [Console]::Out.Flush()
    try { $answer = Read-OwnershipConfirmationLine }
    catch { return $false }
    if ($null -eq $answer) { return $false }
    return ($answer.Trim() -ceq $Agent)
}

# ── Command line ────────────────────────────────────────────────────────────

# Parse -Name value / -Flag options exactly (names case-insensitive, as
# PowerShell parameters are); refuse unknown or repeated ones.
function ConvertFrom-OwnershipArguments {
    param([string[]]$Arguments, [hashtable]$Spec)
    $values = @{}
    $index = 0
    $Arguments = @($Arguments)
    while ($index -lt $Arguments.Count) {
        $argument = [string]$Arguments[$index]
        $name = $null
        foreach ($candidate in @($Spec.Keys)) {
            if ([string]::Equals($candidate, $argument, [System.StringComparison]::OrdinalIgnoreCase)) { $name = $candidate }
        }
        if ($null -eq $name) { Stop-OwnershipRefusal "unknown argument: $argument" }
        if ($values.ContainsKey($name)) { Stop-OwnershipRefusal "repeated argument: $name" }
        if ($Spec[$name]) {
            if ($index + 1 -ge $Arguments.Count) { Stop-OwnershipRefusal "missing value for $name" }
            $values[$name] = [string]$Arguments[$index + 1]
            $index += 2
        }
        else {
            $values[$name] = $true
            $index++
        }
    }
    return $values
}

function Get-OwnershipRequiredAgent {
    param([hashtable]$Values)
    $agent = $Values['-Agent']
    if ($agent -isnot [string] -or -not (Test-OwnershipContainsOrdinal $script:OwnershipAgents $agent)) { Stop-OwnershipRefusal '-Agent must be claude, codex or gemini' }
    return $agent
}

function Get-OwnershipManifestOutPath {
    param([string]$Path, $Homes)
    try {
        if (-not [System.IO.Path]::IsPathRooted($Path)) { $Path = Join-Path ((Get-Location).ProviderPath) $Path }
        $Path = Get-FullPath -LiteralPath $Path
    }
    catch { Stop-OwnershipRefusal '-ManifestOut is not a valid path' }
    if ([System.IO.File]::Exists($Path) -or [System.IO.Directory]::Exists($Path) -or (Get-OwnershipNodeInfo -LiteralPath $Path).Type -ne 'absent') {
        Stop-OwnershipRefusal '-ManifestOut must name a file that does not exist yet'
    }
    $parent = [System.IO.Path]::GetDirectoryName($Path)
    if ([string]::IsNullOrEmpty($parent) -or -not [System.IO.Directory]::Exists($parent)) { Stop-OwnershipRefusal '-ManifestOut directory does not exist' }
    foreach ($root in @($Homes.Roots.Values)) {
        if ((Test-OwnershipSameOrInside $parent $root) -or (Test-OwnershipSameOrInside $Path $root)) {
            Stop-OwnershipRefusal '-ManifestOut must be outside the agent home and every inventory root'
        }
    }
    return $Path
}

function Write-OwnershipNewFile {
    param([string]$LiteralPath, [byte[]]$Data)
    $stream = [System.IO.File]::Open($LiteralPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try { $stream.Write($Data, 0, $Data.Length) }
    finally { $stream.Dispose() }
}

# Serialized manifest as json.dumps(manifest, indent=2, sort_keys=True) + "\n".
function ConvertTo-OwnershipManifestText {
    param($Manifest)
    return ((ConvertTo-OwnershipJson -Value $Manifest -SortKeys -EnsureAscii -Indent 2) + "`n")
}
