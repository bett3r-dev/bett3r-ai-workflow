# ESAS-166 — decisions after the design

## D1 — The map-only owner rule compares mapId exactly with the normalised item id
kind: silent-seam
step: build · slice: 1 · decidedBy: verifier
sources: [code:ownership (plugins/bett3r-ai-workflow/scripts/work-docs-path.py), code:project out["mapId"] = ticket (plugins/bett3r-ai-workflow/scripts/design-map.py), design:ESAS-166 R1, design:ESAS-162 decisions D6]
rejected: normalise the stored mapId — `project` stamps the raw --ticket, so normalising would widen adoption to maps not stamped for this id; fails-safe direction preferred
supersedes: —
`design-map project --ticket '#301'` stamps `#301`, which reads `unowned` (a stop, never an overwrite). Fleet Jira keys are already normalised, so the provisioned path matches. A broken map with a matching mapId reads `none` and Step 4's render then refuses it.

## D2 — /design Step 4's owner list restated so none/unowned agree with item 1
kind: silent-seam
step: build · slice: 1 · decidedBy: verifier
sources: [code:commands/design.md Step 4 owner list]
rejected: —
supersedes: —
Fix round 1 (design-silent): `owner=none` had been defined only as "the folder does not exist", contradicting the provisioned-map rule two lines below.

## D3 — The provisioner's map carry is a byte copy described in prose, not a `design-map write`
kind: silent-seam
step: build · slice: 2 · decidedBy: verifier
sources: [adr:ADR-006 (names the provisioner's copy, byte-identical), code:scripts/test-design-snapshot.sh redirect grep]
rejected: `design-map write <dst> < <src>` — stricter but not required; a bad map already fails closed at /design Step 4's render
supersedes: —
The ADR-006 grep is not tripped and no allowlist was widened. The grep cannot see a copy described in prose; slice 6's ADR section states the copy is the sanctioned door.

## D4 — A carried lane map is frozen; stale equal-count reuse is closed only for the single flow and a lost lane
kind: silent-seam
step: build · slice: 2 · decidedBy: verifier
sources: [design:ESAS-166 block D9, design:ESAS-166 R2, design:ESAS-162 decisions D7]
rejected: re-author on a lane re-run — destroys the owner's answers the map carries
supersedes: —
Fix round 1 (design-silent): lane.yaml keeps `carried` after the first /design commit, so a lane re-run reuses the map; a fork-altering design change escalates to a /design-multi re-run.

## D5 — The carry copies unconditionally when the projection exists
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:agents/provisioner.md "Carry the unit's map"]
rejected: —
supersedes: —
On a reused worktree that already commits docs/prs/<id>/map.json the copy overwrites it uncommitted; lanes are fresh by construction, so not a blocker. Follow-up only.

## D6 — Subjects are computed by a stdlib helper, not a design-map verb
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [design:ESAS-166 block AC4 ("the build picks one"), code:plugins/bett3r-ai-workflow/scripts/design-multi-subjects.py]
rejected: `design-map group` — design-map owns map.json; grouping reads ticket snapshots and never touches a map
supersedes: —
`design-multi-subjects group <units-dir> [--seams] [--prior]` prints JSON then `DESIGN-MULTI-SUBJECTS:v1`; it never writes run.yaml (the orchestrator is the single writer, D4).

## D7 — Seam proposals override the epic default; fingerprint hashes the inputs; asked counts changed or new subjects
kind: silent-seam
step: build · slice: 3 · decidedBy: verifier
sources: [design:ESAS-166 block D2, D4, Fork 1]
rejected: hash the resulting subjects — a changed parent that happens to regroup identically would reuse silently
supersedes: —
A proposal's units leave their default subject; an emptied default disappears; a partial one keeps its epic id. Fingerprint lines: `unit <id> parent <EPIC|->` sorted, then `seam <id> <units>` sorted. `asked` = current subjects with no identical prior (id, basis, units); vanished priors are not asked. Fix round 1 (oracle-wrong): parent keys were hashed but untested.

## D8 — `parent:` is read only from the snapshot's header block
kind: silent-seam
step: build · slice: 3 · decidedBy: verifier
sources: [code:.work/units/<id>.ticket.md snapshot shape (title, Status:, blank, body)]
rejected: match anywhere at column 0 — pasted YAML in a description would regroup a ticket
supersedes: —
Header block = lines up to the first blank line; first column-0 `parent: <KEY>` wins. /design-multi step 0 writes the line there (slice 5).

## D9 — AC1/AC3 fixtures use the built verbs; count misses assert outcome=error
kind: deviation
step: build · slice: 4 · decidedBy: orchestrator
sources: [design:ESAS-166 C1, C2, docs/prs/ESAS-178/decisions.md D13]
rejected: assert the block's `ingest`/`outcome=fail` — names ESAS-178 did not ship; ESAS-178's names govern per the block's own risk note
supersedes: —
Fragments are per-ticket fork sets composed into 7 subject maps (10 tickets); no merge verb exists. The one-answer-path terminal row carries no `map` key, an allowed variant (SKILL.md: an answer with no map applies); D5's orchestrator writes rows with the map id. Cross-map rejection is covered by existing rows.

## D10 — `design-map select` is named with an artifact fallback until ESAS-174 ships it
kind: false-premise
step: build · slice: 5 · decidedBy: orchestrator
sources: [code:VERBS (plugins/bett3r-ai-workflow/scripts/design-map.py) has no select, design:ESAS-166 block D11, E19]
rejected: omit select — AC2 requires the token and D11 owns the call shape
supersedes: —
`ticketRefs` is written only when select returns target=board, which cannot happen at this base.

## D11 — The orchestrator composes a subject map in memory from unit fragments and pipes it to `write`
kind: silent-seam
step: build · slice: 5 · decidedBy: verifier
sources: [code:project multi-input rules (design-map.py), skill:design-map SKILL.md (write does not merge; render --stack refuses ungrounded), adr:ADR-006]
rejected: a merge verb — out of scope (ESAS-178 owns verbs); per-subject answers dirs — one shared <run>/answers/ is safe via otherMap=
supersedes: —
Forks concatenated in unit order (duplicate id stops), nodes deduped by id (conflict escalates), mapId <S>, grounded/shape must agree, validate then write. The lane fragment is a full structureVersion 2 map with cards (never title-only; --final refuses title-only-open). Fix round 1 (design-silent).

## D12 — The one-answer check reads `decisions --closed`'s verdict line, not its exit code
kind: deviation
step: build · slice: 5 · decidedBy: verifier
sources: [adr:ADR-004, design:ESAS-166 block D5 ("exits 0")]
rejected: the block's "the one-answer check exits 0" — ADR-004
supersedes: —
`outcome=ok verb=decisions open=0` proceeds; `outcome=fail reason=open-forks` stops fold-back.

## D13 — Lane fragments are `shape: decision`
kind: shipped-finding
step: build · slice: 5 · decidedBy: verifier
sources: [code:commands/design.md (an epic parent suggests the impact shape), schema:mapShape impact|decision]
rejected: per-subject shape — unspecified by the block; the agree-rule would need a choice before lanes run
supersedes: —
An epic subject drawn as a decision tree bends /design's shape guidance without breaking anything. Follow-up.
