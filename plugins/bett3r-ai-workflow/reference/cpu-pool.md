# The CPU pool (`bin/cpu-pool`)

How a fleet on a compile-heavy host runs more lanes than `cores ÷ 4` without the
machine collapsing. Read with [start-multi-sizing.md](start-multi-sizing.md); that file
owns the lane count, this one owns the mechanism.

## Why

A lane is mostly idle from the machine's point of view: the model's thinking uses
no local CPU, and in pv4's `multi-rus-loop` W2 an executor's time was about half
model and half commands. Then every lane compiles at once, and each cargo takes
every core it sees. Six Rust lanes on ten cores (W0) ran 160 min per lane against
47 at two lanes, with `git` calls averaging a minute. That measurement was taken
with three rogue processes holding three cores at 110 % each, so it overstates the
collapse, but the shape is real: lanes do not slow down gracefully, they thrash.

Queueing whole commands behind K slots would fix it, and would need a lock primitive
macOS lacks (no `flock` binary), a wait that counts against the Bash tool's
timeout, and rules for starvation and stale locks. The pool is the smaller thing.

## What

cargo is a client of the GNU make **jobserver** protocol. One named pipe holds N
tokens; every cargo told `CARGO_MAKEFLAGS=--jobserver-auth=fifo:<path>` takes a token
per compiler process it starts and gives it back when that process exits, across
every worktree on the machine. A lone lane gets all N; six lanes share them;
nothing waits before starting, so no Bash timeout changes. Concurrent compilers
machine-wide stay ≤ lanes + N (each cargo holds one implicit token).

Measured 2026-10-11, cargo 1.99.0, macOS 14, six concurrent `cargo test --no-run`
in six copy-on-write worktrees: peak **14 rustc with 9 tokens**, against 57 uncapped;
tokens intact after every normal run.

`CARGO_MAKEFLAGS`, not `MAKEFLAGS`: cargo reads either, GNU make 3.81 (macOS) reads
only the second, so a gate's `make` sees nothing. A missing pipe is loud: cargo prints
`warning: failed to connect to jobserver from environment variable` and builds
uncapped, visible in any step log.

## How it reaches a lane

Through the environment. A Bash call inside Claude Code inherits the process's
environment, and so do its subagents, so the shell that launches the orchestrator
exports the variable once and every lane, executor, verifier and gate joins
(verified 2026-10-11 with `claude -p` on 2.1.296). Nothing in a lane brief, nothing
an agent must remember.

    cpu-pool up                      # CPU-POOL:v1 action=up outcome=ok path=… tokens=9 holder=…
    eval "$(cpu-pool env)"           # export CARGO_MAKEFLAGS=--jobserver-auth=fifo:…
    fleet-loop --run <run-dir> --tick "CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 claude -p '/bett3r-ai-workflow:start-multi …'"

or `claude` itself for an interactive orchestrator. `bin/` is on `PATH` in a session
that loaded the plugin; from a plain shell, call it by path under the plugin's cache
copy (`~/.claude/plugins/cache/bett3r-ai-workflow/bett3r-ai-workflow/<version>/bin/cpu-pool`).

The pool outlives sessions: a holder process keeps the pipe open, and the state file
`<path>.json` beside it records tokens and the holder's pid. `cpu-pool up` on a live
pool reuses the holder and resets the token count. `cpu-pool down` ends it.

## Sizing

- Tokens default to `cores − 1`. With 6 lanes that allows up to 15 compilers on
  10 cores, a small overcommit that keeps every core busy through one build's serial
  tail (linking, the crate on the critical path).
- The lane count is then bounded by **RAM and disk**, not cores: each lane links its
  own test binaries (pv4: eleven), and each worktree's copy-on-write `target/` grows
  as it compiles. Log `cpu-pool status` beside `uptime` at each dispatch, and record
  `cpuPool: { path, tokens }` in `run.yaml` so the fleet's metrics can separate a wait
  for tokens from a slow compile.
- The orchestrator's own gates (the base gate, wave gates, `--full`) join the same
  pool automatically; they no longer need a quiet machine to be believed, only a
  record of `cpu-pool status` beside the verdict.

## What it does not do

- It is cargo-only. Running the test binaries, `go test`, `node` and `make` take no
  tokens; none of those is where the fleet's CPU went.
- A client killed while holding tokens (`kill -9` on cargo mid-build) loses them,
  shrinking the pool. `cpu-pool status` shows `free=` below `tokens=` with no cargo
  running; `cpu-pool refill` restores N, refusing (`outcome=busy`) while any cargo
  runs because held tokens cannot be told from lost ones. Run it at wave boundaries.
- It does not cut total compile-minutes. Fewer gate runs per ticket (the executor's
  fast gate, the scoped gate once in `/verify-build`) and a shared compile cache do
  that; the pool only stops the machine from thrashing while those minutes run.
