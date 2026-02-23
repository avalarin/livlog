#!/bin/bash
# Stop hook: if files were modified since last review, trigger code-reviewer subagent.
# Returns exit code 2 to block stopping and feed the review instruction to Claude.

INPUT=$(cat)

# Prevent infinite loops — if a Stop hook is already active, allow stopping.
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active')" = "true" ]; then
  exit 0
fi

TRACKING_FILE="$CLAUDE_PROJECT_DIR/.claude/modified-files-pending-review.txt"

if [ -s "$TRACKING_FILE" ]; then
  FILES=$(cat "$TRACKING_FILE")
  # Clear the tracking file so the next session starts clean
  > "$TRACKING_FILE"
  echo "Code changes detected in this session. Use the code-reviewer subagent to review the following modified files: $FILES" >&2
  exit 2
fi

exit 0
