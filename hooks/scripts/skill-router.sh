#!/usr/bin/env bash
# skill-router.sh — Data-driven skill routing hook.
#
# Event: UserPromptSubmit
#
# Scans installed skill SKILL.md files for `triggers:` frontmatter,
# matches the user's prompt against each trigger pattern (sorted by priority),
# and injects a reminder to invoke the matching skill.
#
# Adding a new skill? Just add a `triggers:` block to its SKILL.md frontmatter:
#
#   triggers:
#     - pattern: "keyword1|keyword2|multi word phrase"
#       priority: 80          # higher = checked first (default: 50)
#       min_words: 5          # optional: skip short prompts
#       reminder: "Custom reminder text"
#
# No changes to this script needed.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')
[[ -n "$PROMPT" ]] || exit 0

# Detect the hook event name from input (defaults to UserPromptSubmit for Claude)
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "UserPromptSubmit"')

prompt_lower=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')
word_count=$(echo "$PROMPT" | wc -w | tr -d ' ')

# Determine agent home (Claude, Gemini, or Codex)
AGENT_HOME="$HOME/.claude"
if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.gemini"
elif [[ -n "${CODEX_PROJECT_DIR:-}" ]]; then
    AGENT_HOME="$HOME/.codex"
fi

SKILLS_DIR="$AGENT_HOME/skills"
[[ -d "$SKILLS_DIR" ]] || exit 0

# Collect all triggers from all skills: priority|pattern|min_words|reminder|skill_name
triggers=()

for skill_dir in "$SKILLS_DIR"/*/; do
    skill_md="$skill_dir/SKILL.md"
    [[ -f "$skill_md" ]] || continue

    skill_name=$(basename "$skill_dir")

    # Parse YAML frontmatter for triggers block
    in_frontmatter=false
    in_triggers=false
    current_pattern=""
    current_priority="50"
    current_min_words="0"
    current_reminder=""

    flush_trigger() {
        if [[ -n "$current_pattern" ]]; then
            local r="$current_reminder"
            if [[ -z "$r" ]]; then
                r="This request matches $skill_name. You MUST invoke the Skill tool with skill='$skill_name' BEFORE proceeding."
            fi
            # Use tab as delimiter (patterns contain | which would collide)
            triggers+=("${current_priority}	${current_pattern}	${current_min_words}	${r}	${skill_name}")
        fi
        current_pattern=""
        current_priority="50"
        current_min_words="0"
        current_reminder=""
    }

    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            if $in_frontmatter; then
                flush_trigger
                break
            else
                in_frontmatter=true
                continue
            fi
        fi
        $in_frontmatter || continue

        # Detect triggers: block start
        if [[ "$line" == "triggers:" ]]; then
            in_triggers=true
            continue
        fi

        # Exit triggers block on non-indented line
        if $in_triggers && [[ "$line" =~ ^[a-zA-Z] ]]; then
            flush_trigger
            in_triggers=false
            continue
        fi

        $in_triggers || continue

        # New trigger entry (- pattern: "...")
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*pattern:[[:space:]]*\"(.+)\"$ ]]; then
            flush_trigger
            current_pattern="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*priority:[[:space:]]*([0-9]+) ]]; then
            current_priority="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*min_words:[[:space:]]*([0-9]+) ]]; then
            current_min_words="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*reminder:[[:space:]]*\"(.+)\"$ ]]; then
            current_reminder="${BASH_REMATCH[1]}"
        fi
    done < "$skill_md"
done

# No triggers found — nothing to route
[[ ${#triggers[@]} -gt 0 ]] || exit 0

# Sort by priority descending (first tab-delimited field)
# Sort by priority descending; use while-read to avoid glob expansion (safe on bash 3.2+)
sorted=()
while IFS= read -r line; do
    sorted+=("$line")
done < <(printf '%s\n' "${triggers[@]}" | sort -t$'\t' -k1 -rn)

# Match prompt against sorted triggers (collect ALL matches, deduplicate by skill)
matched_skills=()
matched_reminders=()

for entry in "${sorted[@]}"; do
    IFS=$'\t' read -r priority pattern min_words reminder skill_name <<< "$entry"

    # Check min_words gate
    if [[ "$min_words" -gt 0 && "$word_count" -lt "$min_words" ]]; then
        continue
    fi

    # Skip if this skill already matched (higher-priority trigger won)
    already_matched=false
    if [[ ${#matched_skills[@]} -gt 0 ]]; then
        for s in "${matched_skills[@]}"; do
            [[ "$s" == "$skill_name" ]] && { already_matched=true; break; }
        done
    fi
    $already_matched && continue

    # Match pattern against prompt (word boundary matching)
    # Note: patterns come from locally-installed SKILL.md files, not user input.
    # Guard against malformed regex by suppressing grep errors.
    if echo "$prompt_lower" | grep -qE "\b($pattern)\b" 2>/dev/null; then
        matched_skills+=("$skill_name")

        # Check for input contract and extract required field names
        input_contract="$SKILLS_DIR/$skill_name/contracts/input.yaml"
        if [[ -f "$input_contract" ]]; then
            # Extract required field names: find name: lines where required: true follows
            required_fields=()
            prev_name=""
            while IFS= read -r cline; do
                if [[ "$cline" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.+)$ ]]; then
                    prev_name="${BASH_REMATCH[1]}"
                elif [[ "$cline" =~ ^[[:space:]]*name:[[:space:]]*(.+)$ ]]; then
                    prev_name="${BASH_REMATCH[1]}"
                elif [[ "$cline" =~ ^[[:space:]]*required:[[:space:]]*true && -n "$prev_name" ]]; then
                    required_fields+=("$prev_name")
                    prev_name=""
                elif [[ "$cline" =~ ^[[:space:]]*required:[[:space:]] ]]; then
                    prev_name=""
                fi
            done < "$input_contract"

            if [[ ${#required_fields[@]} -gt 0 ]]; then
                fields_list=$(IFS=', '; echo "${required_fields[*]}")
                reminder="$reminder Required inputs for this skill: [$fields_list]"
            fi
        fi

        matched_reminders+=("$reminder")
    fi
done

# Output combined reminders if any matched
if [[ ${#matched_reminders[@]} -gt 0 ]]; then
    combined=""
    for i in "${!matched_reminders[@]}"; do
        if [[ -n "$combined" ]]; then
            combined+=$'\n\n'
        fi
        combined+="SKILL MATCH ($((i+1))/${#matched_reminders[@]}): ${matched_reminders[$i]}"
    done
    jq -cn \
        --arg ctx "$combined" \
        --arg event "$HOOK_EVENT" \
        '{hookSpecificOutput: {hookEventName: $event, additionalContext: $ctx}}'
fi

exit 0
