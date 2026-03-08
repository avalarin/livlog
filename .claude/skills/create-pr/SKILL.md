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
3. **Get current branch** — run `git branch --show-current`. Note whether you're on `main` or a feature branch. If on `main`, you will skip merge conflict check and PR creation (Steps 5-6) but you MUST still run Steps 2-4 (push, monitor CI, handle failures).

### Step 2: Push to origin

```bash
git push -u origin HEAD
```

If push fails (e.g., no upstream, rejected), diagnose and report to the user.

### Step 3: Monitor CI

After pushing, check if there are GitHub Actions workflows running for this branch.

**IMPORTANT**: CI runs take a few seconds to appear after a push. You MUST wait and retry before concluding there are no runs. Use the following approach:

```bash
# Wait 5 seconds for GitHub to register the run, then check
sleep 5 && gh run list --branch $(git branch --show-current) --limit 5 --json databaseId,name,status,conclusion,event,createdAt
```

If the list is empty, wait another 10 seconds and retry **once more**:

```bash
sleep 10 && gh run list --branch $(git branch --show-current) --limit 5 --json databaseId,name,status,conclusion,event,createdAt
```

Only if the list is still empty after the second attempt, you may skip CI monitoring and proceed to Step 5.

Once you see a run, wait for it to complete. Poll with:

```bash
gh run watch <run-id> --exit-status
```

Use `--exit-status` so the command exits with non-zero if the run fails. Set a reasonable timeout (10 minutes).

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

### Step 5: Check for merge conflicts

If on `main`, skip this step and go to Step 6.

Check if the branch has merge conflicts with the base branch (`main`):

```bash
git fetch origin main && git merge-tree $(git merge-base HEAD origin/main) origin/main HEAD
```

Or attempt a dry-run merge:

```bash
git fetch origin main
git merge --no-commit --no-ff origin/main
```

If there are **no conflicts**, abort the merge and proceed:

```bash
git merge --abort
```

If there **are conflicts**:

1. Abort the test merge:
   ```bash
   git merge --abort
   ```

2. **Ask the user for permission** before resolving. Use AskUserQuestion to show them:
   - Which files have conflicts
   - A brief summary of the conflicting changes
   - "Should I try to resolve these merge conflicts?"

3. If the user agrees, use a sub-agent (software-engineer) to resolve the conflicts:
   - Run `git merge origin/main` to start the real merge
   - Analyze each conflicted file and resolve appropriately
   - Run local verification (lint, build, test — see CLAUDE.md for commands)

4. **Ask the user for permission to commit and push** using AskUserQuestion:
   - Show which files were resolved and how
   - "Can I commit the merge and push?"

5. If approved, complete the merge and push:
   ```bash
   git add <resolved-files>
   git commit -m "merge: resolve conflicts with main"
   git push
   ```

6. Go back to Step 3 to monitor the new CI run.

If the user declines, abort the merge (`git merge --abort`) and report the current state.

### Step 6: Create Pull Request

If on `main`, skip this step — tell the user: "Pushed directly to main. No PR created." and go to Step 7.

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

### Step 7: Summary

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
