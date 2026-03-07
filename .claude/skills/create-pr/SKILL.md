---
name: create-pr
description: Push current branch and create a GitHub pull request. Checks for uncommitted changes, pushes to origin, monitors CI (GitHub Actions), and auto-fixes failures with user approval. Use this skill whenever the user wants to push code, create a PR, open a pull request, submit changes for review, or says things like "push and create PR", "open a PR", "submit my changes". Also trigger when the user says /create-pr.
---

# Create PR

Push the current branch to GitHub and create a pull request, monitoring CI and fixing issues along the way.

## Prerequisites

This skill requires the `gh` CLI (GitHub CLI). If it's not installed, tell the user to install it:
```
brew install gh
gh auth login
```

## Workflow

### Step 1: Pre-flight checks

Run these checks before doing anything:

1. **Verify `gh` is available** — run `which gh`. If missing, stop and tell the user to install it.
2. **Check for uncommitted changes** — run `git status --porcelain`. If there are uncommitted or untracked files, stop and tell the user what's pending. Don't proceed until the working tree is clean.
3. **Get current branch** — run `git branch --show-current`. If on `main`, just push and skip PR creation. Tell the user: "You're on main, pushed directly. No PR created."

### Step 2: Push to origin

```bash
git push -u origin HEAD
```

If push fails (e.g., no upstream, rejected), diagnose and report to the user.

### Step 3: Monitor CI

After pushing, check if there are GitHub Actions workflows running for this branch:

```bash
gh run list --branch $(git branch --show-current) --limit 5
```

Wait for the most recent run to complete. Poll with:

```bash
gh run watch <run-id> --exit-status
```

Use `--exit-status` so the command exits with non-zero if the run fails. Set a reasonable timeout (10 minutes).

If no CI workflows are found (e.g., only backend files changed and the push didn't trigger anything), skip to Step 5.

### Step 4: Handle CI failures

If CI fails:

1. **Get failure details**:
   ```bash
   gh run view <run-id> --log-failed
   ```

2. **Ask the user for permission** before fixing anything. Use AskUserQuestion to show them:
   - Which checks failed
   - A brief summary of the errors
   - "Should I try to fix these issues?"

3. If the user agrees, fix the issues:
   - Analyze the error logs
   - Make the necessary code changes (keep fixes minimal and focused)
   - Run local verification if possible (lint, build, test — see CLAUDE.md for commands)

4. **Ask the user for permission to commit and push** using AskUserQuestion:
   - Show what files changed and a brief description of the fix
   - "Can I commit and push these fixes?"

5. If approved, commit the fix and push:
   ```bash
   git add <specific-files>
   git commit -m "fix: <description of what was fixed>"
   git push
   ```

6. Go back to Step 3 to monitor the new CI run.

If the user declines the fix, stop and report the current state.

### Step 5: Create Pull Request

Once CI passes (or was skipped), create the PR:

1. Check if a PR already exists for this branch:
   ```bash
   gh pr view --json url 2>/dev/null
   ```
   If a PR already exists, skip creation and just report the existing PR URL.

2. Analyze all commits on this branch (compared to main) to write a good PR title and description:
   ```bash
   git log main..HEAD --oneline
   git diff main...HEAD --stat
   ```

3. Create the PR:
   ```bash
   gh pr create --title "<title>" --body "<body>"
   ```

   Use a HEREDOC for the body to preserve formatting. Include:
   - Summary of changes (2-3 bullet points)
   - Test plan if applicable

### Step 6: Summary

Present the user with a final summary:

- **PR link** (clickable)
- **CI status**: passed / passed after fixes / skipped
- **Issues fixed** (if any): brief list of what went wrong and how it was resolved
- **Commits included**: list of commits in the PR

Keep the summary concise and scannable.

## Important rules

- Never force-push. If a normal push is rejected, ask the user what to do.
- Always ask for user permission before making any code changes or commits (via AskUserQuestion). The user should stay in control.
- If CI keeps failing after 3 fix attempts, stop and tell the user — don't loop forever.
- When fixing CI issues, follow the project's code standards from CLAUDE.md.
