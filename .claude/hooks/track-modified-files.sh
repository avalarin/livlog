#!/bin/bash
# PostToolUse hook: tracks every file modified by Edit/Write/MultiEdit.
# Appends the file path to a tracking file for the Stop hook to consume.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -n "$FILE_PATH" ]; then
  # Skip .claude directory — agent configs, hooks, and memory are not reviewed
  if [[ "$FILE_PATH" == *"/.claude/"* ]]; then
    exit 0
  fi

  TRACKING_FILE="$CLAUDE_PROJECT_DIR/.claude/modified-files-pending-review.txt"
  # Append only if not already listed
  if ! grep -qxF "$FILE_PATH" "$TRACKING_FILE" 2>/dev/null; then
    echo "$FILE_PATH" >> "$TRACKING_FILE"
  fi
fi

exit 0
