# ESAS-174 — post-design decisions

## D1 — Plugin version is not bumped in this unit
kind: deviation
step: build · slice: — · decidedBy: orchestrator
sources: [design:block §1 D8, human (orchestrator directive CAMPAIGN-PLAN §5)]
rejected: bump plugin.json per D8 — the campaign takes one bump at /merge-multi
supersedes: —
The block's D8 says bump; the fleet directive says do not. `scripts/check-plugin-version-bump.sh` fails deliberately on this branch.

## D2 — select's unreadable inputs degrade to the silent artifact row, never an error
kind: silent-seam
step: build · slice: S1 · decidedBy: executor
sources: [design:block §1 D2 rows 6/10, code:BoardStatus type guard (esas@de920db packages/sticky-notes-board/src/vite-plugin-esas-fs/board-identity.ts:321)]
rejected: outcome=error on a non-JSON board.json / start.json — would stop a design over a flaky probe
supersedes: —
Empty/non-JSON/non-object board.json reads as board-off; unparseable start.json as start-failed; a board without repoPath as board-other-repo; status ok neither true nor false as mcp-error. missing start.json at --phase start is checked after rows 0-1 and is outcome=error (P1). Tool names match bare or mcp__<server>__-prefixed.

## D3 — Row order 6 vs 7 cannot be pinned by an input
kind: shipped-finding
step: build · slice: S1 · decidedBy: verifier
sources: [code:select (plugins/bett3r-ai-workflow/scripts/design-map.py)]
rejected: —
supersedes: —
Row 6 (no board) and row 7 (board repoPath) cannot both fail on one input; every other adjacent pair is pinned by a two-row precedence case. The no-pwd.txt fallback tests do not separately bite on the logical ($PWD) vs physical (realpath) element — both mutations stayed green; production code is correct, left as follow-up.
