---
description: Drive each vertical slice to green through the dual gate (executor → test → verifier) and commit it. The deterministic implementation loop.
---

# /build — drive the slices

Execute the slices in `.work/slices.yaml`, one at a time, each through the **dual gate**, committing each as it passes. You are the orchestrator: you **dispatch agents and commit** — you do not implement code yourself.

## Argument: $ARGUMENTS
Optional slice id(s) to run (e.g. `2` or `2,3`). Default: all `passes: false` slices.

---

## Step 1 — Load state

Read `.work/slices.yaml`. If it doesn't exist: "No slices found. Run `/plan` first."

The `passes` flags + the git history **are** the progress — there is no separate progress file. Skip any slice already `passes: true` (report "resuming").

## Step 2 — Order the slices

Order by `depends_on` (topological). The **tracer-bullet slice runs first**. Slices with no unmet `depends_on` are independent and *may* be run in parallel (dispatch their executors concurrently) — but commit them one at a time so each commit stays coherent. When unsure, go sequential.

## Model routing — every dispatch names its model

An agent that names no model inherits the session's, which is the most expensive one you have. **Name the model on every dispatch**, from this policy — the roles differ by more than an order of magnitude in what judgment they actually need:

| Dispatch | Model | Why |
|---|---|---|
| `executor` | the slice's `model:` field; **`opus` when absent** | `/plan` marks the mechanical slices (scaffold from a framework skill, config, a test-only slice) `sonnet`. Anything it left unmarked — the tracer bullet, a seam, anything touching an invariant — stays `opus`. |
| `test-runner` | `haiku` (its own frontmatter) | Runs a command, parses a summary line. No judgment. |
| `scope-check` | `sonnet` (its own frontmatter) | `git status`, greps, a diff read. Mechanical by construction. |
| `verifier` | `opus` — **never downgrade this one** | It is the only gate positioned to catch a confidently-wrong oracle, and cheapening it is the corner that ships defects. It is also ~11% of a run's cost, so there is nothing to win here. |
| read-only sweeps (`Explore`, `general-purpose`) | `sonnet` | Grep-shaped, disjoint, and adjudicated by you afterwards. |

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

   **If the slice's deliverable is a test or a guard** (no new production behavior, so no natural RED is available): **mutation-test it instead.** Revert or corrupt one production line at a time and report, per mutation, **which assertion failed, with what values, and which consumers the mutation reached** — a predicate claimed as single-source-of-truth must fail at least one test per declared consumer, and a shortfall is the finding, because a second inline copy of the rule is mutation-blind. A guard asserting an *absence* also ships a positive and a negative control, and pins its traversal if it walks a tree. Report the mutation table where RED evidence would go. This is not optional rigor: RED→GREEN is the anti-tautology gate, and for this slice type it is **structurally unavailable** — which is exactly the type whose entire value is "does this assertion actually bite?"

   Cheaper version, worth running on *any* new case: **apply the smallest mutation the case claims to catch and watch the suite stay green.** If it does, the fixture abbreviated away the thing under test. Say out loud when a case cannot be mutation-checked, rather than leaving it looking un-needled.

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

   **A slice that adds or removes a file of a kind something counts runs the census guards before its commit.** Composition roots, operations, grants, deployment units, registry nodes — the tests that pin those counts glob the tree and import nothing, so the slice's own tests and any related-tests sweep are blind to them by construction, and a slice lands **red at HEAD** for the next slice (or a sibling lane) to discover. The ratchet moves **in the same commit** as the counted surface.

   **Out-of-oracle ripple check (mandatory when the slice changes a wire contract).** The per-slice oracle only covers the slice's own path — it structurally cannot see a suite that lives outside the default test run. When a slice changes an **exported artifact's signature**, an **event/trigger name**, or **deletes a symbol / route / field**, the executor (and verifier) must `grep` callers across the **whole repo including `*.integration.test.ts`, `*.e2e.*`, and fixture files that are excluded from the default `yarn test` run** (they need `jest.integration.config.js` / testcontainers, so they never go red locally). Then either **run the affected suites** via the integration config, or **explicitly flag them as un-run** in the slice summary — never imply "green" for suites the gate structurally cannot see. (Real miss: TV1-1969 changed a dispatcher's trigger event; three pre-existing integration suites still encoded the old topology and were red at HEAD, but none were in `yarn test`, so the dual gate never saw them.)

4. **Resolve:**
   - **test green AND verifier PASS** → **commit the slice** (Step 4).
   - **RETRY or test fail** → re-dispatch the `executor` with the specific feedback. **Max 2 retries**, then ESCALATE. Re-dispatch on `opus` if the first pass ran on `sonnet` — a retry is the evidence that slice was mis-routed.
   - **Every retry is classified, in one line, before it is dispatched.** A second executor pass is the single most expensive event in this loop — it re-pays a whole context — so the rate is worth driving down, and it cannot be driven down without knowing which of these it was: `oracle-wrong` (the test encoded the wrong rule) · `design-silent` (the slice under-specified a seam the executor had to guess) · `ripple` (something outside the slice's surface broke) · `invariant` (the repo rule was not followed) · `mis-routed` (too cheap a model) · `flake` (environment, not the slice). Carry the tally into the Step 5 summary and the PR body. **Retry *rate* is already measured** — `/run-report` prints first-pass green per `/build` invocation — but the rate alone names no fix; the classification is what turns 43%-not-green into a change to `/plan` or to a slice's `gates`.
   - **ESCALATE** → stop this slice and surface it to the user (do not silently proceed). Independent already-committed slices stay committed.

## Step 4 — Commit the slice

When a slice passes both gates:

1. **Scope check** — `git status --short`; the changed/deleted tracked files must match the slice's intended outputs (+ expected generated artifacts, including anything step 0's scaffold wrote — those are in scope for this slice by construction, and a scaffolded file left *unfilled* is the finding, not a scope violation). Any out-of-scope change → stop and surface it (do **not** commit through contamination). Never use `git stash`/`reset --hard`/`checkout --`/`restore`/`clean` to "clean up" — the stash stack is repo-global.
2. **Commit** only the slice's files. Compose the message following the **host repo's commit convention** — use its `/commit` command's format if it has one (typically `type(scope): summary` in the imperative, plus the ticket reference and any required trailer/sign-off). Identify the slice so the per-slice history stays legible, e.g.:
   ```
   feat(<scope>): <slice behavior, imperative, lowercase>

   Slice <id> of <TICKET-ID> — <slice name>. Oracle: <the test>.
   <ticket line + trailer per the repo's convention>
   ```
   One slice = **one commit** — do not re-group across slices the way a bulk `/commit` would.
3. **Set `passes: true` for that slice in `.work/slices.yaml`, in the same turn as the commit** — and, when running under a fleet, append the commit sha to the unit's state file in the same breath. **The flag is the resume point.** A resumed agent decides what to redo from it, so a committed slice left `passes: false` gets **re-executed** — including the subtle reversals that cost the most to get right the first time. This is not bookkeeping and it is not hypothetical: a transport error has killed four lanes in the same second, and one lane sat on six committed slices with a state file reading `slicesDone: 1`.

   Then **re-read the file.** Do not infer the edit's effect from the edit's own success output — a fix-up regex that matched nothing on an indentation mismatch still printed success.

One commit per slice. Git is the record — per-slice commits are **crash insurance**, not tidiness, and batching three slices before committing turns any transport blip into total-progress loss. Of the signals a resumed run reads, the commits are the only one that cannot go stale, because writing them *is* the work.

## Step 5 — Done

When all targeted slices are `passes: true` and committed, report: slices completed, the commit per slice, the **model each slice ran on**, the **retry tally by cause**, any **design elements the scaffolder blocked on** (these are open design questions, not build noise — they outlive the run), and any ESCALATEd items, **plus any out-of-`yarn test` suites flagged as un-run** (from the ripple check in Step 3).

**Verify the carry-forward against HEAD before handing it to `/verify-build` — do not assert it from memory.** The summary's carry-forward note (which file rippled, which suite went red) is what `/verify-build`'s signature-ripple sweep builds on; a wrong file named there can hide real breakages. Re-check every named file against `HEAD` (it is actually the red/affected one) before writing it. (Real miss: TV1-1969's summary named only one of three broken suites and mis-attributed it — the real recovery-semantics break was in a different file.) Then:

> Run `/verify-build` for the whole-PR coherence review and to open the PR.

## Principles

- Dispatch to agents; don't implement. Each agent gets a fresh context. **Name a model on every dispatch** — an unnamed one is the session's, the most expensive available.
- **Generate what is derivable; reserve judgment for what isn't.** Where a design graph fixes an artifact's identity, wiring and placement, deriving them mechanically is not a shortcut — it is what makes the design *converge*, because a hand-written artifact that drifts by one word in a label reads back as a different element and the board reports a phantom forever. What a graph cannot carry — payloads, invariants, handler bodies — is never guessed at.
- **Context length is the bill, not thinking depth.** On a measured fleet run, cache reads were **97% of raw tokens** and 68% of the cost-weighted total; output was 11%. What makes a run expensive is how much context each turn re-sends, so the levers that matter are: keep command output out of agent contexts (redirect + `tail`), keep agent lifetimes short, and don't retry. Speeding up the repo's own commands is *not* one of them — build/test/typecheck/generate/lint together were 12% of agent active time.
- **Both gates, every slice; RED before GREEN.** Never commit on the test alone, never drop the verifier to save tokens, and **where no RED is available, mutation is the substitute, not an exemption.**
- **Never end a turn awaiting a gate.** A backgrounded Bash job's completion re-invokes the main loop, never a subagent, so a unit agent that ends its turn awaiting one deadlocks permanently. A gate that can approach the 600 s ceiling runs **detached with a sentinel and is polled from foreground calls** (`full-gate` → *Reading the verdict*); never pipe a gate, and never read a wrapper's exit code as its verdict.
- **An env-gated oracle records its exact invocation** (flag + services) in the slice, so `/verify-build` can re-run it without archaeology. A slice whose oracle is excluded from the default run cannot be certified by its `passes:` flag — that flag records the run that skipped it.
- The tracer bullet goes first — if its seam doesn't hold, stop before building on it.
- The facts these gates rest on are stated once in [EVIDENCE.md](../EVIDENCE.md).
- No `build-progress.md`, no `build-summary.md`. The commits and `passes` flags are the truth.
