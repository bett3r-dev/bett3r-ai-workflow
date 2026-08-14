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
| `--dry-run` | Print the inventory (step 1) and stop. Merges nothing. |
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
gh pr view <n> --json number,title,state,baseRefName,headRefName,mergeable,mergeStateStatus,reviewDecision
```

Print one row per unit and stop on any of these, naming the unit:

- **Base is not `int/<run-id>`.** Do not merge it. A PR merged into the wrong target returns exit 0, shows `MERGED`, and delivers nothing where you meant it — the merge itself reports success, so this is the one precondition with no downstream tell. Retarget (`gh pr edit <n> --base int/<run-id>`) or exclude the unit.
- **State is already `MERGED`.** Skip it — this command is idempotent and re-running after a partial land is the expected path.
- **`reviewDecision` is `CHANGES_REQUESTED`.** Stop; that is the human's outstanding objection.
- **The unit never reached `passed`** in `run.yaml`, or has no PR.

`--dry-run` stops here.

**2 — Merge into integration, in dependency order.**

Follow `run.yaml`'s waves — a stacked child after its parent. Merge each unit PR into `int/<run-id>`.

**Resolve conflicts in the integration worktree, as merge commits. Never by rewriting a unit branch** — the unit branch is the artifact the human reviewed and approved, and rebasing it invalidates that review silently. Rules that apply to any merge in this flow apply here:

- Generated / codegen files: `git checkout --theirs`, then **re-run the generator**. Never hand-merge them.
- Hand-authored additive files: splice **complete** units. A marker-strip breaks on array tails and interleaves two partial blocks at their shared prefix.
- Check for `*.orig` residue before committing. A `.ts.orig` is not compiled, so it passes every gate invisibly.

**Record every resolution as you make it** — which units, which file, what was kept and what was dropped, and why. This is the one part of what lands that nobody reviewed: the reviewer approved unit diffs, and what ships is those diffs *plus* your resolutions. It goes in the integration PR body (step 5) and it is the only section there allowed to be verbose.

**3 — Run the full gate, once, on integration.**

Per the [full-gate](../skills/full-gate/SKILL.md) skill: `.claude/gate.sh --full` on `int/<run-id>`, verdict read from the `GATE-STEP:` lines and baseline-diffed against the default branch. Read that skill for the discovery order and the four ways a green read is wrong; do not re-derive them here.

A red gate is **fixed on integration**, not deferred. If a failure traces cleanly to one unit and the fix is more than a line, push the fix to that unit's branch and re-merge — that keeps the unit PR an honest record of its own work. Otherwise fix on integration and name the unit in the commit message. Do not open the integration PR over a red gate; an integration branch that looks landed and is red is the worst state this flow can produce, because the fleet is torn down and nobody owns it.

**4 — Collect the closing keywords.**

**A PR merged into `int/<run-id>` does not close its issues.** GitHub fires closing keywords only for PRs merged into the repository's **default** branch. Every `Closes #N` written into a unit PR body by `/verify-build` is therefore inert under this topology — well-formed, rendered as a cross-reference, and closing nothing. The failure has no tell anywhere: well-formed commits, PRs `MERGED`, gates green, and the only symptom is a backlog count nobody has a reason to read.

So collect the union of issues referenced across every unit PR, and carry them into the **integration** PR body — **one `closes` keyword per issue**, repeated. `Closes #56, closes #62, closes #63`. A bare list (`Closes #56, #62`) closes the first and turns the rest into mentions.

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

Units merged (and any skipped, with why) · conflict resolutions, counted · the gate verdict · the integration PR URL · issues closed vs. still open. Update `run.yaml` — `landedAt`, `integrationPr` — so a re-run is a no-op rather than a second attempt.

## Principles

- **Fresh session, always.** The fleet conversation holds the run's memory; this command needs only its bookkeeping. Reopening it to merge is the single largest avoidable cost in the fleet flow.
- **Conflicts resolved once, in one place.** The integration branch exists for exactly this. Any design that resolves the same conflict twice has lost the argument for having it.
- **The unit branch is the reviewed artifact.** Resolve into integration; never rebase what a human approved.
- **The gate runs once, where it can see something.** Cross-unit breakage is invisible per-unit by construction; N full gates buy less than one integration gate and cost N times as much.
- **Merged is not delivered, and merged is not closed.** A wrong-target merge and an inert closing keyword both report success. Each has an explicit assertion above; run them.
- **The integration PR records the landing, not the work.** Each unit PR remains the system of record for its own change — [verify-build](./verify-build.md)'s principle is unchanged, one level up.
- **Nothing is merged without `--land`.** Review gates the merge; the flag gates the default branch.
