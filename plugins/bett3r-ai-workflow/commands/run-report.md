---
description: Where a unit of work's time and tokens went, per pipeline command, role and slice. Reads the transcripts, so any past branch can be reported.
disable-model-invocation: true
---

# /run-report — where the time and tokens went

Reconstructs a unit of work from Claude Code's own transcripts; nothing is instrumented, so any branch on disk can be reported.

## Argument: $ARGUMENTS

| Form | Does |
|---|---|
| *(empty)* | report the current git branch |
| `<branch>` | report that branch |
| `--list` | branches on disk, most recent first |
| `--aggregate` | the trend across every recorded run, grouped by plugin version |
| `--agents` | agent performance across every run: role, model, effort, and what the repo checks cost |
| `--emit` | also record the run to `~/.claude/bett3r-metrics/` (what `/verify-build` does) |
| `--since <5d\|2w\|1m>` | limit the transcript scan or the aggregation window |
| `--fleet <run-dir>` | resolve a `/start-multi` unit (branch or unit id) through that run's `agents.yaml`; automatic from a lane worktree's `.work/lane.yaml` or from `./.work/multi/` |
| `--fleet <run-dir> --all` | the whole fleet run: one row per unit, orchestrator-only time outside every unit's window (an approximation), and `BIGGEST SINGLE CALLS` so a multi-hour blocked call is named rather than folded into `active` |

## Step 1 — Run it

```bash
run-metrics $ARGUMENTS
```

`run-metrics` is on `PATH` by bare name from this plugin's `bin/`; the plugin-root variable is substituted for *hook* invocations only, so a command's bash never uses it. If the bare name is not found, fall back to `node plugins/bett3r-ai-workflow/scripts/run-metrics.mjs`.

The script does all the parsing and arithmetic; this command interprets. If it reports no transcripts for the branch, run `--list` and check the name. A fleet unit is not found by branch, by construction: a lane runs as a subagent of the orchestrator's session, so its records carry the orchestrator's branch. The script resolves it through the run's `agents.yaml`, found from the lane worktree's `.work/lane.yaml` `runDir`, from `./.work/multi/` in the orchestrator's checkout, or from `--fleet`. Done when the tables print, or the absence is explained.

## Step 2 — Read the four numbers that carry the decision

Print the tables, then say what they mean.

1. **Duty cycle** (`alive ÷ elapsed`). Low means the run was slow because nothing was running. Check `DEAD GAPS`: many short pauses is a flow problem (the loop keeps stopping to ask), one long gap is a night's sleep.
2. **First-pass green**, per build invocation. Each fix round costs a whole extra executor pass, so this is the largest lever on cost.
3. **tool vs reason**, per role. A role at ~95% reason is thinking; a role heavy in `tool` is bounded by commands, and `WHERE COMMAND TIME WENT` names which.
4. **Weighted tokens per line landed.** Compare it against `--aggregate`, not intuition.

For the agents rather than the run, `--agents` splits the same numbers `BY ROLE`, `BY MODEL` and `BY EFFORT`; only the `ROLE × MODEL × EFFORT` table controls for which roles ran on a model. `REPO CHECKS` and `WHO PAYS FOR THE CHECKS` show how much shell time is the repo answering back, and for whom. A class dominated by one very long call is flagged, not summed: a multi-hour call is a block (a prompt, a pager, a waiting permission), not throughput to optimise. Done when each of the four numbers has one sentence of reading.

## Step 3 — Name the lever, or say there is none

One recommendation tied to a number in the output: "verifiers spend 96% reasoning and found nothing on 9 of 12 slices, so try a cheaper verifier model" is useful; "optimise the build" is not. A run that was mostly the user asleep is not a process defect. Done when the report ends on one lever or an explicit none.

## What the numbers mean

| Term | Definition |
|---|---|
| **elapsed** | first → last activity; per run, anchored at the first pipeline command |
| **active** | `tool` + `reason`: the run genuinely working; parallel runs add up |
| **alive** | wall-clock during which at least one run was active; never exceeds elapsed |
| **stalled** | `elapsed − active`: API backoff, a permission prompt, a parked session |
| **child** | a parent blocked on a spawned agent; attributed to the child |
| **duty cycle** | `alive ÷ elapsed` |

## Why it is measured this way

- **A unit of work is not a session.** `/clear` and `/handoff` scatter one branch across many sessions; the join key is the git branch.
- **One session is not one branch either.** Records are sliced by branch, or a session that touched six branches reports all six as each other's work.
- **Wall time is not elapsed time.** Every millisecond is classified, never subtracted.
- **A long command is not a stall.** Only non-tool silence counts as stalled, so the threshold applies to gaps between tool calls.
- **Each `/build` invocation is its own ledger.** Merging two passes over the same slices makes every slice look like it took a fix round.

Say where a number is an approximation (prorated per-phase tokens, heuristic slice attribution, `unattributed` rows). A run gets cheaper by weakening the verifier and these tables would applaud, so read first-pass green and rework churn beside any cost win.
