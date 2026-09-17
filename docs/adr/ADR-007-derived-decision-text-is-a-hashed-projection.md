# Derived decision text is a hashed per-ticket projection of map.json, in a region separate from the dispatch marker; a tampered region is displaced in git and stops the item in Jira

ADR-006 made `map.json` the single, program-written record of a design's forks. The *prose* of those
decisions — the "Resolved decision tree" in `docs/prs/<id>/design.md` and in a `/design-multi`
ticket block — was still copied from the map by hand. A hand edit to that prose, or an owner
overturning a fork in the map after the prose was written, left the two disagreeing with nothing to
notice it. This ADR records how ESAS-163 closes that: the decision text is generated from the map,
carries hashes that tell the two kinds of divergence apart, and has one rule per surface for what
happens when a human edited it anyway.

## Decision

**Decision text is a generated region, written by one program: `bin/map-tree`.** It renders the
projection of `map.json` for one ticket — the forks whose `tickets` contain that key, in map order —
between a region pair:

```
<!-- map-tree:v1 ticket=<KEY> gen=1 src=sha256:… out=sha256:… -->
`map-tree:v1 ticket=<KEY> gen=1 src=sha256:… out=sha256:…`
…generated body…
`/map-tree:v1`
<!-- /map-tree:v1 -->
```

`map-tree render|write|check --map <map.json> --ticket <KEY> [<file>] [--dialect md|jira]
[--insert-after <heading>] [--on-tamper refuse|displace]` ends in a `MAP-TREE:v1 outcome=…` verdict
line (ADR-004). `write` touches only the bytes of an existing pair, or inserts one under
`--insert-after`; a file with neither is refused `reason=no-region` and left unchanged, so a legacy
block is never rewritten.

**The region is not a second dispatch marker.** `design-multi:resolved:v2` stays the only line
`/start-multi` reads. `map-tree:v1` is an inner region, unversioned with respect to the
block: its `:v1` is its own, and adding it did not bump `:v2`.

**Two hashes, two different failures.**

- `src=` hashes the canonical JSON (sorted keys, compact separators, UTF-8) of *this ticket's
  projection*. When it no longer matches the map, the region is **stale**: the map moved (a fork was
  overturned, answered or re-attributed) and the text has not caught up. Stale is the expected state
  after an owner answer, and `write` simply regenerates it. Because the hash covers the projection
  and not the whole file, overturning ticket A's fork stales A's region only.
- `out=` hashes the generated body (LF, trailing whitespace stripped, no edge blank lines). When the
  body no longer matches its own `out=`, the region is **tampered**: someone edited the generated
  bytes. `check` tests tamper before staleness, so an edited region over a moved map reports
  `tampered`.

`check` exits 0 fresh, 1 stale or tampered, 2 on an error. A non-zero `check` is never read as fresh:
a lane building over a stale region would build an overturned decision.

**`gen=` is the generator's format version.** A region whose `gen` differs from the running
generator's reads `stale`, not `tampered`, and `write` re-renders it. The consequence is deliberate
and worth naming: a hand edit inside an old-`gen` region is **overwritten without being displaced**,
because the old body's `out=` is not compared once the format changed.

**The file's author generates; the tracker writer only checks.** `/design` Step 4 and the
`/verify-build` Step 5a2 refresh run `map-tree write --on-tamper displace` on `design.md` in the same
commit as `map.json`. `/design-multi` fold-back writes a `<id>.ticket-block.md` region with
`map-tree write --dialect jira` from the unit's projection. `tracker-writer`, which decides nothing
about content, runs `map-tree check` in its preflight beside `resolved-marker-lint` and refuses the
item on any non-zero exit.

**A tampered region: displaced in git, stops the item in Jira.**

- **`design.md` (md dialect): displace.** `--on-tamper displace` moves the tampered body verbatim
  under `### Displaced from generated section (<YYYY-MM-DD>)` directly after the region's end
  marker, regenerates the region, and reports `outcome=displaced`, exit 0. The edit is kept, in git,
  and `/verify-build` names it in the PR body (`map-tree: displaced`). Rejected: stopping the lane
  with a recovery command — it halts an unattended fleet for a case git already makes recoverable.
  Without the flag, `refuse` (the default) exits 1 `tampered` and leaves the file byte-identical.
- **Jira (jira dialect): stop.** `--dialect jira --on-tamper displace` is refused unconditionally,
  `reason=displace-not-allowed-jira`. No lane owns the Jira write, so the tracker writer's stop
  contract governs: the item is reported, never silently rewritten.

**Jira tamper is judged against the local source, not by hashing fetched text.** The markdown → ADF
→ markdown round trip is lossy, so a hash over the fetched description would read a benign
round-trip change as tampering. The local block file is `check`ed before the write, and the write is proved by the tracker
writer's whole-body readback diff. An edit made in the Jira UI is caught only at the **next** write,
when the tracker writer's step 0 re-read diffs the fetched region against the local source it was
written from; a difference beyond the known round-trip markup stops the item. Rejected: hashing a
normalized fetched form — normalization erases the line between a benign `*`→`_` and a fatal one.

**The jira dialect is pre-compressed and ADF-safe** — flat bullets, no tables, paths, globs and
dunders in inline code, no bold span across lines — so the tracker writer's
`CONTENT_LIMIT_EXCEEDED` compression skips the region. If the hand-written parts cannot fit, the item
is refused; the region is never trimmed.

**Read precedence.** Where a committed or provisioned `map.json` exists, it governs and the block's
decision text is its projection. `/design` Step 2 notes a `check` mismatch as a correction, and Step
4 regenerates the text.

## Consequences

- A hand edit to generated decision text is never silent: `check` reports it, a `design.md` run
  moves it into a dated displaced section visible in the PR diff, and a Jira write stops. Displace
  keeps a contrary human edit as prose while the map governs — visible, not reconciled.
- **Limit (F3 = D+): a Jira region's `src=` cannot be re-verified once the run dir is gone.** A
  `/design-multi` ticket's map lives in `<run>/units/<id>.map.json` until the provisioner copies it
  into a lane and the lane's Step 4 commits `docs/prs/<id>/map.json`. Between a lost run dir
  (`mapProvenance: lost`, ADR-006) and that first commit there is no map to recompute `src=` from;
  after it, the committed map is the verifier.
- An edit made in the Jira UI is detected only at the next write, and whether a difference is benign
  round-trip markup stays an agent judgment.
- The projection trusts `tickets`: a fork attributed to the wrong ticket renders fresh and wrong.
- A `gen` bump re-renders every region on its next `write`, and overwrites any hand edit sitting in
  an old-`gen` region (above).

## Status

Accepted. Extends ADR-006's single-writer rule from `map.json` to the prose derived from it, and
ADR-004's verdict-line contract to `map-tree`. Supersedes no ADR.
