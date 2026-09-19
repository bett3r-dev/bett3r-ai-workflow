---
description: Begin a unit of work. Cuts the branch, writes a fresh .work/mode.yaml and records the base sha. Runs no suite and writes no context docs.
---

# /start — begin work

This is the `start` step; its verdict is `LANE-STEP:v1 step=start …`. It produces a branch, a fresh `.work/mode.yaml` and a recorded base, and it runs no suite.

## Argument: $ARGUMENTS

A ticket id, a short description of the work, or both.

## Step protocol

**Brief.** If `.work/lane.yaml` exists you are an unattended lane: `work_item` is the brief's `ticket:` id (or `$ARGUMENTS` when given) and `branch` is its `branch:`; you ask no one anything. Without the file you run attended: inputs come from `$ARGUMENTS` and the user.

**Mode marker.** Delete any existing `.work/mode.yaml` or `.work/lane.yaml` outright, then write `.work/mode.yaml` fresh in Step 3. One file means one scrub path. The one exemption is checkable: leave `.work/lane.yaml` alone when its `worktree:` is this tree **and** its `branch:` is the branch just created, because a brief naming this tree and this branch is this lane's own, and steps 2–5 need it. Nothing here writes `.work/lane.yaml`; the `provisioner` does.

**Verdict.** Your last line is `LANE-STEP:v1 step=start outcome=<success|blocked-on>` at column 0 with nothing after it. Run `lane-step-record '<the identical line>'` immediately before printing it (it records the verdict on the branch when the brief opts in). Printing the line ends the run: take no turn after it.

## Step 1 — Unfinished work

If `.work/slices.yaml` holds slices not all `passes: true`, say so in one line and proceed: that work's record is its branch, commits and PR. If `.work/learnings.md` or any `.work/multi/*/learnings.md` has unprocessed entries, warn before replacing them and name the run: a fleet's `.work/multi/<run-id>/learnings.md` is the run's sole surviving copy after teardown, so recommend `/capture-learnings` first. Done when both files were checked and any warning is printed.

## Step 2 — Branch

Cut a branch off the current one, named `<ticket-id>-<slug>` (`TV1-1594-delete-items`), or from the description when there is no id. Keep the current branch and cut nothing when it already belongs to the execution venue: it is not the repo's default branch and not one this command created (a hosted session that may push only to `claude/*` is one such venue). Ticket identity lives in `.work/mode.yaml`'s `work_item:`, never in the branch slug. Done when `git branch --show-current` prints the branch this unit builds on and your report says in one line whether it was cut or kept.

## Step 3 — Scaffold `.work/`

Create `.work/` and add it to `.gitignore` if missing. It holds working state only; the design is committed beside the code, in the folder `work-docs-path` names.

Write `.work/mode.yaml` with exactly these four keys:

```yaml
mode: start          # start | design | plan | build — the command that wrote this, nothing else
work_item: TV1-1594  # the ticket id; with no id, <yyyy-mm-dd>-<slug> dated the day /start ran, fixed once
branch: TV1-1594-delete-items
updated: 2026-01-30T14:02:11Z   # ISO-8601 UTC
```

Every later command rewrites the file whole and carries `work_item:` forward unchanged. A marker that survives a new `/start` is worse than no marker, because it is confidently wrong about which work item you are on.

`work_item:` takes one of the three shapes `work-docs-path --item` accepts: a Jira key as given; a GitHub issue `#<n>` written `gh-<n>`; or, with no id, `<yyyy-mm-dd>-<slug>`, never the branch name itself. The slug is the last path segment of the branch, lower-cased, every run of other characters turned into one `-`, dashes trimmed from both ends (`claude/Fix_Flaky test` → `fix-flaky-test`). When that leaves nothing, **ask the user for a slug**; with no user, end `blocked-on`. The date is the day `/start` ran, in the local time zone, recorded once and never re-derived: a repeat `/start` on the same branch on the same day gets the same id, and the date keeps two work items on one recycled branch name in separate folders. Done when the file parses with those four keys and `work_item:` is in one of the three shapes.

## Step 4 — Record the base

Write `.work/known-baseline-failures.md` with the base sha and branch and the line `not captured — capture on demand`. Run no suite and no typecheck: the base side of a baseline is needed only when a later step sees a red `HEAD`, and that step captures it then, for the red suites only, as `full-gate` describes. An absent baseline is the absence of a claim, not a claim that the base is green, and the file says so in those words. Done when the file holds the sha, the branch and that line.

## Step 5 — Ticket context (optional)

With a ticket id and a tracker MCP available, fetch the ticket's summary and description. Otherwise continue; the user describes the work.

## Step 6 — Hand off

> Branch `<name>` ready. Run `/design` to grill and model the work.

`success` when the branch exists and `.work/` is scaffolded; `blocked-on` when there is no resolvable work item or the branch cannot be cut from the base. This step never reports `gate-red`. Then the verdict line, as the protocol says.
