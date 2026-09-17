# One program writes map.json; answers enter only through apply-answers; a fleet ticket's map is carried from the run dir by the provisioner, and a lost run dir is reported, never counted

`/design`'s map — the goal/actor/impact/deliverable tree an owner grills forks on — now has a
committed file: `docs/prs/<id>/map.json`, alongside `design.md`. Once a file is committed, more than
one place can plausibly write it: `/design` Step 4 authors it, a fleet's Phase C produces one per
ticket before any lane exists, and `/verify-build` can in principle refresh a stale one against a
later feed. Three writers of the same file is exactly the shape that produces a silent stale-pair
bug (`design.md` says one thing, `map.json` another) the moment any two of them disagree about when
they ran. This ADR is the rule that keeps that from happening as the third writer (`/verify-build`,
ESAS-162) is added.

## Decision

**Every byte of `map.json` goes through exactly one program: `bin/design-map`.** No command, agent
or skill in this plugin writes the file by any other means — not a heredoc, not a text edit, not an
inline `python3 -c`. Two of `design-map`'s verbs are the only doors in:

- **`design-map write <map.json>`** — the only *structural* authoring path. It takes the full map on
  stdin, runs the same validation `validate` runs, and replaces the file whole. This is how `/design`
  Step 4 creates a map from a drafted tree, and how a refresh (below) replaces a stale one.
- **`design-map apply-answers <map.json> <answers-dir> [--final]`** — the only path by which an
  owner's *answers* (read back from the claude.ai artifact's `db` store) enter the file. It folds
  each `<answers-dir>/<forkId>.json` into the matching fork and nothing else.

`render` and `check-page` only read the file (`render --out` additionally writes the page, never the
map); `count`, `drift`, `candidates`, `check-plan`, `project`, `decisions` are read-only reporters.
`scripts/test-design-snapshot.sh` greps `plugins/bett3r-ai-workflow/{commands,agents,skills}` for any
instruction that writes `map.json` or `map.html` by a path other than through `design-map`, with a
planted positive control (a temp file containing a bare `> docs/prs/X/map.json` redirect) proving the
grep actually bites.

**A fleet ticket's map is carried from the run dir by the provisioner, not re-authored by the lane.**
Under `/start-multi`, Phase C writes `<run>/units/<id>.map.json` via `design-map write` before any
lane worktree exists (ESAS-166). The provisioner copies that file into the lane's
`docs/prs/<id>/map.json`, uncommitted, before the lane's `/design` runs. Step 4 in a lane with an
already-provisioned map **uses it as-is** — validates and renders it, never re-authors it — and
commits it byte-identical alongside `design.md` and `map.html`. The rejected alternative was letting
each lane regenerate its own map from the design block: that reads `decided(recommendation)` fresh in
every lane and falsifies the count the goal-signal line reports, because a fork the owner already
decided would re-render as undecided.

**A lost run dir is reported, never counted as zero.** If the run directory Phase C wrote into is
gone by the time the provisioner looks for it — deleted, or the run never reached Phase C — the
provisioner writes `mapProvenance: lost` into the lane's `.work/lane.yaml` instead of a map file.
`/verify-build`'s goal-signal line (`design-map count <path>/map.json --lane .work/lane.yaml --line`)
reads that marker before anything else and prints `map: owner answers not carried: run dir absent` —
never `0 of M forks answered`, which would read as "the owner answered nothing" rather than "the
answers were never delivered to this lane." The two are different failures with different remedies,
and collapsing them into the same zero would hide which one happened.

## Consequences

- A `map.json` in any commit was written by `design-map`, so its shape is exactly what
  `map-structure.schema.json` and `map.schema.json` allow — there is no second, hand-written source
  of truth to drift against the schema.
- The owner-answer count (`design-map count --line`) and the drift verdict (`design-map drift`) can
  both trust the file's provenance: either it came straight from `apply-answers` folding real answers,
  or it is the byte-identical file the provisioner carried, or its `mapProvenance: lost` line explains
  why neither happened.
- The single-writer rule is a standing constraint on every future map-touching feature in this
  plugin (ESAS-163's map-tree calls, ESAS-164's board mode, ESAS-166's fleet projection, ESAS-174's
  session start): each of them calls `design-map`, none of them writes the file directly. The AC3
  grep in `scripts/test-design-snapshot.sh` is the standing gate that catches a regression.
- The consuming side (esas's `mapSeq`/feed, ESAS-167/169) is out of scope here and does not change
  this decision: until it exists, `/verify-build`'s drift step runs `--no-feed` on every
  invocation. A main checkout reports `skip reason=no-map-feed`; a fleet lane runs the same
  `--no-feed` and the PR names it `fleet-lane-no-feed`. That step is inert, not incomplete — it has nothing
  to compare against yet, and this ADR's rule (one writer, via `design-map`) is what it will refresh
  through once the feed lands.

## Status

Accepted. ESAS-166 appends a section below recording the provisioner's copy step and the
`mapProvenance: lost` marker's exact field, once that unit builds it. Supersedes no ADR; extends
ADR-004's verdict-line contract (`design-map`'s verbs already emit `DESIGN-MAP:v1` lines, never a
bare exit code) to this file's writers, and keeps ADR-005's rule that a work item's committed record
lives beside the code, not only in the PR body — `map.json` is now one more file in that folder.
