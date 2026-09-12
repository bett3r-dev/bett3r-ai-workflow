---
description: Begin a unit of work — create the branch and scaffold the ephemeral .work/ workspace. Thin and mechanical, no context docs.
---

# /start — begin work

Thin and mechanical: a branch and an ephemeral workspace. No `context.md`, no committed scaffolding, no ceremony.

## Argument: $ARGUMENTS

A ticket id and/or a short description of the work.

## Step 1 — Check for unfinished work

If `.work/slices.yaml` exists and holds slices not all `passes: true`, note it: "Unfinished work in `.work/` () — starting new work replaces it." **Default: proceed.** That prior work's real record is its branch/commits/PR; `.work/` is disposable. (Only pause if the user explicitly asked to be warned.)

**Records guard:** if `.work/learnings.md` **or any `.work/multi/*/learnings.md`** has unprocessed entries (captured via the `record` skill), warn before replacing, naming the run where there is one: "N unprocessed records in `.work/multi/<run-id>/learnings.md` (fleet run `<run-id>`) — run `/capture-learnings` first?" Losing these is the exact failure `record` exists to prevent, so default to surfacing it here. **The fleet path is not an afterthought:** `/start-multi` step 6 aggregates every lane's buffer there and step 7 then deletes the worktrees the originals lived in, so that file is the run's **sole surviving copy** — and a guard that checks one literal path is a warning that does not print, which looks exactly like nothing being wrong.

## Step 2 — Branch

Create a branch off the current branch. Name it from the ticket id + a slug (e.g. `TV1-1594-delete-items`), or from the description if there's no id. That is the default and the common case: a plain local `/start` off the default branch.

**But check before you create — the branch name may belong to the EXECUTION VENUE, not to you.** If the current branch is already the venue's — it is not the repo's default branch, and it is not one this command created — **keep it and cut nothing.** Record the work item in `.work/mode.yaml` as Step 3 does and say in one line which branch the lane is on and why it was not renamed. The constraint, not the instance: **ticket identity lives in `.work/mode.yaml`'s `work_item:`, never in the branch slug**, and a hosted session that may push only to `claude/*` is one venue, not the rule. Without this the step points the wrong way — the model has to override its own command file to get it right, and the failure lands at push, with the work already done.

## Step 3 — Scaffold `.work/`

Create `.work/ and add it to .gitignore` if it is missing. It holds `slices.yaml` and the rest of the working state — ephemeral, never committed. The design is not kept here: `/design` commits it beside the code, in the folder `work-docs-path` names.

**Then clear and rewrite `.work/mode.yaml`, and clear `.work/lane.yaml`.** This is the load-bearing half of the marker, not a formality: everything else in `.work/` — `design.md`, `slices.yaml`, `passes:`, `design-snapshot/` — is residue that accumulates and is never erased, so a workspace left over from the previous branch reads exactly like the current one's. Delete any existing `.work/mode.yaml` or `.work/lane.yaml` outright and write a fresh `mode.yaml`; never merge with, patch, or preserve a field from what was there. A marker that survives a new `/start` is worse than no marker, because it is confidently wrong about which work item you are on.

**The one exemption, and it is checkable, not a judgement call:** leave `.work/lane.yaml` alone when its `worktree:` is this tree **and** its `branch:` is the branch you just created. A brief naming this worktree and this branch is by construction the brief for this very lane, not residue from a previous run — and `/start` is step 1 of the lane's own sequence, so deleting it there leaves steps 2–5 with no brief and `/verify-build` silently running the **full** gate instead of `--fast`, once per lane, across a fleet. Anything else — a different path, a different branch, a brief with neither field — is residue and is deleted. Scoping the delete here is what lets the lane invoke the five commands plainly; a caller that copies its brief aside and restores it is the same coupling in a second place.

`.work/lane.yaml` is otherwise deleted and **not** rewritten here: it is a lane's whole brief, written into a provisioned worktree from the outside, and a `/start` on your own branch is not a lane. A stale one left behind claims a deferral — of the full gate, to a run that no longer exists — and the claim is silent, which is worse than the residue. **One file means one scrub path**; two brief files means two, and a scrub can miss one.

```yaml
mode: start          # start | design | plan | build — the command that wrote this, nothing else
work_item: TV1-1594  # the ticket id; with no id, <yyyy-mm-dd>-<slug> dated the day /start ran, fixed once
branch: TV1-1594-delete-items
updated: 2026-01-30T14:02:11Z   # ISO-8601 UTC
```

Four fields, overwritten in full by each command that touches it — **never appended to**, since append-only reproduces the exact residue bug the file exists to fix. It is one small file inside an already-gitignored directory, so a repo that ignores it is unaffected.

**With no ticket id, `work_item:` is `<yyyy-mm-dd>-<slug>`, never the branch name itself.** Every command that reads the design passes `work_item:` untouched to `work-docs-path --item`, which accepts a no-id work item only in that shape — a raw `claude/Fix_Flaky test` would block `/design`, `/plan` and `/verify-build` alike. Derive the slug from the last path segment of the branch: lower-case it, turn every run of other characters into one `-`, and trim dashes from both ends (`claude/Fix_Flaky test` → `fix-flaky-test`). If that leaves nothing — a branch ending in `/`, a segment with no ASCII letter or digit — **ask the user for a slug** rather than inventing one; with no one to ask, end `blocked-on` (no resolvable work item).

**The date is the day `/start` ran, in the local time zone, recorded once and never re-derived** (`2026-01-30-fix-flaky-test`). Every later command that rewrites `.work/mode.yaml` carries `work_item:` forward unchanged — it never re-dates it, and never re-derives the slug from the branch. The date is what tells two work items on one branch name apart: a branch deleted after merge and recreated months later for unrelated work derives the same slug, and only the new `/start` day keeps its design out of the old one's folder.

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

## Step 7 — Report the outcome

End your output with this line, at column 0, as the **final** line — nothing after it, not even a closing remark, and no trailing punctuation (`success.` is a value in no vocabulary, and a step that punctuates its marker reports no verdict at all):

    LANE-STEP:v1 step=start outcome=<success|blocked-on>

`success` when the branch exists and `.work/` is scaffolded. `blocked-on` when there is no resolvable work item, or the branch cannot be cut from the base — a lane with no work item has nothing to design. This step runs no suite (Step 4), so it never reports `gate-red`. **Immediately before printing it**, run `lane-step-record '<the identical line>'`: it commits the verdict to your branch when `.work/lane.yaml` carries `verdictOnBranch: true` and does nothing otherwise; a non-zero exit is reported in your prose, never by changing the line. Never emit `infra` — its signal is the line's absence. The format contract is stated once in [unit-lane](../agents/unit-lane.md); do not restate it here.

## Principles

- Thin. The branch, the recorded base sha, `.work/` and a cleared `.work/mode.yaml` are all `start` produces — **no test run**.
- `.work/` is gitignored and disposable; git is the record.

