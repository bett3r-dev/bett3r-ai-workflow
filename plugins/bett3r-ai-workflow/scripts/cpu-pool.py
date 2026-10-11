#!/usr/bin/env python3
"""One machine-wide pool of compiler tokens that every lane's cargo shares.

A fleet's lanes are mostly idle from the machine's point of view (the model's
thinking uses no local CPU), then every lane compiles at once and ten cores serve
six full-parallel cargo builds: W0 of pv4's `multi-rus-loop` ran 160 min per lane
against 47 at two lanes. Queueing whole commands behind K slots fixes that but
creates its own problems (a lock primitive macOS lacks, a wait that counts against
the Bash tool's timeout, starvation, stale locks). This is the smaller thing:

cargo is a client of the GNU make jobserver protocol. One named pipe holds N
tokens; every cargo given `CARGO_MAKEFLAGS=--jobserver-auth=fifo:<path>` takes a
token per compiler process and gives it back, across every worktree on the
machine. A lone lane gets all N; six lanes share them; nothing waits before
starting, so no timeout changes hands. Measured 2026-10-11 on cargo 1.99 / macOS
14, six concurrent builds: peak 14 rustc with 9 tokens against 57 uncapped.

`CARGO_MAKEFLAGS` rather than `MAKEFLAGS`: cargo reads either, GNU make 3.81
(macOS) reads only the second, and a gate that runs `make` should see nothing.
A missing pipe is loud, not silent: cargo prints
`warning: failed to connect to jobserver` and builds uncapped.

The pool reaches a lane through the environment: a Bash call inside Claude Code
inherits the process's environment, so the shell that launches `claude` (or
`fleet-loop`) exports the variable once and every lane, every executor, every
gate joins. Verified 2026-10-11 with `claude -p` on 2.1.296.

Usage (each subcommand ends in one `CPU-POOL:v1` verdict line, ADR-004):

    cpu-pool up [--tokens N] [--path P]   create the pipe, start the holder, fill N tokens
    cpu-pool env [--path P]               print `export CARGO_MAKEFLAGS=...` for eval
    cpu-pool status [--path P]            holder alive, free tokens, rustc/cargo running
    cpu-pool refill [--path P]            restore N tokens when no cargo runs (a client
                                          killed mid-build takes its tokens with it)
    cpu-pool down [--path P]              stop the holder, remove the pipe

Defaults: N = cores − 1 (make's own convention for `-j cores`); the pipe at
`$CPU_POOL_PATH`, else `~/.cache/bett3r-cpu-pool/default.fifo`. Concurrent
compilers across the machine stay ≤ lanes + N (each cargo holds one implicit
token). The state file beside the pipe (`<path>.json`) records tokens and the
holder's pid.

What it does not cover: running the test binaries, `go test`, `node` — none are
jobserver clients, and none is where the fleet's CPU went.
"""

import argparse
import errno
import json
import os
import signal
import subprocess
import sys
import time

MARKER = "CPU-POOL:v1"


def default_path():
    env = os.environ.get("CPU_POOL_PATH")
    if env:
        return env
    return os.path.join(os.path.expanduser("~"), ".cache", "bett3r-cpu-pool", "default.fifo")


def state_path(path):
    return path + ".json"


def read_state(path):
    try:
        with open(state_path(path)) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def write_state(path, state):
    tmp = state_path(path) + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(state, fh)
    os.replace(tmp, state_path(path))


def alive(pid):
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except OSError as exc:
        return exc.errno == errno.EPERM
    return True


def verdict(action, outcome, **kv):
    parts = [MARKER, "action=" + action, "outcome=" + outcome]
    parts += ["%s=%s" % (k, v) for k, v in kv.items() if v is not None]
    print(" ".join(parts))


def open_rw_nonblock(path):
    return os.open(path, os.O_RDWR | os.O_NONBLOCK)


def drain(fd):
    """Read every token currently in the pipe without blocking; return the count."""
    count = 0
    while True:
        try:
            chunk = os.read(fd, 4096)
        except BlockingIOError:
            return count
        except OSError as exc:
            if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                return count
            raise
        if not chunk:
            return count
        count += len(chunk)


def fill(fd, n):
    if n > 0:
        os.write(fd, b"+" * n)


def count_procs(names):
    """How many processes whose command name is in `names` are running."""
    try:
        out = subprocess.run(["ps", "-eo", "comm="], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False).stdout
    except OSError:
        return {n: -1 for n in names}
    counts = {n: 0 for n in names}
    for line in out.decode("utf-8", "replace").splitlines():
        base = os.path.basename(line.strip())
        if base in counts:
            counts[base] += 1
    return counts


def cmd_hold(path):
    """The holder: keeps one read-write end open so the pipe never sees EOF and
    tokens survive between clients. Runs until killed."""
    fd = os.open(path, os.O_RDWR)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    while True:
        signal.pause() if hasattr(signal, "pause") else time.sleep(3600)
    os.close(fd)  # not reached


def cmd_up(path, tokens):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    state = read_state(path) or {}
    if not os.path.exists(path):
        os.mkfifo(path, 0o600)
    reused = alive(state.get("holder"))
    if not reused:
        holder = subprocess.Popen(
            [sys.executable, os.path.abspath(__file__), "hold", "--path", path],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True, close_fds=True,
        )
        state = {"path": path, "tokens": tokens, "holder": holder.pid, "startedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
        time.sleep(0.2)  # let the holder open its end (O_RDWR on a FIFO never blocks)
        if not alive(holder.pid):
            verdict("up", "error", reason="holder-died", path=path)
            return 1
    fd = open_rw_nonblock(path)
    try:
        drain(fd)
        fill(fd, tokens)
    finally:
        os.close(fd)
    state["tokens"] = tokens
    state["path"] = path
    write_state(path, state)
    verdict("up", "ok", path=path, tokens=tokens, holder=state["holder"], reused=str(reused).lower())
    return 0


def env_line(path):
    return "export CARGO_MAKEFLAGS=--jobserver-auth=fifo:%s" % path


def cmd_env(path):
    state = read_state(path)
    if not state or not alive(state.get("holder")) or not os.path.exists(path):
        # stderr so `eval "$(cpu-pool env)"` evaluates nothing rather than this line
        print("%s action=env outcome=down path=%s" % (MARKER, path), file=sys.stderr)
        return 1
    print(env_line(path))
    return 0


def pool_status(path):
    state = read_state(path) or {}
    up = bool(state) and alive(state.get("holder")) and os.path.exists(path)
    free = None
    if up:
        fd = open_rw_nonblock(path)
        try:
            free = drain(fd)
            fill(fd, free)
        finally:
            os.close(fd)
    return state, up, free


def cmd_status(path):
    state, up, free = pool_status(path)
    procs = count_procs(["rustc", "cargo"])
    verdict("status", "up" if up else "down", path=path, tokens=state.get("tokens"), free=free,
            holder=state.get("holder"), rustc=procs["rustc"], cargo=procs["cargo"])
    return 0 if up else 1


def cmd_refill(path):
    state, up, free = pool_status(path)
    if not up:
        verdict("refill", "down", path=path)
        return 1
    procs = count_procs(["cargo"])
    if procs["cargo"] > 0:
        # A running cargo may hold tokens; topping up now would overcommit the cores.
        verdict("refill", "busy", path=path, tokens=state["tokens"], free=free, cargo=procs["cargo"])
        return 1
    fd = open_rw_nonblock(path)
    try:
        had = drain(fd)
        fill(fd, state["tokens"])
    finally:
        os.close(fd)
    verdict("refill", "ok", path=path, tokens=state["tokens"], lost=max(0, state["tokens"] - had))
    return 0


def cmd_down(path):
    state = read_state(path) or {}
    pid = state.get("holder")
    if alive(pid):
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    for p in (path, state_path(path)):
        try:
            os.unlink(p)
        except OSError:
            pass
    verdict("down", "ok", path=path, holder=pid)
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog="cpu-pool", description=__doc__.split("\n\n")[0])
    ap.add_argument("action", choices=["up", "env", "status", "refill", "down", "hold"])
    ap.add_argument("--path", default=None, help="the pipe (default $CPU_POOL_PATH or ~/.cache/bett3r-cpu-pool/default.fifo)")
    ap.add_argument("--tokens", type=int, default=None, help="tokens in the pool (default cores - 1)")
    args = ap.parse_args(argv)
    path = os.path.abspath(args.path or default_path())
    if args.action == "hold":
        return cmd_hold(path)
    if args.action == "up":
        tokens = args.tokens if args.tokens is not None else max(1, (os.cpu_count() or 2) - 1)
        if tokens < 1:
            verdict("up", "error", reason="tokens-under-1")
            return 2
        return cmd_up(path, tokens)
    if args.action == "env":
        return cmd_env(path)
    if args.action == "status":
        return cmd_status(path)
    if args.action == "refill":
        return cmd_refill(path)
    if args.action == "down":
        return cmd_down(path)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
