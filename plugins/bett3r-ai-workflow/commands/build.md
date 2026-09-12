---
description: Drive each vertical slice to green through the dual gate (executor → test → verifier) and commit it. The deterministic implementation loop.
---

# /build — drive the slices

Execute the slices in `.work/slices.yaml` — one at a time in the main tree, or, when Step 2 finds more than one ready at once, concurrently in a worktree pool — each through the **dual gate**, committing each as it passes (and, in the pool, landing it on the task branch). You are the orchestrator: you **dispatch agents and commit** — you do not implement code yourself.

## Argument: $ARGUMENTS
Optional slice id(s) to run (e.g. `2` or `2,3`). Default: all `passes: false` slices. `--max-parallel N` caps how many slices run at once (Step 2); absent, only the plan's width and the brief's `worktreePoolMax` do.

---

## Step 0 — Read your brief, if there is one

**If `.work/lane.yaml` exists, read it before anything else.** It is this unit's whole brief — written into the worktree from the outside — and it is where your inputs come from, not the caller. Take from it: `runners` (the host repo's runner/glob map — which command runs which test paths, so the mechanical gate resolves the slice's artifact to a runner that actually collects it), `preconditions` (the host repo's build/test preconditions), `modelRouting`, `adrAllocations`, and `worktreePoolMax` (the venue's cap on the worktree pool, Step 2 — read only; the venue writes it). Its **absence is a valid state** (a single `/start` flow has no brief), so say which of the two you ran under rather than defaulting silently: a missing brief and a unit that legitimately has none are indistinguishable, and that is exactly how a lane runs on the wrong defaults with nothing red.

Never accept these facts at the invocation instead. A step that learns a fact from whoever called it is a step **the other caller cannot run** — the per-step surface exists so that a step invoked on its own, by a caller it never spoke to, behaves identically.

## Step 1 — Load state

**Record the mode first.** Overwrite `.work/mode.yaml` with `mode: build` and the current work item (`work_item:` carried forward exactly as `/start` recorded it — read it from the existing `.work/mode.yaml` before the rewrite; never re-dated or re-derived from the branch) before reading anything else — full rewrite, never an append, so the marker names the command running now instead of the one that ran last on this branch.

Read `.work/slices.yaml`. If it doesn't exist: "No slices found. Run `/plan` first."

The `passes` flags + the git history **are** the progress — there is no separate progress file. Skip any slice already `passes: true` (report "resuming").

**Resolve the record's folder before dispatching anything**, the way `/design` Step 4 does: `work-docs-path --item <work_item>`, passing the `work_item` from `.work/mode.yaml` untouched, and reading its last line, not its exit code (ADR-004). `outcome=ok` names the folder as `path=`; `decisions.md` and `build-summary.md` live there, beside the committed `design.md` (see *The committed record*, below). `outcome=error` stops the run before any slice: say its `reason=` and end `blocked-on` (Step 6). **Never fall back** to a default root or a copy under `.work/` — a record written anywhere the script did not name is a record no reader finds.

## Step 2 — Order the slices, and size the worktree pool

Order by `depends_on` (topological). The **tracer-bullet slice runs first**. Slices ready at the same moment — every `depends_on` already landed — run concurrently, **each in its own worktree from a reusable pool**, and never side by side in one tree: one tree shares whole-repo build output, half-written files another slice's typecheck reads, generators, the lockfile and the git index. Everything else runs sequentially **in the main tree**, as it always has.

**The git mechanics are `worktree-pool`'s; the decisions are yours.** It sizes, provisions, resets, lands and tears down, and ends every call with one `WORKTREE-POOL:v1 cmd=… outcome=…` line. Redirect its output to a file and **read that line** — never the exit code alone (ADR-004). What is ready, which commit lands first, and what a refusal means are decided here, not by the script.

A call that prints **no verdict line** died before concluding. That is never a pass and never an outcome to reconstruct from git state: stop using the pool, check `git status` in the main checkout (a land may have died mid-cherry-pick), report it, and finish the remaining slices sequentially in the main tree.

1. **Size it.** `worktree-pool size .work/slices.yaml [--only <ids>] [--max-parallel N] [--pool-max N]`. Pass `--only` with the slice ids from `$ARGUMENTS` when this run is targeted, so the pool is sized for the slices that will actually run, not the whole plan. Pass `--pool-max` only with the brief's `worktreePoolMax` (a venue's disk cap — read it from `.work/lane.yaml`, never write it; a brief without the key means no cap), and `--max-parallel` only when this invocation was given one. The width is the largest set of those slices that can be ready at once. **`pool=0` means no pool** — width 1, or a cap below 2: run every slice sequentially in the main tree, provision nothing, and skip the rest of this step. **`outcome=error` → stop before dispatching anything** and report the `reason=`: `dependency-cycle`, `unknown-dependency` and `unreadable-plan` are `/plan` defects; `unmet-dependency-outside-only` means a targeted slice's parent is neither passed nor targeted — ask for the parent to be included rather than building the child on a branch without it.
2. **Provision once, serially, before any slice runs.** Resolve the host repo's install and build commands (the brief's `preconditions`, else its CLAUDE.md and `.claude/rules/`; say which, and pass `''` for one the repo does not have). Run `worktree-pool provision <pool>` and require `outcome=provisioned`. Then dispatch the `provisioner` agent for each listed worktree **one at a time**, and never while any gate of yours is running: concurrent cold builds contend for the same cores, and a gate under load fails falsely. `outcome=refused` (a path in the way that is not a worktree — never delete it; or `reason=reused-worktree-holds-work`, a previous run's worktree still holding an escalated slice's files or an unlanded commit — name its `path=` in the report as held work for a human, and never reset or remove it) or `outcome=failed` → no pool this run: `worktree-pool teardown` whatever it added, run the slices sequentially in the main tree, and report the reason. That costs speed, never correctness.
3. **Reset before every take, unconditionally.** Before a worktree takes a slice — its first included — run `worktree-pool reset <worktree> <task-branch> --install '<cmd>' --build '<cmd>'` and require `outcome=reset`. Its install and build run **whether or not anything changed**, and that is the point: a reused tree inherits stale `.tsbuildinfo` and stray compiled `.js` shadowing sources, and a warm tree must cost time, never correctness (`remote-ai-agents` D6). Never skip it because the lockfile did not move. `outcome=failed step=install|build` → retry that reset once (an install is the likeliest thing here to be environmental), then retire the worktree. `outcome=refused reason=unlanded|dirty` → the worktree holds work: retire it. A retired worktree's slice goes to another worktree, or to the main tree once none is left.
   **A worktree whose slice did not land takes no further slice until teardown** — whether the slice escalated at the gate, exhausted its retries, or conflicted at the land. Its reset would switch and `git clean -fd` the slice's work away, and a slice that escalated at the gate has **no commit** to protect it: a new-files-only slice is nothing but untracked files, which the reset's dirty check deliberately does not count. So it is retired, never reset, and teardown's refusal is what keeps that work on disk for a human.
4. **Dispatch into the worktree.** Each ready slice runs its full Step 3 dual gate there — executor, test-runner, scope-check and verifier are all handed the worktree path as the project directory — and its Step 4 commit is made in that worktree. A dependent slice becomes ready only after its parent's commit **landed**: its reset takes the task-branch tip, so a parent still sitting in a worktree does not exist for it.
5. **Land in dependency order, parents first.** For each green slice, `worktree-pool land <worktree> <sha> --base <reset tip>`, where `<reset tip>` is the `tip=` of that worktree's last reset verdict — only a sha strictly after it can be this slice's commit. Read by outcome:
   - `outcome=landed` → Step 4's `passes: true` happens now, recording the verdict's `sha=` — the **landed** sha, never the worker's — in `.work/slices.yaml`. **`already=true` reads the same way**: the change was already on the branch (a resumed run re-landing after a crash between the land and the record), and `sha=` names the commit carrying it. Record it; do not re-run the slice.
   - `outcome=conflict` → the task branch is untouched: ESCALATE that slice with the verdict's `paths=`, do not resolve it by hand, and do not dispatch its dependants. Its worktree keeps the commit and is retired (step 3).
   - `outcome=refused reason=main-checkout-dirty` → your own main tree has tracked modifications, which is Step 4's contamination: stop landing and surface them — never commit or discard them to make a land go through. Untracked files in the main checkout do not refuse a land.
   - `outcome=refused reason=sha-not-in-worktree` → the worker reported a sha its worktree does not hold. Read that worktree's `git log` yourself: if exactly one commit is in `<reset tip>..HEAD` of that worktree, land it; otherwise ESCALATE. Never land a sha from another worktree.
   - `outcome=refused reason=sha-not-after-base` → the sha is the reset tip or older, so the worker made no commit for this slice: it is not built. Never set `passes: true`; read it as a gate failure: re-dispatch the executor into the same worktree within the retry budget (its uncommitted work stays where it is, as a main-tree retry's would), and once the retries are spent, ESCALATE and retire the worktree (step 3).
   - `outcome=failed step=cherry-pick` → git refused before any conflict (an untracked main-tree file the commit would overwrite, or an empty pick with no equivalent on the branch). The branch is untouched: ESCALATE the slice with the output.
   - `outcome=error` → a usage defect, or `reason=tip-moved-after-abort`: stop all landing and inspect the task branch before anything else.
6. **Workers never write the record.** A worker reports facts in its result — its commit sha, gate verdicts, the deviations it flagged — and you alone write `.work/slices.yaml`, in the main tree, after the land. One writer, so a resumed run reads one file that cannot disagree with itself.
7. **Tear down once every slice landed.** `worktree-pool teardown`; `outcome=removed` ends the pool. `outcome=refused reason=unlanded|dirty` names worktrees still holding work — a commit on no branch, or the uncommitted files of a slice that escalated at the gate. Leave them, name them in the Step 5 report, and never remove them by hand. `outcome=failed step=worktree-remove` → report the path; never retry with force.

## Model routing — every dispatch names its model

An agent that names no model inherits the session's, which is the most expensive one you have. **Name the model on every dispatch**, from this policy — the roles differ by more than an order of magnitude in what judgment they actually need:

| Dispatch | Model | Why |
|---|---|---|
| `executor` | the slice's `model:` field; **`opus` when absent** | `/plan` marks the mechanical slices (scaffold from a framework skill, config, a test-only slice) `sonnet`. Anything it left unmarked — the tracer bullet, a seam, anything touching an invariant — stays `opus`. |
| `test-runner` | `haiku` (its own frontmatter) | Runs a command, parses a summary line. No judgment. |
| `scope-check` | `sonnet` (its own frontmatter) | `git status`, greps, a diff read. Mechanical by construction. |
| `verifier` | `opus` — **never downgrade this one** | It is the only gate positioned to catch a confidently-wrong oracle, and cheapening it is the corner that ships defects. It is also ~11% of a run's cost, so there is nothing to win here. |
| read-only sweeps (`Explore`, `general-purpose`) | `sonnet` | Grep-shaped, disjoint, and adjudicated by you afterwards. |

**Every dispatch description names `slice <id>`** — executor, test-runner, scope-check and verifier alike, retries included (e.g. `slice 3 executor retry 1`). `run-metrics` attributes a dispatch to its slice by a regex over that description and nothing else (`d.match(/slice\s*(\d+)/i)` in `retryLedger`, `scripts/run-metrics.mjs:582`); a description that does not name the slice is counted `unattributed`, and its tokens and retries belong to no slice.

Effort is **not** settable per dispatch — it is inherited from the session (`/effort`), so it is a decision you make once before running, not per agent. `/build` is the mechanical phase and does not need the session's design-grade effort; `xhigh` here buys little and is where the token bill concentrates.

A downgraded executor that fails shows up at the *mechanical* gate and is re-dispatched on `opus`; the verifier is unchanged either way. Record which model each slice ran on in the summary, so a retried `sonnet` slice can be re-marked next time.

## Step 3 — Per slice: the dual gate

For each slice, in order, in a **fresh agent context**:

0. **Scaffold what the design already fixed** — *only when the slice has a `designs:` list, a
   readable design layer is reachable (this checkout's own `.esas/`, or — in a fleet lane — the
   snapshot below), and the host repo ships a design scaffolder* (in a PV3 repo, the
   `scaffold-from-design` skill).

   **In a fleet lane, read the snapshot instead.** A worktree has no `.esas/` — that layer is
   scoped to one unit of work while a run spans N, and a lane must never write it — so the
   `provisioner` copies `design.json` + `graph.json` into `.work/design-snapshot/` and the
   scaffolder is pointed at them (`--design` / `--graph`). Emitted paths still resolve against the
   worktree. **Never create a `.esas/` in a worktree to enable this.**

   **In a pool worktree, read the main checkout's design layer, never a copy.** The worktree was
   reset from the task branch the main checkout has checked out, so its `.esas/design.json` and
   `.esas/graph.json` are this slice's design layer: run the scaffolder from the worktree with
   `--design` / `--graph` pointed at those two files, so emitted paths resolve against the worktree,
   and never create a `.esas/` there. Trust it only while the worktree's reset tip is still the main
   checkout's `HEAD`; once a sibling has landed since, skip the step and say *snapshot sha ≠ this
   worktree's base*.

   **Re-check the snapshot's sha before trusting it.** `manifest.yaml` records the sha its
   `graph.json` was extracted from; if that is not this worktree's base commit, the graph is wrong
   about what exists — it will call artifacts already real that this tree does not have, or anchor
   a fragment in a file that is not here, and neither shows up in the output. On a mismatch, skip
   the step and say so. The provisioner checks this at cut time; you check it again because a lane
   can outlive the tree it was cut from.

   **When the step cannot run, skip it and say which reason** — in the slice's summary, not
   silently. Most repos have no design layer and that is not a gap in them, but the absences mean
   different things and a silent skip makes them indistinguishable:
   - *no `designs:`* — this slice delivers nothing designed, **or** the plan predates the field;
   - *no design layer and no snapshot* — the run had none to carry, or the provisioner refused to
     carry a stale one. The slice's artifacts are hand-written through the `create-*` skills; that
     is a correct outcome, not a setup failure to repair;
   - *snapshot sha ≠ this worktree's base* — a lying snapshot; hand-write, and report it, because
     it means the fleet was cut from a moving tree;
   - *no scaffolder* — the repo's framework has none.

   Run it **scoped to this slice's `designs:` ids**, never un-scoped: an un-scoped run writes the
   whole design's stubs into whichever slice happens to run first, which buries the tracer bullet
   in unreachable code and defeats the point of slicing. Dry-run first, then write.

   **You** run it, not the executor, for two reasons. A blocked item is a *design* question — a
   new subdomain with no home, a policy issuing into two modules, a command whose handler does not
   exist yet — and those are surfaced to the user or taken to the board, which an executor in a
   fresh context is not positioned to do. And the scaffold report is context the executor needs:
   pass it in verbatim, including the fragments it must place and the `STILL OWED` items, so it
   starts from what exists rather than rediscovering it.

   **A block is not a reason to hand-write the artifact.** The refusal *is* the finding — a
   scaffolder that declines to guess a location has told you something the graph could not answer.
   Overriding it by hand discards the only signal that a decision is missing. If the block is that
   a handler does not exist yet, that is a slice-ordering defect: say so, and either reorder or
   ESCALATE.

   Generated files are **not** the slice's deliverable. They compile to stubs; the oracle still
   has to go RED first (step 1). A slice that is green immediately after scaffolding has an oracle
   asserting the stub.

1. **Implement** — dispatch the `executor` agent **on the model this slice routes to** (above) with: the slice (`behavior`, `oracle`, `gates`, intended files), the ticket, and the host project directory. The executor reads the repo's own rules/skills. Instruct it to work **RED → GREEN**: write the oracle test first, **run it and confirm it FAILS** for the right reason (the behavior is genuinely absent — not a typo, missing import, or compile error), *then* implement the minimal code to make it pass. It must report the RED evidence (the failure it saw before implementing).

   **If the slice's deliverable is a test or a guard** (no new production behavior, so no natural RED is available): **mutation-test it instead**, to [EVIDENCE.md](../EVIDENCE.md) §2's rules — one mutation per clause, each naming the assertion that caught it; controls and a pinned traversal for an absence guard. Report the mutation table where RED evidence would go. This is not optional rigor: RED→GREEN is the anti-tautology gate, and for this slice type it is **structurally unavailable** — which is exactly the type whose entire value is "does this assertion actually bite?"

   Cheaper version, worth running on *any* new case: **apply the smallest mutation the case claims to catch and watch the suite stay green.** If it does, the fixture abbreviated away the thing under test.

   **When the slice's gate is "behaviour is unchanged" / "the dispatched set is identical", a green pin or golden is a FLOOR, not equivalence.** Name what the corpus does *not* contain before trusting it (a one-case happy-path pin against a fallback-chain rewrite is a floor of zero), and require an **old-vs-new differential harness** — both implementations, one corpus, diffed outputs — whose corpus is **derived from the change**: enumerate the disagreement set of every predicate the rewrite alters (`||` → `??`, falsy → nullish, presence → truthiness) across *every* field, and vary the axes the migration changed the mechanism on. Pins stayed green through four live divergences in one fleet, two of which would have shipped a garbage ERP element and an infinite retry.

   **A slice whose premise proves false is not a no-op lane.** Report the premise as false with file, line and commit — never adapt the slice until it fits, which is how a plausible-but-wrong rewrite ships. Then ask what remains true: the slice's **gate** usually survives its body's falsification and is often *more* valuable once the body is deferred (it is what makes the deferred change safe later). Ship the gate without the body, or a **ratchet** — a test, an exported predicate, a census — that stops the thing the slice worried about from recurring; and say in the PR body which gates are met, which are not, and which were already true before the diff. Never let a partial slice claim its unmet gates.

   **When the accept criterion is a measured delta over a fixed corpus** (a pinned repo, a golden file, a benchmark set), the slice must state *which shapes relevant to this change the corpus does not contain* before the delta is read as a pass. Any shape named there is covered by a fixture, or the delta is recorded as **silent about it**. A zero delta over a corpus lacking the shape reads as the strongest possible evidence and is, in the limit, none — and it is most dangerous precisely where it is most attractive, on a change whose risk register names a forbidden direction.

2. **Mechanical gate** — dispatch the `test-runner` agent to run the slice's **oracle test**. It must pass — where "pass" is read from jest's own summary line, **never from a piped command's exit code** (`… | tail` reports `tail`'s status, not jest's, so a red run surfaces as exit 0). A run with no parsed `Tests:` summary is **inconclusive** — treat it as non-runnable, not a pass. Three ways this gate fails, all surfaced not swallowed:
   - **non-runnable** oracle (won't compile/collect) is not a pass;
   - **always-green** oracle — the executor reported no credible RED before implementing (or claims it was red but the failure reads as a missing import / wrong path rather than absent behavior). A test that never failed proves nothing; treat as a fail and re-dispatch the executor to fix the oracle, not the code;
   - **red after implementing** — the obvious fail.

3. **Judgment gate** — dispatch the `scope-check` agent and the `verifier` agent **concurrently**, in one message. `scope-check` (sonnet) runs the mechanical half — scope guard, escape-hatch grep, test-deletion diff — and returns a findings list. The `verifier` (opus) reads `${CLAUDE_PROJECT_DIR}/.claude/rules`, checks the slice's `gates` + the repo's invariants, does the falsification pass, and returns PASS / RETRY / ESCALATE.

   **Feed `scope-check`'s report into the verifier's prompt when it lands first; otherwise adjudicate it yourself against the verdict.** The split exists because those checks are grep-shaped and need no judgment — but a `scope-check` finding the verifier never saw is not resolved by having been produced. A CONTAMINATED scope guard blocks the commit on its own, whatever the verifier returned.

   **Route the executor's self-flagged deviations verbatim into the verifier's prompt**, as a named section: *"the executor flagged these as judgment calls it was unsure about — adjudicate each explicitly."* Require a per-item verdict; a flagged item the verifier does not mention is an incomplete verification, not an implicit pass. The rationale is worth stating because it is not obvious: **a green oracle is evidence that the code matches the test, never that the test matches the design.** RED→GREEN rules out a *vacuous* test; it does not rule out a *wrong* one, and a wrong-but-discriminating test is the most expensive artifact a slice can produce — it entrenches the defect behind a `describe` block the next reader treats as settled. The executor has already done the hard part by noticing; the signal is free, and is otherwise discarded at this exact step boundary.

   Where the design was **silent** on a seam the executor had to fill, that is a deviation too — the adjacent stated rule is what gets reused there, and adjacent seams frequently want opposite answers.

   **Resolve the slice's artifact to the runner that collects it — the prior question to "does the oracle pass?" is "does anything see the subject?"** Two ways the answer is no, and neither goes red:

   - **Nothing collects it.** When a slice adds a new artifact *kind* — a new plugin, a new hook, a new script directory — check the runner's actual glob or hardcoded path list, not "there is a test suite for this kind of thing". If nothing collects it the slice is **not done**: ship the oracle and wire it into CI in the same PR. From inside a slice a green gate table looks exactly like coverage ([EVIDENCE.md](../EVIDENCE.md) §1, *it never ran*) — one new plugin with two hooks passed all nine of a repo's gates without a single line of it executing.
   - **Something counts it and is blind to the slice.** Composition roots, operations, grants, deployment units, registry nodes — the tests that pin those counts glob the tree and import nothing, so the slice's own tests and any related-tests sweep are blind to them by construction, and a slice lands **red at HEAD** for the next slice (or a sibling lane) to discover. The ratchet moves **in the same commit** as the counted surface.

   **Out-of-oracle ripple check (mandatory when the slice changes a wire contract).** The per-slice oracle only covers the slice's own path — it structurally cannot see a suite that lives outside the default test run. When a slice changes an **exported artifact's signature**, an **event/trigger name**, or **deletes a symbol / route / field**, the executor (and verifier) must `grep` callers across the **whole repo including `*.integration.test.ts`, `*.e2e.*`, and fixture files that are excluded from the default `yarn test` run** (they need `jest.integration.config.js` / testcontainers, so they never go red locally). Then either **run the affected suites** via the integration config, or **explicitly flag them as un-run** in the slice summary — never imply "green" for suites the gate structurally cannot see. (Real miss: TV1-1969 changed a dispatcher's trigger event; three pre-existing integration suites still encoded the old topology and were red at HEAD, but none were in `yarn test`, so the dual gate never saw them.)

   **To undo an edit you made for a probe, keep a copy first — `cp <file> "$TMPDIR/keep"`, then `cp` it back. Never `git checkout`/`restore` a path.** The slice is **uncommitted for this entire window** — executor, test, scope-check, verifier and every retry — so `git checkout <path>` does not undo your one-line mutation; it makes the file identical to HEAD, and an uncommitted slice is precisely that difference. The prohibition in Step 4 is read *after* the gates; the temptation occurs *here*, mid-gate, cleaning up a probe, where the command reads as scoped and surgical. It has fired: a suite went 77 → 68 and was recovered only from a verifier's scratch rsync copy, by luck. Concurrent sessions in one checkout are the sibling case — before acting, check whose tree this is (`git status`, `git branch --show-current`), because another session cutting branches across it destroys untracked work with no warning of any kind.

4. **Resolve:**
   - **test green AND verifier PASS** → **commit the slice** (Step 4).
   - **RETRY or test fail** → re-dispatch the `executor` with the specific feedback. **Max 2 retries**, then ESCALATE. Re-dispatch on `opus` if the first pass ran on `sonnet` — a retry is the evidence that slice was mis-routed.
   - **Every retry is classified, in one line, before it is dispatched.** A second executor pass is the single most expensive event in this loop — it re-pays a whole context — so the rate is worth driving down, and it cannot be driven down without knowing which of these it was: `oracle-wrong` (the test encoded the wrong rule) · `design-silent` (the slice under-specified a seam the executor had to guess) · `ripple` (something outside the slice's surface broke) · `invariant` (the repo rule was not followed) · `mis-routed` (too cheap a model) · `flake` (environment, not the slice). Carry the tally into the Step 5 summary and the PR body. **Retry *rate* is already measured** — `/run-report` prints first-pass green per `/build` invocation — but the rate alone names no fix; the classification is what turns 43%-not-green into a change to `/plan` or to a slice's `gates`.
   - **ESCALATE** → stop this slice and surface it to the user (do not silently proceed). Independent already-committed slices stay committed. **In a pool, read "committed" as *landed*:** a slice committed in its worktree but not landed is on no branch, and an escalated slice's worktree takes no further slice until teardown (Step 2).

## Step 4 — Commit the slice

When a slice passes both gates:

1. **Scope check** — `git status --short`; the changed/deleted tracked files must match the slice's intended outputs (+ expected generated artifacts, including anything step 0's scaffold wrote — those are in scope for this slice by construction, and a scaffolded file left *unfilled* is the finding, not a scope violation). Any out-of-scope change → stop and surface it (do **not** commit through contamination). Never use `git stash`/`reset --hard`/`checkout --`/`restore`/`clean` to "clean up" — the stash stack is repo-global.
2. **Commit** only the slice's files. Compose the message following the **host repo's commit convention** — use its `/commit` command's format if it has one (typically `type(scope): summary` in the imperative, plus the ticket reference and any required trailer/sign-off). Identify the slice so the per-slice history stays legible, e.g.:
   ```
   feat(<scope>): <slice behavior, imperative, lowercase>

   Slice <id> of <work_item> — <slice name>. Oracle: <the test>.
   <ticket line + trailer per the repo's convention>
   ```
   One slice = **one commit** — do not re-group across slices the way a bulk `/commit` would.
3. **Set `passes: true` for that slice in `.work/slices.yaml`, in the same turn as the commit** — and, when running under a fleet, append the commit sha to the unit's state file in the same breath. **The flag is the resume point.** A resumed agent decides what to redo from it, so a committed slice left `passes: false` gets **re-executed** — including the subtle reversals that cost the most to get right the first time. This is not bookkeeping and it is not hypothetical: a transport error has killed four lanes in the same second, and one lane sat on six committed slices with a state file reading `slicesDone: 1`.

   **In a pool, this happens at the land, with the landed sha** — never at the worker's commit, which is on no branch yet: set `passes: true` when `worktree-pool land` reads `outcome=landed` (Step 2), and append the verdict's `sha=`, not the worker's, to a fleet's state file.

   Then **re-read the file.** Do not infer the edit's effect from the edit's own success output — a fix-up regex that matched nothing on an indentation mismatch still printed success.
4. **Append the slice's decisions to `decisions.md` and commit them, in the same turn** — see *The committed record*. A slice with none appends nothing and makes no record commit.

One slice commit per slice (the record's `docs(record)` commits are separate). Git is the record — per-slice commits are **crash insurance**, not tidiness, and batching three slices before committing turns any transport blip into total-progress loss. Of the signals a resumed run reads, the commits are the only one that cannot go stale, because writing them *is* the work.

## The committed record — `decisions.md` and `build-summary.md`

`/build` leaves two committed files in the folder Step 1 resolved with `work-docs-path --item <work_item>`: `<path>/decisions.md`, the post-design decisions, and `<path>/build-summary.md`, the run's telemetry. `.work/slices.yaml` stays working state — the plan and its `passes` flags, gitignored and never committed.

**The orchestrator is the single writer of `decisions.md` and `build-summary.md`** — Step 2's *Workers never write the record* rule, extended from `slices.yaml` to both files. Executors, verifiers and pool workers never write `decisions.md` or `build-summary.md`: they **report** each decision and fact in their result, and you write it in the main tree. In a pool this is not style — every worker appending to one file would make every cherry-pick conflict.

**`decisions.md` — every decision made after the design.** A deviation from the design, a seam the design was silent on that someone had to fill, a premise that proved false, a finding knowingly shipped, a verifier or gate finding overruled, a waiver: each is one entry. Take them from the executor's flagged deviations, the verifier's per-item verdicts and carried findings, your own retry classifications (`design-silent` names a filled seam) and every human decision on an ESCALATE. The header is fixed, so entries can be counted by `kind` across work items:

```markdown
## D1 — <one-line decision>
kind: silent-seam        # false-premise | silent-seam | deviation | shipped-finding | overruled | waiver
step: build · slice: 2 · decidedBy: executor    # executor | verifier | orchestrator | lane | human
sources: [code:<symbol> (<file>), adr:ADR-NNN, design:<section>, xp:<atom-id>, human]
rejected: <option> — <why not>
supersedes: —            # set when this overturns an earlier entry
<prose: why>
```

- **`sources` records what was consulted** to decide — code, ADRs, design sections, experience atoms, a human. There is **no confidence field**, and none is to be added: a self-rated confidence is uncalibrated and not comparable across models. How good a decision was is measured by outcome — a later entry that `supersedes` it.
- `slice:` is the slice id, or `—` for a decision about the plan as a whole. `rejected:` names the options not taken, or `—` when there were none. `supersedes:` is `—`, or the earlier id(s) this entry overturns (`D3` or `D3, D5`). The log is **append-only**: an overturned entry is never edited or deleted.
- **You allocate the ids**: the next id is one more than the highest in the file, read from the file at the moment you append — so a resumed run continues the sequence instead of restarting it.
- **When**: append a slice's entries right after its Step 4 commit — in a pool, right after its land — and commit `decisions.md` on its own (`docs(record): …`, not folded into the slice's commit), in the same turn. An ESCALATE's human decision is appended when the human decides. The record commit comes before the next land, because a tracked modification in the main checkout refuses a land (`reason=main-checkout-dirty`).

**`build-summary.md`** — written when `/build` ends, green **or partial**. Before Step 6's line, on every outcome — `success`, `gate-red`, and a `blocked-on` that comes after any slice ran — write its frontmatter and a short prose section, and commit it. The frontmatter keys are spelled `work_item:`, not `workItem:`, as `.work/mode.yaml` and the design's ownership header spell them:

```markdown
---
work_item: <work_item, as .work/mode.yaml records it>
plugin: bett3r-ai-workflow@<version>+<sha>
base: <sha the task branch was cut from>
slices:
  - id: 1
    name: <slice name>
    origin: plan                     # plan | verify-build (fix slice)
    mode: sequential                 # sequential | worktree | null
    commit: <landed sha>             # null when it did not land, or when its landed sha cannot be proven
    passed: true
    attempts: 1                      # executor passes; 0 = never started; 1 = first-pass green; null = passed in an earlier session with no record of it
    retries: []                      # classified, per Step 3 "Every retry is classified"; null = passed in an earlier session with no record of it
    verifier: pass                   # the final verdict: pass | retry | escalate; null = no verifier ran
    redBeforeGreen: true             # true | mutation | null
    postDesignDecisions: [D1]        # ids into decisions.md; [] = explicitly none
---
## What shipped
<short prose: outcome, measured root causes, what a future agent should know>
```

- **Zero decisions for a slice is written `postDesignDecisions: []`**, never an absent key — a missing key cannot be told apart from a slice nobody recorded.
- **Every slice in `.work/slices.yaml` gets an entry**, in plan order: a slice missing from the list reads the same as a slice that was never planned. A slice no run has started is `mode: null`, `commit: null`, `passed: false`, `attempts: 0`, `retries: []`, `verifier: null`, `redBeforeGreen: null`, and `postDesignDecisions:` the ids `decisions.md` records for that slice — usually `[]` (a plan-step entry can carry a slice id).
- **In every entry, `id` and `name` come from `.work/slices.yaml` and are never `null`; `origin` is the slice's own `origin:` field in `.work/slices.yaml`, else `plan`** — a slice is in that file because `/plan` or a fix step put it there, so its origin is never unknown.
- **Read the existing `build-summary.md` before writing.** A slice this run did not run keeps its existing entry from `build-summary.md` verbatim only when that entry's `passed` matches the slice's `passes:` flag in `.work/slices.yaml`. An entry that disagrees with the flag is stale — a later session landed the slice and died before Step 6, or a human landed it after an ESCALATE — and is rewritten from the flag: a `passes: true` slice as below, a `passes: false` one keeps its entry with `passed: false` and `commit: null`. Only a slice this run ran gets a new entry from this run's own dispatches. A slice an earlier session passed, with no prior entry or a stale one, gets `commit:`, `passed: true` and `postDesignDecisions:` from `decisions.md`, besides `id`, `name` and `origin`; `mode`, `attempts`, `retries`, `verifier` and `redBeforeGreen` are `null` — never a guessed value.
- **Finding that slice's `commit:`.** Take the landed sha `.work/slices.yaml` records for it (Step 2, for a pool slice); else the one commit that `git log --format=%H -E --grep '^Slice <id> of <work_item> ' <base>..HEAD` finds (`<base>` is the frontmatter's `base:`) — Step 4's message line, anchored at the line start and ended by a space so `XL-2` never matches `XL-27`, ranged so no other work item's history is searched, and never carried by a `docs(record)` commit. If neither yields exactly one commit, write `commit: null` and name the slice and the reason in `## What shipped`; never pick one. So `passed: true` with `commit: null` is legal: the flag says the slice landed, and the record says its commit could not be proven.
- `commit:` is the **landed** sha (Step 2). A slice this run ran that did not land is `passed: false`, `commit: null`, with its last verifier verdict.
- `mode:` is `worktree` for a slice run in the pool, `sequential` for one run in the main tree.
- **The `usage` blocks and the `verifyBuild` block are not written here** — they are generated later by `/verify-build`, from `run-metrics`, because an agent cannot see its own usage. When `/build` runs again on a branch whose `build-summary.md` already has them, rewrite only the keys above and leave those blocks untouched.

## Step 5 — Done

When all targeted slices are `passes: true` and committed, report: slices completed, the commit per slice, the **model each slice ran on**, the **retry tally by cause**, any **design elements the scaffolder blocked on** (these are open design questions, not build noise — they outlive the run), and any ESCALATEd items, **plus any out-of-`yarn test` suites flagged as un-run** (from the ripple check in Step 3).

**Verify the carry-forward against HEAD before handing it to `/verify-build` — do not assert it from memory.** The summary's carry-forward note (which file rippled, which suite went red) is what `/verify-build`'s signature-ripple sweep builds on; a wrong file named there can hide real breakages. Re-check every named file against `HEAD` (it is actually the red/affected one) before writing it. (Real miss: TV1-1969's summary named only one of three broken suites and mis-attributed it — the real recovery-semantics break was in a different file.) Then:

> Run `/verify-build` for the whole-PR coherence review and to open the PR.

## Step 6 — Report the outcome

**First write and commit `build-summary.md`** (*The committed record*), whatever the outcome, unless the run stopped before any slice ran (a Step 1 `work-docs-path` error, a Step 2 `size` error).

End your output with this line, at column 0, as the **final** line — nothing after it, not even a closing remark, and no trailing punctuation (`success.` is a value in no vocabulary, and a step that punctuates its marker reports no verdict at all):

    LANE-STEP:v1 step=build outcome=<success|gate-red|blocked-on> slices=<done>/<total> commits=<n>

`success` only when every targeted slice is `passes: true` **and** committed. `gate-red` when a slice exhausted its retries or a gate stayed red — `2/3` committed is a **partial lane, not a failed one**, so report the counts and let the caller decide. `blocked-on` for an ESCALATE that needs a human. Take `slices=` and `commits=` from the committed shas, not from memory; `commits=` counts slice commits, not the record's `docs(record)` commits. **Immediately before printing it**, run `lane-step-record '<the identical line>'`: it commits the verdict to your branch when `.work/lane.yaml` carries `verdictOnBranch: true` and does nothing otherwise; a non-zero exit is reported in your prose, never by changing the line. Never emit `infra` — its signal is the line's absence. The format contract is stated once in [unit-lane](../agents/unit-lane.md); do not restate it here.

## Principles

- Dispatch to agents; don't implement. Each agent gets a fresh context. **Name a model on every dispatch** — an unnamed one is the session's, the most expensive available.
- **Generate what is derivable; reserve judgment for what isn't.** Where a design graph fixes an artifact's identity, wiring and placement, deriving them mechanically is not a shortcut — it is what makes the design *converge*, because a hand-written artifact that drifts by one word in a label reads back as a different element and the board reports a phantom forever. What a graph cannot carry — payloads, invariants, handler bodies — is never guessed at.
- **Context length is the bill, not thinking depth.** On a measured fleet run, cache reads were **97% of raw tokens** and 68% of the cost-weighted total; output was 11%. What makes a run expensive is how much context each turn re-sends, so the levers that matter are: keep command output out of agent contexts (redirect + `tail`), keep agent lifetimes short, and don't retry. Speeding up the repo's own commands is *not* one of them — build/test/typecheck/generate/lint together were 12% of agent active time.
- **Both gates, every slice; RED before GREEN.** Never commit on the test alone, never drop the verifier to save tokens, and **where no RED is available, mutation is the substitute, not an exemption.**
- **Never end a turn awaiting a gate.** A backgrounded Bash job's completion re-invokes the main loop, never a subagent, so a unit agent that ends its turn awaiting one deadlocks permanently. A gate that can approach the 600 s ceiling runs **detached with a sentinel and is polled from foreground calls** (`full-gate` → *Reading the verdict*); never pipe a gate, and never read a wrapper's exit code as its verdict.
- **An env-gated oracle records its exact invocation** (flag + services) in the slice, so `/verify-build` can re-run it without archaeology. A slice whose oracle is excluded from the default run cannot be certified by its `passes:` flag — that flag records the run that skipped it.
- The tracer bullet goes first — if its seam doesn't hold, stop before building on it.
- The facts these gates rest on are stated once in [EVIDENCE.md](../EVIDENCE.md).
- The commits and the `passes` flags are the progress — there is no `build-progress.md`. `decisions.md` and `build-summary.md` are the committed record, written by the orchestrator alone. `.work/slices.yaml` stays working state in `.work/`.
