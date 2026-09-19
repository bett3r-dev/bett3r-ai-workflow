---
description: Stage and commit the working tree as well-formed, logically grouped commits in the repo's conventions. For ad-hoc changes outside the slice loop.
disable-model-invocation: true
---

# /commit

`/build` commits each slice itself; this is for ad-hoc changes outside that loop: a quick fix, a doc change, leftover work.

## Argument: $ARGUMENTS

Optional guidance for the commit message(s).

## Step 1 — Analyze

`git status`, `git diff`, `git diff --cached`. Derive the ticket id from the branch (`TV1-1594-delete-items` → `TV1-1594`) or from `.work/slices.yaml` `ticket:`. Read the repo's conventions: `git log --oneline -15` for message style (type/scope, prefix, trailer or sign-off) and `${CLAUDE_PROJECT_DIR}/.claude/rules` for commit or grouping rules. Done when the ticket id and the convention are named.

## Step 2 — Group

One complete, self-contained unit per commit, grouped by logical concern the way the repo's rules say (some group by layer or module); unrelated modules in one concern are separate commits; dependency order, foundational first. Left unstaged: `.env` and `.env.*`, anything named `credentials` or `secret`, `*.log`, `node_modules/`, build output. Done when every changed path belongs to exactly one group.

## Step 3 — Messages

The repo's observed convention, defaulting to `type(scope): summary`: type from feat / fix / docs / test / refactor / chore, scope the module affected, summary imperative and lowercase with no trailing period, favouring why over what. Reference the ticket in the body where the repo does, and add its trailer or sign-off. A closing keyword binds to one issue, so repeat it per issue, `Closes #12, closes #13` (the rule's home is `/verify-build` Step 6). Use `$ARGUMENTS` as guidance when given.

## Step 4 — Present and confirm

Show the plan: N commits, each with its message and files. Ask: proceed, edit, or cancel. On edit, adjust and show again. Done when the user has said proceed.

## Step 5 — Execute

For each group in order: stage its files by explicit path, commit with a HEREDOC body, `git log --oneline -1` to confirm. After all: `git log --oneline -N`. Done when N commits show.

## Boundaries

- Stage explicit paths, never `git add -A` over an unreviewed tree: a reviewed path list is the whole point of Step 4.
- The working tree stays as it is; to inspect or snapshot uncommitted changes use `git stash create` and `git diff <object>`, which touch nothing.
