#!/bin/sh
blueprint_gate=${CLAUDE_PROJECT_DIR:-.}/.git
if [ -f "$blueprint_gate" ]; then
  { read -r blueprint_gate <"$blueprint_gate"; } 2>/dev/null
  blueprint_gate=${blueprint_gate#gitdir: }
  case $blueprint_gate in /*) ;; *) blueprint_gate=${CLAUDE_PROJECT_DIR:-.}/$blueprint_gate ;; esac
fi
[ -f "$blueprint_gate/blueprint-connection.json" ] ||
[ -d "${CLAUDE_PROJECT_DIR:-.}/.blueprint" ] || exit 0
#
# SessionStart — "open the BLUEPRINT session channel".
#
# The board wakes an idle session by broadcasting one frame on a WebSocket at
# `/api/blueprint/ws`, which a session holds open with `Monitor`. The mechanism that
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
# Modelled on `blueprint-pending.sh` beside it, and bound by the same two rules,
# for the same reason: there is no per-directory matcher for hooks, so this
# runs at the start of **every session in every repo** where the plugin is
# enabled, including every fleet worktree.
#
#   * **The gate above is the whole program, most of the time.** No connection
#     record in this checkout's git dir and no `.blueprint/`, no work: two `test`s
#     (a `read` of the one-line `.git` file in a linked worktree), no process
#     started, then gone. The record is looked for first because a fleet
#     worktree has no `.blueprint/` (it is gitignored) but has a git dir of its
#     own, which is where `/blueprint connect` puts the record (BP-277 D7).
#     Everything below it is for a checkout that is designing or connected.
#
#   * **Exit 0 on every path, always.** No `set -e`, no `set -u`, no unguarded
#     read. A hook that throws at session start is a hook that greets the user
#     with a diagnostic.
#
# ## Silence is the safe direction, and it is nearly always the answer
#
# `.blueprint/` existing is **not** sufficient, and this is the load-bearing gate:
# every session in the repo has one, and most of them are not designing. An
# instruction to dial a port is only ever correct when there is something on
# the other end of it that belongs to *this* checkout and has nobody listening.
# So the instruction is emitted in exactly one state:
#
#   | GET /api/blueprint/status says                        | verdict     |
#   |--------------------------------------------------|-------------|
#   | nothing there, timeout, non-200, unparsable      | **silence** |
#   | no curl on this machine                           | **silence** |
#   | a board serving a *different* checkout            | **silence** |
#   | this checkout, `sessions` absent (an older board) | **silence** |
#   | this checkout, `sessions` >= 1                    | **silence** |
#   | this checkout, `sessions` == 0                    | the notice  |
#
# This is deliberately the same verdict table `blueprint-mcp`'s session-channel
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
# recovery for that is the `blueprintSessionChannel` notice `blueprint-mcp` attaches to
# every tool result while the channel is shut — this hook only buys t=0.
#
# ## Hosted rows: a checkout connected to a hosted session (BP-277)
#
# `/blueprint connect` writes `$(git rev-parse --git-dir)/blueprint-connection.json`
# ({host, sessionId, branchAtConnect, connectedAt}), and from then on
# `blueprint-mcp` works on that hosted session, not on a local board. A record
# whose four fields this hook cannot read is no record; so is any record while
# BLUEPRINT_HOST_URL is set in this hook's own environment, because env vars
# override it in blueprint-mcp too. The hook cannot see a BLUEPRINT_HOST_URL set
# only in blueprint-mcp's `.mcp.json` env block. With no
# record the hook runs the table above and its output is what it was before
# BP-277, byte for byte (scripts/test-blueprint-design.sh pins both).
#
# With one, the local table is skipped, and:
#
#   | state                                              | prints                       |
#   |----------------------------------------------------|------------------------------|
#   | HEAD is not on branchAtConnect                     | the one-line reminder (F2)   |
#   | `blueprint listen --probe` exits 0 (a listener)    | nothing more                 |
#   | it exits non-zero, hangs past 3 s, or no CLI       | the listen instruction       |
#
# The listen instruction is a `Monitor` command on `blueprint listen`, never a
# `Monitor` ws URL at the host: the ws form carries no Authorization header and
# cannot ack (plugin ADR-018). Instructing when the probe cannot answer is the
# opposite of the local table's default, on purpose: a second listener costs a
# duplicate ring line, a missing one leaves this laptop deaf to its own Asks.

blueprint_root=${CLAUDE_PROJECT_DIR:-.}
blueprint_port=${BLUEPRINT_BOARD_PORT:-3727}

blueprint_record=''
if [ -z "${BLUEPRINT_HOST_URL:-}" ] && command -v git >/dev/null 2>&1; then
  blueprint_git_dir=$( git -C "$blueprint_root" rev-parse --absolute-git-dir 2>/dev/null )
  if [ -n "$blueprint_git_dir" ] && [ -f "$blueprint_git_dir/blueprint-connection.json" ]; then
    blueprint_record=$( tr -d '\n' <"$blueprint_git_dir/blueprint-connection.json" 2>/dev/null )
  fi
fi
# One string field of the record, or empty.
blueprint_field(){
  printf '%s\n' "$blueprint_record" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}
blueprint_host='' blueprint_session='' blueprint_branch_at_connect='' blueprint_connected_at=''
if [ -n "$blueprint_record" ]; then
  blueprint_host=$( blueprint_field host )
  blueprint_session=$( blueprint_field sessionId )
  blueprint_branch_at_connect=$( blueprint_field branchAtConnect )
  blueprint_connected_at=$( blueprint_field connectedAt )
fi

if [ -n "$blueprint_host" ] && [ -n "$blueprint_session" ] && [ -n "$blueprint_branch_at_connect" ] && [ -n "$blueprint_connected_at" ]; then
  # F2 = A: stay on the session and say so. The sentence is blueprint-mcp's
  # (connection.ts, `reminder`), copied so both surfaces read the same.
  blueprint_head=$( git -C "$blueprint_root" symbolic-ref -q HEAD 2>/dev/null )
  blueprint_branch=${blueprint_head#refs/heads/}
  if [ "$blueprint_branch" != "$blueprint_branch_at_connect" ]; then
    if [ -n "$blueprint_branch" ]; then
      blueprint_here="branch $blueprint_branch"; blueprint_switch_to="$blueprint_branch's session"
    else
      blueprint_here='a detached HEAD'; blueprint_switch_to='another session'
    fi
    printf 'blueprint: This checkout is on %s, but Blueprint is connected to the session for branch %s; your Asks still ring here for %s. Run /blueprint connect to switch to %s.\n' \
      "$blueprint_here" "$blueprint_branch_at_connect" "$blueprint_branch_at_connect" "$blueprint_switch_to"
  fi

  # The host's own answer to whether this member's Asks ring a laptop
  # connection (`blueprint listen --probe`, exit 0 when they do), cut off at
  # 3 s so the hook stays inside its 5 s budget.
  blueprint_listening=no
  if command -v blueprint >/dev/null 2>&1; then
    blueprint listen --probe --host "$blueprint_host" --session "$blueprint_session" >/dev/null 2>&1 </dev/null &
    blueprint_probe_pid=$!
    ( sleep 3; kill "$blueprint_probe_pid" 2>/dev/null ) >/dev/null 2>&1 </dev/null &
    blueprint_timer_pid=$!
    wait "$blueprint_probe_pid" 2>/dev/null && blueprint_listening=yes
    kill "$blueprint_timer_pid" 2>/dev/null
  fi
  if [ "$blueprint_listening" != yes ]; then
    printf 'blueprint: this checkout is connected to hosted session %s at %s, and no laptop connection of yours holds its summon socket, so your Asks go to the hosted agent instead of here. Start the listener now, and let the turn end: Monitor({ command: "blueprint listen --host %s --session %s", persistent: true }). If it ends NOT_SIGNED_IN or LISTEN_REFUSED, ask the user to run ! blueprint login --host %s; /blueprint status says more.\n' \
      "$blueprint_session" "$blueprint_host" "$blueprint_host" "$blueprint_session" "$blueprint_host"
  fi
  exit 0
fi

# The local table is for a design layer only: a checkout that passed the gate
# on an unusable record alone stops here, as it did before BP-277.
[ -d "$blueprint_root/.blueprint" ] || exit 0

# No curl, no probe, and no guess. Reporting "open the channel" unprobed would
# be an instruction to dial a port nothing is on, in every session in the repo.
command -v curl >/dev/null 2>&1 || exit 0

blueprint_body=$( curl -fs --max-time 2 "http://127.0.0.1:$blueprint_port/api/blueprint/status" 2>/dev/null )
[ -n "$blueprint_body" ] || exit 0

# Which checkout the board serves is not a question about how it spells the
# path or serialises the answer. The board resolves symlinks and a shell does
# not (`/tmp` is `/private/tmp` on macOS), so both spellings of this project
# root are tried, spaced and compact — the same match `/design`'s preflight
# makes. Anything that does not match is a foreign board, which is silence.
blueprint_serving=no
blueprint_logical=$( CDPATH= cd -- "$blueprint_root" 2>/dev/null && pwd )
blueprint_physical=$( CDPATH= cd -- "$blueprint_root" 2>/dev/null && pwd -P )
for blueprint_path in "$blueprint_logical" "$blueprint_physical"; do
  [ -n "$blueprint_path" ] || continue
  case $blueprint_body in
    *"\"repoPath\":\"$blueprint_path\""*|*"\"repoPath\": \"$blueprint_path\""*) blueprint_serving=yes ;;
  esac
done
[ "$blueprint_serving" = yes ] || exit 0

# Zero, and only a literal zero. A missing field never reaches this test, which
# is the "unknown, never zero" rule spelled as code rather than as a comment.
case $blueprint_body in
  *'"sessions":0'*|*'"sessions": 0'*) ;;
  *) exit 0 ;;
esac

printf 'blueprint: the board is serving this repo and NO session is holding the summon channel open, so the "Ask Claude" button cannot reach anyone. Open it now, and let the turn end: Monitor({ ws: { url: "ws://127.0.0.1:%s/api/blueprint/ws" }, persistent: true })\n' "$blueprint_port"
exit 0
