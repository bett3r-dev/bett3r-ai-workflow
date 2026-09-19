---
description: Fleet orchestrator — drive N work units through the full flow unattended, one worktree each, ending at N reviewable PRs.
---

# /start-multi — unattended delivery across worktrees

Drive a **list of work units** through the standard flow **unattended**, each in its own git worktree. You are the **orchestrator**: you dispatch, verify git state with your own commands, collect escalations and resume; you implement nothing. Everything a lane needs is in the [`unit-lane`](../agents/unit-lane.md) agent and its `.work/lane.yaml` brief; this file holds what **no lane can see**, and that is the test of whether a line belongs here. Unattended is the contract and parallel the optimisation: every human moment is batched (step 4) or pre-answered by a resolved design (step 0), so a fully serialised run satisfies the contract in full.

Run state lives in `.work/multi/<run-id>/run.yaml`: ephemeral, gitignored, resumable, so re-running the same set resumes it. The run has one integration branch, `int/<run-id>`, cut from the pinned BASE; every unit branch is cut from it and every unit PR targets it. This command **merges nothing**: it ends at N reviewable PRs, and [`/merge-multi`](./merge-multi.md), in a fresh session, lands them.

## Argument: $ARGUMENTS

Work-unit ids (with optional descriptions), then flags.

| Flag | Effect |
|---|---|
| `--deps "C:P,..."` | Dependencies (child stacks on parent). The only dep source besides the resolved blocks and one question. |
| `--dry-run` | Print the wave / worktree / branch-base plan; cut nothing. |
| `--max-parallel N` | Cap concurrent lanes. Default conservative. |
| `--no-pr` | Stop after local per-slice commits. |
| `--gate-design` | Pause after `design` on **every** unit (default: only design-heavy ones). |
| `--serial` | No cross-unit parallelism: run each unit's pipeline yourself, from inside its worktree. Mechanics in [start-multi-serial.md](../reference/start-multi-serial.md), read only when `--serial` is set or step 3's tool probe fails. |
| `--keep-worktrees` · `--fresh` · `--run-id <id>` | Teardown / resume-state controls. |

## Steps

**0 — Acquire and snapshot (the only tracker touch).** Resolve `run-id` as `multi-<unit ids joined by ->`, prefix lower-case, ids as written (`multi-ESAS-93-94`): the shape `work-docs-path --item` accepts for the run-level folder `/merge-multi` writes (a unit id with an underscore gives a run id it refuses, so that run's conflict resolutions live in the integration PR body only). Resume when `run.yaml` exists and `--fresh` is absent. Otherwise fetch each unit from the tracker **once** into the run dir; lanes read the snapshot, not the tracker. `git fetch origin`, pin `BASE=$(git rev-parse origin/<default>)`, cut and push `int/<run-id>` from it, and record both in `run.yaml` before any worktree exists. Then run the host repo's gate on `int/<run-id>` once, as step 5 says, and record it as `baseGate`; every provisioner receives that verdict, so the fleet's deliberate reds are proved once, not once per lane.

Read each snapshot for the `design-multi:resolved:vN` marker, emitted twice (an HTML comment and an inline-code line, attributes identical) and matched by the marker's token regex rather than marker-then-heading adjacency, since the tracker round-trip inserts a blank line there. Such a unit is `designResolved` with its `resolvedBase` (`base=`) and is not design-heavy. This reader knows `:v1` and `:v2`; an unknown `:vN` is an escalation. From `:v2` the marker carries `status`: dispatch only `status=ready`, log every `deferred` / `blocked` / `umbrella` unit as skipped with its reason, treat `status=ready deps=<ID>` as ready with a required dep added to the graph, and escalate a status word outside those four as contract drift.

Snapshot from disk where you can: when the marker's `run=` names a `/design-multi` run whose dir exists (`.work/design-multi/<run>/units/`), copy `<id>.ticket.md` + `<id>.ticket-block.md` (and `NEW-*.ticket-body.md` for a commissioned ticket) from there and check marker and `base=` against one cheap tracker field. Only when the dir is absent fetch through a subagent, then verify every snapshot: grep for `truncated` / `[...]` / `elided` and assert the file ends with the block's terminal section, because a truncated file reads exactly like a complete short ticket. A failed check is a re-fetch.

Then derive, per unit, the four things no lane can compute for itself:

- **Drift**: `git diff --stat <resolvedBase>..<BASE> -- <unit's files>` → `movement: none|lines|structural`, and for every dependency the block names, its type/schema surface → `shape: none|changed`, because `--stat` is blind to shape and shape is the axis whose failures compile.
- **A runner + glob map**: `surface → runner → include/exclude globs → does it see this unit's paths?`, resolved to the glob. A unit no runner collects is recorded as such.
- **Repo kind and base**: **standard** (host-repo work), **multi-repo** (2+ checkouts, one primary where branch and PR live), **cross-repo / no-build** (zero host-repo changes: no worktree, `worktreeCreated: false`, pipeline collapses to gate → push → PR). A target repo outside the session's working directories is yours to run: record `repo:` and `runner: agent | orchestrator`.
- **Build/test preconditions** from `CLAUDE.md` and **every** `.claude/rules/` file, ignoring `paths:` frontmatter (at worktree-prep no test file is in context, so a path-gated rule cannot fire), each labelled `applies` only with the command that confirmed it at BASE, else `verify whether it applies`.

Re-resolve every PR the resolved designs cite (`gh pr view <n> --json state`); a `MERGED` stack parent is a base correction. An environment fact is per unit (`link:` specifiers resolve relative to each worktree) and travels as the command that produced it (`node -e "require.resolve('<pkg>')"`, `sops -d …`) with the observation, so the receiving lane re-runs the command rather than the conclusion. If you mutate shared state, name which units it affects. When a directive proves wrong, send a CORRECTION naming what to discard.

Done when every unit has a verified snapshot in the run dir, a `designResolved` / `resolvedBase` / status record, both drift words, a runner map, a repo kind, and labelled preconditions, and `run.yaml` carries `baseGate`.

**1 — Deps → waves.** Populate from `--deps`, then from the resolved blocks: a block is an interview transcript that routinely settles file overlap in writing, so derive `deps` from it with a `depsRationale` quoting it, and ask **once**, only about what the blocks leave open. The derivation is a hypothesis about diffs still unwritten; step 8 verifies it. Topologically sort; a cycle stops the run. Deps live in `run.yaml`, not in tracker links. Done when every unit has a wave and every dep a rationale.

**2 — Worktrees and branches.** Per unit, in wave order: pick a **clean** worktree (one unit each), cut the branch from `int/<run-id>` (independent) or from the parent's committed tip (stacked), then **verify the base yourself**: `git -C <wt> rev-list --count HEAD..origin/int/<run-id>` prints `0`, or `git merge-base --is-ancestor <parent-tip> HEAD` succeeds. A reported ahead/behind is a claim; this command is the check. `--dry-run` prints the resolved plan and stops here.

Then dispatch the [`provisioner`](../agents/provisioner.md) agent, once per unit, before any lane, with the unit id, worktree path, repo kind, run id and integration branch, run dir, scratchpad subdirectory, the pinned base sha, and the `baseGate` verdict for the branch it was cut from (step 0's for `int/<run-id>`, step 5's for a diamond base). It installs and builds, archives inherited `.work/`, lays a multi-repo unit out, snapshots the design layer read-only, carries the unit's map, writes `.work/lane.yaml` and records the base. Its `READY` is a claim: spot-check the one thing readiness means, an artifact its own tests import present on disk.

Sizing the fleet:

- **`--max-parallel` has a second axis, and it is not a machine resource.** Memory and cores say what the laptop survives; spend scales with lanes × the context each lane accumulates, and `--max-parallel` bounds only the first factor. Before dispatching a wave, record the expected cost and the ceiling you will spend in `run.yaml`. A cost stop happens at a wave boundary and means *stop dispatching*: `git push` every started lane's branch first and keep its worktree, because a lane that has not reached `/verify-build` has pushed nothing.
- Size `--max-parallel` by memory, not cores: past some N the fleet falls off a **cliff**, not a slope, and a starved lane reads as a hung one, so log load average and swap when a gate overruns. Serialise `generate-all`-class steps behind a lock; the two axes multiply, since each unit's `/build` may itself run a worktree pool.
- `--max-parallel` bounds lanes, not your own work: a certification gate (step 5's base gate, any gate whose verdict gates a decision) runs with nothing else of yours in flight, because under load a gate fails falsely and a red base you produced is indistinguishable from one you inherited. Before believing a red gate, re-run the named files alone and record `uptime` and `sysctl vm.swapusage` beside both results.
- The lock is a directory. Liveness is a `heartbeat` file refreshed in the background, reclaimed only when `now − mtime > 5 × interval` on two reads an interval apart with the mtime unchanged (a PID is dead seconds after any Bash call returns); the release removes the whole directory (`rm -rf`), because a stray file makes `rmdir` fail silently and every later waiter spins on an ownerless lock.

Done when every unit has a worktree and branch whose base your command verified, a provisioner `READY` you spot-checked (dispatched with a recorded `baseGate`), and `worktree`, `branch`, `base`, `stackParent` recorded in `run.yaml`.

**3 — Dispatch.** Probe the step-invocation tool once, before any lane: a lane needs `Agent`, and its step-lanes need `SlashCommand` or `Skill`, whichever this harness names it. Neither in your session means every lane blocks at `blocked-on=lane-tools` after provisioning, so switch to `--serial` now ([start-multi-serial.md](../reference/start-multi-serial.md)).

Waves in order; within a wave, launch `unit-lane` agents up to `--max-parallel`; a stacked child waits for its parent's **commit**. Each lane's brief is the `.work/lane.yaml` its provisioner wrote: the dispatch names the worktree, the branch, the unit id and the run dir, and points at the file rather than restating it, since a message is lost by the first `/clear` and the file is not.

The brief states only what you MEASURED, ALLOCATED or OBSERVED: drift, the runner/glob map, allocations, the baseline, environment probes, sibling provenance, the parent delta. Where it needs a block decision it quotes verbatim or cites the section, because a summary reads more usable than a quote and is where a false fact enters with zero drift and no gate to catch it. Every brief carries the precedence line: *"Where this brief and `ticket-block.md` disagree, the block wins and the brief is wrong — report the divergence."*

- Write `<run>/agents.yaml` (`unitId`, `agentId`, `worktree`, `dispatchedAt`) as each lane launches, resolve the recipient from it before every `SendMessage`, and lead with `TO: <TICKET-ID>`; the harness addresses opaque ids and you reason in ticket ids.
- A relayed sibling fact carries a branch or sha and its label, `PRESENT ON YOUR BASE` or `ON A SIBLING BRANCH ONLY — code to the seam, do not import`, and is addressed as `git show <sha>:<path>`, since a worktree path is invalid the moment the worktree is recycled.
- Allocate every monotonically-numbered artifact up front, ADR numbers above all, and on request mid-run, requiring claimed / released back; the `domain-modeling` skill states the numbering rule. An `adr=` attribute on a resolved marker is the number that was free when the block was written, not a reservation: re-derive it against BASE plus every sibling branch and rewrite the marker if it moved (`git ls-tree <BASE> --name-only <adr-dir> | grep -q "ADR-$n" && echo "COLLIDED: $n"`).
- Effort is a pre-flight decision, inherited from the session that launched the fleet and chosen once for every lane; model routing is stated per dispatch, and the brief's `modelRouting` carries it.
- Only you write `run.yaml`, aggregated from `units/<id>.state.yaml`; a unit that fails unrecoverably is `failed`, the others continue, and anything stacked on it becomes `blocked`.

Done when every unit in the wave has a row in `agents.yaml` and a state file the lane is writing.

**4 — Collect and resume.** Git is the primary signal and the state file a hint: cross-check `git log origin/<default>..HEAD` against the flags whenever you verify build-complete, and always before cutting a stacked child.

Verify the capability, not the report: **no `.work/steps/*.log` and no `LANE-STEP:` marker means no step ran as a step**, and a `/build` with no per-slice verifier verdict on disk did not run the dual gate. Either is `infra`: re-dispatch, and if it recurs, dispatch the `verifier` yourself per unit as a backfill before teardown. A `verifier` / `executor` / `test-runner` notification from inside a lane's `/build` is progress addressed to the lane, and gets no action, relay or write from you.

On every unit completion, check `<run>/units/<id>.learnings.md`: the lane writes it as the last act of its run, so copy `<worktree>/.work/learnings.md` there yourself only when it is absent (the lane died before writing), and do it immediately, because the worktree is a filesystem outside your control. "Reported complete" is not terminal: a worktree is recycled onto the next unit only when its unit has `terminal: true` in `run.yaml`, since a resume after recycling lands its edits in the sibling's tree with no warning from git; an unavoidable one names the branch the old worktree now holds and works from a fresh throwaway worktree.

You await many agents at once, so your waiting rule differs from a lane's. **A stall detector needs a terminal state and a positive control.** Exclude units at `passed` / `failed`, validate the detector against a directory you just wrote to (`find -mmin -N`; `-newermt` matches nothing on BSD/macOS), and give every awaited agent a ceiling of the base gate's duration × 3, never under 20 minutes, armed as a wake (`ScheduleWakeup`, or a `Monitor` on the transcript's mtime). Three stop shapes: completed + ~0 tool uses + untouched branch is starvation (re-dispatch); completed + real work + "standing by" is a deadlock (corrective resume); running with an unanswered `tool_use` older than the ceiling is blocked on an approval or isolation refusal (stop it, re-dispatch with the command split into plain single commands, and put that shape in the brief).

Aggregate into `run.yaml`. Resume any `in_progress` (dead agent) or escalated unit from its next incomplete step; committed slices are skipped. Escalations reach the human as one numbered list in your own reply, recommendation first and one line of why each, and the answers arrive in the next message. A design-heavy unit stops after `design` for review; a design-resolved unit flows straight to `plan`, escalating only where code drift re-opens a fork.

Done when every unit is `passed`, `failed`, `blocked`, or listed in the current escalation batch.

**5 — Base gate and stacked children.** You own a **diamond base**: a two-parent merge is yours, not the child's, because a base that does not compile surfaces deep inside the child. Generated files: `git checkout --theirs`, then re-run the generator. Hand-authored additive files: splice complete units. Check for `*.orig` residue before committing. Run the host repo's gate on `int/<run-id>` once (step 0), on every diamond base, and on any other orchestrator-authored commit lanes build on, before cutting a child from it: the `full-gate` skill, in the repo's scoped mode (or `--fast` where the host has no scoped mode, and say which ran). The whole-repo modes `--full` and `--all` are never a flow step's; that run is CI's, or the owner's on request. Where your base commit adds or removes a file of a kind a census or ratchet guard counts, run those guards by name on top and record them as named steps, since they glob the tree and no diff-scoped selection reaches them. Record the verdict as `baseGate` in `run.yaml`; it is also the integration-tier baseline the provisioner hands each lane.

A stacked child's scope is re-diffed against the parent's tip: at cut time diff `int..parentTip`, intersect with the child's named files and symbols, and hand it an explicit *already done by parent / refs moved* list. Record `parentTipAtCut`; the child forward-merges after the parent's `/verify-build` and again before opening its PR, and you tell it what changed in `parentTipAtCut..parentHEAD` and why it matters, because a commit it never touched can invalidate an assumption inside its slice without failing anything.

Before each unit's `/verify-build`, `git fetch origin` and compare `origin/<default>` with `createdBaseSha`; if it moved, name the overlapping files per unit (`git merge-tree`) and record the drift so a resumed run inherits it.

Done when every orchestrator-authored base has a recorded gate verdict and every stacked child has `parentTipAtCut`.

**6 — PRs.** Per passed unit, `/verify-build` opens the PR **ready for review** against `int/<run-id>`, or the parent branch when stacked. The default branch is `/merge-multi`'s target: a unit PR there carries sibling noise and resolves conflicts a second time. Done when every passed unit has `prUrl` and its `mergeable` state in `run.yaml`.

**7 — Teardown.** First merge the per-unit `<run>/units/<id>.learnings.md` files into `<run>/learnings.md`, tagged by unit, plus your own dispatch-time friction. Then remove only worktrees this run created whose branch is pushed, or whose unit is terminally `failed` and acknowledged, each as its own Bash call:

    git worktree remove <path>

A pre-existing or dirty worktree stays. Skip with `--keep-worktrees`. Done when `<run>/learnings.md` exists and every removed worktree's unit shows a pushed branch.

**8 — Report and capture.** Per unit: branch (with base or stack parent), step reached, PR URL and `mergeable` state, unresolved decisions, and its `owesSiblings` entries; then the stack topology and merge order. Verify the sibling overlap step 1 assumed, now that both diffs exist: `comm -12` the file lists, `git merge-tree` their merge base. For every pinned counter more than one lane touched, report each lane's delta and the base it took it from, because the merged pin is `base + Σ deltas`, a number on no branch, and `/merge-multi` needs the addends. Collapse follow-ups across units (the same finding from two lanes, items a sibling resolved in flight), separate *needs a decision* from *needs work*, and report raw → collapsed. Run `/capture-learnings` once over `<run>/learnings.md`. End by naming the next gesture: review the N PRs, then `/merge-multi <run-id>` in a **fresh session**, because this session is the largest context in the run and a mechanical merge needs none of it. Done when the report names every unit, every collapsed follow-up, and the next gesture.

## run.yaml (ephemeral, gitignored)

```yaml
runId: multi-<unit ids joined by ->   # e.g. multi-ESAS-93-94 — see step 0
createdBaseSha: <pinned origin/default>
integrationBranch: int/<run-id>
baseGate: { ref: <sha>, mode: <as GATE-MODE printed it>, verdict: PASS|FAIL, namedGuards: [] }
landedAt: null          # /merge-multi writes this
integrationPr: null     # /merge-multi writes this
flags: { gateDesign: false, noPr: false, serial: false, maxParallel: 2, keepWorktrees: false }
deps: [ { child: B, parent: A } ]
units:
  - { id: A, wave: 0, worktree: <path>, worktreeCreated: false, branch: A-slug,
      base: <sha | parent-branch>, stackParent: null, parentTipAtCut: null,
      designHeavy: true, designResolved: false, resolvedBase: null,
      step: build, status: in_progress, prUrl: null, terminal: false }
      # step: pending|start|design|plan|build|verify-build|done
      # prBase is always int/<run-id> unless stacked
```

## Principles

- **The orchestrator owns what no lane can see**: numbering, cross-lane dedup, base drift, sibling overlap, provisioning, addressing, the diamond merge. Each is invisible from inside a unit by construction.
- **Recon is a hint, not a fact.** Compute anything base-sensitive against the pinned BASE (`git show <BASE>:<path>`), not a working-dir grep whose HEAD drifts from it; every handed-down fact is a claim with a provenance and an expiry.
- **A sibling lane cannot cite another lane's committed design (or decisions, or concerns) until merge.** Each lane writes `<root>/<id>/` on its own unit branch; a lane needing a sibling's decision gets it quoted in its brief, the way step 0 hands down any cross-lane fact.
- **No silent decisions**: autonomous and escalated alike ride into the PR body and ADRs with their rejected options; the tracker is untouched after step 0.
