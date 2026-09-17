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
