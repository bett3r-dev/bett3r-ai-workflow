---
description: Begin a unit of work — create the branch and scaffold the ephemeral .work/ workspace. Thin and mechanical, no context docs.
---

# /start — begin work

Thin and mechanical: a branch and an ephemeral workspace. No `context.md`, no committed scaffolding, no ceremony.

## Argument: $ARGUMENTS

A ticket id and/or a short description of the work.

## Step 1 — Check for unfinished work

If `.work/slices.yaml` exists and holds slices not all `passes: true`, note it: "Unfinished work in `.work/` () — starting new work replaces it." **Default: proceed.** That prior work's real record is its branch/commits/PR; `.work/` is disposable. (Only pause if the user explicitly asked to be warned.)

**Records guard:** if `.work/learnings.md` has unprocessed entries (captured via the `record` skill), warn before replacing: "N unprocessed records in `.work/learnings.md` — run `/capture-learnings` first?" Losing these is the exact failure `record` exists to prevent, so default to surfacing it here.

## Step 2 — Branch

Create a branch off the current branch. Name it from the ticket id + a slug (e.g. `TV1-1594-delete-items`), or from the description if there's no id.

## Step 3 — Scaffold `.work/`

Create `.work/ and add it to .gitignore` if it is missing. It holds `design.md` and `slices.yaml` — ephemeral, never committed.

## Step 4 — Capture the baseline → `.work/known-baseline-failures.md`

Record the typecheck/test failures that are **already** on the base, and **how they were captured**. Cheap once here; otherwise every later step re-derives it, and under a fleet every lane pays for it in parallel.

Two rules, because a wrong baseline is worse than none — a lane either chases errors that are not its own or, in the dangerous direction, treats real new errors as pre-existing cover:

- **Capture on a freshly built tree.** When the toolchain cannot resolve a package's `.d.ts`, the failure cascades into ordinary-looking `TS2345`/`TS2322`/`TS2339` in every importing file — indistinguishable by inspection from genuine type errors. So *"filter out the known-noise code and trust the remainder"* is not a safe protocol: the remainder is contaminated by the same cause. (Measured once: `134 × TS6305 + 24 "real"` became `0 + 1` after re-emitting declarations.) A baseline taken with unresolved-dependency errors present is inflated and must not be published.
- **An incremental typechecker under-reports on a second run** — it re-checks almost nothing. Clear the incremental state for a comparable full count.

Later steps compare **by file, not by total**: a total hides an equal-and-opposite swap.

## Step 5 — (optional) Pull ticket context

If a ticket id is given and a tracker MCP is available (Jira/GitHub), fetch the ticket summary/description for context. If not, continue — the user will describe the work.

## Step 6 — Hand off

> Branch `<name>` ready. Run `/design` to grill and model the work.

## Principles

- Thin. The branch, the baseline and `.work/` are all `start` produces.
- `.work/` is gitignored and disposable; git is the record.

