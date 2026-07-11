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

## Step 3 — Per slice: the dual gate

For each slice, in order, in a **fresh agent context**:

1. **Implement** — dispatch the `executor` agent with: the slice (`behavior`, `oracle`, `gates`, intended files), the ticket, and the host project directory. The executor reads the repo's own rules/skills. Instruct it to work **RED → GREEN**: write the oracle test first, **run it and confirm it FAILS** for the right reason (the behavior is genuinely absent — not a typo, missing import, or compile error), *then* implement the minimal code to make it pass. It must report the RED evidence (the failure it saw before implementing).

2. **Mechanical gate** — dispatch the `test-runner` agent to run the slice's **oracle test**. It must pass. Three ways this gate fails, all surfaced not swallowed:
   - **non-runnable** oracle (won't compile/collect) is not a pass;
   - **always-green** oracle — the executor reported no credible RED before implementing (or claims it was red but the failure reads as a missing import / wrong path rather than absent behavior). A test that never failed proves nothing; treat as a fail and re-dispatch the executor to fix the oracle, not the code;
   - **red after implementing** — the obvious fail.

3. **Judgment gate** — dispatch the `verifier` agent. It reads `${CLAUDE_PROJECT_DIR}/.claude/rules`, checks the slice's `gates` + the repo's invariants + the scope guard, and returns PASS / RETRY / ESCALATE.

   **Out-of-oracle ripple check (mandatory when the slice changes a wire contract).** The per-slice oracle only covers the slice's own path — it structurally cannot see a suite that lives outside the default test run. When a slice changes an **exported artifact's signature**, an **event/trigger name**, or **deletes a symbol / route / field**, the executor (and verifier) must `grep` callers across the **whole repo including `*.integration.test.ts`, `*.e2e.*`, and fixture files that are excluded from the default `yarn test` run** (they need `jest.integration.config.js` / testcontainers, so they never go red locally). Then either **run the affected suites** via the integration config, or **explicitly flag them as un-run** in the slice summary — never imply "green" for suites the gate structurally cannot see. (Real miss: TV1-1969 changed a dispatcher's trigger event; three pre-existing integration suites still encoded the old topology and were red at HEAD, but none were in `yarn test`, so the dual gate never saw them.)

4. **Resolve:**
   - **test green AND verifier PASS** → **commit the slice** (Step 4).
   - **RETRY or test fail** → re-dispatch the `executor` with the specific feedback. **Max 2 retries**, then ESCALATE.
   - **ESCALATE** → stop this slice and surface it to the user (do not silently proceed). Independent already-committed slices stay committed.

## Step 4 — Commit the slice

When a slice passes both gates:

1. **Scope check** — `git status --short`; the changed/deleted tracked files must match the slice's intended outputs (+ expected generated artifacts). Any out-of-scope change → stop and surface it (do **not** commit through contamination). Never use `git stash`/`reset --hard`/`checkout --`/`restore`/`clean` to "clean up" — the stash stack is repo-global.
2. **Commit** only the slice's files. Compose the message following the **host repo's commit convention** — use its `/commit` command's format if it has one (typically `type(scope): summary` in the imperative, plus the ticket reference and any required trailer/sign-off). Identify the slice so the per-slice history stays legible, e.g.:
   ```
   feat(<scope>): <slice behavior, imperative, lowercase>

   Slice <id> of <TICKET-ID> — <slice name>. Oracle: <the test>.
   <ticket line + trailer per the repo's convention>
   ```
   One slice = **one commit** — do not re-group across slices the way a bulk `/commit` would.
3. Set `passes: true` for that slice in `.work/slices.yaml`.

One commit per slice. Git is the record.

## Step 5 — Done

When all targeted slices are `passes: true` and committed, report: slices completed, the commit per slice, and any ESCALATEd items, **plus any out-of-`yarn test` suites flagged as un-run** (from the ripple check in Step 3).

**Verify the carry-forward against HEAD before handing it to `/verify-build` — do not assert it from memory.** The summary's carry-forward note (which file rippled, which suite went red) is what `/verify-build`'s signature-ripple sweep builds on; a wrong file named there can hide real breakages. Re-check every named file against `HEAD` (it is actually the red/affected one) before writing it. (Real miss: TV1-1969's summary named only one of three broken suites and mis-attributed it — the real recovery-semantics break was in a different file.) Then:

> Run `/verify-build` for the whole-PR coherence review and to open the PR.

## Principles

- Dispatch to agents; don't implement. Each agent gets a fresh context.
- **Both gates, every slice.** Never commit on the test alone — the verifier catches what tests can't. Never drop the verifier to save tokens; that's the corner that ships defects.
- **RED before GREEN.** A green oracle only means something if it was first seen RED for the right reason. An oracle that never failed could be asserting nothing — it's a tautology, not a proof. The executor writes the test, watches it fail, then makes it pass.
- The tracer bullet goes first — if its seam doesn't hold, stop before building on it.
- No `build-progress.md`, no `build-summary.md`. The commits and `passes` flags are the truth.
