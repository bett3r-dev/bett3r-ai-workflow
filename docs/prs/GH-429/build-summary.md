---
work_item: GH-429
plugin: bett3r-ai-workflow@0.99.0+c0b2f8d
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
    mode: sequential
    modeReason: worktrees-retired
    commit: c9afd79
    passed: true
    attempts: 2
    fixRounds:
      - { cause: design-silent, executor: fresh }
    verifier: pass
    redBeforeGreen: mutation
    postDesignDecisions: [D8, D9, D10, D11, D16, D24, D25, D26, D27, D28, D29, D30]
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
    mode: sequential
    modeReason: ready-alone
    commit: 6070edd
    passed: true
    attempts: 1
    fixRounds: []
    verifier: pass
    redBeforeGreen: mutation
    postDesignDecisions: [D31, D32, D33, D34, D35, D36, D37, D38]
---
## What shipped

**All five slices are landed and green.** This is the second `/build` invocation on the branch: the
first landed slices 1, 3 and 4 and stopped `blocked-on` with slice 2 escalated on the `pluginVersion`
contract; **the owner has since ruled on it**, and this invocation implemented the ruling, landed
slice 2, and landed slice 5. `/build` ran under **no brief** on both invocations — there is no
`.work/lane.yaml`, so Step 0's defaults apply (`sliceBudget: 3`, no `worktreePoolMax`, no
`verdictOnBranch`), and that is a legitimate single-`/plan` flow rather than a missing brief. This
invocation committed 2 slices, under its budget of 3.

**The escalation, and how it was resolved.** Design risk 4 asked `bin/fleet-loop` to refuse before
its first tick when the plugin version it resolved differed from the one `run.yaml` recorded. The
guard had no writer, and could not have one on the driver's side: nothing has loaded the plugin at
t0, and on a fresh run `run.yaml` does not exist yet — the orchestrator creates it in step 0, during
tick 1. Only the orchestrator can observe which plugin `claude -p` loaded, because it **is** the
loaded plugin. As shipped, `absent ⇒ refuse` would have refused 100% of real runs, and a missing
`run.yaml` returned `USAGE`, so the driver could not start a fresh run at all.

The owner's ruling (D24–D26): **the orchestrator is the writer, and the check moves to after tick 1.**
`/start-multi` step 0 records `pluginVersion` from its own loaded manifest, **unconditionally — every
tick, resume path included**, because a create-only write would brick every pre-existing run the
moment the `absent-after-tick-1 ⇒ refuse` arm went live. The driver now proceeds when the key is
absent at t0, treats a missing `run.yaml` as a fresh run, and after each tick refuses on a
tick-to-tick change, on a value still absent, and on `recorded != resolved`. **No backfill and no
migration**: a guessed value would make `resolved == recorded` and convert the guard into a false
pass, which is worse than no guard because it reads as evidence. Absent-then-self-heal is the
deliberate behaviour — one honestly-unguarded tick, then the guard is live.

The false claim that made the original design unbuildable is **deleted, not papered over**:
`resolved_version()` no longer says its manifest is the version `claude -p` will run. `PLUGIN_ROOT`
derives from `__file__` with no symlink resolution, so a by-path invocation reports the **branch's**
version. Under the new design the driver never needs the claim — it compares what the subprocess
**reported**, not what it predicts the subprocess will load.

**A plan premise proved false (D31), and the reason matters more than the fact.** `.work/slices.yaml`
records a plan-time correction asserting that `scripts/run-metrics.mjs` contains **zero** occurrences
of `fleet`, `agents.yaml` or `agentId` in 1569 lines. It contains 87 (63 lines), at HEAD and at the
base commit, and ships a full `--fleet` path. The "zero" is a **grep binary-classification
artifact** — `file(1)` calls the script binary data on 3 NUL bytes in 77,560, and ugrep matches
nothing in it while BSD/GNU grep, perl and python3 all match normally. This is the exact hazard
`scripts/test-flow-seams.sh:1050` already documents, and it fooled the plan. The plan's
**conclusion** — slice 5 is a prose change, not a script change — survives, but for the opposite
reason to the one recorded: not because the code is absent, but because the shipped `--fleet --all`
path is **already** correct about N orchestrator sessions. So `run-report.md`'s new prose documents
shipped behaviour rather than requesting it. **A future reader of the plan should not trust that
note**, and any repo-wide grep over this tree should assume `run-metrics.mjs` is invisible to ugrep.

**Mode.** Slices 2 and 5 both ran **sequentially in the main tree** this invocation. Slice 2's
original worktree, `…-pool/wt-1`, was **retired, not reset** — it holds the escalated work and its
base predates slice 3, so `commands/start-multi.md` there is the pre-slice-3 version the ruling's
edit could not be made against. Its tracked diff and three untracked files were **copied** forward
and applied at the branch tip; the worktree itself was never reset, cleaned or removed, and still
holds its work on disk. Slice 5 was `ready-alone` at its moment.

**Fix rounds across the whole ticket: 3, all `fresh` executors** (`SendMessage` to a subagent is not
available to this session, so no agent could be continued). By cause: **`design-silent` ×2** (slice 3's
teardown seam; slice 2's `pluginVersion` writer, which escalated to the owner rather than being
guessed) and **`oracle-wrong` ×1** (slice 4's one behavioural clause was deletable with the suite
green). First-pass green: 3 of 5. The `design-silent` pair is the cause worth a disposition — both
were seams where the design named a *mitigation* without naming its *writer*, and neither was
mechanical enough for a deterministic check, so both belong where the verifier reads.

**Evidence: RED→GREEN was structurally unavailable for both of this invocation's slices**, whose
deliverables are a guard and prose. Both were mutation-proved instead, per EVIDENCE.md §2, one
mutation per clause, each red **alone**:
- **Slice 2** — 8 mutations. The decisive one is the **permissive arm**: making "absent before tick 1
  ⇒ proceed" refuse again reddens 36 of 50 cases, so the arm most likely to rot into a silent skip
  cannot be quietly removed. Two arms are honestly weaker and named in D28: removing the
  `still-absent-after-tick-1` arm reddens exactly one *message* pin, and removing the
  `changed-tick-to-tick` arm reddens two, because in both cases the mismatch arm still stops the
  driver and only its diagnosis degrades. A tick-count pin is impossible for those two by
  construction, not by omission. **Fixture fidelity was the explicit bar** and it is met: nothing
  synthesizes a `pluginVersion:` line — `new_run()` writes a `run.yaml` without the key and the stub
  tick performs step 0's write itself. A synthesized line is precisely what hid the original defect.
- **Slice 5** — 16 mutations with three controls: a **vacuity control** (deleting ADR-013 withholds
  its 9 dependent pins rather than passing them vacuously), a **negative control** (planting the
  retired sentence in a *third* file reddens the census, so it catches new carriers and not just a
  revert), and a **traversal control** (a no-match census regex reddens a live positive control, so
  the guard is proven to reach real prose). The declared probe reddens **3** pins, not the 2 the
  executor reported (D36).

**Gates.** CI is disabled in this repo, so every gate ran locally and **SCOPED** (`sh .claude/gate.sh`);
`--full`/`--all` was never run, by rule. Final state on the branch: `GATE-MODE: --scoped`, `GATE: PASS`,
**26 steps PASS with one SKIP** — `flow-seams ✓ 542 passed` (481 at base, 527 before slice 5),
`fleet-loop ✓ 50 passed` under sh, dash and bash (a new gate step, mirrored from the workflow and
satisfied by `gate-drift ✓ 59`), `version-bump 0.92.0 → 0.99.0`, `artifact-links ✓ 111 links`,
`eval-coverage ✓ 16/16`, agent census `11` unchanged. The one SKIP is `xp-layer-hooks`, whose surface
this diff does not touch — **and a SKIP is not a pass**. The scoped run's blind spot, named: it
re-proves only the surfaces this diff names, and no census or ratchet that globs the tree counts
`bin/` entrypoints, gate steps, ADRs or command bodies, so the two guards that *do* move with this
diff (`gate-drift`, `validate-plugins`) were run by name and are green.

**Carry-forward for `/verify-build`** — re-verified against HEAD, not asserted from memory:
- **`pluginVersion` is resolved**, and the previous summary's statement that nothing on the branch
  writes the key is now obsolete: `commands/start-multi.md:29` writes it and the schema block carries
  it. The `fleet-loop.py:90-91` false-claim defect that summary reported as live is also fixed.
- **`scripts/run-metrics.mjs:369,486`** still carry singular "the orchestrator's session" docstrings.
  Pre-existing (`git log -L` pins both to `77957d4`), behaviourally inert, and excluded from slice 5's
  census by name with the reason in the guard's comment. A docstring sweep, not a defect (D32).
- **`plugins/bett3r-ai-workflow/commands/run-report.md` is at exactly 900 words**, ADR-012's ceiling,
  with **zero headroom** for the next editor (D35).
- **ADR-013 says `/design-multi`'s phase "is its `units[].step` enum"** three paragraphs before
  "there is no `step=` enum anywhere". Not a contradiction — the second is explicitly scoped to the
  verdict-line grammar and names both scopes it checked — but one clarifying word would stop a reader
  tripping.
- **`docs/prs/GH-429/design.md`** still carries two stale citations: `:46`/`:242` cite
  `TOKEN = re.compile(…)` at `lane-step-parse.py:64`, a surface slice 1 removed; and its F4 bullet
  attributes the `step: plan` sentence to `start-multi.md:73` when it lives at `agents/unit-lane.md:74`.
- **`.work/slices.yaml:23`** says `spendSoFar` where the shipped key is `spendToDate` — a stale plan
  comment; the ADR and `start-multi.md` are right.
- **`commands/start-multi.md:95`**'s parenthetical gloss enumerates two terminal arms while `:105`
  names three statuses, omitting `blocked` (Low; errs toward keeping a worktree).
- **`commands/start-multi.md:52`** records a cost ceiling without naming a unit, while the schema now
  says USD (Low).
- **D6 is now closed**: D11's widening of the `flow-seams` surface landed with slice 2, so a second
  copy of the verdict parser under `bin/`, `scripts/` or the lane-step fixtures no longer escapes a
  scoped gate.
- **`…-pool/wt-1` still exists and still holds slice 2's original uncommitted work.** Nothing in it
  was reset or removed, by instruction. It is now redundant — the work is landed as `c9afd79` — so it
  is safe for a human to tear down, but that is a human's call, not this run's.
- **No out-of-`yarn test` suites were flagged un-run**: this repo has no jest and no integration
  tier; every suite is a shell script the gate runs directly.
