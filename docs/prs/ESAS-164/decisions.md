# ESAS-164 — post-design decisions

## D1 — plugin.json is not bumped on this unit branch
kind: deviation
step: design · slice: — · decidedBy: lane
sources: [design:block D9, .work/lane.yaml preconditions (CAMPAIGN-PLAN §5)]
rejected: bump per block D9 — the fleet's single bump happens at /merge-multi; N unit bumps collide
supersedes: —
The block's D9 and AC8 name `check-plugin-version-bump.sh` passing; on this branch it fails deliberately.

## D2 — the BOARD-GATE marker is an HTML comment line, matched exactly
kind: silent-seam
step: build · slice: S1 · decidedBy: executor
sources: [design:E4, code:preflight extraction (scripts/test-esas-design.sh)]
rejected: bare `BOARD-GATE:v1` text as marker — any prose mention would arm the extraction
supersedes: —
`<!-- BOARD-GATE:v1 -->` does not render and cannot be matched by prose that names the line. Verifier ACCEPT.

## D3 — the combinator does not validate its arguments
kind: silent-seam
step: build · slice: S1 · decidedBy: executor
sources: [design:E4 ("judged values")]
rejected: argument validation — not in the design; a bad arg is a loud `[` stderr error, not a wrong verdict
supersedes: —
Verifier ACCEPT; exhaustive 72-combination check matched the rule.
