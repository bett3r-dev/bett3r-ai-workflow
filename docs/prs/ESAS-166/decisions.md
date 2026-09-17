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
