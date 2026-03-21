#!/usr/bin/env bash
set -euo pipefail

# Usage: init-worktree.sh <branch_name>
# Creates a git worktree, copies config files, and opens iTerm2 tab if available.

BRANCH_NAME="${1:?Usage: init-worktree.sh <branch_name>}"

PROJ_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE_DIR=".claude/worktrees/${BRANCH_NAME}"
WORKTREE_ABS="${PROJ_ROOT}/${WORKTREE_DIR}"
COPY_LIST="${PROJ_ROOT}/.claude/worktree-copy.txt"

# --- Step 1: Create branch and worktree ---

if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
    echo "ERROR: Branch '${BRANCH_NAME}' already exists." >&2
    exit 1
fi

echo "Creating worktree at ${WORKTREE_DIR} on branch ${BRANCH_NAME}..."
git worktree add "${WORKTREE_DIR}" -b "${BRANCH_NAME}"

# --- Step 2: Copy config files ---

COPIED_FILES=()

if [[ -f "${COPY_LIST}" ]]; then
    while IFS= read -r entry || [[ -n "${entry}" ]]; do
        # Skip empty lines and comments
        entry="$(echo "${entry}" | xargs)"
        [[ -z "${entry}" || "${entry}" == \#* ]] && continue

        SRC="${PROJ_ROOT}/${entry}"
        DST="${WORKTREE_ABS}/${entry}"

        if [[ ! -e "${SRC}" ]]; then
            echo "WARN: ${entry} not found in source repo, skipping."
            continue
        fi

        mkdir -p "$(dirname "${DST}")"

        if [[ -d "${SRC}" ]]; then
            cp -r "${SRC}" "${DST}"
        else
            cp "${SRC}" "${DST}"
        fi

        COPIED_FILES+=("${entry}")
        echo "Copied: ${entry}"
    done < "${COPY_LIST}"
else
    echo "No .claude/worktree-copy.txt found, skipping file copy."
fi

# --- Step 3: Open in terminal ---

if [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then
    echo "Opening new iTerm2 tab..."

    osascript <<APPLESCRIPT
tell application "iTerm"
    tell current window
        set newTab to (create tab with default profile)

        tell current session of newTab
            set name to "${BRANCH_NAME}"
            write text "cd '${WORKTREE_ABS}' && claude"

            set bottomSession to (split horizontally with default profile)
            tell bottomSession
                write text "cd '${WORKTREE_ABS}'"
            end tell
        end tell
    end tell
end tell
APPLESCRIPT

    echo ""
    echo "=== Summary ==="
    echo "Branch:   ${BRANCH_NAME}"
    echo "Worktree: ${WORKTREE_ABS}"
    if [[ ${#COPIED_FILES[@]} -gt 0 ]]; then
        echo "Copied:   ${COPIED_FILES[*]}"
    fi
    echo "iTerm2:   New tab opened (Claude top, terminal bottom)"
else
    echo ""
    echo "=== Summary ==="
    echo "Branch:   ${BRANCH_NAME}"
    echo "Worktree: ${WORKTREE_ABS}"
    if [[ ${#COPIED_FILES[@]} -gt 0 ]]; then
        echo "Copied:   ${COPIED_FILES[*]}"
    fi
    echo ""
    echo "To start working:"
    echo "  cd ${WORKTREE_ABS}"
fi
