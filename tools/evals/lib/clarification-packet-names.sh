clarification_task_packet_basename() {
    local fixture_file="$1"
    local skill_name="$2"
    local case_id="$3"

    jq -r --arg id "$case_id" --arg skill "$skill_name" '
      def is_prompt_only($case):
        ($skill == "assistant-clarify") or ((($case.category // "") | ascii_downcase) | contains("clarification"));
      def task_name($number):
        "task-\(if $number < 10 then "0\($number)" else "\($number)" end)";
      def next_available($number; $case_ids; $assigned):
        task_name($number) as $candidate
        | if (($case_ids | index($candidate | ascii_downcase)) == null
              and ($assigned | index($candidate | ascii_downcase)) == null) then $number
          else next_available($number + 1; $case_ids; $assigned) end;
      .cases as $cases
      | [$cases[].id | ascii_downcase] as $case_ids
      | reduce $cases[] as $case
          ({next_number: 1, assigned: [], match: null};
           if is_prompt_only($case) then
             next_available(.next_number; $case_ids; .assigned) as $number
             | task_name($number) as $alias
             | .next_number = ($number + 1)
             | .assigned += [$alias | ascii_downcase]
             | if $case.id == $id then .match = $alias else . end
           else . end)
      | .match // ""
    ' "$fixture_file"
}

is_clarification_case() {
    local skill_name="$1"
    local category="$2"
    local normalized_category

    normalized_category="$(printf '%s' "$category" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
    [[ "$skill_name" == "assistant-clarify" || "$normalized_category" == *clarification* ]]
}
