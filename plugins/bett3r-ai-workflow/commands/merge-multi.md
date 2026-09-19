---
description: Land a finished fleet — merge each reviewed unit PR into `int/<run-id>` (conflicts resolved once), run the scoped gate there, and open the single integration PR to the default branch.
---

# /merge-multi — land the fleet

`/start-multi` ends with N reviewable PRs open against the run's integration branch `int/<run-id>` and nothing merged. You review them at your own pace; **this command is the landing**, run afterwards in a **fresh session**: everything it needs is on disk (`run.yaml`) or on GitHub (`gh pr view`). The integration branch is why reviews stay per unit, conflicts are resolved once as merge commits, and the gate runs once on the assembled tree, the only place cross-unit breakage exists.

## Argument: $ARGUMENTS

Optional run-id. Default: the most recent run in `.work/multi/` for this repo.

| Flag | Effect |
|---|---|
| `--dry-run` | Print the inventory (step 1), run step 1b's read-only ruling and report the would-refuse set, then stop. Merges nothing. |
| `--only <ids>` | Land a subset; the rest stay open against integration. |
| `--land` | Also merge the integration PR into the default branch (step 6). **Off by default**: that is the last irreversible act. |

## Steps

**1 — Inventory. Report; do not act.**

Read `.work/multi/<run-id>/run.yaml` for the unit set, the wave order and the integration branch. `git fetch origin`. Then read each unit's real state from GitHub, since `run.yaml` was written before review:

```sh
gh pr view <n> --json number,title,state,baseRefName,headRefName,headRefOid,mergeable,mergeStateStatus,reviewDecision
```

Print one row per unit and act on each finding as its bullet says:

- **Base is not `int/<run-id>`.** Retarget (`gh pr edit <n> --base int/<run-id>`) or exclude the unit; a wrong-target merge reports `MERGED` and delivers nothing.
- **State is already `MERGED`.** Skip it; re-running after a partial land is the expected path.
- **`reviewDecision` is `CHANGES_REQUESTED`.** Stop; that is the human's outstanding objection.
- **The unit did not reach `passed`** in `run.yaml`, or has no PR. Exclude it.

`--dry-run` continues into the read-only step 1b, reports the would-refuse set (each refused unit with its verdict line and its stacked dependents) and stops before step 2. Done when every unit has a row and a disposition: merge, skip, retarget or exclude, or stop.

**1b — Rule each unit's concerns, before merging it.**

`/verify-build` posted a `flow/concerns` commit status on each unit's head; that status is advisory (a private free-plan repo cannot require it), and a human can merge over a red one. **This command is the hard block**: before merging a unit, rule it yourself from files taken off its own head commit, not the working tree, a sibling's checkout, or the status read back.

The unit's work-docs folder comes from its lane's own record: `work_item:` in `.work/multi/<run-id>/units/<unit-id>.state.yaml`, the exact value the lane copied from its `/start`'s `.work/mode.yaml`, resolved with `work-docs-path --item <work_item>`. The state file is found by the unit's `units[].id`, which is not itself the work item. A missing state file, a missing or empty `work_item:`, or a `work-docs-path` verdict other than `outcome=ok` refuses the unit, and the block then runs no `concerns-check` and prints no verdict line. Never fall back to `run.yaml`'s `units[].id` as the work item. `<sha>` is the `headRefOid` step 1 read.

```sh
STATE=".work/multi/<run-id>/units/<unit-id>.state.yaml"
WORK_ITEM=$(sed -n 's/^work_item:[[:space:]]*//p' "$STATE" 2>/dev/null | head -n 1 \
  | sed -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' -e "s/^[\"']\(.*\)[\"']$/\1/")
DOCS=
[ -n "$WORK_ITEM" ] && DOCS=$(work-docs-path --item "$WORK_ITEM" | tail -n 1 \
  | sed -n 's/^WORK-DOCS-PATH:v1 outcome=ok .* path=\([^ ]*\) .*$/\1/p')
if [ -z "$DOCS" ]; then
  echo "unit <unit-id>: refuse — no work_item in $STATE, or work-docs-path did not resolve it"
else
  TMP=$(mktemp -d)
  git show "<sha>:$DOCS/concerns.md"  > "$TMP/concerns.md"  2>/dev/null || rm -f "$TMP/concerns.md"
  git show "<sha>:$DOCS/decisions.md" > "$TMP/decisions.md" 2>/dev/null || rm -f "$TMP/decisions.md"
  concerns-check --decisions "$TMP/decisions.md" "$TMP/concerns.md"
fi
```

Read the last line, `CONCERNS-CHECK:v1 outcome=pass|fail|error …`, not the exit code (ADR-004). The mapping, each outcome once:

- `outcome=pass` → merge the unit.
- `outcome=fail` → refuse the unit.
- `outcome=error` → refuse the unit. A malformed file, a fabricated or foreign waiver citation, or a corrupt `decisions.md` is not-success exactly like `fail`.
- No verdict line at all (the command produced nothing, died before printing one, or never ran because the unit's work item did not resolve) → refuse the unit.

**A missing `concerns.md` at the unit head is a refusal, not "no concerns".** `/verify-build` always commits the file, empty when the unit raised none, so its absence at that sha means that unit's `/verify-build` did not complete, and the block already refuses it: `concerns-check` returns `outcome=error reason=file-not-found`. A missing `decisions.md` is not by itself a refusal, since `concerns-check` reads it only when a concern is waived.

**Report a refused unit by id with its verdict line**; the same line goes into the integration PR body under step 4's `declared − landed` heading. **A refusal blocks its dependents**: a stacked child's branch is cut from its parent's tip, so merging the child without the parent in `int/<run-id>` would deliver the parent's unruled work by the back door; refuse every unit stacked (directly or transitively) on a refused one, and say so. Units with no dependency on the refused one merge.

Done when every unit has a ruling: `merge`, or `refuse` with its verdict line and its dependents named.

**2 — Merge into integration, in dependency order.**

Follow `run.yaml`'s waves — a stacked child after its parent. Merge each unit PR into `int/<run-id>`. Merge exactly the head sha Step 1b ruled (`gh pr merge <n> --match-head-commit <sha>`, or `git merge <sha>` in the integration worktree), never whatever the branch points at now: if the head has moved since that ruling, re-run Step 1b at the new head sha and refuse on anything but `outcome=pass`. A stacked child's PR targets its parent's branch: `gh pr edit <n> --base int/<run-id>` before merging it, and delete no unit branch while a PR still targets it, since deleting a base closes the child unmerged.

Resolve conflicts in the integration worktree as merge commits, never by rewriting a unit branch: the unit branch is the artifact the human reviewed, and a rebase invalidates that review silently.

- Generated / codegen files: `git checkout --theirs`, then re-run the generator.
- Hand-authored additive files: splice **complete** units; a marker-strip breaks on array tails.
- `*.orig` residue is checked before committing; a `.ts.orig` passes every gate uncompiled.
- A pinned counter touched by N units is **recomputed, never picked**: write `base + Σ (each unit's delta against its own base)`, the addends `/start-multi`'s step-8 report carries, and verify by running the suite, since every branch's value is wrong on the merged tree.
- A clean merge does not discharge a cross-unit obligation. For every `owesSiblings` entry in `units/<id>.state.yaml` and every PR-body "for the <sibling> merge" section, check the merged file even where git did not conflict, apply the obligation on integration with a test red without it, and record it as a resolution; an unresolved one blocks step 5.

Record every resolution as you make it (which units, which file, what was kept and dropped, why), in the integration PR body (step 5) and as an entry in the run-level `decisions.md`: the reviewer approved unit diffs; what ships is those diffs plus your resolutions.

**The run-level `decisions.md`** is `<root>/<run-id>/decisions.md`, resolved with `work-docs-path --item <run-id>` (`run.yaml`'s `runId:`), never a hardcoded root. It holds this command's own conflict resolutions only; `/design-multi` Phase B's policies are not restated there, since each unit's committed `design.md` carries them. If `work-docs-path --item <run-id>` refuses (a hand-made run id, or one built from a unit id `work-docs-path` cannot carry, such as a Jira key with an underscore), write no run-level `decisions.md` entry: put its `WORK-DOCS-PATH:v1` verdict line in the integration PR body under *Conflict resolutions* instead, and continue merging. `/merge-multi` is the file's single writer: each entry is a `## D<n> — <title>` with `step: merge-multi · slice: — · decidedBy: orchestrator`, its id one more than the highest already in the file, in the D-entry grammar `/build`'s record companion (`reference/build-record.md`) states.

Done when every unit ruled `merge` is in `int/<run-id>` at its ruled sha, every conflict and obligation has a recorded resolution, and no `*.orig` remains.

**3 — Run the gate, once, on integration.**

Bump each touched plugin's `plugin.json` once on `int/<run-id>` before the gate; the version-bump step must read `PASS` there, and a `SKIP reason=deferred-to-merge-multi` is refused as red, since integration carries no `.work/lane.yaml` and a `SKIP` means a stale lane brief leaked in; remove it and re-run.

Run the gate as the `full-gate` skill says, in the repo's scoped mode (`--fast` where the host has no scoped mode, and say so), on `int/<run-id>`, reading the verdict from the `GATE-STEP:` lines and baseline-diffing against the default branch. The whole-repo `--full` and `--all` runs are never a flow step's; that run is CI's, or the user's on request. The integration diff is the union of every unit's diff, so the scoped verdict certifies the fleet's combined diff and its importers; report the ref it ran at and therefore which units it covers, naming a unit excluded with `--only` as not covered.

A red gate is **fixed on integration**, not deferred. If a failure traces cleanly to one unit and the fix is more than a line, push the fix to that unit's branch and re-merge, so the unit PR stays an honest record of its own work. A fix pushed to a unit branch changes its head: re-run Step 1b at the new head sha before re-merging, and refuse on anything but `outcome=pass`. Otherwise fix on integration and name the unit in the commit message. The integration PR opens over `GATE: PASS` only; a red integration branch has no owner once the fleet is torn down.

Done when the gate printed `GATE: PASS` on the current tip of `int/<run-id>` and the version-bump step read `PASS`.

**4 — Collect the closing keywords.**

A PR merged into `int/<run-id>` does not close its issues: GitHub fires closing keywords only on merges into the default branch, so every `Closes #N` in a unit PR body is inert. Collect the union of issues referenced across every unit PR into the integration PR body, one `closes` keyword per issue: `Closes #56, closes #62, closes #63`. A bare list (`Closes #56, #62`) closes the first and turns the rest into mentions; `/verify-build` step 6 states the binding rule.

Reconcile the manifest: `run.yaml` declares the run's units and you have just enumerated what merged, so compute **`declared − landed`**. If it is non-empty, the integration PR body states it under its own heading and the report leads with it: a unit step 1b refused is listed with its `CONCERNS-CHECK:v1` verdict line, and a deliberately dropped unit is recorded as dropped with a reason. The integration branch name is not evidence of scope; it was fixed at cut time.

The epic's goal oracle is reported here, red or green; landing every unit with it still red is a reportable outcome, not a silent success.

Done when the body carries one `closes` per referenced issue, the `declared − landed` set (even when empty), and the goal oracle's verdict.

**5 — Open the integration PR.**

`gh pr create --base <default> --head int/<run-id>` — ready for review, not a draft. Then verify its base, since `gh pr create` succeeds silently against the wrong ref. The body is an index, not a concatenation: what landed, what you resolved and what the gate said; every unit PR keeps its full body at its own URL.

```
## Fleet <run-id> — <N> units

| Unit | PR | ADR |
|---|---|---|
| TV1-1001 — <title> | #101 | ADR-0142 |
| TV1-1002 — <title> | #102 | — |

### Conflict resolutions
- TV1-1004 × TV1-1007 in `src/foo.ts` — kept X, dropped Y, because <reason>.
- (or "none")

### Gate
<the full-gate report block, verbatim — step names, counts, baseline diff, and
 anything reported SKIP / INCONCLUSIVE, not selected by the scoping, or
 excluded from the repo's widest run, by name>

Closes #56, closes #62, closes #63
```

Done when the PR exists with `baseRefName` equal to the default branch.

**6 — Land (`--land` only).**

Merge the integration PR into the default branch. Then two assertions, because both failures report success:

```sh
git fetch origin
git merge-base --is-ancestor origin/int/<run-id> origin/<default>   # the merge actually delivered
for n in <every referenced issue>; do printf '%s %s\n' "$n" "$(gh issue view "$n" --json state -q .state)"; done
```

Check the line count before the states, since a `gh` failure prints a blank state and greps clean. Close the stragglers (`gh issue close <n> -c "landed in #<pr>"`). Bulk form when the set is long:

```sh
comm -13 <(gh issue list --state closed --limit 500 --json number -q '.[].number' | sort) \
         <(printf '%s\n' <referenced> | sort)
```

Whatever that prints is still open. Then delete `int/<run-id>` if the repo deletes merged branches, and report the default-branch sha the fleet landed at. Done when the ancestor check succeeded and every referenced issue printed `CLOSED`.

Without `--land`, stop at step 5 and report the integration PR URL and its `mergeable` state, saying plainly that nothing has landed.

**7 — Report.**

Units merged (and any skipped, with why) · `declared − landed`, always, even when empty · the epic goal oracle's verdict · conflict resolutions, counted · the gate verdict · the integration PR URL · issues closed vs. still open. Done when `run.yaml` carries `landedAt` and `integrationPr`, so a re-run is a no-op.

## Principles

- **Fresh session, always.** The fleet conversation holds the run's memory; this command needs only its bookkeeping.
- **Merged is not delivered, and merged is not closed.** A wrong-target merge and an inert closing keyword both report success; each has an explicit assertion above, and nothing lands without `--land`.
