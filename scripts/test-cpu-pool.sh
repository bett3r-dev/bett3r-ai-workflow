#!/bin/sh
# Oracle for `bin/cpu-pool` — the machine-wide compiler token pool a fleet's
# lanes share (reference/cpu-pool.md).
#
# cargo is a GNU-make-jobserver client: given CARGO_MAKEFLAGS=--jobserver-auth=fifo:<p>
# it takes one token from the pipe per compiler process and returns it. The pool
# script owns the pipe's lifecycle; this suite drives the real script against a
# throwaway pipe under a temp dir and reads every verdict line (ADR-004), never an
# exit code, except where the exit code is the contract (`env` must fail when the
# pool is down, so `eval "$(cpu-pool env)"` evaluates nothing).
#
# The client in the "a token taken" case is a few lines of python doing exactly
# what cargo does on the pipe (read one byte, hold it, write it back), so the
# accounting is proved without a Rust toolchain. Cargo's own participation was
# measured by hand (six builds, peak 14 rustc with 9 tokens against 57 uncapped,
# 2026-10-11) and is recorded in the reference doc, not re-run here.
#
# Run locally:  sh scripts/test-cpu-pool.sh
# Exit code is non-zero if anything is broken.
#
# POOL_SH selects the interpreter that runs the `bin/cpu-pool` launcher.

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
POOL="$ROOT/plugins/bett3r-ai-workflow/bin/cpu-pool"
POOL_SH=${POOL_SH:-sh}

TMP=$( mktemp -d "${TMPDIR:-/tmp}/cpu-pool-test.XXXXXX" ) || exit 1
TMP=$( CDPATH= cd -P -- "$TMP" && pwd )
PIPE="$TMP/pool.fifo"
cleanup() {
  CPU_POOL_PATH="$PIPE" $POOL_SH "$POOL" down >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM
export CPU_POOL_PATH="$PIPE"

fail=0
pass() { printf 'ok   %s\n' "$1"; }
flunk() { printf 'FAIL %s\n     %s\n' "$1" "$2"; fail=1; }

# Every assertion reads the verdict line: the last line that starts with the marker.
verdict() { printf '%s\n' "$1" | grep '^CPU-POOL:v1 ' | tail -1; }
has() { printf '%s\n' "$1" | grep -q -- "$2"; }

# --- 1. env before up: no export line on stdout, non-zero, verdict on stderr ---
out=$( $POOL_SH "$POOL" env 2>"$TMP/env.err" ); rc=$?
if [ "$rc" -ne 0 ] && [ -z "$out" ] && grep -q 'action=env outcome=down' "$TMP/env.err"; then
  pass "env with no pool prints nothing to stdout and reports down"
else
  flunk "env with no pool" "rc=$rc stdout='$out' stderr='$(cat "$TMP/env.err")'"
fi

# --- 2. up with 3 tokens ---
out=$( $POOL_SH "$POOL" up --tokens 3 ); v=$( verdict "$out" )
if has "$v" 'action=up outcome=ok' && has "$v" 'tokens=3' && has "$v" 'reused=false' && [ -p "$PIPE" ]; then
  pass "up creates the pipe, starts a holder, fills 3 tokens"
else
  flunk "up" "$out"
fi
holder=$( printf '%s\n' "$v" | sed -n 's/.*holder=\([0-9]*\).*/\1/p' )

# --- 3. env prints the export line, eval-able ---
line=$( $POOL_SH "$POOL" env ); rc=$?
if [ "$rc" -eq 0 ] && [ "$line" = "export CARGO_MAKEFLAGS=--jobserver-auth=fifo:$PIPE" ]; then
  pass "env prints the CARGO_MAKEFLAGS export"
else
  flunk "env" "rc=$rc line='$line'"
fi

# --- 4. status: up, 3 free ---
v=$( verdict "$( $POOL_SH "$POOL" status )" )
if has "$v" 'action=status outcome=up' && has "$v" 'free=3' && has "$v" 'rustc=' ; then
  pass "status reports up with 3 free tokens"
else
  flunk "status after up" "$v"
fi

# --- 5. a client holds one token: free drops to 2, then back to 3 ---
python3 - "$PIPE" "$POOL" "$POOL_SH" <<'PY' >"$TMP/client.out" 2>&1
import os, subprocess, sys
pipe, pool, sh = sys.argv[1:4]
fd = os.open(pipe, os.O_RDWR | os.O_NONBLOCK)
tok = os.read(fd, 1)                       # what cargo does per extra compiler
assert tok == b"+", tok
print(subprocess.run([sh, pool, "status"], stdout=subprocess.PIPE).stdout.decode().strip())
os.write(fd, tok)                          # and what it does when that compiler exits
os.close(fd)
PY
if grep -q 'outcome=up.*free=2' "$TMP/client.out"; then
  pass "a client holding one token shows free=2"
else
  flunk "client accounting" "$(cat "$TMP/client.out")"
fi
v=$( verdict "$( $POOL_SH "$POOL" status )" )
has "$v" 'free=3' && pass "the token returns: free=3" || flunk "token returned" "$v"

# --- 6. a lost token: a client dies holding one; refill restores N when no cargo runs ---
python3 - "$PIPE" <<'PY'
import os, sys
fd = os.open(sys.argv[1], os.O_RDWR | os.O_NONBLOCK)
os.read(fd, 1)   # taken and never returned: the kill -9 case
PY
v=$( verdict "$( $POOL_SH "$POOL" status )" )
has "$v" 'free=2' && pass "a dead client leaves free=2" || flunk "lost token visible" "$v"
v=$( verdict "$( $POOL_SH "$POOL" refill )" )
if has "$v" 'action=refill outcome=ok' && has "$v" 'lost=1'; then
  pass "refill reports lost=1 and restores the pool"
else
  flunk "refill" "$v"
fi
v=$( verdict "$( $POOL_SH "$POOL" status )" )
has "$v" 'free=3' && pass "after refill free=3" || flunk "refill count" "$v"

# --- 7. up again reuses the live holder and keeps a new token count ---
v=$( verdict "$( $POOL_SH "$POOL" up --tokens 5 )" )
if has "$v" 'reused=true' && has "$v" "holder=$holder" && has "$v" 'tokens=5'; then
  pass "a second up reuses the holder and resets the count"
else
  flunk "up reuse" "$v (first holder $holder)"
fi
v=$( verdict "$( $POOL_SH "$POOL" status )" )
has "$v" 'free=5' && pass "status free=5 after resize" || flunk "resize" "$v"

# --- 8. down: holder gone, pipe gone, status down, env fails ---
v=$( verdict "$( $POOL_SH "$POOL" down )" )
has "$v" 'action=down outcome=ok' || flunk "down verdict" "$v"
sleep 0.3
if ! kill -0 "$holder" 2>/dev/null && [ ! -e "$PIPE" ]; then
  pass "down stops the holder and removes the pipe"
else
  flunk "down" "holder alive=$(kill -0 "$holder" 2>/dev/null && echo yes || echo no) pipe=$( [ -e "$PIPE" ] && echo present || echo gone )"
fi
v=$( verdict "$( $POOL_SH "$POOL" status )" )
has "$v" 'outcome=down' && pass "status reports down" || flunk "status after down" "$v"
if ! $POOL_SH "$POOL" env >/dev/null 2>&1; then pass "env fails after down"; else flunk "env after down" "exit 0"; fi

[ "$fail" -eq 0 ] && echo "cpu-pool: all cases pass" || echo "cpu-pool: FAILURES"
exit $fail
