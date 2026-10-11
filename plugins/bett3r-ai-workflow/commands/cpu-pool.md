---
description: Lift the CPU pool before a fleet (one machine-wide compiler token pipe every lane's cargo joins), and say how to launch the orchestrator inside it. Also status, refill, down.
disable-model-invocation: true
---

# /cpu-pool — lift the pool before a fleet

The pool caps compilers machine-wide so a compile-heavy fleet can run more lanes than `cores ÷ 4` without thrashing. It reaches a lane only through `CARGO_MAKEFLAGS` in the environment the orchestrator was **launched** from: a Bash call cannot change its own session's environment, so lifting the pool from inside a session does not make that session join. This command lifts it and hands the owner the launch line. Mechanism, sizing and limits: `reference/cpu-pool.md`.

## Argument: $ARGUMENTS

| Form | Does |
|---|---|
| *(empty)* | `up` with the default tokens (cores − 1) |
| `<N>` or `--tokens <N>` | `up` with N tokens |
| `status` | holder alive, free tokens, rustc and cargo running |
| `refill` | restore the token count a killed cargo took with it; refuses while any cargo runs |
| `down` | stop the holder and remove the pipe; never while a fleet is running |

## Step 1 — Run it

```bash
cpu-pool up [--tokens N]     # or: cpu-pool status | refill | down
cpu-pool status
```

`cpu-pool` is on `PATH` by bare name from this plugin's `bin/`. If it is not found, fall back to `python3 plugins/bett3r-ai-workflow/scripts/cpu-pool.py`. Every subcommand ends in one `CPU-POOL:v1` line; report it verbatim. `up` on a live pool reuses the holder and resets the count (`reused=true`), so running it twice is safe. For `up` with no count given, `status` first: if the pool is already up, say so and leave its token count alone unless the owner asked for one. `down` while `cargo=` is above 0, or while this session or another holds a fleet in flight, is a question for the owner, not an action. Done when the verdict line is printed.

## Step 2 — Say whether this session is in it (after `up`)

```bash
printenv CARGO_MAKEFLAGS
command -v cpu-pool
```

- **Set, and its `fifo:` path is the pool's `path=`**: this session already joins. Say so; `/start-multi` can run here.
- **Unset or another path**: this session and anything it dispatches build **uncapped**. Say it plainly, then give the owner the block to run from a fresh terminal, with the absolute `cpu-pool` path from `command -v` substituted, since `bin/` is on `PATH` only inside a session:

  ```bash
  eval "$(/abs/path/to/bin/cpu-pool env)"   # export CARGO_MAKEFLAGS=--jobserver-auth=fifo:…
  claude                                     # then /bett3r-ai-workflow:start-multi …
  ```

  For a headless fleet, the `eval` line goes before `fleet-loop --run <run-dir> --tick "…"` in the same shell. The pool outlives this session; nothing here needs to stay open.

Done when the owner knows whether this session joins and, if not, has the exact lines to launch one that does.

## Step 3 — Remind what the fleet owes the pool

One line, not a lecture: with the pool up, `/start-multi` records `cpuPool: { path, tokens }` in `run.yaml`, logs `cpu-pool status` beside `uptime` at each dispatch, runs `cpu-pool refill` at a wave boundary when `free=` sits below `tokens=` with no cargo running, and widens one wave at a time (RAM and disk bound the lanes now, not cores). `cpu-pool down` after the fleet lands.
