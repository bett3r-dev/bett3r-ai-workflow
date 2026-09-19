# Sizing the fleet (`/start-multi --max-parallel`)

How wide to run a fleet, and why the limit is not a machine resource. Extracted from
[`commands/start-multi.md`](../commands/start-multi.md) step 2 under ADR-012's ceiling;
**normative** — read it before choosing `--max-parallel` or believing a red gate.

- **`--max-parallel` has a second axis, and it is not a machine resource.** Spend scales with lanes × the context each lane accumulates; `--max-parallel` bounds only the first factor. Record the expected cost and your ceiling in `run.yaml` before dispatching a wave. A cost stop happens at a wave boundary and means *stop dispatching* — the boundary's five preconditions then apply in full.
- Size it by memory, not cores: past some N the fleet falls off a **cliff**, not a slope, and a starved lane reads as a hung one — log load average and swap when a gate overruns. Serialise `generate-all`-class steps behind a lock; the axes multiply, since each unit's `/build` may run its own worktree pool.
- It bounds lanes, not your own work: a certification gate (step 5's base gate, any gate whose verdict gates a decision) runs with nothing else of yours in flight — under load a gate fails falsely, and a red base you produced is indistinguishable from one you inherited. Before believing a red gate, re-run the named files alone and record `uptime` and `sysctl vm.swapusage` beside both results.
- The lock is a directory. Liveness is a `heartbeat` file refreshed in the background, reclaimed only when `now − mtime > 5 × interval` on two reads an interval apart with the mtime unchanged (a PID is dead seconds after any Bash call returns); the release removes the whole directory (`rm -rf`), because a stray file makes `rmdir` fail silently and every later waiter spins on an ownerless lock.

