---
description: Drive each slice in .work/slices.yaml to green through the dual gate (executor → test-runner → scope-check ∥ verifier) and commit it: the implementation loop of the pipeline.
---

# /build — drive the slices

This is the `build` step; its verdict is `LANE-STEP:v1 step=build outcome=<success|gate-red|blocked-on> slices=k/N commits=n`. You are the orchestrator: you dispatch agents, read their reports and commit. You write no code yourself.

**Argument** `$ARGUMENTS`: optional slice ids (`2` or `2,3`); the default is every `passes: false` slice. `--max-parallel N` caps how many slices run concurrently (Step 2).

## Step protocol

**Brief.** If `.work/lane.yaml` exists you are an unattended lane: take every input (`work_item`, `branch`, `worktree`, `runDir`, `gateDeferred`, `sliceBudget`, `mapProvenance`, `preconditions`, the rest) from it and ask no one anything. A fact it hands down is a claim to verify against the tree before you build on it. Without the file you run attended: inputs come from the user and the working tree.

**Mode marker.** Rewrite `.work/mode.yaml` whole: `mode: <this step>`, `work_item:` and `branch:` carried forward exactly as `/start` recorded them, `updated:` now. The file is replaced, not merged or appended; only `/start` clears it.

**Verdict.** Your last line is `LANE-STEP:v1 step=<this step> outcome=<success|gate-red|blocked-on>` with this step's attributes, at column 0 with nothing after it. Run `lane-step-record '<the identical line>'` immediately before printing it (it records the verdict on the branch when the brief opts in). Printing the line ends the run: take no turn after it.

## Step 1 — Load state

1. Mark the mode: `.work/mode.yaml` reads `mode: build` (*Step protocol*).
2. Read `.work/slices.yaml`. Absent: say "No slices found. Run `/plan` first." and end `blocked-on`. A slice already `passes: true` is skipped; say "resuming" when any is.
3. Resolve the record folder: `work-docs-path --item <work_item>`, the `work_item` taken from `.work/mode.yaml` untouched; read its last line, not its exit code (ADR-004). `outcome=ok` names `path=`, where `decisions.md` and `build-summary.md` live beside the committed `design.md`. `outcome=error`: report its `reason=` and end `blocked-on` before any slice runs. The folder is the script's answer; a record written anywhere else is one no reader finds.
4. From the brief, when there is one: `runners` (which command collects which test paths), `preconditions` (the install and build commands), `modelRouting`, `adrAllocations`, `sliceBudget` and `worktreePoolMax`. Say which of the two states you run under, briefed or attended.

Done when the mode marker is written and the slice list and record path are in hand, or the run has ended `blocked-on`.

## Step 2 — Order the slices and size the pool

Order by `depends_on`, topologically; the tracer bullet runs first. Then size the pool:

```
worktree-pool size .work/slices.yaml [--only <ids>] [--max-parallel N] [--pool-max N]
```

Pass `--only` with the ids from `$ARGUMENTS` on a targeted run; `--pool-max` only with the brief's `worktreePoolMax` (the venue writes it, you read it; no key means no cap); `--max-parallel` only when this invocation was given one. Redirect the output to a file and read its `WORKTREE-POOL:v1` line; the exit code is not the verdict.

- `outcome=ok pool=0`: every slice runs sequentially in the main tree, and each records why under `modeReason:` (`pool=0`, or `ready-alone` when it was the only slice ready at its moment).
- `outcome=ok pool>0`: slices ready at the same moment run concurrently, each in its own pool worktree. Follow [build-pool.md](../reference/build-pool.md) for provision, reset, land and teardown; each slice still runs the whole of Step 3, inside its worktree.
- `outcome=error`: stop before dispatching anything and report `reason=`. `dependency-cycle`, `unknown-dependency` and `unreadable-plan` are `/plan` defects; `unmet-dependency-outside-only` means a targeted slice's parent is neither passed nor targeted, so ask for the parent to be included.
- no `WORKTREE-POOL:v1` line: the call died before concluding, which is not a pass and is not reconstructed from git state; run every slice sequentially in the main tree (`modeReason: no-verdict-line`).

Done when every slice to run has an order and a mode, `sequential` or `worktree`.

## Step 3 — Per slice: the dual gate, then the commit

A slice's first pass runs in a fresh agent context; its fix rounds continue it (below).

0. **Scaffold**, only when the slice has `designs:` and the host's `.esas.config.json` declares `designTooling.scaffold`. Run that command from the checkout root with the slice's ids as `--nodes`, dry-run first, then write; when `designTooling.scaffoldSkill` names a skill, follow it for reading the output. In a lane the scaffolder reads the `provisioner`'s `.work/design-snapshot/` through `--design`/`--graph`. When the step cannot run, skip it and say which reason: no `designs:`, no `designTooling.scaffold` declared, no design layer or snapshot, or a snapshot whose `manifest.yaml` `sourceSha` is not this tree's base. Exit 3 is a block, and a block is a design finding (a node with no home, a policy issuing into two modules, a handler that does not exist yet): surface it to the user, or reorder the slices when it is an ordering defect; the refusal is the only signal that a decision is missing, so hand-writing past it discards it. Pass the scaffold report to the executor verbatim, its fragments and `STILL OWED` items included. Generated files are stubs, in scope for the slice; the oracle still goes RED first.

1. **Implement.** Dispatch the `executor` on the model *Model routing* names, with: the slice (`behavior`, `oracle`, `scenarios` verbatim with every field of every one, `seam` with its entry from the plan's top-level `seams:`, `probe`, `gates`, intended files), the ticket and the project directory. Its gate is RED → GREEN: the oracle fails by assertion before the code exists, then passes; the executor reports the RED evidence, the `probe:` result and the runner's own summary lines. A slice whose deliverable is a test or a guard has no RED, and the executor reports a mutation table in its place ([EVIDENCE.md](../EVIDENCE.md) §2). A slice whose premise proves false is reported as false with file, line and commit; the gate the premise protected then ships without the body where it still holds (a test, a ratchet, a census), and the slice claims only the gates it met.

2. **Mechanical gate.** Dispatch the `test-runner` on the slice's oracle; a fix round reads the executor's pasted summary instead. Pass is read from the runner's own summary line, as `full-gate` reads a verdict; a run with no `Tests:` line is inconclusive. Each of these is a fail, and the re-dispatch fixes the oracle, not the code:
   - non-runnable: the oracle does not compile or collect;
   - unasserted scenario: a `then:` from `scenarios:` is nowhere in the test; a `kind: structural` scenario stays unasserted until its negative half is asserted;
   - oracle below the seam: the test lives somewhere other than the slice's `seam:`; a seam that genuinely cannot observe the claim is escalated to the plan, not quietly lowered;
   - probe not red: the `probe:` mutation left the oracle green, was not run, or was reported without the line, the assertion that fired and the values;
   - undiscriminating: the RED was a hang, timeout, crash, import or compile error, empty collection or skipped suite;
   - recomputed expectation: the expected value is derived the way the implementation derives it instead of read from `expected_from:`/`expected_source:`;
   - always-green: no credible RED before implementing;
   - red after implementing.

3. **Judgment gate.** Dispatch `scope-check` and the `verifier` concurrently, in one message. Feed the executor's flagged deviations into the verifier's prompt verbatim, as a named section to adjudicate item by item; feed `scope-check`'s report in when it lands first, otherwise adjudicate it yourself against the verdict. A `CONTAMINATED` scope guard blocks the commit whatever the verifier returned. When the slice changes a wire contract (an exported signature, an event or trigger name, a deleted symbol, route or field), have the executor grep callers across the whole repo, suites outside the default run included, and report each affected suite as run or un-run; the verifier checks that list. A slice that adds an artifact kind (a plugin, a hook, a script directory) is resolved to the runner that collects it, and wires the runner in the same slice when none does; a slice that adds or removes a file a census or ratchet guard counts moves that census in the same commit.

4. **Resolve.**
   - Test green and verifier `PASS`: commit (item 5).
   - `RETRY` or test red: a fix round, at most 2, then `ESCALATE`. Classify every fix round in one line before dispatching it, from the closed set `oracle-wrong` (the test encoded the wrong rule) · `design-silent` (the executor had to guess a seam the design left open) · `ripple` (something outside the slice's surface broke) · `invariant` (a repo rule was not followed) · `mis-routed` (too cheap a model) · `flake` (timing or load: green idle, untouched by the diff). Carry the tally into the record and the verdict; a cause that keeps recurring is owed a disposition through `/capture-learnings`.
   - Not the slice's defect: an environment gap (an unbuilt sibling package, a missing credential, a sandbox refusal) is the verifier's `environment-gap: <cause>`; the slice may `PASS` on the evidence that ran, the gap recorded as `kind: shipped-finding`, and never when the gap is the slice's own oracle. A failure red on the base too (the `full-gate` baseline diff) is out of scope for the slice.
   - `ESCALATE`: stop this slice and surface it to the user; committed slices stay committed.

   **Fix rounds** hand the findings back instead of re-paying the gate. Snapshot the reviewed tree before the verifier's first dispatch and before each re-check, untracked files included, without touching the index:
   ```
   i="${TMPDIR:-/tmp}/slice-<id>.idx"; GIT_INDEX_FILE="$i" git read-tree HEAD && GIT_INDEX_FILE="$i" git add -A && GIT_INDEX_FILE="$i" git write-tree
   ```
   `git diff <previous> <new>` is the round's diff.
   - Executor: `SendMessage` the findings to the one that built the slice when you are the top-level session and the model does not change; otherwise dispatch a fresh one with the slice, the findings verbatim, the round's diff and its own previous report. Record `continued` or `fresh`.
   - Test gate: the executor's pasted summary; re-dispatch the `test-runner` only when the round edited the oracle or the report carries no `Tests:` line.
   - `scope-check`: only when `git diff --name-only <previous> <new>` names a file outside the slice's intended files, or any test file.
   - Verifier: [re-check mode](../agents/verifier.md), continued under the executor's conditions, else fresh; either way with its previous findings, the round's diff and the executor's per-finding response. It stays `opus`.

5. **Commit.** `git status --short`: the changed and deleted tracked files match the slice's intended outputs plus expected generated artifacts (a scaffolded file left unfilled is a finding, not contamination); anything else stops the commit and is surfaced. Commit only the slice's files, in the host repo's convention, with the slice line in the body:
   ```
   feat(<scope>): <slice behavior, imperative, lowercase>

   Slice <id> of <work_item> — <slice name>. Oracle: <the test>.
   <ticket line + trailer per the repo's convention>
   ```
   One slice, one commit. In the same turn set `passes: true` in `.work/slices.yaml` (a fleet lane also appends the sha to its state file) and re-read the file; the flag is the resume point. A `passes: true` on a slice whose oracle is excluded from the default run records the run that skipped it; that slice is certified by re-running the invocation its `oracle:` names, not by the flag. Then `git push`, every slice as it lands; a failed push is one line of prose and the slice stays green. The last commit of the whole step stays unpushed until the verdict is recorded (normally `build-summary.md`'s, so do not push before it): `lane-step-record` writes the verdict into it and pushes, and when the brief carries no `verdictOnBranch` you push it yourself after the line. Then append the slice's decisions ([build-record.md](../reference/build-record.md)) and commit them separately, in the same turn.

   **Yield.** Count the slices you committed in this invocation. When it reaches `sliceBudget` (the brief's value; no key means 3; `0` means no budget) or your own turn count passes ~100, whichever first, while slices remain: stop at this boundary, write the record (Step 4) and report `outcome=success` with the real counts. Yield between slices only, on committed slices only: a slice mid fix round is finished or escalated first, and a red slice is `gate-red`, a verdict rather than a budget stop. The caller dispatches `/build` again on a fresh context and it resumes from `passes: true`.

Done when the slice is committed with its flag set, or escalated, or its fix-round cap is spent.

## Step 4 — Write the record

Follow [build-record.md](../reference/build-record.md): `decisions.md` entries were appended as Step 3 went; `build-summary.md` is written and committed now, green or partial, unless the run stopped before any slice ran.

Done when `build-summary.md` carries an entry for every slice in `.work/slices.yaml` and is committed.

## Step 5 — Verdict

Report: slices completed with the commit per slice, the model each ran on, the fix-round tally by cause and how many rounds were continued, the design elements the scaffolder blocked on (open design questions that outlive the run), escalated items, and every suite the ripple check named as un-run. Verify each file the carry-forward note names against `HEAD` before writing it; `/verify-build`'s ripple sweep builds on it.

Then the verdict line (*Step protocol*):

    LANE-STEP:v1 step=build outcome=<success|gate-red|blocked-on> slices=<done>/<total> commits=<n>

`success`: every targeted slice is `passes: true` and committed, or you yielded with everything attempted committed and green (a yield is a `success` whose `slices=` is short of its total). `gate-red`: a slice exhausted its fix rounds or a gate stayed red; `2/3` is a partial lane, reported with its counts for the caller to decide on. `blocked-on`: an `ESCALATE` awaiting a human. Take `slices=` and `commits=` from the committed shas; `commits=` counts slice commits, not `docs(record)` commits. In a pool, committed means landed. `infra` is not a value you print; its signal is the line's absence.

> Run `/verify-build` for the whole-PR coherence review and to open the PR.

## Model routing

Name a model on every dispatch; an unnamed one inherits the session's, the most expensive available. This table is the routing's single home: `unit-lane`, `/plan` and `/verify-build` route as it does.

| Dispatch | Model |
|---|---|
| `executor` | the slice's `model:`; absent means `opus`. `/plan` marks mechanical slices `sonnet`; the tracer bullet, a seam and anything touching an invariant stay `opus`. |
| `test-runner` | `haiku` (its own frontmatter) |
| `scope-check` | `sonnet` (its own frontmatter) |
| `verifier` | `opus`, and never downgrade this one: it is the only gate positioned to catch a confidently wrong oracle |
| read-only sweeps (`Explore`, `general-purpose`) | `sonnet` |
| a fix round after a `sonnet` executor | `opus`: the fix round is the evidence the slice was mis-routed |

Every dispatch description names `slice <id>` (`slice 3 executor fix round 1`): `run-metrics` attributes a dispatch to its slice by that phrase alone. A continued agent keeps the description it was dispatched with, so a continued agent never takes another slice. Effort is a host setting, not a plugin rule.

**Waiting.** Wait in one blocking call: `Monitor` on the file or transcript the work writes, or a bounded `until <condition>; do sleep 10; done` inside a single foreground Bash call. A background `sleep` or a re-issued timer is a whole extra turn at full context. Printing your verdict line ends the run: take no turn after it.

## Boundaries

- You dispatch and commit; the executor writes the code. A slice you implement yourself has passed neither gate.
- Both gates, every slice. A commit on the test alone, or a verifier dropped to save cost, is how a green suite ships a wrong rule; where no RED exists, mutation is the substitute, not an exemption.
- A tool's verdict is its last line, read as `full-gate` reads a verdict, from the file you redirected it to.
- Undo a probe edit from a copy you kept (`cp <file> "$TMPDIR/keep"`, then `cp` it back). `git checkout`/`restore` on a path makes it identical to `HEAD`, and the uncommitted slice is exactly that difference; compare against a baseline with `git stash create` + `git diff <object>`, since a hook blocks the destructive forms in a lane.
- The record has one writer, you ([build-record.md](../reference/build-record.md)).
- The tracer bullet goes first, and a seam that does not hold stops the run before anything is built on it.
