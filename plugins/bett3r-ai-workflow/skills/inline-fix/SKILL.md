---
name: inline-fix
description: "Use for a quick, self-contained fix to already-shipped functionality outside the slice flow: build, ripple-check, test, and land it as one squashed commit."
disable-model-invocation: true
---

For a small change to functionality that already works and is not being driven through `/build`. The whole fix lands as one commit.

## 1 — Change

Make the change, scoped to the fix.

## 2 — Build

Build every affected repo or package. Done when typecheck and build are clean.

## 3 — Ripple-check

A changed signature or contract breaks callers the edit never touched, and those callers have no gate but this one. For every exported symbol whose signature or behaviour changed, grep every caller across the repo, including `*.integration.test.ts`, e2e and fixture files excluded from the default test run. Fix and spot-run each mismatch. Done when every caller matches.

## 4 — Test

Run the tests, then exercise the changed path end to end: see the fix work, not only the tests green.

## 5 — Commit, once

One self-contained commit, squashed-PR style, even across files or packages (`/commit` splits by concern; this is deliberately one unit).

- Stage the fix's files by explicit path, staging only this fix's paths when the tree has unrelated changes. The rest of the tree stays as it is; to inspect or snapshot uncommitted changes use `git stash create` and `git diff <object>`.
- Subject: imperative summary, `fix(scope): …` where the repo uses conventional commits (read `git log`); the ticket id from the branch (`TV1-1594-…` → `TV1-1594`) and the repo's trailer if it has one.
- One `git commit` with a HEREDOC body. Intermediate commits already made: `git reset --soft <base>` first, then commit once.

Body: **Problem and intent** in the ubiquitous language; **Changes made** and their rationale; **Tests**, how the fix was verified. Done when `git log --oneline -1` shows the one commit and `git status` is clean of this fix's files.
