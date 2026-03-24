# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

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
