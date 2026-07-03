---
name: inline-fix
description: "Use when making a quick, self-contained fix on top of already-shipped functionality, outside the slice flow (/build). Builds, ripple-checks, tests, and lands it as one squashed commit."
---

For a small change to functionality that already works and isn't being driven through the slice loop. The whole fix lands as **one** commit.

## 1 — Make the change
Make the required change, scoped tightly to the fix.

## 2 — Build
Build every affected repo/package. Confirm typecheck/build is clean with no errors.

## 3 — Ripple-check
A fix to existing code is exactly where a changed signature or contract breaks *callers the edit never touched* — and those callers have no gate but this one. For any exported symbol whose signature or behavior changed, grep **every** caller across the repo, explicitly including `*.integration.test.ts` / e2e / fixture files that are **excluded from the default test run** and so never go red locally. Fix and spot-run any mismatch.

## 4 — Test
Run the tests. Then exercise the changed path end-to-end (`/verify`) — see the fix work, don't just see tests green.

## 5 — Commit (one squashed commit)
Author the whole fix as a **single** self-contained commit (squashed-PR style), even if it spans files or packages. Do **not** call `/commit` — that splits by concern; this is deliberately one unit.

- Stage the fix's files by **explicit path**. If the tree has unrelated changes, stage only this fix's paths or file ranges. Never `git add -A` over an unreviewed tree; never `reset --hard`/`stash` to "clean up."
- Subject: imperative summary (`fix(scope): …` if the repo uses conventional commits — detect from `git log`, don't hardcode). Derive the ticket id from the branch (`TV1-1594-…` → `TV1-1594`) and add the repo's trailer/sign-off if it has one.
- One `git commit` (HEREDOC body). If you already made intermediate commits, `git reset --soft <base>` first, then commit once.

Body:
- **Problem & intent** — what we're solving, in the ubiquitous language.
- **Changes made** — the rationale behind the changes.
- **Tests** — how the fix was verified.
