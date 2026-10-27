#!/bin/sh
# Oracle for the shipped UserPromptSubmit hook (hooks/blueprint-pending.sh).
#
# This hook is the one artifact in the plugin that runs *unconditionally, on
# every prompt, in every repo where the plugin is enabled* — there is no
# per-directory matcher. Two failure modes therefore matter more than anything
# it does when it works:
#
#   1. a non-zero exit **blocks the user's prompt** (Claude Code: "Exit code 2 -
#      block processing, erase original prompt"), so every path here asserts
#      exit 0 — including the corrupt and torn inputs;
#   2. a slow path taxes every prompt in every repo, so the absent-`.blueprint`
#      fast-path is timed.
#
# Fixtures under scripts/fixtures/blueprint-pending/ were produced by the real
# @bett3r-dev/blueprint-store — see the README there. They are read-only: each case
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
HOOK="$PLUGIN/hooks/blueprint-pending.sh"
HOOKS_JSON="$PLUGIN/hooks/hooks.json"
FIXTURES="$ROOT/scripts/fixtures/blueprint-pending"
HOOK_SH=${HOOK_SH:-sh}

TMP=$( mktemp -d "${TMPDIR:-/tmp}/blueprint-hook-test.XXXXXX" ) || exit 1
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
# with no .blueprint at all) and records stdout / stderr / status in $TMP.
run_hook(){
  work="$TMP/work"
  rm -rf "$work"
  mkdir -p "$work"
  if [ "$1" != '-' ]; then
    cp -R "$FIXTURES/$1/.blueprint" "$work/.blueprint"
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

printf '\nblueprint-pending hook\n'

if [ ! -f "$HOOK" ]; then
  fail 'the hook script exists' "no file at $HOOK"
else
  pass 'the hook script exists'
fi

# ── The four oracle states ────────────────────────────────────────────────────

assert_case '-' \
  'absent .blueprint: silent (the fast-path exit, on every prompt in every repo)' \
  ''

assert_case 'pending' \
  'pending semantic human ops: one line, correct count and seq range' \
  'blueprint: 2 pending (seq 1→4)'

assert_case 'layout-only' \
  'layout-only pending: silent — "moved 14 stickies" is not a design change' \
  ''

assert_case 'corrupt-cursor' \
  'corrupt cursor: exits 0 and degrades to unsynced (everything pending)' \
  'blueprint: 3 pending (seq 0→4)'

# ── The rest of the contract ──────────────────────────────────────────────────

assert_case 'synced' \
  'synced cursor (byteOffset == size): silent' \
  ''

assert_case 'ai-only' \
  'pending ops are all ai-authored: silent — the count is about the user' \
  ''

assert_case 'stale' \
  'stale cursor (byteOffset > size): reports EVERYTHING pending, from seq 0' \
  'blueprint: 2 pending (seq 0→2)'

assert_case 'no-cursor' \
  'no cursor at all: nothing has been synced, so everything is pending' \
  'blueprint: 2 pending (seq 0→3)'

assert_case 'empty-feed' \
  'empty ops.jsonl: silent' \
  ''

assert_case 'nested-author' \
  'an ai op whose payload carries "author":"human" is not counted as human' \
  'blueprint: 1 pending (seq 1→3)'

assert_case 'torn-tail' \
  'a torn tail is skipped, not counted and not fatal' \
  'blueprint: 1 pending (seq 1→2)'

# The cursor is written `{ seq, byteOffset, writerId, ts }`, so a truncation in
# the tail leaves *both* contract fields perfect while the document is
# unparseable — the store reads that as unsynced, and so must this. A reader
# that checked only "both fields present" disagreed at 94 of 126 truncation
# points, every time by claiming synced.
assert_case 'torn-cursor-tail' \
  'a cursor torn in its writerId tail: both fields intact, still unsynced' \
  'blueprint: 3 pending (seq 0→4)'

# `test` does not return false on an operand it cannot parse — it *fails*, and
# behind `&&` that is indistinguishable from false, so the staleness branch
# silently did not fire. Both halves are asserted: the right answer, and silence
# on stderr (checked by assert_case for every case).
assert_case 'cursor-out-of-range' \
  'a byteOffset past 2^63 degrades to unsynced, silently' \
  'blueprint: 3 pending (seq 0→4)'

# ── Never block a prompt, whatever the input ─────────────────────────────────

printf '\nhardening\n'

hostile_case(){
  work="$TMP/work"
  rm -rf "$work"
  mkdir -p "$work/.blueprint"
  printf '%s' "$2" >"$work/.blueprint/ops.jsonl"
  if [ "$3" != '-' ]; then printf '%s' "$3" >"$work/.blueprint/.claude-cursor"; fi
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
cp -R "$FIXTURES/pending/.blueprint" "$work/.blueprint"
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
rm -rf "$work"; mkdir -p "$work/.blueprint"
printf '{"seq":1}\n' >"$work/.blueprint/ops.jsonl"
chmod 000 "$work/.blueprint/ops.jsonl"
CLAUDE_PROJECT_DIR="$work" "$HOOK_SH" "$HOOK" >"$TMP/out" 2>"$TMP/err" </dev/null
status=$?
chmod 644 "$work/.blueprint/ops.jsonl"
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
  fail 'absent .blueprint costs nothing (50 runs)' "took ${elapsed}s for 50 runs"
else
  pass "absent .blueprint costs nothing: 50 runs in ${elapsed}s"
fi

# ── The SessionStart hook (hooks/blueprint-session-channel.sh) ────────────────────
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
# would then fire in every session in every repo with a `.blueprint/`.
#
# The board is a python stub on an ephemeral port rather than the real one on
# :3727: the assertion is about how the hook *reads* an answer, and binding a
# fixed port would make the verdict a property of what happens to be running on
# this machine.

printf '\nblueprint-session-channel hook (SessionStart)\n'

SESSION_HOOK="$PLUGIN/hooks/blueprint-session-channel.sh"

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
        if self.path == "/api/blueprint/status":
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

# Runs the hook in a work dir that has (or has not) a `.blueprint/`, against a given
# port. stdin closed, exactly as the prompt hook is run above.
run_session_hook(){
  swork="$TMP/swork"
  rm -rf "$swork"; mkdir -p "$swork"
  [ "$1" = 'no-blueprint' ] || mkdir -p "$swork/.blueprint"
  CLAUDE_PROJECT_DIR="$swork" BLUEPRINT_BOARD_PORT="$2" "$HOOK_SH" "$SESSION_HOOK" \
    >"$TMP/sout" 2>"$TMP/serr" </dev/null
  session_status=$?
}

# assert_session <blueprint|no-blueprint> <port> <speaks|silent> <description>
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
  fail 'hooks/blueprint-session-channel.sh ships' "no file at $SESSION_HOOK"
elif ! command -v python3 >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  fail 'the SessionStart cases need python3 and curl' 'one of them is missing on this machine'
else
  # Line 2, the whole program most of the time. No design layer, no probe — and
  # this is the state every fleet worktree and every unrelated repo is in.
  assert_session 'no-blueprint' 1 silent 'no .blueprint/ at all: silent, and nothing is probed'

  # A `.blueprint/` with nothing on the port. The board is user-launched, so this is
  # the ordinary state of a designing repo, and the one where an unconditional
  # print would tell every session to dial a dead address.
  assert_session 'blueprint' 1 silent 'a design layer but no board: silent'

  swork="$TMP/swork"
  rm -rf "$swork"; mkdir -p "$swork/.blueprint"
  physical_swork=$( CDPATH= cd -- "$swork" && pwd -P )

  # The one state that speaks.
  start_session_board "$physical_swork" 0
  if [ -z "$SESSION_BOARD_PORT" ]; then
    fail 'a stub board comes up for the SessionStart cases' 'the stub never printed a port'
  else
    run_session_hook 'blueprint' "$SESSION_BOARD_PORT"
    case $( cat "$TMP/sout" ) in
      *"ws://127.0.0.1:$SESSION_BOARD_PORT/api/blueprint/ws"*)
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
    assert_session 'blueprint' "$SESSION_BOARD_PORT" speaks \
      'a spaced status body from this checkout still arms'
  fi
  stop_session_board

  # Somebody is already holding the channel. Arming a second is a wake nobody
  # needs, in a session that may not be designing at all.
  start_session_board "$physical_swork" 1
  if [ -n "$SESSION_BOARD_PORT" ]; then
    assert_session 'blueprint' "$SESSION_BOARD_PORT" silent \
      'a channel someone already holds (sessions 1): silent'
  fi
  stop_session_board

  # A board on the port serving somebody else. This is the gate that makes
  # `.blueprint/` insufficient: without it every session in a repo whose port
  # happens to be held opens a socket to a stranger's design.
  start_session_board "/somewhere/else" 0
  if [ -n "$SESSION_BOARD_PORT" ]; then
    assert_session 'blueprint' "$SESSION_BOARD_PORT" silent \
      "another checkout's board reporting zero sessions: silent"
  fi
  stop_session_board

  # An older board answers a perfectly valid status with no `sessions` field.
  # Absent is unknown, never zero — it serves no channel to open.
  start_session_board "$physical_swork" omit
  if [ -n "$SESSION_BOARD_PORT" ]; then
    assert_session 'blueprint' "$SESSION_BOARD_PORT" silent \
      'a board with no `sessions` field is unknown, never zero: silent'
  fi
  stop_session_board

  # No curl: the probe cannot be made, so there is nothing to say. Reporting
  # anything here would be a guess printed into every session.
  rm -rf "$swork"; mkdir -p "$swork/.blueprint"
  session_hook_sh=$( command -v "$HOOK_SH" )
  out=$( env -i PATH=/nonexistent CLAUDE_PROJECT_DIR="$swork" "$session_hook_sh" "$SESSION_HOOK" \
         2>"$TMP/serr" </dev/null )
  if [ -n "$out" ] || [ -s "$TMP/serr" ]; then
    fail 'without curl it says nothing, quietly' "stdout: [$out] stderr: [$( cat "$TMP/serr" )]"
  else
    pass 'without curl it says nothing, quietly'
  fi
fi

# ── The lane git guard (hooks/lane-git-guard.sh) ─────────────────────────────
#
# A PreToolUse(Bash) hook, so it runs before every Bash call in every repo
# where the plugin is enabled. It reads the payload (line 2), exits on a glob
# match when no `git` is in it, and otherwise looks for `.work/lane.yaml` in
# the checkouts the command can act on: the payload's cwd, the project dir,
# and every path after `cd`, `-C` or `--work-tree`. The attended fast path is
# asserted silent on both streams. Where a brief is found this is the one hook
# in the plugin that MAY exit 2: that blocks the tool call and hands stderr to
# the model. So the positive cases assert the block (exit 2, exactly one
# stderr line naming the alternative), the negative cases assert exit 0 and
# silence, and stdout is asserted empty on every path, because a PreToolUse
# hook's stdout is injected into the session.

printf '\nlane-git-guard hook (PreToolUse Bash)\n'

GUARD_HOOK="$PLUGIN/hooks/lane-git-guard.sh"

# guard_payload <command> — a PreToolUse(Bash) event. Built with python3, as the
# sibling plugin's suite builds its payloads, so the suite is not testing its
# own JSON escaping of a shell line full of quotes.
guard_payload(){
  python3 -c '
import json, sys
print(json.dumps({
    "session_id": "s1",
    "transcript_path": "/tmp/t.jsonl",
    "cwd": sys.argv[2],
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "tool_input": {"command": sys.argv[1], "description": "run a command", "timeout": 120000},
}))' "$1" "$gcwd"
}

# run_guard <lane|no-lane> <command> — a fresh work dir per case, with or
# without the lane brief, the payload on stdin as the harness sends it. The
# project dir and the payload's cwd are that work dir unless GUARD_PROJECT /
# GUARD_CWD point elsewhere (the cross-checkout cases).
GUARD_PROJECT=''
GUARD_CWD=''
run_guard(){
  gwork="$TMP/gwork"
  rm -rf "$gwork"; mkdir -p "$gwork/.work"
  if [ "$1" = lane ]; then
    printf 'ticket: XL-1\nworktree: %s\nbranch: xl-1-guard\ngateDeferred: true\n' "$gwork" >"$gwork/.work/lane.yaml"
  fi
  gproject=${GUARD_PROJECT:-$gwork}
  gcwd=${GUARD_CWD:-$gwork}
  # Built first, then piped by printf, so a python3 writing straight into a
  # pipe the hook has already left would not print an EPIPE traceback into the
  # suite's own output.
  gpayload=$( guard_payload "$2" )
  printf '%s' "$gpayload" | CLAUDE_PROJECT_DIR="$gproject" "$HOOK_SH" "$GUARD_HOOK" >"$TMP/gout" 2>"$TMP/gerr"
  guard_status=$?
}

# assert_guard <lane|no-lane> <command> <allow|block> <description>
assert_guard(){
  run_guard "$1" "$2"
  gout=$( cat "$TMP/gout" )
  gerr=$( cat "$TMP/gerr" )
  if [ -n "$gout" ]; then
    fail "$4" "wrote to stdout — a PreToolUse hook's stdout is injected into the session" "stdout: $gout"
    return
  fi
  if [ "$3" = allow ]; then
    if [ "$guard_status" -ne 0 ]; then
      fail "$4" "exit status $guard_status — this command must pass through" "stderr: $gerr"
    elif [ -n "$gerr" ]; then
      fail "$4" "wrote to stderr on a command it let through" "stderr: $gerr"
    else
      pass "$4"
    fi
    return
  fi
  if [ "$guard_status" -ne 2 ]; then
    fail "$4" "exit status $guard_status — expected 2, the PreToolUse block" "stderr: $gerr"
    return
  fi
  glines=$( wc -l <"$TMP/gerr" | tr -d ' ' )
  if [ "$glines" != '1' ]; then
    fail "$4" "expected exactly 1 line on stderr, got $glines" "stderr: $gerr"
    return
  fi
  case $gerr in
    *'git stash create'*'git diff <object>'* ) pass "$4" ;;
    * ) fail "$4" 'the stderr line must name the alternative: git stash create + git diff <object>' "stderr: $gerr" ;;
  esac
}

if [ ! -f "$GUARD_HOOK" ]; then
  fail 'hooks/lane-git-guard.sh ships' "no file at $GUARD_HOOK"
elif ! command -v python3 >/dev/null 2>&1; then
  fail 'the lane-git-guard cases need python3' 'python3 is missing on this machine'
else
  pass 'hooks/lane-git-guard.sh ships'

  # The attended fast path: no brief, a command it would otherwise block.
  assert_guard no-lane 'git stash' allow \
    'no .work/lane.yaml: git stash passes through, silent on both streams'

  # The four shapes the design names.
  assert_guard lane 'git stash' block 'lane: git stash is blocked, one stderr line'
  assert_guard lane 'git stash create' allow 'lane: git stash create passes through'
  assert_guard lane 'git stash list' allow 'lane: git stash list passes through'
  assert_guard lane 'git status' allow 'lane: git status passes through'

  # The rest of the blocked set, and its allowed neighbours.
  assert_guard lane 'git stash push -m wip' block 'lane: git stash push is blocked'
  assert_guard lane 'git stash pop' block 'lane: git stash pop is blocked'
  assert_guard lane 'git reset --hard HEAD~1' block 'lane: git reset --hard is blocked'
  assert_guard lane 'git reset --soft HEAD~1' allow 'lane: git reset --soft passes through (inline-fix squashes with it)'
  assert_guard lane 'git checkout -- src/a.ts' block 'lane: git checkout -- <path> is blocked'
  assert_guard lane 'git checkout .' block 'lane: git checkout . is blocked'
  assert_guard lane 'git checkout -b feature/x' allow 'lane: git checkout -b passes through'
  assert_guard lane 'git restore src/a.ts' block 'lane: git restore is blocked'
  assert_guard lane 'git clean -fd' block 'lane: git clean -fd is blocked'
  assert_guard lane 'git clean -n' allow 'lane: git clean -n (dry run) passes through'

  # Compound and wrapped spellings.
  assert_guard lane 'cd /tmp/x && git stash' block 'lane: a blocked command behind cd … && is still blocked'
  assert_guard lane 'git -C /tmp/x stash' block 'lane: git -C <path> stash is blocked'
  assert_guard lane 'git status; git stash' block 'lane: a blocked command after ; is still blocked'
  assert_guard lane 'obj=$(git stash create) && git diff "$obj"' allow \
    'lane: the sanctioned pair, git stash create + git diff <object>, passes through'

  # Tokens, not substrings: the words inside a quoted string are not a command.
  assert_guard lane 'git commit -m "never git stash in a lane"' allow \
    'lane: git stash inside a quoted commit message is not a match'

  # Multi-line commands: a newline is a command separator, like `;`.
  nl=$( printf '\n.' ); nl=${nl%.}
  assert_guard lane "git add .${nl}git stash" block \
    'lane: git stash on the second line of a command is blocked'
  assert_guard lane "git status${nl}git reset --hard HEAD" block \
    'lane: git reset --hard on the second line of a command is blocked'

  # The rest of the tree-discarding forms, and their allowed neighbours.
  assert_guard lane 'git reset --merge' block 'lane: git reset --merge is blocked'
  assert_guard lane 'git reset --keep HEAD~1' block 'lane: git reset --keep is blocked'
  assert_guard lane 'git switch -f main' block 'lane: git switch -f is blocked'
  assert_guard lane 'git switch --discard-changes main' block 'lane: git switch --discard-changes is blocked'
  assert_guard lane 'git switch main' allow 'lane: a plain git switch passes through'
  assert_guard lane 'git checkout -f main' block 'lane: git checkout -f is blocked'
  assert_guard lane 'x=`git stash`' block 'lane: git stash inside a backtick substitution is blocked'
  assert_guard lane 'git stash show' allow 'lane: git stash show passes through'

  # The lane is the checkout the command acts on, not necessarily the project
  # dir: a fleet lane is a subagent of the orchestrator's session and reaches
  # its worktree through cd or git -C, so the brief is looked for in the
  # payload's cwd, the project dir, and every path the command names.
  glane="$TMP/glane"; rm -rf "$glane"; mkdir -p "$glane/.work"
  printf 'ticket: XL-2\nworktree: %s\nbranch: xl-2-guard\n' "$glane" >"$glane/.work/lane.yaml"
  gplain="$TMP/gplain"; rm -rf "$gplain"; mkdir -p "$gplain"
  GUARD_PROJECT="$gplain"; GUARD_CWD="$gplain"
  assert_guard no-lane "git -C $glane stash" block \
    'no lane at the project dir or the cwd: git -C <lane worktree> stash is blocked'
  assert_guard no-lane "cd $glane && git stash" block \
    'no lane at the project dir or the cwd: cd <lane worktree> && git stash is blocked'
  assert_guard no-lane "cd $gplain && git stash" allow \
    'no lane anywhere the command reaches: cd <plain dir> && git stash passes through'
  GUARD_PROJECT="$gplain"; GUARD_CWD="$glane"
  assert_guard no-lane 'git stash' block \
    "lane at the payload's cwd only: git stash is blocked"
  GUARD_PROJECT="$glane"; GUARD_CWD="$gplain"
  assert_guard no-lane 'git stash' block \
    'lane at the project dir only: git stash is blocked'
  GUARD_PROJECT="$TMP"; GUARD_CWD="$TMP"
  assert_guard no-lane 'cd glane && git stash' block \
    'a relative cd into a lane worktree resolves against the cwd and is blocked'
  GUARD_PROJECT=''; GUARD_CWD=''

  # An empty payload: nothing to read, nothing to say.
  gwork="$TMP/gwork"
  rm -rf "$gwork"; mkdir -p "$gwork/.work"
  printf 'branch: xl-1-guard\n' >"$gwork/.work/lane.yaml"
  CLAUDE_PROJECT_DIR="$gwork" "$HOOK_SH" "$GUARD_HOOK" >"$TMP/gout" 2>"$TMP/gerr" </dev/null
  guard_status=$?
  if [ "$guard_status" -ne 0 ] || [ -s "$TMP/gout" ] || [ -s "$TMP/gerr" ]; then
    fail 'lane: an empty payload passes through silently' "exit $guard_status" \
      "stdout: [$( cat "$TMP/gout" )]" "stderr: [$( cat "$TMP/gerr" )]"
  else
    pass 'lane: an empty payload passes through silently'
  fi
fi

# ── The note before compaction (hooks/blueprint-precompact-note.sh) ──────────
#
# A PreCompact hook. Claude Code appends its stdout, on exit 0, to the
# compaction's custom instructions, and an exit 2 BLOCKS the compaction; so it
# speaks only in a Blueprint design run (Steward's hosted worktree,
# `<repo>.blueprint-worktrees/<session id>`), is silent everywhere else, and
# exits 0 on every path. The cases run the hook as hooks.json declares it, the
# ${CLAUDE_PLUGIN_ROOT} substituted, so a missing or mis-pointed entry fails the
# behaviour cases and not only the wiring grep below.

printf '\nblueprint-precompact-note hook (PreCompact)\n'

# The PreCompact entries' args, one per line, ${CLAUDE_PLUGIN_ROOT} resolved;
# empty when hooks.json declares none.
precompact_args(){
  python3 - "$HOOKS_JSON" "$PLUGIN" <<'PYPC' 2>/dev/null
import json, sys
h = json.load(open(sys.argv[1], encoding="utf-8")).get("hooks", {})
for entry in h.get("PreCompact", []):
    for x in entry.get("hooks", []):
        for a in x.get("args", []):
            print(str(a).replace("${CLAUDE_PLUGIN_ROOT}", sys.argv[2]))
PYPC
}

# precompact_payload <trigger> <cwd> — a PreCompact event as the harness sends it.
precompact_payload(){
  printf '{"session_id":"s1","transcript_path":"/tmp/t.jsonl","cwd":"%s","hook_event_name":"PreCompact","trigger":"%s","custom_instructions":""}' "$2" "$1"
}

# run_precompact <project dir> <trigger> — every PreCompact script hooks.json
# declares, under HOOK_SH, the payload on stdin; stdout, stderr, status in $TMP.
run_precompact(){
  : >"$TMP/pout"; : >"$TMP/perr"; pstatus=0
  pscripts=$( precompact_args )
  if [ -z "$pscripts" ]; then pstatus=missing; return; fi
  for pscript in $pscripts; do
    precompact_payload "$2" "$1" | CLAUDE_PROJECT_DIR="$1" "$HOOK_SH" "$pscript" >>"$TMP/pout" 2>>"$TMP/perr"
    prc=$?
    [ "$prc" -eq 0 ] || pstatus=$prc
  done
}

# assert_precompact <project dir> <trigger> <speaks|silent> <description>
assert_precompact(){
  run_precompact "$1" "$2"
  pout=$( cat "$TMP/pout" )
  perr=$( cat "$TMP/perr" )
  if [ "$pstatus" = missing ]; then
    fail "$4" "hooks.json declares no PreCompact hook"
    return
  fi
  if [ "$pstatus" -ne 0 ]; then
    fail "$4" "exit status $pstatus — expected 0; a PreCompact hook that exits 2 blocks the compaction" "stderr: $perr"
    return
  fi
  if [ -n "$perr" ]; then
    fail "$4" "wrote to stderr" "stderr: $perr"
    return
  fi
  if [ "$3" = silent ]; then
    if [ -n "$pout" ]; then fail "$4" "expected no output" "stdout: $pout"; else pass "$4"; fi
    return
  fi
  plines=$( printf '%s\n' "$pout" | grep -c . )
  for pword in 'mcp__blueprint__WriteNote' 'dead ends' 'preferences'; do
    case $pout in
      *"$pword"*) ;;
      *) fail "$4" "expected the one line asking for WriteNote with the dead ends and preferences; missing: $pword" "stdout: [$pout]"; return ;;
    esac
  done
  # Version skew (design, Risks): a Blueprint server older than WriteNote has no
  # such tool, so the call is conditional on the tool being there, with the
  # summary itself as the fallback; and the summary keeps the session id the
  # call needs.
  for pword in 'if your tools include mcp__blueprint__WriteNote' 'if they do not, keep the note in the summary' 'session id'; do
    case $pout in
      *"$pword"*) ;;
      *) fail "$4" "expected the WriteNote call to be conditional on the tool existing, with the summary as fallback, and the session id kept; missing: $pword" "stdout: [$pout]"; return ;;
    esac
  done
  if [ "$plines" = 1 ]; then pass "$4"; else fail "$4" "expected exactly 1 line, got $plines" "stdout: $pout"; fi
}

if ! command -v python3 >/dev/null 2>&1; then
  fail 'the precompact cases need python3' 'python3 is missing on this machine'
else
  prun="$TMP/acme.blueprint-worktrees/0f9c2a51-5c1e-4c47-9d0b-3a1f6e2b7c11"
  pplain="$TMP/acme"
  pboard="$TMP/acme-board"
  pconn="$TMP/acme-connected"
  rm -rf "$prun" "$pplain" "$pboard" "$pconn"
  mkdir -p "$prun" "$pplain" "$pboard/.blueprint" "$pconn/.git"
  printf '{"host":"https://bp.example","sessionId":"s1","branchAtConnect":"main","connectedAt":"2026-10-26T00:00:00Z"}\n' \
    >"$pconn/.git/blueprint-connection.json"

  assert_precompact "$prun" auto speaks \
    'a Blueprint design run, auto compaction: one line asking for WriteNote before the context goes'
  assert_precompact "$prun" manual speaks \
    'a Blueprint design run, /compact: the same line'
  assert_precompact "$pplain" auto silent \
    'no Blueprint run: prints nothing and exits 0'
  assert_precompact "$pboard" auto silent \
    'a checkout with a .blueprint/ but no design run: prints nothing and exits 0'
  assert_precompact "$pconn" auto silent \
    'a checkout with a /blueprint connect record but no design run: prints nothing and exits 0'
  assert_precompact "$TMP/acme.blueprint-worktrees" auto silent \
    'the worktrees folder itself is not a run: prints nothing and exits 0'

  # Never blocks, whatever arrives: no payload, and a project dir that is gone.
  pscripts=$( precompact_args )
  if [ -z "$pscripts" ]; then
    fail 'an empty payload, a vanished project dir and no CLAUDE_PROJECT_DIR all exit 0' 'hooks.json declares no PreCompact hook'
  else
    pbad=''
    for pscript in $pscripts; do
      CLAUDE_PROJECT_DIR="$prun" "$HOOK_SH" "$pscript" >/dev/null 2>&1 </dev/null || pbad="$pbad empty-payload"
      CLAUDE_PROJECT_DIR="$TMP/gone.blueprint-worktrees/x" "$HOOK_SH" "$pscript" >/dev/null 2>&1 </dev/null || pbad="$pbad vanished-dir"
      env -u CLAUDE_PROJECT_DIR "$HOOK_SH" "$pscript" >/dev/null 2>&1 </dev/null || pbad="$pbad no-project-dir"
    done
    if [ -z "$pbad" ]; then
      pass 'an empty payload, a vanished project dir and no CLAUDE_PROJECT_DIR all exit 0'
    else
      fail 'an empty payload, a vanished project dir and no CLAUDE_PROJECT_DIR all exit 0' "non-zero on:$pbad"
    fi
  fi
fi

# ── Capturing the conversation (hooks/blueprint-capture.sh, bin/blueprint-send) ──
#
# ML-1 F28 (opt-in ask) and F17 (warn and choose). A repository opts in from its
# checked-in settings (`env.BLUEPRINT_CAPTURE_REPOSITORY`, the repository's name
# in Blueprint); each person sets BLUEPRINT_CAPTURE to off, ask (the default) or
# always. In `ask` the Stop hook asks the agent, once a session, to ask the
# person "Send this conversation to Blueprint's memory?" with a one-line
# summary, and only a yes runs `blueprint-send`; in `always` the SessionEnd hook
# sends. Every send runs Blueprint's secret check first, and a match stops it
# with "This looks like a secret" and the three ways on. The Blueprint server,
# its upload grant and its bucket are one python stub on an ephemeral port that
# logs every request, so "nothing left the machine" is an empty request log.

printf '\nblueprint-capture hook (Stop, SessionEnd) and blueprint-send\n'

SEND_BIN="$PLUGIN/bin/blueprint-send"

# The scripts hooks.json declares for event $1, ${CLAUDE_PLUGIN_ROOT} resolved.
capture_args(){
  python3 - "$HOOKS_JSON" "$PLUGIN" "$1" <<'PYCA' 2>/dev/null
import json, sys
h = json.load(open(sys.argv[1], encoding="utf-8")).get("hooks", {})
for entry in h.get(sys.argv[3], []):
    for x in entry.get("hooks", []):
        for a in x.get("args", []):
            if str(a).endswith("hooks/blueprint-capture.sh"):
                print(str(a).replace("${CLAUDE_PLUGIN_ROOT}", sys.argv[2]))
PYCA
}

cat >"$TMP/capture-server.py" <<'PYSRV'
# A Blueprint stub: /secret-check answers spans as the real route does (every
# rule's matches, sorted by start and not merged, in UTF-16 units) for five
# rules: GitHub tokens (the shape of gitleaks' github-pat), private-key
# (gitleaks' pattern, which runs across lines), private-key-whole (Blueprint's
# own, a key from its header through its END line), private-key-open (Blueprint's
# own, a key with no END line) and a generic-api-key stand-in
# whose match ends inside a token after `api_key=`, so two spans overlap;
# /documents/upload-grant a presigned POST at its own /bucket with the D44
# checksum fields, /bucket refuses bytes whose SHA-256 is not the checksum (as
# MinIO does) and keeps them, /api/conversations/capture-conversation answers 200.
import base64, email.parser, email.policy, hashlib, json, re, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
log_path, upload_path = sys.argv[1], sys.argv[2]
RULES = [("github-pat", re.compile(r"ghp_[0-9a-zA-Z]{36}")),
         ("generic-api-key", re.compile(r"api_key=\S{12}")),
         ("private-key", re.compile(r"(?i)-----BEGIN[ A-Z0-9_-]{0,100}PRIVATE KEY(?: BLOCK)?-----[\s\S-]{64,}?KEY(?: BLOCK)?-----")),
         ("private-key-whole", re.compile(r"(?i)-----BEGIN[ A-Z0-9_-]{0,100}PRIVATE KEY(?: BLOCK)?-----(?:[^-]|-{1,4}[^-]){64,}?-----END[ A-Z0-9_-]{0,100}PRIVATE KEY(?: BLOCK)?-----")),
         ("private-key-open", re.compile(r"(?i)-----BEGIN[ A-Z0-9_-]{0,100}PRIVATE KEY(?: BLOCK)?-----(?:(?:\r?\n|\\r\\n|\\n)[ \t]*(?:\d+(?:\t|→)[ \t]*)?[A-Za-z][A-Za-z0-9-]*:[^\r\n\\]*)*(?:(?:\r?\n|\\r\\n|\\n)[ \t]*(?:\d+(?:\t|→)[ \t]*)?)?(?:\r?\n|\\r\\n|\\n)[ \t]*(?:\d+(?:\t|→)[ \t]*)?[A-Za-z0-9+/=]{16,}(?:(?:\r?\n|\\r\\n|\\n)[ \t]*(?:\d+(?:\t|→)[ \t]*)?[A-Za-z0-9+/=]{16,})*(?:(?:\r?\n|\\r\\n|\\n)[ \t]*(?:\d+(?:\t|→)[ \t]*)?[A-Za-z0-9+/=]+)?"))]
def u16(s): return len(s.encode("utf-16-le")) // 2
class H(BaseHTTPRequestHandler):
    def reply(self, status, obj):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        entry = {"path": self.path, "auth": self.headers.get("Authorization", "")}
        if self.path == "/bucket":
            msg = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(
                b"Content-Type: " + self.headers["Content-Type"].encode() + b"\r\n\r\n" + raw)
            fields, data = {}, b""
            for part in msg.iter_parts():
                name = part.get_param("name", header="content-disposition")
                if name == "file":
                    data = part.get_payload(decode=True)
                else:
                    fields[name] = part.get_payload(decode=True).decode()
            entry["fields"] = fields
            ok = fields.get("x-amz-checksum-sha256") == base64.b64encode(hashlib.sha256(data).digest()).decode()
            entry["checksum_ok"] = ok
            open(log_path, "a").write(json.dumps(entry) + "\n")
            if not ok:
                self.send_response(400); self.end_headers(); return
            open(upload_path, "wb").write(data)
            self.send_response(204); self.end_headers(); return
        body = json.loads(raw or b"{}")
        entry["body"] = body
        open(log_path, "a").write(json.dumps(entry) + "\n")
        if self.path == "/secret-check":
            if len(raw) > 1 << 20:  # the route's own cap: over 1 MiB is a 400
                self.reply(400, {}); return
            t = body.get("text", "")
            spans = [{"rule": rule, "start": u16(t[:m.start()]), "end": u16(t[:m.end()])} for rule, rx in RULES for m in rx.finditer(t)]
            self.reply(200, {"spans": sorted(spans, key=lambda x: x["start"])})
        elif self.path == "/documents/upload-grant":
            sha = body["sha"]
            self.reply(200, {"url": "http://127.0.0.1:%d/bucket" % self.server.server_port,
                             "fields": {"key": "acme/" + sha, "Content-Type": "text/plain",
                                        "x-amz-checksum-algorithm": "SHA256",
                                        "x-amz-checksum-sha256": base64.b64encode(bytes.fromhex(sha)).decode()},
                             "object_url": "http://127.0.0.1:%d/bucket/acme/%s" % (self.server.server_port, sha)})
        elif self.path == "/api/conversations/capture-conversation":
            if body.get("repository") == "github.com/acme/refused":
                self.reply(422, {"message": "The file's URL is under another org's prefix: upload it again from this org."})
            else:
                self.reply(200, {})
        else:
            self.reply(404, {"error": "no such route"})
    def log_message(self, *a):
        pass
srv = HTTPServer(("127.0.0.1", 0), H)
sys.stdout.write("%d\n" % srv.server_port)
sys.stdout.flush()
srv.serve_forever()
PYSRV

capture_server_pid=''
start_capture_server(){
  rm -f "$TMP/cport" "$TMP/creq" "$TMP/cupload"
  : >"$TMP/creq"
  python3 "$TMP/capture-server.py" "$TMP/creq" "$TMP/cupload" >"$TMP/cport" 2>/dev/null &
  capture_server_pid=$!
  i=0
  while [ ! -s "$TMP/cport" ] && [ "$i" -lt 100 ]; do
    i=$(( i + 1 ))
    sleep 0.05 2>/dev/null || sleep 1
  done
  CAPTURE_PORT=$( tr -d ' \n' <"$TMP/cport" 2>/dev/null )
}
stop_capture_server(){
  [ -n "$capture_server_pid" ] && kill "$capture_server_pid" 2>/dev/null
  wait "$capture_server_pid" 2>/dev/null
  capture_server_pid=''
}

# A transcript as Claude Code writes it: a 1,500-character prompt and reply
# (sent in full), a tool call and a 600-character tool output (cut to 400),
# thinking and a meta line (not the conversation). $2 = 'key' puts a GitHub
# token in the prompt, 'overlap' the token after `api_key=` (two rules' spans
# overlap), 'big' the token after 1.5 million characters, 'pem' a private key
# that runs across the first cut of the secret check's pieces (chunks() ends
# the first piece at character 892,928, 109 blocks of 8,192; the key spans
# characters 891,006 to 893,668 of the rendered text, and 12,000 characters
# follow it so the text needs a second piece).
CAP_KEY='ghp_0123456789abcdefghijklmnopqrstuvwxyz'
write_transcript(){
  python3 - "$1" "$2" "$CAP_KEY" <<'PYTR'
import json, sys
path, kind, key = sys.argv[1:4]
prompt = "Why do retries stop at three? " + "p" * 1500 + " END-OF-PROMPT"
if kind == "key":
    prompt = "my token \U0001F600 is " + key + " — " + prompt
if kind == "big":
    prompt = "q" * 1_500_000 + " then \U0001F600 " + key + " at the end"
if kind == "overlap":
    prompt = "set api_key=" + key + " in the env — " + prompt
if kind == "pem":
    pem = "-----BEGIN RSA PRIVATE KEY-----\n" + ("K" * 64 + "\n") * 40 + "-----END RSA PRIVATE KEY-----\n"
    prompt = ("f" * 999 + "\n") * 891 + pem + "is this key still valid? " + "g" * 12000
lines = [
    {"type": "user", "message": {"role": "user", "content": prompt}},
    {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "thinking", "thinking": "PRIVATE-THINKING"}]}},
    {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "Because the broker " + "r" * 1500 + " END-OF-REPLY"}]}},
    {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "cat retries.log " + "c" * 400 + "TOOLIN-TAIL"}}]}},
    {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "o" * 400 + "TAIL-BEYOND-400" + "x" * 185}]}},
    {"type": "user", "isMeta": True, "message": {"role": "user", "content": [{"type": "text", "text": "META-LINE"}]}},
    {"type": "system", "content": "SYSTEM-LINE"},
]
with open(path, "w", encoding="utf-8") as f:
    for l in lines:
        f.write(json.dumps(l) + "\n")
PYTR
}

# The person's machine: a home with a Blueprint sign-in for the stub, and a
# checkout connected to session s-42 on it, in an interactive Claude Code
# (CLAUDE_CODE_ENTRYPOINT=cli; `claude -p` runs hooks with sdk-cli). Ambient
# Blueprint and Claude state is scrubbed so the verdict is not a property of
# who runs the suite, or of whether a headless lane runs it.
capture_setup(){
  chome="$TMP/chome"; cwork="$TMP/cwork"
  rm -rf "$chome" "$cwork"
  mkdir -p "$chome/.config/blueprint" "$cwork/.git"
  python3 - "$chome/.config/blueprint/credentials.json" "http://127.0.0.1:$CAPTURE_PORT" <<'PYCR'
import json, sys
rec = {"v": 1, "host": sys.argv[2], "token": "pv4k_test", "userId": "u1", "email": "a@b.c", "displayName": "A",
       "expiresAt": "2099-01-01T00:00:00Z", "createdAt": "2026-10-26T00:00:00Z", "store": "file"}
json.dump({"v": 1, "accounts": {sys.argv[2]: json.dumps(rec)}}, open(sys.argv[1], "w"))
PYCR
  printf '{"host":"http://127.0.0.1:%s","sessionId":"s-42","branchAtConnect":"main","connectedAt":"2026-10-26T00:00:00Z"}\n' \
    "$CAPTURE_PORT" >"$cwork/.git/blueprint-connection.json"
  write_transcript "$TMP/claude-7f3a.jsonl" plain
  write_transcript "$TMP/claude-key.jsonl" key
}

# cap_env NAME=VALUE... -- command...: the command in the person's environment.
cap_env(){
  set -- HOME="$chome" CLAUDE_PROJECT_DIR="$cwork" BLUEPRINT_CAPTURE_REPOSITORY=github.com/acme/shop \
    CLAUDE_CODE_ENTRYPOINT=cli "$@"
  env -u BLUEPRINT_ACCESS_TOKEN -u BLUEPRINT_HOST_URL -u BLUEPRINT_CAPTURE -u XDG_STATE_HOME \
      -u CLAUDE_CONFIG_DIR -u GIT_DIR -u CLAUDE_CODE_ENTRYPOINT "$@"
}

# capture_hook <event> <session id> <transcript> <stop_hook_active> [NAME=VALUE...]:
# every script hooks.json declares for the event, under HOOK_SH, the payload on
# stdin; stdout, stderr and status in $TMP (status 'missing' when none is declared).
capture_hook(){
  ev=$1 sid=$2 tp=$3 active=$4
  shift 4
  : >"$TMP/cout"; : >"$TMP/cerr"; cstatus=0
  cscripts=$( capture_args "$ev" )
  if [ -z "$cscripts" ]; then cstatus=missing; return; fi
  for cscript in $cscripts; do
    printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","stop_hook_active":%s,"reason":"prompt_input_exit"}' \
      "$sid" "$tp" "$cwork" "$ev" "$active" |
      cap_env "$@" "$HOOK_SH" "$cscript" >>"$TMP/cout" 2>>"$TMP/cerr"
    crc=$?
    [ "$crc" -eq 0 ] || cstatus=$crc
  done
}

# capture_send [NAME=VALUE...] -- [blueprint-send args...]
capture_send(){
  cenv=''
  while [ $# -gt 0 ] && [ "$1" != -- ]; do cenv="$cenv $1"; shift; done
  [ $# -gt 0 ] && shift
  # shellcheck disable=SC2086
  cap_env $cenv "$HOOK_SH" "$SEND_BIN" "$@" >"$TMP/cout" 2>"$TMP/cerr" </dev/null
  cstatus=$?
}

creq_paths(){ python3 -c 'import json,sys; print(" ".join(json.loads(l)["path"] for l in open(sys.argv[1]) if l.strip()))' "$TMP/creq"; }

if ! command -v python3 >/dev/null 2>&1; then
  fail 'the capture cases need python3' 'python3 is missing on this machine'
else
  start_capture_server
  if [ -z "$CAPTURE_PORT" ]; then
    fail 'the capture stub server starts' 'no port'
  else
    capture_setup

    # ── on no nothing leaves the machine (F28, the opt-in ask) ──
    capture_hook Stop claude-7f3a "$TMP/claude-7f3a.jsonl" false
    cout=$( cat "$TMP/cout" )
    creason=$( printf '%s' "$cout" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get("decision", ""), "|", d.get("reason", ""))
except Exception:
    print("NOT-JSON")' )
    if [ "$cstatus" != 0 ]; then
      fail 'ask (the default): the Stop hook blocks once to have the agent ask "Send this conversation to Blueprint'"'"'s memory?"' "exit status $cstatus, expected 0" "stderr: $( cat "$TMP/cerr" )"
    else
      cmiss=''
      for w in 'block |' "Send this conversation to Blueprint's memory?" 'one-line summary' 'blueprint-send --consent --session-id claude-7f3a' 'when this session ends' 'If they say no, send nothing'; do
        case $creason in *"$w"*) ;; *) cmiss="$cmiss [$w]" ;; esac
      done
      if [ -z "$cmiss" ]; then
        pass 'ask (the default): the Stop hook blocks once to have the agent ask "Send this conversation to Blueprint'"'"'s memory?"'
      else
        fail 'ask (the default): the Stop hook blocks once to have the agent ask "Send this conversation to Blueprint'"'"'s memory?"' "missing:$cmiss" "stdout: [$cout]"
      fi
    fi
    capture_hook Stop claude-7f3a "$TMP/claude-7f3a.jsonl" false
    if [ "$cstatus" = 0 ] && [ ! -s "$TMP/cout" ]; then
      pass 'ask: the next Stop of the same session asks nothing again'
    else
      fail 'ask: the next Stop of the same session asks nothing again' "exit $cstatus" "stdout: [$( cat "$TMP/cout" )]"
    fi
    # The person answered no: the agent runs nothing, and the session ends.
    capture_hook SessionEnd claude-7f3a "$TMP/claude-7f3a.jsonl" false
    creqs=$( creq_paths )
    if [ "$cstatus" = 0 ] && [ -z "$creqs" ] && [ ! -s "$TMP/cupload" ] && [ ! -s "$TMP/cout" ]; then
      pass 'on no nothing leaves the machine: after the ask and the session end, Blueprint received no request'
    else
      fail 'on no nothing leaves the machine: after the ask and the session end, Blueprint received no request' \
        "exit $cstatus; expected requests: none; actual: [$creqs]" "stdout: [$( cat "$TMP/cout" )]"
    fi

    # ── on yes the whole conversation lands, at the session's end (F28, D64) ──
    # The yes comes at the first Stop; the session goes on, and SessionEnd sends
    # the transcript as it is then, every later turn included.
    cp "$TMP/claude-7f3a.jsonl" "$TMP/claude-yes.jsonl"
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_hook Stop claude-yes "$TMP/claude-yes.jsonl" false
    case $( cat "$TMP/cout" ) in *'"decision": "block"'*) cyask=asked ;; *) cyask=silent ;; esac
    capture_send -- --consent --session-id claude-yes
    cyes="$cstatus:$( creq_paths )"
    printf '%s\n' '{"type": "user", "message": {"role": "user", "content": "LATER-TURN after the yes"}}' >>"$TMP/claude-yes.jsonl"
    capture_hook Stop claude-yes "$TMP/claude-yes.jsonl" false
    cyagain="$cstatus:$( cat "$TMP/cout" )"
    capture_hook SessionEnd claude-yes "$TMP/claude-yes.jsonl" false
    creqs=$( creq_paths )
    cexpect='/secret-check /documents/upload-grant /bucket /api/conversations/capture-conversation'
    if [ "$cyask" = asked ] && [ "$cyes" = '0:' ] && [ "$cyagain" = '0:' ] && [ "$cstatus" = 0 ] && [ "$creqs" = "$cexpect" ] \
       && grep -q 'END-OF-PROMPT' "$TMP/cupload" 2>/dev/null && grep -q 'LATER-TURN after the yes' "$TMP/cupload" 2>/dev/null; then
      pass 'on yes the conversation lands: the yes is remembered (nothing sent yet), and the session end sends the whole transcript, later turns included'
    else
      fail 'on yes the conversation lands: the yes is remembered (nothing sent yet), and the session end sends the whole transcript, later turns included' \
        "ask [$cyask]; consent exit:requests [$cyes] (expected 0:); next Stop [$cyagain]; end exit $cstatus; requests [$creqs] (expected [$cexpect]); later turn sent: $( grep -c 'LATER-TURN' "$TMP/cupload" 2>/dev/null )" \
        "stdout: [$( cat "$TMP/cout" )] stderr: [$( cat "$TMP/cerr" )]"
    fi

    # ── headless and unattended runs are never asked (F2): the ask would replace
    # the run's final answer. `claude -p` and the SDKs run hooks with
    # CLAUDE_CODE_ENTRYPOINT sdk-*; a lane holds .work/lane.yaml; a Steward
    # design run is a <repo>.blueprint-worktrees/<id> checkout. Each is followed
    # by the same session, interactive, which is asked: the skip is the only
    # reason it was silent. ──
    : >"$TMP/creq"
    chead=''
    for cep in sdk-cli sdk-ts sdk-py claude-code-github-action; do
      capture_hook Stop "claude-$cep" "$TMP/claude-7f3a.jsonl" false CLAUDE_CODE_ENTRYPOINT=$cep
      chead="$chead $cep=$cstatus:$( wc -c <"$TMP/cout" | tr -d ' ' )"
      capture_hook Stop "claude-$cep" "$TMP/claude-7f3a.jsonl" false
      case $( cat "$TMP/cout" ) in *'"decision": "block"'*) chead="$chead/then-asked" ;; *) chead="$chead/then-silent" ;; esac
    done
    mkdir -p "$cwork/.work"; : >"$cwork/.work/lane.yaml"
    capture_hook Stop claude-lane "$TMP/claude-7f3a.jsonl" false
    chead="$chead lane=$cstatus:$( wc -c <"$TMP/cout" | tr -d ' ' )"
    rm -rf "$cwork/.work"
    capture_hook Stop claude-lane "$TMP/claude-7f3a.jsonl" false
    case $( cat "$TMP/cout" ) in *'"decision": "block"'*) chead="$chead/then-asked" ;; *) chead="$chead/then-silent" ;; esac
    cstew="$TMP/shop.blueprint-worktrees/s-9"
    mkdir -p "$cstew/.git"; cp "$cwork/.git/blueprint-connection.json" "$cstew/.git/"
    capture_hook Stop claude-steward "$TMP/claude-7f3a.jsonl" false CLAUDE_PROJECT_DIR="$cstew"
    chead="$chead steward=$cstatus:$( wc -c <"$TMP/cout" | tr -d ' ' )"
    mv "$cstew" "$TMP/shop-s-9"
    capture_hook Stop claude-steward "$TMP/claude-7f3a.jsonl" false CLAUDE_PROJECT_DIR="$TMP/shop-s-9"
    case $( cat "$TMP/cout" ) in *'"decision": "block"'*) chead="$chead/then-asked" ;; *) chead="$chead/then-silent" ;; esac
    cwant=' sdk-cli=0:0/then-asked sdk-ts=0:0/then-asked sdk-py=0:0/then-asked claude-code-github-action=0:0/then-asked lane=0:0/then-asked steward=0:0/then-asked'
    if [ "$chead" = "$cwant" ] && [ -z "$( creq_paths )" ]; then
      pass 'ask: claude -p and the SDKs, a lane and a Steward design run are not asked (the ask would replace their answer); the same session interactive is'
    else
      fail 'ask: claude -p and the SDKs, a lane and a Steward design run are not asked (the ask would replace their answer); the same session interactive is' \
        "expected [$cwant]" "actual   [$chead]; requests [$( creq_paths )]"
    fi

    capture_hook Stop claude-other "$TMP/claude-7f3a.jsonl" true
    if [ "$cstatus" = 0 ] && [ ! -s "$TMP/cout" ]; then
      pass 'ask: a Stop already continuing from a Stop hook asks nothing (no loop)'
    else
      fail 'ask: a Stop already continuing from a Stop hook asks nothing (no loop)' "exit $cstatus" "stdout: [$( cat "$TMP/cout" )]"
    fi

    # ── off, and a repository that has not opted in ──
    capture_hook Stop claude-off "$TMP/claude-7f3a.jsonl" false BLUEPRINT_CAPTURE=off
    coff1="$cstatus:$( cat "$TMP/cout" )"
    capture_hook SessionEnd claude-off "$TMP/claude-7f3a.jsonl" false BLUEPRINT_CAPTURE=off
    coff2="$cstatus:$( cat "$TMP/cout" )"
    capture_hook SessionEnd claude-noopt "$TMP/claude-7f3a.jsonl" false BLUEPRINT_CAPTURE=always BLUEPRINT_CAPTURE_REPOSITORY=
    coff3="$cstatus:$( cat "$TMP/cout" )"
    creqs=$( creq_paths )
    if [ "$coff1|$coff2|$coff3" = '0:|0:|0:' ] && [ -z "$creqs" ]; then
      pass 'off, or a repository whose settings do not opt in: silent, exit 0, no request'
    else
      fail 'off, or a repository whose settings do not opt in: silent, exit 0, no request' "got [$coff1|$coff2|$coff3], requests [$creqs]"
    fi

    # ── always: the session's end sends it, the secret check first ──
    capture_hook SessionEnd claude-7f3a "$TMP/claude-7f3a.jsonl" false BLUEPRINT_CAPTURE=always
    creqs=$( creq_paths )
    cexpect='/secret-check /documents/upload-grant /bucket /api/conversations/capture-conversation'
    if [ "$cstatus" = 0 ] && [ "$creqs" = "$cexpect" ]; then
      pass 'always: at the session end the hook checks for secrets, takes the grant, uploads, then captures, in that order'
    else
      fail 'always: at the session end the hook checks for secrets, takes the grant, uploads, then captures, in that order' \
        "exit $cstatus; expected [$cexpect]; actual [$creqs]" "stderr: $( cat "$TMP/cerr" )"
    fi
    cverdict=$( python3 - "$TMP/creq" "$TMP/cupload" <<'PYCV'
import base64, hashlib, json, sys
reqs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
by = {r["path"]: r for r in reqs}
bad = []
try:
    data = open(sys.argv[2], "rb").read()
except OSError:
    data = b""
sha = hashlib.sha256(data).hexdigest()
g = by.get("/documents/upload-grant", {}).get("body", {})
if g != {"sha": sha, "size": len(data), "type": "text/plain"}:
    bad.append("grant body %r, expected sha/size/type of the upload and no session" % g)
b = by.get("/bucket", {})
if not b.get("checksum_ok"):
    bad.append("upload checksum not the bytes' SHA-256: %r" % b.get("fields"))
c = by.get("/api/conversations/capture-conversation", {}).get("body", {})
want = {"repository": "github.com/acme/shop", "conversation": "claude-7f3a", "sha": sha, "size": len(data),
        "session": "s-42"}
for k, v in want.items():
    if c.get(k) != v:
        bad.append("capture %s = %r, expected %r" % (k, c.get(k), v))
if not str(c.get("url", "")).endswith("/bucket/acme/" + sha):
    bad.append("capture url %r is not the grant's object_url" % c.get("url"))
for r in reqs:
    if r["path"] != "/bucket" and r["auth"] != "Bearer pv4k_test":
        bad.append("%s sent Authorization %r" % (r["path"], r["auth"]))
print("; ".join(bad) or "ok")
PYCV
)
    if [ "$cverdict" = ok ]; then
      pass 'always: the grant names the sha, size and text/plain; the bucket gets its checksum; the capture names repository, conversation, url, sha, size and the connected session'
    else
      fail 'always: the grant names the sha, size and text/plain; the bucket gets its checksum; the capture names repository, conversation, url, sha, size and the connected session' "$cverdict"
    fi
    cbody=$( python3 - "$TMP/cupload" <<'PYCB'
import sys
try:
    t = open(sys.argv[1], encoding="utf-8").read()
except OSError:
    print("nothing was uploaded")
    sys.exit()
bad = []
prompt = "Why do retries stop at three? " + "p" * 1500 + " END-OF-PROMPT"
reply = "Because the broker " + "r" * 1500 + " END-OF-REPLY"
if prompt not in t: bad.append("the prompt is not there in full")
if reply not in t: bad.append("the reply is not there in full")
if "o" * 400 not in t: bad.append("the tool output's first 400 characters are not there")
if "TAIL-BEYOND-400" in t: bad.append("the tool output past 400 characters was sent")
if "tool call Bash: " not in t: bad.append("the tool call is not there")
if "TOOLIN-TAIL" in t: bad.append("the tool call's input past 400 characters was sent")
for w in ("PRIVATE-THINKING", "META-LINE", "SYSTEM-LINE"):
    if w in t: bad.append(w + " was sent")
print("; ".join(bad) or "ok")
PYCB
)
    if [ "$cbody" = ok ]; then
      pass 'what is sent: prompts and replies in full, tool output cut to 400 characters, no thinking, meta or system lines'
    else
      fail 'what is sent: prompts and replies in full, tool output cut to 400 characters, no thinking, meta or system lines' "$cbody"
    fi

    # ── a pasted key (F17): the hook blocks with 'This looks like a secret' ──
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_hook SessionEnd claude-key "$TMP/claude-key.jsonl" false BLUEPRINT_CAPTURE=always
    creqs=$( creq_paths ); cerr=$( cat "$TMP/cerr" )
    clines=$( printf '%s\n' "$cerr" | grep -c . )
    case $cerr in *'This looks like a secret'*'The next session in this repository raises it.'*) csaid=1 ;; *) csaid=0 ;; esac
    if [ "$cstatus" = 0 ] && [ "$creqs" = /secret-check ] && [ "$csaid" = 1 ] && [ "$clines" = 1 ]; then
      pass 'a pasted key, always: nothing but the secret check is sent, and one line says "This looks like a secret"'
    else
      fail 'a pasted key, always: nothing but the secret check is sent, and one line says "This looks like a secret"' \
        "exit $cstatus; expected requests [/secret-check]; actual [$creqs]; stderr lines $clines" "stderr: [$cerr]"
    fi

    # The person is not there at SessionEnd: the next session in this
    # repository raises the found secret, once, so they can redact, edit or send
    # anyway (F17, D64). A headless run or a person with capture off keeps it
    # for later; another repository's session is not told.
    cpend=''
    capture_hook SessionStart claude-next "$TMP/claude-key.jsonl" false CLAUDE_CODE_ENTRYPOINT=sdk-cli
    cpend="$cpend headless=$cstatus:$( wc -c <"$TMP/cout" | tr -d ' ' )"
    capture_hook SessionStart claude-next "$TMP/claude-key.jsonl" false BLUEPRINT_CAPTURE=off
    cpend="$cpend off=$cstatus:$( wc -c <"$TMP/cout" | tr -d ' ' )"
    capture_hook SessionStart claude-next "$TMP/claude-key.jsonl" false BLUEPRINT_CAPTURE_REPOSITORY=github.com/acme/other
    cpend="$cpend other=$cstatus:$( wc -c <"$TMP/cout" | tr -d ' ' )"
    capture_hook SessionStart claude-next "$TMP/claude-key.jsonl" false
    cout=$( cat "$TMP/cout" )
    cmiss=''
    for w in 'This looks like a secret' 'claude-key' 'github-pat' "blueprint-send --transcript $TMP/claude-key.jsonl --redact" '--text' '--anyway'; do
      case $cout in *"$w"*) ;; *) cmiss="$cmiss [$w]" ;; esac
    done
    case $cout in *"$CAP_KEY"*) cmiss="$cmiss [it prints the key itself]" ;; esac
    capture_hook SessionStart claude-after "$TMP/claude-key.jsonl" false
    cpend="$cpend again=$cstatus:$( wc -c <"$TMP/cout" | tr -d ' ' )"
    if [ "$cpend" = ' headless=0:0 off=0:0 other=0:0 again=0:0' ] && [ -z "$cmiss" ] && [ "$( creq_paths )" = /secret-check ]; then
      pass 'a pasted key, always: the next session in the repository raises it once, with redact, edit or send anyway (not headless, not off, not another repository)'
    else
      fail 'a pasted key, always: the next session in the repository raises it once, with redact, edit or send anyway (not headless, not off, not another repository)' \
        "silent runs [$cpend] (expected [ headless=0:0 off=0:0 other=0:0 again=0:0]); missing in the raise:$cmiss; requests [$( creq_paths )]" "stdout: [$cout]"
    fi

    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-key.jsonl"
    creqs=$( creq_paths ); cout=$( cat "$TMP/cout" )
    cmiss=''
    for w in 'This looks like a secret' 'Redact and send' '--redact' 'Edit' '--text' 'Send anyway' '--anyway' 'cannot be erased'; do
      case $cout in *"$w"*) ;; *) cmiss="$cmiss [$w]" ;; esac
    done
    case $cout in *"$CAP_KEY"*) cmiss="$cmiss [the warning prints the key itself]" ;; esac
    if [ "$cstatus" = 3 ] && [ "$creqs" = /secret-check ] && [ -z "$cmiss" ]; then
      pass 'a pasted key, blueprint-send: it blocks (exit 3) with "This looks like a secret" and offers redact, edit or send anyway'
    else
      fail 'a pasted key, blueprint-send: it blocks (exit 3) with "This looks like a secret" and offers redact, edit or send anyway' \
        "exit $cstatus (expected 3); requests [$creqs] (expected [/secret-check]); missing:$cmiss" "stdout: [$cout]"
    fi

    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-key.jsonl" --redact
    # The route counts in UTF-16 units, so the emoji before the key moves the
    # span one unit past a code-point count: the marker lands exactly on the key.
    if [ "$cstatus" = 0 ] && [ -s "$TMP/cupload" ] && ! grep -q "$CAP_KEY" "$TMP/cupload" \
       && grep -q 'my token 😀 is \[redacted: github-pat\] — Why' "$TMP/cupload" && grep -q 'END-OF-PROMPT' "$TMP/cupload"; then
      pass 'redact and send: the key is replaced by a marker and the rest is sent'
    else
      fail 'redact and send: the key is replaced by a marker and the rest is sent' "exit $cstatus" "stdout: [$( cat "$TMP/cout" )] stderr: [$( cat "$TMP/cerr" )]"
    fi

    # Its own conversation: the one above was redacted, a choice a later one
    # never re-decides.
    cp "$TMP/claude-key.jsonl" "$TMP/claude-key-anyway.jsonl"
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-key-anyway.jsonl" --anyway
    if [ "$cstatus" = 0 ] && grep -q "$CAP_KEY" "$TMP/cupload" 2>/dev/null; then
      pass 'send anyway: the text goes as it is'
    else
      fail 'send anyway: the text goes as it is' "exit $cstatus" "stdout: [$( cat "$TMP/cout" )] stderr: [$( cat "$TMP/cerr" )]"
    fi

    # A tool output is never cut inside a private key. `cat ~/.ssh/id_ed25519`
    # prints a 432-character file: cut at 400 it would keep the whole body and
    # drop the END line the private-key rule closes on, so nothing would match
    # and the key would go. A synthetic PEM of that shape (never a real key),
    # nothing after it; its body lines are KEYBODY1..KEYBODY5 and KEYB6.
    python3 - "$TMP/claude-sshkey.jsonl" <<'PYSSH'
import json, sys
body = ["KEYBODY%d" % i + "A" * 62 for i in range(1, 6)] + ["KEYB6A"]
pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n" + "".join(l + "\n" for l in body) + "-----END OPENSSH PRIVATE KEY-----\n"
assert len(pem) == 432, len(pem)
lines = [
    {"type": "user", "message": {"role": "user", "content": "which key does this box use?"}},
    {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "t9", "name": "Bash", "input": {"command": "cat ~/.ssh/id_ed25519"}}]}},
    {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t9", "content": pem}]}},
]
with open(sys.argv[1], "w", encoding="utf-8") as f:
    for l in lines:
        f.write(json.dumps(l) + "\n")
PYSSH
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-sshkey.jsonl"
    creqs=$( creq_paths ); cout=$( cat "$TMP/cout" )
    case $cout in *'This looks like a secret: 3 matches of private-key, private-key-open, private-key-whole, '*) csaid=1 ;; *) csaid=0 ;; esac
    if [ "$cstatus" = 3 ] && [ "$creqs" = /secret-check ] && [ ! -e "$TMP/cupload" ] && [ "$csaid" = 1 ]; then
      pass 'a tool output that is a whole private key file (432 characters) is not cut inside the key: the send blocks'
    else
      fail 'a tool output that is a whole private key file (432 characters) is not cut inside the key: the send blocks' \
        "exit $cstatus (expected 3); requests [$creqs] (expected [/secret-check]); uploaded: $( [ -e "$TMP/cupload" ] && echo "yes, key body lines $( grep -c 'KEYBODY\|KEYB6' "$TMP/cupload" )" || echo no ) (expected no)" \
        "stdout: [$cout]"
    fi
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-sshkey.jsonl" --redact
    if [ "$cstatus" = 0 ] && grep -q 'tool output: \[redacted: private-key-open\]' "$TMP/cupload" 2>/dev/null \
       && ! grep -q 'KEYBODY\|KEYB6' "$TMP/cupload" && grep -q 'which key does this box use?' "$TMP/cupload"; then
      pass 'redact and send: the private key a tool printed is replaced by a marker, no line of its body sent'
    else
      fail 'redact and send: the private key a tool printed is replaced by a marker, no line of its body sent' \
        "exit $cstatus (expected 0); private-key-open marker: $( grep -c 'redacted: private-key-open' "$TMP/cupload" 2>/dev/null ) (expected 1); key body lines sent: $( grep -c 'KEYBODY\|KEYB6' "$TMP/cupload" 2>/dev/null ) (expected 0)" \
        "stdout: [$( cat "$TMP/cout" )]"
    fi

    # Only a private key's header keeps the rest: a public PEM block (a
    # certificate) in a 600-character tool output is cut at 400 as any other.
    python3 - "$TMP/claude-cert.jsonl" <<'PYCERT'
import json, sys
out = "-----BEGIN CERTIFICATE-----\n" + "M" * 372 + "CERT-BEYOND-400" + "N" * 185 + "\n-----END CERTIFICATE-----\n"
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write(json.dumps({"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t8", "content": out}]}}) + "\n")
PYCERT
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-cert.jsonl"
    if [ "$cstatus" = 0 ] && grep -q "tool output: -----BEGIN CERTIFICATE-----" "$TMP/cupload" 2>/dev/null \
       && grep -qx "M* \[cut: 227 more characters\]" "$TMP/cupload" && ! grep -q 'CERT-BEYOND-400' "$TMP/cupload"; then
      pass 'a tool output with no private key header is still cut at 400 characters'
    else
      fail 'a tool output with no private key header is still cut at 400 characters' \
        "exit $cstatus (expected 0); past 400 sent: $( grep -c 'CERT-BEYOND-400' "$TMP/cupload" 2>/dev/null ) (expected 0)" \
        "upload: [$( cat "$TMP/cupload" 2>/dev/null )]"
    fi

    # Where the cut falls around keys, read from the text the secret check
    # gets: a short key inside the first 400 characters leaves the cut at 400
    # (WITHIN-400 kept, PAST-400 not), and a key whose header lies past the cut
    # is cut away (LATEKEY); a key with no END line moves the cut back to its
    # header's start, so nothing of it is kept (NOEND-TAIL, 543 characters
    # cut), nor of an EC key's scalar whose header starts at 360 with 10
    # characters left before 400 (ECSCALAR, 226 characters cut); of two keys
    # back to back, the
    # first crossing the cut is kept through its END line (FIRSTKEY5) and the
    # second, whose header then lies past the cut, is cut away whole (SECONDKEY)
    # with the 532 characters after; a header named in prose, without its
    # closing dashes, leaves the cut at 400 though an END line follows
    # (PROSE-TAIL); a lowercase key is kept through its END line (lckey5) and
    # nothing after it (LC-AFTER); a header with no END line of its own,
    # another key's header before the next END line, moves the cut back to
    # its start though a public key block (KEY----- markers) and that later
    # key follow: nothing of it (PARTIAL01), of the text between (MIDDLE-TEXT)
    # nor of the later key (UNCLOSEDK) is kept, 3246 characters cut; and an
    # unclosed header at 100 before a complete key whose header starts at 300
    # moves the cut back to 100: the complete key goes with it, whole
    # (UNCLOSEDHEAD, SECONDCOMPLETE, 644 characters cut); a 150-character
    # output, under 400, whose header at 50 has no END line is cut there too
    # (SHORTBODY, 100 characters cut).
    python3 - "$TMP/claude-keycuts.jsonl" <<'PYKC'
import json, sys
def key(word):
    return ("-----BEGIN OPENSSH PRIVATE KEY-----\n" + "".join(word + "%d" % i + "A" * (70 - len(word) - 1) + "\n" for i in range(1, 6))
            + "KEYB6A\n-----END OPENSSH PRIVATE KEY-----\n")
small = "-----BEGIN EC PRIVATE KEY-----\n" + "E" * 64 + "\n-----END EC PRIVATE KEY-----\n"
a = small + "w" * (400 - len(small) - len("WITHIN-400")) + "WITHIN-400" + "PAST-400 " + "v" * 50 + "\n" + key("LATEKEY")
b = "-----BEGIN OPENSSH PRIVATE KEY-----\n" + ("N" * 70 + "\n") * 7 + "NOEND-TAIL"
c = key("FIRSTKEY") + key("SECONDKEY") + "AFTER-KEYS" + "z" * 89
d = "docs/keys.md:3: keys start with -----BEGIN OPENSSH PRIVATE KEY\n" + "p" * 400 + "PROSE-TAIL\n-----END OPENSSH PRIVATE KEY-----\n"
e = key("lckey").lower() + "LC-AFTER" + "y" * 40
partial = "-----BEGIN RSA PRIVATE KEY-----\n" + "".join("PARTIAL%02d" % i + "Q" * 55 + "\n" for i in range(1, 6))
g = partial + "-----BEGIN PUBLIC KEY-----\nMFkw\n-----END PUBLIC KEY-----\n" + "MIDDLE-TEXT " * 200 + key("UNCLOSEDK")
h = "j" * 360 + "-----BEGIN EC PRIVATE KEY-----\n" + "".join("ECSCALAR%d" % i + "Z" * 55 + "\n" for i in range(1, 4))
i2 = "u" * 100 + "-----BEGIN RSA PRIVATE KEY-----\n" + "UNCLOSEDHEAD" + "Q" * 55 + "\n" + "s" * 100 + key("SECONDCOMPLETE") + "AFTER-SECOND"
k = "k" * 50 + "-----BEGIN DSA PRIVATE KEY-----\n" + "SHORTBODY" + "D" * 59
assert len(key("X")) == 432 and len(b) == 543 and len(k) == 150 and e.startswith("-----begin openssh private key-----")
assert g.index("MIDDLE-TEXT") > 400 and len(g) == 3246
assert h.index("-----BEGIN EC") == 360 and len(h) == 586
assert i2.index("-----BEGIN RSA") == 100 and i2.index("-----BEGIN OPENSSH") == 300 and i2.index("-----END OPENSSH") > 400 and len(i2) == 744
with open(sys.argv[1], "w", encoding="utf-8") as f:
    for i, out in enumerate((a, b, c, d, e, g, h, i2, k)):
        f.write(json.dumps({"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "k%d" % i, "content": out}]}}) + "\n")
PYKC
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-keycuts.jsonl"
    ccuts=$( python3 - "$TMP/creq" <<'PYKV'
import json, sys
t = "".join(json.loads(l)["body"]["text"] for l in open(sys.argv[1]) if l.strip() and json.loads(l)["path"] == "/secret-check")
if not t: print("the secret check got no text"); sys.exit()
bad = []
if "WITHIN-400" not in t: bad.append("a short key inside the first 400 characters moved the cut before 400")
if "PAST-400" in t: bad.append("text past 400 after a short key was kept")
if "LATEKEY" in t: bad.append("a key whose header lies past the cut was kept")
if "NOEND-TAIL" in t or "NNNN" in t or "tool output:  [cut: 543 more characters]" not in t: bad.append("a key with no END line was not cut at its header's start")
if "ECSCALAR" in t or "jjj [cut: 226 more characters]" not in t: bad.append("an EC key with no END line, its header at 360, was not cut at the header's start (%d ECSCALAR)" % t.count("ECSCALAR"))
if "FIRSTKEY5" not in t: bad.append("the first of two back-to-back keys was cut inside")
if "SECONDKEY" in t or "-----END OPENSSH PRIVATE KEY----- [cut: 532 more characters]" not in t:
    bad.append("two back-to-back keys were not cut at the first's END line")
if "PROSE-TAIL" in t: bad.append("a header named in prose, without its closing dashes, moved the cut")
if "lckey5" not in t or "LC-AFTER" in t or "-----end openssh private key----- [cut: 49 more characters]" not in t:
    bad.append("a lowercase key was not cut at its END line")
if "PARTIAL01" in t or "MIDDLE-TEXT" in t or "UNCLOSEDK" in t or "tool output:  [cut: 3246 more characters]" not in t:
    bad.append("a header with no END line of its own, another key's header before the next END line, was not cut at its start (PARTIAL01 %d, MIDDLE-TEXT %d, UNCLOSEDK %d)" % (t.count("PARTIAL01"), t.count("MIDDLE-TEXT"), t.count("UNCLOSEDK")))
if "UNCLOSEDHEAD" in t or "SECONDCOMPLETE" in t or "uuu [cut: 644 more characters]" not in t:
    bad.append("an unclosed header at 100 before a complete key at 300 was not cut at 100 (UNCLOSEDHEAD %d, SECONDCOMPLETE %d)" % (t.count("UNCLOSEDHEAD"), t.count("SECONDCOMPLETE")))
if "SHORTBODY" in t or "kkk [cut: 100 more characters]" not in t:
    bad.append("a 150-character output with an unclosed header at 50 was not cut at the header (%d SHORTBODY)" % t.count("SHORTBODY"))
print("; ".join(bad) or "ok")
PYKV
)
    if [ "$ccuts" = ok ]; then
      pass 'the cut around keys: a short key leaves it at 400, a key past it is cut away, a key with no END line is cut at its header, back-to-back keys are cut between them, a prose header leaves it at 400, a lowercase key is kept to its END line, an unclosed header before another key is cut at its start, an output under 400 is cut at its unclosed header'
    else
      fail 'the cut around keys: a short key leaves it at 400, a key past it is cut away, a key with no END line is cut at its header, back-to-back keys are cut between them, a prose header leaves it at 400, a lowercase key is kept to its END line, an unclosed header before another key is cut at its start, an output under 400 is cut at its unclosed header' "$ccuts"
    fi

    # A tool call's input is one line of JSON (its newlines escaped), so the
    # cut after a key ends at the key's END marker, not at a newline: a Write
    # of a key followed by 14 KB of other content keeps nothing past the
    # marker (TRAILING-CONTENT), so --redact never sends that content whole.
    python3 - "$TMP/claude-writekey.jsonl" <<'PYWK'
import json, sys
pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n" + "".join("WKEYBODY%d" % i + "A" * 61 + "\n" for i in range(1, 6)) + "-----END OPENSSH PRIVATE KEY-----\n"
inp = {"file_path": "/repo/fixtures/deploy_key", "content": pem + "TRAILING-CONTENT " * 840}
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write(json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "w1", "name": "Write", "input": inp}]}}) + "\n")
PYWK
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-writekey.jsonl"
    cwk=$( python3 - "$TMP/creq" <<'PYWV'
import json, re, sys
t = "".join(json.loads(l)["body"]["text"] for l in open(sys.argv[1]) if l.strip() and json.loads(l)["path"] == "/secret-check")
if not t: print("the secret check got no text"); sys.exit()
bad = []
if "WKEYBODY5" not in t: bad.append("the key was cut inside")
if not re.search(r"-----END OPENSSH PRIVATE KEY----- \[cut: \d+ more characters\]", t): bad.append("the cut is not at the key's END marker")
n = t.count("TRAILING-CONTENT")
if n: bad.append("%d characters past the END marker kept (%d TRAILING-CONTENT)" % (len(t.split("PRIVATE KEY-----")[-1].split(" [cut:")[0]), n))
print("; ".join(bad) or "ok")
PYWV
)
    if [ "$cwk" = ok ] && [ "$cstatus" = 3 ]; then
      pass 'a tool call that writes a key and more is cut at the key'"'"'s END marker: nothing past it goes to the secret check'
    else
      fail 'a tool call that writes a key and more is cut at the key'"'"'s END marker: nothing past it goes to the secret check' "$cwk; exit $cstatus (expected 3)"
    fi

    printf 'user: my token is %s\n' "$CAP_KEY" >"$TMP/cedit-still.txt"
    printf 'user: my token is [removed by hand]\n' >"$TMP/cedit.txt"
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-key.jsonl" --text "$TMP/cedit-still.txt"
    cstill="$cstatus:$( creq_paths )"
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-key.jsonl" --text "$TMP/cedit.txt"
    if [ "$cstill" = '3:/secret-check' ] && [ "$cstatus" = 0 ] && cmp -s "$TMP/cedit.txt" "$TMP/cupload"; then
      pass 'edit: the edited text is checked again, and sent as edited once it holds no secret'
    else
      fail 'edit: the edited text is checked again, and sent as edited once it holds no secret' \
        "edited-but-still-a-key: [$cstill] (expected 3:/secret-check); clean edit: exit $cstatus" "stdout: [$( cat "$TMP/cout" )]"
    fi

    # An edit is new text the person was shown no warning about: --anyway or
    # --redact beside --text covers none of it, so a key left in it blocks.
    cedits=''
    for cway in anyway redact; do
      : >"$TMP/creq"; rm -f "$TMP/cupload"
      capture_send -- --transcript "$TMP/claude-key.jsonl" --text "$TMP/cedit-still.txt" --$cway
      cedits="$cedits $cway=$cstatus:$( creq_paths ):$( [ -e "$TMP/cupload" ] && echo uploaded || echo none )"
    done
    if [ "$cedits" = ' anyway=3:/secret-check:none redact=3:/secret-check:none' ]; then
      pass 'edit: a choice beside --text covers none of the edit, so a key left in it blocks'
    else
      fail 'edit: a choice beside --text covers none of the edit, so a key left in it blocks' \
        "[$cedits] (expected [ anyway=3:/secret-check:none redact=3:/secret-check:none])" "stdout: [$( cat "$TMP/cout" )]"
    fi

    # The person's choice covers the messages they were shown (F17, F9, F10):
    # the session's end sends those messages the way they chose (redacted, or as
    # they are) and checks every later message again, a secret there blocking
    # and leaving a pending record as with no choice (a later --consent keeps the
    # choice); an edited send is final, and the session's end sends nothing again.
    cpending="$chome/.local/state/blueprint/capture/pending/github.com_acme_shop"
    cexpect='/secret-check /documents/upload-grant /bucket /api/conversations/capture-conversation'
    cp "$TMP/claude-key.jsonl" "$TMP/claude-redact.jsonl"
    capture_send -- --transcript "$TMP/claude-redact.jsonl" --redact
    csent=$cstatus
    capture_send -- --consent --session-id claude-redact
    csent="$csent$cstatus"
    printf '%s\n' '{"type": "user", "message": {"role": "user", "content": "LATER-TURN after the redact"}}' >>"$TMP/claude-redact.jsonl"
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_hook SessionEnd claude-redact "$TMP/claude-redact.jsonl" false
    creqs=$( creq_paths )
    if [ "$csent" = 00 ] && [ "$cstatus" = 0 ] && [ ! -e "$cpending/claude-redact.json" ] && [ "$creqs" = "$cexpect" ] \
       && ! grep -q "$CAP_KEY" "$TMP/cupload" 2>/dev/null && grep -q '\[redacted: github-pat\]' "$TMP/cupload" 2>/dev/null \
       && grep -q 'LATER-TURN after the redact' "$TMP/cupload" 2>/dev/null; then
      pass 'redact sticks: the session end sends the conversation redacted, later turns included, and leaves nothing pending'
    else
      fail 'redact sticks: the session end sends the conversation redacted, later turns included, and leaves nothing pending' \
        "send exit $csent; end exit $cstatus; pending record: $( [ -e "$cpending/claude-redact.json" ] && echo yes || echo no ) (expected no); requests [$creqs] (expected [$cexpect]); key sent: $( grep -c "$CAP_KEY" "$TMP/cupload" 2>/dev/null ); later turn sent: $( grep -c 'LATER-TURN' "$TMP/cupload" 2>/dev/null )" \
        "stderr: [$( cat "$TMP/cerr" )]"
    fi

    cp "$TMP/claude-key.jsonl" "$TMP/claude-anyway.jsonl"
    capture_send -- --transcript "$TMP/claude-anyway.jsonl" --anyway
    csent=$cstatus
    printf '%s\n' '{"type": "user", "message": {"role": "user", "content": "LATER-TURN after the anyway"}}' >>"$TMP/claude-anyway.jsonl"
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_hook SessionEnd claude-anyway "$TMP/claude-anyway.jsonl" false
    creqs=$( creq_paths )
    if [ "$csent" = 0 ] && [ "$cstatus" = 0 ] && [ ! -e "$cpending/claude-anyway.json" ] && [ "$creqs" = "$cexpect" ] \
       && grep -q "$CAP_KEY" "$TMP/cupload" 2>/dev/null && grep -q 'LATER-TURN after the anyway' "$TMP/cupload" 2>/dev/null; then
      pass 'send anyway sticks for the messages shown: the session end checks again and sends them as they are, later turns included, nothing pending'
    else
      fail 'send anyway sticks for the messages shown: the session end checks again and sends them as they are, later turns included, nothing pending' \
        "send exit $csent; end exit $cstatus; pending record: $( [ -e "$cpending/claude-anyway.json" ] && echo yes || echo no ) (expected no); requests [$creqs] (expected [$cexpect]); approved key sent: $( grep -c "$CAP_KEY" "$TMP/cupload" 2>/dev/null ); later turn sent: $( grep -c 'LATER-TURN' "$TMP/cupload" 2>/dev/null )" \
        "stderr: [$( cat "$TMP/cerr" )]"
    fi

    # A key pasted after the choice is not covered by it (F10): sent anyway or
    # redacted, a later message holding a second token makes the session's end
    # send nothing but the check, and leave a pending record whose warning names
    # only the new match (one match, on the new message's line of the text).
    CAP_KEY2='ghp_ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ'
    cstate="$chome/.local/state/blueprint/capture"
    for cway in anyway redact; do
      cp "$TMP/claude-key.jsonl" "$TMP/claude-later-$cway.jsonl"
      capture_send -- --transcript "$TMP/claude-later-$cway.jsonl" --$cway
      csent=$cstatus
      printf '{"type": "user", "message": {"role": "user", "content": "LATER-TURN %s"}}\n' "$CAP_KEY2" >>"$TMP/claude-later-$cway.jsonl"
      : >"$TMP/creq"; rm -f "$TMP/cupload"
      capture_hook SessionEnd "claude-later-$cway" "$TMP/claude-later-$cway.jsonl" false
      creqs=$( creq_paths )
      cline=$( grep -n "$CAP_KEY2" "$cstate/claude-later-$cway.txt" 2>/dev/null | cut -d: -f1 )
      cwarn=$( python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["lines"][0])' "$cpending/claude-later-$cway.json" 2>/dev/null )
      case $cwarn in *"This looks like a secret: 1 match of github-pat, the first on line $cline of the conversation."*) csaid=1 ;; *) csaid=0 ;; esac
      if [ "$csent" = 0 ] && [ "$cstatus" = 0 ] && [ "$creqs" = /secret-check ] && [ ! -e "$TMP/cupload" ] \
         && [ -n "$cline" ] && [ "$cline" != 1 ] && [ "$csaid" = 1 ]; then
        pass "a key after --$cway: the session end checks the later message, sends nothing and leaves a pending record naming only the new match"
      else
        fail "a key after --$cway: the session end checks the later message, sends nothing and leaves a pending record naming only the new match" \
          "send exit $csent; end exit $cstatus; requests [$creqs] (expected [/secret-check]); uploaded: $( [ -e "$TMP/cupload" ] && echo yes || echo no ) (expected no); new key on line [$cline]; pending warning: [$cwarn]" \
          "stderr: [$( cat "$TMP/cerr" )]"
      fi
    done

    # The choice covers what the warning showed: a key pasted between the
    # warning and the --anyway is checked by that send, which blocks again.
    cp "$TMP/claude-key.jsonl" "$TMP/claude-shown.jsonl"
    capture_send -- --transcript "$TMP/claude-shown.jsonl"
    csent=$cstatus
    printf '{"type": "user", "message": {"role": "user", "content": "LATER-TURN %s"}}\n' "$CAP_KEY2" >>"$TMP/claude-shown.jsonl"
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-shown.jsonl" --anyway
    creqs=$( creq_paths ); cout=$( cat "$TMP/cout" )
    cline=$( grep -n "$CAP_KEY2" "$cstate/claude-shown.txt" 2>/dev/null | cut -d: -f1 )
    case $cout in *"This looks like a secret: 1 match of github-pat, the first on line $cline of the conversation."*) csaid=1 ;; *) csaid=0 ;; esac
    if [ "$csent" = 3 ] && [ "$cstatus" = 3 ] && [ "$creqs" = /secret-check ] && [ ! -e "$TMP/cupload" ] \
       && [ -n "$cline" ] && [ "$cline" != 1 ] && [ "$csaid" = 1 ]; then
      pass 'send anyway covers the messages the warning showed: a key pasted after the warning blocks the --anyway, naming only the new match'
    else
      fail 'send anyway covers the messages the warning showed: a key pasted after the warning blocks the --anyway, naming only the new match' \
        "warning exit $csent (expected 3); anyway exit $cstatus (expected 3); requests [$creqs] (expected [/secret-check]); uploaded: $( [ -e "$TMP/cupload" ] && echo yes || echo no ) (expected no); new key on line [$cline]" \
        "stdout: [$cout]"
    fi

    # A match covered by a choice lies wholly inside the messages it covers
    # (F11). A message sent anyway that only mentions a private key's header is
    # harmless alone; a key pasted later makes the private-key rule (which runs
    # across lines to the first KEY-----) match from that mention into the new
    # message. That match is not the old choice's: the session's end blocks, and
    # its warning counts it beside private-key-whole's match of the new key.
    CAP_PEM_LINE='b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW'
    printf '{"type": "user", "message": {"role": "user", "content": "my token is %s and my deploy keys are PEM files; they start with -----BEGIN OPENSSH PRIVATE KEY----- and I keep them in ~/.ssh. Why do retries stop at three?"}}\n' "$CAP_KEY" >"$TMP/claude-mention.jsonl"
    printf '%s\n' '{"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "Because the broker caps them."}]}}' >>"$TMP/claude-mention.jsonl"
    capture_send -- --transcript "$TMP/claude-mention.jsonl"
    csent=$cstatus
    capture_send -- --transcript "$TMP/claude-mention.jsonl" --anyway
    csent="$csent$cstatus"
    printf '{"type": "user", "message": {"role": "user", "content": "here is the one that fails:\\n-----BEGIN OPENSSH PRIVATE KEY-----\\n%s\\n%s\\n%s\\n-----END OPENSSH PRIVATE KEY-----"}}\n' \
      "$CAP_PEM_LINE" "$CAP_PEM_LINE" "$CAP_PEM_LINE" >>"$TMP/claude-mention.jsonl"
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_hook SessionEnd claude-mention "$TMP/claude-mention.jsonl" false
    creqs=$( creq_paths )
    cwarn=$( python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["lines"][0])' "$cpending/claude-mention.json" 2>/dev/null )
    case $cwarn in *'This looks like a secret: 3 matches of private-key, private-key-open, private-key-whole, '*) csaid=1 ;; *) csaid=0 ;; esac
    if [ "$csent" = 30 ] && [ "$cstatus" = 0 ] && [ "$creqs" = /secret-check ] && [ ! -e "$TMP/cupload" ] && [ "$csaid" = 1 ]; then
      pass 'a match that runs from a message sent anyway into a later one is not covered: the session end blocks on the pasted key'
    else
      fail 'a match that runs from a message sent anyway into a later one is not covered: the session end blocks on the pasted key' \
        "warning, anyway exits $csent (expected 30); end exit $cstatus; requests [$creqs] (expected [/secret-check]); uploaded: $( [ -e "$TMP/cupload" ] && echo "yes, key body lines $( grep -c "$CAP_PEM_LINE" "$TMP/cupload" )" || echo no ) (expected no); pending warning: [$cwarn]" \
        "stderr: [$( cat "$TMP/cerr" )]"
    fi

    # The same shape redacted first: the person answers the session end's
    # warning with --anyway, which covers only the pasted key's message. The
    # match runs through text chosen to be redacted (the mention), the "\n\n"
    # between messages included, so it is redacted, not sent as it is.
    sed -n 1,2p "$TMP/claude-mention.jsonl" >"$TMP/claude-mention-r.jsonl"
    capture_send -- --transcript "$TMP/claude-mention-r.jsonl"
    csent=$cstatus
    capture_send -- --transcript "$TMP/claude-mention-r.jsonl" --redact
    csent="$csent$cstatus"
    sed -n 3p "$TMP/claude-mention.jsonl" >>"$TMP/claude-mention-r.jsonl"
    capture_hook SessionEnd claude-mention-r "$TMP/claude-mention-r.jsonl" false
    [ -e "$cpending/claude-mention-r.json" ] && csent="${csent}p" || csent="${csent}-"
    rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-mention-r.jsonl" --anyway
    csent="$csent$cstatus"
    if [ "$csent" = 30p0 ] && grep -q '\[redacted: private-key\]' "$TMP/cupload" 2>/dev/null \
       && ! grep -q 'they start with -----BEGIN' "$TMP/cupload" && ! grep -q "$CAP_KEY" "$TMP/cupload"; then
      pass 'a match that runs from a redacted message into one sent anyway is redacted'
    else
      fail 'a match that runs from a redacted message into one sent anyway is redacted' \
        "warning, redact, pending, anyway: [$csent] (expected [30p0]); private-key marker: $( grep -c '\[redacted: private-key\]' "$TMP/cupload" 2>/dev/null ) (expected 1); mention sent: $( grep -c 'they start with -----BEGIN' "$TMP/cupload" 2>/dev/null ) (expected 0)" \
        "stdout: [$( cat "$TMP/cout" )]"
    fi

    # A choice is by message (F12): a later choice applies only to the messages
    # no earlier choice covers, and never re-decides one. Redact a key, paste a
    # second, answer the session end's warning with --anyway: the first stays
    # redacted, the second goes as it is; and the other way round. The session's
    # end after that sends each message the way its own choice says.
    for cways in redact:anyway anyway:redact; do
      cfirst=${cways%%:*} csecond=${cways#*:}
      ct="$TMP/claude-two-$cfirst.jsonl"
      printf '{"type": "user", "message": {"role": "user", "content": "FIRST %s"}}\n' "$CAP_KEY" >"$ct"
      capture_send -- --transcript "$ct"
      csent=$cstatus
      capture_send -- --transcript "$ct" --$cfirst
      csent="$csent$cstatus"
      printf '{"type": "user", "message": {"role": "user", "content": "SECOND %s"}}\n' "$CAP_KEY2" >>"$ct"
      capture_hook SessionEnd "claude-two-$cfirst" "$ct" false
      [ -e "$cpending/claude-two-$cfirst.json" ] && csent="${csent}p" || csent="${csent}-"
      rm -f "$TMP/cupload"
      capture_send -- --transcript "$ct" --$csecond
      csent="$csent$cstatus"
      cgot=$( python3 - "$TMP/cupload" "$CAP_KEY" "$CAP_KEY2" <<'PYTWO'
import sys
try:
    t = open(sys.argv[1], encoding="utf-8").read()
except OSError:
    print("nothing"); sys.exit()
def shown(word, key):
    line = [l for l in t.split("\n") if word in l]
    return "%s=%s" % (word, "raw" if line and key in line[0] else "redacted" if line and "[redacted: github-pat]" in line[0] else "?")
print(shown("FIRST", sys.argv[2]), shown("SECOND", sys.argv[3]))
PYTWO
)
      rm -f "$TMP/cupload"
      capture_hook SessionEnd "claude-two-$cfirst" "$ct" false
      cend=$cstatus
      cgot2=$( python3 -c 'import sys; t=open(sys.argv[1]).read(); print(("K1" if sys.argv[2] in t else "-") + ("K2" if sys.argv[3] in t else "-"))' "$TMP/cupload" "$CAP_KEY" "$CAP_KEY2" 2>/dev/null )
      if [ "$cfirst" = redact ]; then cwant='FIRST=redacted SECOND=raw' cwant2=-K2; else cwant='FIRST=raw SECOND=redacted' cwant2=K1-; fi
      if [ "$csent" = 30p0 ] && [ "$cgot" = "$cwant" ] && [ "$cend" = 0 ] && [ "$cgot2" = "$cwant2" ]; then
        pass "--$csecond after --$cfirst covers only the new message: the first key stays as --$cfirst left it, at the send and at the session end"
      else
        fail "--$csecond after --$cfirst covers only the new message: the first key stays as --$cfirst left it, at the send and at the session end" \
          "warning, $cfirst, pending, $csecond: [$csent] (expected [30p0]); sent [$cgot] (expected [$cwant]); session end exit $cend, keys sent [$cgot2] (expected [$cwant2])" \
          "stdout: [$( cat "$TMP/cout" )] stderr: [$( cat "$TMP/cerr" )]"
      fi
    done

    cp "$TMP/claude-key.jsonl" "$TMP/claude-edited.jsonl"
    capture_send -- --transcript "$TMP/claude-edited.jsonl" --text "$TMP/cedit.txt"
    csent=$cstatus
    printf '%s\n' '{"type": "user", "message": {"role": "user", "content": "LATER-TURN after the edit"}}' >>"$TMP/claude-edited.jsonl"
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_hook SessionEnd claude-edited "$TMP/claude-edited.jsonl" false BLUEPRINT_CAPTURE=always
    creqs=$( creq_paths )
    if [ "$csent" = 0 ] && [ "$cstatus" = 0 ] && [ ! -e "$cpending/claude-edited.json" ] && [ -z "$creqs" ]; then
      pass 'edit is final: the session end, even in always, sends an edited conversation nothing again and leaves nothing pending'
    else
      fail 'edit is final: the session end, even in always, sends an edited conversation nothing again and leaves nothing pending' \
        "send exit $csent; end exit $cstatus; pending record: $( [ -e "$cpending/claude-edited.json" ] && echo yes || echo no ) (expected no); requests [$creqs] (expected none)" \
        "stderr: [$( cat "$TMP/cerr" )]"
    fi

    # A conversation over the route's 1 MiB is checked in pieces, and a key in
    # the second piece is still found where it is.
    write_transcript "$TMP/claude-big.jsonl" big
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-big.jsonl" --redact
    cchecks=$( creq_paths | tr ' ' '\n' | grep -c '^/secret-check$' )
    if [ "$cstatus" = 0 ] && [ "$cchecks" -ge 2 ] && ! grep -q "$CAP_KEY" "$TMP/cupload" && grep -q 'then 😀 \[redacted: github-pat\] at the end' "$TMP/cupload"; then
      pass 'a conversation over 1 MiB is checked in pieces, and a key in a later piece is redacted where it is'
    else
      fail 'a conversation over 1 MiB is checked in pieces, and a key in a later piece is redacted where it is' "exit $cstatus; secret checks $cchecks (expected >= 2)" "stdout: [$( cat "$TMP/cout" )]"
    fi

    # Two rules' spans overlap (the route returns every rule's matches, sorted
    # by start, not merged): the redaction runs to the furthest end, so no tail
    # of the key goes out (F5).
    write_transcript "$TMP/claude-overlap.jsonl" overlap
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-overlap.jsonl" --redact
    if [ "$cstatus" = 0 ] && [ -s "$TMP/cupload" ] && ! grep -q 'klmnopqrstuvwxyz' "$TMP/cupload" \
       && grep -q 'set \[redacted: generic-api-key\] in the env' "$TMP/cupload"; then
      pass 'redact: overlapping spans of two rules are redacted to the furthest end, no tail of the key sent'
    else
      fail 'redact: overlapping spans of two rules are redacted to the furthest end, no tail of the key sent' \
        "exit $cstatus; sent: [$( grep -o 'set .\{0,80\}in the env' "$TMP/cupload" 2>/dev/null )] (expected [set [redacted: generic-api-key] in the env])"
    fi

    # A private key that runs across the first piece's end (character 892,928)
    # is still found: the second piece starts OVERLAP blocks before that cut,
    # so it holds the whole key (F6). With no overlap neither piece holds it.
    write_transcript "$TMP/claude-pem.jsonl" pem
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send -- --transcript "$TMP/claude-pem.jsonl"
    cchecks=$( creq_paths | tr ' ' '\n' | grep -c '^/secret-check$' )
    case $( cat "$TMP/cout" ) in *'This looks like a secret'*private-key*) csaid=1 ;; *) csaid=0 ;; esac
    if [ "$cstatus" = 3 ] && [ "$cchecks" -ge 2 ] && [ "$csaid" = 1 ] && [ ! -s "$TMP/cupload" ]; then
      pass 'a private key across the boundary between two pieces of the secret check is found (the pieces overlap)'
    else
      fail 'a private key across the boundary between two pieces of the secret check is found (the pieces overlap)' \
        "exit $cstatus (expected 3); secret checks $cchecks (expected >= 2); private-key named: $csaid; uploaded: $( [ -s "$TMP/cupload" ] && echo yes || echo no )" "stdout: [$( cat "$TMP/cout" )]"
    fi

    # Sent once by blueprint-send, the session is not asked again at its Stop;
    # the send was its person's yes, so its end sends it again, whole.
    : >"$TMP/creq"
    capture_send -- --transcript "$TMP/claude-7f3a.jsonl" --session-id claude-sent
    csent=$cstatus
    capture_hook Stop claude-sent "$TMP/claude-7f3a.jsonl" false
    csentstop="$cstatus:$( cat "$TMP/cout" )"
    : >"$TMP/creq"
    capture_hook SessionEnd claude-sent "$TMP/claude-7f3a.jsonl" false
    creqs=$( creq_paths )
    cexpect='/secret-check /documents/upload-grant /bucket /api/conversations/capture-conversation'
    if [ "$csent" = 0 ] && [ "$csentstop" = '0:' ] && [ "$creqs" = "$cexpect" ]; then
      pass 'ask: a session already sent with blueprint-send is not asked at its Stop, and its end sends it again, whole'
    else
      fail 'ask: a session already sent with blueprint-send is not asked at its Stop, and its end sends it again, whole' \
        "send exit $csent; Stop [$csentstop] (expected 0:); session end requests [$creqs] (expected [$cexpect])"
    fi

    # Any value but off, ask and always reads as ask, which sends nothing unasked.
    : >"$TMP/creq"
    capture_hook Stop claude-bogus "$TMP/claude-7f3a.jsonl" false BLUEPRINT_CAPTURE=yes-please
    case $( cat "$TMP/cout" ) in *'"decision": "block"'*"Send this conversation to Blueprint's memory?"*) cbog=asks ;; *) cbog=silent ;; esac
    if [ "$cstatus" = 0 ] && [ "$cbog" = asks ] && [ -z "$( creq_paths )" ]; then
      pass 'an unknown BLUEPRINT_CAPTURE value reads as ask: it asks and sends nothing'
    else
      fail 'an unknown BLUEPRINT_CAPTURE value reads as ask: it asks and sends nothing' "exit $cstatus; $cbog; requests [$( creq_paths )]"
    fi

    # No Blueprint host, or no token the hook can read (the blueprint CLI keeps
    # a sign-in in the OS keychain unless `--store file`): no ask (F3, D64).
    # Without a token it says once a session, in one line, how to give it one,
    # and blueprint-send says the same.
    mv "$cwork/.git/blueprint-connection.json" "$TMP/conn.keep"
    capture_hook Stop claude-nohost "$TMP/claude-7f3a.jsonl" false
    cnohost="$cstatus:$( cat "$TMP/cout" )"
    mv "$TMP/conn.keep" "$cwork/.git/blueprint-connection.json"
    mv "$chome/.config/blueprint/credentials.json" "$TMP/cred.keep"
    capture_hook Stop claude-nosign "$TMP/claude-7f3a.jsonl" false
    cnosign="$cstatus:$( cat "$TMP/cout" )"
    cnosignerr=$( cat "$TMP/cerr" )
    capture_hook Stop claude-nosign "$TMP/claude-7f3a.jsonl" false
    cnosign2="$cstatus:$( cat "$TMP/cout" )$( cat "$TMP/cerr" )"
    capture_send -- --transcript "$TMP/claude-7f3a.jsonl"
    cnosendout="$cstatus:$( cat "$TMP/cout" )"
    cmiss=''
    for w in 'blueprint login --host' '--store file' 'BLUEPRINT_ACCESS_TOKEN'; do
      case $cnosignerr in *"$w"*) ;; *) cmiss="$cmiss [hook: $w]" ;; esac
      case $cnosendout in *"$w"*) ;; *) cmiss="$cmiss [send: $w]" ;; esac
    done
    [ "$( printf '%s\n' "$cnosignerr" | grep -c . )" = 1 ] || cmiss="$cmiss [hook: not one line]"
    case $cnosendout in 1:*) ;; *) cmiss="$cmiss [send: exit not 1]" ;; esac
    if [ "$cnosign|$cnosign2" = '0:|0:' ] && [ -z "$cmiss" ]; then
      pass 'no readable token: ask stays silent and says once, in one line, to sign in with --store file or set BLUEPRINT_ACCESS_TOKEN; blueprint-send says the same'
    else
      fail 'no readable token: ask stays silent and says once, in one line, to sign in with --store file or set BLUEPRINT_ACCESS_TOKEN; blueprint-send says the same' \
        "first Stop [$cnosign] (expected 0:), second Stop [$cnosign2] (expected 0:); missing:$cmiss" "hook stderr: [$cnosignerr] send: [$cnosendout]"
    fi
    # BLUEPRINT_HOST_URL and BLUEPRINT_ACCESS_TOKEN stand in for the record and
    # the credentials file, and the env host attaches no connected session.
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send BLUEPRINT_HOST_URL="http://127.0.0.1:$CAPTURE_PORT" BLUEPRINT_ACCESS_TOKEN=pv4k_env -- --transcript "$TMP/claude-7f3a.jsonl"
    cenv=$( python3 -c 'import json,sys
r = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
c = [x for x in r if x["path"].endswith("capture-conversation")]
print(sorted({x["auth"] for x in r if x["path"] != "/bucket"}), c and ("session" in c[0]["body"]))' "$TMP/creq" )
    mv "$TMP/cred.keep" "$chome/.config/blueprint/credentials.json"
    if [ "$cnohost|$cnosign" = '0:|0:' ] && [ "$cstatus" = 0 ] && [ "$cenv" = "['Bearer pv4k_env'] False" ]; then
      pass 'no host or no sign-in: no ask; BLUEPRINT_HOST_URL and BLUEPRINT_ACCESS_TOKEN stand in, with no connected session attached'
    else
      fail 'no host or no sign-in: no ask; BLUEPRINT_HOST_URL and BLUEPRINT_ACCESS_TOKEN stand in, with no connected session attached' \
        "no host [$cnohost]; no sign-in [$cnosign]; env send exit $cstatus, auth and session [$cenv]"
    fi

    # Blueprint refuses the capture: one line carrying its message.
    capture_send BLUEPRINT_CAPTURE_REPOSITORY=github.com/acme/refused -- --transcript "$TMP/claude-7f3a.jsonl"
    cout=$( cat "$TMP/cout" ); clines=$( printf '%s\n' "$cout" | grep -c . )
    case $cout in *"under another org's prefix"*) csaid=1 ;; *) csaid=0 ;; esac
    if [ "$cstatus" = 1 ] && [ "$clines" = 1 ] && [ "$csaid" = 1 ]; then
      pass 'a refused capture: exit 1 and one line with Blueprint'"'"'s message'
    else
      fail 'a refused capture: exit 1 and one line with Blueprint'"'"'s message' "exit $cstatus; lines $clines" "stdout: [$cout]"
    fi

    # ── /blueprint-send any time: this session's transcript, found by its project ──
    cconf="$TMP/cconfig"
    # Claude Code names a project's folder by its resolved path, each other
    # character a dash (/tmp is /private/tmp on macOS).
    cslug=$( python3 -c 'import os,re,sys; print(re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(sys.argv[1])))' "$cwork" )
    rm -rf "$cconf"; mkdir -p "$cconf/projects/$cslug"
    cp "$TMP/claude-7f3a.jsonl" "$cconf/projects/$cslug/claude-old.jsonl"
    touch -t 202601010000 "$cconf/projects/$cslug/claude-old.jsonl"
    cp "$TMP/claude-7f3a.jsonl" "$cconf/projects/$cslug/claude-now.jsonl"
    : >"$TMP/creq"; rm -f "$TMP/cupload"
    capture_send CLAUDE_CONFIG_DIR="$cconf" --
    cconv=$( python3 -c 'import json,sys
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r["path"].endswith("capture-conversation"): print(r["body"]["conversation"])' "$TMP/creq" )
    if [ "$cstatus" = 0 ] && [ "$cconv" = claude-now ]; then
      pass 'blueprint-send with no arguments sends this session: the newest transcript of this project'
    else
      fail 'blueprint-send with no arguments sends this session: the newest transcript of this project' \
        "exit $cstatus; expected conversation claude-now; actual [$cconv]" "stderr: [$( cat "$TMP/cerr" )]"
    fi
    : >"$TMP/creq"
    capture_send CLAUDE_CONFIG_DIR="$cconf" -- --session-id claude-old
    cconv=$( python3 -c 'import json,sys
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r["path"].endswith("capture-conversation"): print(r["body"]["conversation"])' "$TMP/creq" )
    if [ "$cstatus" = 0 ] && [ "$cconv" = claude-old ]; then
      pass 'blueprint-send --session-id sends that conversation of this project'
    else
      fail 'blueprint-send --session-id sends that conversation of this project' "exit $cstatus; expected claude-old; actual [$cconv]" "stdout: [$( cat "$TMP/cout" )]"
    fi

    # ── Blueprint unreachable: fail open, one line ──
    stop_capture_server
    capture_hook SessionEnd claude-7f3a "$TMP/claude-7f3a.jsonl" false BLUEPRINT_CAPTURE=always
    cerr=$( cat "$TMP/cerr" ); clines=$( printf '%s\n' "$cerr" | grep -c . )
    case $cerr in *unreachable*) csaid=1 ;; *) csaid=0 ;; esac
    if [ "$cstatus" = 0 ] && [ "$clines" = 1 ] && [ "$csaid" = 1 ] && [ ! -s "$TMP/cout" ]; then
      pass 'Blueprint unreachable at the session end: exit 0 and one line saying so'
    else
      fail 'Blueprint unreachable at the session end: exit 0 and one line saying so' "exit $cstatus; stderr lines $clines" "stderr: [$cerr]"
    fi
    capture_send -- --transcript "$TMP/claude-7f3a.jsonl"
    cout=$( cat "$TMP/cout" ); clines=$( printf '%s\n' "$cout" | grep -c . )
    case $cout in *unreachable*) csaid=1 ;; *) csaid=0 ;; esac
    if [ "$cstatus" = 1 ] && [ "$clines" = 1 ] && [ "$csaid" = 1 ]; then
      pass 'blueprint-send with Blueprint unreachable: one line, exit 1, nothing sent'
    else
      fail 'blueprint-send with Blueprint unreachable: one line, exit 1, nothing sent' "exit $cstatus; lines $clines" "stdout: [$cout] stderr: [$( cat "$TMP/cerr" )]"
    fi

    # Never blocks, whatever arrives: no payload, garbage, no project dir.
    cbad=''
    for ev in Stop SessionEnd SessionStart; do
      for cscript in $( capture_args "$ev" ); do
        cap_env BLUEPRINT_CAPTURE=always "$HOOK_SH" "$cscript" >/dev/null 2>&1 </dev/null || cbad="$cbad $ev-empty"
        printf 'not json' | cap_env "$HOOK_SH" "$cscript" >/dev/null 2>&1 || cbad="$cbad $ev-garbage"
        env -u CLAUDE_PROJECT_DIR BLUEPRINT_CAPTURE_REPOSITORY=x "$HOOK_SH" "$cscript" >/dev/null 2>&1 </dev/null || cbad="$cbad $ev-no-project"
      done
    done
    if [ -z "$cbad" ] && [ -n "$( capture_args Stop )" ]; then
      pass 'an empty payload, garbage and no CLAUDE_PROJECT_DIR all exit 0'
    else
      fail 'an empty payload, garbage and no CLAUDE_PROJECT_DIR all exit 0' "non-zero on:$cbad"
    fi
  fi
  stop_capture_server
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
    'CLAUDE_PLUGIN_ROOT}/hooks/blueprint-session-channel.sh'
  assert_json 'it sets an explicit timeout of 5s' '"timeout": *5'
  assert_json 'it points at the shipped script via ${CLAUDE_PLUGIN_ROOT}' 'CLAUDE_PLUGIN_ROOT}/hooks/blueprint-pending.sh'
  assert_json 'it declares a PreToolUse hook' '"PreToolUse"'
  assert_json 'matched on the Bash tool' '"matcher": *"Bash"'
  assert_json 'and points that one at the lane git guard' 'CLAUDE_PLUGIN_ROOT}/hooks/lane-git-guard.sh'
  assert_json 'it declares a PreCompact hook' '"PreCompact"'
  assert_json 'and points that one at the note-before-compaction script' 'CLAUDE_PLUGIN_ROOT}/hooks/blueprint-precompact-note.sh'
  # Once, and with no matcher: a matcher on PreCompact selects the trigger, and
  # the note is owed before an auto compaction and a /compact alike.
  pc_wiring=$( python3 - "$HOOKS_JSON" <<'PYW' 2>&1
import json, sys
h = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]
hits = [(entry.get("matcher"), x.get("timeout")) for entry in h.get("PreCompact", []) for x in entry.get("hooks", [])
        if any(str(a).endswith("hooks/blueprint-precompact-note.sh") for a in x.get("args", []))]
print(hits)
PYW
)
  if [ "$pc_wiring" = '[(None, 5)]' ]; then
    pass 'blueprint-precompact-note.sh is registered once, under PreCompact, with no matcher and a 5s timeout'
  else
    fail 'blueprint-precompact-note.sh is registered once, under PreCompact, with no matcher and a 5s timeout' "got: $pc_wiring"
  fi
  # The capture hook: the ask is a Stop hook (the only one that gives the agent
  # a turn), the always send a SessionEnd hook; once each, no matcher, and a
  # timeout that covers the send's four requests (SessionEnd only).
  cap_wiring=$( python3 - "$HOOKS_JSON" <<'PYCW' 2>&1
import json, sys
h = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]
print([(ev, entry.get("matcher"), x.get("timeout")) for ev in sorted(h) for entry in h[ev] for x in entry.get("hooks", [])
       if any(str(a) == "${CLAUDE_PLUGIN_ROOT}/hooks/blueprint-capture.sh" for a in x.get("args", []))])
PYCW
)
  if [ "$cap_wiring" = "[('SessionEnd', None, 30), ('SessionStart', None, 5), ('Stop', None, 10)]" ]; then
    pass 'blueprint-capture.sh is registered once under Stop (10s), SessionEnd (30s) and SessionStart (5s), with no matcher'
  else
    fail 'blueprint-capture.sh is registered once under Stop (10s), SessionEnd (30s) and SessionStart (5s), with no matcher' "got: $cap_wiring"
  fi
  # The capture's Stop hook does block once (the ask), so its docs say what is
  # true: it never blocks work. A bare "never blocks" about it is false (F7).
  cap_words=$( python3 - "$HOOKS_JSON" "$PLUGIN/README.md" "$PLUGIN/hooks/README.md" <<'PYNB' 2>&1
import json, re, sys
desc = json.load(open(sys.argv[1], encoding="utf-8"))["description"]
texts = {"hooks.json": desc[desc.find("conversation capture"):]}
texts["README.md"] = "".join(l for l in open(sys.argv[2], encoding="utf-8") if l.startswith("| `blueprint-capture.sh`"))
hr = open(sys.argv[3], encoding="utf-8").read()
start = hr.find("## blueprint-capture.sh")
texts["hooks/README.md"] = hr[start:hr.find("\n## ", start + 1)] if start >= 0 else ""
bad = ["%s: no capture text" % k for k, t in texts.items() if len(t) < 40]
bad += ["%s: %r" % (k, m.group(0)) for k, t in texts.items() for m in re.finditer(r"(?i)never blocks(?! work)\W{0,2}\w*", t)]
print("; ".join(bad) or "ok")
PYNB
)
  if [ "$cap_words" = ok ]; then
    pass 'the capture'"'"'s docs say it never blocks work, not that it never blocks'
  else
    fail 'the capture'"'"'s docs say it never blocks work, not that it never blocks' "$cap_words"
  fi
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
