---
description: Stage and commit the working tree as well-formed, logically-grouped commits following the repo's conventions. For ad-hoc changes outside the slice loop (/build commits each slice itself).
---

# /commit — smart commit

Stage and commit the working tree as one or more **well-formed, logically-grouped** commits that follow the repo's conventions.

> In the slice flow, `/build` already commits each slice as it passes the dual gate. Use `/commit` for **ad-hoc** changes outside that loop — a quick fix, a doc change, leftover work — or wherever you're not driving slices.

## Argument: $ARGUMENTS
Optional guidance for the commit message(s).

## Step 1 — Analyze
- `git status`, `git diff`, `git diff --cached`.
- **Derive the ticket id from the branch name** (e.g. `TV1-1594-delete-items` → `TV1-1594`), or from `.work/slices.yaml` `ticket:` if present.
- Learn the repo's conventions: `git log --oneline -15` for the message style (type/scope, prefix, trailer/sign-off), and `${CLAUDE_PROJECT_DIR}/.claude/rules` for any commit/grouping rules.

## Step 2 — Group into logical commits
Split into as many commits as needed — **each commit one complete, self-contained unit; never bundle unrelated concerns.** Group by logical concern, following the repo's conventions (a project may group by layer/module — read its rules). Unrelated modules in the same concern → separate commits. Order by dependency (foundational first).

**Never stage:** `.env` / `.env.*`, `*credentials*`, `*secret*`, `*.log`, `node_modules/`, build output.

## Step 3 — Messages
Follow the repo's observed convention; default to `type(scope): summary` (conventional commits):
- **type** — feat / fix / docs / test / refactor / chore (per repo norm).
- **scope** — the module or area affected.
- **summary** — imperative, lowercase, no trailing period; favor *why* over *what*.
- Reference the ticket (from the branch) in the body if the repo does so, and include the repo's trailer/sign-off convention (detect it — don't hardcode).

Use `$ARGUMENTS` as guidance if provided.

## Step 4 — Present & confirm
Show the full plan (N commits: message + files for each). Ask: **proceed / edit / cancel.** On "edit", adjust groupings or messages, then proceed.

## Step 5 — Execute in order
For each group in dependency order: stage its specific files, create the commit (HEREDOC for proper formatting), and `git log --oneline -1` to confirm before the next. After all: `git log --oneline -N` for the full set.

## Working-tree safety
Stage **explicit paths** — never `git add -A` blindly over an unreviewed tree. Never use `git reset --hard`, `git checkout -- <path>`, `git restore <path>`, or `git stash` to "clean up" first — the stash stack is repo-global and shared across worktrees.

## Principles
- One self-contained unit per commit; unrelated concerns never share a commit.
- Detect the repo's conventions; don't impose new ones.
- Confirm the plan before committing.
