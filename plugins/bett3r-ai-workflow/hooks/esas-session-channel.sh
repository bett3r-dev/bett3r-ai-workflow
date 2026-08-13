#!/bin/sh
[ -d "${CLAUDE_PROJECT_DIR:-.}/.esas" ] || exit 0
#
# SessionStart — "open the ESAS session channel".
#
# The board wakes an idle session by broadcasting one frame on a WebSocket at
# `/api/esas/ws`, which a session holds open with `Monitor`. The mechanism that
# preceded it did not fail on its transport; it failed because **its arming
# belonged to a command**. The watcher went up inside `/design`, so it died at
# every session boundary — a resume, a `/handon`, any other session doing
# something else in the repo — and the only recovery was the human remembering
# to ask. This hook is the other half of moving that arming to the *session*:
# `SessionStart` fires for every session in the repo, resumed ones included, so
# the channel can be opened at t=0 without anybody asking.
#
# It emits an instruction, never an action. Opening the socket is a `Monitor`
# call the model makes; a hook cannot make one.
#
# ## Why this file is written the way it is
#
# Modelled on `esas-pending.sh` beside it, and bound by the same two rules,
# for the same reason: there is no per-directory matcher for hooks, so this
# runs at the start of **every session in every repo** where the plugin is
# enabled, including every fleet worktree.
#
#   * **Line 2 is the whole program, most of the time.** No `.esas/`, no work:
#     one `test`, then gone. Everything below it is for the one checkout in a
#     session that is actually designing.
#
#   * **Exit 0 on every path, always.** No `set -e`, no `set -u`, no unguarded
#     read. A hook that throws at session start is a hook that greets the user
#     with a diagnostic.
#
# ## Silence is the safe direction, and it is nearly always the answer
#
# `.esas/` existing is **not** sufficient, and this is the load-bearing gate:
# every session in the repo has one, and most of them are not designing. An
# instruction to dial a port is only ever correct when there is something on
# the other end of it that belongs to *this* checkout and has nobody listening.
# So the instruction is emitted in exactly one state:
#
#   | GET /api/esas/status says                        | verdict     |
#   |--------------------------------------------------|-------------|
#   | nothing there, timeout, non-200, unparsable      | **silence** |
#   | no curl on this machine                           | **silence** |
#   | a board serving a *different* checkout            | **silence** |
#   | this checkout, `sessions` absent (an older board) | **silence** |
#   | this checkout, `sessions` >= 1                    | **silence** |
#   | this checkout, `sessions` == 0                    | the notice  |
#
# This is deliberately the same verdict table `esas-mcp`'s session-channel
# notice runs, and for the same reasons: a notice with no board on the port
# tells every session in every repository to dial a dead address, and one for a
# *foreign* board attaches this session to somebody else's design.
#
# `sessions` absent is **unknown, never zero** — a board that predates the
# channel answers a perfectly valid status without the field and serves no
# socket to open.
#
# Note what is *not* covered, on purpose: a board that is restarted later in
# the session leaves this session deaf, and `SessionStart` has already run. The
# recovery for that is the `esasSessionChannel` notice `esas-mcp` attaches to
# every tool result while the channel is shut — this hook only buys t=0.

esas_root=${CLAUDE_PROJECT_DIR:-.}
esas_port=${ESAS_BOARD_PORT:-3727}

# No curl, no probe, and no guess. Reporting "open the channel" unprobed would
# be an instruction to dial a port nothing is on, in every session in the repo.
command -v curl >/dev/null 2>&1 || exit 0

esas_body=$( curl -fs --max-time 2 "http://127.0.0.1:$esas_port/api/esas/status" 2>/dev/null )
[ -n "$esas_body" ] || exit 0

# Which checkout the board serves is not a question about how it spells the
# path or serialises the answer. The board resolves symlinks and a shell does
# not (`/tmp` is `/private/tmp` on macOS), so both spellings of this project
# root are tried, spaced and compact — the same match `/design`'s preflight
# makes. Anything that does not match is a foreign board, which is silence.
esas_serving=no
esas_logical=$( CDPATH= cd -- "$esas_root" 2>/dev/null && pwd )
esas_physical=$( CDPATH= cd -- "$esas_root" 2>/dev/null && pwd -P )
for esas_path in "$esas_logical" "$esas_physical"; do
  [ -n "$esas_path" ] || continue
  case $esas_body in
    *"\"repoPath\":\"$esas_path\""*|*"\"repoPath\": \"$esas_path\""*) esas_serving=yes ;;
  esac
done
[ "$esas_serving" = yes ] || exit 0

# Zero, and only a literal zero. A missing field never reaches this test, which
# is the "unknown, never zero" rule spelled as code rather than as a comment.
case $esas_body in
  *'"sessions":0'*|*'"sessions": 0'*) ;;
  *) exit 0 ;;
esac

printf 'esas: the board is serving this repo and NO session is holding the summon channel open, so the "Ask Claude" button cannot reach anyone. Open it now, and let the turn end: Monitor({ ws: { url: "ws://127.0.0.1:%s/api/esas/ws" }, persistent: true })\n' "$esas_port"
exit 0
