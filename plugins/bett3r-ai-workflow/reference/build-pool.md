# /build — the worktree pool

*Companion to `/build` Step 2, read when `worktree-pool size` reports `pool>0`; not a step to run on its own.*

The git mechanics are `worktree-pool`'s: it provisions, resets, lands and tears down, and ends every call with one `WORKTREE-POOL:v1 cmd=… outcome=…` line. A call that prints no verdict line died before concluding: stop using the pool, check `git status` in the main checkout (a land may have died mid cherry-pick), report it, and finish the remaining slices sequentially in the main tree (`modeReason: no-verdict-line`).

## 1. Provision, before any slice runs

Resolve the install and build commands (the brief's `preconditions`, else the repo's `CLAUDE.md` and `.claude/rules/`; say which; `''` for one the repo lacks). `worktree-pool provision <pool>` requires `outcome=provisioned`. Then dispatch the `pool-provisioner` (`haiku`) per listed worktree, one at a time and while none of your gates is running: cold builds under a running gate fail it falsely.

`outcome=refused` (`path-exists-not-a-worktree`: leave the path alone; `reused-worktree-holds-work`: name its `path=` as held work for a human), `outcome=failed`, and a `pool-provisioner` reporting `BLOCKED` take one exit: `worktree-pool teardown` what was added, run every slice sequentially in the main tree (`modeReason: provision-refused|provision-failed`), report why.

## 2. Reset before every take, unconditionally

Before a worktree takes a slice, its first included: `worktree-pool reset <worktree> <task-branch> --install '<cmd>' --build '<cmd>'`, requiring `outcome=reset`. Install and build run whether or not anything changed (a reused tree inherits stale build output), and a warm tree costs time, never correctness. Never skip it because the lockfile did not move. `outcome=failed step=install|build`: retry the reset a single time, then retire the worktree. `outcome=refused reason=unlanded|dirty`: the worktree holds work; retire it. A retired worktree's slice goes to another worktree, or to the main tree when none is left (`modeReason: worktrees-retired`).

A worktree whose slice did not land takes no further slice until teardown: a reset would switch and clean the slice's work away, and an escalated new-files-only slice is untracked files the dirty check deliberately ignores. Retired, not reset; teardown's refusal keeps the work on disk.

## 3. Dispatch into the worktree

Each ready slice runs the whole of Step 3 there: executor, test-runner, scope-check and verifier receive the worktree path as the project directory, and the commit is made in that worktree. A dependent slice becomes ready only after its parent landed: its reset takes the task-branch tip, and a parent still in a worktree does not exist for it.

In a pool worktree point the scaffolder's `--design`/`--graph` at the main checkout's `.esas/design.json` and `.esas/graph.json`, and skip the step (*snapshot sha ≠ this worktree's base*) after a sibling has landed since the reset.

## 4. Land in dependency order, parents first

`worktree-pool land <worktree> <sha> --base <reset tip>`, `<reset tip>` being the `tip=` of that worktree's last reset verdict.

| Outcome | Action |
|---|---|
| `outcome=landed` | Set `passes: true` now, at the land, with the landed sha: the verdict's `sha=`, the **landed** sha, never the worker's, into `.work/slices.yaml` and a fleet's state file; then push. `already=true` reads the same way (a resumed run re-landing after a crash between land and record): record `sha=`. |
| `outcome=conflict` | Branch untouched. `ESCALATE` the slice with `paths=`, resolve nothing by hand, dispatch none of its dependants. Its worktree keeps the commit and is retired. |
| `outcome=refused reason=main-checkout-dirty` | Your main tree has tracked modifications: contamination. Stop landing and surface them; a commit or discard made to let a land through is the move this refusal exists to stop. Untracked files refuse nothing. |
| `outcome=refused reason=sha-not-in-worktree` | Read that worktree's `git log`: exactly one commit in `<reset tip>..HEAD` lands; anything else is `ESCALATE`. |
| `outcome=refused reason=sha-not-after-base` | The worker made no commit, so the slice is not built and `passes:` stays false. A red gate: re-dispatch the executor into the same worktree within the fix-round cap, then `ESCALATE` and retire the worktree. |
| `outcome=failed step=cherry-pick` | Git refused before any conflict (an untracked main-tree file in the way, an empty pick). Branch untouched; `ESCALATE` with the output. |
| `outcome=error` | A usage defect, or `reason=tip-moved-after-abort`: stop all landing and inspect the task branch first. |

Workers never write the record: a worker reports facts (its commit sha, gate verdicts, flagged deviations), and you alone write `.work/slices.yaml`, `decisions.md` and `build-summary.md`, in the main tree, after the land, committing the record before the next land (a tracked modification in the main checkout refuses one).

## 5. Tear down when every slice landed

`worktree-pool teardown`; `outcome=removed` ends the pool. `outcome=refused reason=unlanded|dirty` names worktrees still holding work (a commit on no branch, an escalated slice's files): leave them and name them in the Step 5 report. `outcome=failed step=worktree-remove`: report the path, with no forced retry. In the pool, "committed" in the verdict means landed.
