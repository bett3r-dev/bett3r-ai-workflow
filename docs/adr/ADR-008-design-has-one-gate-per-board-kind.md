# /design has one gate per board kind; the combination is an executable block over judged inputs; the map gate never runs unattended

## Context

`/design`'s Board mode used to open with a single check: does this repo have a
`.esas/` directory at all? A `no` skipped the whole section — `"skip this
section entirely"` — before anything about the *design itself* had been read.
That check answers one question, "is the eventstorming board possible here",
and it answered it **before** a second, independent question ever got asked:
"does this design's own shape — an artifact rendered for one owner to click
through, no `.esas/` required — call for a map at all?"

E2 settled that a claude.ai artifact counts as a live map exactly like a board
does: `design-map` re-renders it on each unlock, and a design with open owner
forks has one whether or not the repo carries `.esas/`. Folding that into the
existing `.esas/` check would make the map conditional on eventstorming
machinery it does not need, which is backwards — the map is the wider-reaching
of the two, and the eventstorming board narrower.

`.work/lane.yaml`'s existence marks an unattended lane (D5): a design-lane
agent runs with nobody watching, so anything that could post to a map or a
board there is a **silent no**, not a smaller yes.

## Decision

**Two gates, in order, never merged.** The map gate runs first, over every
repo regardless of `.esas/`; the eventstorming gate runs second, and it is the
one that carries the old `no .esas/` exit, now as a silent no *inside* its own
gate rather than ahead of both. "Say nothing on a no" holds per gate, not once
for the pair — a map gate that also explained the eventstorming no would leak
one board kind's vocabulary into the other's refusal.

**The combination is one executable block, not two paragraphs of prose.**
`commands/design.md`'s Board mode carries a fenced `sh` block after a
`<!-- BOARD-GATE:v1 -->` marker. Its five arguments are the model's own
**judged** values — `open_owner_forks artifact_forks epic_parent lane
esas_capable` — never a preflight key, never a re-read of the tree the model
already has open (`"relevance is not a preflight key"` stays true: this
combinator reads no files). It prints exactly one line:

```
BOARD-GATE:v1 map=yes|no shape=decision|impact|- es=offer|silent
```

following ADR-004's rule that a step reports a line, not an exit code. The
combination:

- `map=yes` iff `lane=0` and `open_owner_forks>=1`.
- `shape=impact` iff map is yes and there is an epic parent; `shape=decision`
  iff map is yes and there is no epic parent; `shape=-` otherwise.
- `es=offer` iff `esas_capable=1` and `artifact_forks>=1`; `es=silent`
  otherwise.

**The map gate never runs unattended.** `lane=0` is one of the two conditions
for `map=yes` by construction, so a lane — anything with `.work/lane.yaml` on
disk — always reads `map=no` regardless of how many forks it found. The design
lane's own forbidden list (`agents/design-lane.md`) enforces the same rule from
the other side: no `map_*` tool but the `get_map` read, no `start_map_session`,
no `design-map` subcommand that renders, posts or ingests answers. Two gates
that agree for two different reasons is the point — a bug in the combinator
alone still leaves the lane's tool list refusing the act.

## Rejected options

- **Prose plus needles.** Two paragraphs describing the same decision table
  this ADR's block encodes, checked only by a human reviewer reading them
  against each other. The combination has five booleans and three outputs —
  exactly the shape a table of assertions verifies mechanically and prose
  verifies by trust.
- **Board-only.** Treat the map as a `.esas/`-scoped concept, gated the same
  way the eventstorming board is. This was live until E2 corrected it: the
  claude.ai artifact is a map with no board and no `.esas/` in sight, so a map
  gate scoped to `.esas/` would leave it permanently `map=no`.
- **One combined gate.** Merge both questions into a single check, the shape
  the original `.esas/` exit already was. Rejected because the suite's own
  regression is exactly this: collapsing the two loses the property that a map
  can be offered in a repo where eventstorming never will be, and a repo where
  eventstorming is possible but no forks exist yet should still see no map.
- **Keeping the `no .esas/` exit first.** The map could never be offered
  anywhere `.esas/` is absent, which is the same defect as board-only under a
  different name — it just keeps the old ordering instead of stating a new
  rule.

## Consequences

A needle-based guard over this file catches the block being **deleted**; it
does not catch the block being **wrong** — a `map=yes` printed for
`lane=1 open_owner_forks=4` reads exactly like a healthy suite until the table
in `scripts/test-esas-design.sh` runs it and shows the value. The oracle for
this ADR is that table, not a grep.

The map gate reads no tree and trusts the model's own judgement of its five
inputs. That means it says yes on almost every attended design that has open
owner forks at all — the gate is permissive by design, and the actual
gatekeeping happens downstream, in whether the design turns out to need any
forks posted at all (D4's ordering: nothing posted before grounding, dependent
forks get a title and no card). A reader expecting the gate itself to be
selective will find it is not; that selectivity was never its job.

## Status

Accepted.
