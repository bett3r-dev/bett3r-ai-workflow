---
description: Land a finished fleet — merge each reviewed unit PR into the run's integration branch (conflicts resolved once), run the full gate there, and open the single integration PR to the default branch.
---

# /merge-multi — land the fleet

`/start-multi` ends with N reviewable PRs open against the run's integration branch `int/<run-id>`, and nothing merged. You review them at your own pace. **This command is the landing**, run afterwards — in a **fresh session**.

**Run it fresh; do not reopen the fleet conversation.** That session is the largest context in the run — it dispatched N lanes, collected N escalations, aggregated N state files — and re-invoking it to perform a mechanical merge sequence re-sends all of it. Everything this command needs is on disk (`run.yaml`) or on GitHub (`gh pr view`). The bookkeeping is cheap; the memory is not.

## Argument: $ARGUMENTS
Optional run-id. Default: the most recent run in `.work/multi/` for this repo.

| Flag | Effect |
|---|---|
| `--dry-run` | Print the inventory (step 1), run step 1b's read-only ruling and report the would-refuse set, then stop. Merges nothing. |
| `--only <ids>` | Land a subset; the rest stay open against integration. |
| `--land` | Also merge the integration PR into the default branch (step 6). **Off by default** — that is the last irreversible act. |

## Why an integration branch at all

Each unit branch is cut from `int/<run-id>`, and each unit PR's base is `int/<run-id>`. That buys three things at once, and they are otherwise in tension:

- **Reviews stay per-unit.** A unit PR's diff against integration is exactly that unit's work — no sibling noise.
- **Conflicts are resolved once.** Inter-unit conflicts surface when units merge into integration, and are resolved *there*, as merge commits. Merging the units individually into the default branch instead would resolve the same conflicts a second time, against a moving target.
- **The full gate runs once.** Cross-unit breakage exists only on the assembled tree, so no per-unit gate can see it — and running the full gate N times to look for something structurally invisible to it is the fleet's most wasteful step. Units run `--fast`; integration runs `--full`.

## Steps

**1 — Inventory. Report; do not act.**

Read `.work/multi/<run-id>/run.yaml` for the unit set, the wave order, and the integration branch. `git fetch origin`. Then, per unit, read the real state from GitHub rather than from `run.yaml` — the state file was written before review:

```sh
gh pr view <n> --json number,title,state,baseRefName,headRefName,headRefOid,mergeable,mergeStateStatus,reviewDecision
```

Print one row per unit and stop on any of these, naming the unit:

- **Base is not `int/<run-id>`.** Do not merge it. A PR merged into the wrong target returns exit 0, shows `MERGED`, and delivers nothing where you meant it — the merge itself reports success, so this is the one precondition with no downstream tell. Retarget (`gh pr edit <n> --base int/<run-id>`) or exclude the unit.
- **State is already `MERGED`.** Skip it — this command is idempotent and re-running after a partial land is the expected path.
- **`reviewDecision` is `CHANGES_REQUESTED`.** Stop; that is the human's outstanding objection.
- **The unit never reached `passed`** in `run.yaml`, or has no PR.

`--dry-run` continues into step 1b, because that ruling is read-only and is exactly what a dry run exists to show: it reports the would-refuse set (each refused unit with its verdict line, plus its stacked dependents) and stops before step 2. The two steps act differently on purpose: a finding above acts on the unit it names, as its bullet says — skip it, retarget or exclude it, or stop on the human's outstanding objection — while a step-1b refusal removes that unit and its stacked dependents from the landing, and the rest proceed.

**1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.**

`/verify-build` posted a `flow/concerns` commit status on each unit's head, but that status is **advisory only** (a private free-plan repo cannot make it required) and a human can merge over a red one. **This command is the hard block** (design F4/C2): before merging a unit (step 2), rule it yourself, from files taken off *its own head commit* — never the working tree, never a sibling's checkout, and never by reading the GitHub status back.

The unit's work-docs folder comes from its lane's own record: read `work_item:` from `.work/multi/<run-id>/units/<unit-id>.state.yaml` — the exact value the unit's lane copied from its `/start`'s `.work/mode.yaml` — and resolve it with `work-docs-path --item <work_item>`. The state file is found by the unit's `units[].id`, which is not itself the work item. A missing state file, a missing or empty `work_item:`, or a `work-docs-path` verdict other than `outcome=ok` refuses the unit: the block below then runs no `concerns-check` and prints no verdict line. Never fall back to `run.yaml`'s `units[].id` as the work item. `<sha>` is the head sha step 1's inventory already read (`headRefOid`).

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

Read the last line, `CONCERNS-CHECK:v1 outcome=pass|fail|error …`, never the exit code (ADR-004). The mapping is exactly this, each outcome named once:

- `outcome=pass` → merge the unit.
- `outcome=fail` → refuse the unit.
- `outcome=error` → refuse the unit. This is not-success exactly like `fail` — a malformed file, a fabricated or foreign waiver citation, or a corrupt `decisions.md` never reads as a pass or as "no concerns".
- No verdict line at all (the command produced nothing, died before printing one, or never ran because the unit's work item did not resolve) → refuse the unit.

**A missing `concerns.md` at the unit head is a refusal, not "no concerns".** `/verify-build` always commits the file, empty when the unit raised none, so `git show` failing to find it at that sha means that unit's `/verify-build` did not complete — and the `git show` above already reproduces that: with no file written to `$TMP/concerns.md`, `concerns-check` itself returns `outcome=error reason=file-not-found`, which the mapping above already refuses. A missing `decisions.md` is **not** by itself a refusal — `concerns-check` only reads it when a concern is waived, exactly the behaviour `/verify-build` already relies on; an absent one simply means this unit raised no waiver.

**Report a refused unit by id, with the verdict line**, and do not merge it; that same line goes into the integration PR body under step 4's `declared − landed` heading, as the reason the unit did not land. **A refusal blocks its dependents**: a stacked child's branch is cut from its parent's tip (`/start-multi` step 2), so merging the child without the parent already in `int/<run-id>` would deliver the parent's unruled work into integration by the back door — refuse every unit stacked (directly or transitively) on a refused one, and say so. Units in other waves with no dependency on the refused one are unaffected and still merge.

**2 — Merge into integration, in dependency order.**

Follow `run.yaml`'s waves — a stacked child after its parent. Merge each unit PR into `int/<run-id>`. Merge exactly the head sha Step 1b ruled (`gh pr merge <n> --match-head-commit <sha>`, or `git merge <sha>` in the integration worktree), never whatever the branch points at now: if the head has moved since that ruling, re-run Step 1b at the new head sha and refuse on anything but `outcome=pass`. **A stacked child's PR targets its parent's branch**, so `gh pr edit <n> --base int/<run-id>` before merging it — merged in place it reports MERGED and delivers nothing to integration — and delete no unit branch while a PR still targets it: deleting a base closes the child unmerged ([verify-build](./verify-build.md) step 6).

**Resolve conflicts in the integration worktree, as merge commits. Never by rewriting a unit branch** — the unit branch is the artifact the human reviewed and approved, and rebasing it invalidates that review silently. Rules that apply to any merge in this flow apply here:

- Generated / codegen files: `git checkout --theirs`, then **re-run the generator**. Never hand-merge them.
- Hand-authored additive files: splice **complete** units. A marker-strip breaks on array tails and interleaves two partial blocks at their shared prefix.
- Check for `*.orig` residue before committing. A `.ts.orig` is not compiled, so it passes every gate invisibly.

**A pinned counter touched by N units is RECOMPUTED, never picked.** For any monotonic pin several units moved — tier counts, node-registry census, deployment-unit counts, topology ratchets — every branch's value is correct on its own base and wrong on the merged tree, so there is no side to take: `ours`/`theirs` ships a wrong pin the suite then *enforces*, surfacing as an authorization defect rather than a merge defect. Write `base + Σ (each unit's delta measured against its own base)` — `run.yaml`'s step-8 report carries the addends — and verify by **running the suite**, which prints the received length, not by the merge being clean. One fleet's correct value (704) appeared on no branch.

**A clean merge does not discharge a cross-unit obligation.** Before merging, list every obligation the units recorded for the merge — `owesSiblings` in each `units/<id>.state.yaml`, and any PR-body "for the <sibling> merge" section. Check each against the merged file whether or not git conflicted there, apply it on integration with a test that is red without it, and record it as a resolution like any conflict; an obligation with no matching resolution blocks step 5. One was written three times — design, state file, PR body — and merged away cleanly with every gate green, because no unit's tests could reach the intersection.

**Record every resolution as you make it** — which units, which file, what was kept and what was dropped, and why. This is the one part of what lands that nobody reviewed: the reviewer approved unit diffs, and what ships is those diffs *plus* your resolutions. It goes in the integration PR body (step 5), which is the only section there allowed to be verbose, **and** as a `decisions.md` entry in the run-level folder below — the body keeps being written exactly as before; the entry is additive, not a replacement.

**The run-level `decisions.md`** is `<root>/<run-id>/decisions.md`, for every fleet run, resolved with `work-docs-path --item <run-id>` (`run.yaml`'s `runId:`) — never a hardcoded root. It holds this command's own conflict resolutions only, since no single unit owns them. `/design-multi` Phase B's cross-cutting policies are not restated there: each unit's committed `design.md` already carries its resolved design. If `work-docs-path --item <run-id>` refuses (a hand-made run id, or one built from a unit id `work-docs-path` cannot carry, such as a Jira key with an underscore), write no run-level `decisions.md` entry: put its `WORK-DOCS-PATH:v1` verdict line in the integration PR body under *Conflict resolutions* instead, and continue merging. `/merge-multi` is the file's single writer, allocating each `## D<n> — <title>` id the way `commands/build.md`'s *The committed record* does (one more than the highest id already in the file, read at the moment of the append) and never editing or removing an entry it did not just write, using the exact header grammar `concerns-check`'s docstring quotes back from `build.md`:

```
## D<n> — <title>
kind: silent-seam        # false-premise | silent-seam | deviation | shipped-finding | overruled | waiver
step: merge-multi · slice: — · decidedBy: orchestrator
sources: [code:<symbol> (<file>), adr:ADR-NNN, design:<section>, xp:<atom-id>, human]
rejected: <option> — <why not>
supersedes: —            # set when this overturns an earlier entry
```

**3 — Run the full gate, once, on integration.**

Per the [full-gate](../skills/full-gate/SKILL.md) skill: `node .claude/gate.mjs --full` (or the repo's `.claude/gate.sh`) on `int/<run-id>`, verdict read from the `GATE-STEP:` lines and baseline-diffed against the default branch. Read that skill for the discovery order and the four ways a green read is wrong; do not re-derive them here. They are all [EVIDENCE.md](../EVIDENCE.md) §1 — *a verdict is evidence only about what it actually executed* — and this is the one run in the whole fleet that certifies the assembled tree, so a misread here is unbacked by anything downstream.

The verdict names the ref it ran at and therefore **which units it covers** — the assembled tree covers every merged unit; a unit excluded with `--only` is not covered and is named as such.

A red gate is **fixed on integration**, not deferred. If a failure traces cleanly to one unit and the fix is more than a line, push the fix to that unit's branch and re-merge — that keeps the unit PR an honest record of its own work. A fix pushed to a unit branch changes its head: re-run Step 1b at the new head sha before re-merging, and refuse on anything but `outcome=pass`. Otherwise fix on integration and name the unit in the commit message. Do not open the integration PR over a red gate; an integration branch that looks landed and is red is the worst state this flow can produce, because the fleet is torn down and nobody owns it.

**4 — Collect the closing keywords.**

**A PR merged into `int/<run-id>` does not close its issues.** GitHub fires closing keywords only for PRs merged into the repository's **default** branch. Every `Closes #N` written into a unit PR body by `/verify-build` is therefore inert under this topology — well-formed, rendered as a cross-reference, and closing nothing. The failure has no tell anywhere: well-formed commits, PRs `MERGED`, gates green, and the only symptom is a backlog count nobody has a reason to read.

So collect the union of issues referenced across every unit PR, and carry them into the **integration** PR body — **one `closes` keyword per issue**, repeated. `Closes #56, closes #62, closes #63`. A bare list (`Closes #56, #62`) closes the first and turns the rest into mentions.

**RECONCILE the manifest before you open the PR.** `run.yaml` declares the run's units and you have just enumerated what merged: compute **`declared − landed`**. If it is non-empty, the integration PR body states it **under its own heading** and the report leads with it; a unit step 1b refused is listed there with its `CONCERNS-CHECK:v1` verdict line as the reason; a unit deliberately dropped is recorded **as dropped, with a reason**, because deliberate omission and silent disappearance must not look identical. One line of set arithmetic against state you already hold — without it a nine-unit run once landed eight with every gate green and correct. **The integration branch name is not evidence of scope**: it is derived from the requested unit list at cut time and never revised, so it reads as confirmation of a scope the run may not have delivered.

**The epic's goal oracle is reported here, red or green.** A fleet that lands every unit with the goal oracle still red is a **reportable outcome, not a silent success**.

**5 — Open the integration PR.**

`gh pr create --base <default> --head int/<run-id>` — ready for review, not a draft. Then verify its base after the fact; `gh pr create` succeeds silently against the wrong ref.

**The body is an index, not a concatenation.** Every unit PR keeps its full body at its own URL permanently, and the ADRs are committed files — copying them here duplicates rather than preserves, and a twelve-ticket wall of text is a body nobody reads. Only three things are genuinely new at this level, and none of them exists anywhere else: what landed, what you resolved, and what the gate said.

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
 anything reported SKIP / INCONCLUSIVE or excluded from --full by name>

Closes #56, closes #62, closes #63
```

**6 — Land (`--land` only).**

Merge the integration PR into the default branch. Then two assertions, because both failures report success:

```sh
git fetch origin
git merge-base --is-ancestor origin/int/<run-id> origin/<default>   # the merge actually delivered
for n in <every referenced issue>; do printf '%s %s\n' "$n" "$(gh issue view "$n" --json state -q .state)"; done
```

One line per reference, every one `CLOSED`. **Check the line count before the states** — a `gh` failure prints a blank state and greps clean. Close the stragglers (`gh issue close <n> -c "landed in #<pr>"`). Bulk form when the set is long:

```sh
comm -13 <(gh issue list --state closed --limit 500 --json number -q '.[].number' | sort) \
         <(printf '%s\n' <referenced> | sort)
```

Whatever that prints is what stayed open.

Then delete `int/<run-id>` if the repo deletes merged branches, and report the default-branch sha the fleet landed at.

**Without `--land`**, stop at step 5 and report the integration PR URL and its `mergeable` state. Say plainly that nothing has merged into the default branch.

**7 — Report.**

Units merged (and any skipped, with why) · **`declared − landed`, always, even when empty** · the epic goal oracle's verdict · conflict resolutions, counted · the gate verdict · the integration PR URL · issues closed vs. still open. Update `run.yaml` — `landedAt`, `integrationPr` — so a re-run is a no-op rather than a second attempt.

## Principles

- **Fresh session, always.** The fleet conversation holds the run's memory; this command needs only its bookkeeping. Reopening it to merge is the single largest avoidable cost in the fleet flow.
- **Conflicts resolved once, in one place.** The integration branch exists for exactly this. Any design that resolves the same conflict twice has lost the argument for having it.
- **The unit branch is the reviewed artifact.** Resolve into integration; never rebase what a human approved.
- **The gate runs once, where it can see something.** Cross-unit breakage is invisible per-unit by construction; N full gates buy less than one integration gate and cost N times as much.
- **Merged is not delivered, and merged is not closed.** A wrong-target merge and an inert closing keyword both report success. Each has an explicit assertion above; run them.
- **The integration PR records the landing, not the work.** Each unit PR remains the system of record for its own change — [verify-build](./verify-build.md)'s principle is unchanged, one level up.
- **Nothing is merged without `--land`.** Review gates the merge; the flag gates the default branch.
