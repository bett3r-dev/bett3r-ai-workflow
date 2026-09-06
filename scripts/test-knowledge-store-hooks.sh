#!/bin/sh
# Oracle for the shipped knowledge-store hooks
# (plugins/bett3r-knowledge-store/hooks/ks-capture-teardown.sh and ks-capture-pr.sh).
#
# ## Why this file had to exist before the hooks could ship
#
# `scripts/test-hooks.sh` is hardcoded to `plugins/bett3r-ai-workflow` and to
# two named scripts inside it. It is the oracle for `esas-pending.sh` and
# `esas-session-channel.sh` and **for nothing else**. Before this file, a whole
# new plugin with two new hooks could have shipped with every gate in this repo
# green, and every one of them green *correctly* — none of them collects an
# artifact that did not exist when they were written. A gate list is a list of
# runners, not a map of what they observe.
#
# ## The two failure modes that outrank everything the hooks do when they work
#
#   1. **A non-zero exit from the PreToolUse hook cancels the user's Bash
#      call.** Claude Code reads exit 2 as "block this tool call". The command
#      it would most often cancel is the `git worktree remove` the hook exists
#      to protect — so every path here asserts exit 0, including the hostile
#      and malformed inputs.
#   2. **These hooks run before and after EVERY Bash call in EVERY repo where
#      the plugin is enabled.** There is no per-directory matcher. So the
#      unconfigured fast path is asserted silent on both streams, and timed.
#
# ## How the store is stubbed
#
# `.knowledge-store/capture` is the seam: a repo-local executable the store
# installs. Every case here installs a **stub** that records its argv, so the
# assertions are about what the hook *decided* and what key it computed — not
# about any real store, which is not this repo's code and cannot be a
# dependency of this repo's CI.
#
# Run locally:  sh scripts/test-knowledge-store-hooks.sh
# Exit code is non-zero if anything is broken, so CI fails the PR.
#
# HOOK_SH selects the interpreter the *hooks* run under (the suite itself is
# POSIX sh either way). Claude Code spawns them as `sh <script>`, and `sh` is
# dash on Debian/Ubuntu and bash-in-POSIX-mode on macOS, so:
#     for s in sh dash bash; do HOOK_SH=$s sh scripts/test-knowledge-store-hooks.sh; done

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
PLUGIN="$ROOT/plugins/bett3r-knowledge-store"
TEARDOWN_HOOK="$PLUGIN/hooks/ks-capture-teardown.sh"
PR_HOOK="$PLUGIN/hooks/ks-capture-pr.sh"
HOOKS_JSON="$PLUGIN/hooks/hooks.json"
HOOK_SH=${HOOK_SH:-sh}

TMP=$( mktemp -d "${TMPDIR:-/tmp}/ks-hook-test.XXXXXX" ) || exit 1
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

# The suite builds its event payloads with python3 rather than by hand, because
# a `command` field is a shell line full of quotes and backslashes and a
# hand-rolled JSON writer would be testing its own escaping. A missing python3
# is a hard failure and never a skip: a suite that quietly runs no cases is the
# reassuring-failing shape this whole gate exists to refuse.
if ! command -v python3 >/dev/null 2>&1; then
  printf '\n\033[31m✗ python3 is required to build the event payloads — refusing to report a pass over zero cases.\033[0m\n\n'
  exit 1
fi

# ── The world each case runs in ──────────────────────────────────────────────
#
# A fresh work dir per case. `setup_repo <mode>`:
#   bare      no .knowledge-store at all — the unconfigured repo, i.e. almost
#             every repo the plugin is enabled in
#   inert     a .knowledge-store/ directory but a capture that is NOT executable
#   ok        a stub capture that records argv and succeeds
#   down      a stub capture that records argv and exits 1 (store unreachable)
#   slow      a stub capture that sleeps, then records argv
# **Every case gets its own directory.** Not tidiness: the PR hook detaches its
# capture, so that child can still be running when the next case starts. With a
# single reused work dir it wrote its record into the *next* case's freshly
# recreated `.knowledge-store/`, and the suite read one case's capture as
# another's. Both directions of that are poison — it manufactures a pass for a
# case that captured nothing and a failure for a case that behaved perfectly.
# A unique directory per case makes a straggler harmless by construction.
case_n=0
WORK="$TMP/work-0"

setup_repo(){
  case_n=$(( case_n + 1 ))
  WORK="$TMP/work-$case_n"
  rm -rf "$WORK"
  mkdir -p "$WORK"
  [ "$1" = bare ] && return 0
  mkdir -p "$WORK/.knowledge-store"
  cat > "$WORK/.knowledge-store/capture" <<'STUB'
#!/bin/sh
# argv, one invocation per line, unambiguously delimited.
printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$( dirname -- "$0" )/argv.log"
STUB
  case $1 in
    inert )
      chmod 644 "$WORK/.knowledge-store/capture" ;;
    down )
      printf 'printf "store unreachable: connection refused\\n" >&2\nexit 1\n' \
        >>"$WORK/.knowledge-store/capture"
      chmod +x "$WORK/.knowledge-store/capture" ;;
    slow )
      # Sleep AFTER recording, so the marker appears promptly while the process
      # is still alive — the detached case asserts the hook returned before the
      # child did, which needs the child to still be running.
      printf 'sleep 3\n' >>"$WORK/.knowledge-store/capture"
      chmod +x "$WORK/.knowledge-store/capture" ;;
    * )
      chmod +x "$WORK/.knowledge-store/capture" ;;
  esac
  return 0
}

argv_log(){ cat "$WORK/.knowledge-store/argv.log" 2>/dev/null; }

# pre_payload <command> — a PreToolUse(Bash) event.
pre_payload(){
  python3 -c '
import json, sys
print(json.dumps({
    "session_id": "s1",
    "transcript_path": "/tmp/t.jsonl",
    "cwd": sys.argv[2],
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "tool_input": {"command": sys.argv[1], "description": sys.argv[3], "timeout": 120000},
}))' "$1" "$WORK" "${2:-run a command}"
}

# post_payload <command> <stdout> — a PostToolUse(Bash) event.
post_payload(){
  python3 -c '
import json, sys
print(json.dumps({
    "session_id": "s1",
    "transcript_path": "/tmp/t.jsonl",
    "cwd": sys.argv[3],
    "hook_event_name": "PostToolUse",
    "tool_name": "Bash",
    "tool_input": {"command": sys.argv[1], "description": "open the PR", "timeout": 120000},
    "tool_response": {"stdout": sys.argv[2], "stderr": "", "interrupted": False, "isImage": False},
}))' "$1" "$2" "$WORK"
}

# run_hook <hook-path> <payload>
run_hook(){
  printf '%s' "$2" | CLAUDE_PROJECT_DIR="$WORK" "$HOOK_SH" "$1" >"$TMP/out" 2>"$TMP/err"
  status=$?
}

# Every hook run, in every case, must satisfy these three. Returns 1 when it
# has already reported a failure, so callers can stop.
assert_safe(){
  if [ "$status" -ne 0 ]; then
    fail "$1" "exit status $status — a non-zero PreToolUse exit CANCELS the user's command" \
      "stderr: $( cat "$TMP/err" )"
    return 1
  fi
  if [ -s "$TMP/out" ]; then
    fail "$1" "wrote to stdout — a hook's stdout is injected into the session" \
      "stdout: $( cat "$TMP/out" )"
    return 1
  fi
  return 0
}

# assert_capture <hook> <payload> <expected-argv-log> <description>
# The expected log is the full recorded argv, so "no capture" is spelled '' and
# is asserted as strictly as a capture is.
assert_capture(){
  run_hook "$1" "$2"
  assert_safe "$4" || return
  actual=$( argv_log )
  if [ "$actual" != "$3" ]; then
    fail "$4" "expected argv log: [$3]" "actual argv log:   [$actual]" \
      "stderr: $( cat "$TMP/err" )"
    return
  fi
  pass "$4"
}

# assert_capture_async <hook> <payload> <expected-argv-log> <description>
# The PR hook's capture is detached, so "did it capture?" cannot be read
# immediately after the hook returns — that is a question about a process that
# is deliberately still running. Polling for the expected record is the honest
# way to assert an asynchronous contract; asserting it synchronously would have
# been asserting that the hook is NOT detached, which the timing case above
# proves it is.
#
# The empty expectation is polled too, for a fixed interval rather than until a
# match: "nothing was dispatched" is only evidence if enough time passed for a
# dispatch to have shown up.
assert_capture_async(){
  run_hook "$1" "$2"
  assert_safe "$4" || return
  if [ -z "$3" ]; then
    sleep 1
    actual=$( argv_log )
  else
    i=0
    actual=$( argv_log )
    while [ "$actual" != "$3" ] && [ "$i" -lt 40 ]; do
      i=$(( i + 1 ))
      sleep 0.1 2>/dev/null || sleep 1
      actual=$( argv_log )
    done
  fi
  if [ "$actual" != "$3" ]; then
    fail "$4" "expected argv log: [$3]" "actual argv log:   [$actual]" \
      "stderr: $( cat "$TMP/err" )"
    return
  fi
  pass "$4"
}

# ── 1. Inert in an unconfigured repo ─────────────────────────────────────────
#
# The state every fleet worktree and every unrelated repo is in, on every Bash
# call. Silence on BOTH streams is the contract, not a nicety: a shell
# diagnostic here would print in front of the user's work forever.

printf '\ninert in a repo that never heard of the knowledge store\n'

if [ ! -f "$TEARDOWN_HOOK" ]; then
  fail 'the teardown hook ships' "no file at $TEARDOWN_HOOK"
else
  pass 'the teardown hook ships'
fi
if [ ! -f "$PR_HOOK" ]; then
  fail 'the pr hook ships' "no file at $PR_HOOK"
else
  pass 'the pr hook ships'
fi

# A *real* teardown command, so this is the fast path refusing an event it
# would otherwise act on — not the fast path being asked nothing.
setup_repo bare
run_hook "$TEARDOWN_HOOK" "$( pre_payload 'git worktree remove /tmp/wt-lane-a' )"
if [ "$status" -ne 0 ]; then
  fail 'bare repo, real teardown command: exits 0' "exit status $status"
elif [ -s "$TMP/out" ] || [ -s "$TMP/err" ]; then
  fail 'bare repo, real teardown command: silent on both streams' \
    "stdout: [$( cat "$TMP/out" )]" "stderr: [$( cat "$TMP/err" )]"
else
  pass 'bare repo, real teardown command: exit 0, no output at all'
fi

setup_repo bare
run_hook "$PR_HOOK" "$( post_payload 'gh pr create --base master' 'https://github.com/o/r/pull/7' )"
if [ "$status" -ne 0 ]; then
  fail 'bare repo, real gh pr create: exits 0' "exit status $status"
elif [ -s "$TMP/out" ] || [ -s "$TMP/err" ]; then
  fail 'bare repo, real gh pr create: silent on both streams' \
    "stdout: [$( cat "$TMP/out" )]" "stderr: [$( cat "$TMP/err" )]"
else
  pass 'bare repo, real gh pr create: exit 0, no output at all'
fi

# A `.knowledge-store/` that exists but whose capture is not executable. The
# sentinel is `-x`, not `-f`: a half-installed store must read as not installed,
# because the alternative is a hook that tries to exec a non-executable file
# before every teardown.
setup_repo inert
assert_capture "$TEARDOWN_HOOK" "$( pre_payload 'git worktree remove /tmp/wt-lane-a' )" '' \
  'a non-executable capture reads as not configured (-x, not -f)'

# ── 2. The teardown matcher ──────────────────────────────────────────────────
#
# The risk named at design time: "a PreToolUse matcher that misses a teardown
# variant loses artifacts silently." So the variants `/start-multi` can actually
# emit are enumerated as cases rather than trusted to a regex.

printf '\nteardown matcher — the invocations /start-multi emits\n'

for variant in \
  'git worktree remove /tmp/wt-lane-a' \
  'git worktree remove --force /tmp/wt-lane-a' \
  'git -C /repo worktree remove /tmp/wt-lane-a' \
  'cd /repo && git worktree remove /tmp/wt-lane-a' \
  'git worktree remove   /tmp/wt-lane-a' \
  '/usr/bin/git worktree remove /tmp/wt-lane-a'
do
  setup_repo ok
  assert_capture "$TEARDOWN_HOOK" "$( pre_payload "$variant" )" \
    "worktree-remove|/tmp/wt-lane-a|$WORK" \
    "matches: $variant"
done

# Quoted path, because a worktree under a path with a space is a path the
# tokeniser has to keep as one token rather than file under `/tmp/wt`.
setup_repo ok
assert_capture "$TEARDOWN_HOOK" "$( pre_payload 'git worktree remove "/tmp/wt lane a"' )" \
  "worktree-remove|/tmp/wt lane a|$WORK" \
  'matches a quoted path and keeps it as one token'

printf '\nteardown matcher — what it must NOT fire on\n'

for variant in \
  'git worktree list' \
  'git worktree prune' \
  'git worktree add /tmp/wt-lane-b feature' \
  'git worktree list && echo remove' \
  'echo "git worktree remove is what step 7 does"' \
  'git commit -m "remove the worktree"'
do
  setup_repo ok
  assert_capture "$TEARDOWN_HOOK" "$( pre_payload "$variant" )" '' \
    "does not fire: $variant"
done

# `tool_input.description` is agent-written prose. A substring search over the
# raw payload would see it; matching on `tool_input.command` by path does not.
# This is the case that fails if anyone ever "simplifies" the scanner to a grep.
setup_repo ok
assert_capture "$TEARDOWN_HOOK" \
  "$( pre_payload 'ls -la /tmp' 'run git worktree remove on the stale lane' )" '' \
  'a description that says "git worktree remove" is not a teardown'

# ── 3. The natural key is stable, so a double capture is free ────────────────

printf '\nidempotence — the natural key is a pure function of the invocation\n'

setup_repo ok
run_hook "$TEARDOWN_HOOK" "$( pre_payload 'git worktree remove /tmp/wt-lane-a' )"
first=$( argv_log )
run_hook "$TEARDOWN_HOOK" "$( pre_payload 'git worktree remove /tmp/wt-lane-a' )"
both=$( argv_log )
expected="worktree-remove|/tmp/wt-lane-a|$WORK
worktree-remove|/tmp/wt-lane-a|$WORK"
if [ "$both" != "$expected" ]; then
  fail 'the same teardown twice produces byte-identical argv' \
    "expected two identical lines" "actual: [$both]"
elif [ -z "$first" ]; then
  fail 'the same teardown twice produces byte-identical argv' 'the first run captured nothing'
else
  # Named as what it buys: the store dedups on argument 2, so re-running a
  # teardown is a no-op in the store. Nothing time-, run- or session-derived may
  # enter the key or this stops being true.
  pass 'the same teardown twice produces byte-identical argv (so double capture is a store no-op)'
fi

# ── 4. A store that is down never blocks a teardown ──────────────────────────

printf '\nstore unreachable\n'

setup_repo down
run_hook "$TEARDOWN_HOOK" "$( pre_payload 'git worktree remove /tmp/wt-lane-a' )"
if [ "$status" -ne 0 ]; then
  fail 'a failing capture still exits 0 — the teardown is never blocked' \
    "exit status $status — this would CANCEL the user's git worktree remove"
elif [ -s "$TMP/out" ]; then
  fail 'a failing capture says nothing on stdout' "stdout: $( cat "$TMP/out" )"
elif [ ! -s "$TMP/err" ]; then
  fail 'a failing capture is LOUD on stderr' \
    'nothing on stderr — artifacts are about to be destroyed uncaptured and nobody is told'
else
  pass 'store unreachable: exit 0 (teardown not blocked), loud on stderr, silent on stdout'
fi

# The failure message has to name the thing that is being lost, or it is a
# stack trace nobody can act on at the moment they see it.
case $( cat "$TMP/err" ) in
  *'/tmp/wt-lane-a'* ) pass 'and the failure names the worktree whose artifacts are being lost' ;;
  * ) fail 'and the failure names the worktree whose artifacts are being lost' \
        "stderr: $( cat "$TMP/err" )" ;;
esac

# ── 5. The PR hook ───────────────────────────────────────────────────────────

printf '\ngh pr create — matcher and natural key\n'

setup_repo ok
assert_capture_async "$PR_HOOK" \
  "$( post_payload 'gh pr create --base master --title x' 'https://github.com/bett3r-dev/r/pull/42' )" \
  "pr-create|https://github.com/bett3r-dev/r/pull/42|$WORK" \
  'gh pr create: the PR URL from stdout is the natural key'

setup_repo ok
assert_capture_async "$PR_HOOK" \
  "$( post_payload 'cd /repo && gh pr create --fill' 'Creating pull request...
https://github.com/bett3r-dev/r/pull/42
' )" \
  "pr-create|https://github.com/bett3r-dev/r/pull/42|$WORK" \
  'the URL is found among gh chatter on other lines'

for variant in 'gh pr view 42' 'gh pr merge 42 --delete-branch' 'gh pr edit 42 --base main' 'gh issue create'
do
  setup_repo ok
  assert_capture_async "$PR_HOOK" "$( post_payload "$variant" 'https://github.com/o/r/pull/42' )" '' \
    "does not fire: $variant"
done

# `gh pr create` that produced no PR — it failed, or it was a dry run. There is
# nothing to capture, and a capture under a guessed key would be worse than
# none: it would be a record the store can never reconcile.
setup_repo ok
assert_capture_async "$PR_HOOK" "$( post_payload 'gh pr create --base master' 'pull request create failed' )" '' \
  'gh pr create that printed no PR URL captures nothing'

# ── 6. The PR capture is detached; the teardown capture is not ───────────────
#
# This is the design decision "blocking at teardown, non-blocking at PR create",
# asserted as a timing difference. Both halves are needed: the second one alone
# would pass against a hook that never captured at all.

printf '\nblocking at teardown, non-blocking at PR create\n'

setup_repo slow
start=$( date +%s )
run_hook "$PR_HOOK" "$( post_payload 'gh pr create --fill' 'https://github.com/o/r/pull/9' )"
end=$( date +%s )
elapsed=$(( end - start ))
if [ "$status" -ne 0 ]; then
  fail 'pr capture is detached: the hook returns immediately' "exit status $status"
elif [ "$elapsed" -ge 3 ]; then
  fail 'pr capture is detached: the hook returns immediately' \
    "took ${elapsed}s against a capture that sleeps 3s — it waited"
else
  pass "pr capture is detached: returned in ${elapsed}s against a 3s capture"
fi
# ...and it really did dispatch it. A hook that matched nothing would also be fast.
i=0
while [ ! -s "$WORK/.knowledge-store/argv.log" ] && [ "$i" -lt 40 ]; do
  i=$(( i + 1 ))
  sleep 0.1 2>/dev/null || sleep 1
done
if [ "$( argv_log )" = "pr-create|https://github.com/o/r/pull/9|$WORK" ]; then
  pass 'and the detached capture really ran, with the right key'
else
  fail 'and the detached capture really ran, with the right key' "argv log: [$( argv_log )]"
fi

setup_repo slow
start=$( date +%s )
run_hook "$TEARDOWN_HOOK" "$( pre_payload 'git worktree remove /tmp/wt-lane-a' )"
end=$( date +%s )
elapsed=$(( end - start ))
if [ "$status" -ne 0 ]; then
  fail 'teardown capture BLOCKS: the hook waits for it' "exit status $status"
elif [ "$elapsed" -lt 3 ]; then
  fail 'teardown capture BLOCKS: the hook waits for it' \
    "returned in ${elapsed}s against a capture that sleeps 3s — it did not wait, so the" \
    'capture is racing the removal it exists to precede'
else
  pass "teardown capture blocks: waited ${elapsed}s for a 3s capture"
fi

# ── 7. Nothing cancels the user's command, whatever arrives ──────────────────

printf '\nhardening — no payload may ever produce a non-zero exit\n'

hostile(){
  setup_repo ok
  printf '%s' "$2" | CLAUDE_PROJECT_DIR="$WORK" "$HOOK_SH" "$3" >"$TMP/out" 2>"$TMP/err"
  st=$?
  if [ "$st" -ne 0 ]; then
    fail "$1" "exit status $st — this CANCELS the user's command" "stderr: $( cat "$TMP/err" )"
  elif [ -s "$TMP/err" ]; then
    fail "$1" 'wrote to stderr on a payload it should have ignored' "stderr: $( cat "$TMP/err" )"
  else
    pass "$1"
  fi
}

hostile 'empty stdin (teardown)' '' "$TEARDOWN_HOOK"
hostile 'empty stdin (pr)' '' "$PR_HOOK"
hostile 'stdin that is not JSON (teardown)' 'not json at all' "$TEARDOWN_HOOK"
hostile 'stdin that is not JSON (pr)' 'not json at all' "$PR_HOOK"
hostile 'a truncated payload mid-command (teardown)' \
  '{"tool_name":"Bash","tool_input":{"command":"git worktree remo' "$TEARDOWN_HOOK"
hostile 'a payload with no tool_input at all (teardown)' \
  '{"tool_name":"Bash","hook_event_name":"PreToolUse"}' "$TEARDOWN_HOOK"
hostile 'unbalanced braces (pr)' '}}}{{{"command":"gh pr create"' "$PR_HOOK"
hostile 'binary garbage (teardown)' \
  "$( printf '\001\002\377 {"tool_input":{"command":"x"}}' )" "$TEARDOWN_HOOK"
hostile 'a command field that is a very long line (teardown)' \
  "$( python3 -c 'import json;print(json.dumps({"tool_name":"Bash","cwd":"/x","tool_input":{"command":"echo "+"a"*20000}}))' )" \
  "$TEARDOWN_HOOK"

# A stripped PATH: no awk, no sed, no tr, no head. The hooks cannot decide
# anything without them; what they must not do is say so, or fail, in front of
# the user's command.
setup_repo ok
hook_sh_abs=$( command -v "$HOOK_SH" )
for h in "$TEARDOWN_HOOK" "$PR_HOOK"; do
  out=$( printf '%s' "$( pre_payload 'git worktree remove /tmp/wt-lane-a' )" \
         | env -i PATH=/nonexistent CLAUDE_PROJECT_DIR="$WORK" "$hook_sh_abs" "$h" 2>"$TMP/err" )
  st=$?
  name=$( basename "$h" )
  if [ "$st" -ne 0 ]; then
    fail "a stripped PATH still exits 0 ($name)" "exit status $st" "stderr: $( cat "$TMP/err" )"
  elif [ -n "$out" ] || [ -s "$TMP/err" ]; then
    fail "a stripped PATH degrades to silence ($name)" \
      "stdout: [$out]" "stderr: [$( cat "$TMP/err" )]"
  else
    pass "a stripped PATH degrades to silence, exit 0 ($name)"
  fi
done

# ── 8. The fast path is free ─────────────────────────────────────────────────
#
# This runs before and after every Bash call in every repo where the plugin is
# enabled, so the unconfigured path has to be indistinguishable from zero.

printf '\ncost — the unconfigured path runs on every Bash call in every repo\n'

setup_repo bare
payload=$( pre_payload 'git worktree remove /tmp/wt-lane-a' )
start=$( date +%s )
i=0
while [ "$i" -lt 50 ]; do
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$WORK" "$HOOK_SH" "$TEARDOWN_HOOK" >/dev/null 2>&1
  i=$(( i + 1 ))
done
end=$( date +%s )
elapsed=$(( end - start ))
if [ "$elapsed" -gt 2 ]; then
  fail 'the unconfigured path costs nothing (50 runs)' "took ${elapsed}s for 50 runs"
else
  pass "the unconfigured path costs nothing: 50 runs in ${elapsed}s"
fi

# ── 9. The wiring Claude Code actually reads ─────────────────────────────────
#
# The scripts working is worth nothing if the runtime never runs them, and that
# failure is silent — a hook that is not declared does not error, it simply
# never fires. `<plugin>/hooks/hooks.json` is the path Claude Code stats.

printf '\nwiring\n'

assert_json(){
  if grep -q "$2" "$HOOKS_JSON" 2>/dev/null; then pass "$1"; else fail "$1" "not found in $HOOKS_JSON: $2"; fi
}

if [ ! -f "$HOOKS_JSON" ]; then
  fail 'hooks/hooks.json exists (the path Claude Code auto-loads)' "no file at $HOOKS_JSON"
else
  pass 'hooks/hooks.json exists (the path Claude Code auto-loads)'
  assert_json 'it declares a PreToolUse hook' '"PreToolUse"'
  assert_json 'it declares a PostToolUse hook' '"PostToolUse"'
  # The matcher field selects on the TOOL NAME and nothing else. A design table
  # rendering the matcher as "the runtime command matches git worktree remove"
  # describes a mechanism the platform does not have; a regex here would match
  # no tool and fire never.
  assert_json 'both matchers select the Bash tool by name' '"matcher": *"Bash"'
  assert_json 'it points at the shipped teardown script via ${CLAUDE_PLUGIN_ROOT}' \
    'CLAUDE_PLUGIN_ROOT}/hooks/ks-capture-teardown.sh'
  assert_json 'it points at the shipped pr script via ${CLAUDE_PLUGIN_ROOT}' \
    'CLAUDE_PLUGIN_ROOT}/hooks/ks-capture-pr.sh'
  assert_json 'it sets an explicit timeout on each hook' '"timeout":'
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$HOOKS_JSON" 2>/dev/null; then
    pass 'hooks.json is valid JSON'
  else
    fail 'hooks.json is valid JSON' "json.load failed on $HOOKS_JSON"
  fi
  # The two matchers must be the only two entries: a third event added without a
  # case in this file is a hook nothing observes, which is the hole this suite
  # was written to close.
  n_events=$( python3 -c '
import json, sys
print(len(json.load(open(sys.argv[1]))["hooks"]))' "$HOOKS_JSON" 2>/dev/null )
  if [ "$n_events" = '2' ]; then
    pass 'exactly two hook events are declared — every one of them has cases above'
  else
    fail 'exactly two hook events are declared — every one of them has cases above' \
      "hooks.json declares $n_events event(s); add cases here before adding an event"
  fi
fi

# Line 2, asserted as text. It is the whole program most of the time, and it is
# the single line whose deletion turns a plugin nobody notices into one that
# shells out before every Bash call in every repo on the machine.
printf '\nthe sentinel\n'
for h in "$TEARDOWN_HOOK" "$PR_HOOK"; do
  name=$( basename "$h" )
  line2=$( sed -n '2p' "$h" 2>/dev/null )
  case $line2 in
    '[ -x "${CLAUDE_PROJECT_DIR:-.}/.knowledge-store/capture" ] || exit 0' )
      pass "$name line 2 is the single existence test, before anything else" ;;
    * )
      fail "$name line 2 is the single existence test, before anything else" \
        "line 2 is: [$line2]" ;;
  esac
done

printf '\n'
if [ "$failed" -gt 0 ]; then
  printf '\033[31m✗ %d failed\033[0m, %d passed\n\n' "$failed" "$passed"
  exit 1
fi
printf '\033[32m✓ %d passed\033[0m\n\n' "$passed"
