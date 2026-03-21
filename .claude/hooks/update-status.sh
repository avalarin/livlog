#!/bin/bash
# Hook: update-status.sh
# Events: PostToolUse, Stop, Notification
# Writes .claude/status.json in the current worktree and
# syncs to .claude/all-statuses.json in the main worktree.

set -euo pipefail

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

STATUS_FILE="${CLAUDE_PROJECT_DIR}/.claude/status.json"

# --- Determine status, phase, and message based on event ---

determine_phase_and_message() {
  local tool_name="$1"
  local tool_input="$2"
  local phase message

  case "$tool_name" in
    Edit|MultiEdit|Write)
      phase="coding"
      local file_path
      file_path=$(echo "$tool_input" | jq -r '.file_path // empty')
      if [ -n "$file_path" ]; then
        message="Editing ${file_path##*/}"
      else
        message="Editing files"
      fi
      ;;
    Bash)
      local command
      command=$(echo "$tool_input" | jq -r '.command // empty')
      if echo "$command" | grep -qiE '(test|xcodebuild test)'; then
        phase="testing"
        message="Running tests"
      elif echo "$command" | grep -qiE '(build|xcodebuild build|go build|compile)'; then
        phase="testing"
        message="Building project"
      elif echo "$command" | grep -qiE '(lint|swiftlint|golangci)'; then
        phase="reviewing"
        message="Running linter"
      else
        # Keep previous phase for generic bash commands
        phase=""
        # Truncate command for display
        local short_cmd
        short_cmd=$(echo "$command" | head -1 | cut -c1-60)
        message="Running: ${short_cmd}"
      fi
      ;;
    TaskCreate|TaskUpdate|TaskList)
      phase="planning"
      local subject
      subject=$(echo "$tool_input" | jq -r '.subject // empty')
      if [ -n "$subject" ]; then
        message="Task: ${subject}"
      else
        message="Managing tasks"
      fi
      ;;
    AskUserQuestion)
      phase="planning"
      message="Asking user question"
      ;;
    Agent)
      local agent_type
      agent_type=$(echo "$tool_input" | jq -r '.subagent_type // empty')
      case "$agent_type" in
        code-reviewer)
          phase="reviewing"
          message="Running code review"
          ;;
        software-engineer)
          phase="coding"
          local desc
          desc=$(echo "$tool_input" | jq -r '.description // empty')
          message="Engineering: ${desc:-working}"
          ;;
        system-analyst|Explore|Plan)
          phase="planning"
          local desc
          desc=$(echo "$tool_input" | jq -r '.description // empty')
          message="Analyzing: ${desc:-researching}"
          ;;
        *)
          phase=""
          message="Running agent: ${agent_type:-unknown}"
          ;;
      esac
      ;;
    Grep|Glob|Read)
      phase=""
      message="Reading codebase"
      ;;
    *)
      phase=""
      message="Working: ${tool_name}"
      ;;
  esac

  echo "${phase}|${message}"
}

# --- Build the status object ---

case "$EVENT" in
  PostToolUse)
    tool_name=$(echo "$INPUT" | jq -r '.tool_name // empty')
    tool_input=$(echo "$INPUT" | jq -c '.tool_input // {}')

    result=$(determine_phase_and_message "$tool_name" "$tool_input")
    new_phase="${result%%|*}"
    new_message="${result#*|}"

    # Read previous phase if new one is empty (keep previous)
    if [ -z "$new_phase" ] && [ -f "$STATUS_FILE" ]; then
      new_phase=$(jq -r '.phase // "coding"' "$STATUS_FILE")
    fi
    new_phase="${new_phase:-coding}"

    jq -n \
      --arg status "working" \
      --arg phase "$new_phase" \
      --arg message "$new_message" \
      --arg timestamp "$TIMESTAMP" \
      --arg branch "$(git -C "$CLAUDE_PROJECT_DIR" branch --show-current 2>/dev/null || echo unknown)" \
      '{status: $status, phase: $phase, message: $message, branch: $branch, updated_at: $timestamp}' \
      > "$STATUS_FILE"
    ;;

  Stop)
    jq -n \
      --arg status "waiting" \
      --arg phase "idle" \
      --arg message "Finished" \
      --arg timestamp "$TIMESTAMP" \
      --arg branch "$(git -C "$CLAUDE_PROJECT_DIR" branch --show-current 2>/dev/null || echo unknown)" \
      '{status: $status, phase: $phase, message: $message, branch: $branch, updated_at: $timestamp}' \
      > "$STATUS_FILE"
    ;;

  Notification)
    # Preserve current phase from existing status
    current_phase="planning"
    if [ -f "$STATUS_FILE" ]; then
      current_phase=$(jq -r '.phase // "planning"' "$STATUS_FILE")
    fi

    jq -n \
      --arg status "waiting" \
      --arg phase "$current_phase" \
      --arg message "Waiting for user input" \
      --arg timestamp "$TIMESTAMP" \
      --arg branch "$(git -C "$CLAUDE_PROJECT_DIR" branch --show-current 2>/dev/null || echo unknown)" \
      '{status: $status, phase: $phase, message: $message, branch: $branch, updated_at: $timestamp}' \
      > "$STATUS_FILE"
    ;;

  *)
    # Unknown event, ignore
    exit 0
    ;;
esac

# --- Update iTerm2 tab title ---

if [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
  PHASE=$(jq -r '.phase' "$STATUS_FILE")
  BRANCH=$(jq -r '.branch' "$STATUS_FILE")
  case "$PHASE" in
    coding)    EMOJI="🔨" ;;
    testing)   EMOJI="🧪" ;;
    reviewing) EMOJI="🔍" ;;
    planning)  EMOJI="📋" ;;
    idle)      EMOJI="💤" ;;
    *)         EMOJI="⚙️" ;;
  esac
  printf "\033]1;%s · %s\007" "$EMOJI" "$BRANCH" > /dev/tty 2>/dev/null || true
fi

# --- Sync to all-statuses.json in the main worktree ---

MAIN_WORKTREE=$(git -C "$CLAUDE_PROJECT_DIR" worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')

if [ -n "$MAIN_WORKTREE" ]; then
  ALL_STATUSES_FILE="${MAIN_WORKTREE}/.claude/all-statuses.json"
  WORKTREE_NAME=$(basename "$CLAUDE_PROJECT_DIR")
  CURRENT_STATUS=$(cat "$STATUS_FILE")

  # Create or update all-statuses.json atomically
  if [ -f "$ALL_STATUSES_FILE" ]; then
    jq --arg key "$WORKTREE_NAME" --argjson val "$CURRENT_STATUS" \
      '.[$key] = $val' "$ALL_STATUSES_FILE" > "${ALL_STATUSES_FILE}.tmp" \
      && mv "${ALL_STATUSES_FILE}.tmp" "$ALL_STATUSES_FILE"
  else
    mkdir -p "$(dirname "$ALL_STATUSES_FILE")"
    jq -n --arg key "$WORKTREE_NAME" --argjson val "$CURRENT_STATUS" \
      '{($key): $val}' > "$ALL_STATUSES_FILE"
  fi
fi

exit 0
