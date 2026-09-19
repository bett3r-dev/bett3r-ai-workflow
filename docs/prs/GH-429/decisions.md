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
