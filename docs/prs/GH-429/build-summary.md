---
work_item: GH-429
plugin: bett3r-ai-workflow@0.97.0+0f602c0
base: d04a3cd
slices:
  - id: 1
    name: "A FLEET-STEP:v1 yield line is read by the one verdict parser (tracer bullet)"
    origin: plan
    mode: sequential
    modeReason: ready-alone
    commit: 77084c2
    passed: true
    attempts: 1
    fixRounds: []
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D1, D2, D3, D4, D5, D6]
  - id: 2
    name: "bin/fleet-loop ticks until the run is terminal and stops when the wave does not advance"
    origin: plan
    mode: worktree
    modeReason: null
    commit: null
    passed: false
    attempts: 1
    fixRounds: []
    verifier: escalate
    redBeforeGreen: true
    postDesignDecisions: [D8, D9, D10, D11, D16]
  - id: 3
    name: "/start-multi yields at wave completion, having pushed every started branch and released the lock"
    origin: plan
    mode: worktree
    modeReason: null
    commit: 35f1e83
    passed: true
    attempts: 2
    fixRounds:
      - { cause: design-silent, executor: fresh }
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D12, D13, D14, D15]
  - id: 4
    name: "/design-multi ends at the A/B and B/C phase boundaries"
    origin: plan
    mode: sequential
    modeReason: ready-alone
    commit: f9cf3af
    passed: true
    attempts: 2
    fixRounds:
      - { cause: oracle-wrong, executor: fresh }
    verifier: pass
    redBeforeGreen: true
    postDesignDecisions: [D17, D18, D19, D20, D21, D22, D23]
  - id: 5
    name: "ADR-013 and the attribution rule for a run with many orchestrator ticks"
    origin: plan
    mode: null
    modeReason: null
    commit: null
    passed: false
    attempts: 0
    fixRounds: []
    verifier: null
    redBeforeGreen: null
    postDesignDecisions: []
---
## What shipped

Three of five slices landed: the tracer bullet (1), `/start-multi`'s wave yield (3) and
`/design-multi`'s phase boundaries (4). **Slice 2 is ESCALATED and needs an owner ruling; slice 5
never started.** `/build` ran under **no brief** — there is no `.work/lane.yaml`, so Step 0's
defaults apply (`sliceBudget: 3`, no `worktreePoolMax`), and that is a legitimate single-`/plan`
flow rather than a missing brief. This invocation committed its three slices and stopped; the
outcome is `blocked-on` for slice 2, not a budget yield.

**The escalation (slice 2 — read this first).** `bin/fleet-loop`'s control flow is correct and
mutation-proven: the tick/stop/no-progress decisions each red under their own mutation, none hangs,
and the driver reads verdicts only through the shipped `bin/lane-step --marker FLEET-STEP` with no
second copy of the token regex. What escalates is **design risk 4's named mitigation**, on two
findings that compound. (1) The version guard has **no writer**: `pluginVersion` occurs nowhere in
the repo outside slice 2's own two files, the plan's contract note never lists this contract, and
slice 3's scope sentence actively forbids adding the key — so with `absent ⇒ refuse`, the driver
refuses 100% of real runs and re-invokes zero orchestrators. That is the reader-only contract
`scripts/test-flow-seams.sh:1086-1095` documents as invisible to every gate, and the suite only
looks green because its own fixture synthesizes a `pluginVersion:` line no producer writes. (2) The
claim at `fleet-loop.py:90-91` that the manifest it reads is "the version `claude -p` will actually
run, not the branch's" is **false by-path**: `PLUGIN_ROOT` comes from `__file__` with no symlink
resolution, so invoked by absolute path — the only invocation anything exercises — it reports the
branch's version. The dangerous direction is a false pass, where `run.yaml` records the branch
version while `claude -p` loads an older cached roster and the driver proceeds on the wrong roster
every tick. **The owner must rule on who writes the key and what is compared.** The verifier's
recommendation: the orchestrator writes `pluginVersion` from its own loaded manifest and the driver
compares tick-to-tick recorded values, which removes the PATH claim entirely; interim, `absent ⇒
warn-and-proceed` with its own scenario, `mismatch ⇒ refuse`. That fix lands in `commands/start-multi.md`
— slice 3's file — so it is a cross-slice seam, not an executor fix. **Slice 2's work is intact and
uncommitted in `/Users/tomasruiz/Documents/development/bett3r-ai-workflow-pool/wt-1`**; pool
teardown refused (`outcome=refused reason=dirty`) precisely to keep it, and that worktree must not
be reset or removed by hand.

**Mode.** Slice 1 ran sequentially in the main tree (`ready-alone`); slices 2 and 3 ran concurrently
in a two-worktree pool (`worktree-pool size` → `width=2 pool=2`, both reset at tip `798f03f` with
`--install ''`/`--build ''`, this repo having no install or build); slice 4 ran sequentially again,
since slice 2's escalation left it alone at its moment. The pool's `provisioner` agent dispatches
were skipped deliberately and recorded as D7.

**Fix rounds: 2, both `fresh` executors** (SendMessage is unavailable in this session, so no agent
could be continued). Slice 3: one `design-silent` round — the teardown seam. Slice 4: one
`oracle-wrong` round — the slice's one behavioural clause was deletable with the suite green.
First-pass green: 1 of 3 landed slices.

**The most valuable thing this run caught, twice.** A pin that greps a paragraph rather than the
line it must reach is green about something it does not touch. Slice 3's terminal-condition pin was
satisfied by a *neighbouring* Done line spelling the same phrase, and slice 4's one behavioural
obligation had no pin at all. Both were found by a deletion lens — delete the clause, watch the
suite stay green — not by reading the assertion. Every pin added after that point was
mutation-proved to red *alone*.

**A near-miss worth keeping (slice 3).** Precondition 1 ("push every started lane's branch") made
step 7's pre-existing removal condition ("branch is pushed, or terminally failed and acknowledged")
universally true, so a gate-red non-terminal lane's worktree would have been destroyed by
`git worktree remove` in the same tick — the exact tree the precondition exists to preserve.
Teardown is now gated on `terminal: true`; the set of removed worktrees is strictly smaller, and
nothing pinned that condition before (a grep for it in the suite returned zero).

**Gates.** CI is disabled in this repo, so every gate ran locally and **SCOPED** (`sh .claude/gate.sh`);
`--full`/`--all` was never run, by rule. Final state on the branch: `GATE: PASS`, `GATE-MODE: --scoped`,
`flow-seams ✓ 524 passed` (481 at base), `version-bump 0.92.0 → 0.97.0`, with `xp-layer-hooks` and
`version-gate-tests` SKIP — neither surface is touched by this diff, and a SKIP is not a pass. The
scoped run's blind spot, named: it re-proves only the surfaces this diff names, and these slices'
deliverables are largely *prose pinned by greps*, so a behavioural regression in how `/design-multi`
or `/start-multi` actually runs is invisible to every gate this repo has.

**Carry-forward for `/verify-build`** — verified against HEAD, not asserted from memory:
- **`pluginVersion`** — the blocking integration item above. Nothing on the branch writes the key.
- **`commands/run-report.md:22,32`** still asserts one orchestrator session per run, which slices 3
  and 4 falsify. This is design **risk 1**, labelled a gate-less seam; nothing goes red when it is
  wrong, the numbers are merely mis-attributed. It is **slice 5's** work and slice 5 never ran.
- **ADR-013 does not exist yet** (slice 5), and now owes `phases=` alongside `waves=`.
- **`docs/prs/GH-429/design.md`** carries two stale citations: `:46`/`:242` cite
  `TOKEN = re.compile(…)` at `lane-step-parse.py:64`, a surface slice 1 removed; and its F4 bullet
  attributes the `step: plan` sentence to `start-multi.md:73` when it lives at `agents/unit-lane.md:74`.
- **`commands/start-multi.md:95`**'s parenthetical gloss enumerates two terminal arms while `:105`
  names three statuses, omitting `blocked` (Low; errs toward keeping a worktree).
- **`commands/start-multi.md:52`** records a cost ceiling without naming a unit, while the schema
  now says USD (Low).
- A second copy of the verdict parser added under `hooks/`, `reference/`, root `scripts/*.py` or
  `docs/prs/*` would still SKIP `flow-seams` under a scoped gate (residual of D11's widening, which
  itself did not land — it lives in slice 2's worktree, so **D6 stays open on the branch**).
- **No out-of-`yarn test` suites were flagged un-run**: this repo has no jest and no integration
  tier; every suite is a shell script the gate runs directly.
