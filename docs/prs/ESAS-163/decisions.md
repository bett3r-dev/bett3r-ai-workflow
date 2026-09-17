# ESAS-163 — decisions after the design

## D1 — map-tree validates through the sibling launcher, never PATH
kind: deviation
step: design · slice: 1 · decidedBy: lane
sources: [code:bin/design-map, non-repo read: which design-map (plugin cache 0.81.0 lacks write/validate)]
rejected: PATH lookup — resolves to the installed plugin cache, whose design-map predates the v2 verbs
supersedes: —
The block's D1 says "calls design-map validate as a subprocess"; the executable resolved is `<plugin>/bin/design-map`, verified by a failing fake on PATH.

## D2 — Rendering details D8 leaves open
kind: silent-seam
step: build · slice: 1 · decidedBy: executor
sources: [design:block D8, code:render_md (plugins/bett3r-ai-workflow/scripts/map-tree.py)]
rejected: —
supersedes: —
`###` per fork; a status tag line then `Why:`; an open fork reads `OPEN — recommended: <label>` with no option list; rejected lines only on decided forks; missing rejectedBecause → "no reason recorded"; empty restsOn on a card-less fork → "waits on an unrecorded fork". Moot is checked before card-less (verifier finding, fix round 1: a card-less moot fork rendered LOCKED).

## D3 — Unspecified refusals and region mechanics
kind: silent-seam
step: build · slice: 1 · decidedBy: executor
sources: [design:block D3/D4/F2]
rejected: —
supersedes: —
Error verdicts omit counts when no projection was computed; `gen` mismatch → `stale` with no extra reason (a hand edit inside an old-gen region is overwritten, as D2 allows — named in ADR-007); `--insert-after` exact-line match, absent → `heading-not-found`; `multiple-regions`, `region-unterminated` refuse; a second displace inserts the newest section directly after the end marker, above older ones; regions are LF in CRLF files; the displaced date is local.
