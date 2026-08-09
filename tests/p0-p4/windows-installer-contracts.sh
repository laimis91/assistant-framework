#!/usr/bin/env bash

if [[ -z "${P0P4_HARNESS_LOADED:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/p0p4-harness.sh"
fi
p0p4_bootstrap_suite "${BASH_SOURCE[0]}"

test_start "native Windows installer exposes the planned safe PowerShell surface"
installer="$FRAMEWORK_DIR/install.ps1"
native_suite="$FRAMEWORK_DIR/tests/windows/installer-contracts.ps1"
failures=()

[[ -f "$installer" ]] || failures+=("missing install.ps1")
[[ ! -e "$FRAMEWORK_DIR/tools/cleanup-memory-graph.ps1" ]] || failures+=("retired Memory Graph PowerShell cleanup remains")
[[ ! -e "$FRAMEWORK_DIR/tools/cleanup-memory-graph.sh" ]] || failures+=("retired Memory Graph Bash cleanup remains")
[[ -f "$native_suite" ]] || failures+=("missing tests/windows/installer-contracts.ps1")

if [[ -f "$installer" ]]; then
    grep -Fq -- '#requires -Version 5.1' "$installer" \
        || failures+=("missing PowerShell 5.1 marker")

    for parameter in Agent Skill Plugin DryRun NoHooks; do
        grep -Eq -- "\\\$$parameter([[:space:]]|[,)=])" "$installer" \
            || failures+=("missing -$parameter parameter")
    done

    p0p4_contains_text "$installer" '.agents' \
        || failures+=("missing native .agents skills destination")
    p0p4_contains_text "$installer" 'skills' \
        || failures+=("missing native .agents skills destination")
    grep -Fq -- 'CODEX_HOME' "$installer" \
        || failures+=("missing CODEX_HOME support")
    grep -Fq -- 'LiteralPath' "$installer" \
        || failures+=("missing literal-path file operations")
    grep -Fq -- 'ConvertTo-Json -Depth 100' "$installer" \
        || failures+=("missing deep JSON preservation")
    grep -Fq -- '[Environment]::OSVersion.Platform' "$installer" \
        || failures+=("security decisions do not use the host platform API")
    if grep -Fq -- 'cleanup-memory-graph' "$installer"; then
        failures+=("installer retains the retired Memory Graph cleanup dependency")
    fi
    if rg -n -e '^function .*(MemoryGraph|GraphSeed)' "$installer" >/tmp/p0p4-windows-retired-installer-functions.out; then
        failures+=("installer retains retired Memory Graph registration, build, or seed functions")
    fi
    grep -Fq -- 'Locked-file preflight failed' "$installer" \
        || failures+=("Codex update files lack a locked-file preflight diagnostic")
    grep -Fq -- 'Partial installation:' "$installer" \
        || failures+=("post-mutation failures lack a partial-install diagnostic")
    if grep -Fq -- '$env:OS' "$installer"; then
        failures+=("security decisions trust mutable OS environment text")
    fi

    if grep -Eqi -- 'Invoke-Expression|Set-ExecutionPolicy|ExecutionPolicy[[:space:]]+Bypass|Start-Process[^[:cntrl:]]*-Verb[[:space:]]+RunAs|New-Item[^[:cntrl:]]*SymbolicLink' "$installer"; then
        failures+=("contains a forbidden PowerShell execution or symlink surface")
    fi
fi

if [[ -f "$native_suite" ]]; then
    grep -Fq -- '#requires -Version 5.1' "$native_suite" \
        || failures+=("native suite lacks the PowerShell 5.1 marker")
    grep -Fq -- 'Parser]::ParseFile' "$native_suite" \
        || failures+=("native suite lacks PowerShell parser validation")
    grep -Fq -- 'USERPROFILE' "$native_suite" \
        || failures+=("native suite does not isolate USERPROFILE")
    grep -Fq -- 'HOME' "$native_suite" \
        || failures+=("native suite does not isolate HOME")
    grep -Fq -- 'CODEX_HOME' "$native_suite" \
        || failures+=("native suite does not exercise CODEX_HOME")
    grep -Fq -- 'junction' "$native_suite" \
        || failures+=("native suite lacks Windows junction containment coverage")
    grep -Fq -- 'HardLink' "$native_suite" \
        || failures+=("native suite lacks Windows hard-link replacement coverage")
    grep -Fq -- 'dry-run is byte-for-byte non-mutating' "$native_suite" \
        || failures+=("native suite lacks dry-run immutability coverage")
    grep -Fq -- 'unbalanced installer markers' "$native_suite" \
        || failures+=("native suite lacks fail-closed marker coverage")
    grep -Fq -- 'fresh install omits the retired Memory Graph launcher and registration' "$native_suite" \
        || failures+=("native suite lacks retired Memory Graph coverage")
    grep -Fq -- 'Codex installation preserves existing legacy Memory Graph state without a CLI' "$native_suite" \
        || failures+=("native suite lacks legacy-state preservation coverage")
    grep -Fq -- 'locked Codex instructions fail preflight before installation changes' "$native_suite" \
        || failures+=("native suite lacks locked Codex update-file preflight coverage")
    grep -Fq -- "Assert-NotContains \$combined 'cleanup-memory-graph' 'Installer retains the retired cleanup-script dependency'" "$native_suite" \
        || failures+=("native suite lacks Assert-NotContains coverage for the retired cleanup-script dependency")
fi

if [[ "${#failures[@]}" -eq 0 ]]; then
    pass
else
    fail "$(IFS='; '; printf '%s' "${failures[*]}")"
fi

test_start "native Windows installation is documented and verified in both PowerShell runtimes"
workflow="$FRAMEWORK_DIR/.github/workflows/windows-installer.yml"
readme="$FRAMEWORK_DIR/README.md"
promotion_failures=()

if [[ ! -f "$workflow" ]]; then
    promotion_failures+=("missing .github/workflows/windows-installer.yml")
else
    grep -Eq -- 'runs-on:[[:space:]]*windows-latest' "$workflow" \
        || promotion_failures+=("Windows workflow does not use windows-latest")
    grep -Eq -- 'shell:[[:space:]]*powershell([[:space:]]|$)' "$workflow" \
        || promotion_failures+=("Windows workflow does not run Windows PowerShell 5.1")
    grep -Eq -- 'shell:[[:space:]]*pwsh([[:space:]]|$)' "$workflow" \
        || promotion_failures+=("Windows workflow does not run PowerShell 7")
    grep -Eq -- 'tests[\\/]windows[\\/]installer-contracts\.ps1' "$workflow" \
        || promotion_failures+=("Windows workflow does not run the native installer suite")
    for windows_job in windows-powershell-51 powershell-7; do
        job_block="$(awk -v header="  ${windows_job}:" '
            $0 == header { in_job = 1; next }
            in_job && /^  [^[:space:]]/ { exit }
            in_job { print }
        ' "$workflow")"
        [[ "$(grep -Ec -- '^[[:space:]]+uses: actions/checkout@v5[[:space:]]*$' <<<"$job_block")" -eq 1 ]] \
            || promotion_failures+=("Windows job $windows_job does not use checkout@v5 exactly once")
        [[ "$(grep -Ec -- '^[[:space:]]+uses: actions/checkout@' <<<"$job_block")" -eq 1 ]] \
            || promotion_failures+=("Windows job $windows_job contains an additional checkout action version")
    done
    grep -Eq -- '^  pull_request:[[:space:]]*$' "$workflow" \
        || promotion_failures+=("Windows workflow does not validate pull requests")
    push_branches="$(awk '
        $0 == "  push:" { in_push = 1; next }
        in_push && /^[^[:space:]]/ { exit }
        in_push && $0 ~ /^    branches:[[:space:]]*$/ { in_branches = 1; next }
        in_branches && $0 ~ /^    [^[:space:]]/ { exit }
        in_branches && $0 ~ /^      -[[:space:]]+/ {
            branch = $0
            sub(/^      -[[:space:]]+/, "", branch)
            sub(/[[:space:]]+$/, "", branch)
            print branch
        }
    ' "$workflow")"
    [[ "$push_branches" == "main" ]] \
        || promotion_failures+=("Windows workflow push validation is not restricted exactly to main")
    grep -Fq -- "- 'install.sh'" "$workflow" \
        || promotion_failures+=("Windows workflow does not react to Unix installer parity changes")
    grep -Fq -- "- 'docs/plugin-architecture.md'" "$workflow" \
        || promotion_failures+=("Windows workflow does not react to plugin profile source changes")
    if grep -Eqi -- 'ExecutionPolicy[[:space:]]+Bypass' "$workflow"; then
        promotion_failures+=("Windows workflow bypasses PowerShell execution policy")
    fi
fi


if [[ ! -f "$readme" ]]; then
    promotion_failures+=("missing README.md")
else
    grep -Eqi -- '^#{1,4}[[:space:]]+.*(native[[:space:]]+)?windows' "$readme" \
        || promotion_failures+=("README lacks a native Windows section")
    grep -Eq -- 'install\.ps1[^[:cntrl:]]*-Agent[[:space:]]+(codex|claude|gemini)([[:space:]]|$)' "$readme" \
        || promotion_failures+=("README lacks a full native Windows install example")
    grep -Eq -- 'install\.ps1[^[:cntrl:]]*-Skill[[:space:]]+[^[:space:]]+' "$readme" \
        || promotion_failures+=("README lacks a single-skill Windows example")
    grep -Eq -- 'install\.ps1[^[:cntrl:]]*-Plugin[[:space:]]+[^[:space:]]+' "$readme" \
        || promotion_failures+=("README lacks a profile Windows example")
    grep -Eq -- 'install\.ps1[^[:cntrl:]]*-DryRun([[:space:]]|$)' "$readme" \
        || promotion_failures+=("README lacks a Windows dry-run example")
    grep -Eqi -- 'reinstall|re-run the (same )?command|run the (same )?command again' "$readme" \
        || promotion_failures+=("README does not explain Windows reinstall behavior")
    grep -Eqi -- 'close Codex App' "$readme" \
        || promotion_failures+=("README does not tell users to close Codex App before installation")
    grep -Eq -- '\.agents[\\/]skills' "$readme" \
        || promotion_failures+=("README omits the native Codex .agents skills destination")
    grep -Fq -- 'CODEX_HOME' "$readme" \
        || promotion_failures+=("README omits CODEX_HOME behavior")
    if rg -n -i -e 'requires?[^[:cntrl:]]*(\.NET|dotnet)[[:space:]]+8' \
        -e '(\.NET|dotnet)[[:space:]]+8[^[:cntrl:]]*(required|prerequisite)' \
        "$readme" >/tmp/p0p4-windows-retired-dotnet-prerequisite.out; then
        promotion_failures+=("README retains the retired Memory Graph .NET 8 prerequisite")
    fi
    grep -Eqi -- 'Windows PowerShell[[:space:]]+5\.1' "$readme" \
        || promotion_failures+=("README omits Windows PowerShell 5.1 support")
    grep -Eqi -- 'PowerShell[[:space:]]+7' "$readme" \
        || promotion_failures+=("README omits PowerShell 7 support")
    grep -Fq -- 'Unblock-File' "$readme" \
        || promotion_failures+=("README omits safe downloaded-script unblocking guidance")
    grep -Eqi -- 'Git Bash|WSL' "$readme" \
        || promotion_failures+=("README omits the Git Bash or WSL boundary")
    grep -Eqi -- 'Bash-only|Bash[[:space:]-]+helpers?|maintenance[^[:cntrl:]]*Bash|eval[^[:cntrl:]]*Bash' "$readme" \
        || promotion_failures+=("README does not identify the remaining Bash-only helpers")
    grep -Eqi -- '^#{1,4}[[:space:]]+.*manual (verification|test)' "$readme" \
        || promotion_failures+=("README lacks a Windows manual verification checklist")
fi

if [[ "${#promotion_failures[@]}" -eq 0 ]]; then
    pass
else
    fail "$(IFS='; '; printf '%s' "${promotion_failures[*]}")"
fi

test_start "Windows workflow does not retain retired Memory Graph SDK setup"
windows_workflow="$FRAMEWORK_DIR/.github/workflows/windows-installer.yml"
if rg -n -i 'setup-dotnet|dotnet-version|\.NET 8 SDK' "$windows_workflow" >/tmp/p0p4-windows-sdk-retirement.out; then
    fail "Windows installer workflow retains unused .NET SDK setup after legacy feature removal"
else
    pass
fi

p0p4_finish_suite "${BASH_SOURCE[0]}"
