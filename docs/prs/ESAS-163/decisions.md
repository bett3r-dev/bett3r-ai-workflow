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

## D4 — Jira dialect layout and escaping, where D6 lists properties only
kind: silent-seam
step: build · slice: 2 · decidedBy: executor
sources: [design:block D6/F2, code:render_jira, jira_text (plugins/bett3r-ai-workflow/scripts/map-tree.py)]
rejected: trimming content to "pre-compress" — D6 says the region is never trimmed
supersedes: —
One one-line bold bullet per fork plus `Why:` and `Rejected —` bullets; tokens matching dunder/glob/path are code-spanned (also wraps "why?", "and/or" — cosmetic); whitespace runs incl. newlines collapse to one space (verifier F1: a newline crashed the renderer); backtick-bearing words are never wrapped and a stray backtick switches generated spans to a double fence (verifier F2/F3). `_x_`, inner `|`, mid-line `#` are not escaped (every line starts `- `). Jira's acceptance of a double-backtick span is unverified against live ADF — check at first live use.

## D5 — The Jira displace refusal is unconditional and first
kind: silent-seam
step: build · slice: 2 · decidedBy: executor
sources: [design:block F2 (Jira = A)]
rejected: refusing only when a tamper is found — would let a fresh-region call succeed with a flag the dialect forbids
supersedes: —
`--dialect jira --on-tamper displace` exits 2 `reason=displace-not-allowed-jira` before the file or map is read.

## D6 — /design requires the literal `## Resolved decision tree` heading
kind: silent-seam
step: build · slice: 3 · decidedBy: verifier
sources: [code:commands/design.md Sections list, code:docs/prs/{ESAS-161,ESAS-162,ESAS-178,XL-27}/design.md headings, code:map-tree --insert-after]
rejected: fuzzy heading match in map-tree — a guess at which heading is "the" tree; per-folder heading discovery — undeclared contract
supersedes: —
`--insert-after` is exact; older design docs use heading variants. /design rewrites design.md in full every pass, so the required line is written before map-tree inserts. /verify-build's refresh does not rewrite design.md: a missing heading there is flagged `heading-not-found`, nothing committed.

## D7 — tracker-writer's map-tree check runs only on a source that carries a region; the map is read beside the source
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [design:block D5 "non-zero refuses the item", code:agents/tracker-writer.md preflight]
rejected: check every source — addenda, filed tickets and legacy blocks have no region and would always refuse
supersedes: —
Map path assumed `units/<id>.map.json` beside the source; the design-multi brief to tracker-writer does not carry it yet (follow-up, owner ESAS-166 which owns fold-back). A block that should carry a region but lacks one passes preflight — accepted risk.

## D8 — Step 0 "last local source" is the local region whose out= matches the fetched marker
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [design:block D7]
rejected: hashing a normalized fetched form — rejected by D7 itself
supersedes: —
No local source with that `out=` stops the item; this can stop a legitimate regeneration (conservative direction).

## D9 — plugin.json not bumped; AC8 fails by directive
kind: waiver
step: build · slice: 3 · decidedBy: human
sources: [human (orchestrator directive, CAMPAIGN-PLAN §5), design:block §2, §3 AC8]
rejected: bump per block — the single bump happens at /merge-multi
supersedes: —

## D10 — Finding: the ESAS-156 epic oracle expects map-tree:begin/end markers
kind: shipped-finding
step: build · slice: 3 · decidedBy: verifier
sources: [code:scripts/oracles/epic-esas-156.sh:223-228]
rejected: edit the epic oracle here — owned by no unit, out of scope
supersedes: —
The shipped pair is `map-tree:v1` / `/map-tree:v1`; that stage will report `region-markers-absent` (loud, not a silent pass) until the oracle is updated. Routed to the orchestrator.
