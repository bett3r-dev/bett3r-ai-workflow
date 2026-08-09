---
description: Where a unit of work's time and tokens actually went — per pipeline command, per role, per slice. Reads the transcripts, so it works on any past branch.
---

# /run-report — where the time and tokens went

Reconstructs a unit of work from Claude Code's own transcripts. Nothing is instrumented, so **every branch already on disk can be reported retroactively** — including the ones that took eight hours and you want to explain.

## Argument: $ARGUMENTS

| Form | Does |
|---|---|
| *(empty)* | report the current git branch |
| `<branch>` | report that branch |
| `--list` | branches on disk, most recent first — use when you don't recall the exact name |
| `--aggregate` | the trend across every recorded run, grouped by plugin version |
| `--agents` | **agent** performance across every run: role, model, effort, and what the repo checks cost |
| `--emit` | also record the run to `~/.claude/bett3r-metrics/` (what `/verify-build` does) |
| `--since <5d\|2w\|1m>` | limit the transcript scan (or the aggregation window) |

---

## Step 1 — Run it

```bash
run-metrics $ARGUMENTS
```

`run-metrics` is on `PATH`: every enabled plugin's `bin/` is, keyed by the version the session loaded. Do **not** reach for `${CLAUDE_PLUGIN_ROOT}` — it is substituted for *hook* invocations only, so in a command's bash block it expands to empty and the failure reads as a missing file rather than a missing variable. If the bare name is genuinely not found (a source checkout that was never installed), fall back to `node plugins/bett3r-ai-workflow/scripts/run-metrics.mjs`.

The script does all the parsing and arithmetic. **Do not recompute any of it by reading transcripts yourself** — they run to hundreds of megabytes, and the four traps below are already handled there.

If it reports no transcripts for the branch, run `--list` and check the name; a branch reachable in git is not necessarily one you did work on in this tool.

## Step 2 — Read the four numbers that carry the decision

Print the tables, then say what they mean. The point of the report is the tweak it implies, not the tables.

1. **Duty cycle** (`≥1 agent alive` ÷ `run elapsed`). Low duty cycle means the run was slow because *nothing was running*, not because the agents were slow. Check `DEAD GAPS` before concluding anything: ten short pauses is a flow problem (the loop keeps stopping to ask you something), one long gap is just a night's sleep and needs no fix at all.
2. **First-pass green**, per build invocation. Each retry costs a whole extra executor pass, so this is the largest single lever on total cost. Read it per invocation — never across a branch that ran `/build` twice.
3. **tool vs reason**, per role. A role at ~95% reason is thinking, not waiting on your machine; speeding up the build won't touch it. A role heavy in `tool` is bounded by commands, and `WHERE COMMAND TIME WENT` names which.
4. **Weighted tokens per line landed**. The efficiency number. Compare it against `--aggregate`, not against intuition.

### When the question is about the agents, not the run

`--aggregate` answers *"how are my runs trending?"*. `--agents` answers *"how are my agents performing?"* — a different cut, and usually the more actionable one:

- **BY ROLE** — where active time goes, split tool vs reasoning, with `tok/line` per role.
- **BY MODEL** / **BY EFFORT** — the same split, discriminated. Read these two together with role: a model's `tok/line` is mostly a statement about *which roles ran on it*, not about the model. Only the **ROLE × MODEL × EFFORT** table controls for that, which is why it exists.
- **REPO CHECKS** — how much of shell time is the repo answering back (`build`, `test`, `typecheck`, `lint`, `generate`, `install`) rather than the model working, and **WHO PAYS FOR THE CHECKS** attributes it per role.

A class dominated by one very long call is flagged rather than left in the total. **A single multi-hour call is a block — an interactive prompt, a pager, a waiting permission — not throughput to optimise**, and treating it as cost sends you tuning something that was never slow.

## Step 3 — Name the lever, or say there isn't one

Give **one** recommendation, tied to a number in the output. "Verifiers spend 96% of their time reasoning and found nothing on 9 of 12 slices — consider a cheaper model for the verifier" is useful. "Consider optimising the build" is not.

If nothing stands out, say so plainly. A run that was mostly you being asleep is not a process defect, and reporting it as one trains you to ignore the report.

---

## What the numbers mean

| Term | Definition |
|---|---|
| **elapsed** | first→last activity. Per run, anchored at the first pipeline command. |
| **active** | `tool` + `reason` — the run genuinely working. Parallel runs add up, so the sum exceeds wall time. |
| **alive** | wall-clock during which *at least one* run was active. Never exceeds elapsed. |
| **stalled** | `elapsed − active`: API backoff, a permission prompt waiting on you, or a parked session. |
| **child** | a parent blocked on a spawned agent. Attributed to the child, never counted as the parent's work. |
| **duty cycle** | `alive ÷ elapsed`. How much of the calendar the machine was actually working. |

## Why it is measured this way

Each of these was measured the wrong way first, and each wrong way looked entirely reasonable:

- **A unit of work is not a session.** `/clear` and `/handoff` scatter one branch across many sessions — one real branch spanned 26. The join key is the git branch.
- **One session is not one branch either.** A session that touched six branches will report all six as each other's work unless records are sliced by branch. Three unrelated branches once reported byte-identical totals.
- **Wall time is not elapsed time.** `last − first` once claimed 3,587 minutes for an agent that worked 52. Every millisecond is classified, never subtracted.
- **A long command is not a stall.** A 40-minute build is real work, so only *non-tool* silence counts as stalled. This is why the threshold applies to gaps between tool calls and not to the calls themselves.
- **Each `/build` invocation is its own ledger.** Merging two passes over the same slices makes every slice look like a retry — a real branch read 0% first-pass-green purely from that, when its two passes were 33% and 100%.

## Principles

- **The script is the source of truth for the arithmetic.** Interpretation is this command's job; recomputation is not.
- **Report what was measured, not what would be reassuring.** Where a number is an approximation — prorated per-phase tokens, heuristic slice attribution, `unattributed` rows — say so rather than presenting it flat.
- Efficiency without quality is a trap: a run gets cheaper by weakening the verifier, and these tables would applaud. Read `first-pass green` and rework churn alongside any cost win.
