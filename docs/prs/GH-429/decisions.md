# Post-design decisions — GH-429

Every decision made after the design was resolved. Append-only; ids are never reused.

## D1 — The uniqueness guard's needle moved from the `LANE-STEP:v(` literal to the marker-independent attribute clause
kind: deviation
step: build · slice: 1 · decidedBy: executor
sources: [code:lane_token_needle (scripts/test-flow-seams.sh), code:token (plugins/bett3r-ai-workflow/scripts/lane-step-parse.py), design:Scenarios/still one parser, human]
rejected: keep the literal needle — it was ALREADY RED at base (d04a3cd's docs/prs/GH-429/design.md:46, map.json:196 and map.html quote the regex verbatim), and after parameterisation the literal no longer occurs in the parser at all, so it would have become a guard over the empty set that passes silently
supersedes: —
Slice 1's structural scenario spelled the needle as a literal. The verifier independently reproduced the base-red state with `git archive d04a3cd` and confirmed both halves of the executor's claim, then mutation-checked the replacement: the new needle matches the production parser (positive control), catches a `FLEET-STEP` copy the old literal could not, and no longer matches a document that merely quotes the rule. Residual weakening, accepted: a second parser spelling a looser attribute clause would now escape. The gate "must stay green" is honoured in substance, not by the letter of the needle.

## D2 — The marker surface is a `--marker NAME` flag, not an env var or a second positional
kind: silent-seam
step: build · slice: 1 · decidedBy: executor
sources: [code:main (plugins/bett3r-ai-workflow/bin/lane-step), design:Behavior]
rejected: an env var (invisible at the call site) — a second positional (collides with the existing single-path contract)
supersedes: —
The slice said "asking for the FLEET-STEP marker" without naming a surface. A flag keeps the default path byte-identical for the five shipped callers, and the default is test-pinned: flipping `DEFAULT_MARKER` to `FLEET-STEP` reds ten assertions.

## D3 — A lone `--marker` with no value exits 2 rather than dying in a traceback
kind: silent-seam
step: build · slice: 1 · decidedBy: executor
sources: [code:main (plugins/bett3r-ai-workflow/scripts/lane-step-parse.py)]
rejected: treat it as a path — a traceback reads to a caller as `infra` rather than as its own usage error
supersedes: —
Unspecified by the slice. Shipped unasserted; recorded as D3 and as finding F4 below rather than pretending a test covers it.

## D4 — The FLEET trailing-prose assertion is shipped without a mutation that reds it alone
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:scripts/test-flow-seams.sh:626-635, code:scripts/fixtures/lane-step/README.md:86-90]
rejected: another fix round to make it independently load-bearing — the clause it guards is now provably shared (one `token()`, one `.match()`, one `\s*$`), and the pre-existing default-marker fixture reds under the same mutation
supersedes: —
Its comment claims it catches a parameterisation that loses a clause for every marker but the default; no mutation reds it alone, so that sentence is aspirational. Either soften it or name the divergence it uniquely kills.

## D5 — docs/prs/GH-429/design.md still cites a surface the slice removed
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:docs/prs/GH-429/design.md:46, code:docs/prs/GH-429/design.md:242]
rejected: amending the design doc inside slice 1 — out of the slice's touches, and the design is the committed record of what was decided, not of what shipped
supersedes: —
`:46` cites `TOKEN = re.compile(…)` at `lane-step-parse.py:64` and `:242` cites `sed -n '60,67p'` as the evidence that the marker is hardcoded. `TOKEN` no longer exists. Worth a one-line amendment in a later slice — and `:46` is the very text that made the old guard needle unusable (D1).

## D6 — The gate's `flow-seams` surface does not list the paths slices 2 and 3 touch
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:.claude/gate.sh:194]
rejected: widening the surface inside slice 1 — .claude/gate.sh is not in slice 1's touches; slice 2 already owns that file
supersedes: —
Pre-existing, not created here. `flow-seams` is scoped to `commands/*`, `agents/*`, `skills/*`, `docs/adr/*` and `scripts/test-flow-seams.sh`, but not to `plugins/bett3r-ai-workflow/scripts/*`, `bin/*` or `scripts/fixtures/lane-step/*`. Slice 1's suite ran only because it edited the test file; a future diff touching `lane-step-parse.py` alone would print `SKIP` for the only suite guarding it. Carried into slice 2, which edits `.claude/gate.sh`.

## D7 — The pool's worktrees were provisioned without dispatching the `provisioner` agent
kind: deviation
step: build · slice: — · decidedBy: orchestrator
sources: [code:.claude/gate.sh, code:plugins/bett3r-ai-workflow/bin/worktree-pool, human]
rejected: two serial `provisioner` dispatches — this repo has no package.json, no install and no build, so the agent's install/build half was a no-op and its remaining work (scrub inherited `.work/`, capture the baseline) is deterministic
supersedes: —
`worktree-pool provision 2` then `reset <wt> <branch> --install '' --build ''` per worktree, both verdicts read from their `WORKTREE-POOL:v1` lines (`outcome=provisioned`, `outcome=reset`, tip `798f03f`). Neither worktree carried an inherited `.work/`, checked directly. Recorded because the skill dispatches the agent unconditionally and this run did not.

## D8 — `bin/fleet-loop` takes its tick command as `--tick '<shell command>'`, with no default and no env fallback
kind: silent-seam
step: build · slice: 2 · decidedBy: executor
sources: [code:worktree-pool reset --install/--build, design:Behavior]
rejected: a default tick command — a guessed tick would invoke some other orchestrator
supersedes: —
Adjudicated ACCEPTED by the verifier: it mirrors the sibling script's idiom and both missing-argument cases are asserted.

## D9 — `bin/fleet-loop` stops with `blocked-on=fleet-tick-cap` at `tick_number >= N`, which the slice did not specify
kind: deviation
step: build · slice: 2 · decidedBy: executor
sources: [code:plugins/bett3r-ai-workflow/scripts/fleet-loop.py, design:Seams/flow diagram]
rejected: no cap — a `k` that oscillates (1/3, 2/3, 1/3, …) advances at every comparison and loops forever
supersedes: —
Extra behaviour beyond the slice, self-flagged. The verifier confirmed by mutation that the cap does not mask the no-progress guard (unmutated, no-progress fires at tick 2; the cap could not fire before tick 3) and that it is what turns the slice's probe into an assertion instead of a hang. ACCEPTED as good judgment.

## D10 — `bin/fleet-loop` reports plain `fleet-loop: …` prose, not a `FLEET-LOOP:v1` verdict line of its own
kind: deviation
step: build · slice: 2 · decidedBy: executor
sources: [code:bin/worktree-pool, code:bin/work-docs-path, code:bin/design-map, adr:ADR-004]
rejected: a third marker line — the executor's reason was that `blocked-on` cannot be an attribute KEY of the shipped grammar (keys are `[A-Za-z_][A-Za-z0-9_]*`)
supersedes: —
The verifier UPHELD this as a finding rather than accepting it: hyphens are legal in attribute VALUES (the repo ships a punctuated-value fixture), so `FLEET-LOOP:v1 outcome=stopped reason=no-progress ticks=3` would satisfy both, and every sibling `bin/` script ends in a `NAME:v1 …` line. Open coherence decision, carried with the escalation.

## D11 — The gate's `flow-seams` surface widening is correctly scoped, not too broad
kind: overruled
step: build · slice: 2 · decidedBy: verifier
sources: [code:.claude/gate.sh, code:scripts/test-flow-seams.sh (the uniqueness guard's read set)]
rejected: narrowing it back — the guard itself reads `$ROOT/scripts`, all of `$PLUGIN` and `$ROOT/docs`, so the widened surface is still narrower than what the suite actually inspects
supersedes: D6
The executor named the cost (many plugin diffs now run the 484-check suite that previously SKIPped). Residual, recorded: a second parser under `hooks/`, `reference/`, root `scripts/*.py` or `docs/prs/*` would still SKIP under a scoped gate. Note this decision lives in slice 2's worktree and did NOT land — D6 stays open on the branch.

## D12 — The tick number is derived as `1 + max(tick)` in agents.yaml, not stored in run.yaml
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [code:plugins/bett3r-ai-workflow/commands/start-multi.md, design:GH-429-F4]
rejected: a `tick:` counter in run.yaml — a third key, and a STORED PROJECTION, which is exactly what F4 forbids
supersedes: —
Verifier: ACCEPT, and the right call — deriving it from the file the orchestrator already writes keeps the projection/accumulator split intact, and it stays monotonic even if a tick dies mid-write.

## D13 — `spendToDate` and `waveBudget.ceiling` are denominated in USD, a unit no upstream artifact states
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [code:commands/start-multi.md:52 (records a ceiling, names no unit), design:risk 5]
rejected: leaving the addend unitless — design risk 5 is a NAMED MITIGATION, and an addend whose ticks may write different units sums to something silently meaningless, which is the accumulator failure the risk names
supersedes: —
Raised by the verifier as Finding 2 on the first pass and fixed in fix round 1; both keys now name USD and each is pinned by its own executed assertion. Follow-up (Low, not taken): step 2's `:52` prose would read better as "the ceiling you will spend, in USD".

## D14 — Teardown is gated on `terminal: true`, because precondition 1 makes "branch is pushed" universally true
kind: deviation
step: build · slice: 3 · decidedBy: verifier
sources: [code:commands/start-multi.md:95,99,107, code:commands/start-multi.md:77 (worktree recycling already gates on terminal)]
rejected: leaving step 7's pre-existing "branch is pushed, or terminally failed and acknowledged" condition — with every started branch now pushed at the boundary, a gate-red non-terminal lane's worktree qualified for `git worktree remove`, destroying the tree precondition 1 exists to preserve
supersedes: —
The first pass shipped this hole and the verifier constructed the repro; fix round 1 closed it. Set comparison, verified: old = `pushed ∨ (failed ∧ acked)`, new = `terminal ∧ pushed` — strictly FEWER worktrees removed, in the safe direction, and now consistent with `:77`, the one other destructive decision in the file. Newly pinned by three assertions; nothing pinned it before (a grep for `worktree remove|terminal: true` in the suite returned zero). Residue (Low): `:105` names three terminal statuses but `:95`'s parenthetical gloss enumerates two, omitting `blocked`.

## D15 — A pin that greps a whole paragraph was narrowed to the one line it must reach
kind: deviation
step: build · slice: 3 · decidedBy: executor
sources: [code:scripts/test-flow-seams.sh:3102-3131]
rejected: the paragraph-wide grep — probed, it produced ZERO reds, because step 7's Done line also spells `terminal: true`
supersedes: —
Recorded because it is a measured instance of the failure the probe rule exists for: green about something the assertion does not reach. The verifier re-ran the probe independently and confirmed the narrowed pin now reds, alone.

## D16 — Slice 2 is ESCALATED: design risk 4's version guard has no writer, and its platform claim is false by-path
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:plugins/bett3r-ai-workflow/scripts/fleet-loop.py:90-91,168-173, code:commands/start-multi.md:126-131, code:scripts/test-flow-seams.sh:1086-1095, design:risk 4, human]
rejected: landing it as-is — a driver that refuses 100% of real runs is the reader-only contract the plan's own contract note forbids, and no gate can see it (the suite's `new_run` helper synthesizes a `pluginVersion:` line no in-repo producer writes)
supersedes: —
The control flow is sound and mutation-proven (tick/stop/no-progress all red under their own mutations, none hanging). Two defects defeat risk 4's NAMED MITIGATION, so it cannot ship as a follow-up. (1) `pluginVersion` has no writer anywhere in the repo, and the plan's contract note does not list this contract, so no slice is assigned to write it — while slice 3's scope sentence actively forbids adding it. (2) `fleet-loop.py:90-91` claims the manifest it reads is "the version `claude -p` will actually run, not the branch's", but `PLUGIN_ROOT` derives from `__file__` with no symlink resolution, so invoked by absolute path — the only invocation anything exercises — it reports the BRANCH's version. The dangerous direction is a false pass: run.yaml recording the branch version while `claude -p` loads an older cached roster gives `resolved == recorded` and the driver proceeds on the wrong roster every tick. The owner must rule on who writes the key and what is compared; that lands in slice 3's file, so it is a cross-slice seam, not an executor fix. The verifier's recommendation: the orchestrator writes `pluginVersion` from its own loaded manifest and the driver compares tick-to-tick recorded values, which removes the need for the PATH claim entirely; interim, absent ⇒ warn-and-proceed (with its own scenario), mismatch ⇒ refuse. Slice 2's work is preserved uncommitted in the pool worktree named in build-summary.md.

## D17 — /design-multi's A/B boundary emits a verdict line the design never specified
kind: silent-seam
step: build · slice: 4 · decidedBy: executor
sources: [adr:ADR-004, code:plugins/bett3r-ai-workflow/scripts/lane-step-parse.py, design:GH-429-F5, code:scripts/test-flow-seams.sh (Seam I's outcome census)]
rejected: prose alone — "the human opens Phase B" stated as a request is something a driver can ignore, and enforcement is what F5 asks for
supersedes: —
`FLEET-STEP:v1 outcome=blocked-on blockedOn=awaiting-owner-sitting phases=k/N units=t/u`. The verifier ruled this NOT scope creep but the correct enforcement: by ADR-004 a context that ends must print a line, `blocked-on` is one of the three sanctioned outcomes and reads as a stop, and slice 1's parameterisation is what makes it readable at all. Both the parse claim and the census acceptance were re-verified independently against the current parser.

## D18 — The new attribute is spelled `phases=`, not `phase=` and not `waves=`
kind: silent-seam
step: build · slice: 4 · decidedBy: executor
sources: [code:plugins/bett3r-ai-workflow/scripts/lane-step-parse.py (the attribute grammar), design:GH-429-F4]
rejected: `phase=` — one character from the forbidden `phase:` state key, and confusable with it. `waves=` — false, because phases are not waves
supersedes: —
Unnamed by the design. ADR-013 (slice 5) will need to carry `phases=` alongside `waves=`.

## D19 — The B/C boundary is the same KIND of end as A/B, but a plain `success`, so a driver may reopen Phase C
kind: silent-seam
step: build · slice: 4 · decidedBy: executor
sources: [design:GH-429-F5 option A ("Phase C is tracker-writer waves … the part that most resembles a wave loop and least needs the sitting's context")]
rejected: making Phase C human-only too — it would contradict the design's own reason for splitting B/C off
supersedes: —
The design decides who opens Phase B (the human, never a driver) and is silent on Phase C. The verifier found the choice better-grounded than the executor claimed: `success phases=2/3` short of the total reads as tick-again under F3's own idiom, while A/B's `blocked-on` reads as a stop.

## D20 — `--serial` never yields, and that question is now recorded as DECIDED
kind: silent-seam
step: build · slice: 4 · decidedBy: executor
sources: [code:plugins/bett3r-ai-workflow/reference/start-multi-serial.md, code:commands/start-multi.md:117, design:Unspecified seams ("must either yield … or say in its own words that it never yields. Which of the two is not decided here.")]
rejected: inheriting the wave yield silently — the design explicitly delegated the choice and required the answer be stated in the artifact's own words
supersedes: —
The reason is serial's own mechanics: it holds a worktree open across every step, so there is no point at which it holds nothing. Slice 3 had landed a sentence calling the question undecided; fix round 1 corrected that one clause, so the branch no longer asserts both sides. Serial also now stamps every agents.yaml row `tick: 1`, closing slice 3's Low carry-forward.

## D21 — The sitting must write terminal answers as `<run>/answers/` rows BEFORE the B/C context ends
kind: silent-seam
step: build · slice: 4 · decidedBy: executor
sources: [code:commands/design-multi.md:83 (Step 5.2, inside Step 5 — Phase C at :78), design:GH-429-F5]
rejected: leaving Step 5.2 as the only writer — it sits inside Phase C, so without this obligation a terminal answer exists only in the ended sitting and "Phase C restarts from `<run>/answers/`" is false for exactly those answers
supersedes: —
The slice's one behavioural addition beyond wording. Verified correct and in scope by the verifier — which also found it UNPINNED (deletable with 522 green); fix round 1 gave it its own assertion, mutation-proved to red alone.

## D22 — A pin was accepted as brittle-but-fail-closed rather than loosened
kind: overruled
step: build · slice: 4 · decidedBy: verifier
sources: [code:scripts/test-flow-seams.sh:3190-3191]
rejected: a looser plain-prose needle — it would risk staying green while the obligation is weakened, which is the dangerous direction
supersedes: —
D21's needle spans both load-bearing halves (the `map: <S>` shape and the `**before** this context ends` deadline) and so is sensitive to cosmetic re-punctuation. Ruled a noise risk, not a correctness risk: it fails closed, and the author re-syncs.

## D23 — No census guards against a future artifact re-opening the `--serial` question
kind: shipped-finding
step: build · slice: 4 · decidedBy: verifier
sources: [code:docs/prs/GH-429/design.md:184, code:plugins/bett3r-ai-workflow/reference/start-multi-serial.md]
rejected: an absence census over "not decided"/"undecided"/"open question" near `serial` — it would flag design.md:184, the very sentence that GRANTS the decision, so the guard would redden on correct files
supersedes: —
The verifier confirmed the reason is real rather than convenient and swept the corpus: no rival open-question claim about `--serial` exists today. Residual and named: a future third file re-opening it is uncaught. Not a mitigation the design leans on.

## D24 — The orchestrator writes `pluginVersion`, and the driver's check moves to after tick 1
kind: silent-seam
step: build · slice: 2 · decidedBy: human
sources: [code:plugins/bett3r-ai-workflow/commands/start-multi.md:29, code:plugins/bett3r-ai-workflow/scripts/fleet-loop.py, design:risk 4, human]
rejected: the driver resolving the loaded version itself — it structurally cannot. `PLUGIN_ROOT` derives from `__file__` with no symlink resolution, so a by-path invocation reports the BRANCH's version, and nothing has loaded the plugin at t0 anyway; also rejected: papering the gap over with `realpath`
supersedes: —
The escalation that stopped this slice. Design risk 4 asked the driver to refuse on a version mismatch before the first tick, but on a fresh run `run.yaml` does not exist yet — the orchestrator creates it in step 0, during tick 1 — so the pre-tick check refused 100% of real runs, and a missing `run.yaml` returned USAGE, which meant the driver could not start a fresh run at all. Only the orchestrator can observe which plugin `claude -p` loaded, because it IS the loaded plugin. The owner ruled: the orchestrator is the writer, and the comparison happens after each tick — `recorded` against the driver's `resolved`, and `recorded` tick-to-tick.

## D25 — Slice 2 edits slice 3's `commands/start-multi.md`, by the owner's explicit ruling
kind: deviation
step: build · slice: 2 · decidedBy: human
sources: [code:plugins/bett3r-ai-workflow/commands/start-multi.md:29,127, human]
rejected: a sixth slice for the writer — it would land the guard (slice 2) before the producer it reads, leaving a shipped refusal arm with nothing writing the field
supersedes: —
A deliberate cross-slice seam, not scope creep: the guard and its producer must land in one commit or the `absent after tick 1 ⇒ refuse` arm is live against a field no artifact writes. The write is UNCONDITIONAL — every tick, resume path included — because a create-only write would brick every pre-existing run, and the pin is deliberately on the unconditional half rather than the key's name (mutation M8: weakening it to "when you create it" reddens 1 of 527 alone).

## D26 — `pluginVersion` is NOT backfilled into existing run.yaml files, and no migration is added
kind: deviation
step: build · slice: 2 · decidedBy: human
sources: [code:plugins/bett3r-ai-workflow/scripts/fleet-loop.py, human]
rejected: backfilling the branch's version into existing runs — a guessed value makes `resolved == recorded` and converts the guard into a false pass, which is worse than no guard because it reads as evidence
supersedes: —
Absent-then-self-heal is the chosen behaviour: one honestly-unguarded tick, then the orchestrator's own write makes the guard live. The driver opens `run.yaml` read-only.

## D27 — The version check runs before the verdict is parsed, so a terminal tick cannot bypass it
kind: deviation
step: build · slice: 2 · decidedBy: executor
sources: [code:plugins/bett3r-ai-workflow/scripts/fleet-loop.py:214-216, design:risk 4]
rejected: checking after the verdict is read — a `waves=N/N` terminal tick would then exit 0 unchecked
supersedes: —
The ruling said "after each tick" without ordering the check against the verdict parse. Cost, accepted: a run whose LAST tick has a mismatched version exits 1 instead of 0. Verifier adjudicated it as the conservative reading — a terminal verdict produced by the wrong plugin copy is not this run's to act on.

## D28 — The `recorded changed tick-to-tick` arm is a diagnosis refinement, not extra stopping power
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:plugins/bett3r-ai-workflow/scripts/fleet-loop.py, code:scripts/test-fleet-loop.sh]
rejected: dropping the arm as redundant — it is the only arm that can be true when BOTH values differ from `resolved`, and it is the more specific diagnosis
supersedes: —
If `recorded` changes between ticks, at least one value also differs from `resolved`, so the mismatch arm would fire anyway. The `changed` arm is therefore checked FIRST and pinned on the driver's own words (`pluginVersion changed mid-run`, `previous tick recorded=…`) rather than on the fact of stopping. Named and residual: mutation M4 reddens 2 message pins and no tick count, and M2 (removing the `still absent after tick 1` arm) reddens exactly 1 message pin — the driver still stops, only its diagnosis degrades. A tick-count pin is impossible for these two arms by construction, not by omission.

## D29 — A literally-false docstring claim about PyYAML was corrected rather than shipped
kind: overruled
step: build · slice: 2 · decidedBy: verifier
sources: [code:plugins/bett3r-ai-workflow/scripts/fleet-loop.py:83-86, code:plugins/bett3r-ai-workflow/scripts/design-map.py:1377]
rejected: shipping "PyYAML is not a dependency of this plugin's scripts" — `design-map.py` imports it, lazily, so the sentence is false in its literal half
supersedes: —
Reworded to "not an unconditional dependency", naming the one lazy importer. The load-bearing half was already true and verified (`.claude/gate.sh` treats a missing PyYAML as INCONCLUSIVE rather than installing it). Corrected because this slice's whole ruling was about deleting a false claim from a docstring rather than papering over it; shipping a second one in the same file would be incoherent.

## D30 — A `STUB_VERSION` ordering fragility in the new suite is accepted and named
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:scripts/test-fleet-loop.sh:268-276]
rejected: adding a per-case guard against inherited stub state — judged not worth the harness complexity for a 50-case single-file suite
supersedes: —
`stub-trailing-prose.sh` does not call `arm` and inherits the previous case's exported `STUB_VERSION`. Verified correct today (run-c2's `arm` resets it to the real manifest version immediately before), but order-fragile if cases are reordered. Follow-up named, not taken: have the trailing-prose stub read `$VERSION` directly.

## D31 — The plan's "run-metrics.mjs has no `--fleet` path" premise is FALSE; the conclusion survives for a different reason
kind: false-premise
step: build · slice: 5 · decidedBy: verifier
sources: [code:plugins/bett3r-ai-workflow/scripts/run-metrics.mjs:1378-1405,1421, code:scripts/test-flow-seams.sh:1050, design:risk 1]
rejected: writing the assertion against run-metrics.mjs that the false premise would have justified — and equally, letting the premise stand because the conclusion it supported was right
supersedes: —
`.work/slices.yaml`'s plan-time correction states that run-metrics.mjs contains ZERO occurrences of `fleet`, `agents.yaml` or `agentId` in 1569 lines, checked at d04a3cd. It contains 87 (63 lines), at HEAD and at d04a3cd, and ships `fleetRunDirs()`, `readAgentsYaml()`, `findFleetLane()`, `collectFleetUnit()`, `fleetWholeRun()` and `renderFleet()`. The "zero" is a grep binary-classification artifact — `file(1)` reports the script as binary data on 3 NUL bytes in 77,560, and ugrep matches nothing in it while BSD/GNU grep, perl and python3 all match normally. This is the exact hazard scripts/test-flow-seams.sh:1050 already documents, and it fooled the plan. The plan's CONCLUSION — that slice 5 is a prose/contract change, not a script change — survives, but for the opposite reason to the one recorded: not because the code is absent, but because the shipped `--fleet --all` path is ALREADY correct about N orchestrator sessions (`parents` is a Set of parent session files, `orchOnly.sessions = orchFiles.length`, spans unioned then netted of unit windows, and the count is rendered). So run-report.md's new prose documents shipped behaviour rather than requesting it.

## D32 — Two singular docstrings in run-metrics.mjs are left standing as a named follow-up
kind: shipped-finding
step: build · slice: 5 · decidedBy: verifier
sources: [code:plugins/bett3r-ai-workflow/scripts/run-metrics.mjs:369,486, code:scripts/test-flow-seams.sh (Seam K census exclusion)]
rejected: widening the census to catch them — it would redden a file this slice deliberately writes no assertion about, and the fix is a docstring sweep, not this slice's behaviour
supersedes: —
Both lines still say a lane runs as a subagent of the ORCHESTRATOR's session. `git log -L` pins both to 77957d4, so they are pre-existing and out of this slice's scope; the same file's `--fleet --all` header already reads plural, and `:486`'s own sentence continues "No branch filtering", so behaviour is unaffected. Excluded from the census by full path with the reason stated in the guard's comment. Residual and named: the retired wording survives in two stale comments.

## D33 — The census pins the absence of a rewording, not of the falsehood itself
kind: shipped-finding
step: build · slice: 5 · decidedBy: verifier
sources: [code:scripts/test-flow-seams.sh (Seam K), code:plugins/bett3r-ai-workflow/hooks/lane-git-guard.sh:9, code:plugins/bett3r-ai-workflow/hooks/README.md:23]
rejected: widening the needle to `subagent of the orchestrator's session` — lane-git-guard.sh:9 and hooks/README.md:23 use that phrase for a nesting/cwd fact that stays true per tick, so the wider guard would have forced edits to two CORRECT hook comments
supersedes: —
"A fleet unit's records carry one orchestrator's branch" is not actually wrong per tick — the branch is the same across ticks. The genuinely retired claim is the singular SESSION, retired here as "the orchestrator TICK that dispatched it, so its records carry THAT tick's branch". The census therefore guards a phrase that is not itself the falsehood: a rewording guard in ADR-012's sense. Accepted because the load-bearing gate is the POSITIVE pin, which reddens under the slice's probe; the census's own controls (a planted third carrier, and a no-match regex) both fire.

## D34 — LEDGER.md is excluded from the census by name
kind: waiver
step: build · slice: 5 · decidedBy: executor
sources: [adr:ADR-012, code:docs/LEDGER.md:1711,1714]
rejected: amending LEDGER entry 1710-1714 with a retire condition — ADR-012 is explicit that the ledger carries evidence verbatim, and rewriting an entry to match a later change falsifies the record
supersedes: —
The precedent is the existing ADR-003 exclusion. The exclusion cannot hide anything, because the excluded file is simultaneously the census's LIVE positive control for traversal — hiding a carrier would break the control.

## D35 — Three passages were trimmed from run-report.md that the slice did not ask for
kind: deviation
step: build · slice: 5 · decidedBy: executor
sources: [code:plugins/bett3r-ai-workflow/commands/run-report.md:22, code:plugins/bett3r-ai-workflow/scripts/run-metrics.mjs:1426, adr:ADR-012]
rejected: exceeding ADR-012's 900-word ceiling to leave the prose untouched
supersedes: —
The file was 898 words at base and the slice's additions had to be paid for. Adjudicated trim by trim by the verifier: (a) the Step-2 "a class dominated by one very long call is flagged, not summed" sentence was not merely duplicative but MISPLACED — `BIGGEST SINGLE CALLS` is rendered only by `renderFleet` (`--fleet --all`), while the sentence sat in the `--agents` paragraph describing a table `--agents` does not print; its single home is :22 and the interpretation half ships in the output header itself. (b) "so any branch on disk can be reported" is already in the frontmatter description. (c) compression of a paragraph the slice rewrote anyway. No rule lost. Named for the next editor: the file is now at exactly 900 words with ZERO headroom.

## D36 — The declared probe reddens three pins, not one, and the sentence was not split to change that
kind: deviation
step: build · slice: 5 · decidedBy: verifier
sources: [code:plugins/bett3r-ai-workflow/commands/run-report.md (the new bullet), code:scripts/test-flow-seams.sh (Seam K)]
rejected: splitting the bullet into three sentences so the probe reddens exactly one assertion — three clauses of one rule belong in one reader-facing sentence
supersedes: —
The bullet carries the N-windows clause, the approximation label and the agents.yaml two-lifetimes clause, and the suite's `present` helper is line-oriented, so the probe reddens all three pins. The executor reported 2; the verifier re-ran it and measured 3. Each clause additionally has its own isolating mutation, so no clause rests on the shared probe alone.

## D37 — ADR-013 records the rejected fourth outcome word without spelling its token
kind: deviation
step: build · slice: 5 · decidedBy: executor
sources: [code:scripts/test-flow-seams.sh (the slice-1 census), code:docs/adr/ADR-013-a-fleet-orchestrator-is-a-tick-not-a-session.md]
rejected: spelling the literal token — a slice-1 guard forbids it outside docs/prs/GH-429/, and minting it in an ADR would defeat the guard that keeps the vocabulary at three
supersedes: —
Reworded to "a fourth outcome word — a `yield` beside the three". The ADR records the rejected option without the literal appearing in a live artifact.

## D38 — The "five leased steps" count was dropped rather than propagated
kind: deviation
step: build · slice: 5 · decidedBy: executor
sources: [code:../remote-ai-agents/src/ledger/runs.ts:12]
rejected: writing "five" to match the phrasing used elsewhere in this ticket's prose — `RunStep` is six values (start|plan|build|verify-build|merge|lane)
supersedes: —
The count was removed from the ADR instead. The verifier swept the branch: no surviving artifact says "five leased steps", and every remaining "five steps" refers to the PIPELINE's five, which is accurate — `lane` is the wrapper, not a pipeline step.
