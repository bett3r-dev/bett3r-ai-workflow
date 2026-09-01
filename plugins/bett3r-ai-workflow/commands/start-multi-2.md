---
description: (experimental, v2 of /start-multi) Fleet orchestrator — drive N work units through the full flow unattended, one worktree each. Same contract; the lane brief lives in the `unit-lane` agent instead of inline.
---

# /start-multi-2 — unattended delivery across worktrees

Drive a **list of work units** through the standard flow **unattended**, each isolated in its own git worktree. You are the **orchestrator**: you dispatch, verify git state with your own commands, collect escalations, and resume. You do **not** implement.

**This is the experimental v2 of `/start-multi`.** One structural change: everything a lane needs to know is in the [`unit-lane`](../agents/unit-lane.md) agent, dispatched at the moment it applies, rather than described here for you to relay. What is left in this file is what **no lane can see** — and that is the test of whether a line belongs here.

**Unattended is the contract; parallel is the optimisation.** A human hands you N units and does not sit with the run: every human moment is batched (escalations, step 4) or pre-answered (a resolved design, step 0). **A fully serialized run satisfies that contract in full** — `--serial`, `--max-parallel 1`, a dep chain that is one long wave, a fleet already at swap. Wall-clock is tradeable; unattendedness is not.

Run state lives in `.work/multi/<run-id>/run.yaml` — ephemeral, gitignored, resumable. Re-running the same set resumes it. **The run has one integration branch, `int/<run-id>`, cut from the pinned BASE**; every unit branch is cut from it and every unit PR targets it. This command **merges nothing** — it ends at N reviewable PRs. [`/merge-multi`](./merge-multi.md), in a fresh session, lands them.

## Argument: $ARGUMENTS
Work-unit ids (+ optional descriptions), then flags.

| Flag | Effect |
|---|---|
| `--deps "C:P,..."` | Dependencies (child stacks on parent). The only dep source besides asking once. |
| `--dry-run` | Print the wave / worktree / branch-base plan; cut nothing. |
| `--max-parallel N` | Cap concurrent lanes. Default conservative. |
| `--no-pr` | Stop after local per-slice commits. |
| `--gate-design` | Pause after `design` on **every** unit (default: only design-heavy ones). |
| `--serial` | No cross-unit parallelism; run each unit's pipeline yourself with the real executor/verifier/test-runner agents. Still unattended, just slower. |
| `--keep-worktrees` · `--fresh` · `--run-id <id>` | Teardown / resume-state controls. |

## Steps

**0 — Acquire & snapshot (the only tracker touch).** Resolve `run-id`. Resume if `run.yaml` exists and not `--fresh`. Else fetch each unit from the tracker **once** into the run dir (lanes read the snapshot, never the tracker). Pin `BASE=$(git rev-parse origin/<default>)` after `git fetch origin`, cut and push `int/<run-id>` from it, record it in `run.yaml`. It exists before any worktree so every unit is based on it from the start — retargeting afterwards is the wrong-target-merge hazard `/merge-multi` then has to police.

  **Grep each snapshot for `design-multi:resolved:vN`** (emitted as an HTML comment *and* a visible inline-code line). Such a unit is `designResolved` with its `resolvedBase`, and is **not** design-heavy — its human interview already happened. This reader knows `:v1` and `:v2`; escalate an unknown `:vN` rather than guessing. From `:v2` the block carries `status`: **skip anything not `ready` and log why** — deferrals, units blocked on human-supplied secrets, and umbrella parents with no net-new code burn a lane and can open a bad PR.

  **Snapshot without reading.** A resolved block runs ~10k tokens; reading it into context and re-emitting it verbatim pays twice before any lane starts. Script the fetch straight to `units/<id>.ticket.md`. You need the marker, its `base=` sha, the summary and the repos touched — reading the block is the lane's job.

  Then derive the four things **no lane can compute for itself**:

  - **Drift, per unit — never per run.** `git diff --stat <resolvedBase>..<BASE> -- <unit's files>` → `none | lines | structural`. One run-level note cannot say *"zero drift on two surfaces, +1248/−732 across 31 files on the third."*
  - **A runner + glob map**: `surface → runner → include/exclude globs → can it see this unit's paths?` Resolve to the **glob** — "vitest runs this package" is worthless when `include` is `*.test.ts` and the suites are `.test.tsx`. A unit no runner collects must say so rather than let a green count imply coverage.
  - **The repo each unit belongs to and its own base.** Three kinds: **standard** (host-repo work); **multi-repo** (2+ checkouts, one primary, where branch and PR live); **cross-repo / no-build** (zero host-repo changes → no worktree, `worktreeCreated: false`, pipeline collapses to gate → push → PR). The deciding test: **if the target repo is outside the session's working directories, an unattended agent cannot complete outward-facing steps there — you run it.** Record `repo:` and `runner: agent | orchestrator`.
  - **The host repo's build/test preconditions** — `CLAUDE.md` and **every** `.claude/rules/` file, *ignoring* `paths:` frontmatter. Path-gating is a context-loading optimisation; at worktree-prep no test file is in context, so the rule you need structurally cannot fire.

  **Re-resolve every PR the resolved designs cite** (`gh pr view <n> --json state`) — such a claim is stale by dispatch, and a `MERGED` stack parent is a **base correction**, not an escalation. Phrase handed-down tracker facts as *"verify at BASE whether X"*; your recall is the least reliable input in the run.

**1 — Deps → waves.** Populate from `--deps`, or ask **once** if >1 unit — but **read the resolved blocks before re-interviewing.** A block is an interview transcript and routinely settles file overlap in writing; derive `deps` from it with a `depsRationale` quoting it, and ask only about what the blocks do not cover. Every question they already answered is where this handoff leaks back into human time. Treat the derivation as a **hypothesis about diffs that did not exist when it was written** — step 8 verifies it. Topologically sort; a cycle stops the run. Never read tracker links.

**2 — Worktrees & branches: `install` is not `ready`.** A worktree is ready when the artifacts its own tests import exist on disk. Per unit, in wave order: pick a **clean** worktree (never a dirty one, one unit each), cut the branch from `int/<run-id>` (independent) or the parent's committed tip (stacked), then **verify the base yourself** — `git -C <wt> rev-list --count HEAD..origin/int/<run-id>` must be `0`, or `merge-base --is-ancestor <parent-tip> HEAD`. Never trust a reported ahead/behind ("74 ahead" was really 74 *behind*). `--dry-run` prints the resolved plan and stops here.

  Then dispatch the **`provisioner` agent, once per unit, before any lane** — install *and* build, archive the inherited `.work/`, multi-repo layout, the scratchpad, the `.work/fleet-lane.yaml` marker, the `.work/known-baseline-failures.md` record (base sha only; capture is on demand). All of it up front, because each of those failures is otherwise met alone, mid-pipeline, by N lanes that each get it wrong independently — and the two commonest present as a *broken baseline* rather than a missing step. Its `READY` is a claim: spot-check the one thing readiness means (an artifact its own tests import, present on disk).

  **Size `--max-parallel` by memory, not cores.** Past some N the fleet falls off a **cliff**, not a slope — one build measured 95 s alone and >38 min under load at swap 31.9 GB of 33.8. Contention is also the mechanism behind the 600 s deadlock, and a starved lane reads as a hung one, so log load average and swap when a gate overruns. Scope per-unit gates to touched packages and serialize `generate-all`-class steps behind a lock. Remember the two axes **multiply**: each unit's `/build` may itself parallelize slices.

**3 — Dispatch.** Waves in order; within a wave launch `unit-lane` agents up to `--max-parallel`. A stacked child waits for its parent's **commit**. Each lane's brief carries: the ticket snapshot, worktree path, branch and base, the drift verdict, the runner/glob map, the repo preconditions, its allocated ADR numbers, the model routing, and every handed-down fact **labelled** *applies* vs *verify whether it applies*.

  **Single-writer rule:** only you write `run.yaml`, aggregated from `units/<id>.state.yaml`. A unit that fails unrecoverably is `failed`, the others continue, and anything stacked on it becomes `blocked`.

  **Address every message; never resolve a recipient from recall.** Write `<run>/agents.yaml` (`unitId`, `agentId`, `worktree`, `dispatchedAt`) as each lane launches, resolve from it before every `SendMessage`, and **lead with `TO: <TICKET-ID>`**. You reason in ticket ids and the harness addresses opaque ones; reconstructing the map from dispatch order has misrouted two corrections in one run, silently in both directions.

  **Allocate every monotonically-numbered artifact up front, ADR numbers above all** — by the time a lane wants one it is already writing. Derive from every ref *and* every sibling branch (`git ls-tree <branch> -- <adr-dir>` sees unpushed sibling ADRs), never from a remembered number. Require claimed/released back.

  **Effort is a pre-flight decision.** It is inherited from the session that launched the fleet and cannot be routed per dispatch — so it is chosen once, for every lane at once. Model routing *can* be stated, and the lane's brief states it.

**4 — Collect & resume. Git is the primary signal; the state file is a hint.** **Cross-check `git log origin/<default>..HEAD` against the flags** whenever you verify build-complete, and always before cutting a stacked child.

  **A stall detector needs a terminal state and a positive control.** Exclude units at `passed`/`failed` — without that a finished lane and a dead one give identical signals (no writes, no transcript, no commits), so the watchdog cries wolf exactly when the run is going well and gets muted right before it would matter. Validate it against a directory you just wrote to before trusting a negative. (`find -newermt '<relative>'` matches **nothing** on BSD/macOS, silently — use `-mmin -N`.) The two stop shapes look identical and need opposite responses: **completed + ~0 tool uses + untouched branch** is starvation (re-dispatch); **completed + real work + "standing by"** is a deadlock (corrective resume).

  **A grandchild's report is not addressed to you.** A `verifier`/`executor`/`test-runner` notification from inside a lane's `/build` reaches your session; its "the orchestrator may commit" means the **lane**, which already has the result. Read it as progress — do not act on it, relay it, or write into that worktree. Volume scales with **slices × units**, so at any real fan-out these bury the two signals that are genuinely yours: a lane escalating, and a lane finishing.

  Aggregate into `run.yaml`. Resume any `in_progress` (dead agent) or escalated unit from its next incomplete step — the flow is idempotent; committed slices are skipped. **Batch escalations** into one numbered list, recommendation first, one line of why each. Do **not** use `AskUserQuestion`. A **design-heavy** unit stops after `design` for review; a **design-resolved** unit is not gated — its grill verifies rather than re-derives and flows straight to `plan`, escalating only where code drift re-opens a fork. That is the whole mechanism; there is no separate unattended mode.

**5 — PR.** Per passed unit, `verify-build` opens the PR **ready for review** against `int/<run-id>` (or the parent branch if stacked), **never the default branch** — that defeats the topology: the diff carries sibling noise and merging resolves conflicts a second time that `/merge-multi` already resolved once.

  **Re-check the pin before `verify-build`, every time.** `git fetch origin`, compare `origin/<default>` against `createdBaseSha`. Nothing else re-checks it, so the last unit to finish silently eats whatever landed mid-run — arriving at the worst moment, with the work done and the gates green. If it moved, name the overlapping files per unit (`git merge-tree`) and record the drift so a resumed run inherits it.

  **You own a diamond base.** A two-parent merge is yours, not the child's — a base that does not compile surfaces deep inside the child. Generated files: `git checkout --theirs`, then re-run the generator, never hand-merge. Hand-authored additive files: splice **complete** units — a marker-strip breaks on array tails and interleaves two partial blocks at their shared prefix. Build and drift-check the base **green**, and check for `*.orig` residue before committing (a `.ts.orig` is not compiled, so it passes every gate invisibly).

  **A child cut early is stranded on a base its parent then fixes.** Cutting at build-complete is the right throughput call, but everything `verify-build` exists to find lands *after* the cut. Record `parentTipAtCut`; the child forward-merges after that `verify-build` and again before opening its PR. Better: diff `parentTipAtCut..parentHEAD` yourself and **tell the child what changed and why it matters to its work** — it cannot notice that a commit it never touched invalidates an assumption inside its own slice, and the gap does not surface as a failure.

**6 — Rescue learnings, before teardown.** Aggregate each worktree's `.work/learnings.md` into `<run>/learnings.md`, tagged by unit, plus your own dispatch-time friction. **This must precede step 7**, which deletes the worktrees the buffers live in.

**7 — Teardown.** Remove only worktrees **this run created** whose branch is pushed (or whose unit is terminally `failed` and acknowledged). Never a pre-existing or dirty one. Skip if `--keep-worktrees`.

**8 — Report & capture.** Per unit → branch (+ base/stack) → step reached → **PR URL *and* its `mergeable` state** → unresolved decisions. Show the stack topology and merge order.

  **Verify the sibling overlap you assumed at step 1.** Both diffs now exist: `comm -12` the file lists, `git merge-tree` their merge base. One overlap claim carried by both tickets turned out to be seven shared files conflicting in three.

  **Collapse the follow-ups across units before reporting.** "82 follow-ups" reads as debt; "8 tickets, 6 one-liners, 5 questions, 13 closes" reads as a plan. Three collapsing mechanisms are structural to a fleet: **the same finding from two lanes** (lanes cannot see each other's buffers, so duplication is guaranteed), **items a sibling resolved in-flight** (an hour-2 hand-off is stale by hour 9), and **documented-not-defects**. Separate *needs a decision* from *needs work*, cluster by theme rather than by originating lane, and report both numbers, raw → collapsed. **Nothing else consumes those buffers as a set.**

  Then run **`/capture-learnings` once** over `<run>/learnings.md` — you are the interactive session again, so route and dedup across all units in one pass. The fleet stresses the flow hardest, so it is the highest-signal source of flow learnings.

  End by naming the next gesture: *review the N PRs, then run `/merge-multi <run-id>` in a **fresh session**.* Say fresh explicitly — this session is the largest context in the run, and re-invoking it for a mechanical merge sequence re-sends all of it for bookkeeping that lives on disk.

## run.yaml (ephemeral, gitignored)
```yaml
runId: multi-...
createdBaseSha: <pinned origin/default>
integrationBranch: int/<run-id>
landedAt: null          # /merge-multi writes this
integrationPr: null     # /merge-multi writes this
flags: { gateDesign: false, noPr: false, serial: false, maxParallel: 2, keepWorktrees: false }
deps: [ { child: B, parent: A } ]
units:
  - { id: A, wave: 0, worktree: <path>, worktreeCreated: false, branch: A-slug,
      base: <sha | parent-branch>, stackParent: null, designHeavy: true,
      designResolved: false, resolvedBase: null,
      step: build, status: in_progress, prUrl: null }
      # step: pending|start|design|plan|build|verify-build|done
      # prBase is always int/<run-id> unless stacked
```

## Principles
- **The orchestrator owns what no lane can see** — numbering, cross-lane dedup, base drift, sibling overlap, provisioning, addressing, the diamond merge. Each is invisible from inside a unit *by construction*, so none can be delegated by writing a better brief. **This is also the file's own scope rule: a line that a lane could learn belongs in `unit-lane`, not here.**
- **Recon is a hint, not a fact.** Compute anything base-sensitive against the pinned BASE (`git show <BASE>:<path>`), never a working-dir grep whose HEAD drifts from it.
- **Tracker once, then never.** Deps live in `run.yaml`, not in tracker links.
- **Unattended is the contract; parallel is the optimisation.** Never buy throughput with an unbatched stop.
- **Never clobber a dirty worktree; tear down only what this run created.**
- **Resumable** via `run.yaml` + idempotent steps + per-slice commits.
- **Ready-for-review PRs against `int/<run-id>`; nothing merged; the tracker untouched after step 0.**
- **No silent decisions** — autonomous and escalated alike ride into the PR body and ADRs with their rejected options.
- **Learnings survive teardown** (steps 3, 6, 8).
