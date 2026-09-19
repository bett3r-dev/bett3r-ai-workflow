# LEDGER — the evidence behind the rules

This file is the evidence behind the rules in this plugin's commands, agents and skills: the
incidents, measurements and war stories that used to sit inside those artifacts as instruction
text. It is grouped by the artifact each rule lived in at commit `c75ba88`, and every
`evidence:` field is quoted verbatim from that commit (paths are relative to
`plugins/bett3r-ai-workflow/`).

No agent loads this file, and nothing under `commands/`, `agents/` or `skills/` links to it.
Humans read it; `/evolve` and `/capture-learnings` append to it. `scripts/check-needles.py`
asserts presence corpus-wide under `plugins/**/*.md`, so a needle may be satisfied by a sentence
here once its wording leaves an artifact. Each entry's `rule:` should have a live home in an
artifact; an entry whose rule has no home is a rule that died, and `expiry:` names the
condition that retires it on purpose.


## commands/build.md

### modeReason names the Step 2 branch that sent a slice to the main tree
- rule: Every main-tree slice records `modeReason:` naming which Step 2 branch made it sequential; `ready-alone` when it was the only slice ready.
- source: commands/build.md:32; commands/build.md:280 at c75ba88
- evidence:
  > a plan the pool sized at width 4 once ran every slice sequentially with nothing saying why.
  >
  > - `mode:` is `worktree` for a slice run in the pool, `sequential` for one run in the main tree; `modeReason:` names which Step 2 branch sent a `sequential` slice there — `ready-alone` when it was the only slice ready at its moment.
- recorded: 2026-09-13
- expiry: the pool is removed, or build-summary.md drops the mode/modeReason keys

### Reset before every take, unconditionally
- rule: A pool worktree is reset (install and build) before every slice it takes, whether or not anything changed; a warm tree costs time, never correctness.
- source: commands/build.md:40 at c75ba88
- evidence:
  > 3. **Reset before every take, unconditionally.** Before a worktree takes a slice — its first included — run `worktree-pool reset <worktree> <task-branch> --install '<cmd>' --build '<cmd>'` and require `outcome=reset`. Its install and build run **whether or not anything changed**, and that is the point: a reused tree inherits stale `.tsbuildinfo` and stray compiled `.js` shadowing sources, and a warm tree must cost time, never correctness (`remote-ai-agents` D6). Never skip it because the lockfile did not move.
- recorded: 2026-09-12
- expiry: worktree-pool reset stops being the single definition of readiness, or a reused tree can be proven free of stale build output without rebuilding

### An escalated slice's worktree is retired, never reset
- rule: A worktree whose slice did not land takes no further slice until teardown: a new-files-only slice is untracked files that a reset's dirty check does not count.
- source: commands/build.md:41 at c75ba88
- evidence:
  > **A worktree whose slice did not land takes no further slice until teardown** — whether the slice escalated at the gate, exhausted its fix rounds, or conflicted at the land. Its reset would switch and `git clean -fd` the slice's work away, and a slice that escalated at the gate has **no commit** to protect it: a new-files-only slice is nothing but untracked files, which the reset's dirty check deliberately does not count. So it is retired, never reset, and teardown's refusal is what keeps that work on disk for a human.
- recorded: 2026-09-13
- expiry: the reset's dirty check counts untracked files

### The verifier stays on opus and is never traded down
- rule: The verifier runs on opus on every dispatch; it is the only gate positioned to catch a confidently-wrong oracle and is ~11% of a run's cost.
- source: commands/build.md:63; agents/unit-lane.md:231 at c75ba88
- evidence:
  > | `verifier` | `opus` — **never downgrade this one** | It is the only gate positioned to catch a confidently-wrong oracle, and cheapening it is the corner that ships defects. It is also ~11% of a run's cost, so there is nothing to win here. |
  >
  > `sonnet`, and **the verifier stays on `opus` and is never traded down**.
- recorded: 2026-08-13
- expiry: a cheaper model is shown to catch the confidently-wrong oracle at the same rate, or the verifier's share of run cost changes materially

### Every dispatch names its slice; a continued agent never takes another slice
- rule: Every dispatch description names `slice <id>` (fix rounds included), and a continued agent stays on the slice it was dispatched for, because run-metrics attributes by that description alone.
- source: commands/build.md:66 at c75ba88
- evidence:
  > **Every dispatch description names `slice <id>`** — executor, test-runner, scope-check and verifier alike, fix rounds included (e.g. `slice 3 executor fix round 1`). `run-metrics` attributes a dispatch to its slice by a regex over that description and nothing else (`d.match(/slice\s*(\d+)/i)` in `fixRoundLedger`, `scripts/run-metrics.mjs`); a description that does not name the slice is counted `unattributed`, and its tokens and passes belong to no slice. A continued agent (Step 3, *Fix rounds*) keeps the description it was dispatched with and each resume counts as one more pass, so **a continued agent never takes another slice**: its whole transcript stays attributed to the first — one verifier resumed across ten slices billed all ten to slice 1.
- recorded: 2026-09-13
- expiry: run-metrics attributes dispatches by something other than the description regex

### Effort is a pre-flight decision, not a per-dispatch one
- rule: Effort is inherited from the session and chosen once before the run; model routing is stated per dispatch, effort is not.
- source: commands/start-multi.md:81; commands/build.md:68 at c75ba88
- evidence:
  > **Effort is a pre-flight decision.** It is inherited from the session that launched the fleet and cannot be routed per dispatch — so it is chosen once, for every lane at once. Model routing *can* be stated, and the lane's brief states it.
  >
  > Effort is **not** settable per dispatch — it is inherited from the session (`/effort`), so it is a decision you make once before running, not per agent. `/build` is the mechanical phase and does not need the session's design-grade effort; `xhigh` here buys little and is where the token bill concentrates.
- recorded: 2026-09-04
- expiry: the harness allows effort to be set per Agent dispatch

### Pass scenarios verbatim: oracle-wrong is 41% of fix rounds
- rule: The executor receives every field of every slice scenario verbatim; a paraphrase re-opens the oracle-wrong gap that each fix round re-pays with a fresh executor context.
- source: commands/build.md:135 at c75ba88
- evidence:
  > **Pass `scenarios` verbatim — every field of every one.** It is the slice's oracle in the one form that cannot be quietly re-read, and paraphrasing it here re-opens the exact gap it closes: `oracle-wrong` is 41% of all classified fix rounds, and each one costs a fresh executor context.
- recorded: 2026-09-19
- expiry: the oracle-wrong share of classified fix rounds falls to the level of ripple (~6%)

### A green pin is a floor, not equivalence: four live divergences
- rule: A behaviour-unchanged gate needs an old-vs-new differential harness whose corpus is derived from the change; a pin or golden that stays green is a floor.
- source: commands/build.md:141 at c75ba88
- evidence:
  > Pins stayed green through four live divergences in one fleet, two of which would have shipped a garbage ERP element and an infinite retry.
- recorded: 2026-09-05
- expiry: none known

### Its corpus lacked the shape: a zero delta is evidence only about shapes the corpus contains
- rule: Before reading a measured delta as a pass, state which shapes relevant to the change the corpus does not contain; a fixture that abbreviates away the coincidence it guards discriminates nothing.
- source: EVIDENCE.md:19; commands/build.md:145 at c75ba88
- evidence:
  > - **Its corpus lacked the shape.** A zero delta over a pinned corpus, a golden file or a fixture set is evidence only about shapes that corpus *contains*. Before reading a delta as a pass, state **which shapes relevant to this change the corpus does not contain** — one sentence, answerable from the fixtures you just wrote. A fixture that abbreviates away the coincidence it exists to guard (two path segments that share a name, shortened to one) looks like coverage and discriminates nothing.
  >
  > **When the accept criterion is a measured delta over a fixed corpus** (a pinned repo, a golden file, a benchmark set), the slice must state *which shapes relevant to this change the corpus does not contain* before the delta is read as a pass. Any shape named there is covered by a fixture, or the delta is recorded as **silent about it**. A zero delta over a corpus lacking the shape reads as the strongest possible evidence and is, in the limit, none — and it is most dangerous precisely where it is most attractive, on a change whose risk register names a forbidden direction.
- recorded: 2026-08-08
- expiry: none known

### An undiscriminating RED is no evidence
- rule: A RED that is a hang, timeout, crash before the assertion, import or compile error, empty collection or skipped suite is indistinguishable from a broken harness; re-dispatch for a RED that prints expected vs actual.
- source: commands/build.md:152; agents/executor.md:31 at c75ba88
- evidence:
  > - **undiscriminating** oracle — the RED was a hang, timeout, crash before the assertion, import or compile error, an empty collection the assertion never ran over, or a skipped suite. It is indistinguishable from a broken harness, so it is no evidence that the test can tell right from wrong; re-dispatch for a RED that prints expected vs actual;
  >
  > **A valid RED DISCRIMINATES: it is an assertion failure that prints the expected and the actual value.** A failure caused by a typo, a missing import, an unresolved path, a compile error, a hang or timeout, a crash before the assertion, an empty collection the assertion never ran over, or a suite that was skipped, is **not** a valid RED — fix the test until the only reason it fails is the missing behavior, then proceed. Capture the failure message; you must report it as RED evidence. A test you never watched fail proves nothing.
- recorded: 2026-09-19
- expiry: none known

### Nothing collects a new artifact kind: two hooks passed nine gates without executing
- rule: When a slice adds a new artifact kind, check the runner's actual glob or path list; if nothing collects it, the slice ships the oracle and its CI wiring in the same PR.
- source: commands/build.md:167; EVIDENCE.md:15 at c75ba88
- evidence:
  > From inside a slice a green gate table looks exactly like coverage (EVIDENCE.md (`../EVIDENCE.md`) §1, *it never ran*) — one new plugin with two hooks passed all nine of a repo's gates without a single line of it executing.
  >
  > And a runner **hardcoded to named paths** collects nothing from a new artifact *kind* — a new plugin, a new hook, a new directory — so a whole subsystem ships with every gate green, and green correctly.
- recorded: 2026-09-06
- expiry: none known

### Tree-counting guards are blind to a related-tests sweep
- rule: A change that adds or removes a file of a kind something counts runs the census and ratchet guards by name, and the ratchet moves in the same commit as the counted surface.
- source: commands/build.md:168; skills/full-gate/SKILL.md:113 at c75ba88
- evidence:
  > Composition roots, operations, grants, deployment units, registry nodes — the tests that pin those counts glob the tree and import nothing, so the slice's own tests and any related-tests sweep are blind to them by construction, and a slice lands **red at HEAD** for the next slice (or a sibling lane) to discover. The ratchet moves **in the same commit** as the counted surface.
  >
  > - **Tests that COUNT the tree are invisible to a related-tests sweep.** Census and ratchet guards (composition roots, operation tiers, grant counts, deployment-unit census) glob the filesystem and import nothing, so `--findRelatedTests` has no edge to them by construction — a 407-suite related sweep was green while the branch was red on a count pinned at 21. A change that **adds or removes a file of a kind something counts** runs those guards explicitly, or the full suite once, before it is called good.
- recorded: 2026-09-06
- expiry: the host gate's scoped mode selects tree-counting guards from the diff

### Out-of-oracle ripple: TV1-1969's trigger change and its carry-forward
- rule: When a slice changes a wire contract, grep callers repo-wide including integration, e2e and fixture files excluded from the default run, then run them or flag them un-run; verify the carry-forward against HEAD before handing it to /verify-build.
- source: commands/build.md:170; commands/build.md:287 at c75ba88
- evidence:
  > (Real miss: TV1-1969 changed a dispatcher's trigger event; three pre-existing integration suites still encoded the old topology and were red at HEAD, but none were in `yarn test`, so the dual gate never saw them.)
  >
  > (Real miss: TV1-1969's summary named only one of three broken suites and mis-attributed it — the real recovery-semantics break was in a different file.)
- recorded: 2026-07-12
- expiry: none known

### Never git checkout a path to undo a probe: a suite went 77 to 68
- rule: Undo a probe edit from a kept copy (`cp` out, `cp` back); never `git checkout`/`restore` a path while the slice is uncommitted, and check whose tree this is before acting in a shared checkout.
- source: commands/build.md:172 at c75ba88
- evidence:
  > It has fired: a suite went 77 → 68 and was recovered only from a verifier's scratch rsync copy, by luck. Concurrent sessions in one checkout are the sibling case — before acting, check whose tree this is (`git status`, `git branch --show-current`), because another session cutting branches across it destroys untracked work with no warning of any kind.
- recorded: 2026-09-13
- expiry: lane-git-guard.sh blocks the command in every lane; the prose then keeps only the sanctioned alternative

### A fix round is evidence the slice was mis-routed
- rule: A slice whose first pass ran on sonnet moves to opus for its fix round.
- source: commands/build.md:176 at c75ba88
- evidence:
  > Move the executor to `opus` if the first pass ran on `sonnet` — a fix round is the evidence that slice was mis-routed.
- recorded: 2026-09-13
- expiry: none known

### Every fix round is classified, in one line, before it is dispatched
- rule: Classify each fix round (oracle-wrong, design-silent, ripple, invariant, mis-routed, flake, environment) before dispatching it; a recurring cause is owed a disposition: mechanical gets a deterministic check, judgement goes where the verifier reads.
- source: commands/build.md:177 at c75ba88
- evidence:
  > - **Every fix round is classified, in one line, before it is dispatched.** A fix round is the single most expensive event in this loop, so the rate is worth driving down, and it cannot be driven down without knowing which of these it was: `oracle-wrong` (the test encoded the wrong rule) · `design-silent` (the slice under-specified a seam the executor had to guess) · `ripple` (something outside the slice's surface broke) · `invariant` (the repo rule was not followed) · `mis-routed` (too cheap a model) · `flake` (timing or load — green idle, untouched by the diff) · `environment` (a test that cannot collect or run for a reason outside the slice). Carry the tally into the Step 5 summary and the PR body. **Fix-round *rate* is already measured** — `/run-report` prints first-pass green per `/build` invocation — but the rate alone names no fix; the classification is what turns 43%-not-green into a change to `/plan` or to a slice's `gates`. **And a cause that keeps recurring is owed a disposition, not another mention in a retro:** classify it — mechanical (a fixed syntactic pattern, a banned API, an import shape, a file-location rule) gets a **deterministic check, full stop**; only a genuine judgement call gets prose, and then it goes where the *verifier* reads, never into the executor's brief, because the executor is under the most context pressure at exactly the moment it would have to remember. `/capture-learnings` step 1b owns this; a host repo that keeps a disposition ledger (this plugin's own repo keeps `docs/causes.md`, gated by `scripts/check-repeat-causes.py`) makes it red-until-done rather than remembered.
- recorded: 2026-09-19
- expiry: none known

### Fix rounds hand the findings back: TV2-21's 10 rounds re-paid the whole gate
- rule: A fix round continues the executor and verifier with the findings, the round's diff and the previous report instead of re-paying a fresh executor, test run, scope-check and full verifier pass.
- source: commands/build.md:181 at c75ba88
- evidence:
  > On TV2-21 all 10 fix rounds came from verifier findings and none from a red test, yet each re-paid a fresh executor, a test re-run, a scope-check and an opus verifier re-reading every rule — 9 h 30 m for 6 of 8 slices.
- recorded: 2026-09-13
- expiry: none known

### passes: true in the same turn as the commit; the flag is the resume point
- rule: Set `passes: true` (and the fleet state file's sha) in the same turn as the slice commit; commit per slice, because a resumed run re-executes any committed slice left `passes: false`.
- source: commands/build.md:203; commands/build.md:224 at c75ba88
- evidence:
  > **The flag is the resume point.** A resumed agent decides what to redo from it, so a committed slice left `passes: false` gets **re-executed** — including the subtle reversals that cost the most to get right the first time. This is not bookkeeping and it is not hypothetical: a transport error has killed four lanes in the same second, and one lane sat on six committed slices with a state file reading `slicesDone: 1`.
  >
  > Git is the record — per-slice commits are **crash insurance**, not tidiness, and batching three slices before committing turns any transport blip into total-progress loss.
- recorded: 2026-08-08
- expiry: none known

### Re-read the file after an edit; a matched-nothing fix-up printed success
- rule: After editing `.work/slices.yaml`, re-read it; do not infer the edit's effect from the edit's own success output.
- source: commands/build.md:207 at c75ba88
- evidence:
  > Then **re-read the file.** Do not infer the edit's effect from the edit's own success output — a fix-up regex that matched nothing on an indentation mismatch still printed success.
- recorded: 2026-08-08
- expiry: none known

### Push every slice: the branch exists in one local worktree and nowhere else
- rule: Push the branch right after each slice's flag is set (after the land, in a pool); a cost stop, a rate-limit kill or a reclaimed worktree otherwise loses every green slice already paid for.
- source: commands/build.md:209; commands/start-multi.md:55 at c75ba88
- evidence:
  > Until `/verify-build` step 6 the branch exists in **one local worktree and nowhere else**, so a lane stopped for cost, killed by a rate limit, or running in a worktree that gets reclaimed loses every green slice it already paid for. A slice costs minutes to earn and a push costs seconds, and the fleet's teardown guard (`/start-multi` step 7, *only a worktree whose branch is pushed*) is only protective because the branch **is** pushed by then.
  >
  > But a lane that has not reached `/verify-build` **has not pushed**: its commits exist in one local worktree and nowhere else. So a cost stop means *stop dispatching*, never *tear down* — `git push` each started lane's branch before you stop, and keep its worktree. Teardown's "only a pushed branch" guard (step 7) is what stands between an unpushed lane and losing every slice it paid for.
- recorded: 2026-09-18
- expiry: none known

### Yield at a slice boundary: 66.72M weighted tokens against 3.26M
- rule: A step runs in a fresh context and ends; /build yields at a slice boundary once its sliceBudget (denominated in committed slices, the one unit a step can count from inside) is spent, and the caller re-dispatches it on an empty context.
- source: commands/build.md:215; agents/unit-lane.md:95-104; agents/step-lane.md:27-38; agents/provisioner.md:171 at c75ba88
- evidence:
  > The measurement it exists for: a lane that drove nine slices in one context cost **66.72M weighted tokens, 89% of it cache read**, while the same work restarted on a fresh context at a slice boundary cost **3.26M against 35M**.
  >
  > **Why, in one measurement.** A lane that ran all five steps in its own context
  > cost **66.72M weighted tokens over 9.7 hours** for +2164/−259 lines, **89% of it
  > cache read**: the context re-reading its own history on every turn, so slice 1's
  > executor report was still being re-sent during `/verify-build`. On the same
  > fleet, the same work handed to a fresh context at a step boundary cost **3.26M
  > against 35M**. The saving is not the dispatch, it is the **ending** — a context
  > that ends stops being re-read — and it compounds, because what comes back to you
  > is one line instead of five steps of transcript. **Your own context must stay
  > small**: five dispatches, five verdicts, your state file. If you find yourself
  > reading a step's output, you have re-created the thing this shape deletes.
  >
  > A measured fleet lane that ran all five steps in one context cost **66.72M
  > weighted tokens over 9.7 hours** for +2164/−259 lines, **89% of it cache read** —
  > the context re-reading its own history on every turn. On the same fleet, the
  > same work handed to a fresh context at a step boundary cost **3.26M against
  > 35M**. That is the entire reason this agent is a separate dispatch and not a
  > paragraph in `unit-lane`.
  >
  > The saving is not the dispatch; it is the **ending**. A context that ends stops
  > being re-read. So: **one step, then stop.** If you notice the next step is
  > obviously runnable, that is not your call — say so in your prose and stop
  > anyway. A step-lane that helpfully ran two steps has rebuilt the thing this
  > agent was created to delete.
  >
  > `sliceBudget` is the lane's **context ceiling, expressed in the one unit a step can actually count.** A step cannot see its own token usage — that is measured afterwards by `run-metrics`, which is too late to act on — so the budget is denominated in committed slices, which are countable from inside and are the only clean resume point `/build` has. Three is the default because the measured failure was a lane that drove nine slices in one context for 66.72M weighted tokens, 89% of it cache read, against 3.26M for the same work restarted fresh at a slice boundary.
- recorded: 2026-09-18
- expiry: a step can read its own context size, so the ceiling can be denominated in tokens

### sliceBudget counts slices, the bill is context: $0.67 versus $43
- rule: Yield at a slice boundary on either the slice budget or a context bound (~150k tokens, observable as ~100 turns or a slice at three or more fix rounds), whichever trips first; yield early on suspicion.
- source: commands/build.md:219; commands/build.md:221; commands/build.md:221 at c75ba88
- evidence:
  > a measured 2-slice lane carrying `sliceBudget: 3` could never yield, and ran its context to **410k tokens and 167.9M cache reads** without once crossing a rule.
  >
  > At roughly **150k tokens of context, stop at the next boundary** even with budget left — that is where re-read cost starts dominating everything else you do, and measured fleet spend concentrates there: lanes that stayed under it cost **$0.67 each**, lanes that crossed it cost **$43**.
  >
  > You cannot read your own context size directly, so treat these as the observable that stands in for it, and trust the first one that trips: your own turn count past **~100**, a slice that has taken **three or more fix rounds**, or any point where re-reading your history feels like most of what a turn does. **Yield early on suspicion, not late on proof** — a fresh context costs one dispatch, while a wrong guess in the other direction is paid on every remaining turn of the run.
- recorded: 2026-09-19
- expiry: the harness exposes context size to the agent directly

### The orchestrator is the single writer of decisions.md and build-summary.md
- rule: Executors, verifiers and pool workers report decisions and facts in their result; only the /build orchestrator writes the committed record, in the main tree, or every cherry-pick of a pool land conflicts.
- source: commands/build.md:230 at c75ba88
- evidence:
  > **The orchestrator is the single writer of `decisions.md` and `build-summary.md`** — Step 2's *Workers never write the record* rule, extended from `slices.yaml` to both files. Executors, verifiers and pool workers never write `decisions.md` or `build-summary.md`: they **report** each decision and fact in their result, and you write it in the main tree. In a pool this is not style — every worker appending to one file would make every cherry-pick conflict.
- recorded: 2026-09-12
- expiry: none known

### No confidence field in decisions.md
- rule: A decision entry records what was consulted (`sources`) and never a self-rated confidence; quality is measured by a later entry that `supersedes` it.
- source: commands/build.md:244 at c75ba88
- evidence:
  > There is **no confidence field**, and none is to be added: a self-rated confidence is uncalibrated and not comparable across models. How good a decision was is measured by outcome — a later entry that `supersedes` it.
- recorded: 2026-09-12
- expiry: a calibrated, cross-model-comparable confidence measure exists

### Name a model on every dispatch
- rule: An unnamed model is the session's, the most expensive available; every dispatch names one from the routing table.
- source: commands/build.md:303; commands/build.md:56 at c75ba88
- evidence:
  > **Name a model on every dispatch** — an unnamed one is the session's, the most expensive available.
  >
  > An agent that names no model inherits the session's, which is the most expensive one you have. **Name the model on every dispatch**, from this policy — the roles differ by more than an order of magnitude in what judgment they actually need:
- recorded: 2026-09-13
- expiry: the harness default for an unnamed subagent model stops being the session model

### Context length is the bill: cache reads were 97% of raw tokens
- rule: Keep command output out of agent contexts, keep each agent to one slice, and hand findings back instead of re-paying a context; speeding up the repo's own commands is not a lever.
- source: commands/build.md:305 at c75ba88
- evidence:
  > - **Context length is the bill, not thinking depth.** On a measured fleet run, cache reads were **97% of raw tokens** and 68% of the cost-weighted total; output was 11%. What makes a run expensive is how much context each turn re-sends, so the levers that matter are: keep command output out of agent contexts (redirect + `tail`), keep each agent to one slice, and hand findings back instead of re-paying a context for them. Speeding up the repo's own commands is *not* one of them — build/test/typecheck/generate/lint together were 12% of agent active time.
- recorded: 2026-09-13
- expiry: a re-measured fleet run shows a different cost split

### Redirect + tail, never pipe: `… | tail` reports tail's status
- rule: Read a gate's pass from the runner's own summary line, never from a piped command's exit code; a run with no parsed summary is inconclusive.
- source: commands/build.md:147; skills/full-gate/SKILL.md:44; EVIDENCE.md:70 at c75ba88
- evidence:
  > It must pass — where "pass" is read from jest's own summary line, **never from a piped command's exit code** (`… | tail` reports `tail`'s status, not jest's, so a red run surfaces as exit 0). A run with no parsed `Tests:` summary is **inconclusive** — treat it as non-runnable, not a pass.
  >
  > - **The script must not pipe its own steps.** `yarn test | tail -30` reports `tail`'s status; a 33-suite-red run surfaces as exit 0. Use `set -o pipefail`, or capture into a log and read `${PIPESTATUS[0]}`.
  >
  > - **`$?` after a pipeline or a redirect-then-echo is the last command's**, not the tool's: `yarn gate > log; echo "EXIT: $?"` printed 0 under a log ending `GATE FAILED`. Capture `rc=$?` on its own line, or `${PIPESTATUS[0]}`, and judge on the tool's printed verdict.
- recorded: 2026-09-13
- expiry: none known

## commands/verify-build.md

### A lane never bumps plugin.json; the fleet bumps once on integration
- rule: In a gateDeferred lane the version-bump step reports SKIP and the PR body names the deferral; N lanes bumping guarantee manifest conflicts.
- source: commands/verify-build.md:30 at c75ba88
- evidence:
  > the fleet does one bump per plugin on the integration branch, so a lane never bumps `plugin.json` (N lanes bumping guarantee manifest conflicts and a version meaningless on int).
- recorded: 2026-09-17
- expiry: none known

### Fail-fast CI hides later steps: a known-red baseline hid the version gate
- rule: On a red CI run, open the step list, enumerate the steps the red one prevented, and run each locally by name; a collapsed `gh pr checks` line is not a reading of the run.
- source: commands/verify-build.md:34; EVIDENCE.md:15 at c75ba88
- evidence:
  > `gh pr checks` collapses a whole workflow to one line, and a job that fail-fasted reports every later step as `skipped` (EVIDENCE.md (`../EVIDENCE.md`) §1, *it never ran*).
  >
  > A **fail-fast** runner ends the job at its first red step and reports every later step as `skipped`; on a run already headlined `fail`, nothing distinguishes "this gate passed" from "this gate was never reached" without opening the step list, and *which* gates are lost depends only on their order in the file, not on what the diff touched (a known-red baseline once hid the version gate from two PRs).
- recorded: 2026-09-06
- expiry: none known

### Resolve the true base first: 509 files instead of ~67
- rule: Diff against the branch's real fork point (the integration branch under a fleet), and sanity-check the file count against the plan's `touches:` union before reviewing.
- source: commands/verify-build.md:38 at c75ba88
- evidence:
  > Diffing against a stale `master` silently inflates the scope (a real case: 509 files / +68k/−46k instead of ~67 files) and the coherence review runs against the wrong diff — a *silent* scope error, no command errors.
- recorded: 2026-07-06
- expiry: none known

### Sweep: a deleted subsystem left a live admin route
- rule: A deletion proves zero live callers across every repo, because a broken caller in a sibling package still compiles.
- source: commands/verify-build.md:60 at c75ba88
- evidence:
  > | **deletes** a symbol / route / config field / subsystem | zero live callers across **every** repo — a broken caller in a sibling package still compiles that package fine | a deleted bitmap subsystem left a live admin route → runtime 404, plus a debug tool and dead config, all green |
- recorded: 2026-08-08
- expiry: none known

### Sweep: a widened signature fixed one site; 7 integration suites kept the old shape
- rule: A changed exported signature is checked against every caller including integration, e2e and fixture files excluded from the default run.
- source: commands/verify-build.md:61 at c75ba88
- evidence:
  > | changes an **exported signature** | every caller matches, **including** `*.integration.test.ts` / e2e / fixtures excluded from the default run — then run those suites or flag them un-run | a widened arg fixed the one prod site; 7 integration suites kept passing the old shape, invisible to `yarn test` |
- recorded: 2026-08-08
- expiry: none known

### Sweep: a read-model key change broke 19 integration suites used as a fixture
- rule: A changed key property or persisted field name enumerates every consumer outside the owning module and migrates them to one shared helper with a guard test.
- source: commands/verify-build.md:62 at c75ba88
- evidence:
  > | changes a read model's **key property**, a persisted field name, or anything that changes what `readById` / a pushed-down filter resolves | enumerate every consumer of that collection **outside the owning module** (`grep -rn "<table_name>"`) and check each one's access shape — key-based, filter-based, scan-and-match; migrate them to **one shared helper** plus a guard test on the old shape, not N call-site edits | the module's own ~21 suites and its integration oracle stayed green while 19 integration suites in four unrelated subsystems used the table as a de-facto fixture and got `null`; two hours were spent attributing it, one of them to machine contention |
- recorded: 2026-09-05
- expiry: none known

### Sweep: templates are generators of future code; a seeder read an empty set
- rule: A deleted or redefined credential, header or env contract is swept through templates and skills that emit code using it, and a template references a helper rather than inlining the literal.
- source: commands/verify-build.md:63 at c75ba88
- evidence:
  > | deletes or redefines a **credential, header, auth mode or env contract** | grep the **templates and skills** that emit code using it — `.claude/skills/**`, plugin skills, scaffolding scripts, `docs/**` code fences, README snippets — and fix them in the same PR; a template that emits a credential should reference a helper, never inline the literal | a template is a generator of future code: it has *authors*, not callers, so every caller-shaped sweep returns clean. A seeder built from the stale one authenticated, got a 200, and read an empty set |
- recorded: 2026-09-05
- expiry: none known

### Sweep: a new reader of a persisted table reasons about rows, not control flow
- rule: For a new reader of an already-persisted collection, enumerate every other writer and prove the key space cannot select their rows.
- source: commands/verify-build.md:64 at c75ba88
- evidence:
  > | adds a **new reader** of an already-persisted table / index / collection | reason about *what the query can return*, not when it runs: enumerate **every other writer** and prove this key space cannot select their rows, or narrow it until it can't | the safety argument is phrased as control flow ("only runs when X failed", "byte-identical for existing callers"). Control flow is about your code; the rows belong to someone else |
- recorded: 2026-08-08
- expiry: none known

### Sweep: a pure rename rehydrated the aggregate to accounts["undefined"]
- rule: A rename or removal of a persisted field ships an upcaster or version bump, with a test exercising a pre-change row, and names the changed path that has no test.
- source: commands/verify-build.md:65; agents/verifier.md:38 at c75ba88
- evidence:
  > | touches **event schemas**, **persisted field names**, or **idempotency/dedup records** | (1) a rename/removal ships an upcaster or version bump; (2) rows written *before* this diff still work, with a test that exercises one; (3) name the changed path that has no test | a "pure rename" rehydrated the aggregate to `accounts["undefined"]`; a reversal keyed off a field pre-enrichment rows lacked |
  >
  > - **Schema evolution** — does a renamed/removed persisted field ship an upcaster or event-type version bump? (A "rename" that touches event/aggregate-state fields is evolution, not a rename — old-shaped events rehydrate to `undefined`.)
- recorded: 2026-08-08
- expiry: none known

### Sweep: migrate-on-read restamped a v99 file down
- rule: Reads and writes agree per version: recognized-legacy migrates on write, genuinely-newer refuses typed, and both directions are tested.
- source: commands/verify-build.md:66 at c75ba88
- evidence:
  > | has **migrate-on-read** for a persisted format | reads and writes agree per version: recognized-legacy **migrates on write** (never dead-ends the session), genuinely-newer **refuses, typed** — and both directions are tested | a file that rendered everywhere refused every write; the fold restamped a v99 file *down*, the exact loss its own comment claimed was closed |
- recorded: 2026-08-08
- expiry: none known

### Sweep: a stale canary WARNed on every no-op batch, twice
- rule: An adjusted total fixes every other site comparing against the unadjusted value and collapses the computation into one exported function; a sweep firing twice on one site means the earlier remedy was too shallow.
- source: commands/verify-build.md:67 at c75ba88
- evidence:
  > | introduces an **adjustment to a total / count / threshold** | every *other* site comparing against the **unadjusted** value (`< total`, `>= totalItems`) is fixed — and if more than one site computes the adjusted value, **collapse them into one exported function** | a stale canary WARNed on every no-op batch. Fixing only the arithmetic left the duplication, and the next skip-bucket re-broke it at the same line two weeks later. **A sweep firing twice on one site means the earlier remedy was too shallow** |
- recorded: 2026-08-08
- expiry: none known

### Sweep: a mechanical guard disarmed by a sibling surface forwarding author: 'human'
- rule: A mechanical guard names the field its dispatch condition reads and stamps it at every surface that can set it; never validate the claim.
- source: commands/verify-build.md:68 at c75ba88
- evidence:
  > | introduces a **mechanical guard** (conflict, tenancy, rate, permission) | name the field its dispatch condition reads, then enumerate **every surface that can set it** — tool schemas, HTTP bodies, message payloads, defaults. Stamp at each surface; never validate the claim | one frontend hard-stamped `author: 'human'` with a comment on why spoofing was impossible; the sibling MCP surface forwarded it as an optional parameter, disarming the guard entirely |
- recorded: 2026-08-08
- expiry: none known

### Sweep: a cross-tenant reconcile passed build, drift and a green integration test
- rule: An on-demand operate-over-my-rows endpoint derives the tenant from the authenticated user and pushes it into the filter; build the two-tenant repro, because single-tenant harnesses cannot see the class.
- source: commands/verify-build.md:69; agents/verifier.md:45 at c75ba88
- evidence:
  > | ships an **on-demand "operate over my rows" endpoint** | the tenant is derived from the authenticated user and pushed into the query filter — never from an optional body field, never a system-wide scan for an authed caller (cron/system paths legitimately stay unscoped). Build the two-tenant repro | single-tenant harnesses cannot see it: build, `generate:check` and a green Postgres integration test all passed a cross-tenant reconcile |
  >
  > Single-tenant harnesses cannot see this class, so build + typecheck + a green integration test are all compatible with a cross-tenant leak.
- recorded: 2026-08-08
- expiry: none known

### Sweep: the two directions of a reversible operation took different write paths
- rule: A reversible operation proves its inverse on the real adapter with its write semantics stated; a forward-green gate says nothing about the other direction.
- source: commands/verify-build.md:70; EVIDENCE.md:17 at c75ba88
- evidence:
  > | implements a **reversible operation** | the **inverse** on the real adapter too, with its write semantics stated. A forward-green gate — or an inherited "verified on Postgres" — says nothing about the other direction | the two directions took different write paths: a dot-path write forward, a whole-row merge back, which could not drop the keys the forward pass baked |
  >
  > - **It ran the other direction.** A reversible operation (suspend/resume, apply/undo, migrate-on-read vs on-write) usually takes two *different* write paths — one a merge, one a replace; one a dot-path, one a whole-row rebuild. Forward-green is not evidence about the inverse.
- recorded: 2026-08-08
- expiry: none known

### Sweep: a drift gate resolved a stale compiled .js beside the .ts
- rule: When a codegen/drift gate asserts something verifiably false in the source, suspect its inputs before editing the source.
- source: commands/verify-build.md:71 at c75ba88
- evidence:
  > | adds endpoints / operations / policies / registry nodes | run the repo's **own** codegen/drift gate (`generate:check`, `generate-all` + `git status`) and read its real verdict. Composition drift exists only once the slices are assembled, so no per-slice gate sees it | if the gate asserts something you can verify is false in the source, **suspect its inputs before editing the source** — it resolved through `paths` and loaded a stale compiled `.js` sitting beside the `.ts` |
- recorded: 2026-08-08
- expiry: none known

### Sweep: a seventh contradicting site 72 lines below a line the PR had just fixed
- rule: A claim correction sweeps the belief in synonyms, not the literal string, and re-sweeps every file the PR itself edited.
- source: commands/verify-build.md:72 at c75ba88
- evidence:
  > | **corrects a claim** or removes a duplication | sweep the **belief in synonyms**, not the literal string, and **re-sweep every file this PR itself edited** | a literal `git log -S` found 4 sites; synonyms found 2 more and the whole-PR pass found a seventh **72 lines below a line the PR had just fixed** — shipping a self-contradicting file is worse than fixing neither |
- recorded: 2026-08-08
- expiry: none known

### Sweep: added files appear in no conflict list; a PCI oracle merged green testing nothing
- rule: A merge-in enumerates what the other side added (`--diff-filter=A`), intersects it with what this side modified, and reads the assertions of every added test on that intersection.
- source: commands/verify-build.md:73 at c75ba88
- evidence:
  > | merges another branch in | enumerate what the **other side added** (`git diff --diff-filter=A --name-only <base>...<theirs>`), intersect with what **this** side modified, and read the assertions of every added test/fixture on that intersection | new files conflict with nothing, so they appear in no conflict list — an added PCI oracle merged green against a prop API this branch had replaced, still committed, still collecting, testing nothing |
- recorded: 2026-08-08
- expiry: none known

### Sweep: a later slice stopped holding all three watched files when one had degraded safely
- rule: When a later slice removes a protection, state what the earlier slice covers and what the removal applies to; a non-empty difference is the finding.
- source: commands/verify-build.md:74 at c75ba88
- evidence:
  > | a later slice **removes a protection** an earlier slice made unnecessary | state the two sets — what the earlier slice actually covers, what the removal is applied to — and the difference. Non-empty difference *is* the finding | one slice made *one* watched file degrade safely; the next stopped holding **all three**, and the third was still client-fatal |
- recorded: 2026-08-08
- expiry: none known

### Sweep: a guarantee credited to a deep merge came from an outbox concurrency:1
- rule: A stated framework mechanism is verified against framework source before it reaches the PR body.
- source: commands/verify-build.md:75 at c75ba88
- evidence:
  > | asserts **why** a guarantee holds by naming a framework mechanism | verify the claim against framework source-of-truth **before it reaches the PR body**; correct it in place | an oracle and comment credited a deep merge; the guarantee actually came from an outbox `concurrency:1` and was topology-dependent. Behaviour green, stated reason wrong |
- recorded: 2026-08-08
- expiry: none known

### Sweep: a tracer bypassed a P0 a later commit had already fixed
- rule: Skipped, xfail and tracer blocks citing a blocker are re-validated against HEAD.
- source: commands/verify-build.md:76 at c75ba88
- evidence:
  > | carries **skipped / `xfail` / tracer** blocks citing a blocker | re-validate each rationale against `HEAD` — a later slice may have fixed the cited blocker, leaving the path uncovered and the comment lying | a tracer bypassed a "P0" that a later commit on the same branch had already fixed |
- recorded: 2026-08-08
- expiry: none known

### Sweep: a by-position refill and a stream trim composed into a silent-drop window
- rule: Cross-slice composition is reasoned pairwise over every invariant, cursor or floor more than one slice touches; both slices individually correct is the signature of a composition finding.
- source: commands/verify-build.md:77; commands/verify-build.md:52 at c75ba88
- evidence:
  > | — (always) **cross-slice composition** | enumerate the invariants / cursors / floors more than one slice touches; reason about each **pairwise** interaction, especially where one slice *advances* what another *reads* or *trims* against (the gate from Step 2 covers the whole diff; this row is about *why* it is green) | a by-position refill and a stream trim were each correct and composed into a silent-drop window |
  >
  > The rest are the one class with **no per-slice gate at all: composition** — two slices individually correct, the defect in the seam between them. "Both slices were individually correct" is the *signature* of a real composition finding, never a reason to downgrade it.
- recorded: 2026-08-14
- expiry: none known

### Sweep: a NUL sentinel in a .ts literal passed 8/8 and made the diff unreviewable
- rule: `Bin` in the diff-stat on a hand-authored source path is a hard finding; `grep` returning nothing on a file you just edited is the earlier tell. Prefer plain visible separators.
- source: commands/verify-build.md:78; agents/executor.md:43 at c75ba88
- evidence:
  > | — (always) **`Bin` in the diff-stat** on a hand-authored source path | treat as a hard finding, not noise. `git diff --numstat` emits `-\t-\t<path>`; locate with `grep -aPn '[\x00-\x08\x0e-\x1f]'` | a NUL sentinel in a `.ts` string literal compiled, passed 8/8 integration tests, and made the whole file's diff unreviewable on a diff-is-the-deliverable ticket. Earlier tell: **`grep` returning nothing on a file you just edited** is a binary-classification symptom, not an answer — run `file` |
  >
  > - **Prefer plain, visible separators in string literals.** A control byte as a "collision-proof" sentinel makes git classify the file as binary — the diff becomes `Bin NNN bytes` and unreviewable, while build and tests stay green because the byte is behavior-invisible. If `grep` returns nothing on a file you just edited and expected to match, that is a binary-classification symptom, not an answer: run `file <path>` (`data` rather than `… text` confirms it).
- recorded: 2026-08-08
- expiry: none known

### Adjudicate sweep reports, never re-run them; a clean verdict is a claim
- rule: Dispatch sweeps on sonnet with the row each owns; when two reports disagree, read the primary source; a clean verdict is a claim to disprove like any other.
- source: commands/verify-build.md:91 at c75ba88
- evidence:
  > (A "this is already fixed, lines 35-60 type-prefix every import" verdict had read the first half of the import block; the blocker was live, and trusting it would have dropped the fix and the gate wiring built on it.)
- recorded: 2026-08-13
- expiry: none known

### Disprove every Critical: 3 of 4 on TV1-1950 were false positives
- rule: Before propagating a Critical/High, read the call site, git-blame against the base, and construct a failing input; drop what cannot survive all three.
- source: commands/verify-build.md:93; agents/verifier.md:92 at c75ba88
- evidence:
  > (Real miss: 3 of 4 reported Criticals on TV1-1950 were false positives — a truthy `'0'` misread as falsy, a verbatim-from-`master` pre-existing line, and a "double increment" that was load-bearing for restart determinism — each would have introduced a bug if "fixed"; the git-blame check alone kills two of them.)
  >
  > a verifier that emits plausible-but-wrong Criticals turns the reader into the verifier-of-the-verifier, and propagating one as a "fix" actively introduces a regression (the cost is asymmetric: an unverified Critical is more expensive than a missed nit).
- recorded: 2026-07-06
- expiry: none known

### Write the owed ADR before the PR: both deferring lanes re-measured wrong figures
- rule: An ADR owed by the resolved design is written before the PR opens, quoting the re-measured figure and its command; if it cannot be written now the decision is not resolved.
- source: commands/verify-build.md:104 at c75ba88
- evidence:
  > Quote the measurement and the command, not the design's number — two lanes that deferred were made to write the ADR now, and **both re-measured figures their own designs had wrong.**
- recorded: 2026-09-10
- expiry: none known

### Re-resolve every path an ADR cites; one shipped with a dropped directory
- rule: Every `file:line` and symbol an ADR cites is re-resolved before commit.
- source: commands/verify-build.md:107 at c75ba88
- evidence:
  > one shipped citing a path that did not exist as written, an abbreviation having dropped a directory.
- recorded: 2026-08-08
- expiry: none known

### A worked example the suite does not consume: one named a unit that did not exist
- rule: A worked example in an ADR, design or config sample becomes a fixture the tests read, or is anchored to the command or commit that verified it.
- source: commands/verify-build.md:113 at c75ba88
- evidence:
  > a hand-maintained example on no build path (one named a unit that did not exist) is a liability to delete, not neutral documentation.
- recorded: 2026-09-05
- expiry: none known

### Only the owner waives
- rule: A concern is waived only in the owner's own words, recorded as a `kind: waiver`, `decidedBy: human` entry in decisions.md whose title names the concern; never on an agent's judgement or from a paraphrase.
- source: commands/verify-build.md:130 at c75ba88
- evidence:
  > **Waivers. Only the owner waives.** A C-entry is `waived` only when the owner — the human who owns this unit — gives a waiver in their own words, during this `/verify-build` or earlier in this conversation or the ticket. Never waive on an agent's own judgment (yours, a sub-agent's, a review bot's), and never from a paraphrase.
- recorded: 2026-09-12
- expiry: none known

### concerns-check outcome=error is not-success, exactly like fail
- rule: A malformed concerns file, a bad or foreign waiver citation, or a missing verdict line is read as failure, never as a pass or as no concerns.
- source: commands/verify-build.md:141; commands/merge-multi.md:74 at c75ba88
- evidence:
  > **`outcome=error` is not-success, exactly like `outcome=fail`:** a malformed file or a bad waiver record is never read as a pass or as "no concerns". A command that printed no verdict line is `outcome=error`.
  >
  > - `outcome=error` → refuse the unit. This is not-success exactly like `fail` — a malformed file, a fabricated or foreign waiver citation, or a corrupt `decisions.md` never reads as a pass or as "no concerns".
- recorded: 2026-09-12
- expiry: none known

### Concerns fail closed: a hard entry ruled partial, unmet or cannot-determine fails
- rule: What the verifier could not check is `cannot-determine`, never `met`, and a hard concern in that state is a fail named in the PR body.
- source: commands/verify-build.md:248; commands/verify-build.md:126 at c75ba88
- evidence:
  > fail: one bullet per bar: hard entry ruled partial, unmet or cannot-determine (or still at verdict: —) — `C<n>` — <its label> — the bar as raised: <quote:> — evidence: <evidence:>
  >
  > What you could not check is `cannot-determine`, with why — never `met`.
- recorded: 2026-09-12
- expiry: none known

### A failure to measure never blocks landing
- rule: run-metrics is advisory: an error is one line in the report and `usage: null`, and the PR opens regardless.
- source: commands/verify-build.md:194 at c75ba88
- evidence:
  > **A failure to measure must never block landing the work**: an error in either command is one line in your report and the `usage: null` above, and Step 6 runs regardless.
- recorded: 2026-09-12
- expiry: none known

### PR opened is not done: a moved base voids the green checks
- rule: After opening, compare the current default branch against the pinned base; a moved base invalidates diff-reading gates and nothing marks them stale, so re-run them locally and read a check's sha and timestamp, never its colour.
- source: commands/verify-build.md:202; EVIDENCE.md:51; commands/evolve.md:60 at c75ba88
- evidence:
  > **It invalidates the green checks too, and nothing marks them stale:** a gate that reads the *diff* (a version-bump gate, a changed-files guard) stated its verdict about a base that is gone, and GitHub does not re-run it when the base moves. Compare each check's sha and timestamp against the current base; where the base moved, **re-run the diff-reading gates locally against it and report that**, rather than reading the green. Two same-base PRs that agree on a version string produce no conflict at all — the one case a merge conflict cannot surface.
  >
  > **A green CI check is an inherited fact with exactly this expiry** — a verdict about the base it ran on, void once that base moves, and for a gate that reads the *diff* a sibling merge is precisely what voids it. Two PRs cut from one commit bumped to the same version, so there was no textual conflict: `MERGEABLE`/`CLEAN` throughout and a green version gate seven hours older than the merge that invalidated it. Read a check's sha and timestamp, never its colour.
  >
  > - **Cut from one base.** Two PRs that bump to the *same* string produce no textual conflict — both read `MERGEABLE`/`CLEAN`, and the version gate's green on the second is a claim about a base the first has since replaced (EVIDENCE.md (`../EVIDENCE.md`) §3). Re-run the gate locally against the current base before merging.
- recorded: 2026-09-06
- expiry: the CI re-runs diff-reading gates when a PR's base moves

### A stacked child: merging into a stale base or deleting the base are both silent
- rule: Retarget a stacked child before its parent merges, delete a parent's branch only once nothing targets it, and verify after every merge with `git merge-base --is-ancestor`.
- source: commands/verify-build.md:204; commands/evolve.md:61 at c75ba88
- evidence:
  > **For a stacked child, do not rely on GitHub to retarget it — both things that happen to its base are silent.** While the parent's branch stays, the child keeps pointing at a merged branch: merging it there returns exit 0, shows MERGED, and delivers nothing to the default branch. And **deleting that branch through `gh pr merge --delete-branch` or `git push --delete` closes the child unmerged** (`base_ref_deleted` → `closed`, observed with `delete_branch_on_merge` false), and a closed child cannot be reopened while its base is gone. So retarget first (`gh pr edit <n> --base <default>`), delete a parent's branch only once nothing targets it, and verify **after every merge** with `git merge-base --is-ancestor origin/<head> origin/<default>` — the only check that catches a wrong-target merge, because that merge itself reports success.
  >
  > **Never merge a parent with `--delete-branch` while a child targets it:** deleting a base branch through `gh` closes the child *unmerged* (`base_ref_deleted` → `closed`), not retargeted, and it cannot be reopened while the base is gone — one round had to reopen a PR under a new number.
- recorded: 2026-09-12
- expiry: GitHub retargets or preserves a child PR when its base branch is deleted

### A closing keyword binds to exactly one issue: 80 references shipped as 7 closures
- rule: Repeat the closing keyword per issue (`Closes #56, closes #62`); a bare list closes the first and leaves the rest as mentions with nothing red anywhere, and a unit PR merged into an integration branch closes nothing.
- source: commands/verify-build.md:206; commands/evolve.md:56; commands/merge-multi.md:120; commands/commit.md:30 at c75ba88
- evidence:
  > **A closing keyword binds to exactly one issue — repeat it per issue.** `Closes #56, closes #62, closes #63`, in the body and in every commit message. A bare list, commas or not, closes the first and leaves the rest as mentions, with nothing red anywhere — 80 references once shipped as 7 closures. The plugin repo gates this (`scripts/check-closes-syntax.py`, over commit messages *and* instructional examples); a host repo does not, so here the rule travels with you.
  >
  > **A closing keyword binds to exactly one reference** — `Closes #56 #62 #63`, with or without commas, closes `#56` alone; repeat the keyword, `Closes #56, closes #62, closes #63`. Nothing goes red: the only tell is a backlog count (80 references once produced 7 closures). `scripts/check-closes-syntax.py` refuses the malformed line in commit messages *and* in the artifacts' own examples, because a wrong example is how the next round writes it again.
  >
  > GitHub fires closing keywords only for PRs merged into the repository's **default** branch. Every `Closes #N` written into a unit PR body by `/verify-build` is therefore inert under this topology — well-formed, rendered as a cross-reference, and closing nothing. The failure has no tell anywhere: well-formed commits, PRs `MERGED`, gates green, and the only symptom is a backlog count nobody has a reason to read.
  >
  > - **A GitHub closing keyword binds to exactly one issue — repeat it per issue.** `Closes #12, closes #13`, never a bare list: `Closes #12 #13` closes `#12` and leaves the rest as ordinary mentions, and a comma does not change that. The mistake is silent in every direction — the commit is well-formed, the merge succeeds, nothing warns — so the message is the last place it can be caught cheaply.
- recorded: 2026-09-12
- expiry: GitHub changes the closing-keyword grammar

### A gh failure prints a blank state and greps clean
- rule: When asserting issues reached CLOSED, check the line count before the states.
- source: commands/verify-build.md:214; commands/evolve.md:89 at c75ba88
- evidence:
  > check the line count *before* the states, because a `gh` failure prints a blank state and greps clean.
  >
  > a short list or a blank state is `gh` failing, indistinguishable from calm if you only grep for offenders.
- recorded: 2026-08-08
- expiry: none known

### Invariant-shaped sweeps for a safety-direction change
- rule: Where the work carries a may-only-widen / must-never-lose invariant, brief the sweeps with invariant-shaped questions, not a generic review.
- source: commands/verify-build.md:321 at c75ba88
- evidence:
  > Both defects in one such change looked locally correct and were invisible from the output by construction; a generic review would have missed them, and its own zero-delta measurement did.
- recorded: 2026-08-08
- expiry: none known

## commands/design-multi.md

### Prove the tree the agents read is the pin, in both directions; re-verify at Phase C
- rule: Test `HEAD == BASE` both ways before dispatching read-only lanes, record `treeClean` only paired with its sha, and re-verify the pin at Phase C.
- source: commands/design-multi.md:29; commands/design-multi.md:29 at c75ba88
- evidence:
  > `merge-base --is-ancestor` one way returned true while the worktree was 25 commits *behind* the pin, and 6 of 10 agents cited `file:line` against a tree the orchestrator never saw.
  >
  > **Re-verify the pin at Phase C**, not only here (one base moved 57 commits between phases and invalidated three conclusions).
- recorded: 2026-09-12
- expiry: none known

### Wave-0 audit: unbuilt suppliers, wave membership, stale shared docs, dead probe infra
- rule: One read-only auditor checks every `Depends on:` exists in code, every ticket the wave should contain is in the set, every shared grounding doc is still true, and whether probe infrastructure is up, before any lane pays for it N times.
- source: commands/design-multi.md:31; commands/design-multi.md:31 at c75ba88
- evidence:
  > does every `Depends on:` dependency **exist in code** (three of six units once discovered separately, at full cost, that they were blocked on the same unbuilt supplier); is every ticket the wave *should* contain in the run set (the missing dependency was named as wave-1 in the epic's own addendum); and is each **shared grounding doc** the brief cites still true (a `CONTEXT.md` handed to twelve lanes was stale four ways — a stale shared doc is a false premise multiplied by N).
  >
  > four opaque MCP failures once stood in for that one line.
- recorded: 2026-09-12
- expiry: none known

### Exact citations audit premise soundness right past: 4 of 4, 37 of 199
- rule: Verify class membership, sweep uncited premises, and establish a claim of the form F-returns-X-over-C by running F over C, never by grepping F's regexes.
- source: commands/design-multi.md:33; commands/design-multi.md:36 at c75ba88
- evidence:
  > Five findings in one run's worth of runs came from outside that frame, and each is a query, not a caution:
  >
  > **Exact citations audit premise SOUNDNESS right past.** 4 of 4 tickets in one run cited correctly and inferred falsely. Two checks a citation sweep cannot perform: for any premise of the form *"X is an instance of the class Y refuses / requires / handles"*, verify the **membership**, not that X and Y both exist at their lines; and **sweep the uncited premises** — every *"since X"*, *"because X"*, *"as X"* clause carrying no citation is a claim about the code, invisible to a `path:line` pass by construction. List them and check each. And a fact *"function F returns X over corpus C"* is established by **running F over C**, never by grepping F's regexes — a re-implemented predicate reproduces the auditor's reading of F, not F ("37 of 199 won't classify" was 199/199 once the shipped function ran).
- recorded: 2026-09-10
- expiry: none known

### A count or negative universal carries its command and its complement query
- rule: A handed-down enumeration is a sample unless it carries its sweep, and a correct command still asks half the question; name the complement query.
- source: commands/design-multi.md:37 at c75ba88
- evidence:
  > A carried, correct command still asks half the question, so name the other half: additive DDL net of its subtractive verb (`create index` vs `drop index`); a moved derivation's **inverse** derivations (`dirname(`, `resolve(x, '..')`, `.slice(` over the derived value); a reused extractor or dispatcher's **branches enumerated against the variant table** it claims to cover, never its doc comment (that one found a live defect at base). Three lanes inherited three clean, wrong counts this way.
- recorded: 2026-09-12
- expiry: none known

### A lane re-derives its own dependencies; the Depends on: line was wrong
- rule: A lane re-derives dependencies from first principles rather than inheriting the ticket's `Depends on:` line, and reports where they disagree.
- source: commands/design-multi.md:39 at c75ba88
- evidence:
  > And a lane **re-derives its own dependencies from first principles** rather than inheriting the ticket's `Depends on:` line, reporting where the two disagree: that line was wrong here in a way no citation check could catch, and the named dependency is often not the blocking one.
- recorded: 2026-09-10
- expiry: none known

### Grep for the resolved marker before dispatching; two overlapping runs wrote opposite blocks
- rule: Grep each snapshot for `design-multi:resolved:v(\d+)`, read its `run=`, and stop and ask when another run owns the ticket; the marker with `status=ready` is the section's identity and is replaced, never appended.
- source: commands/design-multi.md:41 at c75ba88
- evidence:
  > **Grep each snapshot for `design-multi:resolved:v(\d+)` before dispatching anything, and read its `run=`.** This command writes that marker and is otherwise blind to its own past output, and tickets linger in `To Do` long after their work merges. Marker with **this run's** `run=` → short-circuit to a cheap verification pass: re-check the block's *done-is-verifiable-by* and scope claims at the new base, and record `already_done` (recommend transitioning, drop the unit), `still_valid` (reuse) or `stale` (run Phase A and **replace** the old block — never append a second; the marker is the section's identity). Marker with a **different** `run=` → a concurrent or earlier sibling run owns this ticket: **stop and ask** — reuse it, redesign and replace, or drop the unit — never run a Phase A whose result Phase C cannot write. Two overlapping runs once wrote `status=ready` blocks giving opposite release-sequencing instructions for the same sibling repo, and only a write-back agent's aside surfaced it.
- recorded: 2026-09-05
- expiry: none known

### A task-completion notification is evidence the agent stopped, never that it produced anything
- rule: Stat the lane's `units/<id>.*` files from disk before collecting a unit.
- source: commands/design-multi.md:49 at c75ba88
- evidence:
  > **A task-completion notification is evidence the agent stopped, never evidence it produced anything** — and `run.yaml` is written from your bookkeeping, not from disk, so nothing else would catch it.
- recorded: 2026-09-17
- expiry: none known

### Label every handed-down fact with a stamp: an APPLIES on a fixed precedent
- rule: Handed-down facts carry `APPLIES [verified <date> via <command>]` or `VERIFY`; a sibling-sourced or designed-not-built fact is always VERIFY, and consumers are listed beside suppliers with their mode decisions.
- source: commands/design-multi.md:50; commands/design-multi.md:50; commands/design-multi.md:50 at c75ba88
- evidence:
  > an `APPLIES` on a precedent that had already been fixed made one unit design *around* the thing it should have copied.
  >
  > The last three all reached lanes as `APPLIES` in one campaign, and were false.
  >
  > one design was reversed by a consumer its brief never named, and two lanes each designed a writer for one file.
- recorded: 2026-09-12
- expiry: none known

### Run parked probes batched per external system: five forks collapsed into one sitting
- rule: Between Phase A and B, run the orchestrator-runnable probes lanes parked, one auth handshake per external system, labelled `EMPIRICAL — <env> <date>`.
- source: commands/design-multi.md:52 at c75ba88
- evidence:
  > batched per external system** (one auth handshake, many questions: five separate "who runs this?" forks once collapsed into one sitting that reversed a design and found three live defects no ticket named).
- recorded: 2026-09-05
- expiry: none known

### Quote the recommendation from the critiqued draft, never from a ticket or handoff
- rule: The recommendation shown in Phase B is the post-critique one.
- source: commands/design-multi.md:56 at c75ba88
- evidence:
  > the recommendation **quoted from the critiqued draft's fork section**, never from a ticket, a handoff or an earlier summary, which carry the pre-critique one (a user once answered a fork whose stated recommendation the critique had already reversed).
- recorded: 2026-09-12
- expiry: none known

### Whose call is it: two of eight roots were engineering decisions in product clothes
- rule: A fork that more reading or thinking would settle is the engineer's; check sibling ADRs for precedent before parking a hard-but-code-answerable question with the user.
- source: commands/design-multi.md:62 at c75ba88
- evidence:
  > Two of eight roots in one sitting were engineering decisions in product clothes, and the user said so (*"this decision is way over my head"*) — on a one-way-door persisted field, where an uninformed "do what you think" would have been recorded as a user decision.
- recorded: 2026-09-12
- expiry: none known

### Index resolved contract clauses across drafts: a 60 s dead-peer window under a 30 s lease
- rule: The seam index groups by concrete artifact and covers resolved clauses (timeouts, transports, who writes which file) as well as open forks.
- source: commands/design-multi.md:62 at c75ba88
- evidence:
  > Two individually valid resolved decisions — a 60 s dead-peer window under a 30 s lease, three push transports for one feed, two writers of one file — were never forks, so no other gate sees them.
- recorded: 2026-09-12
- expiry: none known

### Collapse dependent forks: a draft's lead was B while its recommendations composed to A
- rule: Present the root fork first and resolve the dependent one to a single recommendation or mark it dependent.
- source: commands/design-multi.md:68 at c75ba88
- evidence:
  > A draft can carry two recommendations that contradict each other — one led with *"partition, unless Fork 2 comes back 'UI appropriateness'"* and then recommended exactly that on Fork 2, so its stated lead was **B** while its own recommendations composed to **A**.
- recorded: 2026-09-04
- expiry: none known

### Re-frame an answer naming an impossible combination
- rule: When an answer needs two properties the code cannot provide together, say so with evidence and map the intent onto the option that delivers it.
- source: commands/design-multi.md:69 at c75ba88
- evidence:
  > When the answer needs two properties the code cannot provide together ("a rule, and idempotent" — a send inside a rule graph cannot be idempotent, because a transient failure re-runs the graph from node 0)
- recorded: 2026-09-04
- expiry: none known

### Re-verify after the answers: an accepted cost promoted a different claim to load-bearing
- rule: Which claims are load-bearing changes when the human answers; verify the one or two the answers made load-bearing after the sitting, not before.
- source: commands/design-multi.md:70 at c75ba88
- evidence:
  > one draft rejected a cross-repo signature change partly on its cost, the user said that cost was acceptable, and that instantly promoted a different claim (whether the seam could even see the caller) to load-bearing — verifying it reversed the recommendation.
- recorded: 2026-09-04
- expiry: none known

### A cross-cutting fact re-scans every drafted recommendation
- rule: When an answer establishes a cross-cutting fact, re-scan every unit's recommendations against it and record what it kills as withdrawn-with-reason.
- source: commands/design-multi.md:71 at c75ba88
- evidence:
  > one run's lead recommendation (a runtime assertion answered by production traffic) had been dead since the sitting's first sentence.
- recorded: 2026-09-05
- expiry: none known

### Re-run premise probes at Phase C: one fix shipped mid-sitting
- rule: Before writing back, re-run each unit's premise probes and re-resolve its `groundedShas`, and stamp the block with the sha it was written against.
- source: commands/design-multi.md:88 at c75ba88
- evidence:
  > when the human **acts** (one fix shipped mid-sitting and collapsed its ticket to recurrence-prevention) the draft would instruct `/start-multi` to do work that no longer exists
- recorded: 2026-09-05
- expiry: none known

### A five-wave campaign wrote ~20 addenda to already-written suppliers
- rule: In a dependency-ordered campaign, hold a supplier's block until the consuming wave's fold-back or write it expecting addenda, and fold a discovered obligation into any still-unwritten block.
- source: commands/design-multi.md:96 at c75ba88
- evidence:
  > One five-wave campaign wrote ~20 addenda to already-written suppliers, two of them corrections that left block and addendum disagreeing.
- recorded: 2026-09-17
- expiry: none known

### A deferral with no owner is refused; a declined hook dissolved a hard deps edge
- rule: Grep every run-dir record for unowned deferrals before writing; the obligations join has a third outcome, contradicted, and a retired row is recorded as retired.
- source: commands/design-multi.md:101; commands/design-multi.md:101 at c75ba88
- evidence:
  > "The orchestrator" or "this session" is **no owner** — it ends when the session does; one such row silently skipped a freeze check.
  >
  > Declining both hooks once dissolved a hard `deps=` edge into an ordering preference and changed the build schedule.
- recorded: 2026-09-12
- expiry: none known

### The epic gets one goal-level oracle, owned by no unit, committed RED
- rule: Nothing in the flow otherwise asks what proves the epic works; the goal oracle asserts the epic's own done-is-verifiable-by sentence end to end and is committed failing before the first unit is cut.
- source: commands/design-multi.md:103 at c75ba88
- evidence:
  > Every incentive and artifact in this flow points at unit scope — the ticket, the block, the slices, the gate — and nothing prompts *"what proves the EPIC works?"*, so eight units can be Done, every gate green, and the system do nothing.
- recorded: 2026-09-10
- expiry: none known

### Reserve ADR numbers against the pinned base; an empty ls-tree handed three lanes a taken number
- rule: Reserve monotonic numbers with `git ls-tree` against the pinned base plus every sibling branch, print the highest found, and re-run the query immediately before writing; the window is any wall-clock gap.
- source: commands/design-multi.md:105; commands/design-multi.md:107 at c75ba88
- evidence:
  > a monotonic-number query that returns nothing is a broken query (`git ls-tree` with a `./`-prefixed path matches nothing), not a clean namespace, and one such empty result handed three lanes a number already taken on `master`.
  >
  > one run's freshly reallocated numbers were taken by `master` four hours later.
- recorded: 2026-09-05
- expiry: none known

### status is required; buildableNow dissolved a near-block and rescued a live-defect slice
- rule: Every non-ready verdict carries `buildableNow`, `blockProof` and `resolutionPath`; a bare `blocked` removes buildable work and a bare `deferred` is indistinguishable from forgotten.
- source: commands/design-multi.md:122 at c75ba88
- evidence:
  > Every non-`ready` verdict carries three fields — `buildableNow` (what ships despite the block; forces the composition check that dissolved one near-block and rescued a live-defect slice from another), `blockProof` (needs X, dependency gives only Y, therefore Z) and `resolutionPath` (the un-defer trigger or the cheapest experiment that settles it) — because a bare `blocked` has silently removed buildable work and a bare `deferred` is indistinguishable from forgotten.
- recorded: 2026-09-05
- expiry: none known

### Every cited path is proved reachable from the stamped base: ESAS-45 for ADR-045
- rule: One `git cat-file -e <BASE>:<path>` per citation before the write, including tickets the orchestrator files itself.
- source: commands/design-multi.md:124 at c75ba88
- evidence:
  > Tickets you file are the easy miss, because you just read the code and "know" the path: two filed this way carried a full path invented from a bare filename and `ESAS-45` for `ADR-045`.
- recorded: 2026-09-12
- expiry: none known

### The ADF budget is the block's, never a lane's
- rule: Never quote the tracker budget in a lane brief; applied to an 18-25k draft it prunes the reasoning.
- source: commands/design-multi.md:129 at c75ba88
- evidence:
  > The budget is the **block's** — never quote it in a lane brief, where it gets applied to 18–25k drafts and prunes their reasoning.
- recorded: 2026-09-17
- expiry: none known

### Glossary/ADR deltas ride in the block as delta: specified, deferred to build
- rule: A delta describing code that has not landed is not committed on the default branch; it rides in the block and is discharged by /build or /verify-build on the branch.
- source: commands/design-multi.md:133 at c75ba88
- evidence:
  > **Glossary/ADR deltas ride in the block as `delta: specified, deferred to build`** — which section, what it must say, what it waits for — discharged by `/build` or `/verify-build` on the branch. Not committed here: you are on the default branch, most deltas describe code that has not landed, non-ready units must not have theirs applied, and a commit invalidates step 0's pin.
- recorded: 2026-09-05
- expiry: none known

## commands/design.md

### Zero providers is the normal case, and it is silent
- rule: With no context provider declared, /design does not look, does not mention the extension point, and behaves exactly as before; a provider that errors never fails /design.
- source: commands/design.md:79; CONTEXT-PROVIDERS.md:5 at c75ba88
- evidence:
  > The base plugin ships no provider and **zero providers is the normal case** — with none declared, do not go looking, do not mention that an extension point was consulted, and this step behaves exactly as it did before.
  >
  > carries. **Zero providers is the normal case, and it is the case this contract is written around:
- recorded: 2026-09-06
- expiry: none known

### A provider is declared by a contextProviders key, never sniffed from tool presence
- rule: The declaration is the `contextProviders` key in the host repo's `.claude/bett3r-ai-workflow.json`; an MCP tool in the session or a capture marker directory is not a declaration.
- source: commands/design.md:81; CONTEXT-PROVIDERS.md:42-47 at c75ba88
- evidence:
  > The declaration is a `contextProviders` key in the repo's `.claude/bett3r-ai-workflow.json` — the same per-repo config `work-docs-path` reads `workDocsRoot` from, and it is the declaration, not this plugin, that names the provider and how it is called.
  >
  > **The declaration is a `contextProviders` key in the host repo's
  > `.claude/bett3r-ai-workflow.json`** — the same per-repo config the flow already reads
  > `workDocsRoot` from. Nothing else declares one. In particular: the presence of a provider's
  > MCP tool in the session is **not** a declaration — that is this plugin deciding, from ambient
  > state no repo owner opted into — and neither is a capture marker directory, which can say a
  > repo captures and cannot say whether it wants its designs grounded.
- recorded: 2026-09-18
- expiry: none known

### Only a canonical contribution settles a fork; an outage is not an empty corpus
- rule: Pending, backfilled or text-matched items open forks and never close one; a refusal, PARTIAL or timeout is one `grounding degraded:` note, and the fork's map status distinguishes `store-unreachable` from `no-atoms-matched`.
- source: commands/design.md:83 at c75ba88
- evidence:
  > **Only a contribution the provider marks canonical may settle a fork.** Anything it marks pending, backfilled or matched on text alone is a *candidate*: it opens a fork and never closes one. Where a provider marks an item that way in its own words — a question rather than a fact, not to be cited as a decision — that wording is the rule, not a hint. A provider that refuses, returns `PARTIAL` or times out is one `grounding degraded:` note carrying the refusal's own reason, and the run continues; **never** write that up as "there are no recorded decisions", which is a claim about the corpus where all you have is an outage. A fork that grounding could not settle stays **open** and records why on its map status — `store-unreachable` for the outage, `no-atoms-matched` or `only-pending` where the store answered and nothing canonical applied. Those are different facts and the doc never conflates them.
- recorded: 2026-09-18
- expiry: none known

### The ticket is evidence, not spec: three of four descriptions stale, a fourth's premise false
- rule: Where the ticket and the code disagree, the code wins and the doc says so.
- source: commands/design.md:87 at c75ba88
- evidence:
  > Stale tickets are the norm — in one 4-ticket run three descriptions were stale and a fourth's premise was false.
- recorded: 2026-09-05
- expiry: none known

### The ticket's own history before its body: seven of eleven sections had shipped
- rule: `git log --grep=<TICKET-ID>` first; a non-empty result makes the body a historical document and the deliverable a SHIPPED / OUTSTANDING ledger.
- source: commands/design.md:89 at c75ba88
- evidence:
  > non-empty means the body is a **historical document**: seven of eleven sections had shipped under one ticket's own id, and the deliverable is a per-section SHIPPED / OUTSTANDING ledger with shas, not a design.
- recorded: 2026-09-05
- expiry: none known

### Re-resolve citations by identity: ADR-090 §7 lived in ADR-097
- rule: Re-locate code by symbol and confirm a cited section is about the cited subject; write citations as `symbol (file:line)` so a lane 66 commits later re-locates them in one grep.
- source: commands/design.md:91; commands/design.md:91 at c75ba88
- evidence:
  > An ADR cited by number rots into a real-but-wrong document (four tickets cited `ADR-090 §7`; the section lived in `ADR-097`, and 090 existed with no §7); a `file:line` rots on every commit and can still resolve to an unrelated file of the same name.
  >
  > the symbol is the contract, and a lane 66 commits later re-locates it in one grep instead of re-reading the file.
- recorded: 2026-09-05
- expiry: none known

### A cited sibling exists in code, not just in Jira: two tickets sized as mirror X
- rule: Check a cited sibling ticket exists in code with `git log --all --grep` and a concept-noun grep; where the ghost is named in an AC, the AC is unverifiable.
- source: commands/design.md:94 at c75ba88
- evidence:
  > Two tickets were sized as "mirror X" where X had never existed; where the ghost is named in an acceptance criterion, the AC is unverifiable — say so and re-size.
- recorded: 2026-09-05
- expiry: none known

### Producer-only evidence is a finding: the form it pre-filled did not exist
- rule: Name the host surface a pre-fill / extend / consume verb attaches to, and grep for it.
- source: commands/design.md:95 at c75ba88
- evidence:
  > Every cited `file:line` in one ticket was correct and the form it pre-filled did not exist; the tell was a verified section listing four producer artifacts and zero consumers.
- recorded: 2026-09-05
- expiry: none known

### A does-not-reuse list is a probe in both directions
- rule: Each excluded X still exists, and a concept-noun grep finds the near-duplicate the list omits.
- source: commands/design.md:96 at c75ba88
- evidence:
  > - **A "does not reuse X" list is a probe in both directions** — each X still exists (a relocated module makes the exclusion a fossil), and a concept-noun grep for the near-duplicate the list omits (the omission was worth more than every item on one list).
- recorded: 2026-09-05
- expiry: none known

### Absence-of-use is not absence-of-capability: ForEachNode had no built-in user
- rule: Search the engine's own source by concept noun and record the search that failed; re-run a subagent's negative existence claim yourself.
- source: commands/design.md:97 at c75ba88
- evidence:
  > Absence-of-use is not absence-of-capability: `ForEachNode` existed with no built-in user. Search the engine's own source by concept noun (`forEach`, `map`, `fanOut`, `iterate`) and record *the search that failed*, not the callers that happened not to use it. A subagent's **negative** existence claim is the highest-risk thing it can return — re-run the one-line `find` yourself before acting on it.
- recorded: 2026-09-05
- expiry: none known

### A hit count is not evidence a concept exists: six hits for purchaseorder
- rule: The deliverable of a grep is a classified list, never a number; scope the corpus to the domain question.
- source: commands/design.md:98 at c75ba88
- evidence:
  > Six hits for `purchaseorder` were three vendor type dumps and three marketing strings; the deliverable is a **classified list** ("6 files, all under `sales-channels/*/types/` and `apps/landing/`"), never a number.
- recorded: 2026-09-05
- expiry: none known

### An error-code claim cites the constructing frame: code === 23505 dead behind a green test
- rule: Unless the constructing frame was read, the claim is this-path-fails, not this-path-throws-X.
- source: commands/design.md:102 at c75ba88
- evidence:
  > adapters remap SQLSTATEs invisibly from the caller, and a `code === 23505` branch was dead behind a green test that hand-built the shape.
- recorded: 2026-09-05
- expiry: none known

### A fact about a multi-entry-point symbol carries the lane it was observed on
- rule: "`neto` is computed in the handler" was true of one of two issuance lanes; unscoped is where the design question lives.
- source: commands/design.md:103 at c75ba88
- evidence:
  > - **A fact about a multi-entry-point symbol carries the lane it was observed on**, or it is `UNVERIFIED`: "`neto` is computed in the handler" was true of one of two issuance lanes. Unscoped is precisely where the design question lives.
- recorded: 2026-09-05
- expiry: none known

### Throw or return is answered at the caller
- rule: A gate relaxed to `return undefined` was an admin escalation at its call site.
- source: commands/design.md:104 at c75ba88
- evidence:
  > A gate relaxed to `return undefined` was, at its call site, an admin escalation — invisible from the gate's own file.
- recorded: 2026-09-05
- expiry: none known

### An auto-resolution's prerequisite chain is checked before it is settled
- rule: The mapping that made one auto-resolution safe collapsed three tax-id kinds to one wrong code.
- source: commands/design.md:106 at c75ba88
- evidence:
  > the mapping that makes "wire the real buyer document into the ARCA call" safe collapsed three tax-id kinds to one wrong code.
- recorded: 2026-09-05
- expiry: none known

### Prior art is evidence of a convention: sales.Customer's live compliance defect; four of five renames
- rule: When the move is mirror X, probe what X gets wrong; derive a greenfield site checklist from `git show --stat --find-renames`, never from memory.
- source: commands/design.md:109 at c75ba88
- evidence:
  > `sales.Customer` would have handed a new aggregate a live compliance defect. And for a "stand up a new <thing>" unit, derive the site checklist from `git show --stat --find-renames` over the last genuine greenfield commit series, never from memory — four of five candidates were renames.
- recorded: 2026-09-05
- expiry: none known

### Assumptions about behaviour are run, not read: three of three failures were that kind
- rule: Render the template, run the function, print the expansion; grep every reference to a type before calling a widening additive; grep the assertion string, not the test file name.
- source: commands/design.md:111 at c75ba88
- evidence:
  > Three of three real failures in one unit were the second kind. Two concrete forms: **grep every other reference to a type before accepting that a widening is "purely additive"** (a union widened for its readers broke a positional consumer inside a fenced function); and **when a design says "test X asserts Y", grep the assertion string, not the file name** — the real assertion was a shell probe wired to `test:chart`.
- recorded: 2026-09-05
- expiry: none known

### DIES / SURVIVES per repo: a grep summon → 0 oracle would have renamed the feature away
- rule: Oracles name the implementation surface, never the ubiquitous-language term; each component names the repo that contains it.
- source: commands/design.md:115 at c75ba88
- evidence:
  > the press route and the client half of a summon were listed for deletion with the sentinel they merely carried, and a `grep summon → 0` oracle would have renamed the feature out of the codebase.
- recorded: 2026-09-05
- expiry: none known

### Check the mechanism behind a stated rationale, not just the ask
- rule: A deferral's reasoning, a stated blocker, an already-handled-by-X is one probe from materially different; a claim about another repo's runtime checks the executing artifact; a shipped worked example is run.
- source: commands/design.md:117; EVIDENCE.md:47 at c75ba88
- evidence:
  > Three rules hold across all eight: **check the *mechanism* behind a stated rationale, not just the ask** — a deferral's reasoning, a stated blocker, an "already handled by X" is usually one probe from materially different; **a claim about another repo's runtime checks the artifact that executes** (installed package, plugin cache, deployed build), not only its source; and **if the ticket ships a worked example of the defect, run it.**
  >
  > - **Verify the mechanism, not only the defect.** A deferral's rationale, a stated blocker, a named mitigation, a worked example the ticket ships — each is usually one probe from being materially different than stated. Run the example; make the API call; read the cited line range. A deferral is written at the moment of least scrutiny and then inherited as though it had a design pass.
- recorded: 2026-09-05
- expiry: none known

### An ADR that corrects a premise ships the corrected reason
- rule: A decision can survive its premise's falsification; an ADR keeping the original rationale is one nobody can safely inherit.
- source: commands/design.md:119 at c75ba88
- evidence:
  > a fallback that "inherits monolith sizing" actually mis-sized in two directions, which *strengthened* hard-fail
- recorded: 2026-09-05
- expiry: none known

### Verify the block's claims, not that its prose fits
- rule: A resolved block is interview-resolved, zero-drift and can be false; verify the mitigation, not just the risk, and re-derive any decision that re-argues existing behaviour.
- source: commands/design.md:127; commands/design.md:130; EVIDENCE.md:46 at c75ba88
- evidence:
  > **Verify the block's claims, not that its prose fits.** A decision can be interview-resolved, zero-drift, paste-ready and factually false — the interview happens once and runs unattended afterwards, so an error introduced *during* the interview has no downstream gate, and zero drift reads as nothing to check.
  >
  > the known case had the risk fire *through* its mitigation, which was itself the false claim.
  >
  > A decision can be interview-resolved, zero-drift, perfectly-fitting prose and factually false — and zero drift makes it *worse*, because zero drift reads as nothing to check.
- recorded: 2026-09-05
- expiry: none known

### Enumerate what the block does not decide: unspecified seams
- rule: For each decision naming a rule, ask which other component performs the same class of operation; emit the unanswered ones as unspecified seams and pass them down as explicit non-guidance.
- source: commands/design.md:135; EVIDENCE.md:58 at c75ba88
- evidence:
  > Emit the unanswered ones as **unspecified seams** and pass them down as explicit non-guidance.
  >
  > A specification's gaps get filled by whatever rule sits next to them. **An unspecified seam adjacent to a specified one is the highest-risk place in a design**, because the specified rule is exactly what will be reused there — and the two seams frequently want opposite answers. The recurring shapes: read-modify-write pairs, the client and server halves of one document, and the read and write paths over one piece of state. Completeness raises this risk rather than lowering it: the better-evidenced the document, the more confidently its rule is generalised into the gap.
- recorded: 2026-09-04
- expiry: none known

### A citation that lives only in the draft is destroyed by the next regeneration
- rule: Where a canonical contribution settles a fork, its citation id goes into the fork's map status as `resolvedBy`, because regenerated decision text is a projection of the map.
- source: commands/design.md:141 at c75ba88
- evidence:
  > **Where a canonical contribution from Step 1 settles a fork, say which one** — quote its claim and its verbatim span in the walk, and carry its citation id into the fork's map status as `resolvedBy` beside `source`, exactly as the provider spelled it. Not into the prose alone: regenerated decision text is a projection of the map (ADR-007), so a citation that lives only in the draft is destroyed by the next regeneration with nothing red.
- recorded: 2026-09-18
- expiry: ADR-007's generated region is withdrawn

### A recorder's id has one home: the sidecar the verdict names
- rule: An id handed back by a recording call goes into the fork-id-keyed sidecar beside map.json, never into map.json or `resolvedBy`.
- source: commands/design.md:143; skills/design-map/SKILL.md:447-456 at c75ba88
- evidence:
  > **Where the call hands back an id, that id has one home: the sidecar the verdict names as `sidecar=`, keyed by fork id, committed in the same commit as `map.json`.** Never into `map.json` itself, and never into `resolvedBy` — that key carries what *settled* the fork, and an id handed back by a recorder only says where the answer was filed.
  >
  > `sidecar=` names where the id a recorder hands back is written:
  > `<map path without its .json>.resolved-by.json`, beside the map, a JSON object
  > keyed by fork id, committed with the map. **Beside, not inside:** the fork
  > object is closed (`additionalProperties: false`), as is every `status` branch,
  > and the status kind refs the byte-identical copy of esas's vocabulary — so an
  > id in the map would be a cross-repo vocabulary change, not a field addition. **Named after its own map**, not a flat
  > `resolved-by.json`, because a run dir holds one map per subject in one
  > directory. That file is the id's one home. It is distinct from `resolvedBy` on
  > a fork's status, which carries what **settled** the fork; an id handed back by
  > a recorder says only where the answer was filed.
- recorded: 2026-09-18
- expiry: esas's map vocabulary gains a field for a recorder id

### Recording is never a gate; never probe whether the provider is up before calling
- rule: A refusal is learned from the call's own answer; a health check in command prose is a rule restated per command instead of living in the one process every command calls.
- source: commands/design.md:145 at c75ba88
- evidence:
  > Never probe whether the provider is up before calling — you learn that from the call's own answer, and a health check in this prose is a rule restated per command instead of living in the one process every command calls.
- recorded: 2026-09-18
- expiry: none known

### Could a fresh session holding only this repo run /plan without loss?
- rule: Before handing off, enumerate what the session produced and confirm each is in the doc, committed, or declared re-derivable with its command; this fails worse the better the session was.
- source: commands/design.md:192; EVIDENCE.md:62 at c75ba88
- evidence:
  > **Answer this before handing off: could a fresh session holding only this repo and the committed `<path>/design.md` run `/plan` without loss?** Enumerate what this session produced — files, commands and their outputs, counts, external state — and confirm each is in the doc, committed, or declared re-derivable with the command to re-derive it (EVIDENCE.md (`../EVIDENCE.md`) §4: this fails worse the better the session was).
  >
  > A step may not hand off state that lives only in its own context — and this fails *worse* the better the session was, because a session that ran more spikes produced more that the doc format never asked for.
- recorded: 2026-09-12
- expiry: none known

### A citation target must be reachable from the base its reader branches from: 531 → 586 lines
- rule: The design is committed beside the code, and every outside pointer names the committed path, never a `.work/` path.
- source: commands/design.md:196 at c75ba88
- evidence:
  > Six lanes of one run read the doc only because they happened to run in the authoring worktree; mid-run it was committed elsewhere and corrected (531 → 586 lines: a falsified claim, a new rule), and every ticket still pointed at the dead path. **The rule that outlives the specifics: a citation target must be reachable from the base its reader branches from.**
- recorded: 2026-09-12
- expiry: none known

## commands/start-multi.md

### Snapshot from disk, not from a subagent's memory: four of eleven snapshots truncated
- rule: Copy ticket snapshots from the /design-multi run dir; when fetching through a subagent, grep for truncation markers and assert the terminal section is present, and re-fetch on failure.
- source: commands/start-multi.md:34 at c75ba88
- evidence:
  > A "do not truncate" instruction is not a control — summarising is what a subagent does with a large document, and four of eleven snapshots once came back with a literal *"[Full resolved design section truncated for length...]"*, which read as complete short tickets to lanes that never see the tracker, and hid a compile dependency the wave plan then violated.
- recorded: 2026-09-05
- expiry: the tracker MCP can fetch to a file

### Drift per unit, never per run; --stat measures movement and is blind to shape
- rule: Report `movement: none|lines|structural` and `shape: none|changed` per unit, diffing each named dependency's type/schema surface separately.
- source: commands/start-multi.md:38; commands/start-multi.md:38 at c75ba88
- evidence:
  > One run-level note cannot say *"zero drift on two surfaces, +1248/−732 across 31 files on the third."*
  >
  > **`--stat` measures MOVEMENT and is blind to SHAPE** — a dependency that gained, renamed or retyped a field between `resolvedBase` and `BASE` leaves the design's prose intact and its meaning wrong. So for every dependency a resolved block *names*, also diff that dependency's **type/schema surface** (`git diff <resolvedBase>..<BASE> -- <its model/schema files>`) and hand the lane that verdict separately: a unit whose own files did not move can still be `structural` on this axis, and **it is the axis whose failures compile.**
- recorded: 2026-09-10
- expiry: none known

### An environment fact is per-unit: three dependency versions; SOPS keys not present
- rule: Hand down the command with the observation, never the conclusion; a completed lane's environment finding is still a per-unit fact.
- source: commands/start-multi.md:45 at c75ba88
- evidence:
  > `link:../pv3/packages/*` resolves relative to *each worktree*, so three lanes once held three dependency versions while the orchestrator asserted "symlinked everywhere, do not rebuild" from its own checkout; and a lane's "SOPS keys not present", passed down as settled, was really an unmaterialised `config/local.yaml` — the receiving lane disproved it and ran the gate the briefing called impossible.
- recorded: 2026-09-10
- expiry: none known

### Verify the base yourself: 74 ahead was really 74 behind
- rule: After cutting a branch, `rev-list --count HEAD..origin/int/<run-id>` must be 0; never trust a reported ahead/behind.
- source: commands/start-multi.md:49 at c75ba88
- evidence:
  > Never trust a reported ahead/behind ("74 ahead" was really 74 *behind*).
- recorded: 2026-09-04
- expiry: none known

### Provision before any lane: the two commonest failures present as a broken baseline
- rule: The provisioner runs once per unit before any lane, because each failure is otherwise met alone by N lanes that get it wrong independently.
- source: commands/start-multi.md:51 at c75ba88
- evidence:
  > All of it up front, because each of those failures is otherwise met alone, mid-pipeline, by N lanes that each get it wrong independently — and the two commonest present as a *broken baseline* rather than a missing step.
- recorded: 2026-09-06
- expiry: none known

### --max-parallel has a second axis, and it is not a machine resource
- rule: State the expected cost and the ceiling before dispatching a wave; spend scales with lanes × context per lane, and a cost stop is stop-dispatching at a wave boundary, never tear-down.
- source: commands/start-multi.md:55 at c75ba88
- evidence:
  > **`--max-parallel` has a second axis, and it is not a machine resource.** Memory and cores tell you what the laptop survives; they say nothing about what the run costs, and the two are not correlated — five lanes fit in RAM comfortably and consumed most of a weekly allowance in six hours.
- recorded: 2026-09-18
- expiry: none known

### Size --max-parallel by memory, not cores: the cliff
- rule: Past some N the fleet falls off a cliff; log load average and swap when a gate overruns, scope per-unit gates, and serialize generate-all-class steps behind a lock.
- source: commands/start-multi.md:57 at c75ba88
- evidence:
  > **Size `--max-parallel` by memory, not cores.** Past some N the fleet falls off a **cliff**, not a slope — one build measured 95 s alone and >38 min under load at swap 31.9 GB of 33.8. Contention is also the mechanism behind the 600 s deadlock, and a starved lane reads as a hung one, so log load average and swap when a gate overruns.
- recorded: 2026-09-04
- expiry: none known

### Never overlap a certification gate with provisioning; under load a gate fails falsely
- rule: A gate whose verdict gates a decision runs with nothing else of yours in flight, and a red result is re-run alone with `uptime` and `vm.swapusage` recorded.
- source: commands/start-multi.md:59 at c75ba88
- evidence:
  > under load a gate does not merely **overrun**, it **fails falsely**. Wall-clock timeouts on out-of-process dependencies and fs-watcher assertions are the load-sensitive class, and **a red base you produced yourself is indistinguishable from one you inherited — and it arrives pointing at whatever you most recently merged.**
- recorded: 2026-09-10
- expiry: none known

### The lock is a directory: PID liveness cleared a live lock; the release path leaked twice
- rule: Never adjudicate lock ownership on PID liveness, treat a heartbeat as liveness only with a refresher, and remove every file the lock created on release.
- source: commands/start-multi.md:61; commands/start-multi.md:61 at c75ba88
- evidence:
  > Never adjudicate ownership on PID liveness — every Bash call is a new shell, so the `$$` in `owner` is dead seconds after a legitimate acquire, and a coordinator once cleared a live lock on that evidence.
  >
  > And the release path must remove **every file it created** (or `rm -rf` the dir): a stray file makes `rmdir` fail silently, the dir leaks ownerless, and every later waiter classifies that as "acquire gap" and spins forever — leaked twice in one night.
- recorded: 2026-09-05
- expiry: none known

### The brief states only what you measured: 2 of 4 briefs asserted a false fact
- rule: A lane brief never restates or summarises the resolved block; it quotes or cites, and every brief carries the precedence line that the block wins over the brief.
- source: commands/start-multi.md:65 at c75ba88
- evidence:
  > Summarising is the helpful default and the summary reads *more* usable than a quote, which is exactly the trap — 2 of 4 briefs in one run asserted a false fact the block contradicted, written carefully, with zero drift and no gate that could catch it. A conclusion you did not verify at BASE does not belong in a document you sign. And **every brief carries a precedence line, mandatory, not incidental** — *"Where this brief and `ticket-block.md` disagree, the block wins and the brief is wrong — report the divergence"* — which is the single sentence that converted that run from a shipped defect into two lanes reporting a correction.
- recorded: 2026-09-10
- expiry: none known

### --serial: worktree isolation refuses compound git commands
- rule: Under --serial brief every agent to use plain single commands and absolute scratch paths; these are the harness's heuristics and are re-verified when it changes.
- source: commands/start-multi.md:69 at c75ba88
- evidence:
  > (3) Worktree isolation refuses — or holds for approval — commands it cannot show are not git: a compound `cd … && git …`, a runtime variable as a command argument, a `node -e` built from command output, and any copy or delete of a `.git`, even under the scratchpad. Every executor and verifier brief says *plain single commands, absolute scratch paths*; once briefed, no executor tripped. These shapes are the harness's heuristics — re-verify them when it changes.
- recorded: 2026-09-12
- expiry: the harness's worktree isolation changes what it holds for approval

### Verify the capability, never the report: five lanes claimed all five steps with no step tool
- rule: No `.work/steps/*.log` and no `LANE-STEP:` marker means no step ran as a step; treat it as infra and re-dispatch, and a lane asserts it holds `Agent` before step 1.
- source: commands/start-multi.md:71; agents/unit-lane.md:114-123 at c75ba88
- evidence:
  > Five lanes have reported "all five steps complete" while holding no step-invocation tool and no `Agent`, having read the command files and executed their substance inline; the disclosure is unreliable in both directions and is the only channel you have. So check the artifact instead: **no `.work/steps/*.log` and no `LANE-STEP:` marker means no step ran as a step**, and a `/build` with no per-slice verifier verdict on disk did not run the dual gate.
  >
  > **Before step 1, assert you can actually dispatch.** Confirm you hold `Agent`.
  > **If it is missing, stop and report `blocked-on=lane-tools`**, naming the tools
  > you do hold — do not read the command files and execute their substance inline,
  > and do not fall back to invoking the steps yourself. That substitution is the
  > failure this assertion exists for: it produces good work, green gates and a
  > plausible report, while `/build`'s dual gate never runs and **no `LANE-STEP:`
  > line is ever emitted by any step**, so a scheduler classifying lanes by marker
  > absence reads the whole fleet as `infra` — nine lanes across four fleets
  > rediscovered this. `step-lane` re-asserts the step-invoking half (`SlashCommand`
  > or `Skill`, whichever this harness names it) inside the context that needs it.
- recorded: 2026-09-12
- expiry: none known

### Address every message from agents.yaml; lead with TO: <TICKET-ID>
- rule: Resolve every recipient from `<run>/agents.yaml`, never from recall; a directive whose ticket id is not the lane's is recorded as a misroute.
- source: commands/start-multi.md:75; agents/unit-lane.md:255 at c75ba88
- evidence:
  > **Address every message; never resolve a recipient from recall.** Write `<run>/agents.yaml` (`unitId`, `agentId`, `worktree`, `dispatchedAt`) as each lane launches, resolve from it before every `SendMessage`, and **lead with `TO: <TICKET-ID>`**. You reason in ticket ids and the harness addresses opaque ones; reconstructing the map from dispatch order has misrouted two corrections in one run, silently in both directions.
  >
  > misroute and report it. Every message you receive leads with `TO: <TICKET-ID>`;
- recorded: 2026-09-04
- expiry: none known

### A relayed sibling fact carries its provenance: B corrected CONTEXT.md on B's branch only
- rule: Label a sibling fact `PRESENT ON YOUR BASE` or `ON A SIBLING BRANCH ONLY`, and address a sibling's artifact by `git show <sha>:<path>`, never by worktree path.
- source: commands/start-multi.md:77 at c75ba88
- evidence:
  > In a stacked fleet most sibling facts are branch-local: "B already corrected `CONTEXT.md`" was true on B's branch and false on C's base, so C re-made the edit and guaranteed a conflict.
- recorded: 2026-09-05
- expiry: none known

### An adr= attribute on a resolved-design marker is not a reservation
- rule: Fold every marker's `adr=` into the fleet's allocation, re-derived against the pinned BASE plus every sibling branch, and rewrite the marker if it moved.
- source: commands/start-multi.md:79 at c75ba88
- evidence:
  > **An `adr=` attribute on a resolved-design marker is not a reservation** — it is the number that was free when `/design-multi` wrote the block, and lanes write their ADRs hours later, each in its own worktree. Fold every such number into this allocation: re-derive it against the fleet's pinned BASE plus every sibling branch and **rewrite the marker if it moved** — `git ls-tree <BASE> --name-only <adr-dir> | grep -q "ADR-$n" && echo "COLLIDED: $n"`.
- recorded: 2026-09-12
- expiry: none known

### A stall detector needs a terminal state and a positive control; one call sat 6h21m
- rule: Exclude passed/failed units, validate the detector against a directory just written to, and never end a turn awaiting a background agent with no timer.
- source: commands/start-multi.md:85; commands/start-multi.md:85 at c75ba88
- evidence:
  > **A stall detector needs a terminal state and a positive control.** Exclude units at `passed`/`failed` — without that a finished lane and a dead one give identical signals (no writes, no transcript, no commits), so the watchdog cries wolf exactly when the run is going well and gets muted right before it would matter. Validate it against a directory you just wrote to before trusting a negative. (`find -newermt '<relative>'` matches **nothing** on BSD/macOS, silently — use `-mmin -N`.)
  >
  > A notification that never comes is otherwise indistinguishable from work; one verifier call sat 6h21m on a refusal, 36% of a serial fleet's wall clock.
- recorded: 2026-09-12
- expiry: none known

### Rescue learnings on every unit completion; a worktree was deleted seconds after it reported
- rule: Copy `<worktree>/.work/learnings.md` to the run dir at completion, not at teardown.
- source: commands/start-multi.md:89 at c75ba88
- evidence:
  > another session on the machine once deleted a completed lane's worktree to reclaim disk, seconds after it reported, before step 6 was ever reached.
- recorded: 2026-09-05
- expiry: none known

### You own a diamond base; a .ts.orig passes every gate invisibly
- rule: A two-parent merge is the orchestrator's: theirs-then-regenerate for generated files, complete units for additive files, check for `*.orig`, then run the scoped gate on the base before cutting a child.
- source: commands/start-multi.md:99; commands/merge-multi.md:89 at c75ba88
- evidence:
  > **You own a diamond base.** A two-parent merge is yours, not the child's — a base that does not compile surfaces deep inside the child. Generated files: `git checkout --theirs`, then re-run the generator, never hand-merge. Hand-authored additive files: splice **complete** units — a marker-strip breaks on array tails and interleaves two partial blocks at their shared prefix. Check for `*.orig` residue before committing (a `.ts.orig` is not compiled, so it passes every gate invisibly).
  >
  > - Check for `*.orig` residue before committing. A `.ts.orig` is not compiled, so it passes every gate invisibly.
- recorded: 2026-09-19
- expiry: none known

### A stacked child re-diffs against the parent's tip and forward-merges after its verify-build
- rule: Record `parentTipAtCut`, re-diff the child's scope against it, and tell the child what the parent changed after the cut and why it matters.
- source: commands/start-multi.md:101; commands/start-multi.md:103 at c75ba88
- evidence:
  > **A stacked child's scope is re-diffed against the PARENT's tip, not the integration base.** Drift in step 0 was computed against `BASE`; a child's real base is `parentTipAtCut`, and against it part of the child's scope list is already done and its `file:line` refs have moved (two scope items and +5/+25 line drift in one cut). At cut time diff `int..parentTip`, intersect with the child's named files and symbols, and hand it an explicit *already done by parent / refs moved in these files* list.
  >
  > **A child cut early is stranded on a base its parent then fixes.** Cutting at build-complete is the right throughput call, but everything `verify-build` exists to find lands *after* the cut. Record `parentTipAtCut`; the child forward-merges after that `verify-build` and again before opening its PR. Better: diff `parentTipAtCut..parentHEAD` yourself and **tell the child what changed and why it matters to its work** — it cannot notice that a commit it never touched invalidates an assumption inside its own slice, and the gap does not surface as a failure.
- recorded: 2026-09-05
- expiry: none known

### Verify the sibling overlap you assumed: seven shared files conflicting in three
- rule: At report time, `comm -12` the file lists and `git merge-tree` the merge base.
- source: commands/start-multi.md:111 at c75ba88
- evidence:
  > One overlap claim carried by both tickets turned out to be seven shared files conflicting in three.
- recorded: 2026-09-04
- expiry: none known

### Pinned counters: report each lane's delta; 704 appeared on no branch
- rule: For every pinned counter more than one lane touched, report the delta and the base it was measured from; the merged pin is `base + Σ deltas`, recomputed and verified by running the suite.
- source: commands/start-multi.md:113; commands/merge-multi.md:91; agents/unit-lane.md:289-291 at c75ba88
- evidence:
  > the merged pin is `base + Σ deltas`, a number on no branch (689 + 8 + 3 + 2 + 1 + 1 = 704 across five lanes).
  >
  > One fleet's correct value (704) appeared on no branch.
  >
  > **A pinned counter you move is reported as a DELTA with the base you measured
  > it from** — never the final number, and never a sibling's number, which is
  > right on its base and wrong on yours. The merge computes `base + Σ deltas`.
- recorded: 2026-09-05
- expiry: none known

### Collapse follow-ups before reporting: 82 follow-ups is debt
- rule: Dedupe across units, separate needs-a-decision from needs-work, cluster by theme, and report raw → collapsed.
- source: commands/start-multi.md:115 at c75ba88
- evidence:
  > ("82 follow-ups" is debt; "8 tickets, 6 one-liners, 5 questions, 13 closes" is a plan).
- recorded: 2026-09-05
- expiry: none known

### Recon is a hint: compute base-sensitive facts with git show <BASE>:<path>
- rule: Anything base-sensitive is computed against the pinned BASE, never a working-dir grep whose HEAD has drifted.
- source: commands/start-multi.md:141; commands/plan.md:38 at c75ba88
- evidence:
  > - **Recon is a hint, not a fact.** Compute anything base-sensitive against the pinned BASE (`git show <BASE>:<path>`), never a working-dir grep whose HEAD drifts from it. Every handed-down fact is a claim with a provenance and an expiry — EVIDENCE.md (`../EVIDENCE.md`) §3.
  >
  > against the integration base (`git show <BASE>:<path>` or a repo-wide grep) and **record where each resolves in the slice**
- recorded: 2026-09-05
- expiry: none known

## commands/plan.md

### A slice is cuttable only when everything it names resolves at the base
- rule: Resolve every symbol and every data input a slice names against the base and record where; four of seven lanes found a premise false in under a minute on symbols a cut-time grep would have shown absent.
- source: commands/plan.md:38 at c75ba88
- evidence:
  > one slice read an epic field `run.yaml` never had and a run id the path script rejected, and all of it surfaced at the verifier. Four of seven lanes in another fleet found their slice's premise false in under a minute each, on symbols a grep at cut time would have shown absent.
- recorded: 2026-09-12
- expiry: none known

### Every-X-must-do-Y needs a structural oracle: an N+1th appender caught days later
- rule: A census guard enumerates call sites from source, asserts the negative form, names the new file in its failure, and excludes comments.
- source: commands/plan.md:39; commands/plan.md:39 at c75ba88
- evidence:
  > one such guard caught a sibling lane's N+1th appender days later.
  >
  > Such a guard matches source text, so it must **exclude comments** — one flagged two files that mention the token only in prose, one of them arguing *for* the seam.
- recorded: 2026-09-12
- expiry: none known

### Confirm the existing suite exists: three slices named suites that did not exist
- rule: Where an oracle says the existing suite, record its path at plan time.
- source: commands/plan.md:40 at c75ba88
- evidence:
  > Three slices once named suites that did not exist (the rules had pin JSON, no `.test.ts`), which turned a "run the tests" slice into a "write the tests" slice mid-flight and changed its size.
- recorded: 2026-09-05
- expiry: none known

### A gate text carries the obligation, never the derived fact: there were four; toHaveLength(199)
- rule: Every code-describing field in slices.yaml is an instruction to observe and cite, re-checked against HEAD when written, never an observation number from memory.
- source: commands/plan.md:41; commands/plan.md:41 at c75ba88
- evidence:
  > "grep every declaration site and report the count you observed" — not "declared in THREE places" (there were four, and the fourth was a closed-enum runtime defect);
  >
  > A mid-run hint written from the design's intent ("a property, not a literal") once contradicted a test an earlier slice had already committed (`toHaveLength( 199 )`).
- recorded: 2026-09-12
- expiry: none known

### Split a sweep over 10 files or 200 sites: the cap exists for the fix round
- rule: Record `surface:` counted at the base with a positive control; above 10 files or 200 sites split into ordered sub-slices unless atomic.
- source: commands/plan.md:43; skills/vertical-slicing/SKILL.md:128 at c75ba88
- evidence:
  > The cap exists for the fix round, not the first pass: a ~26-file, ~1,140-call-site billing sweep ran 3 h 20 m and escalated on two small findings, where six sub-slices would have escalated one.
  >
  > **The ceiling belongs to the fix round**: a sweep over 10 files or 200 sites is split (`/plan` Step 3), because one finding anywhere in it re-opens the whole sweep.
- recorded: 2026-09-13
- expiry: none known

### Tautology: the expected value comes from expected_from and expected_source
- rule: Every behavioural scenario says where its expected value comes from and cites it; a value recomputed the way the code computes it passes by construction.
- source: commands/plan.md:45; skills/vertical-slicing/SKILL.md:119; agents/executor.md:38; commands/build.md:153; skills/design-map/SKILL.md:319; skills/design-map/SKILL.md:340 at c75ba88
- evidence:
  > - **Tautology.** *"The assertion recomputes the expected value the way the code does, so it passes by construction and can never disagree with the code."* Every behavioural scenario says where its expected value comes from — `expected_from: literal | worked-example | spec | existing-behaviour` — and everything but a hand-checked literal cites it in `expected_source:` (`file:line`, doc section, ticket). **The citation is the check**: "the spec says so" with nothing to open is exactly how a recomputation gets written down as a fact. A `kind: structural` scenario carries neither — its expected value *is* the census it states.
  >
  > - **Tautology** — the assertion recomputes the expected value the way the code does, so it passes by construction and can never disagree with the code. The expected value must come from an independent source: a known-good literal, a worked example, the spec. `expected_from:` names which, and `expected_source:` cites it for everything but a literal. The citation is the check.
  >
  > - **Say where each expected value came from.** The scenario carries `expected_from:` and, unless it is a hand-checked literal, `expected_source:`; the assertion you write uses **that** value, read from that source. A value you computed the way the implementation computes it passes by construction and can never disagree with the code — red before the code, green after, and wrong throughout.
  >
  > - **recomputed expectation** — the assertion derives its expected value the way the implementation does, rather than from the scenario's `expected_from:`/`expected_source:`. It passes by construction and can never disagree with the code;
  >
  > behavioural scenario carries no `expected_from:`, names one outside
  >
  > `expected_from:` names an independent source and `expected_source:` cites it —
- recorded: 2026-09-19
- expiry: none known

### Reachability: the probe is named at plan time; an erasure suite stayed 8/8 with PII unencrypted
- rule: Every slice declares `probe:`, the one production line whose deletion must turn its oracle red, before a test exists that has to survive it; a probe that does not go red is a finding, never an errand.
- source: commands/plan.md:46; commands/plan.md:49; agents/verifier.md:50; agents/executor.md:37; skills/vertical-slicing/SKILL.md:120; skills/design-map/SKILL.md:342-346; skills/design-map/SKILL.md:316 at c75ba88
- evidence:
  > - **Reachability.** Every slice declares `probe:` — the **one-line mutation of production code that must turn this slice's oracle red**. Name it here, at plan time, before a test exists that has to survive it; named afterwards it is invented to match whatever was built. This is the most expensive class on record: an erasure suite that composed its own subject stayed 8/8 green with the production harness spread removed, and PII shipped unencrypted with every gate green. A probe that names the test rather than the production line is not a probe.
  >
  > `check-plan` refuses `slice-unprobed` and `scenario-unsourced` (`why=no-expected-from|unknown-expected-from|no-expected-source`).
  >
  > **a test that composes its own subject cannot be an oracle for that subject's production wiring** (an erasure suite that built `EncryptedEventStore` itself stayed 8/8 green with the harness spread removed — and nothing else guarded that spread: PII shipped unencrypted with every gate green)
  >
  > A probe that does **not** go red is a **finding, not an errand you failed**: the oracle is green about something it does not reach, which is how an erasure suite stayed 8/8 green with the production harness spread removed and PII shipped unencrypted with every gate green.
  >
  > - **Reachability** — `probe:` is the one production line whose deletion must turn the oracle red, named at plan time so it cannot be invented afterwards to match what was built. An erasure suite that composed its own subject stayed 8/8 green with the production harness spread removed, and PII shipped unencrypted with every gate green.
  >
  > how a recomputation is written down as a fact. *Reachability*: `probe:` is the
  > production line whose deletion must turn the oracle red, named at plan time so
  > it cannot be invented afterwards to fit what was built — an erasure suite that
  > composed its own subject stayed 8/8 green with the production harness spread
  > removed. *Discrimination*: the failure must be an assertion with values, never a
  >
  > - `outcome=fail reason=slice-unprobed slice=<id>` (exit 1) — a slice declares no
- recorded: 2026-09-19
- expiry: none known

### Discrimination is a property of the run, not a plan field
- rule: The RED must fail by assertion with values; enforced where the evidence exists (the executor and /build's fix-round causes), never as a YAML claim.
- source: commands/plan.md:47; skills/vertical-slicing/SKILL.md:121 at c75ba88
- evidence:
  > - **Discrimination.** The oracle must fail **by assertion, with values** — never by hang, timeout, crash, import error, empty collection or skipped suite. This one is *not* a plan field on purpose: it is a property of the RED the executor actually watches, so it is enforced where that evidence exists (`executor.md`, and `/build`'s fix-round causes). A `discriminates: true` in YAML would be a claim, and a claim is what the gate exists to stop taking on trust.
  >
  > - **Discrimination** — the oracle fails by **assertion, with values**: never a hang, timeout, crash, import error, empty collection or skipped suite. This one is not a plan field, deliberately — it is a property of the RED the executor watches, so it is enforced there and in `/build`'s fix-round causes rather than asserted in YAML.
- recorded: 2026-09-19
- expiry: none known

### Name the unit's seams before its oracles: 738 tests green with both wiring lines deleted
- rule: Seams are named once per unit (fewest, highest, existing over new, ideally one) and every slice's oracle lands at one; a `kind: structural` scenario asserts its negative half; check-plan refuses plan-unseamed, slice-unseamed, unnamed-seam and an undefended extra or new seam.
- source: commands/plan.md:50; commands/plan.md:86; commands/build.md:150; agents/executor.md:30; agents/verifier.md:27; skills/design-map/SKILL.md:224-231; skills/design-map/SKILL.md:350-359; skills/design-map/SKILL.md:305; skills/design-map/SKILL.md:309; skills/design-map/SKILL.md:314; skills/vertical-slicing/SKILL.md:113 at c75ba88
- evidence:
  > - **Name the unit's seams BEFORE its oracles — fewest, highest, existing over new.** Write down the seams this unit will test at, as a top-level `seams:` block, and let every slice's `seam:` point at one of them. **The ideal number is one.** Prefer an existing seam to a new one, and the highest one that can still observe the claim — the slice's oracle then lands where the behaviour is *composed*, not where a unit happens to be convenient. Left unpressured, eight slices invent eight oracle locations and each is an independent chance to assert below the level the claim lives at: the worst defect in the corpus is exactly that — the oracle sat at the unit rather than the composition root, so **both wiring lines could be deleted with `tsc` clean and 738 tests green.** Record each seam's `at:` (the `file:line` it resolves to at the base, checked when written — the same rule as every other code-describing field above) and its `kind:` (`existing` or `new`). **The first seam is free; every seam after it, and every `kind: new` one, owes a one-line `why:`** — why the already-named seams cannot hold this slice's claim. `check-plan` refuses a plan with no `seams:` (`reason=plan-unseamed`), a slice with no `seam:` (`slice-unseamed`), a slice naming a seam the unit never declared (`unnamed-seam`), and an undefended extra or new seam (`seam-unstructured why=extra-unjustified|new-unjustified`). *Highest* stays a judgement — what is mechanical is that the choice is written down, defended and reviewable instead of being made eight times in silence.
  >
  > - **`kind: structural` keeps prose on purpose**, for the "every X must do Y" rules Step 3 above already mandates a structural oracle for. Given/When/Then has no room for the negative half — *"and no module outside `<owner>`…"* — and that negative half is what caught the worst defect in the corpus: a composition root whose two wiring lines could both be deleted with `tsc` clean and 738 tests green. A structural scenario carrying Given/When/Then as well is refused; one of the two is decoration and nobody can tell which.
  >
  > it is how a composition root's two wiring lines were both deleted with `tsc` clean and 738 tests green.
  >
  > which is how a composition root's two wiring lines were both deleted with `tsc` clean and 738 tests green.
  >
  > the composition-root case where both wiring lines could be deleted with `tsc` clean and 738 tests green.
  >
  > - **`kind: structural` keeps prose, deliberately.** A census assertion — *"every
  >   appender declares it, and no module outside `<owner>` appends"* — has a
  >   negative half that Given/When/Then has no room for. `/plan` already mandates
  >   that form for an "every X must do Y" rule, and it is the form that caught the
  >   worst defect in the corpus (a composition root whose two wiring lines could be
  >   deleted with 738 tests still green). Carrying both is refused
  >   (`walk-structural-gwt`): one of them is then decoration and nobody can tell
  >   which.
  >
  > **The seams are named once per unit, before the oracles.** Fewest, highest,
  > existing over new — the ideal number is one. Unpressured, eight slices invent
  > eight oracle locations, and each is an independent chance to assert below the
  > level the claim lives at; that is the shape of the worst defect in the corpus,
  > where the oracle sat at the unit rather than the composition root and both
  > wiring lines could be deleted with `tsc` clean and 738 tests green. *Highest* is
  > a judgement and stays one — what is checkable is that the seam is named,
  > located (`at:`) and defended, so the first seam is free and every one after it
  > owes a line saying why the named ones cannot hold the claim. A cap would be
  > wrong: some units genuinely need two. Silence was what was wrong.
  >
  > - `outcome=fail reason=plan-unseamed` (exit 1) — the plan declares no `seams:`.
  >
  > with no `why:` (`why=extra-unjustified|new-unjustified`). The name is emitted
  >
  > - `outcome=fail reason=unnamed-seam slice=<id> seam=<name>` (exit 1) — a slice's
  >
  > `seams:` is the unit's answer to *"where do we test this"*, written once and inherited by every oracle. Prefer an **existing** seam to a new one and the **highest** one that can still observe the claim, and keep the count down — the ideal is one. Left unpressured, eight slices invent eight oracle locations, and each is an independent chance to assert below the level the claim lives at: the worst defect on record is that shape — the oracle sat at the unit, not the composition root, so both wiring lines could be deleted with `tsc` clean and 738 tests green. *Highest* is a judgement and stays one; what is mechanical is that the seam is **named, located and defended** — `check-plan` refuses `plan-unseamed`, `slice-unseamed`, `unnamed-seam` and an undefended extra or new seam. A `why:` is the entire cost of a second seam, deliberately: a cap would be wrong (some units need two) and silence was what was wrong before.
- recorded: 2026-09-19
- expiry: none known

### Slice order follows oracle-provability, not the ticket's deploy sequence
- rule: A slice whose oracle asserts new behaviour while the old policy is still registered is structurally red; put the deletion first or split the oracle, and record the deploy sequence in the PR body.
- source: commands/plan.md:51 at c75ba88
- evidence:
  > a slice whose oracle asserts the new behaviour while the old policy is still registered is structurally red (both restore → double).
- recorded: 2026-09-05
- expiry: none known

### Unattended branch: no user to approve, by construction
- rule: In a fleet run /plan skips the review, writes `review: unattended`, and marks every candidate unconfirmed without copying one into an oracle.
- source: commands/plan.md:64 at c75ba88
- evidence:
  > Inside a `/start-multi` fleet run there is **no user to approve, by construction** — this step reads as a hard gate with no exit, so an agent must decide on its own whether the instruction applies to it, and a literal one stalls here.
- recorded: 2026-09-17
- expiry: none known

### Both zero-first-pass-green runs had no map: scenarios reach the unit with no map
- rule: Every slice carries `scenarios:` as Given/When/Then (or `kind: structural`); a decided fork's walk is the scenario, and check-plan refuses slice-unscened, because oracle-wrong is 41% of 966 classified fix rounds while ripple is 6%.
- source: commands/plan.md:87; skills/design-map/SKILL.md:325-334; skills/design-map/SKILL.md:299; skills/design-map/SKILL.md:211-217; skills/vertical-slicing/SKILL.md:111; skills/grill/SKILL.md:84 at c75ba88
- evidence:
  > Both zero-first-pass-green runs on record were `review: unattended` with no map, so every oracle in fifteen slices was written freehand and 41% of all fix rounds since have been `oracle-wrong`.
  >
  > **`scenarios:` is the half of the contract that reaches a unit with no map at
  > all**, and that is the half that was costing: both measured 0%-first-pass-green
  > runs were `review: unattended` with no `map.json`, so this whole candidate
  > pipeline emitted nothing and every oracle in fifteen slices was written freehand
  > from prose. A walk contract enforced only inside `candidates` would have left
  > exactly those runs untouched. `oracle:` keeps its meaning — the narrative of the
  > test; `scenarios:` is what the executor must make true, in a form it cannot
  > quietly re-interpret. The `candidate-in-oracle` search covers a slice's
  > `scenarios:` as well as its `oracle:`, or renaming the field would have been the
  > whole of the bypass.
  >
  > - `outcome=fail reason=slice-unscened slice=<id>` (exit 1) — a slice carries no
  >
  > **The measured reason this is a rule and not a suggestion.** Across 966
  > classified fix rounds, `oracle-wrong` — the test encoded the wrong rule — is
  > **41%**, the largest single cause, and in the runs where it was itemised *every*
  > round came from a verifier finding and *none* from a red test. A test built from
  > prose goes red before the code exists and green after, and is still wrong: RED →
  > GREEN is an anti-tautology gate, and it cannot tell whether the rule asserted is
  > the rule that was decided. The only cause slice size controls, `ripple`, is 6%.
  >
  > It is required on every slice because the measured failure is not that slices are too big — across 966 classified fix rounds `ripple`, the only cause slice size controls, is **6%**, while `oracle-wrong` (the test encoded the wrong rule, went green, and was caught only by the verifier) is **41%**. Where a design map's fork was decided and its walk confirmed, that walk *is* the scenario; where there is no map, write them here — the two runs on record with 0% first-pass green had no map at all.
  >
  > This is the cheapest check in the whole flow, and it is the one aimed at the largest measured cost: across 966 classified fix rounds, `oracle-wrong` — the test encoded the wrong rule, went green, and was caught only by the verifier — is **41%**, while slice size (`ripple`) is 6%. An owner reading a `then:` catches a mis-aimed oracle in seconds; the verifier catches the same thing three agent-hours later and re-pays a whole executor context.
- recorded: 2026-09-19
- expiry: a re-measured fix-round corpus changes the oracle-wrong share materially

### Act on check-plan's reason; never invent a seams entry to match a slice
- rule: Each check-plan refusal has one remedy, and a seam refusal goes back to Step 3 rather than adding YAML that re-buys the eight-oracle-locations failure.
- source: commands/plan.md:92 at c75ba88
- evidence:
  > **Then run `design-map check-plan .work/slices.yaml`** in both the attended and the unattended branch. On `outcome=fail`, act on its `reason=` and re-run: `reason=candidate-in-oracle` → remove the copied candidate example from that `slice=`'s `oracle`; `reason=unattended-confirmed` → reset that candidate's status back to `status: unconfirmed`; `reason=slice-unprobed` → name the production line whose deletion must turn that slice's oracle red, never the test file; `reason=scenario-unsourced` → say where the expected value comes from and cite it, and if the honest answer is "from how the code will compute it", the scenario is the thing to fix, not the field; `reason=plan-unseamed` / `slice-unseamed` / `unnamed-seam` / `seam-unstructured` → go back to Step 3 and name the seam properly, **never by inventing a `seams:` entry to match whatever a slice already said** — that reverses the contract and re-buys the eight-oracle-locations failure with one extra line of YAML. Never proceed on a failing plan. `/build`, the executor and the verifier all ignore `candidateOracles:` — nothing in the build or its gates blocks on the mark.
- recorded: 2026-09-19
- expiry: none known

### Route mechanical slices to sonnet; absent means opus
- rule: /plan is the only step that knows which slices are mechanical; an unrouted slices.yaml sends the whole build through the most expensive model.
- source: commands/plan.md:110; skills/vertical-slicing/SKILL.md:98 at c75ba88
- evidence:
  > This is the only place in the flow that knows which slices are hard, and an unrouted `slices.yaml` sends the whole build through the most expensive model available.
  >
  > model: sonnet                  # OPTIONAL. Present only on mechanical slices; absent means opus.
- recorded: 2026-09-13
- expiry: none known

## commands/merge-multi.md

### A PR merged into the wrong target returns exit 0 and shows MERGED
- rule: Stop on any unit whose base is not `int/<run-id>`; retarget or exclude it, because a wrong-target merge is the one precondition with no downstream tell.
- source: commands/merge-multi.md:40 at c75ba88
- evidence:
  > A PR merged into the wrong target returns exit 0, shows `MERGED`, and delivers nothing where you meant it — the merge itself reports success, so this is the one precondition with no downstream tell.
- recorded: 2026-08-14
- expiry: none known

### The flow/concerns status is advisory; /merge-multi is the hard block
- rule: A private free-plan repo cannot require a commit status, so /merge-multi rules each unit's concerns itself from files at its head commit and refuses anything but outcome=pass.
- source: commands/merge-multi.md:49; commands/verify-build.md:283 at c75ba88
- evidence:
  > `/verify-build` posted a `flow/concerns` commit status on each unit's head, but that status is **advisory only** (a private free-plan repo cannot make it required) and a human can merge over a red one. **This command is the hard block** (design F4/C2): before merging a unit (step 2), rule it yourself, from files taken off *its own head commit* — never the working tree, never a sibling's checkout, and never by reading the GitHub status back.
  >
  > In a private repository on GitHub's free plan, branch protection and rulesets are unavailable: a status cannot be required, so the red mark is advisory in a single flow, and a human can merge over `flow/concerns` = failure.
- recorded: 2026-09-12
- expiry: the repo can require the flow/concerns status through branch protection

### A clean merge does not discharge a cross-unit obligation: written three times, merged away
- rule: List every `owesSiblings` obligation before merging, check each against the merged file whether or not git conflicted, and apply it with a test that is red without it.
- source: commands/merge-multi.md:93 at c75ba88
- evidence:
  > One was written three times — design, state file, PR body — and merged away cleanly with every gate green, because no unit's tests could reach the intersection.
- recorded: 2026-09-12
- expiry: none known

### Reconcile declared − landed: a nine-unit run landed eight with every gate green
- rule: Compute `declared − landed` from run.yaml before opening the integration PR and state it under its own heading; the branch name is not evidence of scope.
- source: commands/merge-multi.md:124 at c75ba88
- evidence:
  > One line of set arithmetic against state you already hold — without it a nine-unit run once landed eight with every gate green and correct.
- recorded: 2026-09-12
- expiry: none known

### Run /merge-multi in a fresh session
- rule: The fleet conversation is the run's largest context and none of it is needed to land; re-invoking it re-sends all of it.
- source: commands/merge-multi.md:9 at c75ba88
- evidence:
  > **Run it fresh; do not reopen the fleet conversation.** That session is the largest context in the run — it dispatched N lanes, collected N escalations, aggregated N state files — and re-invoking it to perform a mechanical merge sequence re-sends all of it. Everything this command needs is on disk (`run.yaml`) or on GitHub (`gh pr view`). The bookkeeping is cheap; the memory is not.
- recorded: 2026-08-14
- expiry: none known

## commands/start.md

### The records guard checks the fleet path too
- rule: The unprocessed-learnings warning covers `.work/multi/*/learnings.md`, the run's sole surviving copy after teardown; a guard checking one literal path is a warning that does not print.
- source: commands/start.md:17 at c75ba88
- evidence:
  > **The fleet path is not an afterthought:** `/start-multi` step 6 aggregates every lane's buffer there and step 7 then deletes the worktrees the originals lived in, so that file is the run's **sole surviving copy** — and a guard that checks one literal path is a warning that does not print, which looks exactly like nothing being wrong.
- recorded: 2026-09-10
- expiry: none known

### A marker that survives a new /start is worse than no marker
- rule: /start deletes and rewrites `.work/mode.yaml` and deletes `.work/lane.yaml` outright (except a brief naming this worktree and this branch); nothing else in `.work/` is ever erased.
- source: commands/start.md:29 at c75ba88
- evidence:
  > This is the load-bearing half of the marker, not a formality: everything else in `.work/` — `design.md`, `slices.yaml`, `passes:`, `design-snapshot/` — is residue that accumulates and is never erased, so a workspace left over from the previous branch reads exactly like the current one's. Delete any existing `.work/mode.yaml` or `.work/lane.yaml` outright and write a fresh `mode.yaml`; never merge with, patch, or preserve a field from what was there. A marker that survives a new `/start` is worse than no marker, because it is confidently wrong about which work item you are on.
- recorded: 2026-09-06
- expiry: none known

### Capture a baseline on a freshly built tree: 134 × TS6305 + 24 became 0 + 1
- rule: An unresolved `.d.ts` cascades into ordinary-looking type errors, an incremental typechecker under-reports on a second run, and a baseline taken that way is never published.
- source: commands/start.md:56; commands/start.md:57; agents/provisioner.md:55 at c75ba88
- evidence:
  > - **Capture on a freshly built tree.** When the toolchain cannot resolve a package's `.d.ts`, the failure cascades into ordinary-looking `TS2345`/`TS2322`/`TS2339` in every importing file — indistinguishable by inspection from genuine type errors. So *"filter out the known-noise code and trust the remainder"* is not a safe protocol: the remainder is contaminated by the same cause. (Measured once: `134 × TS6305 + 24 "real"` became `0 + 1` after re-emitting declarations.) A baseline taken with unresolved-dependency errors present is inflated and must not be published.
  >
  > - **An incremental typechecker under-reports on a second run** — it re-checks almost nothing. Clear the incremental state for the suites you are capturing, or the count is not comparable.
  >
  > **Re-emit composite `build/*.d.ts`.** A worktree whose branch was switched leaves phantom `TS6305` cascades that a transpile-only build never surfaces.
- recorded: 2026-08-08
- expiry: none known

### The eager baseline capture is withdrawn; capture on demand for the red suites by name
- rule: /start and the provisioner record the base sha and "not captured — capture on demand"; the base side is only needed on a red HEAD.
- source: agents/provisioner.md:194; agents/provisioner.md:192; commands/start.md:50; commands/start.md:52 at c75ba88
- evidence:
  > **The eager capture is withdrawn** (2026-08-24). The argument for it was "paying once here beats N lanes paying in parallel" — but the base side of a baseline diff is only needed when a lane's `HEAD` is **red**, and a fleet's lanes are usually green. Paying once per *worktree* to serve the minority case is the same unbounded cost one level down. A lane that goes red captures the base side then, for **its red suites by name**.
  >
  > Write `.work/known-baseline-failures.md` exactly as `/start` step 4 specifies: the base **sha and branch**, and **"not captured — capture on demand"**. Seconds, no test run.
  >
  > Write `.work/known-baseline-failures.md` with the base **sha and branch**, and the line **"not captured — capture on demand"**. That is the whole step. It costs seconds.
  >
  > **Do not run the test suite or a full typecheck here.** A baseline is the *base-side* half of a diff, and that half is only ever needed when `HEAD` comes up **red**. When `HEAD` is green with parsed counts, zero `PASS→FAIL` flips are possible and the base-side run was pure cost — see full-gate (`../skills/full-gate/SKILL.md`) § "Reading the verdict", which already says exactly this. Capturing eagerly pays it on every unit of every run to serve the minority case.
- recorded: 2026-08-24
- expiry: none known

### A wrong shared baseline is worse than none
- rule: Lanes chase failures that were never theirs or wave real ones through as pre-existing cover; a capture from a run that executed nothing is recorded inconclusive, never as an empty failure set.
- source: agents/provisioner.md:203; commands/start.md:54 at c75ba88
- evidence:
  > a **wrong shared baseline is worse than none** (lanes then chase failures that were never theirs, or wave real ones through as pre-existing cover)
  >
  > because a wrong baseline is worse than none (a lane either chases failures that were never its own or, in the dangerous direction, waves real ones through as pre-existing cover)
- recorded: 2026-08-24
- expiry: none known

## commands/evolve.md

### Redundancy is invisible across files: 3 files / 1,487 words collapsed into 1 / 1,439
- rule: Prune redundant rules across the artifacts loaded together; the duplication surfaces only when the content is moved.
- source: commands/evolve.md:18 at c75ba88
- evidence:
  > one real audit collapsed 3 files / 1,487 words into 1 file / 1,439 by inlining, and the duplication only surfaced during the move.
- recorded: 2026-09-04
- expiry: none known

### Anecdote outweighing rule: compress the story to the clause that makes it credible
- rule: Keep the rule, keep one clause of the story.
- source: commands/evolve.md:19 at c75ba88
- evidence:
  > 3. **Anecdote outweighing rule.** The behavioural instruction is one sentence and the story justifying it is a paragraph. Keep the rule, compress the story to the clause that makes it credible ("three lanes once picked the same `ADR-057`"). The story is what makes a rule *stick* on first read and what makes the artifact unreadable on the twentieth — one clause buys most of the first at little of the second.
- recorded: 2026-09-04
- expiry: none known

### There is a split floor: a 468-word skill with 668 and 351-word references
- rule: Below the floor inlining wins outright; a split you can delete beats a split you have to verify forever.
- source: commands/evolve.md:44 at c75ba88
- evidence:
  > - **There is a floor, and below it inlining wins outright.** Measured case: a 468-word skill whose two references were 668 and 351 words — smaller than its own references combined. **A split you can delete beats a split you have to verify forever.**
- recorded: 2026-09-04
- expiry: none known

### Split by trigger, never by topic
- rule: Content may leave an artifact only when its loading is gated on a condition something already evaluates and acts on.
- source: commands/evolve.md:45 at c75ba88
- evidence:
  > - **Split by trigger, never by topic.** Content may leave only when its loading is gated on a condition something *already evaluates and acts on*. "Fleet mechanics" is a topic and makes an unsafe split; "this unit checks out 2+ repos" is a trigger and makes a safe one.
- recorded: 2026-09-04
- expiry: none known

### Explanation may be referenced. Behavior may not
- rule: Ask what happens when the pointer is not followed; if the artifact still acts correctly and only loses the why, the split is safe.
- source: commands/evolve.md:46 at c75ba88
- evidence:
  > - **Explanation may be referenced. Behavior may not.** Ask what happens when the pointer is *not* followed. If the artifact still acts correctly and merely loses the *why*, the split is safe.
- recorded: 2026-09-04
- expiry: none known

### For behavior use a subagent: a split with loading probability 1
- rule: Behavior that must leave a parent goes to a subagent dispatched at the moment it applies, never to a reference file.
- source: commands/evolve.md:47 at c75ba88
- evidence:
  > - **For behavior, use a subagent instead — a split with loading probability 1.** Fresh context, dispatched at the moment it applies, nothing competing. What must *not* go: anything the parent is required to verify for itself.
- recorded: 2026-09-04
- expiry: none known

### Splitting is not a token optimisation: 97% cache reads, 1–4% of ~210k per turn
- rule: Split for attention; if the stated reason is cost, the lever is elsewhere.
- source: commands/evolve.md:48 at c75ba88
- evidence:
  > - **Splitting is not a token optimisation.** Measured on a real fleet run, cache reads were **97% of raw tokens**, and an artifact's own text is 1–4% of a typical agent's ~210k per-turn context. When the split content *is* needed it is loaded anyway, so the saving is zero exactly when it matters. Split for **attention**; if the stated reason is cost, the lever is elsewhere.
- recorded: 2026-09-04
- expiry: a re-measured fleet run changes the artifact share of per-turn context materially

### The version bump is the release: two behaviour-changing commits shipped to no one
- rule: A plugin is copied into its version-keyed cache only when the version string changes; an unbumped edit merges cleanly and reaches nobody.
- source: commands/evolve.md:63; README.md:43 at c75ba88
- evidence:
  > A plugin is copied into its version-keyed cache only when that string changes, so an unbumped edit merges cleanly and reaches nobody — exactly how two behaviour-changing commits shipped to no one with every gate green (`docs/adr/ADR-001`).
  >
  > the bump is not bookkeeping, it is the release itself, because the install is a version-keyed cache that copies nothing when the string has not moved (see `docs/adr/ADR-001`, and the CI gate that now refuses the omission).
- recorded: 2026-09-04
- expiry: the plugin cache is keyed by content rather than version

### A PR that splits an artifact writes the eval scenario in the same pass
- rule: Every presence gate is corpus-wide, so a split is green whether the pointer is opened or not; a `must_open` scenario is the only evidence, and check-eval-coverage refuses an unguarded split.
- source: commands/evolve.md:65 at c75ba88
- evidence:
  > **A PR that splits an artifact writes the eval scenario in the same pass** — not a follow-up issue: this pass is the last moment anyone knows what the pointer was for. Every gate in `scripts/` asserts presence **corpus-wide** by design, so a split is green whether the pointer is ever opened or not. The only remaining evidence is a session that opened the file: a scenario in `scripts/eval/` asserting `must_open`, testing a rule that exists **only** behind the pointer (an answer the model could produce from priors proves nothing — the tool call is the evidence). `scripts/check-eval-coverage.py` refuses an unguarded split.
- recorded: 2026-09-04
- expiry: none known

### Does it still load: /verify-build, /start and create-readmodel were all dead
- rule: A malformed command silently never registers; run validate-plugins.py, do not eyeball it.
- source: commands/evolve.md:73 at c75ba88
- evidence:
  > (Real miss: `/verify-build`, `/start` and `create-readmodel` were all dead this way; one had never once loaded while another command referenced it.)
- recorded: 2026-09-04
- expiry: none known

## commands/run-report.md

### CLAUDE_PLUGIN_ROOT is substituted for hook invocations only; plugin executables go in bin/
- rule: In a command's bash block `${CLAUDE_PLUGIN_ROOT}` expands to empty; every enabled plugin's `bin/` is on PATH keyed by version, and the cache path pattern insists on a segment before the plugin name.
- source: commands/run-report.md:31; commands/verify-build.md:168; skills/esas-design/PREFLIGHT.md:28-35 at c75ba88
- evidence:
  > Do **not** reach for `${CLAUDE_PLUGIN_ROOT}` — it is substituted for *hook* invocations only, so in a command's bash block it expands to empty and the failure reads as a missing file rather than a missing variable.
  >
  > (`run-metrics` is on `PATH` from this plugin's `bin/`. `${CLAUDE_PLUGIN_ROOT}` is **not** available in a command's bash block — it is substituted for hooks only.)
  >
  > # `CLAUDE_PLUGIN_ROOT` is substituted for *hook* invocations only, so it is
  > # unset here and cannot answer this. `PATH` can: the cache `bin` directory of
  > # every enabled plugin is on it, and that directory is keyed by the version —
  > #     …/plugins/cache/<marketplace>/bett3r-ai-workflow/<version>/bin
  > # The marketplace directory happens to share this plugin's name, which is why
  > # the pattern insists on a path segment *before* the plugin one: without it the
  > # sibling `bett3r-pv3-ai-skills` under the same marketplace would read as this
  > # plugin, and report its version as ours.
- recorded: 2026-08-09
- expiry: Claude Code substitutes CLAUDE_PLUGIN_ROOT in command bash blocks

### A fleet unit is not found by branch, by construction
- rule: A lane's transcript is a subagent of the orchestrator's session and carries the orchestrator's branch; run-metrics resolves it through agents.yaml.
- source: commands/run-report.md:37 at c75ba88
- evidence:
  > **A fleet unit is not found by branch, by construction.** A `/start-multi` lane runs as a subagent of the *orchestrator's* session, so its transcript sits under that session and every record in it carries the orchestrator's branch and cwd, not the worktree's — every lane once reported "no transcripts found".
- recorded: 2026-09-06
- expiry: none known

### A unit of work is not a session: one branch spanned 26
- rule: Transcript metrics join on the git branch.
- source: commands/run-report.md:81 at c75ba88
- evidence:
  > - **A unit of work is not a session.** `/clear` and `/handoff` scatter one branch across many sessions — one real branch spanned 26. The join key is the git branch.
- recorded: 2026-08-09
- expiry: none known

### One session is not one branch either: byte-identical totals
- rule: Records are sliced by branch, or a session that touched six branches reports all six as each other's work.
- source: commands/run-report.md:82 at c75ba88
- evidence:
  > - **One session is not one branch either.** A session that touched six branches will report all six as each other's work unless records are sliced by branch. Three unrelated branches once reported byte-identical totals.
- recorded: 2026-08-09
- expiry: none known

### Wall time is not elapsed time: 3,587 minutes for an agent that worked 52
- rule: Every millisecond is classified (tool / reason / child / stalled), never subtracted.
- source: commands/run-report.md:83 at c75ba88
- evidence:
  > - **Wall time is not elapsed time.** `last − first` once claimed 3,587 minutes for an agent that worked 52. Every millisecond is classified, never subtracted.
- recorded: 2026-08-09
- expiry: none known

### Each /build invocation is its own ledger: 0% first-pass-green from 33% and 100%
- rule: First-pass green is read per build invocation, never merged across passes over the same slices.
- source: commands/run-report.md:85 at c75ba88
- evidence:
  > - **Each `/build` invocation is its own ledger.** Merging two passes over the same slices makes every slice look like it took a fix round — a real branch read 0% first-pass-green purely from that, when its two passes were 33% and 100%.
- recorded: 2026-09-13
- expiry: none known

### A single multi-hour call is a block, not throughput
- rule: A class dominated by one very long call is flagged rather than folded into the total.
- source: commands/run-report.md:56 at c75ba88
- evidence:
  > A class dominated by one very long call is flagged rather than left in the total. **A single multi-hour call is a block — an interactive prompt, a pager, a waiting permission — not throughput to optimise**, and treating it as cost sends you tuning something that was never slow.
- recorded: 2026-08-09
- expiry: none known

## commands/capture-learnings.md

### Mechanical → a deterministic check, full stop
- rule: A candidate guarding a mechanical pattern gets a check as the default disposition; prose is for judgement calls, and a thrice-recorded fix-round cause is red in check-repeat-causes until it has a disposition.
- source: commands/capture-learnings.md:17; commands/capture-learnings.md:21; commands/capture-learnings.md:128 at c75ba88
- evidence:
  > **Ask of every candidate, first: is the thing it guards against MECHANICAL?** A fixed syntactic pattern, a banned API, an import shape, a file-location rule, a census over call sites, a required field, an artifact that must exist. If it is, **it gets a deterministic check, full stop — building the check is the default disposition, and writing the rule is the fallback.** A rule that a future agent has to *remember* is not a control; it competes for attention with every other rule in the same artifact and loses quietly, and the same defect ships again with every gate green.
  >
  > this repo keeps that in `docs/causes.md`, with `scripts/check-repeat-causes.py` red until a thrice-recorded cause has an entry naming either the check that now fires or the judgement that no check can.
  >
  > - **Mechanical → a deterministic check, full stop.** Prose is for judgement calls, and a repeating fix-round cause is a disposition owed, not a number to quote.
- recorded: 2026-09-19
- expiry: none known

### The reviewer imposes standards, not the implementer
- rule: A judgement disposition goes where the verifier reads and a mechanical one in scripts/, never one more line in the executor's brief.
- source: commands/capture-learnings.md:23; commands/capture-learnings.md:129 at c75ba88
- evidence:
  > **Where the rule lands matters as much as whether it is written.** A standard is imposed by the **review** agent, not the implementation agent: the implementation agent is under the most context pressure at exactly the moment it would have to remember. So a mechanical disposition goes in `scripts/` and the gate; a judgement one goes where the **verifier** reads — never as one more line in the executor's brief.
  >
  > - **The reviewer imposes standards, not the implementer** — the implementer has the most context pressure exactly where it would have to remember.
- recorded: 2026-09-19
- expiry: none known

### Stale guidance is worse than no guidance: the gh api -X PATCH detour
- rule: A workaround for a local or transient condition is a bug report about the machine, not a learning.
- source: commands/capture-learnings.md:50 at c75ba88
- evidence:
  > (Real miss: a `gh api -X PATCH` detour written into `/verify-build` and distributed everywhere, solely because one machine's token lacked `read:org`. The token was fixable in a minute; the guidance would have misled every reader forever.)
- recorded: 2026-09-04
- expiry: none known

### A local file named after a plugin skill is a shadow: 887 lines beside 132
- rule: Before writing to `.claude/rules/<x>.md` or `.claude/skills/<x>/`, run check-skill-shadows; a shadow strands the learning in one repo.
- source: commands/capture-learnings.md:78; commands/capture-learnings.md:78 at c75ba88
- evidence:
  > usually a pre-extraction copy that has kept growing (887 lines beside the plugin's 132) and therefore *looks* more authoritative than the thing that owns it.
  >
  > in one host repo `ddd-patterns` collides and `code-style` genuinely is host-owned
- recorded: 2026-09-06
- expiry: none known

### Write the issue body to a file; --body is a shell string
- rule: Backticked paths in `--body "<markdown>"` are command-substituted away with exit 0; use `--body-file`.
- source: commands/capture-learnings.md:85-86; EVIDENCE.md:72 at c75ba88
- evidence:
  > # Write the body to a file first. `--body "<markdown>"` is a shell string: backticked paths, flags
  > # and symbols are command-substituted away, `gh` exits 0, and the loss is silent and partial.
  >
  > - **An unquoted shell context expands backticks in whatever text it carries** — double quotes are not protection; command substitution inside them is POSIX. A heredoc (`<<PY`) substitutes every backticked identifier before Python sees it, five `str.replace` calls match nothing, and the script prints its success message. The flow's highest-frequency instance is not a script but a *payload*: `gh … --body "<markdown>"` substitutes the same way, `gh` exits 0, most of the body survives, and two headings lose exactly the word they were about. `<<'PY'`, and `--body-file` for every `gh issue|pr create|comment`; and when a command should affect N things, print N and check it.
- recorded: 2026-09-06
- expiry: none known

## agents/executor.md

### The fixture owns anything ambient
- rule: An assertion reading PATH, HOME, TZ, locale, git config or installed-tool state sets or scrubs it in the fixture and asserts each branch against a synthesized value.
- source: agents/executor.md:36; EVIDENCE.md:20; agents/verifier.md:44 at c75ba88
- evidence:
  > - **The fixture owns anything ambient.** If an assertion reads `PATH`, `HOME`, `TZ`, locale, git config or installed-tool state, set or scrub it in the fixture and assert each branch against a **synthesized** value. Otherwise the verdict is a property of who ran it — green on your machine, red on CI, for no defect — and the repair under pressure is to loosen the assertion until the coverage is gone.
  >
  > - **Its environment differed.** An assertion reading ambient `PATH` / `HOME` / `TZ` / locale / git config / installed-tool state has a verdict that is a property of *who ran it* — green on the laptop, red on CI, for no defect. The fixture must set or scrub it, and each branch must be asserted against a synthesized value.
  >
  > 7. **Ambient-environment probe.** Does any new assertion read a value the fixture did not set — `PATH`, `HOME`, `TZ`, locale, git config, installed-tool state, network reachability? If so, **would it return a different verdict on CI than on this machine?** A test whose verdict is a property of who ran it is not a test; the fixture must set or scrub the value and assert each branch against a synthesized one. Both directions are findings: green-here/red-on-CI gets loosened until the coverage is gone, and its quieter inverse leaves a branch never exercised while appearing covered.
- recorded: 2026-08-08
- expiry: none known

### Two ways a guard cannot fail: a source-text pin matches commented-out code; a sync finally restores on the first microtask
- rule: A guard parses the specific literal rather than substring-searching the file, and a helper that swaps argv/env/cwd around an async subject is `async` and awaits inside the `try`.
- source: agents/executor.md:39 at c75ba88
- evidence:
  > Two ways a guard cannot fail: **a source-text pin matches commented-out code** (`source.includes('assertManifestFloor(')` is satisfied by `// await assertManifestFloor(`, and commenting a call out during a debug run is the likeliest way to lose one — strip comment lines, or parse the specific literal rather than substring-search the file); and **a helper that swaps `argv`/`env`/`cwd` around an async subject in a sync `finally` restores on the first microtask**, so every `.resolves` assertion passes vacuously — the helper must be `async` and `return await run()` inside the `try`.
- recorded: 2026-09-12
- expiry: none known

### A test asserting on an event drives the real producer: a credit note on the invoice's stream
- rule: A synthesized downstream event exercises the consumer against a fixture the producer can never emit; where a field is an identity or routing key, assert the resulting stream id.
- source: agents/executor.md:40 at c75ba88
- evidence:
  > a synthesized downstream event exercises the consumer against a fixture the producer can never emit, and one green suite pinned a credit note onto the invoice's stream.
- recorded: 2026-09-05
- expiry: none known

### A new directory gets a positive control
- rule: Drop a deliberately-broken `__probe.ts` and confirm the typechecker raises; a brand-new directory may not be covered by the include globs.
- source: agents/executor.md:41 at c75ba88
- evidence:
  > - **A new directory gets a positive control**: drop a deliberately-broken `__probe.ts` in it, confirm the typechecker raises the expected error, delete it. A brand-new directory may simply not be covered by the include globs, and "typecheck passed" is then "typecheck never looked".
- recorded: 2026-09-05
- expiry: none known

### Prose drift: seven of seven RETRYs were prose, zero code; 30–58-row all-yes tables
- rule: Before COMPLETED, re-read every docblock and doc sentence as a claim, open the source and quote the words that support it; a table of resolving `file:line`s is not that probe.
- source: agents/executor.md:47; agents/executor.md:47 at c75ba88
- evidence:
  > Seven of seven verifier RETRYs across two lanes were prose drift, zero code: the explanation drifts from the code more often than the code drifts from the design, and a wrong docblock is what misleads the next reader.
  >
  > three of four ADR slices in one run took a fix round behind 30–58-row all-"yes" resolution tables.
- recorded: 2026-09-13
- expiry: none known

### The stash stack is repo-global: never stash, reset --hard, checkout --, restore or clean
- rule: Compare against a baseline with `git stash create` + `git diff <object>`; any out-of-scope tracked change is surfaced, never committed.
- source: agents/executor.md:53; agents/scope-check.md:27; agents/provisioner.md:235; commands/commit.md:41; commands/build.md:194 at c75ba88
- evidence:
  > NEVER run `git stash` (or `pop`/`apply`/`drop`), `git reset --hard`, `git checkout .` / `git checkout -- <path>`, `git restore <path>`, or `git clean`. The stash stack is **repo-global**, shared across all worktrees — mutating it corrupts unrelated WIP. To compare against a baseline use `git stash create` + `git diff <object>`, or reason via `git diff` / `git status`. Before reporting COMPLETED, confirm your tracked changes match the slice's intended files — any out-of-scope tracked change is a red flag to surface, not commit.
  >
  > **Never mutate the working tree.** No `git stash` / `reset --hard` / `checkout --` / `restore` / `clean` — the stash stack is repo-global and shared across worktrees. Everything here is readable with `git diff` / `git status`.
  >
  > - **Never touch another unit's worktree or scratchpad**, and never run `git stash` / `reset --hard` / `checkout .` / `clean` — the stash stack is repo-global and shared across all worktrees.
  >
  > Stage **explicit paths** — never `git add -A` blindly over an unreviewed tree. Never use `git reset --hard`, `git checkout -- <path>`, `git restore <path>`, or `git stash` to "clean up" first — the stash stack is repo-global and shared across worktrees.
  >
  > Never use `git stash`/`reset --hard`/`checkout --`/`restore`/`clean` to "clean up" — the stash stack is repo-global.
- recorded: 2026-06-19
- expiry: lane-git-guard.sh (PreToolUse) blocks these commands in every lane; the prose then keeps only the sanctioned alternative

### Never negative-test a guard by mutating tracked files
- rule: Prove a guard fails on bad input in a throwaway scratch dir; never end a turn with a deliberate mutation in the tree.
- source: agents/executor.md:55 at c75ba88
- evidence:
  > **Never negative-test a guard by mutating tracked files.** Proving a guard fails on bad input is a real need; doing it in place means any interruption leaves the "bad input" in the tree. Copy the script to a throwaway scratch dir and run it against fixture inputs there (`REPO_ROOT` resolves via `dirname`). **Never end a turn with a deliberate mutation in the tree** — restore in the very next tool call and confirm with `git diff` before reporting. The mid-restore timeout is the obvious hazard; the worse one is simply stopping, because a stall leaves no failed action to notice — just a clean-looking pause with a deliberate regression sitting in the tree, which the next gate then runs against.
- recorded: 2026-08-08
- expiry: none known

### Redirect every gate's output and read the tail: 292k tokens of context per turn
- rule: A gate log read once is re-sent on every later turn; redirect to a file, read the tail, grep for the failure, never cat a log already summarised.
- source: agents/executor.md:57-60 at c75ba88
- evidence:
  > **Redirect every gate's output to a file and read only the tail.** `yarn build > /tmp/gate-build.log 2>&1; tail -40 /tmp/gate-build.log` — never the bare command. Two separate reasons, and the second is the expensive one:
  >
  > 1. A piped gate reports the *pipe's* exit code (`yarn build | grep | head` is unconditionally 0), so the verdict is a lie in the reassuring direction.
  > 2. **A gate log read once is re-sent on every turn after it.** Your context is re-transmitted whole to the model on each turn, so one 3,000-line build dump is not paid once — it is paid again for every remaining turn of your life. Measured on a real fleet run: executors averaged **292k tokens of context per turn** across 1,801 calls, and cache reads were 97% of that run's raw token bill. The largest single thing an executor controls about its own cost is how much command output it lets into its context. Read the tail, `grep` for the specific failure, and never `cat` a log you have already summarised.
- recorded: 2026-08-13
- expiry: the harness stops re-sending the whole context each turn, or a re-measured run shows a different split

### Run every command in the foreground: Bash auto-backgrounds at 600 s
- rule: A backgrounded job's completion re-invokes the main loop, never a subagent; recover a gate that crossed the ceiling with a blocking waiter on the pid or a sentinel file, never a re-run.
- source: agents/executor.md:64; agents/provisioner.md:233; commands/build.md:307 at c75ba88
- evidence:
  > **Run every build/test/git command in the foreground.** A backgrounded Bash job's completion re-invokes the *main* loop, never a subagent, so ending your turn to await one deadlocks you permanently. Note the ceiling that makes this more than a preference: Bash auto-backgrounds at 600 s, so a gate that exceeds it is backgrounded *against* your instruction. The recovery is a blocking waiter on the pid or a sentinel file — never a re-run, never arming a watch. And never pipe a gate — redirect it, per the rule above.
  >
  > - **Run every command in the foreground.** A backgrounded Bash job's completion re-invokes the *main* loop, never a subagent, so ending your turn to await one deadlocks you permanently. Bash auto-backgrounds at 600 s, so a long install/build is backgrounded *against* your instruction — recover with a blocking waiter on the pid or a sentinel file, never a re-run.
  >
  > - **Never end a turn awaiting a gate.** A backgrounded Bash job's completion re-invokes the main loop, never a subagent, so a unit agent that ends its turn awaiting one deadlocks permanently. A gate that can approach the 600 s ceiling runs **detached with a sentinel and is polled from foreground calls** (`full-gate` → *Reading the verdict*); never pipe a gate, and never read a wrapper's exit code as its verdict.
- recorded: 2026-08-13
- expiry: the Bash tool's 600 s auto-background ceiling changes, or subagents receive background-job completions

### Issues / deviations / assumptions is required: "none" is a valid answer, the field is not
- rule: The executor's flagged deviations are routed verbatim into the verifier and adjudicated item by item; the provisioner's blockers field is required the same way.
- source: agents/executor.md:86; agents/provisioner.md:229; commands/build.md:161 at c75ba88
- evidence:
  > **Issues / deviations / assumptions:** **required — "none" is a valid answer, the field is not.** Every judgment call you were unsure about, every state you noticed and did not cover, every place you filled a silence in the design with a rule borrowed from somewhere adjacent. This is routed verbatim into the verifier's prompt and adjudicated item by item, so a doubt written here is the cheapest defect-catch in the flow. Do not smooth it into prose at the end of the report.
  >
  > **Blockers / anomalies:** **required — "none" is a valid answer, the field is not.** Anything you worked around, any specifier you could not resolve, any gate whose verdict you could not read cleanly.
  >
  > **Route the executor's self-flagged deviations verbatim into the verifier's prompt**, as a named section: *"the executor flagged these as judgment calls it was unsure about — adjudicate each explicitly."* Require a per-item verdict; a flagged item the verifier does not mention is an incomplete verification, not an implicit pass.
- recorded: 2026-08-08
- expiry: none known

### Your returned output is the reply channel
- rule: A subagent's return value is read directly by the agent that spawned it; never ask for a relay or address the orchestrator by name.
- source: agents/executor.md:93; agents/verifier.md:140; agents/test-runner.md:44; agents/scope-check.md:41; agents/provisioner.md:237 at c75ba88
- evidence:
  > - **Your returned output *is* the reply channel** — the agent that spawned you reads it directly. Do not ask for a relay or caveat the report with your tooling limits.
  >
  > - **Your returned output *is* the reply channel** — the agent that spawned you reads it directly. Do not ask for a relay, do not caveat the report with your tooling limits, and do not address "the orchestrator" by name: under `/start-multi` that word means the fleet, one level above your actual reader, and your verdict is not addressed to it.
  >
  > - Your returned output *is* the reply channel — the agent that spawned you reads it directly. Don't ask for a relay or caveat the report with your tooling limits.
  >
  > - Your returned output *is* the reply channel — the agent that spawned you reads it directly. Do not ask for a relay or caveat the report with your tooling limits.
  >
  > - **Your returned output *is* the reply channel** — the orchestrator reads it directly. Your READY is a *claim*, and the orchestrator is expected to spot-check it; state what you actually observed, not what the commands were supposed to achieve. The facts behind that: EVIDENCE.md (`../EVIDENCE.md`).
- recorded: 2026-08-08
- expiry: none known

### Where the design is silent, say so rather than generalising the adjacent rule
- rule: An unspecified seam next to a specified one is the most likely place to go wrong; flag it as a deviation, do not infer it.
- source: agents/executor.md:92; commands/build.md:163 at c75ba88
- evidence:
  > - **Where the design is silent, say so rather than generalising the adjacent rule.** An unspecified seam next to a specified one is the most likely place to go wrong, because the stated rule is exactly what you will reach for — and the two frequently want opposite answers (read vs. write paths over one piece of state; the client and server halves of one document). Flag it as a deviation; do not infer it.
  >
  > Where the design was **silent** on a seam the executor had to fill, that is a deviation too — the adjacent stated rule is what gets reused there, and adjacent seams frequently want opposite answers.
- recorded: 2026-08-08
- expiry: none known

### A scaffolded file's identity is the design's: unplaced fragments silently never run
- rule: Do not rewrite a scaffolded file's imports, export names, subdomain or placement; place every fragment the report lists and delete each marker as it is satisfied.
- source: agents/executor.md:25; agents/verifier.md:32 at c75ba88
- evidence:
  > 5. **If your prompt carries a scaffold report, start from it.** Files it created already exist — open them, do not re-create them, and do not rewrite their imports, export names, subdomain or placement: those encode the design's identity, and changing one makes the design stop converging (the board reports a phantom artifact and nobody notices, because the code compiles). Your job in those files is the `TODO(scaffold)` markers and the `STILL OWED` block. **Place every fragment the report lists** — a fragment is code for a file that already exists, and an unplaced registration fragment leaves the artifact never wired to the event bus: it compiles, typechecks, and silently never runs. Delete each marker as you satisfy it, and the `STILL OWED` block when the file is done; a scaffold banner left in finished code trains the next reader to ignore banners.
  >
  > **A scaffolded slice has one extra failure mode.** If the diff contains generated artifacts, check that no `TODO(scaffold)` marker or `STILL OWED` block survives in a file the slice claims to deliver, and that every generated artifact is actually **registered** in its module composition root. An unregistered artifact compiles, typechecks, and is never wired up — the suite is green and the behavior simply never happens, so the oracle is the only thing standing between that and a merge. Treat a surviving marker as an incomplete slice, not a cosmetic leftover.
- recorded: 2026-09-01
- expiry: none known

## agents/verifier.md

### The test-deletion guard: a silent deletion let a guard regress
- rule: A deleted test case or assertion with untouched production symbols is a reviewable event requiring justification; a rename preserves its cases 1:1.
- source: agents/verifier.md:36; agents/scope-check.md:24 at c75ba88
- evidence:
  > The question it forces — *what behavior just lost its only test?* — is one no checklist of positive invariants will raise, and a silent test deletion has let a guard quietly regress under the resulting coverage vacuum.
  >
  > 3. **Test deletions.** A deleted test is a deleted invariant and it is invisible to every other gate: the suite still passes, there is simply less of it. Diff the test files (`git diff <base>...HEAD -- '*test*'`) and report any **removed test case or assertion**, together with whether the production symbols it covered were touched in the same diff. A test-file *rename* must carry its cases 1:1 — report the count on each side.
- recorded: 2026-07-13
- expiry: none known

### A mutation probe that does not go red is a finding: redundancy hides the load-bearing seam
- rule: Establish why the specified probe did not fire; a hand-built fixture for an event with a real producer is a finding, and a behaviour-unchanged pin's corpus is questioned before the code.
- source: agents/verifier.md:50 at c75ba88
- evidence:
  > and **redundancy hides which seam is load-bearing** (three independent normalisation seams each upheld a guard alone). Treat a hand-built fixture for an event that has a real producer in-repo as a finding, not a style note; and where a slice's gate is "behaviour unchanged", **question the corpus before the code** — a pin whose matrix held the one axis the migration changed as a constant produced two of three findings by being questioned.
- recorded: 2026-09-05
- expiry: none known

### The checklist is always one incident behind; report a falsification table
- rule: Attack the diff's own reasoning: for each load-bearing claim in code, commit, PR body and the design docs, ask what would have to be true for it to be false, and report `claim → probe run → holds / FALSE`.
- source: agents/verifier.md:54; agents/verifier.md:60; EVIDENCE.md:54; agents/verifier.md:123 at c75ba88
- evidence:
  > every entry exists because someone was already burned by that class, so the checklist is always exactly one incident behind reality, and a diff that passes it still reads as "verified" while shipping a novel defect.
  >
  > Report as a **falsification table** — `claim → probe run → holds / FALSE` — so the reader sees what was actually challenged rather than that a box was ticked.
  >
  > When a claim survives, the useful output shape is a **falsification table** — `claim → probe run → holds / FALSE`.
  >
  > **Falsification:** a table — `claim → probe run → holds / FALSE` — covering the diff's *and* the design docs' load-bearing claims, including which adapters the harness wires vs. the composition root where relevant. "No load-bearing claims to falsify" is a valid answer; silence is not.
- recorded: 2026-07-13
- expiry: none known

### The design docs are an independent defect surface
- rule: Expect the code to be fine and the justifications partly wrong; a conformance check returns PASS on a design that is false.
- source: agents/verifier.md:58 at c75ba88
- evidence:
  > **The design docs are an independent defect surface, and the one that survives into the durable record.** A wrong `file:line`, a wrongly-scoped grep, a "zero producers / no consumers" claim, an "X is safe because Y" — each outlives the PR and misleads whoever reads it next. Expect the code to be fine and the *justifications* to be partly wrong; that is the common shape. A conformance check ("does the code match the design?") returns PASS on all of it, because the code implements the design faithfully and the design is what is false.
- recorded: 2026-08-08
- expiry: none known

### A sentence describing behaviour is a clause: six times in one run, surviving every mutation test
- rule: Enumerate every load-bearing claim the diff adds and name the test that pins it or delete the sentence; for an attribution, check the source says the claim, not that the citation resolves.
- source: agents/verifier.md:62 at c75ba88
- evidence:
  > In one run this class hit **six times** and was the **only** defect class that survived every lane's own mutation testing: it compiles, commits and reviews clean.
- recorded: 2026-09-12
- expiry: none known

### Zero non-test callers shipped as wired: a whole session state minted only in tests
- rule: An exported symbol or state literal with zero non-test callers is not implemented.
- source: agents/verifier.md:65; agents/design-lane.md:161-163 at c75ba88
- evidence:
  > - an exported symbol or state literal with **zero non-test callers**, shipped as though wired (a whole session state was persisted, reduced and queried while every mint of it was in a test);
  >
  > both in the draft, or mark the claim `REACHABILITY-ONLY`. Corollary: a symbol
  > with **zero non-test callers is not "implemented"** — two shipped ADR
  > decisions rest on exactly that, and one such chain reversed a recommendation. Fold clearly-right
- recorded: 2026-09-10
- expiry: none known

### A path cited in source, SQL or a migration that does not resolve
- rule: `git cat-file -e` over every path token in comments; one checksum-pinned migration shipped citing a missing test file, correctable only by supersession.
- source: agents/verifier.md:66 at c75ba88
- evidence:
  > - a **path or filename cited inside source, SQL or a migration that does not resolve** — `git cat-file -e` over every `path/file.ext` token in comments catches it in one pass, and one immutable checksum-pinned migration shipped citing a test file that does not exist, correctable only by supersession;
- recorded: 2026-09-10
- expiry: none known

### A doc comment whose scope is narrower than its sentence
- rule: Confident architectural universals are each one grep from falsification; a true-but-scoped comment earns trust and generalises silently.
- source: agents/verifier.md:67 at c75ba88
- evidence:
  > - a doc comment whose **scope is narrower than its sentence**. In a repo whose headers are good the failure mode is not a wrong doc but a true-but-scoped one: it earns trust by being accurate about what its author was looking at, and generalises silently. That predicts *where* to look — the confident architectural universals ("the one write path", "every X goes through Y"), each of which is one `grep` away from falsification.
- recorded: 2026-09-10
- expiry: none known

### The deletion lens: 8 of 9 tests died under their own mutation and the survivor sat on the defect
- rule: Ask which tests would still pass if the feature under test were deleted; apply it to negative controls too.
- source: agents/verifier.md:69 at c75ba88
- evidence:
  > it found the one remaining hole in a run where 8 of 9 new tests died correctly under their own mutation and the surviving trio sat exactly on the defect.
- recorded: 2026-09-10
- expiry: none known

### Two eventstore implementations: which one does production wire?
- rule: A claim of the form X-is-correct-because-the-framework-does-Y locates every implementation of Y and diffs the harness's port wiring against the composition root; a sound experiment in the wrong environment defeats scrutiny.
- source: agents/verifier.md:73; agents/verifier.md:74 at c75ba88
- evidence:
  > - **Where is Y implemented? Is there more than one implementation?** Frameworks routinely ship two (e.g. a `DatabaseEventstore` that accepts a `_transaction` and never uses it, and a `PostgresEventstore` that reads on the transaction connection).
  >
  > A workaround justified by framework behavior that **production does not exhibit** is a **blocking finding**, however convincing its evidence: a sound experiment run in the wrong environment arrives with a reproduction attached and *defeats* scrutiny — "observed, not inferred" launders a harness artifact into a platform-wide claim.
- recorded: 2026-07-13
- expiry: none known

### A source-grep guard must exclude comments: both lanes weakened the comment
- rule: Prefer matching an import form; where comment-stripping is impractical the AC says prose is excluded and how.
- source: agents/verifier.md:75 at c75ba88
- evidence:
  > Two lanes independently tripped one on prose, and **both "fixed" it by weakening the comment**, which is the wrong direction on both counts.
- recorded: 2026-09-10
- expiry: none known

### PASS-with-follow-ups is not available for a named mitigation
- rule: A finding that leaves a design-named mitigation unverified is RETRY, not a follow-up, and the fix is mutation-tested; anything parked as a follow-up ships.
- source: agents/verifier.md:84; agents/verifier.md:88 at c75ba88
- evidence:
  > ## PASS-with-follow-ups is not available for a named mitigation
  >
  > PASS-with-follow-ups is your weakest signal and the one least likely to be re-litigated — in practice, anything parked there ships.
- recorded: 2026-08-08
- expiry: none known

### Re-check mode judges each finding against the diff, never the response
- rule: `FIXED` names the hunk; a fixed with no hunk behind it is `NOT FIXED`.
- source: agents/verifier.md:104 at c75ba88
- evidence:
  > - **Judge each finding against the diff, never against the response.** `FIXED` names the hunk that fixes it; `NOT FIXED` names what still holds, at `file:line`; a finding the executor disputed instead of changing is `UPHELD` or `WITHDRAWN`, with the evidence. A "fixed" with no hunk behind it is `NOT FIXED`.
- recorded: 2026-09-13
- expiry: none known

### Environment gaps: never when the gap is the slice's own oracle
- rule: A test that could not run for a reason outside the slice is reported as `environment-gap`, not escalated, and PASS stands on what did run, except for the slice's own oracle.
- source: agents/verifier.md:127; commands/build.md:178 at c75ba88
- evidence:
  > **Environment gaps:** each test that could not collect or run for a reason outside the slice — an unbuilt sibling package, a missing credential, a sandbox refusal — as `environment-gap: <exact cause>`, or "none". A gap is not a finding: PASS stands on the evidence that did run, and never when the gap is the slice's own oracle.
  >
  > An **environment gap** — a test that cannot collect or run because of an unbuilt sibling package, a missing credential, a sandbox refusal to touch shared state: the verifier reports it as `environment-gap` with its exact cause, and the slice may PASS on the evidence that did run, the gap written to `decisions.md` (`kind: shipped-finding`) and `build-summary.md`. Never for the slice's own oracle — an oracle that cannot run is a red mechanical gate.
- recorded: 2026-09-13
- expiry: none known

### A pre-existing failure is out of scope for the slice and for /verify-build
- rule: Red on the base too is pre-existing by the baseline diff; the unit delivers its ticket, not unrelated repairs, and ESCALATE is for the slice's own work.
- source: commands/build.md:178; agents/verifier.md:95 at c75ba88
- evidence:
  > A **pre-existing failure** — red on the base too, by the `full-gate` skill's baseline diff: out of scope for the slice and for `/verify-build`, because the unit delivers its ticket, not unrelated repairs. ESCALATE is for the slice's own work.
  >
  > 2. **`git blame` / base-branch check** — is this pre-existing on the base branch, not introduced by this slice? If so it's out of scope, not a finding — name it and leave it: the slice delivers its own behaviour, not unrelated repairs.
- recorded: 2026-09-13
- expiry: none known

## agents/provisioner.md

### install is not ready: Failed to resolve entry for package; 40 of 57 files collected zero tests
- rule: A worktree is ready when the artifacts its own tests import exist on disk; workspace deps resolve through a gitignored build/, so every fresh worktree needs a build before any agent is dispatched.
- source: agents/provisioner.md:18; agents/provisioner.md:49-51; agents/provisioner.md:205; agents/pool-provisioner.md:72-76 at c75ba88
- evidence:
  > **Why this is a separate step at all:** `install` is not `ready`. A worktree is ready when **the artifacts its own tests import exist on disk** — not when the checkout is cut, and not when the package manager exits 0.
  >
  > - A `tsc --build` monorepo may emit **only the module format `exports.import` does not point at**, so a bare `build` leaves the package unimportable while reporting success.
  > - Workspace dependencies resolve through a **gitignored `build/`**, which is absent in every fresh worktree. So this hits **every unit of every run** — it is not an edge case.
  > - It presents as `Failed to resolve entry for package`, or as *"40 of 57 files collected zero tests"* — which reads as a **broken baseline** rather than as a missing provisioning step, and a lane that misreads it that way will spend its budget chasing a phantom regression.
  >
  > **Your build in step 1 is still mandatory.** It is what makes the worktree *ready* — unrelated to the baseline, and the thing that stops "40 of 57 files collected zero tests" being misread as a broken baseline.
  >
  > - **Never interpret a build or test failure.** Not "this looks like a broken
  >   baseline", not "this suite was probably already red", not a fix. The signals
  >   here are built to mislead — a missing build reads as *"40 of 57 files collected
  >   zero tests"*, which reads as a broken baseline — and judging them is the
  >   `provisioner` (`provisioner.md`)'s job on the lane path, not yours on this one.
- recorded: 2026-08-08
- expiry: workspace dependencies resolve without a build step

### Stage the decrypted local config: a ValidationError names an unrelated connector
- rule: For every `*.enc.*` whose decrypted sibling exists in the source checkout and not here, copy it or run the decrypt task; confirm it is gitignored.
- source: agents/provisioner.md:57; agents/pool-provisioner.md:40-43 at c75ba88
- evidence:
  > A fresh worktree gets `*.enc.*` and no decrypted sibling, and `generate-all` then dies **naming an unrelated connector** (`ValidationError at Mercadolibre … value: { webhookPath, appId, … }` — every field except the missing secret), which sends a lane into the connector's code.
  >
  > Skipping this does not fail here — it fails later, inside a slice, as a
  > `ValidationError` naming **an unrelated connector** and every field except the
  > missing secret. You cannot recognise that error from inside this agent, which is
  > exactly why you do the copy now rather than diagnose it later.
- recorded: 2026-09-05
- expiry: none known

### Probe every test tier: three unrunnable tiers found at PR time; 10/10 green then 17/17 red
- rule: Record RUNNABLE / UNRUNNABLE / INTERMITTENT per tier at provision, and treat a tier runnable at provision and red at build as environmental until proven otherwise.
- source: agents/provisioner.md:59 at c75ba88
- evidence:
  > Three lanes once discovered three unrunnable tiers at PR time, each separately; and a tier that was `RUNNABLE` at provision and red at build is **presumed environmental until proven otherwise** — one suite went 10/10 green twice, then 17/17 red with no code change when the broker's token store emptied.
- recorded: 2026-09-05
- expiry: none known

### Archive (never delete) a reused worktree's .work/
- rule: Stale and current `.work/` are distinguishable only by mtime; the buffers hold the learnings the rescue step exists to recover, and a populated slices.yaml builds a different ticket confidently.
- source: agents/provisioner.md:63; agents/provisioner.md:65; agents/provisioner.md:66; agents/provisioner.md:67 at c75ba88
- evidence:
  > **Archive (never delete) a reused worktree's `.work/`.**
  >
  > - The dangerous files are exactly the ones the flow reads back: `slices.yaml`, `pr-body.md`, `decisions.md` — plus a `design.md`, which is legacy residue from checkouts before 0.68.0 (the design is now committed, not kept in `.work/`) and is archived like the rest. A populated `slices.yaml` gives a lane every reason to build a **different ticket**, confidently.
  >
  > - Stale and current are distinguishable **only by mtime**. `.work/` is gitignored, so `git status` is clean either way — there is no ordinary tell.
  >
  > - Archive into the run directory rather than removing: those buffers include the `learnings.md` that the fleet's rescue step exists to recover. Deleting them destroys the run's highest-signal output.
- recorded: 2026-08-08
- expiry: none known

### Lay a multi-repo unit out by repo: yarn install dies with Manifest not found
- rule: `<RUN>/wt/<unit>/<repo>`, so relative specifiers between checkouts resolve; verify them at cut time.
- source: agents/provisioner.md:75 at c75ba88
- evidence:
  > Otherwise every `portal:` / `file:` / `link:` / relative `workspace:` specifier between them breaks. This is a hard block, not a degradation: `yarn install` dies with `Manifest not found`, which points at a manifest rather than at the layout, so the error actively misdirects.
- recorded: 2026-08-08
- expiry: none known

### The session scratchpad is not isolated: one lane's pr-body.md clobbered another's
- rule: Each unit gets its own scratchpad subdirectory.
- source: agents/provisioner.md:79; agents/pool-provisioner.md:61-63 at c75ba88
- evidence:
  > Worktrees are isolated; **the session scratchpad is not**. One lane's `pr-body.md` has silently clobbered another's, and the exposure grows as the unit brief standardises filenames across lanes.
  >
  > Use the scratchpad subdirectory you were handed and confirm it exists. Worktrees
  > are isolated; **the session scratchpad is not**, and one slice's file has
  > silently clobbered another's.
- recorded: 2026-08-08
- expiry: none known

### A rules file rots like any claim: build/esm/index.js versus ./src/index.ts
- rule: Preconditions handed down from CLAUDE.md and .claude/rules are labelled `applies` only with the command that confirmed them at BASE.
- source: agents/provisioner.md:175 at c75ba88
- evidence:
  > one extracted repo's rules said packages export `build/esm/index.js` while every `package.json` at BASE exported `./src/index.ts`, and that went into three briefs as settled (`git show <BASE>:<pkg>/package.json` is the confirming command).
- recorded: 2026-09-12
- expiry: none known

### The brief is a file in the worktree, not a message; one file, one scrub path
- rule: A lane that is cleared, handed off or resumed loses a message and keeps the file; a stale brief claims a deferral to a fleet that no longer exists, so /start deletes it and there is one brief file.
- source: agents/provisioner.md:177; agents/provisioner.md:177; agents/provisioner.md:179; commands/start.md:33 at c75ba88
- evidence:
  > It has to be a **file in the worktree**, not a message. A lane that is `/clear`ed, handed off, or resumed by a fresh agent loses the message and keeps the file — and a step invoked on its own is the limit case, because every step is then a fresh agent with no memory of a dispatch it never saw.
  >
  > the failure mode of a *stale* brief inherited from a previous run is a PR that silently claims a deferral to a fleet that no longer exists.
  >
  > **One brief file, so one scrub path.** Splitting it in two means two scrub paths, and a scrub that misses one leaves exactly the stale marker above.
  >
  > **One file means one scrub path**; two brief files means two, and a scrub can miss one.
- recorded: 2026-09-19
- expiry: none known

### A worktree provisioned under the old marker is re-provisioned, not migrated
- rule: There is no dual-read for the per-fleet marker lane.yaml absorbed; both halves of the failure are quiet.
- source: agents/provisioner.md:181-188 at c75ba88
- evidence:
  > **A worktree provisioned before this file was named `lane.yaml` is re-provisioned, not migrated.**
  > There is deliberately no dual-read for the older per-fleet marker it absorbed (named in ADR-003,
  > and deliberately not repeated here — see below): reinstating it would restore
  > the two-scrub-paths failure this file exists to close. The cost of not having one is worth naming,
  > because both halves fail *quietly* — a lane still holding the old file silently runs the branch-wide
  > scoped gate where `--fast` was wanted (slow, survivable), and `run-metrics` silently resolves **nothing** rather than
  > erroring, which is the failure `/run-report` already warns about: a fleet unit is not findable by
  > branch, by construction. Re-provision the worktree, or rename the file by hand.
- recorded: 2026-09-06
- expiry: no worktree provisioned before lane.yaml existed remains

### A deliberately-red tier is a hand-down, not a capture: COMMITTED RED ON PURPOSE
- rule: The orchestrator's base gate verdict is the integration-tier baseline; every deliberately-red suite reaches known-baseline-failures.md by name with its reason and the word deliberate.
- source: agents/provisioner.md:196; agents/provisioner.md:198-199; commands/start-multi.md:53 at c75ba88
- evidence:
  > a committed-red acceptance oracle is a practice this flow's ecosystem encourages, so the more it spreads the more this costs, and three lanes once each re-proved the same intentional failure.
  >
  > epic-goal-oracle.integration.test.ts — COMMITTED RED ON PURPOSE
  > (ESAS-82 seams REGISTRATION, GIT EXPORT); inherited, not yours; do not "fix"
  >
  > every deliberately-red suite in it must reach `.work/known-baseline-failures.md` **by name, with its reason and the word `deliberate`**.
- recorded: 2026-09-19
- expiry: none known

### A snapshot whose sha is not this worktree's base is a lying snapshot
- rule: The design snapshot is written only when the main checkout's HEAD matches the run's pinned base with a clean tree; a lane with no snapshot hand-writes, a lane with a lying one generates against a tree that does not exist.
- source: agents/provisioner.md:102-106; commands/build.md:96-101 at c75ba88
- evidence:
  > - **Match, clean tree** → write the snapshot.
  > - **Anything else** → **do not write it.** Report the mismatch with both shas.
  >   A lane with no snapshot hand-writes its artifacts, which is correct and
  >   survivable; a lane with a lying snapshot generates code against a tree that
  >   does not exist, which is neither.
  >
  > **Re-check the snapshot's sha before trusting it.** `manifest.yaml` records the sha its
  > `graph.json` was extracted from; if that is not this worktree's base commit, the graph is wrong
  > about what exists — it will call artifacts already real that this tree does not have, or anchor
  > a fragment in a file that is not here, and neither shows up in the output. On a mismatch, skip
  > the step and say so. The provisioner checks this at cut time; you check it again because a lane
  > can outlive the tree it was cut from.
- recorded: 2026-09-01
- expiry: none known

### Never copy ops.jsonl, board.json, design.json.bak or .claude-cursor into a worktree
- rule: Those are live session state; a copy invites something to treat the lane as a session participant and write back.
- source: agents/provisioner.md:116-120 at c75ba88
- evidence:
  > **Never copy `ops.jsonl`, `board.json`, `design.json.bak` or `.claude-cursor`.**
  > Those are live *session* state — cursors, an op log, board geometry — and a copy
  > of them in a worktree is an invitation for something to treat the lane as a
  > participant in the session and write back. The two documents above are the only
  > ones the scaffolder reads.
- recorded: 2026-09-01
- expiry: none known

## agents/unit-lane.md

### blocked-on=build-no-progress is the only guard on the yield loop
- rule: When slices=k/N does not advance between two /build dispatches, stop with both lines; a budget yield resuming onto the same slice forever is the one way the loop burns more than it saves.
- source: agents/unit-lane.md:146-154 at c75ba88
- evidence:
  > - `outcome=success` and `slices=k/N` with **k < N** → dispatch a **fresh**
  >   `step-lane` for `/build` again. It resumes from `passes: true` in
  >   `.work/slices.yaml`, which is already the resume point, and it starts on an
  >   empty context. Repeat until `k == N`.
  > - **k did not advance** between two consecutive dispatches → stop and report
  >   `blocked-on=build-no-progress` with both lines. A budget yield that resumes
  >   onto the same slice forever is the one way this loop can burn more than it
  >   saves, and it is the only thing you must guard.
  > - Anything but `outcome=success` → the table's rule above; do not re-dispatch.
- recorded: 2026-09-18
- expiry: none known

### Name the committed slices in the state file, not just the step
- rule: A lane reporting `step: plan, commits: []` while its branch carries three committed slices is the single most common way the orchestrator misreads a run.
- source: agents/unit-lane.md:181-185 at c75ba88
- evidence:
  > that value, and refuses to merge a unit whose state file lacks it. Update it after each pipeline
  > step, and **name the slices you have committed**, not just the step: `/build`
  > is one step containing N slices, and a lane reporting `step: plan, commits:
  > []` while its branch carries three committed slices is the single most common
  > way the orchestrator misreads a run.
- recorded: 2026-09-12
- expiry: none known

### A directive carries the constraint, never the expression: saleTime double-billed a metering period
- rule: Implement the constraint a directive expresses, not its line; a directive that contradicts the code is reported, not absorbed.
- source: agents/unit-lane.md:235-244 at c75ba88
- evidence:
  > A directive **carries a constraint, never an expression**. If one arrives
  > implementation-shaped, implement the constraint, not the line — a prescribed
  > `saleTime: data.date ?? existing.saleTime` was once implemented faithfully and
  > double-billed a metering period, where *"`saleTime` is the bucketing key and
  > must not move when an edit arrives — `date` is mutable"* would have been
  > satisfied **and tested**.
  >
  > And the symmetric half: **a directive is an input to your judgement, not a
  > settled decision. If it contradicts the code, the code wins and you say so** —
  > record the provenance in the PR body rather than absorbing it silently.
- recorded: 2026-09-01
- expiry: none known

### A split-by-region rule is a parallel-lane rule
- rule: A stacked child already holds its parent's edits, so it adjusts the import block rather than following a parallel-lane rule into an unused-import compile error.
- source: agents/unit-lane.md:246-252 at c75ba88
- evidence:
  > **A split-by-region rule is a PARALLEL-lane rule.** "Keep to the import/wiring
  > layer and leave handler bodies alone" guards a reviewability hazard that only
  > exists when a sibling holds the other half of the same file. A **stacked** child
  > already has its parent's edits in its base, so no line is contended — and it
  > **should** adjust the import block, because collapsing a handler body and
  > leaving the now-dead imports is a compile error under `noUnusedLocals` or any
  > unused-import lint. Do not follow a parallel-lane rule into a build failure.
- recorded: 2026-09-10
- expiry: none known

### Three lanes once picked the same ADR-057
- rule: Use only the numbers the brief allocates and report claimed / released; never derive a number yourself.
- source: agents/unit-lane.md:282-287; commands/evolve.md:19 at c75ba88
- evidence:
  > Your brief allocates any monotonically-numbered artifact you may create, ADR
  > numbers above all. **Use only what you were given, and report back
  > claimed / released** — a reserved-but-unused number leaves a permanent hole, and
  > three lanes once picked the same `ADR-057` under different filenames: no
  > conflict, clean merge, one number meaning three things. Never derive a number
  > yourself. Prefer amending an existing ADR where one covers the ground.
  >
  > 3. **Anecdote outweighing rule.** The behavioural instruction is one sentence and the story justifying it is a paragraph. Keep the rule, compress the story to the clause that makes it credible ("three lanes once picked the same `ADR-057`"). The story is what makes a rule *stick* on first read and what makes the artifact unreadable on the twentieth — one clause buys most of the first at little of the second.
- recorded: 2026-09-01
- expiry: none known

### Every resumed task starts by checking whose tree this is
- rule: Before any edit on a resumed task, `git rev-parse --abbrev-ref HEAD` must be the brief's branch; a recycled worktree gives no warning.
- source: agents/unit-lane.md:295-302; agents/step-lane.md:42-46 at c75ba88
- evidence:
  > Before any edit on a resumed task — not only at startup — run
  > `git rev-parse --abbrev-ref HEAD` in your worktree and **STOP if it is not your
  > brief's branch.** The orchestrator may have recycled your worktree onto another
  > unit between your report and its follow-up; git gives no warning, and the only
  > tell is a file you meant to edit "not existing". Two seconds converts a silent
  > cross-lane write into an immediate stop. If it happens, do not check your branch
  > out over the sibling's: land your commit from a throwaway `git worktree add`
  > under your scratchpad and remove it after.
  >
  > 1. **Assert the tree is yours.** `git -C <worktree> rev-parse --abbrev-ref HEAD`
  >    must equal your brief's branch. If it does not, **stop and report
  >    `blocked-on=wrong-tree`** naming what you found — the orchestrator may have
  >    recycled the worktree, and git gives no warning (`unit-lane`, *Every resumed
  >    task starts by checking whose tree this is*).
- recorded: 2026-09-05
- expiry: none known

### BLOCKED: worktree reclaimed has a benign twin
- rule: Real reclamation is mass tracked deletions of root config; a couple of files going dirty-then-clean is usually your own commit landing while a child worked.
- source: agents/unit-lane.md:326-329 at c75ba88
- evidence:
  > **`BLOCKED: worktree reclaimed` has a benign twin.** Real reclamation is mass
  > tracked deletions of root config (`jest.config.js`, `.yarnrc.yml`, `.swcrc`,
  > `dockerfile`); a couple of files going dirty-then-clean is usually your own
  > commit landing while a child worked — `git log -1 -- <file>` before declaring it.
- recorded: 2026-09-05
- expiry: none known

### A step's prose is not a fallback verdict; infra is retried, not believed
- rule: `lane-step` exits 3 printing nothing when there is no verdict; re-run the step rather than reading its prose for what it obviously meant.
- source: agents/unit-lane.md:167-173; agents/step-lane.md:119-125 at c75ba88
- evidence:
  > It prints one `key=value` per attribute and exits `0`. It exits **`3`, printing
  > nothing, when there is no verdict** — no marker, a marker that is not the final
  > line, one embedded in prose, or one whose attributes are not attributes. That is
  > the `infra` case by ADR-004's absence rule, and `infra` is retried, not believed:
  > re-run the step rather than reading its prose for what it "obviously" meant. A
  > step's prose is not a fallback verdict. If it were, the marker would be
  > decoration and every transcript that merely *discusses* an outcome would be one.
  >
  > ## If the step printed no line
  >
  > Report that fact in your prose and **emit no line of your own**. Absence is the
  > `infra` signal by ADR-004 (`../../../docs/adr/ADR-004-a-step-reports-a-line-not-an-exit-code.md`),
  > and it is retried by the caller, not believed. Inventing a line from the step's
  > prose would convert an honest `infra` into a fabricated verdict — the one
  > failure this whole marker contract exists to prevent.
- recorded: 2026-09-06
- expiry: none known

### Buffer learnings only; never run /capture-learnings from a lane
- rule: N lanes racing /capture-learnings produce duplicate and wrong-repo issues; the orchestrator captures once.
- source: agents/unit-lane.md:186-191; agents/design-lane.md:205-211 at c75ba88
- evidence:
  > - `.work/learnings.md` in your worktree — friction in the *flow itself*
  >   (a gate that misfired, a skill that misled, a step that fought the grain).
  >   **Buffer only. Never run `/capture-learnings`**: it files GitHub issues
  >   one-confirm-each and dedups against the backlog, so N lanes racing it produce
  >   duplicate and wrong-repo issues. The orchestrator rescues the buffers and
  >   captures once at the end.
  >
  > ## Learnings
  >
  > Friction in the flow itself (a probe that misfired, a skill that misled, a step
  > that fought the grain) is appended to `<run>/units/<id>.learnings.md`. **Buffer
  > only — never run `/capture-learnings`**: it files GitHub issues one-confirm-each
  > and dedups against a backlog, so parallel agents racing it duplicate. The
  > orchestrator captures once at the end.
- recorded: 2026-09-01
- expiry: none known

## agents/step-lane.md

### Printing your verdict line ends the run: 31 of 106 lanes kept running, 3,264 turns and ~$488
- rule: Once the LANE-STEP line is emitted the run is over; a lane that has reported and not stopped is billing its caller for its own history.
- source: agents/step-lane.md:73-85 at c75ba88
- evidence:
  > **That line ends you.** It is a terminal act, not a status update: once you
  > have emitted it, your run is over and you take no further turn — no
  > re-verification, no tidying, no "let me just confirm the tree is clean", and
  > above all no waiting to see whether anything else happens. There is nothing
  > left to wait for; the line *is* the result, and your caller already has it.
  >
  > This is the failure the *ending* is supposed to buy, and it is the common
  > one: across a measured fleet, **31 of 106 lanes kept running past their own
  > line** — one emitted it on turn 622 and then took 133 more turns, another
  > finished on turn 7 and took 193. Together, **3,264 turns and ~$488 spent
  > after the work was done**, at the largest prefix each context ever reached,
  > producing nothing. A lane that has reported and not stopped is not being
  > thorough; it is billing its caller for its own history.
- recorded: 2026-09-19
- expiry: a re-measured fleet shows no post-verdict turns

### Wait in one blocking call, never in a loop of turns: sleep 550 issued 530 times, ~$58
- rule: A wait costs one whole context re-read per turn it spans; put the condition inside one bounded blocking call, and no harness observed so far makes `Agent` synchronous.
- source: agents/step-lane.md:99-117; agents/unit-lane.md:220-225 at c75ba88
- evidence:
  > ## Wait in one call, never in a loop of turns
  >
  > Waiting is the cheapest thing you do and the easiest to make the most expensive.
  > A wait costs **one whole context re-read per turn it spans** — so what you pay
  > is set by how many *turns* you wait across, never by how long you wait.
  >
  > **One blocking call is one turn, at any duration.** Put the condition inside the
  > call and let it block:
  >
  >     until [ -f "$LOG" ] && grep -q '^LANE-STEP:v1' "$LOG"; do sleep 10; done
  >
  > **A sequence of `sleep` calls is one turn each, and every one re-reads your
  > whole history.** A measured lane issued `sleep 550; echo ok` **530 separate
  > times** while its prefix stood at 200–410k tokens: ~$58 of cache reads to wait,
  > and not one line of work in any of them. That is the single most expensive way
  > to do nothing this harness offers.
  >
  > So: never re-issue a timer to check again. Give the call the condition that ends
  > it, plus a bound so it cannot hang forever, and spend one turn on it.
  >
  > **Have the child's result in hand before you proceed — never end a turn on
  > "waiting".** Do not assume a dispatch flag makes `Agent` synchronous: check the
  > tool's actual schema in your harness, and where no such flag exists (absent in
  > every harness observed so far) block on the child's completion notification. Never `SendMessage` a child you are waiting on — that leaves you
  > **idle, not working**, because its resumes notify the top-level session and yours
  > do not; a fix round is a fresh `Agent` dispatch carrying `/build`'s fix-round brief, accepting the lost context.
- recorded: 2026-09-19
- expiry: the harness offers a wait primitive that does not cost a turn

### One harness has only Skill; demanding SlashCommand by name blocks every lane
- rule: Assert `SlashCommand` or `Skill`, whichever the harness names, plus `Agent`; never read the command file and execute its substance inline.
- source: agents/step-lane.md:47-54 at c75ba88
- evidence:
  > 2. **Assert you can invoke a step.** You need **`SlashCommand` or `Skill`**,
  >    whichever this harness names it — one harness has only `Skill`, so demanding
  >    `SlashCommand` by name blocks every lane — and `Agent`, because `/build`
  >    dispatches the executor, test-runner, scope-check and verifier. Missing
  >    either → stop and report **`blocked-on=lane-tools`**, naming the tools you do
  >    hold. **Never read the command file and execute its substance inline**: that
  >    produces good work, green gates and a plausible report while the dual gate
  >    never runs and no `LANE-STEP:` line is emitted by anything.
- recorded: 2026-09-18
- expiry: every harness names the step-invoking tool the same way

## agents/test-runner.md

### A run that executed nothing is inconclusive, and it exits 0: Tests: 0 total
- rule: `Tests: 0 total`, an all-skipped tier, or a suite that died at collection is never green and never a baseline; report the count, always.
- source: agents/test-runner.md:24; EVIDENCE.md:13; agents/provisioner.md:203; skills/full-gate/SKILL.md:110; EVIDENCE.md:71 at c75ba88
- evidence:
  > 5. **A run that executed nothing is inconclusive too, and it exits 0.** `Tests: 0 total`, a suite whose cases are all skipped behind an env flag (jest prints `PASS`), or suites that die at collection — none of these are green and none can serve as a baseline. Report the **count**, always; it is the only thing that distinguishes them. In a fresh worktree the first suspect is an unbuilt workspace dependency, not a real RED.
  >
  > - **It ran nothing.** `Tests: 0 total`, an all-skipped env-gated tier, a suite that died at collection — all exit 0. A run with no parsed summary line, or a zero count, is **inconclusive**: never green, and never usable as a baseline.
  >
  > Two things that do not change: a **wrong shared baseline is worse than none** (lanes then chase failures that were never theirs, or wave real ones through as pre-existing cover), and a capture from a run that executed nothing is not a baseline — `Tests: 0 total`, an all-skipped tier, or a suite that died at collection all exit 0. If you do capture on demand and get that, record **inconclusive** and say so in your report; never an empty failure set.
  >
  > - **A run that executed nothing reports green.** `Tests: 0 total` and an all-skipped tier both exit 0, and jest prints `PASS` for the latter. The counts in `<detail>` are the only thing that distinguishes them from a real pass — which is why the contract requires them.
  >
  > - **`find -maxdepth N` silently excludes deeper paths**; an empty result from a depth-bounded find is inconclusive, exactly like `Tests: 0 total`. Do not bound an existence probe.
- recorded: 2026-08-08
- expiry: none known

### Failure outside the slice's surface is not a slice RED
- rule: If `git diff <base>...HEAD` over the failing test's paths is empty, say so; a slice RED triggers fix rounds and the worst outcome is a fix to a test the slice never touched.
- source: agents/test-runner.md:26 at c75ba88
- evidence:
  > - **Diff surface** — is the failing test, or the code it exercises, inside the slice's diff? If `git diff <base>...HEAD` over those paths is empty, the verdict is *"failure outside the slice's surface"*, not "slice RED". Say it that way; a slice RED triggers fix rounds and executor churn, and the worst outcome is a "fix" to a test the slice never touched.
- recorded: 2026-09-13
- expiry: none known

### Load sensitivity: even a 10-second budget is not generous under parallel agents
- rule: A timing-shaped failure outside the surface is re-run idle; flaky-under-load + green-idle + untouched-by-diff is an environment artifact, never a RETRY.
- source: agents/test-runner.md:27; EVIDENCE.md:21 at c75ba88
- evidence:
  > - **Load sensitivity** — if it is outside the surface and the failure is timing-shaped, re-run it idle before classifying. Timing-shaped includes ceilings the test asserts **and** `Test timed out in Nms` from the runner's own default, which nobody wrote and which is invisible in the test body. The exposed class is any suite with a wall-clock budget on out-of-process work — fs watches, `git` and other CLI subprocesses — and under parallel agents even a 10-second budget is not generous. Flaky-under-load + green-idle + untouched-by-diff ⇒ an environment artifact, named as such, never a RETRY.
  >
  > - **The load was different.** A wall-clock ceiling — asserted by the test, *or* imposed by the runner's own default timeout, which nobody wrote and nobody can see in the test body — fails under contention on out-of-process work (fs watches, `git`, CLI subprocesses). Outside the diff surface **and** green when re-run idle ⇒ an environment artifact, named as such; never a regression.
- recorded: 2026-08-08
- expiry: none known

### Name any runner that structurally cannot see the slice's paths
- rule: A green count over a suite that never collected the diff is the most expensive verdict, because it reads as coverage.
- source: agents/test-runner.md:42; EVIDENCE.md:14 at c75ba88
- evidence:
  > - Name any runner that **structurally cannot see** the slice's paths (ignore-patterns, an `include` glob that misses the file's extension). A green count over a suite that never collected the diff is the most expensive verdict you can return, because it reads as coverage.
  >
  > - **It could not see your code.** Ignore-patterns and `include` globs decide what collects — `*.test.tsx` under an `include` of `*.test.ts` has never run, ever. Compare test files **on disk** against the files the runner **reported**; a material gap is a config defect, not coverage.
- recorded: 2026-08-08
- expiry: none known

## agents/tracker-writer.md

### The ADF budget is on the conversion: 20,243 prose characters accepted, 32,369 code-dense refused
- rule: Code-dense markdown expands ~2.5× in ADF; over-limit is an explicit CONTENT_LIMIT_EXCEEDED, so attempt the write and compress markup before facts, never the map-tree region.
- source: agents/tracker-writer.md:67-80 at c75ba88
- evidence:
  > 1. **Budget per ticket — the cap is on the ADF conversion, not the markdown.**
  >    Every inline-code span and bold run becomes its own ADF node with marks, so
  >    code-dense markdown expands ~2.5× and prose far less: 20,243 prose characters
  >    were accepted whole, 32,369 code-dense ones refused. `32767 − len(existing)`
  >    is therefore not a headroom figure, and no markdown count predicts the
  >    outcome. Over-limit is an explicit `CONTENT_LIMIT_EXCEEDED`, never a
  >    truncation, so an uncertain write is safe to attempt; on refusal compress
  >    **markup before facts** — tables → prose bullets, drop backticks around paths
  >    (fewest marks), collapse multi-line risk entries. Citations and
  >    rejected-option evidence are the block's value and go last. Compression
  >    **skips the `map-tree:v1` region**: its text is already emitted compressed
  >    and ADF-safe by its generator, and a trim inside it is a hand edit of
  >    generated bytes. If the hand-written parts cannot be compressed to fit, the
  >    item is refused — the region is never trimmed.
- recorded: 2026-09-12
- expiry: Jira's ADF description limit or conversion changes

### Never reproduce the preserved region by hand: one word rendered into another language
- rule: Slice the fetched description in a script and diff the payload against the fetch before sending.
- source: agents/tracker-writer.md:81-86 at c75ba88
- evidence:
  > 2. **Never reproduce the preserved region by hand.** Slice the fetched
  >    description at its end (or at the marker, when replacing) and concatenate in
  >    a script; save the payload as a file and `diff` it against the fetch before
  >    sending. An agent that re-typed the prefix rendered one word into another
  >    language, and only its own disclosure caught it. A block is appended after a
  >    `---` separator — read-modify-append, never REPLACE.
- recorded: 2026-09-12
- expiry: none known

### Never re-send a Jira-rendered description verbatim: hard breaks and __dunder__ underscores
- rule: Rebuild from the local source; keep globs, flags and anything with paired asterisks or underscores in inline code, because Jira reads `__tests__` as bold delimiters and stores it with the underscores deleted.
- source: agents/tracker-writer.md:87-96 at c75ba88
- evidence:
  > 3. **Never re-send a Jira-rendered description verbatim.** The fetched form
  >    carries hard breaks that delete the interior of a `**bold**` span straddling
  >    them on re-send, and paired `*` / `_` in prose come back as emphasis — a glob
  >    written as prose stopped being a runnable command. Rebuild from the local
  >    source of truth, and keep globs, flags, and anything containing paired
  >    asterisks **or paired underscores** in inline code — including `__dunder__`
  >    path segments such as `__tests__`, `__init__`, `__mocks__`, which Jira reads
  >    as bold delimiters and stores with the underscores **deleted** (fenced blocks
  >    round-trip intact). A path token is not obviously "a glob or a flag", which is
  >    why the narrower rule did not fire.
- recorded: 2026-09-12
- expiry: Jira's markdown → ADF round-trip stops consuming paired asterisks and underscores

### No table nested inside a list item
- rule: The converter dropped one whole, with the load-bearing fact in it.
- source: agents/tracker-writer.md:97-98 at c75ba88
- evidence:
  > 4. **No table nested inside a list item** — the converter dropped one whole,
  >    with the load-bearing fact in it. Top-level tables or flat bullets.
- recorded: 2026-09-12
- expiry: Jira's converter preserves nested tables

### Verify by a diff of the whole read-back: the bold deletion landed three sections away
- rule: The read-back is a fresh fetch after the write, never constructed from the payload; classify each difference and stop on a shortened span, changed glob, missing sentence or consumed path token.
- source: agents/tracker-writer.md:99-109 at c75ba88
- evidence:
  > 5. **Verify by a DIFF of the whole read-back against what was sent**, not a
  >    spot-check of the patch site: the bold deletion above landed three sections
  >    away from the edit. The read-back is a **fresh fetch after the write**; where
  >    the fetch tool cannot write to disk, `post` is a transcription of that fetch,
  >    labelled so — **never construct `post` from the payload**, which makes the
  >    diff green by construction. Classify each difference — bullet/fence/
  >    table-separator normalisation, `*` → `_`, escaped `~`, unwrapped bold around
  >    inline code are benign; a shortened span, a changed glob, a missing sentence,
  >    **or a path token whose underscores or asterisks were consumed as emphasis**
  >    stops the run. What is provable through `editJiraIssue` is *pre-fetch vs
  >    post-fetch of the preserved region* — claim that, not "byte-identical".
- recorded: 2026-09-12
- expiry: none known

### A readback proves the write landed, not that it survived: a parallel key sweep rewrote three blocks
- rule: Re-fetch every item at wave end and repeat the lint and citation checks; stop before the first write if another session is active with no no-other-writer claim.
- source: agents/tracker-writer.md:113-118 at c75ba88
- evidence:
  > **A readback proves the write landed, not that it survived.** Re-fetch every
  > item written in this wave and repeat the marker lint and citation checks — a
  > parallel session's key sweep once rewrote `run=` and path tokens in three
  > blocks minutes after each passed its readback. If the brief says another
  > session is active on these issues and carries no *no other writer* claim, stop
  > before the first write and say so.
- recorded: 2026-09-12
- expiry: none known

## agents/design-lane.md

### A citation comes only from output that carries its own line number: nine sed-derived citations wrong
- rule: Derive `file:line` from `grep -n`, `cat -n` or Read, paste symbol names from the source, sweep the draft for `:~` approximation markers, and make every citation reproducible by `grep -n '<symbol>' <path>`.
- source: agents/design-lane.md:72-84 at c75ba88
- evidence:
  > **A citation comes only from output that carries its own line number** —
  > `grep -n`, `cat -n`, or the Read tool. Never compute one from `sed -n 'A,Bp'`,
  > which prints content without numbers: the offset is done by hand, and a
  > self-review that re-reads the same `sed` output confirms the error. One lane
  > split cleanly — nine `sed`-derived citations wrong, every `grep -n`-derived
  > one exact. Read a range with `sed` for prose if you like, then re-derive the
  > citation with `grep -n` on the symbol. **Paste the symbol name from the
  > source; never retype or paraphrase it** — `isFrozen (session.ts:204)` for
  > `isSessionFrozen (session.ts:203)` survives a spot-check of that line, and a
  > wave-0 fact propagates to every lane by construction. Before you emit, sweep
  > your own draft: `grep -n ':~'` (an approximation marker is its own defect
  > signature — every one in one lane was off by 1–6 lines), and every
  > `symbol (path:line)` must be reproducible by `grep -n '<symbol>' <path>`.
- recorded: 2026-09-10
- expiry: none known

### Two census traps in comment-dense repos
- rule: An occurrence count counts prose in doc comments; imports reach across a monorepo by deep relative path as well as by package specifier.
- source: agents/design-lane.md:86-90 at c75ba88
- evidence:
  > **Two census traps in comment-dense repos:** an occurrence count over a
  > symbol name counts prose in doc comments as usage — confirm each hit is a
  > call site. And imports reach across a monorepo by deep relative path as well
  > as by package specifier: grep `<pkg>/src/` as well as `@scope/<pkg>`, or a
  > coupling analysis reports a seam that is not there.
- recorded: 2026-09-10
- expiry: none known

### Run the ticket's Done-is-verifiable-by clause against BASE: three of ten failed, a fourth was already true
- rule: Answer does-it-already-pass, can-it-pass-at-all and does-it-presuppose-existing-machinery with commands, and rewrite a criterion that fails as a recorded finding.
- source: agents/design-lane.md:92-106 at c75ba88
- evidence:
  > **Run the ticket's own "Done is verifiable by" clause against BASE before
  > designing anything**, and answer each question with a command. *Does it
  > already pass?* Then it does not discriminate base from done, and the real
  > scope is whatever remains — rewrite it to something false at base. *Can it
  > pass at all?* If it names a suite, **read the suite**; a criterion that
  > contradicts how the suite is built is not a target. *Does it presuppose
  > machinery that exists?* Grep for it — a criterion naming a capability the
  > repo has never had ("rollback", "replay") is commissioning it, and that is
  > unpriced scope. Three of ten in one wave failed one of the three, and a
  > fourth was already-true behind citations that were all exact — so be willing
  > to contradict the ticket on its AC after confirming its references. A
  > rewritten criterion is a finding, not a liberty: record the original, why it
  > fails, and the replacement. When it comes back already-true, the useful next
  > question is not "close the ticket" but **what real defect is adjacent to the
  > one the ticket mis-described?**
- recorded: 2026-09-10
- expiry: none known

### If you delegate a sweep, read only files its brief does not name: ~60% re-derived
- rule: The brief is the boundary; adjudicate a disagreement on evidence, never on which was written first.
- source: agents/design-lane.md:108-113 at c75ba88
- evidence:
  > **If you delegate a sweep, read only files its brief does NOT name.** The
  > brief is the boundary; if nothing outside it is worth reading, the
  > delegation should not have happened. One lane re-derived ~60% of its own
  > sub-agent's sweep because the delegated question was the interesting one.
  > Where you and it reach *different* conclusions, adjudicate on evidence —
  > never break the tie by whichever was written down first.
- recorded: 2026-09-05
- expiry: none known

### Offer an auto-resolution back as this lane's own resolution, never as the owner's
- rule: A lane passes nothing asserting whether it is attended; that is read from the marked worktree by the process the call goes to.
- source: agents/design-lane.md:123-131 at c75ba88
- evidence:
  > Then offer each auto-resolution back the way `/design` Step 3 does — `design-map
  > record` over this unit's map, one declared call per payload it prints, the
  > returned id into the `sidecar=` the verdict names and never into `map.json` —
  > and offer it **as this lane's own resolution, never as the owner's**. A lane
  > passes nothing that asserts which of the two it is: that is read from the
  > worktree the provisioner marked, by the one process the call goes to, and a
  > lane that could claim otherwise could sign its own guesses as the owner's
  > answers. A call that refuses or is unreachable is one line in the draft naming
  > the fork it did not record, and the lane continues.
- recorded: 2026-09-18
- expiry: none known

### Re-ground every load-bearing claim as if it were someone else's; trace the trigger, not the callee chain
- rule: A self-run critique fed its own context is a no-op; what pays is re-grounding against source, then the arch and ops lenses, marking unproven reachability `REACHABILITY-ONLY`.
- source: agents/design-lane.md:148-169 at c75ba88
- evidence:
  > 5. **Attack the draft, then revise it in place, then write `state.yaml` as
  >    your last act.** You have no `Skill` tool, so the `critique` skill is not
  >    invocable here, and a self-run critique fed your own context is a no-op by
  >    construction — the lenses cannot doubt facts you are already holding. What
  >    pays instead, and what the two lanes that got value did: **re-ground every
  >    load-bearing claim against source as if it were someone else's** (one such
  >    pass caught a believed-and-written claim and a second census error behind
  >    it), *then* apply the `arch` and `ops` lens questions. **Where a claim turns
  >    on whether a path actually executes** — "this is persisted", "this runs on
  >    every X", "this is called after Y" — **trace the trigger, not the callee
  >    chain.** A chain of definitions proves the path *can* be reached, never that
  >    anything reaches it; each link genuinely exists, which is what makes it feel
  >    like proof. Find what invokes the entry point and under what condition, state
  >    both in the draft, or mark the claim `REACHABILITY-ONLY`. Corollary: a symbol
  >    with **zero non-test callers is not "implemented"** — two shipped ADR
  >    decisions rest on exactly that, and one such chain reversed a recommendation. Fold clearly-right
  >    fixes in, **promote a missed genuine fork to the open-forks list**, carry a
  >    no-good-answer weakness to *Risks*. **The critique output is an input to a
  >    revision, never a turn-ending artifact: your turn ends when `state.yaml` is
  >    on disk after the revision** — three lanes across two runs stopped on the
  >    verdict line with the revision undone, and the orchestrator's disk check
  >    only sees a missing file, not a stale draft.
- recorded: 2026-09-05
- expiry: none known

### The emit precedes the critique deliberately
- rule: A terminal-looking verdict outcompetes any then-emit after it; the pre-critique draft is on disk first and the turn ends when state.yaml is written after the revision.
- source: agents/design-lane.md:183-186 at c75ba88
- evidence:
  > **The emit precedes the critique deliberately.** A terminal-looking verdict
  > outcompetes any "then emit" after it — two of three agents once ended their turn
  > there with none of their files written — so the pre-critique draft is on disk
  > first, and a swallowed step 5 leaves a complete draft instead of nothing.
- recorded: 2026-09-05
- expiry: none known

### Establish a credential is absent before deferring: five forks answerable with a committed certificate
- rule: Grep for committed sandbox credentials and vendor SDKs; found means an orchestrator-runnable probe, genuinely absent means a land-time rule naming which credential and who holds it.
- source: agents/design-lane.md:192-203 at c75ba88
- evidence:
  > - **You may lack credentials** for some probes (private registries, org-scoped
  >   reads, anything behind SSO). Do not guess the answer — but **establish that
  >   the credential is actually absent before deferring**: grep for `*.crt` /
  >   `*.key` / `*.pem`, `scripts/<vendor>/`, `.env*` templates and sandbox config,
  >   and check whether the vendor SDK is already a dependency. Sandbox credentials
  >   are routinely committed *so that they can be used* — five "needs a named
  >   human" forks in one run were answerable with a committed certificate.
  >   **Found** → park it as an **orchestrator-runnable probe**, naming the whole
  >   dependency chain (a "one call" probe needing a credentials tool first is not
  >   one call from cold). **Genuinely absent** → turn the question into a rule the
  >   build checks at land time, naming *which* credential is missing and who holds
  >   it, never "a human".
- recorded: 2026-09-01
- expiry: none known

### A read-only lane never writes the design layer or the map
- rule: N agents writing one design.json is N tickets' designs in a layer scoped to one unit of work; a lane runs only `design-map validate` and `write` for its own fragment.
- source: agents/design-lane.md:18-28 at c75ba88
- evidence:
  > You are **read-only against the repo** — your only writes are your own
  > `<run>/units/<id>.*` files. Never `run.yaml`, never another unit's files, and in
  > a repo with `.esas/` never the design layer: `get_flow` and `get_design` are
  > reads and grounding against the extracted graph is exactly your job, but **no
  > `comment`, `resolve`, `propose`, `modify` or `remove`** — and, for the same
  > reason, no `map_*` tool except the `get_map` read, no `start_map_session`, and
  > no `design-map` subcommand that renders, posts or ingests answers: you are
  > unattended, and any of those would act as if the map gate had said yes with
  > nobody watching. N agents writing one
  > `design.json` is N tickets' designs in a layer scoped to one unit of work,
  > serialized in dispatch order with nothing recording which ticket asserted what.
- recorded: 2026-09-01
- expiry: none known

## skills/full-gate/SKILL.md

### Never read a pass from a piped or wrapper exit code: four shards exited 0 with two FAIL
- rule: Parse the GATE-STEP lines; a wrapper's sentinel must be its last command, and a sharded runner's exit code is unverified.
- source: skills/full-gate/SKILL.md:107; EVIDENCE.md:70 at c75ba88
- evidence:
  > - **Never read a pass from a piped exit code**, yours or the script's — nor from a **wrapper's**: `cmd > log; echo EXIT=$?` reports the `echo`, and `nohup sh -c "gate > log; echo EXIT=$? >> log; echo done"` reports `done`. The sentinel must be the **last** command in the wrapper. And a runner that fans out to sub-processes may not propagate child failure at all — `test:integration` in four shards once exited 0 with two shards `FAIL`; read the runner's own per-unit summary and treat any sharded/parallel wrapper's exit code as unverified. Parse the `GATE-STEP:` lines; if there are none, you are looking at output from something that is not a conforming gate, and the run is inconclusive.
  >
  > - **`$?` after a pipeline or a redirect-then-echo is the last command's**, not the tool's: `yarn gate > log; echo "EXIT: $?"` printed 0 under a log ending `GATE FAILED`. Capture `rc=$?` on its own line, or `${PIPESTATUS[0]}`, and judge on the tool's printed verdict.
- recorded: 2026-09-05
- expiry: none known

### Run a whole-repo gate detached with a sentinel: an interrupted generate-all left 177 corrupted files
- rule: A gate that can outlive the 600 s ceiling runs under nohup with a `GATE_EXIT=` sentinel polled from foreground calls.
- source: skills/full-gate/SKILL.md:108 at c75ba88
- evidence:
  > - **A whole-repo gate outlives the Bash tool's 600 s ceiling — run it detached and poll a sentinel it writes itself.** `nohup sh -c "<gate> > <log> 2>&1; echo GATE_EXIT=$? >> <log>" &`, then poll the log from foreground calls until `GATE_EXIT` appears. A plain or backgrounded invocation is killed partway, and for a **generator** that is worse than a lost verdict: an interrupted `generate-all` once left 177 corrupted files that read as real drift. A generator that fails **fast** (config validation, before the writing stage) leaves a clean tree; one interrupted mid-run leaves a tree to restore, never to diff for meaning.
- recorded: 2026-09-19
- expiry: the Bash tool's ceiling changes

### A silent, fast, exit-0 typecheck is undecidable: plant a positive control inside a workspace
- rule: When the verdict is load-bearing, plant a deliberate type error in a workspace the runner visits and confirm exit 1; `yarn build` under swc is transpile-only.
- source: skills/full-gate/SKILL.md:109 at c75ba88
- evidence:
  > - **A silent, fast, exit-0 typecheck is undecidable, and deleting `tsbuildinfo` does not decide it** — a genuinely clean run is also fast and empty. When the verdict is load-bearing, use a **positive control**: plant a deliberate type error, confirm exit 1, remove it. The control must live **inside a workspace the runner visits** — under `workspaces foreach`, a repo-root file belongs to no project and is skipped silently, so the control itself false-passes. Same principle for any gate: a negative result is evidence only once the instrument has been seen to produce a positive one. (`yarn build` under swc is transpile-only and passed a real type error the typecheck caught.)
- recorded: 2026-09-05
- expiry: none known

### A green partial inventory reads as full coverage: 33 of 57 suites excluded
- rule: Compare the repo's test files on disk against the count the runner reported; a material gap is a config defect, not coverage.
- source: skills/full-gate/SKILL.md:111; EVIDENCE.md:14 at c75ba88
- evidence:
  > - **A green *partial* inventory reads as full coverage**, and is harder to spot than zero because the run looks substantial. `find` the repo's test files by its naming convention and compare against the count the runner reported; a material gap means the `include` globs are wrong or a tier is opt-in. (A root glob that predated a monorepo move silently excluded **33 of 57 suites**; every prior "green" on that branch was vacuous for them.)
  >
  > - **It could not see your code.** Ignore-patterns and `include` globs decide what collects — `*.test.tsx` under an `include` of `*.test.ts` has never run, ever. Compare test files **on disk** against the files the runner **reported**; a material gap is a config defect, not coverage.
- recorded: 2026-08-14
- expiry: none known

### Before running anything at the base, check whether the diff surface already answers it
- rule: An empty `git diff --name-only <base>..HEAD -- <paths>` disowns a failure by construction; a baseline run is the third resort, and a linked sibling checkout is a second moving variable.
- source: skills/full-gate/SKILL.md:112 at c75ba88
- evidence:
  > - **Before running anything at the base to attribute a result, check whether the diff surface already answers it.** `git diff --name-only <base>..HEAD -- <the failing suite's subject paths>` empty ⇒ the branch cannot have caused it — disowned **by construction**, in seconds, unfalsifiable by load or flakiness; or `git show <base>:<artifact>` already violates the assertion. A baseline *run* is the third resort, and one printing `Tests: 0 total` is **inconclusive**, never "fails on master too". Byte-identical inputs include a **linked sibling checkout**: a control worktree must sit where its `link:../pv3/...` resolves to the same rebuilt sibling, or it compares against a path that does not exist — and a sibling another lane rebuilt is a second moving variable no per-repo baseline records.
- recorded: 2026-09-05
- expiry: none known

### All green is the wrong bar when the base is already red: diff by file, not by total
- rule: Capture the failing-suite set on base and HEAD and diff the names; an empty baseline file is the absence of a claim, never a claim the base is green.
- source: skills/full-gate/SKILL.md:114; commands/start.md:59 at c75ba88
- evidence:
  > - **"All green" is the wrong bar when the base is already red.** The sound verdict is a **baseline diff**: capture the failing-suite *set* on the base and on `HEAD`, and diff the **names**. `PASS→FAIL` is a regression; already-red-on-base is pre-existing — name it and move on. Compare **by file, not by total**; totals hide an equal-and-opposite swap. `.work/known-baseline-failures.md` is where that base-side set is written. It normally arrives holding only the base sha and *"not captured — capture on demand"*: `/start` and the `provisioner` deliberately do **not** run a suite to fill it, because the base side is only needed on a red `HEAD`. When you need it, capture it yourself — for the **red suites by name**, on a freshly-built tree — and append it there for whoever comes next. An empty baseline file is the absence of a claim about the base, never a claim that the base is green.
  >
  > Later steps compare **by file, not by total**: a total hides an equal-and-opposite swap. An absent baseline is not a claim that the base is green — it is the absence of a claim, and the file says so in those words so nobody reads the empty file as an empty failure set.
- recorded: 2026-08-24
- expiry: none known

### A venue without the repo's secrets certifies partially; INCONCLUSIVE, not SKIP
- rule: A step the environment could not run for lack of a credential is INCONCLUSIVE, and two runs whose enablements trade are not additive.
- source: skills/full-gate/SKILL.md:115; skills/full-gate/SKILL.md:46 at c75ba88
- evidence:
  > - **A run on a venue without the repo's secrets cannot fully certify a branch** — its verdict is **partial by construction**, however green, and the landing gate runs where the secrets are. Say which steps were `INCONCLUSIVE` for that reason and why, rather than reporting a clean gate. And where making one step runnable **disables another**, the two runs' verdicts are **not additive**: name the pair that traded in the PR body, because reporting each run's own honest verdict and letting the union imply coverage is a claim neither run made.
  >
  > `INCONCLUSIVE` is for a step that ran but proved nothing — zero tests collected, an all-skipped env-gated tier, a suite that died at collection, **or a step the environment could not run because it lacks a required credential**. That fourth cause is the one a hosted venue hits on every secret-dependent step, and it is neither `SKIP` (which claims deliberate exclusion) nor `FAIL` (which claims a regression): it is the **absence of a claim**, and `SKIP` is the one wrong answer that looks tidy in a PR body. **Neither is a pass**, and the flow must surface both by name rather than folding them into a summary count.
- recorded: 2026-09-10
- expiry: none known

### No flow step ever runs --full or --all
- rule: The whole-repo run is CI's or the human's on request; a scoped verdict certifies the diff and its importers and names the tree-counting guards it could not select.
- source: skills/full-gate/SKILL.md:24; skills/full-gate/SKILL.md:26; commands/verify-build.md:28 at c75ba88
- evidence:
  > **No flow step ever runs `--full` or `--all`, and none may be made to.** The rule is the user's, and it is unconditional: a whole-repo run is minutes-to-tens-of-minutes of laptop time paid on every unit of every run, to re-prove a tree nobody changed. The full run happens **once**, elsewhere — in the CI pipeline, or when the user asks for it by name. If you believe a step genuinely needs `--full`, **stop and ask**; do not decide it yourself, and do not "just this once" it because the scoped verdict felt thin.
  >
  > **So say what a scoped verdict is, every time you report one.** It certifies *this branch's diff and its importers*, not the tree. Quote the `GATE-MODE:` line, and never write a sentence that reads as whole-repo certification. Two blind spots are structural and belong in the report by name whenever the diff could reach them: **tests that count the tree** (census and ratchet guards glob the filesystem and import nothing, so no diff-scoped selection has an edge to them — a change that adds or removes a file of a kind something counts runs those guards explicitly), and **behavioural ripple a typecheck cannot see**. That residue is exactly what the CI / on-request `--full` exists to cover, and naming it is how the two halves add up.
  >
  > **Never `--full`, never `--all`, under any condition — not for a big diff, not for a risky one, not "just to be sure".** The whole-repo run belongs to the CI pipeline, or to the user asking for it by name; a flow step that helps itself to one spends tens of minutes of the user's laptop re-proving a tree the unit did not touch. If you think this unit needs one, **say so in the PR body and stop** — the decision is the user's.
- recorded: 2026-09-19
- expiry: none known

### Node, not bash, for the gate script: a contributor, not a preference
- rule: A `.sh` makes Git Bash or WSL a precondition for running the repo's own gate on Windows; `spawnSync(..., { shell: true })` resolves `yarn` → `yarn.cmd`.
- source: skills/full-gate/SKILL.md:28 at c75ba88
- evidence:
  > **Node, not bash, and the reason is a contributor, not a preference.** This is the one flow artifact each host repo authors itself and each contributor runs directly, and a `.sh` makes a working Git Bash or WSL a precondition for running the repo's own gate on Windows. Node is already present in any repo this flow runs in, and `spawnSync(..., { shell: true })` resolves `yarn` → `yarn.cmd` for free. A `.claude/gate.sh` is still accepted (see discovery) — a repo that already has one need not rewrite it — but a **new** one is `.mjs`.
- recorded: 2026-08-14
- expiry: none known

## skills/grill/SKILL.md

### Never name a reference without restating what it is: "it is very hard for me to follow you"
- rule: Every coined label and every outside identifier carries a short descriptive title at every mention.
- source: skills/grill/SKILL.md:59 at c75ba88
- evidence:
  > - **Never name a reference without restating what it is — every time, no exceptions.** This covers *both* the labels you coined ("option b3", "scenario A", "the hybrid") *and* the identifiers that came from outside (ticket keys, requirement/risk numbers, ADR ids, board element names, file paths used as shorthand). An identifier is an address, not a meaning: the user is not holding your numbering, and by fork 6 they are not holding theirs either ( *"it is very hard for me to follow you… I start to lose track"* ). Carry a short descriptive title in parentheses at **every** mention, not just the first:
- recorded: 2026-08-16
- expiry: none known

### A timeline with a concrete named cast beats prose: a lost explanation landed on relabelling
- rule: Define the cast once, then walk it per scenario as an indented timeline with an outcome line; mandatory where a fork is about how data moves.
- source: skills/grill/SKILL.md:65 at c75ba88
- evidence:
  > - **A timeline with a concrete named cast beats prose.** Define the cast once — real product names, SKUs, amounts — then walk it step by step per scenario as an indented timeline with an outcome line. This is mandatory where a fork is about **how data moves**; a previously-lost explanation landed immediately on being relabelled this way.
- recorded: 2026-08-08
- expiry: none known

### Bold the load-bearing claim in every paragraph: "a huge block of unstructured text"
- rule: Skimming bold-only must give the shape of the fork and the recommendation before a full sentence is read.
- source: skills/grill/SKILL.md:89 at c75ba88
- evidence:
  > - **Bold the load-bearing claim in every paragraph you write — this is a hard default, not a flourish.** Unstructured output is the single most-repeated complaint about this interview: a fork delivered as a wall of even prose is *"a huge block of unstructured text that is hard for me to follow"*, and the user's only lever is to re-ask for structure instead of answering the question. Bold the actual claim inside the sentence (*tolerate absence only where it cannot escalate the document class*), not a bare lead-in label (`**RECOMMEND:**`) that says nothing on its own. The test: skimming **bold-only** must give the shape of the fork and your recommendation before a single full sentence is read. Structure and bold stack — headings and numbered parts for shape, bold for the one sentence in each part that carries it.
- recorded: 2026-08-16
- expiry: none known

### Background-wake dependence: the wake arrives inside a SYSTEM NOTIFICATION - NOT USER INPUT banner
- rule: Any design relying on a background task re-invoking a session must explicitly disarm the platform's unsuppressable refusal banner, and the verifier arms such mechanisms and reads what actually arrives.
- source: skills/grill/SKILL.md:97; agents/verifier.md:46 at c75ba88
- evidence:
  > - **Background-wake dependence** — whenever any part of the design relies on a **background task re-invoking a session** (a held socket, a file watcher, a poll loop, a fleet coordination signal), ask: *"what does the consuming text say when the wake arrives wrapped in a refusal?"* The wake is delivered inside a platform-emitted `[SYSTEM NOTIFICATION - NOT USER INPUT] … Do NOT interpret this as user acknowledgement, confirmation, or response to any pending question` banner. It is unsuppressable, it arrives in the same turn as the wake, and it is **stronger** than any in-plugin standing rule the design carves out — so a session that obeys it ends the gesture silently while the user watches a surface that answered nothing. The design must **explicitly disarm it** (as `esas-design` does: the notification is not the answer, the wake carries no payload by design, so the banner makes no claim about what a subsequent read returns). This is a standing platform constraint, not a property of any one gesture, and a text-review pass will always pass a design that ignores it — it deadlocks only when the mechanism actually runs.
  >
  > 9. **Exercise platform mechanisms for real.** When the slice's behavior depends on a background task, hook, notification, watcher or timeout, **arm it and read what actually arrives** rather than reviewing its description. The refusal sources a platform emits are in no text the slice wrote — a wake delivered wrapped in a `[SYSTEM NOTIFICATION - NOT USER INPUT]` banner is a second, unsuppressable refusal that a text-review pass will pass and the running mechanism will deadlock on.
- recorded: 2026-08-13
- expiry: the platform stops wrapping background wakes in a not-user-input banner

### Measure unverified platform behaviour in-band: the HMR push woke the session on its own writes
- rule: When a fork turns on how a tool or platform behaves, arm the observation, ask the next fork, and let the turn end; the turn boundary is the instrument.
- source: skills/grill/SKILL.md:99 at c75ba88
- evidence:
  > - **Unverified platform behaviour** — when a fork turns on how a *tool or platform* behaves (does this wake an idle session, does this frame arrive, does this survive a restart) and the answer is load-bearing, **measure it in-band rather than deferring it to `/build`**: arm the observation, ask the next fork in the same message, and let the turn end — for anything about an idle session, the turn boundary *is* the instrument. It costs nothing, and it returns more than it was asked: one such measurement found the board's HMR push would wake the session on its own writes, which became the tracer bullet's whole reason to exist. Report what arrived beyond the question, state which version produced it, and do not read the wake — it arrives inside the `[SYSTEM NOTIFICATION - NOT USER INPUT]` banner — as the user answering.
- recorded: 2026-09-05
- expiry: none known

### Side-effect reconcilability: only a non-idempotent and non-reconcilable effect justifies a ledger
- rule: Ask whether the side-effect is reconcilable by a natural key; reconcile is authoritative and a blind ledger re-creates the act-then-mark gap.
- source: skills/grill/SKILL.md:104; skills/grill/SKILL.md:101; skills/grill/SKILL.md:102 at c75ba88
- evidence:
  > - **Only** a side-effect that is non-idempotent **and** non-reconcilable justifies a best-effort local ledger — and say so explicitly, because a blind ledger otherwise just re-creates the act-then-mark gap it appears to close.
  >
  > - **Side-effect reconcilability** — whenever the design performs an **external or otherwise non-idempotent side-effect** that can be retried/redelivered, ask: *"Is this side-effect **reconcilable** against the external system by a natural key — can you ask it 'does this already exist?' (a SKU, a client-reference, a transactionally-reserved number you can read back)?"*
  >
  > - **Yes** → reconcile by that key; build **no** local dedup structure (ledger/bitmap/lease). Reconcile is authoritative — it survives total loss of any local dedup store.
- recorded: 2026-06-27
- expiry: none known

### In-session behaviour is evidence about the loaded version, not the design question
- rule: When a fork concerns the flow itself, state which version produced any observation and never argue from an absence in the running session.
- source: skills/grill/SKILL.md:91; EVIDENCE.md:52 at c75ba88
- evidence:
  > **And where a fork concerns the behaviour of the flow, a skill, or a command this session is itself running: the session is a participant, not an observer.** In-session behaviour is evidence about the **loaded version**, never about the design question, and an absence in the running session is never an argument for or against adding something. State which version produced any observation offered as evidence, and let the user weigh whether they *want* the capability independently of whether it currently works.
  >
  > - **In-session behaviour is evidence about the loaded version, not about the design question.** The trap whenever this flow reasons about itself: an absence in the running session is never an argument against adding something.
- recorded: 2026-08-08
- expiry: none known

### Never use AskUserQuestion, anywhere in this flow
- rule: A plain numbered list with a recommendation beats the picker every time; the user answers free-form.
- source: skills/grill/SKILL.md:8 at c75ba88
- evidence:
  > Ask the questions one at a time. **Never use `AskUserQuestion` — not here, not anywhere in this flow.** It wraps chrome and fixed options around what is usually a "pick a branch" call, and a plain list beats it every time. Present the options and your recommendation as a numbered list; the user answers free-form. This is a standing preference with no carve-out.
- recorded: 2026-07-12
- expiry: none known

## skills/vertical-slicing/SKILL.md

### A gate that never fired is indistinguishable from a gate that cannot fire
- rule: Order a self-enforcing slice so a later slice in the same PR is its first live subject, and state in the PR which commit is a new mechanism's first live proof.
- source: skills/vertical-slicing/SKILL.md:30; commands/verify-build.md:112 at c75ba88
- evidence:
  > Both other orderings fail. Mechanism-last means it is never exercised by its own PR and ships asserted-but-unproven — and for an enforcement mechanism that is the whole risk: **a gate that never fired is indistinguishable from a gate that cannot fire.**
  >
  > - **If the PR adds an enforcement mechanism** (a CI gate, lint rule, schema check, hook), state **which commit is its first live proof** — or, if none is, say why. A gate that never fired is indistinguishable from a gate that cannot fire.
- recorded: 2026-08-08
- expiry: none known

### A write-side oracle asserts its own artifact: the same message twice
- rule: Convergence, idempotency, ordering and dedup are asserted on the stream, count or version, never on a read-model row; one implementation wrote a fresh random stream per delivery and passed.
- source: skills/vertical-slicing/SKILL.md:51 at c75ba88
- evidence:
  > **An oracle for a write-side guarantee asserts that guarantee's own artifact.** Where the behavior names convergence, idempotency, exactly-once, ordering or dedup, the assertion is on the event stream, the event count or the version — never on a read-model row or a query result, because the projection's own `upsert` dedups independently and passes a non-convergent implementation green. "The same message twice yields ONE row" was satisfied by an implementation that wrote a fresh random stream per delivery; asserting the **stream set across the whole eventstore** caught two wrong mechanisms before implementation, one of them a silent cross-tenant collapse. A thin complete path still asserts at the layer its claim lives.
- recorded: 2026-09-05
- expiry: none known

### A declaration-only slice needs a named oracle too
- rule: A purely additive vocabulary or type slice pins existing behaviour by round-tripping the only live producer's inputs.
- source: skills/vertical-slicing/SKILL.md:53 at c75ba88
- evidence:
  > **A declaration-only slice needs a named oracle too.** A purely additive vocabulary or type slice compiles, breaks nothing, and passes every gate vacuously; the answer to *"what test fails if this slice is wrong?"* is a test pinned to **existing** behavior — round-trip the inputs the only live producer supplies today — which is falsifiable without changing anything.
- recorded: 2026-09-05
- expiry: none known

### Slicing only one side of a contract: 41→77 tests and the marker emitted by nothing
- rule: For every contract a unit introduces, name the slice that writes it and the slice that reads it; a unit shipping one side is green by construction.
- source: skills/vertical-slicing/SKILL.md:132; commands/plan.md:60 at c75ba88
- evidence:
  > - **Slicing only one side of a contract.** When a unit introduces a contract between two parties — a producer and a consumer, a writer and a reader, a caller and a callee — name the slice that builds **each** side, or state which side is out of scope and why. A unit that ships one side is **green by construction**: the tests can only exercise the half that exists, and the specified degrade path is indistinguishable from the system working. One unit sliced the *reading* of a step contract three ways — spec, parser, reader, plus a uniqueness guard — shipped 41→77 tests, both gates green on every slice, and the marker was emitted by nothing. This is not the tracer bullet rule: every slice there was genuinely vertical and individually complete; the gap is **between** slices, in the set, which is why it belongs to `/plan` and no single slice's gate can see it. The check is one question over the slice list: *for every contract this unit introduces, which slice writes it and which slice reads it?*
  >
  > - **For every contract this unit introduces, which slice writes it and which slice reads it?** A unit that ships one side is green by construction, and no single slice's gate can see it (`vertical-slicing`, anti-patterns). Answer it in the unattended branch too — it is answerable from the slice list alone.
- recorded: 2026-09-06
- expiry: none known

### An oracle nobody said how to break
- rule: Every slice states what would have to change for it to go red; the cheapest thing to write is the one that ships a suite that cannot fail.
- source: skills/vertical-slicing/SKILL.md:129 at c75ba88
- evidence:
  > - **An oracle nobody said how to break.** Every slice green, every scenario asserted, and no statement anywhere of what would have to change for any of it to go red. It is the cheapest thing to write and the one that ships a suite that cannot fail.
- recorded: 2026-09-19
- expiry: none known

## skills/domain-modeling/SKILL.md

### The no-ADRs-yet default is docs/adr/ADR-NNN-slug.md and fires once per repo
- rule: The default must match what vertical-slicing's schema and verify-build's PR template render; the three agree, and a change to one changes all.
- source: skills/domain-modeling/SKILL.md:95 at c75ba88
- evidence:
  > Only if the repo has **no** ADRs yet, default to **`docs/adr/ADR-NNN-slug.md`** — the spelling the rest of this plugin renders into every host repo (`vertical-slicing`'s `slices.yaml` schema, `verify-build`'s PR-body template). This rule fires exactly once per repo, on the *first* ADR, and every later ADR inherits whatever it produced by "match what's there" — so a default that disagrees with the templates sets a convention the repo keeps forever, and one the flow's own artifacts then fail to match. The three must agree; if the zero-padded form is ever preferred, both templates change too.
- recorded: 2026-08-09
- expiry: none known

### Never take the next ADR number from a directory listing: 22% duplicated numbers
- rule: Scan every ref, go above the highest, check uniqueness against the merge target; the collision is silent because different slugs never conflict.
- source: skills/domain-modeling/SKILL.md:103; commands/verify-build.md:105; commands/verify-build.md:106 at c75ba88
- evidence:
  > The collision is **silent**: different slugs mean different filenames, so nothing conflicts, the merge is clean, and both land. It is not a parallelism artifact either — two sequential sessions on two long-lived stacks produce it just as readily, and one repo's namespace reached 22% duplicated numbers this way.
  >
  > **Never take the next number from a directory listing** — it shows only numbers that reached *your* branch, and numbers on unmerged siblings, open PRs and other stacks are already claimed. Scan every ref: `git log --all --name-only --pretty=format: | grep -oE 'ADR-[0-9]+' | sort -u | tail -5`, then go above it. This is the last point where a collision is still cheap: a rename after merge breaks every inbound `ADR-0NN` citation permanently.
  >
  > - **Check uniqueness against the merge target, not the branch.** The failure shape is a *filename* difference with a *number* collision, which no git mechanism surfaces — different names never conflict, so both land.
- recorded: 2026-08-09
- expiry: none known

## skills/design-map/SKILL.md

### The page's comment box never wakes the session (observed 2026-09-17)
- rule: Readback runs on the owner's word in the terminal; tell the owner how to hand back when publishing.
- source: skills/design-map/SKILL.md:125-134; skills/design-map/SKILL.md:119-121 at c75ba88
- evidence:
  > **The page's comment box never wakes the session.** Each fork's comment
  > textarea writes `answers/<forkId>.comment` into the artifact's db, like a
  > pick; it is not an artifact comment thread, so it cannot notify me. Observed
  > 2026-09-17: a page published with `capabilities: {db: {}}` on a watched
  > session ("auto-replies armed"), every fork answered and "done" typed into
  > F1's comment box — no notification of any kind reached the session. A saved
  > pick sends nothing either.
  >
  > **The observed readback trigger is the owner's word in the terminal** — that
  > they are done, or have answered some forks. Sync then.
  >
  > **When publishing, tell the owner how to hand back**, in so many words: "answer
  > on the page, then tell me in the terminal when you're done." Without that
  > sentence the owner answers every fork and is left with no way to reach me.
- recorded: 2026-09-17
- expiry: the artifact db store gains a notification path to the watched session

### The comment-mode disarm is unmeasured; a wake never runs --final
- rule: A comment thread sent to Claude may arrive inside the not-user-input banner; it is a doorbell, the answers are in the store, and `--final` needs the owner's word in the terminal.
- source: skills/design-map/SKILL.md:143-160 at c75ba88
- evidence:
  > ### The disarm: a comment-mode thread is not a refusal (unmeasured)
  >
  > A different path exists: a comment thread the owner opens from the artifact's
  > own comment mode and sends to Claude. That **may** wake a watched session,
  > arriving inside the platform's `[SYSTEM NOTIFICATION - NOT USER INPUT]`
  > banner. **This is not measured** — the 2026-09-17 run did not exercise that
  > path, so neither the wake nor the banner's wording has been observed. The
  > disarm stays for that case: read as a refusal, the banner would end the
  > gesture silently while the owner watches a page that answered nothing. It is
  > not one: **the notification is the doorbell; the answers are in the store**,
  > about which the banner makes no claim. On such a wake, run the same readback —
  > `read_db` over `answers` into `<answers-dir>/`, then fold with
  > `apply-answers` **without `--final`**. **A wake never runs `--final`**,
  > whatever the comment says — even "done". The banner-wrapped comment is the
  > doorbell, not the owner's word; `--final` turns every open fork into
  > `decided(recommendation)`, after which nobody can tell a fork the owner let
  > stand from one they never reached. Tell the owner in the terminal what the
  > fold shows and wait for them there.
- recorded: 2026-09-17
- expiry: the comment-mode wake and its banner are observed

### decided-nowalk and walk-unstructured are refusals, not counters
- rule: A decided fork whose chosen option has no walk, or a prose walk, stops /plan (`outcome=fail`), because its slice would get an oracle invented downstream from prose; the verdict names the walk's index, never its text.
- source: skills/design-map/SKILL.md:265-280 at c75ba88
- evidence:
  > - `skipped-nowalk` — **can no longer happen**, and is kept on the verdict line
  >   at `0` because `/plan` parses that line and its zero is the proof the refusal
  >   fired rather than a fork being quietly dropped. A decided fork whose chosen
  >   option carries no walk is now `outcome=fail reason=decided-nowalk`: a choice
  >   somebody made that nobody can test, whose slice gets an oracle invented
  >   downstream from prose
  > - `skipped-untestable` — the fork carries `testable: false` (a process-rule
  >   card the design lane marks unoracled, ESAS-164); when both zero-walk and
  >   `testable: false` hold, `skipped-untestable` wins
  >
  > Two refusals, both `outcome=fail` (exit 1 — a fixable map, not a broken tool):
  > `reason=decided-nowalk id=<fork> option=<id>`, and `reason=walk-unstructured
  > id=<fork> option=<id> walk=<index>` when a chosen option's walk is prose. The
  > walk's **index**, never its scenario text: every attribute on a verdict line is
  > space-free by contract, and a refusal nobody can parse reads downstream as no
  > refusal at all.
- recorded: 2026-09-19
- expiry: none known

### record is pure over files
- rule: Argument derivation for the recording call lives in design-map, testable with nothing reachable; the verb posts nothing.
- source: skills/design-map/SKILL.md:432-440 at c75ba88
- evidence:
  > `record` is pure over files, like `apply-answers`: no network call, no
  > subprocess, no tool of its own. It prints, before the verdict line, a JSON
  > array of one payload per fork the map says is **answered** — every fork with a
  > `decided` status, in map order — each carrying `forkKey` (the fork's own map
  > id, the join key), `question` (its title), `options` (every option label),
  > `chosen` (the map's `status.option`: the option **id**, not its label),
  > `chosenLabel`, `rationale` (the card's `recommendation.why`), `source` and
  > `tickets`. The whole derivation is therefore testable with nothing reachable,
  > and no caller retypes a fork id or an option from a transcript.
- recorded: 2026-09-18
- expiry: none known

### Never hand-edit map.schema.json
- rule: The vocabulary is a byte-identical copy of what esas emits; test-design-map prints `SKIP reason=no-esas-checkout` (not a pass) without `$ESAS_CHECKOUT`.
- source: skills/design-map/SKILL.md:16-24 at c75ba88
- evidence:
  > - **`map.schema.json` is the vocabulary** — the closed sets (fork status kind,
  >   decided source, node level, map shape), a byte-identical copy of what esas
  >   emits at `packages/esas-schema/schema/map.schema.json`.
  >   **Never hand-edit `map.schema.json`**: a value added here and not in esas is a second source
  >   for one closed set, and an edited copy can no longer be told stale. To
  >   change a set, change it in esas and copy the emitted file over whole.
  >   `scripts/test-design-map.sh` compares the copy with `$ESAS_CHECKOUT` when
  >   that is set, and prints `SKIP reason=no-esas-checkout` (not a pass) when it
  >   is not.
- recorded: 2026-09-17
- expiry: none known

### --expect is the count of the grilled tree, never read back off the payload
- rule: The two counts catch different drops: a fork lost between interview and file, and one lost while drawing.
- source: skills/design-map/SKILL.md:85-91 at c75ba88
- evidence:
  > **--expect is the count of the grilled tree** — the number of forks I hold in
  > my own head after the interview, not a count read back off the payload or the
  > page. It is mandatory (C1/F2): the two counts it gates catch different drops —
  > `--expect` against the payload catches a fork lost between the interview and
  > the file I wrote; the renderer's own page-vs-payload count catches one lost
  > while drawing. A mismatch on either is `outcome=error`, names both counts, and
  > leaves no page behind.
- recorded: 2026-09-16
- expiry: none known

### select never launches, never hangs, and pins the target
- rule: `select` is pure over captured files, its one network call has a 2 s ceiling with no retry, and a board that dies mid-sitting is handled at the sync point with one `get_map`.
- source: skills/design-map/SKILL.md:535-552 at c75ba88
- evidence:
  > **D3 — never launch anything (this skill, or `select`, does not spawn a process).** The choice of
  > target never triggers a launch by itself; a board only exists because something else already started
  > one, or because the owner acts on the one-time launch line above.
  >
  > **D4 — never hang.** No row of the table retries, polls, or waits past the `--max-time 2` on the one
  > network call (`board.json`'s curl) it is built from. A slow or wedged board reads exactly like no
  > board: `board.json` is empty, row 6 fires, the design proceeds on the artifact.
  >
  > **D5 — the board dies mid-sitting.** This is not a `select` row; it is what the agent does at a sync
  > point when `board.json`'s curl comes back empty on a design that is already `target=board`. Call
  > `get_map` once (no retry). If it answers, merge its readback statuses onto the local `map.json` by
  > fork id — a fork the readback does not mention keeps its local status untouched, and a fork only in
  > the readback (never locally known) is ignored — set the merged map's `feedSeq` to the readback's
  > `mapSeq`, and pipe the result into `design-map write <map.json>` on stdin (there is no dedicated merge
  > verb; `write`'s existing whole-file replace already expresses it). Tell the owner once, using the same
  > launch-line wording as row 6. If the board is **still** down at the next sync point, stop trying it at
  > all and render the artifact from `map.json` as it now stands. A failed MCP tool call anywhere in this
  > recipe (not just `get_map`) means no more MCP tool calls for the rest of the session.
- recorded: 2026-09-17
- expiry: none known

## skills/esas-design/SKILL.md

### Read ids before referencing them: UNRESOLVED_EDGE_ENDPOINT and label casing
- rule: Extracted `ext` ids carry an `external-system-` segment a proposed node will not; label casing changes the derived id; propose nodes first and read the returned nodeIds before sending edges.
- source: skills/esas-design/SKILL.md:255-276 at c75ba88
- evidence:
  > **Read ids before referencing them — never guess a derived id.** No verb lists
  > node ids (`get_flow` *requires* a root command id you already have), so the
  > entry point is grepping `.esas/graph.json`. Ids read
  > `<subdomain>_<abbrev>_<kebab-label>` (`cmd`, `evt`, `rm`, `agg`, `pol`, `sys`,
  > `ext`, `ui`). Two things break the obvious guess:
  >
  > - **Extracted `ext` ids carry an extra `external-system-` segment a *proposed*
  >   node will not reproduce** — it comes from the extractor's artifact naming, not
  >   from `(subdomain, type, label)`, so an edge to
  >   `…_ext_external-system-foo-api` fails `UNRESOLVED_EDGE_ENDPOINT` against a
  >   node that landed as `…_ext_foo-api`.
  > - **Label casing is load-bearing.** `"MercadoLibre Messaging API"` does not kebab
  >   to `mercadolibre-messaging-api` (the caser splits internal capitals and
  >   acronyms); `"Mercalibre Messaging Api"` does. Same artifact, two ids, no
  >   warning — and it survives review because it is a correctly-spelled label.
  >   Prefer plain Title Case wherever the derived id will be referenced.
  >
  > So where a batch introduces a node later edges must point at and the id is not
  > certain, **propose the nodes first, read the returned `nodeIds`, then send the
  > edges** — a deliberate exception to *batch everything*, because `propose`
  > rejects the whole batch and the no-take-it-apart rule makes each miss a full
  > round-trip.
- recorded: 2026-09-04
- expiry: esas's id derivation changes

### No hook can wake the board session
- rule: `FileChanged` has no decision control and `Stop` fires before anything is answered; the session channel is a persistent `Monitor` and the SessionStart hook only nudges.
- source: skills/esas-design/SKILL.md:88-96 at c75ba88
- evidence:
  > `persistent: true` makes it **session-scoped rather than turn-scoped**, which is
  > the whole mechanism: a command-scoped channel dies at every session boundary and
  > only the user remembering to ask brings it back.
  >
  > **No hook can do this.** `FileChanged` has no decision control (side effects
  > only, cannot inject context); `Stop` fires the instant you finish posting, before
  > anything is answered. Ruled out at the mechanism level. This plugin's
  > `SessionStart` hook may *tell* you to open the channel — that is a nudge to run
  > the `Monitor` call, not a second wake mechanism.
- recorded: 2026-09-04
- expiry: Claude Code hooks gain a way to inject context on a file change

### Verified at esas @ de920db: --non-anchor serves a board with no extracted reality
- rule: A repo with no graph can still get a map; the owner launches `esas-session-server --non-anchor` from the launch line, and nothing in design-map spawns it.
- source: skills/esas-design/BOARD-SETUP.md:15 at c75ba88
- evidence:
  > Verified at esas @ de920db: `packages/esas-session-server/src/launcher.ts:261-262` parses `--non-anchor` into `args.nonAnchor = true`, and `:303` sets `anchored: !args.nonAnchor`.
- recorded: before 2026-09-19
- expiry: esas changes the launcher's --non-anchor handling

### The arming, not the transport, was what kept failing
- rule: The summon channel is one persistent Monitor call opened at SessionStart for every session in the repo, replacing a watcher armed by /design that died at every session boundary.
- source: skills/esas-design/BOARD-SETUP.md:70; hooks/README.md:88-93 at c75ba88
- evidence:
  > That replaces a watcher that had to be armed on exactly the right turn and re-armed after every one — the arming, not the transport, was what kept failing.
  >
  > **Why a hook exists at all** is the whole reason the mechanism was rewritten.
  > The channel it replaced was a shell watcher armed by the `/design` command, so
  > its arming died at every session boundary — a resume, a `/handon`, any other
  > session in the repo — and the recovery was the human remembering to ask.
  > `SessionStart` fires for **every** session in the repo, resumed ones included,
  > so the channel can go up at t=0 with nobody asked.
- recorded: 2026-08-13
- expiry: none known

### Never spawn the board unasked: an orphan squats :3727 for the next repo
- rule: The board is offered when the first batch of questions is ready and started only on a yes; the port is claimed strictly.
- source: skills/esas-design/BOARD-SETUP.md:60 at c75ba88
- evidence:
  > **Never spawn it unasked, and never at the preflight.** The port is the reason, and it is strict (below): a board nobody asked for squats :3727 for as long as it runs, and the repo that pays is the *next* one — its board will not bind, in a session that did nothing wrong and has no reason to suspect a board it never started. An orphan is also the hardest kind to find, which is what the `board: other-repo` row of the command's verdict table is for. Offering at the preflight makes that the ordinary outcome rather than the unlucky one: the preflight answers *capability*, and a checkout that can hold a board is not yet a design that needs one.
- recorded: 2026-08-08
- expiry: the board stops claiming its port strictly

### Do not set ESAS_REPO_PATH
- rule: .mcp.json is git-tracked and byte-identical in every worktree, so an absolute path would make every worktree design against one checkout.
- source: skills/esas-design/BOARD-SETUP.md:29 at c75ba88
- evidence:
  > **Do not set `ESAS_REPO_PATH`.** The server designs against its working directory, and Claude Code spawns a project server with the working directory set to the project root — including inside a worktree, where that is the worktree itself. `.mcp.json` is git-tracked, so the entry is byte-identical in every worktree of a fleet: pinning an absolute path there would make all of them design against the one checkout it names, which is exactly the split layer the main-checkout rule exists to prevent. Unpinned, a worktree answers `ESAS_DIR_MISSING`, which is the right answer there.
- recorded: 2026-08-08
- expiry: none known

## skills/esas-pending/SKILL.md

### The pending count is telemetry, never a trigger
- rule: Never act on, sync, or mention pending ESAS board changes unless the user asks; the only ask is a summon frame on the session channel.
- source: skills/esas-pending/SKILL.md:3; hooks/README.md:43; README.md:27; CONTEXT-PROVIDERS.md:14-24 at c75ba88
- evidence:
  > description: "STANDING RULE for the `esas: N pending (seq A→B)` line injected by this plugin's UserPromptSubmit hook: it is telemetry, never a trigger — never act on, sync, or even mention pending ESAS board changes unless the user asks. The one carve-out: a board summon — a frame arriving on the ESAS session channel (/api/esas/ws) that this session holds open — IS the user asking, and is synced; the count never is. Read this file only if unsure what the line means or whether to react to it."
  >
  > **telemetry, never a trigger**; the standing rule for reacting to it lives in
  >
  > Hook: **`UserPromptSubmit` → `esas: N pending (seq A→B)`** (`hooks/esas-pending.sh`). While the user has unsynced edits on the ESAS design board, the count goes in front of the next prompt so Claude knows its picture is stale — telemetry, never a trigger. Silent and free in every repo without a `.esas/` directory, and it always exits 0, because a `UserPromptSubmit` hook that doesn't would erase the user's prompt. The standing rule for reacting to it (never unsolicited) is the **`esas-pending`** skill. See `hooks/README.md`.
  >
  > The obvious alternative was tried in this repo and is rejected **on its own measured evidence**.
  > A hook that injects a count exists — `hooks/esas-pending.sh`, a `UserPromptSubmit` hook that runs
  > unconditionally on every prompt in every repo where the plugin is enabled — and the standing rule
  > in `skills/esas-pending/SKILL.md` that governs it says:
  >
  > > it is telemetry, never a trigger — never act on, sync, or even mention pending ESAS board
  > > changes unless the user asks.
  >
  > That is a surface this codebase built, found to be an interruption, and then suppressed by
  > standing rule. It arrives *beside* the reasoning, at a moment nobody chose, carrying no way to be
  > acted on — so the only safe rule was to ignore it. **Do not rebuild it.** There is also a hard limit, and it is the constraint that forced this seam into the base plugin
- recorded: 2026-08-13
- expiry: none known

## skills/handoff/SKILL.md

### Emit plugin-qualified command names in a handoff
- rule: A bare slash name resolves against the host repo's namespace, and a repo mid-migration has real files with the same names.
- source: skills/handoff/SKILL.md:15 at c75ba88
- evidence:
  > **Emit plugin-qualified command names** — `/bett3r-ai-workflow:verify-build`, not `/verify-build` — in `status`, `flow.prev`, `flow.next` and every `skill-runbook` key. A bare slash name resolves against the **host repo's** namespace, which this plugin cannot see or control, and any repo mid-migration from local commands to the plugin has real files with these exact names still sitting in `.claude/commands/`. The collision is silent: both are invocable, and picking the wrong one runs different instructions. It degrades the handoff as a human artifact too — a reader cannot tell which command produced it. Qualifying costs nothing where there is no collision. (`flow.step` values stay bare; they name pipeline *positions*, not invocable commands.)
- recorded: 2026-08-08
- expiry: none known

### A conflict inventory expires on the next sibling merge: predicted one, produced four
- rule: Scope a measured inventory to the sha it was computed against and never carry a negative generalisation beyond the branches measured.
- source: skills/handoff/SKILL.md:18 at c75ba88
- evidence:
  > - **A conflict inventory expires on the next sibling merge.** Scope it to the master SHA it was computed against and mark it as expiring — not as a property of the branches. Content on an *unmerged* sibling is invisible to the analysis, so a "zero hand-authored conflicts" generalisation is true only of the branches actually measured; never carry a negative generalisation beyond that set. (One inventory predicted one conflict and the merge produced four, two of them the only ones needing real judgement — and a session planning around the inventory would have handed exactly those to a mechanical resolver.)
- recorded: 2026-08-08
- expiry: none known

### A .work occupancy warning is a measurement: it described a finished lane as in-flight
- rule: Write the warning with its liveness test and separate what is unrecoverable from what merged commits preserve.
- source: skills/handoff/SKILL.md:19 at c75ba88
- evidence:
  > - **A `.work/` occupancy or collision warning is a measurement too, and it reads as a structural fact.** Write it with its **liveness test** — the tickets it names and what would prove them done (`git log --all --grep=<ID>` merged commits, `passes: true` across the referenced `slices.yaml`, the blocker's commit) — and list separately what in `.work/` is genuinely **unrecoverable** (an unprocessed `record.md` / `learnings.md` buffer) from what merged commits already preserve. One warning described a lane as in-flight that had finished before the warning was written, and never mentioned the one thing worth protecting.
- recorded: 2026-09-05
- expiry: none known

### Recorded agentIds are session-scoped: No transcript found
- rule: Carry the context needed to re-dispatch fresh; if resuming a warm agent is load-bearing, the handoff is broken by construction.
- source: skills/handoff/SKILL.md:20 at c75ba88
- evidence:
  > - **Recorded `agentId`s are session-scoped.** "Resume the warm agent, it has the context" fails with `No transcript found` from any new session — which is precisely the situation a handoff exists to serve. Record the same-session precondition alongside any agent map, and **carry the context needed to re-dispatch fresh** (worktree, branch, tip SHA, procedure, invariants). If resuming is merely an optimisation the handoff survives its failure; if it is load-bearing, the handoff is broken by construction.
- recorded: 2026-08-08
- expiry: the harness lets a new session resume another session's subagent

## skills/critique/SKILL.md

### Hand the lenses facts, not a summary: one finding justified the whole cost
- rule: A prose summary is self-consistent by construction; given `file:line` facts the lenses catch the argument being wrong about the code, and restatement-heavy output is a cost signal.
- source: skills/critique/SKILL.md:44; skills/critique/SKILL.md:46 at c75ba88
- evidence:
  > One such pass returned a single finding that justified the whole cost: a call site discarding exactly the value the ticket was about, at exactly the site of the silent degrade. It flipped the recommended fix and invalidated the draft's proposed rendering outright.
  >
  > **Restatement-heavy output is a cost signal, not a clean bill of health** — it means the input was too abstract, not that the design was sound.
- recorded: 2026-08-08
- expiry: none known

## CONTEXT-PROVIDERS.md

### A hook cannot enter Step 3's reasoning
- rule: A hook fires around a tool call and an MCP call cannot see the slash command; the place a contribution must land is a fork in an interview, which is why the seam is in the base plugin and not an overlay.
- source: CONTEXT-PROVIDERS.md:24-27 at c75ba88
- evidence:
  > acted on — so the only safe rule was to ignore it. **Do not rebuild it.** There is also a hard limit, and it is the constraint that forced this seam into the base plugin
  > rather than an overlay: **a hook cannot enter Step 3's reasoning.** It fires around a tool call,
  > and an MCP call cannot see the slash command at all — but the place a contribution has to land is a
  > fork in an interview.
- recorded: 2026-09-06
- expiry: none known

### An extension point with exactly one known consumer: resist generalising
- rule: No provider ordering, priorities, merge policy or negotiation protocol until a second consumer exists to be right about.
- source: CONTEXT-PROVIDERS.md:98-101 at c75ba88
- evidence:
  > This is an extension point with exactly one known consumer. **Resist generalising further than
  > that one case justifies.** No provider ordering, no priorities, no merge policy, no negotiation
  > protocol — none of it has a second consumer to be right about yet, and each one is a rule a future
  > provider would have to be wrong about first before anyone learned what it should say.
- recorded: 2026-09-06
- expiry: a second context provider exists

## hooks/README.md

### hooks/hooks.json is loaded automatically: verified three ways on Claude Code 2.1.220
- rule: The manifest's `hooks` field is for additional hook files only; `${CLAUDE_PLUGIN_ROOT}` is substituted only for plugin hooks and `args` is the exec form.
- source: hooks/README.md:5-22; hooks/README.md:30-37 at c75ba88
- evidence:
  > `hooks/hooks.json` — **this exact path** — is loaded automatically for every
  > enabled plugin. Nothing in `plugin.json` needs to reference it; that manifest's
  > `hooks` field is for *additional* hook files only, and pointing it back here is
  > an error ("The standard hooks/hooks.json is loaded automatically, so
  > manifest.hooks should only reference additional hook files").
  >
  > Verified against Claude Code 2.1.220, three ways:
  >
  > 1. **The published schema** — `https://json.schemastore.org/claude-code-plugin-manifest.json`
  >    describes `plugin.json`'s `hooks` as "additional hooks (in addition to those
  >    in `hooks/hooks.json`, if it exists)".
  > 2. **`claude plugin validate <plugin> --strict`** reads this file — renaming the
  >    event to `UserPromptSubmitt` fails with
  >    `hooks.UserPromptSubmitt: Invalid key in record`.
  > 3. **A live run** — `claude -p … --plugin-dir <this plugin> --debug-file …`
  >    logged `Read hooks.json for plugin bett3r-ai-workflow`, then
  >    `Hook UserPromptSubmit success: esas: 2 pending (seq 1→4)`, and the line
  >    reached the model's context.
  >
  > `${CLAUDE_PLUGIN_ROOT}` is substituted in `command` **and** in each `args`
  > element, and is available *only* to plugin hooks — a `settings.json` hook that
  > references it is rejected. `${CLAUDE_PROJECT_DIR}` is both substitutable and
  > exported into the hook's environment, which is what `esas-pending.sh` reads.
  >
  > `args` is the exec form: the command is spawned directly, with no shell
  > re-parse, so a plugin path containing spaces cannot break the invocation. Keep
  > `command` a bare executable name when `args` is present.
- recorded: 2026-08-01
- expiry: Claude Code changes the plugin hook loading contract

### esas-pending.sh always exits 0 and is free without a board: below the noise floor
- rule: A UserPromptSubmit hook that exits 2 erases the user's prompt; the hook's own work does not register against an empty script, and it degrades silently.
- source: hooks/README.md:46-60 at c75ba88
- evidence:
  > Two properties are load-bearing, because this runs on **every prompt in every
  > repo** where the plugin is enabled (there is no per-directory matcher):
  >
  > - **It always exits 0.** A `UserPromptSubmit` hook that exits 2 blocks
  >   processing and erases the user's prompt. Every path here — corrupt cursor,
  >   unreadable feed, torn feed, binary garbage — exits 0.
  > - **It is free when there is no board.** Line 2 is
  >   `[ -f "${CLAUDE_PROJECT_DIR:-.}/.esas/ops.jsonl" ] || exit 0`. Measured
  >   against an empty script on the same machine, the difference is **below the
  >   noise floor** — the whole cost is the process spawn that every command hook
  >   pays, and the hook's own work does not register.
  >
  > It also degrades silently rather than loudly: with `wc` and `awk` — the only two
  > tools it still needs — absent (`PATH=/nonexistent`) it prints nothing, to
  > either stream, and exits 0.
- recorded: 2026-08-01
- expiry: none known

### The scan is linear in feed size: 4.6 s at 20,000 ops, at the timeout
- rule: Hitting the 5 s timeout is benign (no line, prompt proceeds); layout writes are excluded from the count, not the scan.
- source: hooks/README.md:62-75 at c75ba88
- evidence:
  > The declared `timeout` is 5 s. Scanning cost is linear in feed size, on the feed
  > the cursor has *not* bounded:
  >
  > | feed | scan |
  > |---|---|
  > | 1 MB / 2 000 ops | 0.47 s |
  > | 9.7 MB / 20 000 ops | 4.6 s — **at the timeout** |
  >
  > A design session's semantic feed does not approach that, but debounced
  > `class: layout` position writes are the plausible route: they are excluded from
  > the *count*, not from the *scan*. Hitting the timeout is benign — the hook is
  > killed, no line is injected, and the prompt proceeds untouched, because a
  > timed-out hook is not a non-zero exit. It costs one prompt's telemetry, never
  > the prompt.
- recorded: 2026-08-01
- expiry: the feed format or the hook's scan changes

### esas-session-channel.sh speaks in exactly one state
- rule: A board answering on the port, serving this checkout, with `sessions: 0`; everything else is silent, because `.esas/` existing is not sufficient.
- source: hooks/README.md:100-112 at c75ba88
- evidence:
  > **Silence is the behaviour under test.** It speaks in exactly one state: a board
  > answering `GET /api/esas/status` on `${ESAS_BOARD_PORT:-3727}`, serving **this**
  > checkout (`repoPath` matched in both JSON spellings and both the logical and
  > physical spelling of the project root), and reporting `sessions: 0`. Nothing on
  > the port, a board serving another checkout, `sessions >= 1`, and a board with no
  > `sessions` field at all (unknown, never zero) are **all silent** — `.esas/`
  > existing is deliberately *not* sufficient, or every unrelated session in a
  > designing repo would open a socket it will never use.
  >
  > What it does **not** cover: a board restarted later in the session, which
  > `SessionStart` has already run past. That is recovered by the
  > `esasSessionChannel` notice `esas-mcp` attaches to every tool result while the
  > channel is shut. This hook buys t=0 only.
- recorded: 2026-08-13
- expiry: none known

## EVIDENCE.md

### A gate states its blind spot in the same breath as its verdict
- rule: Green with no named blind spot is a claim, not a result; every SKIP, INCONCLUSIVE and unselected guard goes in the PR body by name.
- source: EVIDENCE.md:23; skills/full-gate/SKILL.md:117 at c75ba88
- evidence:
  > **The rule: a gate states its blind spot in the same breath as its verdict.** "Green" with no named blind spot is a claim, not a result.
  >
  > - **A gate's verdict names its blind spot in the same breath.** Any step reported `SKIP` or `INCONCLUSIVE`, any tier the repo excludes from its widest run on purpose, and — on every scoped run — the fact that unrelated suites and tree-counting guards were **not selected**, goes into the PR body by name. Silence there reads as coverage.
- recorded: 2026-08-08
- expiry: none known

### A negative result is evidence only if the probe could have produced a positive
- rule: Every absence claim ships with a positive control run in the same breath.
- source: EVIDENCE.md:25 at c75ba88
- evidence:
  > **The corollary, which catches the whole class on its own:** *a negative result is evidence only if the probe could have produced a positive.* Every absence claim — zero callers, no offenders, no consumers, nothing drifted — ships with a **positive control**: something the probe must flag, run in the same breath. A detector that has never been seen to fire is not evidence of calm.
- recorded: 2026-08-08
- expiry: none known

### A check that takes configuration is verifiable only on the path it is configured right
- rule: The configured-wrong path needs its own assertion; `COUPLING_FORBIDDEN_TERMS='zzz-never-appears'` printed `41 passed`.
- source: EVIDENCE.md:27 at c75ba88
- evidence:
  > **A check that takes configuration is verifiable only on the path it is configured *right*.** When a gate gains an input — an env-overridable file list, a term list — the configured-**wrong** path needs its own assertion: the table is non-empty, it covers the known subjects, and the asserted-row count reconciles. `COUPLING_FORBIDDEN_TERMS='zzz-never-appears'` exited 0 and printed `41 passed` — byte-identical to a genuine pass, with the invariant checking nothing. Contrast a hard override that fails *loud* (`MARKER_PY=/bin/false`): silent-green and loud-red differ in kind, not degree.
- recorded: 2026-09-06
- expiry: none known

### Ask of every check whether it fails alarming or fails reassuring
- rule: Reassuring-failing checks are the ones that need the positive control.
- source: EVIDENCE.md:29 at c75ba88
- evidence:
  > **Ask of every check whether it fails alarming or fails reassuring.** A false alarm is investigated in a minute. The identical defect in a success check — "no errors in ten minutes, therefore green" — is believed. Reassuring-failing checks are the ones that need the positive control.
- recorded: 2026-08-08
- expiry: none known

### Mutation is one-to-one, and redundancy is not defence-in-depth in a guard
- rule: For each clause name the mutation that kills it and the assertion that catches it; a second inline copy is mutation-blind, a `^` beside `re.match` survived three mutations at 52/52, and a prose guard is mutated by rewording.
- source: EVIDENCE.md:37 at c75ba88
- evidence:
  > - **Mutation.** Break the production line the test claims to catch, and watch it go red — reporting which assertion failed, with what values, and **which consumers** the mutation reached. A predicate claimed as single-source-of-truth should fail at least one test per declared consumer; a shortfall *is* the finding, because a second inline copy of the rule is mutation-blind. **The mapping must be one-to-one:** for each clause of a rule, name the mutation that kills it *and* the single assertion that catches it. **Redundancy is not defence-in-depth in a guard** — two clauses enforcing the same predicate at the same position make each other unkillable (a `^` beside a `re.match`, which anchors regardless, survived three separate mutations at 52/52 green), and an unkillable clause is one no gate can ever report on. Where redundancy is found the fix is to delete the twin, not to wrap a fixture around it. Where a slice's deliverable **is** a test or a guard there is no natural RED at all, so mutation is the only evidence available. A guard asserting an *absence* additionally needs a positive and a negative control, and if it walks a tree, its traversal pinned — or it passes by never descending. **For a guard over prose** (a rule stated in a command, skill or agent), deleting the sentence is not the mutation that matters — **rewording is**: (1) an added sentence contradicting the rule while the pinned one stays, (2) the rule inverted in place with its keywords kept, (3) the sentence moved to where it no longer precedes the action it gates. A presence needle or keyword list survives all three — five deletion-mutated guards in one run did, for ~10 extra verifier rounds. What holds is a **closed set**: every unit of the section or file pinned, keyed by its section, so any addition, edit or move fails and names the unit, with any executable block also *run*. A legitimate rewording then updates the pinned list; the guard says so.
- recorded: 2026-09-12
- expiry: none known

### State what a count counts, and quote symbols as the source spells them
- rule: A uniqueness or exhaustiveness claim is a probe, never a premise.
- source: EVIDENCE.md:48 at c75ba88
- evidence:
  > - **A uniqueness or exhaustiveness claim is a probe, never a premise.** "The only surface", "nothing else reads this", "three call sites" — grep before building on it. State what a count counts ("5 files / 7 call expressions", not "five call sites"), and quote symbols **as the source spells them**: a paraphrased identifier is indistinguishable from a real one until you grep.
- recorded: 2026-08-08
- expiry: none known

### The limit is part of the measurement: --limit 200 re-measured at 506; 87 of 196 ADRs
- rule: Write the command inline with its flags and assert exactly what it tested.
- source: EVIDENCE.md:49 at c75ba88
- evidence:
  > - **A measured figure carries the command that produced it *and* the predicate it tested.** **The limit is part of the measurement:** a count equal to the limit passed is a *lower bound*, not a population — so write the command inline with its flags (`gh pr list --state merged --limit 200`), never its name. Recorded as `gh pr list`, that `200` was a page cap read as a corpus size and re-measured at 506, already having sized a backfill. **And the prose must assert exactly what the command tested** — when one command answers two questions, the figure belongs to one of them, so name which: `87 of 196 ADRs` was correct as *a path token anywhere in the prose* and was cited for *a structured `Grounding:` line*, which is 18–21. That half is the worse one, because re-running the recorded command reproduces the figure and appears to confirm the claim. (`wc -c`, not `du`, for corpus size.)
- recorded: 2026-09-06
- expiry: none known

### Probe hygiene: BSD getopt stops parsing options at the first operand
- rule: A negative-universal sweep carries a positive control on its own filter or pathspec; the listed traps each exit 0 with nothing on stderr.
- source: EVIDENCE.md:68 at c75ba88
- evidence:
  > - **A pattern that matches nothing returns a clean zero — so a negative-universal sweep carries a positive control on its own filter or pathspec** (`git ls-files -- <pathspec> | wc -l` > 0, or the same probe on a token known present). That gate covers the traps not yet listed; the listed ones, each exit 0 with nothing on stderr: `--include` **after** the path operands (BSD `getopt` stops parsing options at the first operand, so the flag becomes a filename — flags first); a filter naming the wrong extension (the template was `.html`, the filter said `.hbs`, and the defect it "ruled out" affected 100% of a document class); a quoted **git pathspec with `**`**, which matches no path without `:(glob)` magic (`':(glob)dir/**/*.ts'`, or just `'dir/'`); and three zsh shapes — an **unquoted** glob flag (`--include=*.ts`) expanded and aborted before `grep` sees it, a command stored in a variable (`PG="psql -At"; $PG -c …`) that is not word-split, and an unquoted word starting with `=` (`echo ==== X`) that aborts the rest of a `;`-chained probe. These recur despite being documented, because briefs say *what* to verify, not which command to run — so the rule lives in every agent that probes (`design-lane`), not in a brief.
- recorded: 2026-09-12
- expiry: none known

### A cd inside a compound command persists: cat >> decisions.md created a new file in the root
- rule: Use absolute paths, `git -C`, or a subshell.
- source: EVIDENCE.md:69 at c75ba88
- evidence:
  > - A `cd` inside a compound command **persists into later calls**, silently invalidating every relative path afterwards — an unqualified `cat >> decisions.md` created a new file in the repo root and printed "updated". Use absolute paths, `git -C <path>`, or a subshell — `( cd X && … )`.
- recorded: 2026-09-05
- expiry: none known

### cat on a large file defeats itself
- rule: A known-large artifact is a Read or a windowed `sed -n` after an index pass, never a `cat`; an agent grounds on the 2 KB preview believing it read the whole thing.
- source: EVIDENCE.md:73 at c75ba88
- evidence:
  > - **`cat` on a large file defeats itself** — the output is persisted to a file and a 2 KB preview returned, and re-reading *that* persists again; an agent grounds on the preview believing it read the whole thing. A known-large artifact is a `Read` or a windowed `sed -n` after an index pass (`grep -n '^##'`), never a `cat`; and a source grep that walks `build/` or a checked-in `dist/` returns an unusable bundle dump.
- recorded: 2026-09-05
- expiry: the tool stops truncating large outputs to a preview

### Every inherited fact has an expiry
- rule: Stamp a claim with the sha, ref or moment it was computed against and re-derive it before acting.
- source: EVIDENCE.md:51 at c75ba88
- evidence:
  > **Every inherited fact has an expiry.** A conflict inventory dies on the next sibling merge. A pinned base moves when someone outside the run merges. A residual ticket goes stale against its own fleet's tail merges. A recorded `agentId` dies with its session. Stamp a claim with the sha, ref or moment it was computed against, and re-derive it before acting.
- recorded: 2026-09-06
- expiry: none known

## Appendix — needles owned elsewhere

Listed by index into `scripts/needles.json`, not by literal, so this file never satisfies another plugin's needle and that plugin's own gate stays load-bearing.

Needles in `scripts/needles.json` whose home at `c75ba88` is another plugin. They are listed here for
completeness of the coverage table only; this plugin carries no entry for them and does not own them.

- needles.json #55 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #56 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #57 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #58 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #59 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #60 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #61 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #62 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #63 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #64 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #65 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #66 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #67 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #68 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #69 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #70 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #72 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #73 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #74 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #75 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #76 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #77 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #78 — owned elsewhere: bett3r-pv3-ai-skills
- needles.json #98 — owned elsewhere: bett3r-xp-layer
- needles.json #99 — owned elsewhere: bett3r-xp-layer
- needles.json #100 — owned elsewhere: bett3r-xp-layer
- needles.json #101 — owned elsewhere: bett3r-xp-layer
- needles.json #102 — owned elsewhere: bett3r-xp-layer

## Needle coverage

One line per entry of `scripts/needles.json` (145), in file order: the literal, and the entry title(s)
whose `evidence:` carries it byte-exact on one line, or where else it lives.

- [x] `## 1 — A verdict is evidence only about what it actually executed` → kept in artifact: plugins/bett3r-ai-workflow/EVIDENCE.md
- [x] `## 3 — An inherited statement is a claim with a provenance and an expiry` → kept in artifact: plugins/bett3r-ai-workflow/EVIDENCE.md
- [x] `a gate states its blind spot in the same breath as its verdict` → A gate states its blind spot in the same breath as its verdict
- [x] `a negative result is evidence only if the probe could have produced a positive` → A negative result is evidence only if the probe could have produced a positive
- [x] `fails alarming or fails reassuring` → Ask of every check whether it fails alarming or fails reassuring
- [x] `An unspecified seam adjacent to a specified one` → Enumerate what the block does not decide: unspecified seams
- [x] `Tests: 0 total` → A run that executed nothing is inconclusive, and it exits 0: Tests: 0 total · Before running anything at the base, check whether the diff surface already answers it
- [x] `stops parsing options at the first operand` → Probe hygiene: BSD getopt stops parsing options at the first operand
- [x] `known-baseline-failures.md` → The eager baseline capture is withdrawn; capture on demand for the red suites by name · A deliberately-red tier is a hand-down, not a capture: COMMITTED RED ON PURPOSE · All green is the wrong bar when the base is already red: diff by file, not by total
- [x] `134 × TS6305` → Capture a baseline on a freshly built tree: 134 × TS6305 + 24 became 0 + 1
- [x] `mutation-blind` → Mutation is one-to-one, and redundancy is not defence-in-depth in a guard
- [x] `slicesDone: 1` → passes: true in the same turn as the commit; the flag is the resume point
- [x] `auto-backgrounds at` → Run every command in the foreground: Bash auto-backgrounds at 600 s
- [x] `The fixture owns anything ambient` → The fixture owns anything ambient
- [x] `Never negative-test a guard by mutating tracked files` → Never negative-test a guard by mutating tracked files
- [x] `"none" is a valid answer, the field is not` → Issues / deviations / assumptions is required: "none" is a valid answer, the field is not
- [x] `failure outside the slice's surface` → Failure outside the slice's surface is not a slice RED
- [x] `output *is* the reply channel` → Your returned output is the reply channel
- [x] `PASS-with-follow-ups is not available for a named mitigation` → PASS-with-follow-ups is not available for a named mitigation
- [ ] `SYSTEM NOTIFICATION - NOT USER INPUT` → Background-wake dependence: the wake arrives inside a SYSTEM NOTIFICATION - NOT USER INPUT banner · Measure unverified platform behaviour in-band: the HMR push woke the session on its own writes · The comment-mode disarm is unmeasured; a wake never runs --final
- [x] `claim → probe run → holds / FALSE` → The checklist is always one incident behind; report a falsification table
- [x] `paraphrased identifier is indistinguishable from a real one` → State what a count counts, and quote symbols as the source spells them
- [x] `5 files / 7 call expressions` → State what a count counts, and quote symbols as the source spells them
- [x] `mechanism* behind a stated rationale` → Check the mechanism behind a stated rationale, not just the ask
- [x] `not that its prose fits` → Verify the block's claims, not that its prose fits
- [x] `unspecified seams` → Enumerate what the block does not decide: unspecified seams
- [x] `could a fresh session holding only this repo` → Could a fresh session holding only this repo run /plan without loss?
- [x] `no user to approve, by construction` → Unattended branch: no user to approve, by construction
- [x] `design-multi:resolved:v(\d+)` → Grep for the resolved marker before dispatching; two overlapping runs wrote opposite blocks
- [x] `The emit precedes the critique deliberately` → The emit precedes the critique deliberately
- [x] `evidence the agent stopped` → A task-completion notification is evidence the agent stopped, never that it produced anything
- [x] `delta: specified, deferred to build` → Glossary/ADR deltas ride in the block as delta: specified, deferred to build
- [x] `ADR-057` → Anecdote outweighing rule: compress the story to the clause that makes it credible · Three lanes once picked the same ADR-057
- [x] `status=ready` → Grep for the resolved marker before dispatching; two overlapping runs wrote opposite blocks
- [x] `diamond base` → You own a diamond base; a .ts.orig passes every gate invisibly
- [x] `Archive (never delete)` → Archive (never delete) a reused worktree's .work/
- [x] `git show <BASE>:<path>` → Recon is a hint: compute base-sensitive facts with git show <BASE>:<path>
- [x] `cliff` → Size --max-parallel by memory, not cores: the cliff
- [x] `TO: <TICKET-ID>` → Address every message from agents.yaml; lead with TO: <TICKET-ID>
- [x] `terminal state and a positive control` → A stall detector needs a terminal state and a positive control; one call sat 6h21m
- [x] `Failed to resolve entry for package` → install is not ready: Failed to resolve entry for package; 40 of 57 files collected zero tests
- [x] `parentTipAtCut` → A stacked child re-diffs against the parent's tip and forward-merges after its verify-build
- [x] `saleTime: data.date ?? existing.saleTime` → A directive carries the constraint, never the expression: saleTime double-billed a metering period
- [x] `author: 'human'` → Sweep: a mechanical guard disarmed by a sibling surface forwarding author: 'human'
- [x] `72 lines below a line the PR had just fixed` → Sweep: a seventh contradicting site 72 lines below a line the PR had just fixed
- [x] `--diff-filter=A --name-only` → Sweep: added files appear in no conflict list; a PCI oracle merged green testing nothing
- [x] `33 of 57 suites` → A green partial inventory reads as full coverage: 33 of 57 suites excluded
- [x] `delete_branch_on_merge` → A stacked child: merging into a stale base or deleting the base are both silent
- [x] `binary-classification symptom` → Sweep: a NUL sentinel in a .ts literal passed 8/8 and made the diff unreviewable
- [x] `Restatement-heavy output` → Hand the lenses facts, not a summary: one finding justified the whole cost
- [x] `ADR-NNN-slug.md` → The no-ADRs-yet default is docs/adr/ADR-NNN-slug.md and fires once per repo
- [x] `UNRESOLVED_EDGE_ENDPOINT` → Read ids before referencing them: UNRESOLVED_EDGE_ENDPOINT and label casing
- [ ] `Background-wake dependence` → Background-wake dependence: the wake arrives inside a SYSTEM NOTIFICATION - NOT USER INPUT banner
- [x] `No transcript found` → Recorded agentIds are session-scoped: No transcript found
- [x] `gate that never fired is indistinguishable from a gate that cannot fire` → A gate that never fired is indistinguishable from a gate that cannot fire
- [x] needles.json #55 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #56 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #57 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #58 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #59 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #60 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #61 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #62 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #63 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #64 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #65 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #66 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #67 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #68 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #69 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #70 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] `non-reconcilable` → Side-effect reconcilability: only a non-idempotent and non-reconcilable effect justifies a ledger
- [x] needles.json #72 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #73 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #74 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #75 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #76 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #77 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #78 → owned elsewhere: bett3r-pv3-ai-skills (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] `A closing keyword binds to exactly one` → A closing keyword binds to exactly one issue: 80 references shipped as 7 closures
- [x] `writes the eval scenario in the same pass` → A PR that splits an artifact writes the eval scenario in the same pass
- [x] `A split you can delete beats a split you have to verify forever` → There is a split floor: a 468-word skill with 668 and 351-word references
- [x] `Split by trigger, never by topic` → Split by trigger, never by topic
- [x] `Explanation may be referenced. Behavior may not` → Explanation may be referenced. Behavior may not
- [x] `a split with loading probability 1` → For behavior use a subagent: a split with loading probability 1
- [x] `substituted for *hook* invocations only` → CLAUDE_PLUGIN_ROOT is substituted for hook invocations only; plugin executables go in bin/
- [x] `Every millisecond is classified, never subtracted` → Wall time is not elapsed time: 3,587 minutes for an agent that worked 52
- [x] `A unit of work is not a session` → A unit of work is not a session: one branch spanned 26
- [x] `Each `/build` invocation is its own ledger` → Each /build invocation is its own ledger: 0% first-pass-green from 33% and 100%
- [x] `A failure to measure must never block landing the work` → A failure to measure never blocks landing
- [x] `One session is not one branch either` → One session is not one branch either: byte-identical totals
- [x] `292k tokens of context per turn` → Redirect every gate's output and read the tail: 292k tokens of context per turn
- [x] `Name a model on every dispatch` → Name a model on every dispatch
- [x] `never downgrade this one` → The verifier stays on opus and is never traded down
- [x] ``mis-routed` (too cheap a model)` → Every fix round is classified, in one line, before it is dispatched
- [x] `absent means opus` → Route mechanical slices to sonnet; absent means opus
- [x] `Effort is a pre-flight decision` → Effort is a pre-flight decision, not a per-dispatch one
- [x] `Splitting is not a token optimisation` → Splitting is not a token optimisation: 97% cache reads, 1–4% of ~210k per turn
- [x] needles.json #98 → owned elsewhere: bett3r-xp-layer (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #99 → owned elsewhere: bett3r-xp-layer (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #100 → owned elsewhere: bett3r-xp-layer (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #101 → owned elsewhere: bett3r-xp-layer (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] needles.json #102 → owned elsewhere: bett3r-xp-layer (literal kept out of this file so the other plugin's own gate stays load-bearing)
- [x] `A marker that survives a new `/start` is worse than no marker` → A marker that survives a new /start is worse than no marker
- [x] `zero providers is the normal case` → Zero providers is the normal case, and it is silent
- [x] `telemetry, never a trigger` → The pending count is telemetry, never a trigger
- [x] `a hook cannot enter Step 3's reasoning` → A hook cannot enter Step 3's reasoning
- [x] `Reset before every take, unconditionally` → Reset before every take, unconditionally
- [x] `is the single writer of `decisions.md` and `build-summary.md`` → The orchestrator is the single writer of decisions.md and build-summary.md
- [x] `ruled partial, unmet or cannot-determine` → Concerns fail closed: a hard entry ruled partial, unmet or cannot-determine fails
- [x] `is not-success, exactly like `outcome=fail`` → concerns-check outcome=error is not-success, exactly like fail
- [x] `Only the owner waives.` → Only the owner waives
- [x] `This command is the hard block` → The flow/concerns status is advisory; /merge-multi is the hard block
- [x] `a continued agent never takes another slice` → Every dispatch names its slice; a continued agent never takes another slice
- [x] `with no hunk behind it` → Re-check mode judges each finding against the diff, never the response
- [x] `The cap exists for the fix round, not the first pass` → Split a sweep over 10 files or 200 sites: the cap exists for the fix round
- [x] `never when the gap is the slice's own oracle` → Environment gaps: never when the gap is the slice's own oracle
- [x] `names which Step 2 branch sent a `sequential` slice` → modeReason names the Step 2 branch that sent a slice to the main tree
- [x] `Only a contribution the provider marks canonical may settle a fork` → Only a canonical contribution settles a fork; an outage is not an empty corpus
- [x] `a `contextProviders` key` → A provider is declared by a contextProviders key, never sniffed from tool presence
- [x] `a claim about the corpus where all you have is an outage` → Only a canonical contribution settles a fork; an outage is not an empty corpus
- [x] `a citation that lives only in the draft is destroyed by the next regeneration` → A citation that lives only in the draft is destroyed by the next regeneration
- [x] `that id has one home: the sidecar the verdict names` → A recorder's id has one home: the sidecar the verdict names
- [x] ``record` is pure over files` → record is pure over files
- [x] `Never probe whether the provider is up before calling` → Recording is never a gate; never probe whether the provider is up before calling
- [x] `as this lane's own resolution, never as the owner's` → Offer an auto-resolution back as this lane's own resolution, never as the owner's
- [x] `66.72M weighted tokens` → Yield at a slice boundary: 66.72M weighted tokens against 3.26M
- [x] `3.26M against 35M` → Yield at a slice boundary: 66.72M weighted tokens against 3.26M
- [x] `The saving is not the dispatch, it is the **ending**` → Yield at a slice boundary: 66.72M weighted tokens against 3.26M
- [x] `blocked-on=build-no-progress` → blocked-on=build-no-progress is the only guard on the yield loop
- [x] `denominated in committed slices` → Yield at a slice boundary: 66.72M weighted tokens against 3.26M
- [x] `second axis, and it is not a machine resource` → --max-parallel has a second axis, and it is not a machine resource
- [x] `one local worktree and nowhere else` → Push every slice: the branch exists in one local worktree and nowhere else
- [x] `walk-unstructured` → decided-nowalk and walk-unstructured are refusals, not counters
- [x] `decided-nowalk` → decided-nowalk and walk-unstructured are refusals, not counters
- [x] `slice-unscened` → Both zero-first-pass-green runs had no map: scenarios reach the unit with no map
- [x] `kind: structural` → Tautology: the expected value comes from expected_from and expected_source · Name the unit's seams before its oracles: 738 tests green with both wiring lines deleted
- [x] `plan-unseamed` → Name the unit's seams before its oracles: 738 tests green with both wiring lines deleted · Act on check-plan's reason; never invent a seams entry to match a slice
- [x] `unnamed-seam` → Name the unit's seams before its oracles: 738 tests green with both wiring lines deleted · Act on check-plan's reason; never invent a seams entry to match a slice
- [x] `extra-unjustified` → Name the unit's seams before its oracles: 738 tests green with both wiring lines deleted
- [x] `slice-unprobed` → Reachability: the probe is named at plan time; an erasure suite stayed 8/8 with PII unencrypted · Act on check-plan's reason; never invent a seams entry to match a slice
- [x] `expected_from` → Tautology: the expected value comes from expected_from and expected_source
- [x] `undiscriminating` → An undiscriminating RED is no evidence
- [x] `deterministic check, full stop` → Every fix round is classified, in one line, before it is dispatched · Mechanical → a deterministic check, full stop
- [x] `most context pressure` → Every fix round is classified, in one line, before it is dispatched · The reviewer imposes standards, not the implementer
