# A fleet orchestrator is a re-dispatchable tick, not a session — and the resume point is derived, never stored

After [ADR-012](./ADR-012-artifacts-carry-rules-the-ledger-carries-evidence.md) every *lane* context
is bounded. One term was not. A **step** runs in a `step-lane` that ends on its verdict line. A
**unit** runs in a `unit-lane` holding five dispatches, five verdicts and a state file. The
**orchestrator** — `/start-multi`, `/design-multi`, `/merge-multi` — was one context for a whole run:
every dispatch, every child-completion notification and its own reasoning, growing with the number of
unit events at a cost quadratic in its own turn count. ADR-012 thinned its command body, which is
per-turn cost, and changed nothing about its length.

**So the orchestrator ends.** `commands/start-multi.md` now opens its `## The tick boundary` section with
the rule in one line — *"You are a tick, not a session"* — and a shell driver, `bin/fleet-loop`, re-invokes a fresh
one per wave. `/design-multi` ends at its A/B and B/C phase boundaries the same way. Per-tick context
is bounded by one wave rather than by the fleet.

Nothing here was ever exponential. Growth in any single context is linear per turn and cost is
quadratic in turns; old fleets felt exponential because three multipliers stacked — inline command
bodies in the unit-lane, unbounded polling turns, and no context that ever ended on purpose. ADR-012
removed two. This is the third.

## The rule that makes resume safe: derive the progress, store only what no unit determines

A context that ends has to be able to answer *where did the run get to* from disk. The tempting
answer is to write the answer down — a `wavesDone:` counter, a `phase:` pointer — and it is the wrong
one, because the command already names the failure mode of exactly that: *"a state file that says
`step: plan` while the branch carries three slices"* is called the orchestrator's commonest misread,
and *git is the primary signal and the state file a hint*.

So the split, stated in `start-multi.md`'s step 4 of the yield:

* **Projections are derived, every tick.** Wave progress is `units[].wave` plus `step`/`status`,
  cross-checked against `git log origin/<default>..<each unit's branch>`. `/design-multi`'s phase is
  its `units[].step` enum. Neither is written to `run.yaml`, and a `wavesDone:` or `phase:` key there
  is a second, staler answer to a question the units already answer.
* **What no unit determines is stored, and only that.** `run.yaml` gains exactly two keys for the
  yield. `waveBudget` is a **policy input** — a ceiling nothing can compute from the units.
  `spendToDate` is an **accumulator**: cumulative spend is not a projection of `units[]` at all, and
  it is written as an addend at each wave boundary because after the yield no context is long enough
  to notice its own growth, which is what the cost stop's trigger used to be.

The distinction is the whole decision. A projection re-derived on a fresh context cannot be stale; an
accumulator cannot be re-derived at all. Everything else about a resumed tick follows from which of
the two a value is.

`pluginVersion` is stored for a third reason, and it is neither: it is an **observation only the
orchestrator can make**. `claude -p` resolves the plugin from the cache, so the copy that ticks may be
behind the branch — observed during this work, with a cache at `0.92.0` against a branch at `0.94.0`
whose roster the older copy did not have. The driver cannot resolve what `claude -p` will load and
does not try; `start-multi.md` records the version of *its own loaded manifest* on every tick, resume
included, and `scripts/fleet-loop.py` compares that recorded value with the version of the copy its
own launcher sits in, after each tick.

## The verdict grammar: three outcomes and a lease, not a `step=` enum

A yield needs a machine-readable *"I stopped, and the run is not done"*. The first proposal was a
fourth outcome word — a `yield` beside the three — and the reason it does not exist is worth recording
precisely, because the issue that asked for it named the wrong mechanism.

There are two real constraints, and neither is an enum of step names:

1. **The `OUTCOMES` table is exactly three values.** In the consuming scheduler
   (`remote-ai-agents`, `src/scheduler/verdict.ts:109`) `OUTCOMES` maps `success`, `gate-red` and
   `blocked-on` and nothing else; an unknown word returns `exitClass: 'infra'` with
   `infraReason: 'unknown-outcome'`. A fourth word is not rejected — it is silently reclassified as
   infrastructure, which is the reassuring direction [ADR-004](./ADR-004-a-step-reports-a-line-not-an-exit-code.md)
   exists to keep the contract out of.
2. **The second constraint is a lease, not a vocabulary.** `readStepResult` takes an `expectedStep`
   — the step the scheduler *leased* — and returns `infraReason: 'wrong-step'` when the line's
   `step=` disagrees (`verdict.ts:150-157`). **There is no `step=` enum anywhere.** Not in the
   scheduler, which compares against one leased value, and not in this plugin's
   `scripts/lane-step-parse.py`, which pins the marker word and the attribute grammar and no
   attribute's value. Rejecting a reused `LANE-STEP:v1 step=start-multi` because "the enum has no
   such step" would have been a true conclusion from a false premise; the real objection is that the
   orchestrator is not one of the steps the scheduler leases at all, so any lease its line collides
   with is one it should not have held.

What shipped follows from those two. A new marker word, `FLEET-STEP:v1`, reusing the three outcomes:
`FLEET-STEP:v1 outcome=success waves=<k>/<N> units=<t>/<u>`, where a yield is a **`success` whose
`waves=` is short of its total** — the idiom `/build` already uses one level down, where a short
`slices=` means the same thing. `lane-step-parse.py` took a `--marker NAME` parameter so the marker
word is the only thing that varies and every clause of the parse rule — the column-0 anchor, the
last-line-only rule, the end-of-line clause — is still written once. `/design-multi` spells its
phase boundaries in the same grammar with `phases=<k>/3`.

## What the driver may not become

`bin/fleet-loop` holds **no state but the previous tick's `waves=k/N`**, which is what makes it a
driver and not a second orchestrator. Everything it does with that number is a stopping rule: tick
again while `k` advances, stop at `k=N`, and stop with `blocked-on=fleet-no-progress` when `k` is
unchanged across two consecutive ticks — the guard `unit-lane`'s `/build` loop already proves one
level down. There is a tick cap too (`blocked-on=fleet-tick-cap`), because a no-progress guard only
catches a run that is *not* moving.

It reports plain prose rather than a verdict line of its own. A driver that emitted a `FLEET-LOOP:`
marker would be a third grammar for a reader nobody has written, and the run's verdict is already the
last tick's.

## The cost this decision moves rather than removes

Two figures, both named because neither is paid for by the yield:

* **The per-tick re-read floor is unmeasured.** Quadratic-in-turns is replaced by
  linear-in-waves × (re-read `run.yaml` + every `units/<id>.state.yaml` + the git cross-check). At 30
  units over 10 waves that floor is the new dominant term and no measurement of it exists.
* **Attribution is now N windows, not one.** `/run-report --fleet <run-dir> --all` measures a run by
  the orchestrator's sessions; with N ticks there are N of them. This is the seam with no gate behind
  it: nothing goes red when the attribution is wrong, the numbers are simply misread, which is why
  `commands/run-report.md` states the per-tick rule in its own words rather than leaving it implied.

## What this does not decide

* **`/merge-multi` does not yield.** It already runs in a fresh session by rule and its length is the
  fleet's unit count. A per-unit yield on this same pattern is plausible and is deliberately not
  decided here: nothing in this record licenses inventing one by analogy.
* **`--serial` never yields**, and that is stated in `reference/start-multi-serial.md`, the file the
  serial path actually reads.
* **What a `v1` reader does with a `vN` line** remains open in ADR-004 and is not settled here.

## Status

Accepted. Supersedes nothing. Extends ADR-004: `FLEET-STEP:v1` is the same contract one level up — a
line, never an exit code, and its absence is `infra`.
