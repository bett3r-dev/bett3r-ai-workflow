---
description: Fleet orchestrator — drive N work units through the full flow unattended, one worktree each. Same contract; the lane brief lives in the `unit-lane` agent instead of inline.
---

# /start-multi — unattended delivery across worktrees

Drive a **list of work units** through the standard flow **unattended**, each isolated in its own git worktree. You are the **orchestrator**: you dispatch, verify git state with your own commands, collect escalations, and resume. You do **not** implement.

Everything a lane needs to know is in the [`unit-lane`](../agents/unit-lane.md) agent, dispatched at the moment it applies, rather than described here for you to relay. What is left in this file is what **no lane can see** — and that is the test of whether a line belongs here.

**Unattended is the contract; parallel is the optimisation.** Every human moment is batched (escalations, step 4) or pre-answered (a resolved design, step 0), and a fully serialized run — `--serial`, one long dep chain, a fleet already at swap — satisfies the contract in full.

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

  **Grep each snapshot for `design-multi:resolved:vN`** (emitted as an HTML comment *and* a visible inline-code line; match the marker's token regex, never marker-then-heading adjacency — the tracker's round-trip inserts a blank line there). Such a unit is `designResolved` with its `resolvedBase`, and is **not** design-heavy — its human interview already happened. This reader knows `:v1` and `:v2`; escalate an unknown `:vN` rather than guessing. From `:v2` the marker carries `status`: **skip anything not `ready` and log why** — deferrals, units blocked on human-supplied secrets, and umbrella parents with no net-new code burn a lane and can open a bad PR. `status=ready deps=<ID>` is ready **with a required dep**: add it to the dep graph as if passed in `--deps`. A status word outside those four is a contract drift — escalate, do not guess.

  **Snapshot from disk, not from a subagent's memory.** A resolved block runs ~10k tokens; reading it into context and re-emitting it pays twice before any lane starts, and the Jira MCP tool cannot fetch to a file. When the marker's `run=` names a `/design-multi` run whose dir exists (`.work/design-multi/<run>/units/`), **copy** `<id>.ticket.md` + `<id>.ticket-block.md` (and `NEW-*.ticket-body.md` for a commissioned ticket) from there and verify marker + `base=` against one cheap tracker field — a file copy cannot truncate. Only when the dir is absent fetch through a subagent, and then **verify every snapshot**: grep for `truncated` / `[...]` / `elided`, and assert the file ends with the block's terminal section. A "do not truncate" instruction is not a control — summarising is what a subagent does with a large document, and four of eleven snapshots once came back with a literal *"[Full resolved design section truncated for length...]"*, which read as complete short tickets to lanes that never see the tracker, and hid a compile dependency the wave plan then violated. A failed check is a re-fetch, not a warning; derive deps (step 1) only from verified snapshots.

  Then derive the four things **no lane can compute for itself**:

  - **Drift, per unit — never per run.** `git diff --stat <resolvedBase>..<BASE> -- <unit's files>` → `none | lines | structural`. One run-level note cannot say *"zero drift on two surfaces, +1248/−732 across 31 files on the third."*
  - **A runner + glob map**: `surface → runner → include/exclude globs → can it see this unit's paths?` Resolve to the **glob** — "vitest runs this package" is worthless when `include` is `*.test.ts` and the suites are `.test.tsx`. A unit no runner collects must say so rather than let a green count imply coverage.
  - **The repo each unit belongs to and its own base.** Three kinds: **standard** (host-repo work); **multi-repo** (2+ checkouts, one primary, where branch and PR live); **cross-repo / no-build** (zero host-repo changes → no worktree, `worktreeCreated: false`, pipeline collapses to gate → push → PR). The deciding test: **if the target repo is outside the session's working directories, an unattended agent cannot complete outward-facing steps there — you run it.** Record `repo:` and `runner: agent | orchestrator`.
  - **The host repo's build/test preconditions** — `CLAUDE.md` and **every** `.claude/rules/` file, *ignoring* `paths:` frontmatter. Path-gating is a context-loading optimisation; at worktree-prep no test file is in context, so the rule you need structurally cannot fire.

  **Re-resolve every PR the resolved designs cite** (`gh pr view <n> --json state`) — such a claim is stale by dispatch, and a `MERGED` stack parent is a **base correction**, not an escalation. Phrase handed-down tracker facts as *"verify at BASE whether X"*; your recall is the least reliable input in the run.

  **An environment fact is per-unit, never fleet-wide — and a completed lane's finding is still a per-unit fact.** `link:../pv3/packages/*` resolves relative to *each worktree*, so three lanes once held three dependency versions while the orchestrator asserted "pv3 is symlinked everywhere, do not rebuild" from its own checkout; and a lane's "SOPS keys not present" was passed down as settled when the real cause was an unmaterialised `config/local.yaml` — the receiving lane disproved it and ran the drift gate the briefing said was impossible. Hand down the **command** (`node -e "require.resolve('<pkg>')"`, `sops -d …`) with the observation, never the conclusion; if you mutate shared state, name which units it affects; if a directive proves wrong, send an explicit CORRECTION naming what to discard.

**1 — Deps → waves.** Populate from `--deps`, or ask **once** if >1 unit — but **read the resolved blocks before re-interviewing.** A block is an interview transcript and routinely settles file overlap in writing; derive `deps` from it with a `depsRationale` quoting it, and ask only about what the blocks do not cover. Every question they already answered is where this handoff leaks back into human time. Treat the derivation as a **hypothesis about diffs that did not exist when it was written** — step 8 verifies it. Topologically sort; a cycle stops the run. Never read tracker links.

**2 — Worktrees & branches: `install` is not `ready`.** A worktree is ready when the artifacts its own tests import exist on disk. Per unit, in wave order: pick a **clean** worktree (never a dirty one, one unit each), cut the branch from `int/<run-id>` (independent) or the parent's committed tip (stacked), then **verify the base yourself** — `git -C <wt> rev-list --count HEAD..origin/int/<run-id>` must be `0`, or `merge-base --is-ancestor <parent-tip> HEAD`. Never trust a reported ahead/behind ("74 ahead" was really 74 *behind*). `--dry-run` prints the resolved plan and stops here.

  Then dispatch the **`provisioner` agent, once per unit, before any lane** — install *and* build, archive the inherited `.work/`, multi-repo layout, the scratchpad, the `.work/lane.yaml` **lane brief**, the `.work/known-baseline-failures.md` record (base sha only; capture is on demand). It also carries the **design layer** in read-only when the run has one — `design.json` + `graph.json` copied to `.work/design-snapshot/` with the sha they came from — which is what lets a lane's `/build` scaffold its designed artifacts without a `.esas/` ever existing in a worktree. It refuses to copy a snapshot whose sha does not match the run's base, because a lane that generates against a tree that does not exist is worse off than one that hand-writes. All of it up front, because each of those failures is otherwise met alone, mid-pipeline, by N lanes that each get it wrong independently — and the two commonest present as a *broken baseline* rather than a missing step. Its `READY` is a claim: spot-check the one thing readiness means (an artifact its own tests import, present on disk).

  **Size `--max-parallel` by memory, not cores.** Past some N the fleet falls off a **cliff**, not a slope — one build measured 95 s alone and >38 min under load at swap 31.9 GB of 33.8. Contention is also the mechanism behind the 600 s deadlock, and a starved lane reads as a hung one, so log load average and swap when a gate overruns. Scope per-unit gates to touched packages and serialize `generate-all`-class steps behind a lock. Remember the two axes **multiply**: each unit's `/build` may itself parallelize slices.

  **The lock is a directory, and three things about it are not intuitive.** Never adjudicate ownership on PID liveness — every Bash call is a new shell, so the `$$` in `owner` is dead seconds after a legitimate acquire, and a coordinator once cleared a live lock on that evidence. A `heartbeat` touched once at acquire is a *timestamp*, not liveness; treat it as liveness only with a background refresher, and reclaim only when `now − mtime > 5 × interval` on two reads an interval apart with the mtime unchanged. And the release path must remove **every file it created** (or `rm -rf` the dir): a stray file makes `rmdir` fail silently, the dir leaks ownerless, and every later waiter classifies that as "acquire gap" and spins forever — leaked twice in one night.

**3 — Dispatch.** Waves in order; within a wave launch `unit-lane` agents up to `--max-parallel`. A stacked child waits for its parent's **commit**. Each lane's brief is the `.work/lane.yaml` the provisioner wrote in its worktree — the ticket snapshot, worktree path, branch and base, the drift verdict, the runner/glob map, the repo preconditions, its allocated ADR numbers, the model routing, and every handed-down fact **labelled** *applies* vs *verify whether it applies*. Dispatch points the lane at that file rather than restating it: a message is lost by the first `/clear`, and every step invoked on its own is a fresh agent.

  **Single-writer rule:** only you write `run.yaml`, aggregated from `units/<id>.state.yaml`. A unit that fails unrecoverably is `failed`, the others continue, and anything stacked on it becomes `blocked`.

  **Address every message; never resolve a recipient from recall.** Write `<run>/agents.yaml` (`unitId`, `agentId`, `worktree`, `dispatchedAt`) as each lane launches, resolve from it before every `SendMessage`, and **lead with `TO: <TICKET-ID>`**. You reason in ticket ids and the harness addresses opaque ones; reconstructing the map from dispatch order has misrouted two corrections in one run, silently in both directions.

  **A relayed sibling fact carries its provenance — a branch or sha, and whether it is on THIS lane's base.** In a stacked fleet most sibling facts are branch-local: "B already corrected `CONTEXT.md`" was true on B's branch and false on C's base, so C re-made the edit and guaranteed a conflict. Label it `PRESENT ON YOUR BASE` or `ON A SIBLING BRANCH ONLY — code to the seam, do not import`. **Never address a sibling's artifact by worktree path** — a path is valid when written and invalid when read once the worktree is recycled; `git show <sha>:<path>` works from anywhere. This is the *where* half of the *applies / verify* label, which says only how much to trust.

  **Allocate every monotonically-numbered artifact up front, ADR numbers above all** — by the time a lane wants one it is already writing. Derive from every ref *and* every sibling branch (`git ls-tree <branch> -- <adr-dir>` sees unpushed sibling ADRs), never from a remembered number. Require claimed/released back.

  **Effort is a pre-flight decision.** It is inherited from the session that launched the fleet and cannot be routed per dispatch — so it is chosen once, for every lane at once. Model routing *can* be stated, and the lane's brief states it.

**4 — Collect & resume. Git is the primary signal; the state file is a hint.** **Cross-check `git log origin/<default>..HEAD` against the flags** whenever you verify build-complete, and always before cutting a stacked child.

  **A stall detector needs a terminal state and a positive control.** Exclude units at `passed`/`failed` — without that a finished lane and a dead one give identical signals (no writes, no transcript, no commits), so the watchdog cries wolf exactly when the run is going well and gets muted right before it would matter. Validate it against a directory you just wrote to before trusting a negative. (`find -newermt '<relative>'` matches **nothing** on BSD/macOS, silently — use `-mmin -N`.) The two stop shapes look identical and need opposite responses: **completed + ~0 tool uses + untouched branch** is starvation (re-dispatch); **completed + real work + "standing by"** is a deadlock (corrective resume).

  **A grandchild's report is not addressed to you.** A `verifier`/`executor`/`test-runner` notification from inside a lane's `/build` reaches your session; its "the orchestrator may commit" means the **lane**, which already has the result. Read it as progress — do not act on it, relay it, or write into that worktree. Volume scales with **slices × units**, so at any real fan-out these bury the two signals that are genuinely yours: a lane escalating, and a lane finishing.

  **On every unit completion, rescue its learnings first**: copy `<worktree>/.work/learnings.md` → `<run>/units/<id>.learnings.md` now, not at teardown. The buffers are the run's richest output and the only artifact living on a filesystem you do not control — another session on the machine once deleted a completed lane's worktree to reclaim disk, seconds after it reported, before step 6 was ever reached.

  **"Reported complete" is not terminal.** A worktree may be recycled onto the next unit only when its lane has **no pending follow-up and will not be resumed** — track `terminal: true` per unit in `run.yaml` rather than inferring it. Resuming a lane (an ADR allocation, a correction) after its worktree was recycled is a **cross-lane write**: its branch is checked out nowhere, so its next edit lands in the sibling's tree with no warning from git, and a `git add -A` from either side puts one lane's ADR on the other's branch. If a resume after recycling is unavoidable, the message names the branch the old worktree now holds and tells the lane to work from a fresh throwaway worktree.

  Aggregate into `run.yaml`. Resume any `in_progress` (dead agent) or escalated unit from its next incomplete step — the flow is idempotent; committed slices are skipped. **Batch escalations** into one numbered list, recommendation first, one line of why each. Do **not** use `AskUserQuestion`. A **design-heavy** unit stops after `design` for review; a **design-resolved** unit is not gated — its grill verifies rather than re-derives and flows straight to `plan`, escalating only where code drift re-opens a fork. That is the whole mechanism; there is no separate unattended mode.

**5 — PR.** Per passed unit, `verify-build` opens the PR **ready for review** against `int/<run-id>` (or the parent branch if stacked), **never the default branch** — that defeats the topology: the diff carries sibling noise and merging resolves conflicts a second time that `/merge-multi` already resolved once.

  **Re-check the pin before `verify-build`, every time.** `git fetch origin`, compare `origin/<default>` against `createdBaseSha`. Nothing else re-checks it, so the last unit to finish silently eats whatever landed mid-run — arriving at the worst moment, with the work done and the gates green. If it moved, name the overlapping files per unit (`git merge-tree`) and record the drift so a resumed run inherits it.

  **You own a diamond base.** A two-parent merge is yours, not the child's — a base that does not compile surfaces deep inside the child. Generated files: `git checkout --theirs`, then re-run the generator, never hand-merge. Hand-authored additive files: splice **complete** units — a marker-strip breaks on array tails and interleaves two partial blocks at their shared prefix. Check for `*.orig` residue before committing (a `.ts.orig` is not compiled, so it passes every gate invisibly). Then **run the host repo's full gate on the base before cutting any child from it** (`full-gate` skill) and record the verdict in `run.yaml` — build + generate + union-check is **not** sufficient: census and ratchet guards glob the tree and import nothing, so no scoped run reaches them, and a red one lands on whichever lane happens to run `--full` first, paying another lane's bill. Same for any other orchestrator-authored commit lanes build on.

  **A stacked child's scope is re-diffed against the PARENT's tip, not the integration base.** Drift in step 0 was computed against `BASE`; a child's real base is `parentTipAtCut`, and against it part of the child's scope list is already done and its `file:line` refs have moved (two scope items and +5/+25 line drift in one cut). At cut time diff `int..parentTip`, intersect with the child's named files and symbols, and hand it an explicit *already done by parent / refs moved in these files* list.

  **A child cut early is stranded on a base its parent then fixes.** Cutting at build-complete is the right throughput call, but everything `verify-build` exists to find lands *after* the cut. Record `parentTipAtCut`; the child forward-merges after that `verify-build` and again before opening its PR. Better: diff `parentTipAtCut..parentHEAD` yourself and **tell the child what changed and why it matters to its work** — it cannot notice that a commit it never touched invalidates an assumption inside its own slice, and the gap does not surface as a failure.

**6 — Aggregate learnings, before teardown.** Merge the per-unit buffers step 4 rescued into `<run>/learnings.md`, tagged by unit, plus your own dispatch-time friction; re-copy any worktree buffer newer than its rescued copy. **This must precede step 7**, which deletes the worktrees the buffers live in.

**7 — Teardown.** Remove only worktrees **this run created** whose branch is pushed (or whose unit is terminally `failed` and acknowledged). Never a pre-existing or dirty one. Skip if `--keep-worktrees`.

**8 — Report & capture.** Per unit → branch (+ base/stack) → step reached → **PR URL *and* its `mergeable` state** → unresolved decisions. Show the stack topology and merge order.

  **Verify the sibling overlap you assumed at step 1.** Both diffs now exist: `comm -12` the file lists, `git merge-tree` their merge base. One overlap claim carried by both tickets turned out to be seven shared files conflicting in three.

  **For every pinned counter more than one lane touched, report each lane's DELTA and the base it measured from** — never the branch values. Each lane's number is right on its own base and wrong everywhere else, and the merged pin is `base + Σ deltas`, a number on no branch (689 + 8 + 3 + 2 + 1 + 1 = 704 across five lanes). `/merge-multi` needs the addends.

  **Collapse the follow-ups across units before reporting** — the same finding from two lanes (they cannot see each other's buffers), items a sibling resolved in-flight, and documented-not-defects. Separate *needs a decision* from *needs work*, cluster by theme, and report raw → collapsed ("82 follow-ups" is debt; "8 tickets, 6 one-liners, 5 questions, 13 closes" is a plan). Nothing else consumes those buffers as a set.

  Then run **`/capture-learnings` once** over `<run>/learnings.md` — you are the interactive session again, so route and dedup across all units in one pass.

  End by naming the next gesture: *review the N PRs, then run `/merge-multi <run-id>` in a **fresh session*** — this session is the largest context in the run, and a mechanical merge needs none of it.

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
- **Recon is a hint, not a fact.** Compute anything base-sensitive against the pinned BASE (`git show <BASE>:<path>`), never a working-dir grep whose HEAD drifts from it. Every handed-down fact is a claim with a provenance and an expiry — [EVIDENCE.md](../EVIDENCE.md) §3.
- **Tracker once, then never.** Deps live in `run.yaml`, not in tracker links.
- **Unattended is the contract; parallel is the optimisation.** Never buy throughput with an unbatched stop.
- **Never clobber a dirty worktree; tear down only what this run created.**
- **Resumable** via `run.yaml` + idempotent steps + per-slice commits.
- **Ready-for-review PRs against `int/<run-id>`; nothing merged; the tracker untouched after step 0.**
- **No silent decisions** — autonomous and escalated alike ride into the PR body and ADRs with their rejected options.
- **Learnings survive teardown** — rescued at unit completion (step 4), aggregated at 6, captured at 8.
