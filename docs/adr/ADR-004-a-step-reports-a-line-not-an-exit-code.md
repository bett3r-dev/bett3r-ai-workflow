# A step reports a line, not an exit code — and the line's absence is a verdict

A pipeline step invoked on its own has to say what happened in a way something other than a human
can read. The obvious channel is the exit code, and the issue that prompted this asked for exactly
that: *"distinguishable exit codes (success / gate-red / `BLOCKED_ON` / infra)"*.

We did not do that. **The verdict is a `LANE-STEP:v1` line on stdout; the exit code is a coarse
cross-check, never the contract.**

## Why not the exit code

This plugin has spent a lot to learn that exit codes lie, and the lessons are already written down
in four places — `full-gate` (*"never read a pass from a piped exit code, yours or the script's —
nor from a wrapper's"*), `executor`, `provisioner`, `test-runner` — plus EVIDENCE.md's probe
hygiene. The recorded failures: a pipeline reporting `tail`'s status, a wrapper reporting `echo`'s,
and a sharded runner that "exited 0 with two shards FAIL".

Those are properties of **shell pipelines and wrappers**, not of a process's true exit status, and
the distinction matters — a caller reading a real process's status has no pipe in it. So the
argument against exit codes is not that they are always wrong. It is narrower, and it still holds:
**the exit code is one integer, set by whoever happens to run last, and every layer between the step
and its reader can overwrite it without anyone noticing.** A channel that fails silently in the
reassuring direction is the wrong place for the contract.

## What we did instead

One line, emitted last, structured facts as attributes on the marker:

```
LANE-STEP:v1 step=build outcome=success slices=3/3 commits=3
```

This is not a new invention. The repo already had the pattern twice, and reaching for a third shape
was the error the design pass corrected in itself:

* **`full-gate`** — the gate prints `GATE-STEP:` lines, and *"the flow reads those lines, never the
  exit code alone"*.
* **`design-multi`** — `design-multi:resolved:vN` is *"the only machine-readable surface"*: versioned,
  attributes on the marker, matched by token regex, deliberately tolerant of transport mangling.

`:vN` carries over verbatim, including the rule that it is bumped only when the shape changes.

## The surprising half: absence is the fourth signal

A step that reaches **any** conclusion emits a line. So **no line means the process died without
concluding** — which is precisely `infra`, and it requires no cooperation from a step that is being
OOM-killed, disconnected, or destroyed underneath. `full-gate` already reasons this way one level
down: *"if there are none, you are looking at output from something that is not a conforming gate,
and the run is inconclusive."*

The consequence is worth stating plainly, because it is what makes the design cheap: **`infra` is
never something a step must remember to report.** The three outcomes a step actually emits are
`success`, `gate-red` and `blocked-on`.

## The trade-off we accepted

**The producer is a model, and the precedent's producer was a script.** `GATE-STEP:` comes from a
shell script, which cannot accidentally emit one. A `LANE-STEP:` line comes from a model whose
stdout also carries its own prose — so it can emit the marker while explaining the marker, echo an
example out of its own instructions, or emit two. `design-multi` has already been bitten by the
weaker form of this, where a tracker's round-trip inserted a blank line between marker and heading.

This is a real weakness in the analogy and it is not fully mitigated. What the design does about it:
**parse the last match, require it to be the final line, and give the token a shape that does not
occur in prose about it.** What it does not do is pretend a model is a script.

We took it anyway, because the alternative channels are worse. An exit code cannot carry
`slices=3/3` at all, and a result *file* is less durable than stdout for the case the whole design
exists to serve — a fresh agent in a recycled worktree has its own stdout, and may have somebody
else's file.

## `blocked-on` is named here with nothing behind it

The fourth outcome is reachable and carries **no structured payload**. It is named now rather than
deferred because a step that hits an unanswerable fork otherwise has to exit `gate-red`, which
conflates *the gate is red* with *I have a question* — different claims, and the consuming project's
own park state (`Needs a Human`, deliberately not `Blocked`) is built on the difference. Naming the
class costs one enum value. The record behind it — the question, the options, what each implies — is
separate work.

## Status

Accepted. Supersedes nothing. Extends **ADR-003**'s seam discipline: the line and the brief file are
both seams, and neither may name its first consumer — `scripts/test-flow-seams.sh` grows an
assertion that generalises past the single hard-coded string it checks today.
