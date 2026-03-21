---
name: worktree-init
description: Create a new git worktree with its own branch for isolated feature work. Sets up the worktree in .claude/worktrees/, copies required config files, and opens a new iTerm2 tab (with split panes for Claude + terminal) if available. Use this skill when the user wants to start working on a new feature in isolation, create a worktree, branch off for parallel work, or says things like "new worktree", "start a new branch for X", "I want to work on X in a separate worktree", or /worktree-init.
---

# Worktree Init

Create a new git branch and worktree for isolated feature development, copy required config files, and optionally open a new iTerm2 tab with Claude ready to go.

## Workflow

### Step 1: Determine the branch name

Ask the user what they want to work on (if they haven't already described it). Use the AskUserQuestion tool.

**If the user provides a description:**
- Generate a short, descriptive branch name in `snake-case` English
- Keep it under 4 words, e.g. `add-collection-sharing`, `fix-auth-token-refresh`
- Translate from any language to English

**If the user says they don't know or skips the description:**
- Generate a random two-word name combining an adjective + animal, e.g. `silver-falcon`, `crystal-owl`, `amber-fox`, `velvet-crane`
- Use whimsical/fairy-tale style adjectives: `golden`, `silver`, `crystal`, `velvet`, `amber`, `misty`, `frost`, `ember`, `shadow`, `lunar`
- Use bird/animal nouns: `falcon`, `owl`, `fox`, `crane`, `wolf`, `hawk`, `raven`, `phoenix`, `lynx`, `heron`

The branch name and worktree directory name should be the same.

### Step 2: Run the init script

Once you have the branch name, run the bundled script:

```bash
bash <skill-path>/scripts/init-worktree.sh <branch_name>
```

The script handles everything:
1. Creates the git worktree and branch at `.claude/worktrees/<branch_name>`
2. Copies files listed in `.claude/worktree-copy.txt` (one path per line, comments with `#` supported)
3. If iTerm2 — opens a new tab named after the branch, split horizontally: Claude on top, terminal on bottom
4. If not iTerm2 — prints a `cd` command for the user

If the script exits with an error (e.g. branch already exists), tell the user and ask if they want to pick a different name.

### Step 3: Report the result

Relay the script output to the user. The script already prints a summary, so just pass it through.

## Important notes

- Always run the script from the project root directory
- The `.claude/worktrees/` directory has a `.gitignore` that ignores everything — worktree contents won't be committed
- The copy list file `.claude/worktree-copy.txt` can be edited by the user to add more paths; if it doesn't exist, no files are copied
