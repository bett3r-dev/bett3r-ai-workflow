# ESAS-161 — post-design decisions

## D1 — map.json schema shape fixed by the executor
kind: silent-seam
step: build · slice: 1 · decidedBy: executor
sources: [design:map.json contract, code:map.schema.json (plugins/bett3r-ai-workflow/skills/design-map/map.schema.json), code:CONTEXT.md Fork/Actor (map) (esas 1a1d24c), verifier]
rejected: the ESAS-156 prototype's richer cards (use cases, walkthroughs, depends-on, repo tag) — not needed for v0
supersedes: —
The design named the levels but not their shape. Chosen: goal{id,title}, mapActors[], impacts[{mapActor}], deliverables[{impact,forks[]}]; fork {id,title,status,by?,reason?,problem,options[{key,label,recommended?}],recommendation}; additionalProperties:false throughout; impactMap levels minItems 1. Slice 2 and ESAS-167 read this contract.

## D2 — no referential-integrity checks on the map
kind: silent-seam
step: build · slice: 1 · decidedBy: verifier
sources: [code:design-map.py (plugins/bett3r-ai-workflow/scripts/design-map.py), design:C1]
rejected: refusing dangling fork/mapActor references — cost without affecting the fork counts C1 guards
supersedes: —
Only duplicate fork ids are refused. A dangling reference loses a label on the page. ESAS-167 (the board reader) should own integrity.

## D3 — a refusal removes only a page design-map wrote, and never the map
kind: silent-seam
step: build · slice: 1 · decidedBy: verifier
sources: [design:C1 "no page left behind", verifier repro (render victim.json --out victim.json deleted the map)]
rejected: deleting any file at --out — destroyed the author's uncommitted map
supersedes: —
Pages carry <meta name="generator" content="design-map">; remove_page deletes only a file with that marker in its first 4KB. --out resolving to the map is refused (out-is-map). A hand-written file containing the marker is treated as a page.

## D4 — check-page verb added beside render
kind: deviation
step: build · slice: 1 · decidedBy: verifier
sources: [verifier R1]
rejected: a fault-injection switch in production code to test the page gate
supersedes: —
`design-map check-page <map> <page> --expect <n>` runs the payload and page counts over an existing page, read-only. render's own gate is pinned separately by an importlib test.

## D5 — read-only degradation checked by page text only
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:map.html:510-519 (esas 1a1d24c)]
rejected: —
supersedes: —
The oracle cannot execute the page, so the claude.use("db") → null path is asserted by presence. Also: a comment-only answer renders as "done" on the page while the design keeps that fork open — cosmetic in slice 1, must be reconciled in slice 2.

## D6 — esas master moved past the design's grounding commit
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:docs/prs/ESAS-156/map.html:467-474 (esas 1a1d24c), design:grounding 59ab592]
rejected: —
supersedes: —
Re-grounded at 1a1d24c; the answers writer and CONTEXT.md Fork/Actor (map) are unchanged.

## D7 — fork gains an optional `pick` (option key)
kind: deviation
step: build · slice: 2 · decidedBy: executor
sources: [decisions:D1, design:F3, verifier]
rejected: decided(owner) without recording the chosen option
supersedes: —
Amends D1's fork shape so decided(owner) keeps the owner's choice. A hand-written map's pick is not checked against its options (consistent with D2). --final sets pick only when exactly one option is recommended.

## D8 — --final also decides comment-only forks
kind: silent-seam
step: build · slice: 2 · decidedBy: verifier
sources: [design:--final, code:CONTEXT.md "open question" (esas 1a1d24c)]
rejected: keeping commented forks open under --final
supersedes: —
--final is the owner saying they are done; comments are still printed. The skill (slice 3) must resolve printed comments before running --final.

## D9 — an invalid pick on a moot fork refuses the whole run
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:design-map.py fold/docstring, design:open question on re-render (design.md:150)]
rejected: —
supersedes: —
A valid pick on a moot fork is ignored as documented, but a pick that is not an option key refuses with unknown-pick — contradicting the docstring. Also shipped: an in-place write narrows the map's mode to 0600. Both are optional follow-ups.

## D10 — answers dir layout is <answers-dir>/<forkId>.json
kind: silent-seam
step: build · slice: 2 · decidedBy: executor
sources: [code:map.html saveAnswer (esas 1a1d24c), design:answers/<forkId>]
rejected: one aggregate answers.json
supersedes: —
One file per db doc, holding {pick, comment, updatedAt}; dot-files ignored, other entries refused. The slice-3 skill must materialise read_db results in exactly this layout. Unknown-fork answers are refused, not dropped.
