#!/bin/sh
# Oracle for the shipped UserPromptSubmit hook (hooks/esas-pending.sh).
#
# This hook is the one artifact in the plugin that runs *unconditionally, on
# every prompt, in every repo where the plugin is enabled* — there is no
# per-directory matcher. Two failure modes therefore matter more than anything
# it does when it works:
#
#   1. a non-zero exit **blocks the user's prompt** (Claude Code: "Exit code 2 -
#      block processing, erase original prompt"), so every path here asserts
#      exit 0 — including the corrupt and torn inputs;
#   2. a slow path taxes every prompt in every repo, so the absent-`.esas`
#      fast-path is timed.
#
# Fixtures under scripts/fixtures/esas-pending/ were produced by the real
# @bett3r-dev/esas-store — see the README there. They are read-only: each case
# runs against a copy in a temp dir.
#
# Run locally:  sh scripts/test-hooks.sh
# Exit code is non-zero if anything is broken, so CI fails the PR.
#
# HOOK_SH selects the interpreter the *hook* runs under (the suite itself is
# POSIX sh either way). Claude Code spawns it as `sh <script>`, and `sh` is dash
# on Debian/Ubuntu and bash-in-POSIX-mode on macOS, so:
#     for s in sh dash bash; do HOOK_SH=$s sh scripts/test-hooks.sh; done

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
PLUGIN="$ROOT/plugins/bett3r-ai-workflow"
HOOK="$PLUGIN/hooks/esas-pending.sh"
HOOKS_JSON="$PLUGIN/hooks/hooks.json"
FIXTURES="$ROOT/scripts/fixtures/esas-pending"
HOOK_SH=${HOOK_SH:-sh}

TMP=$( mktemp -d "${TMPDIR:-/tmp}/esas-hook-test.XXXXXX" ) || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

passed=0
failed=0

fail(){
  failed=$(( failed + 1 ))
  printf '  \033[31m✗\033[0m %s\n' "$1"
  shift
  for line in "$@"; do printf '      %s\n' "$line"; done
}

pass(){
  passed=$(( passed + 1 ))
  printf '  \033[32m✓\033[0m %s\n' "$1"
}

# Runs the hook against a fresh copy of $1 (a fixture name, or `-` for a repo
# with no .esas at all) and records stdout / stderr / status in $TMP.
run_hook(){
  work="$TMP/work"
  rm -rf "$work"
  mkdir -p "$work"
  if [ "$1" != '-' ]; then
    cp -R "$FIXTURES/$1/.esas" "$work/.esas"
  fi
  # The hook is spawned as `sh <script>` by hooks.json, with CLAUDE_PROJECT_DIR
  # in its environment (Claude Code sets it for every command hook). stdin is
  # the event JSON, which this hook does not read — closed here on purpose, so
  # a future read from it can never hang the prompt.
  CLAUDE_PROJECT_DIR="$work" "$HOOK_SH" "$HOOK" >"$TMP/out" 2>"$TMP/err" </dev/null
  status=$?
}

# assert_case <fixture> <description> <expected-stdout>
assert_case(){
  fixture=$1
  description=$2
  expected=$3

  run_hook "$fixture"
  actual=$( cat "$TMP/out" )
  stderr=$( cat "$TMP/err" )

  if [ "$status" -ne 0 ]; then
    fail "$description" "exit status $status — a non-zero hook BLOCKS the prompt" "stderr: $stderr"
    return
  fi
  # Silence on stderr is part of the contract, not a nicety. A shell diagnostic
  # here means some `test` *failed* rather than compared — and behind `&&` a
  # failed test looks exactly like a false one, so a leak on stderr is the
  # visible half of a decision that silently did not happen.
  if [ -n "$stderr" ]; then
    fail "$description" "wrote to stderr — the hook must degrade silently" "stderr: $stderr"
    return
  fi
  if [ "$actual" != "$expected" ]; then
    fail "$description" "expected: [$expected]" "actual:   [$actual]" "stderr:   $stderr"
    return
  fi
  # One line or none, never more: the injection is telemetry, not a report.
  lines=$( wc -l <"$TMP/out" | tr -d ' ' )
  if [ -n "$expected" ] && [ "$lines" != '1' ]; then
    fail "$description" "expected exactly 1 line of output, got $lines"
    return
  fi
  pass "$description"
}

printf '\nesas-pending hook\n'

if [ ! -f "$HOOK" ]; then
  fail 'the hook script exists' "no file at $HOOK"
else
  pass 'the hook script exists'
fi

# ── The four oracle states ────────────────────────────────────────────────────

assert_case '-' \
  'absent .esas: silent (the fast-path exit, on every prompt in every repo)' \
  ''

assert_case 'pending' \
  'pending semantic human ops: one line, correct count and seq range' \
  'esas: 2 pending (seq 1→4)'

assert_case 'layout-only' \
  'layout-only pending: silent — "moved 14 stickies" is not a design change' \
  ''

assert_case 'corrupt-cursor' \
  'corrupt cursor: exits 0 and degrades to unsynced (everything pending)' \
  'esas: 3 pending (seq 0→4)'

# ── The rest of the contract ──────────────────────────────────────────────────

assert_case 'synced' \
  'synced cursor (byteOffset == size): silent' \
  ''

assert_case 'ai-only' \
  'pending ops are all ai-authored: silent — the count is about the user' \
  ''

assert_case 'stale' \
  'stale cursor (byteOffset > size): reports EVERYTHING pending, from seq 0' \
  'esas: 2 pending (seq 0→2)'

assert_case 'no-cursor' \
  'no cursor at all: nothing has been synced, so everything is pending' \
  'esas: 2 pending (seq 0→3)'

assert_case 'empty-feed' \
  'empty ops.jsonl: silent' \
  ''

assert_case 'nested-author' \
  'an ai op whose payload carries "author":"human" is not counted as human' \
  'esas: 1 pending (seq 1→3)'

assert_case 'torn-tail' \
  'a torn tail is skipped, not counted and not fatal' \
  'esas: 1 pending (seq 1→2)'

# The cursor is written `{ seq, byteOffset, writerId, ts }`, so a truncation in
# the tail leaves *both* contract fields perfect while the document is
# unparseable — the store reads that as unsynced, and so must this. A reader
# that checked only "both fields present" disagreed at 94 of 126 truncation
# points, every time by claiming synced.
assert_case 'torn-cursor-tail' \
  'a cursor torn in its writerId tail: both fields intact, still unsynced' \
  'esas: 3 pending (seq 0→4)'

# `test` does not return false on an operand it cannot parse — it *fails*, and
# behind `&&` that is indistinguishable from false, so the staleness branch
# silently did not fire. Both halves are asserted: the right answer, and silence
# on stderr (checked by assert_case for every case).
assert_case 'cursor-out-of-range' \
  'a byteOffset past 2^63 degrades to unsynced, silently' \
  'esas: 3 pending (seq 0→4)'

# ── Never block a prompt, whatever the input ─────────────────────────────────

printf '\nhardening\n'

hostile_case(){
  work="$TMP/work"
  rm -rf "$work"
  mkdir -p "$work/.esas"
  printf '%s' "$2" >"$work/.esas/ops.jsonl"
  if [ "$3" != '-' ]; then printf '%s' "$3" >"$work/.esas/.claude-cursor"; fi
  CLAUDE_PROJECT_DIR="$work" "$HOOK_SH" "$HOOK" >"$TMP/out" 2>"$TMP/err" </dev/null
  status=$?
  if [ "$status" -ne 0 ]; then
    fail "$1" "exit status $status — a non-zero hook BLOCKS the prompt" "stderr: $( cat "$TMP/err" )"
  elif [ -s "$TMP/err" ]; then
    fail "$1" "wrote to stderr — the hook must degrade silently" "stderr: $( cat "$TMP/err" )"
  else
    pass "$1"
  fi
}

hostile_case 'binary garbage in the feed still exits 0' \
  "$( printf '\001\002\377 not json at all\n{"seq":1}\n' )" '-'
hostile_case 'a cursor that is not JSON still exits 0' \
  '{"seq":1,"ts":"x","author":"human","class":"semantic","verb":"propose","payload":{},"writerSha":"s","writerId":"w"}
' 'not json at all'
hostile_case 'a negative byteOffset still exits 0' \
  '{"seq":1,"ts":"x","author":"human","class":"semantic","verb":"propose","payload":{},"writerSha":"s","writerId":"w"}
' '{ "seq": -5, "byteOffset": -9 }'
hostile_case 'a cursor with no numbers at all still exits 0' \
  '{"seq":1,"ts":"x","author":"human","class":"semantic","verb":"propose","payload":{},"writerSha":"s","writerId":"w"}
' '{}'
hostile_case 'an out-of-range seq still exits 0' \
  '{"seq":1,"ts":"x","author":"human","class":"semantic","verb":"propose","payload":{},"writerSha":"s","writerId":"w"}
' '{ "seq": 9223372036854775808, "byteOffset": 0 }'
hostile_case 'a 40-digit byteOffset still exits 0' \
  '{"seq":1,"ts":"x","author":"human","class":"semantic","verb":"propose","payload":{},"writerSha":"s","writerId":"w"}
' '{ "seq": 1, "byteOffset": 1111111111111111111111111111111111111111 }'
hostile_case 'a single-line cursor is read per-field, not per-shape' \
  '{"seq":1,"ts":"x","author":"human","class":"semantic","verb":"propose","payload":{},"writerSha":"s","writerId":"w"}
' '{"byteOffset":0,"seq":0}'

# No wc, no sed, no awk, no head — a stripped PATH, a container, a rescue
# shell. The hook cannot count without them; what it must not do is say so in
# front of the user's prompt, or fail.
work="$TMP/work"
rm -rf "$work"; mkdir -p "$work"
cp -R "$FIXTURES/pending/.esas" "$work/.esas"
# Absolute, because `env -i PATH=/nonexistent` cannot look the interpreter up.
hook_sh_abs=$( command -v "$HOOK_SH" )
out=$( env -i PATH=/nonexistent CLAUDE_PROJECT_DIR="$work" "$hook_sh_abs" "$HOOK" 2>"$TMP/err" </dev/null )
status=$?
if [ "$status" -ne 0 ]; then
  fail 'a stripped PATH still exits 0' "exit status $status" "stderr: $( cat "$TMP/err" )"
elif [ -n "$out" ] || [ -s "$TMP/err" ]; then
  fail 'a stripped PATH degrades to silence' "stdout: [$out]" "stderr: [$( cat "$TMP/err" )]"
else
  pass 'a stripped PATH degrades to silence, exit 0'
fi

# An unreadable feed: the hook may not read it, and may not complain either.
work="$TMP/work"
rm -rf "$work"; mkdir -p "$work/.esas"
printf '{"seq":1}\n' >"$work/.esas/ops.jsonl"
chmod 000 "$work/.esas/ops.jsonl"
CLAUDE_PROJECT_DIR="$work" "$HOOK_SH" "$HOOK" >"$TMP/out" 2>"$TMP/err" </dev/null
status=$?
chmod 644 "$work/.esas/ops.jsonl"
if [ "$status" -ne 0 ]; then
  fail 'an unreadable feed still exits 0' "exit status $status"
elif [ -s "$TMP/err" ] && [ "$( id -u )" != '0' ]; then
  fail 'an unreadable feed stays quiet on stderr' "stderr: $( cat "$TMP/err" )"
else
  pass 'an unreadable feed still exits 0, quietly'
fi

# ── The fast path is free ─────────────────────────────────────────────────────

printf '\ncost\n'

work="$TMP/work"
rm -rf "$work"; mkdir -p "$work"
start=$( date +%s )
i=0
while [ "$i" -lt 50 ]; do
  CLAUDE_PROJECT_DIR="$work" "$HOOK_SH" "$HOOK" >/dev/null 2>&1 </dev/null
  i=$(( i + 1 ))
done
end=$( date +%s )
elapsed=$(( end - start ))
# 50 runs of a hook that must be indistinguishable from zero. Two seconds is a
# ceiling generous enough for the slowest CI runner and still an order of
# magnitude under the 5 s timeout for a *single* run.
if [ "$elapsed" -gt 2 ]; then
  fail 'absent .esas costs nothing (50 runs)' "took ${elapsed}s for 50 runs"
else
  pass "absent .esas costs nothing: 50 runs in ${elapsed}s"
fi

# ── The SessionStart hook (hooks/esas-session-channel.sh) ────────────────────
#
# The second hook in this plugin, and the one whose *silence* is the behaviour
# under test. It tells a session to open the board's summon channel, and it must
# say that in exactly one state — a board on the port, serving THIS checkout,
# reporting `sessions: 0`. Every other state is silence, because an instruction
# to dial a port is wrong in all of them: nothing there means dial a dead
# address, a foreign board means attach this session to somebody else's design,
# and `sessions >= 1` means somebody already holds it.
#
# So the negative cases carry the weight here. A hook that printed
# unconditionally would pass a suite that only checked the positive one, and
# would then fire in every session in every repo with a `.esas/`.
#
# The board is a python stub on an ephemeral port rather than the real one on
# :3727: the assertion is about how the hook *reads* an answer, and binding a
# fixed port would make the verdict a property of what happens to be running on
# this machine.

printf '\nesas-session-channel hook (SessionStart)\n'

SESSION_HOOK="$PLUGIN/hooks/esas-session-channel.sh"

session_board_pid=''
# $1 = repoPath to answer with, $2 = the sessions count, $3 = 'pretty' to space
# the JSON. Compact is the board's own `JSON.stringify` spelling; the spaced
# variant exists because which checkout a board serves is not a question about
# how it serialises the answer.
start_session_board(){
  rm -f "$TMP/sport"
  python3 -c '
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
separators = (", ", ": ") if len(sys.argv) > 3 and sys.argv[3] == "pretty" else (",", ":")
fields = {"repoPath": sys.argv[1], "gitSha": "deadbee", "lastSeq": 7}
if sys.argv[2] != "omit":
    fields["sessions"] = int(sys.argv[2])
body = json.dumps(fields, separators=separators).encode()
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/esas/status":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *a):
        pass
srv = HTTPServer(("127.0.0.1", 0), H)
sys.stdout.write("%d\n" % srv.server_port)
sys.stdout.flush()
srv.serve_forever()
' "$1" "$2" "${3:-compact}" >"$TMP/sport" 2>/dev/null &
  session_board_pid=$!
  i=0
  while [ ! -s "$TMP/sport" ] && [ "$i" -lt 100 ]; do
    i=$(( i + 1 ))
    sleep 0.05 2>/dev/null || sleep 1
  done
  SESSION_BOARD_PORT=$( tr -d ' \n' <"$TMP/sport" 2>/dev/null )
}

stop_session_board(){
  [ -n "$session_board_pid" ] && kill "$session_board_pid" 2>/dev/null
  wait "$session_board_pid" 2>/dev/null
  session_board_pid=''
}

# Runs the hook in a work dir that has (or has not) a `.esas/`, against a given
# port. stdin closed, exactly as the prompt hook is run above.
run_session_hook(){
  swork="$TMP/swork"
  rm -rf "$swork"; mkdir -p "$swork"
  [ "$1" = 'no-esas' ] || mkdir -p "$swork/.esas"
  CLAUDE_PROJECT_DIR="$swork" ESAS_BOARD_PORT="$2" "$HOOK_SH" "$SESSION_HOOK" \
    >"$TMP/sout" 2>"$TMP/serr" </dev/null
  session_status=$?
}

# assert_session <esas|no-esas> <port> <speaks|silent> <description>
assert_session(){
  run_session_hook "$1" "$2"
  sout=$( cat "$TMP/sout" )
  serr=$( cat "$TMP/serr" )
  if [ "$session_status" -ne 0 ]; then
    fail "$4" "exit status $session_status — every path must exit 0" "stderr: $serr"
  elif [ -n "$serr" ]; then
    fail "$4" "wrote to stderr at session start" "stderr: $serr"
  elif [ "$3" = silent ] && [ -n "$sout" ]; then
    fail "$4" "expected silence, got: $sout"
  elif [ "$3" = speaks ] && [ -z "$sout" ]; then
    fail "$4" 'expected the arming instruction, got silence'
  else
    pass "$4"
  fi
}

if [ ! -f "$SESSION_HOOK" ]; then
  fail 'hooks/esas-session-channel.sh ships' "no file at $SESSION_HOOK"
elif ! command -v python3 >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  fail 'the SessionStart cases need python3 and curl' 'one of them is missing on this machine'
else
  # Line 2, the whole program most of the time. No design layer, no probe — and
  # this is the state every fleet worktree and every unrelated repo is in.
  assert_session 'no-esas' 1 silent 'no .esas/ at all: silent, and nothing is probed'

  # A `.esas/` with nothing on the port. The board is user-launched, so this is
  # the ordinary state of a designing repo, and the one where an unconditional
  # print would tell every session to dial a dead address.
  assert_session 'esas' 1 silent 'a design layer but no board: silent'

  swork="$TMP/swork"
  rm -rf "$swork"; mkdir -p "$swork/.esas"
  physical_swork=$( CDPATH= cd -- "$swork" && pwd -P )

  # The one state that speaks.
  start_session_board "$physical_swork" 0
  if [ -z "$SESSION_BOARD_PORT" ]; then
    fail 'a stub board comes up for the SessionStart cases' 'the stub never printed a port'
  else
    run_session_hook 'esas' "$SESSION_BOARD_PORT"
    case $( cat "$TMP/sout" ) in
      *"ws://127.0.0.1:$SESSION_BOARD_PORT/api/esas/ws"*)
        pass 'this checkout, sessions 0: it names the exact ws URL to open' ;;
      *)
        fail 'this checkout, sessions 0: it names the exact ws URL to open' \
          "actual: [$( cat "$TMP/sout" )]" ;;
    esac
    case $( cat "$TMP/sout" ) in
      *'persistent: true'*) pass 'and the Monitor call it emits is persistent' ;;
      *) fail 'and the Monitor call it emits is persistent' "actual: [$( cat "$TMP/sout" )]" ;;
    esac
  fi
  stop_session_board

  # Same state, spaced JSON. How a board serialises its answer is not a fact
  # about whether anyone is listening on it.
  start_session_board "$physical_swork" 0 pretty
  if [ -n "$SESSION_BOARD_PORT" ]; then
    assert_session 'esas' "$SESSION_BOARD_PORT" speaks \
      'a spaced status body from this checkout still arms'
  fi
  stop_session_board

  # Somebody is already holding the channel. Arming a second is a wake nobody
  # needs, in a session that may not be designing at all.
  start_session_board "$physical_swork" 1
  if [ -n "$SESSION_BOARD_PORT" ]; then
    assert_session 'esas' "$SESSION_BOARD_PORT" silent \
      'a channel someone already holds (sessions 1): silent'
  fi
  stop_session_board

  # A board on the port serving somebody else. This is the gate that makes
  # `.esas/` insufficient: without it every session in a repo whose port
  # happens to be held opens a socket to a stranger's design.
  start_session_board "/somewhere/else" 0
  if [ -n "$SESSION_BOARD_PORT" ]; then
    assert_session 'esas' "$SESSION_BOARD_PORT" silent \
      "another checkout's board reporting zero sessions: silent"
  fi
  stop_session_board

  # An older board answers a perfectly valid status with no `sessions` field.
  # Absent is unknown, never zero — it serves no channel to open.
  start_session_board "$physical_swork" omit
  if [ -n "$SESSION_BOARD_PORT" ]; then
    assert_session 'esas' "$SESSION_BOARD_PORT" silent \
      'a board with no `sessions` field is unknown, never zero: silent'
  fi
  stop_session_board

  # No curl: the probe cannot be made, so there is nothing to say. Reporting
  # anything here would be a guess printed into every session.
  rm -rf "$swork"; mkdir -p "$swork/.esas"
  session_hook_sh=$( command -v "$HOOK_SH" )
  out=$( env -i PATH=/nonexistent CLAUDE_PROJECT_DIR="$swork" "$session_hook_sh" "$SESSION_HOOK" \
         2>"$TMP/serr" </dev/null )
  if [ -n "$out" ] || [ -s "$TMP/serr" ]; then
    fail 'without curl it says nothing, quietly' "stdout: [$out] stderr: [$( cat "$TMP/serr" )]"
  else
    pass 'without curl it says nothing, quietly'
  fi
fi

# ── The mechanism: how the plugin declares the hooks ─────────────────────────
#
# The script working is worth nothing if Claude Code never runs it, and that
# failure is silent. `<plugin>/hooks/hooks.json` is loaded automatically (it is
# the path Claude Code stats; `plugin.json`'s `hooks` field is for *additional*
# files only), so these assert the wiring the runtime actually reads.

printf '\nwiring\n'

assert_json(){
  if grep -q "$2" "$HOOKS_JSON" 2>/dev/null; then pass "$1"; else fail "$1" "not found in $HOOKS_JSON: $2"; fi
}

if [ ! -f "$HOOKS_JSON" ]; then
  fail 'hooks/hooks.json exists (the path Claude Code auto-loads)' "no file at $HOOKS_JSON"
else
  pass 'hooks/hooks.json exists (the path Claude Code auto-loads)'
  assert_json 'it declares a UserPromptSubmit hook' '"UserPromptSubmit"'
  assert_json 'it declares a SessionStart hook' '"SessionStart"'
  assert_json 'and points that one at its shipped script too' \
    'CLAUDE_PLUGIN_ROOT}/hooks/esas-session-channel.sh'
  assert_json 'it sets an explicit timeout of 5s' '"timeout": *5'
  assert_json 'it points at the shipped script via ${CLAUDE_PLUGIN_ROOT}' 'CLAUDE_PLUGIN_ROOT}/hooks/esas-pending.sh'
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$HOOKS_JSON" 2>/dev/null; then
    pass 'hooks.json is valid JSON'
  else
    fail 'hooks.json is valid JSON' "json.load failed on $HOOKS_JSON"
  fi
fi

printf '\n'
if [ "$failed" -gt 0 ]; then
  printf '\033[31m✗ %d failed\033[0m, %d passed\n\n' "$failed" "$passed"
  exit 1
fi
printf '\033[32m✓ %d passed\033[0m\n\n' "$passed"
