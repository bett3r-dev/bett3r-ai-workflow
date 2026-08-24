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

## Step 4 — Record the base, do NOT run the suite

Write `.work/known-baseline-failures.md` with the base **sha and branch**, and the line **"not captured — capture on demand"**. That is the whole step. It costs seconds.

**Do not run the test suite or a full typecheck here.** A baseline is the *base-side* half of a diff, and that half is only ever needed when `HEAD` comes up **red**. When `HEAD` is green with parsed counts, zero `PASS→FAIL` flips are possible and the base-side run was pure cost — see [full-gate](../skills/full-gate/SKILL.md) § "Reading the verdict", which already says exactly this. Capturing eagerly pays it on every unit of every run to serve the minority case.

**Capture on demand instead, and narrowly.** The first time a step sees a red `HEAD`, capture the base side **only for the suites that are red** — by name, not the whole tier — and append them here with the method used. Two rules then apply, because a wrong baseline is worse than none (a lane either chases failures that were never its own or, in the dangerous direction, waves real ones through as pre-existing cover):

- **Capture on a freshly built tree.** When the toolchain cannot resolve a package's `.d.ts`, the failure cascades into ordinary-looking `TS2345`/`TS2322`/`TS2339` in every importing file — indistinguishable by inspection from genuine type errors. So *"filter out the known-noise code and trust the remainder"* is not a safe protocol: the remainder is contaminated by the same cause. (Measured once: `134 × TS6305 + 24 "real"` became `0 + 1` after re-emitting declarations.) A baseline taken with unresolved-dependency errors present is inflated and must not be published.
- **An incremental typechecker under-reports on a second run** — it re-checks almost nothing. Clear the incremental state for the suites you are capturing, or the count is not comparable.

Later steps compare **by file, not by total**: a total hides an equal-and-opposite swap. An absent baseline is not a claim that the base is green — it is the absence of a claim, and the file says so in those words so nobody reads the empty file as an empty failure set.

## Step 5 — (optional) Pull ticket context

If a ticket id is given and a tracker MCP is available (Jira/GitHub), fetch the ticket summary/description for context. If not, continue — the user will describe the work.

## Step 6 — Hand off

> Branch `<name>` ready. Run `/design` to grill and model the work.

## Principles

- Thin. The branch, the recorded base sha and `.work/` are all `start` produces — **no test run**.
- `.work/` is gitignored and disposable; git is the record.

