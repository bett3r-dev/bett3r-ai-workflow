# /start-multi --serial — the orchestrator runs the lanes

`--serial` keeps the contract (unattended, one integration branch, PRs against `int/<run-id>`) and drops cross-unit parallelism: there is no `unit-lane`. You run each unit's five steps yourself, from inside its worktree, with the real `executor`, `verifier`, `test-runner` and `scope-check` agents under `/build`. Use it when `--serial` was passed, when step 3's probe found no `Agent` or no step-invocation tool in your session, or when a fleet is already at swap.

## Mechanics

1. **Enter the worktree.** The pipeline commands act on the session's cwd, so `EnterWorktree(<path>)` per unit, then invoke `/start`, `/design`, `/plan`, `/build` (re-invoked on a yield exactly as `unit-lane` states) and `/verify-build`, each bare, each reading `.work/lane.yaml`. Read every verdict off the step's `LANE-STEP:` line; an absent line is `infra` and the step is re-run.
2. **Mirror the run state.** Inside a worktree you cannot write the run dir or another worktree, so keep run state in `<worktree>/.work/orchestrator/state-mirror.md` and apply it to `run.yaml`, `agents.yaml` and `units/<id>.state.yaml` after `ExitWorktree` (keep the worktree). A lane this mode replaces stays in `agents.yaml` with `status: superseded`, so nothing resolves the unit to it.
3. **Write briefs that isolation accepts.** Worktree isolation refuses, or holds for approval, commands it cannot show are not git: a compound `cd … && git …`, a runtime variable as a command argument, a `node -e` built from command output, and any copy or delete of a `.git`, even under the scratchpad. Every executor and verifier brief says *plain single commands, absolute scratch paths*. These shapes are the harness's heuristics; re-verify them when it changes.
4. **Wait as a lane would.** Step 4's stall ceiling and wake apply to every per-slice agent you dispatch here (executor, verifier, test-runner, scope-check), and each wait is one blocking call, as `unit-lane` states.
5. **Rescue learnings before leaving.** Copy `<worktree>/.work/learnings.md` → `<run>/units/<id>.learnings.md` before `ExitWorktree`; with no lane, you are that file's writer here. Steps 5 to 8 of `/start-multi` apply per wave as on the parallel path.

Done with a unit when its state file shows `verify-build` with an outcome, its PR URL is recorded, and the mirror has been applied to `run.yaml`.
