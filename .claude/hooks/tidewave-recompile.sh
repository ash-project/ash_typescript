#!/bin/bash
INPUT=$(cat)
CODE=$(echo "$INPUT" | jq -r '.tool_input.code')

jq -n --arg code "recompile()
$CODE" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: { code: $code }
  }
}'
