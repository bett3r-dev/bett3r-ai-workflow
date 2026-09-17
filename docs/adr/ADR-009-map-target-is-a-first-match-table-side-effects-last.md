# A map's target is chosen by a deterministic first-match table; every side effect runs last; a design keeps the surface it started on

`/design`'s map now has two surfaces that carry the same forks: a live esas board (`.esas/`,
`mcp__esas__*` tools, a running board process) and a claude.ai artifact page (`design-map render`).
Before ESAS-174 the choice between them was made by prose scattered across the skill and the board
setup file — "if the board seems to be up, use it" — read informally, at a point in the session
where the agent had already, in the course of finding out, done things a probe should never do: it
had called `start_map_session`, which creates `.esas/` on disk. A repo that was never going to get a
board ended up with the directory anyway, because the check that would have said no ran *after* the
side effect that only a yes should trigger.

## Decision

**`design-map select` is the one place the target is decided, and it is pure over files.** It reads a
captures directory (`tools.txt`, `status.json`, `board.json`, `start.json`, optional `pwd.txt`) built
by the agent from what it already observed in the session — no network call, no subprocess, no MCP
tool of its own. Rows 0-8 of `design.md`'s decision tree (map pinned, fleet lane, tool list,
capabilities, ok-ness, board presence, board repo, board kinds) are evaluated in a fixed order and the
**first** row that fails to hold wins: its reason is the answer. Nothing past the first match is
looked at, and nothing about a later row's shape leaks into an earlier reason.

**Side effects run last, and only after every read-only row has passed.** `select --phase probe`
answers `board-candidate` without ever suggesting the agent call anything. Only when a design is a
`board-candidate` does the agent call `start_map_session` — the one write in the whole path, because
it is the call that creates `.esas/` — and only then does `select --phase start` re-run rows 0-8
(a stale probe is never promoted) and apply rows 9-11 over the fresh `start.json`. A repo that fails
any earlier row never sees `start_map_session` called on its behalf, so it never gets an `.esas/` it
did not ask for.

**A design keeps the surface it started on.** Once a map's `target` is written as `artifact`, every
later `select` call short-circuits at row 0 and returns `artifact` with `probe: skipped` — no re-read
of the current session's tools or board state can move it. A `board` pin is not final in the same way:
it is a *soft* pin that re-probes at the next sync point, and a probe failure there is D5's territory
(a board that died mid-sitting), not this table's. The reason is E17: moving a design from the
artifact to a board mid-sitting would need the owner's answers carried across, and every way to carry
them either turns owner decisions into AI claims or needs a new status. The board is offered, as
information, for the next design instead.

## Context

`.esas/`'s own creation is not inert: `plugins/bett3r-ai-workflow/hooks/esas-session-channel.sh:2` is a
guard clause, `[ -d "${CLAUDE_PROJECT_DIR:-.}/.esas" ] || exit 0` — the hook arms only once `.esas/`
exists, on the next `SessionStart` after the directory appears (verified by reading the file: line 2
is exactly that test, ahead of the rest of the script). Calling `start_map_session` early, as a
diagnostic rather than a committed choice, therefore does not just leave a stray folder — it changes
what the *next* session in this repo does before a human ever decided this design wanted a board at
all.

## Rejected options

- **Prose rules in SKILL.md (D1).** Rejected: a rule the agent reads and applies is not
  unattended-testable — no fixture can prove the agent picked the row the prose meant.
- **A shell script doing the `curl` (D1).** Rejected: it still cannot read MCP (the tool list and
  `status` body only exist inside the session), so the table would be split between a script and the
  agent.
- **Calling `start_map_session` unconditionally before the first map write (D2-order).** This was
  ESAS-170's original obligation, retargeted to ESAS-174 by P6. Rejected: it creates `.esas/`, which
  arms `hooks/esas-session-channel.sh:2` for every later session, in repos that never wanted a board.
- **Pinning, option B: the AI replays the owner's answers onto the board (E17).** Rejected: owner
  decisions would become AI claims, and O3 allows the AI only `decided(recommendation)`.
- **Pinning, option C: "decided elsewhere" context cards (E17).** Rejected: it needs a new status,
  against the standing decline P3.

## Consequences

A repo that will never carry a board (no MCP tools, or MCP with no `map` capability) never has
`.esas/` created on its behalf: `select --phase probe` returns `artifact` at row 2 or 3 and the agent
never calls `start_map_session`. The oracle is `scripts/test-design-map.sh`'s `select` cases, run over
`scripts/fixtures/design-map/select/`, plus decisions.md D3's finding that rows 6 and 7 cannot both fail on the same
input (left as a follow-up, not a defect in this ADR's decision).

## Status

Accepted.
