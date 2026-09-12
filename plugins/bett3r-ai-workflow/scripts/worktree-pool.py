#!/usr/bin/env python3
"""The git mechanics of /build's worktree pool. Judgment lives in commands/build.md.

/build runs slices that are ready at the same moment concurrently, each in its
own worktree, and lands each green commit on the task branch. What is ready,
the order commits land in, and what to do about a refusal are decisions, and
they stay in the command. This script only does the git: it sizes, creates,
resets, lands and removes, and says what happened in ONE line.

Every subcommand ends with a verdict line on stdout (ADR-004):

    WORKTREE-POOL:v1 cmd=<subcommand> outcome=<outcome> key=value ...

Read the line, never the exit code alone — a wrapper or a pipe overwrites the
exit status without anyone noticing, and it cannot carry `sha=` or `paths=`
anyway. The exit code is a coarse cross-check: 0 for the success outcome,
1 for refused / conflict / failed, 2 for a usage error. No line at all means the
script died before concluding. Attribute values never contain whitespace;
paths in `paths=` and `worktrees=` are comma-joined and percent-encoded.

Subcommands (run from the main checkout, which has the task branch checked out):

  size <slices.yaml> [--only <id,id>] [--max-parallel N] [--pool-max N]
      outcome=ok width=W pool=P. Width is the largest set of slices that will
      run and can be ready at the same moment — the largest antichain of the
      dependency order, not the largest topological wave. The slices that will
      run are the `passes: false` ones, narrowed to --only when given; a
      `passes: true` slice is a satisfied dependency and never a member. With
      --only, a target whose dependency is neither passed nor targeted is
      outcome=error reason=unmet-dependency-outside-only. Pool is
      min(width, --max-parallel, --pool-max), and 0 — no pool — when that is
      below 2.

  provision <n> [--root DIR]
      outcome=provisioned. Adds worktrees DIR/wt-1..n detached at the task
      branch tip, one after another. DIR defaults to `<checkout>-pool`, a
      sibling of the checkout, never inside it (a nested tree is walked by the
      host repo's own test and typecheck globs). A path that is already one of
      this repo's worktrees is reused — unless it holds work (any tracked or
      untracked change, or a commit not on the task branch), which is
      outcome=refused reason=reused-worktree-holds-work path=<worktree>. It installs and builds nothing: every
      take of a worktree goes through `reset`, which does.

  reset <worktree> <tip> --install CMD --build CMD
      outcome=reset. `git switch --detach <tip>`, `git clean -fd` (ignored
      files such as node_modules/ survive), then install, then build — always,
      whether or not anything changed. CMD is the host repo's own command, run
      with `sh -c` in the worktree; an empty CMD means the repo has none and is
      reported as `install=none` / `build=none`. Both flags are required: this
      script knows no package manager. Refuses (`reason=unlanded|dirty`) a
      worktree holding a commit not on <tip>, or tracked modifications, since
      the switch would discard that work.

  land <worktree> <sha> --base <reset tip>
      outcome=landed already=false sha=<landed sha> source=<sha>. Cherry-picks
      <sha> (a commit in <worktree>) onto the checked-out task branch. --base is
      required: the tip that worktree's last reset took. A sha equal to it or
      older is no slice commit — a worker that never committed still has it at
      HEAD — and is outcome=refused reason=sha-not-after-base. When the
      branch already carries that change — the same sha, or a commit with the
      same stable patch id — it picks nothing and reports outcome=landed
      already=true sha=<that commit>, so a resumed run can re-land safely. On a
      conflict it aborts the cherry-pick, leaves the branch where it was, and
      reports outcome=conflict paths=<conflicted paths>. Refuses a sha not in
      <worktree> (`reason=sha-not-in-worktree`) and a main checkout with tracked
      modifications (`reason=main-checkout-dirty`); untracked files in the main
      checkout are accepted.

  teardown [--root DIR]
      outcome=removed n=N. Removes every worktree under DIR. Refuses
      (`reason=unlanded`, then `reason=dirty`) while any of them holds a commit
      whose change is not on the task branch, or any tracked or untracked change.
"""
import os
import re
import subprocess
import sys
from urllib.parse import quote

TOKEN = "WORKTREE-POOL:v1"
EXIT = {"ok": 0, "provisioned": 0, "reset": 0, "landed": 0, "removed": 0,
        "refused": 1, "conflict": 1, "failed": 1, "error": 2}


def verdict(cmd, outcome, **attrs):
    parts = [TOKEN, f"cmd={cmd}", f"outcome={outcome}"]
    for key, val in attrs.items():
        parts.append(f"{key}={val}")
    sys.stdout.write(" ".join(parts) + "\n")
    sys.stdout.flush()
    return EXIT[outcome]


def enc(paths):
    return ",".join(quote(p, safe="/._-+@") for p in paths)


def git(*args, cwd=None):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def note(msg):
    sys.stdout.write(msg + "\n")
    sys.stdout.flush()


class Usage(Exception):
    pass


def parse_flags(args, known):
    """Split positional args from `--flag value` pairs; unknown flags are usage errors."""
    pos, flags, i = [], {}, 0
    while i < len(args):
        a = args[i]
        if a.startswith("--"):
            if a not in known:
                raise Usage(f"unknown-flag-{a[2:]}")
            if i + 1 >= len(args):
                raise Usage(f"missing-value-{a[2:]}")
            flags[a] = args[i + 1]
            i += 2
        else:
            pos.append(a)
            i += 1
    return pos, flags


def positive_int(raw, name):
    if not re.fullmatch(r"[0-9]+", raw or "") or int(raw) < 1:
        raise Usage(f"{name}-not-a-positive-integer")
    return int(raw)


# --- size ------------------------------------------------------------------

ITEM = re.compile(r"^(\s*)-\s+id:\s*(.+?)\s*$")


def scalar(raw):
    raw = re.sub(r"\s+#.*$", "", raw).strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
        raw = raw[1:-1]
    return raw


def parse_slices(path):
    """The narrow reader: `id`, `passes`, `depends_on` of each item under `slices:`.

    No YAML dependency, same discipline as scripts/test-flow-seams.sh: the plan
    format is a list of maps, and a shape this cannot read is an error, never a
    guess — a wrong width sizes a pool for a plan that is not the one on disk.
    """
    lines = open(path, encoding="utf-8").read().splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if re.match(r"^slices:\s*(#.*)?$", l))
    except StopIteration:
        raise ValueError("no top-level `slices:` key")
    slices, cur, dash, key_indent, block = [], None, None, None, False
    for line in lines[start + 1:]:
        if line.strip() == "" or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            break
        m = ITEM.match(line)
        if m and (dash is None or len(m.group(1)) == dash):
            dash = len(m.group(1))
            key_indent = dash + 2
            cur = {"id": scalar(m.group(2)), "passes": False, "depends_on": None}
            slices.append(cur)
            block = False
            continue
        if cur is None:
            raise ValueError(f"line before the first `- id:` item: {line.strip()!r}")
        if block:
            b = re.match(r"^\s+-\s*(.+?)\s*$", line)
            if b and indent > key_indent:
                cur["depends_on"].append(scalar(b.group(1)))
                continue
            block = False
        if indent != key_indent:
            continue
        k = re.match(r"^\s*([A-Za-z_]+):\s*(.*)$", line)
        if not k:
            continue
        key, val = k.group(1), scalar(k.group(2))
        if key == "passes":
            cur["passes"] = val == "true"
        elif key == "depends_on":
            if val == "":
                cur["depends_on"], block = [], True
            elif val.startswith("[") and val.endswith("]"):
                cur["depends_on"] = [scalar(x) for x in val[1:-1].split(",") if x.strip()]
            else:
                raise ValueError(f"slice {cur['id']}: unreadable depends_on {val!r}")
    if not slices:
        raise ValueError("`slices:` holds no `- id:` items")
    for s in slices:
        if s["depends_on"] is None:
            raise ValueError(f"slice {s['id']} has no depends_on")
    return slices


class PlanError(Exception):
    def __init__(self, reason, detail):
        super().__init__(detail)
        self.reason = reason


def dag_width(slices, only=None):
    """The most slices that will run and can be ready at the same moment.

    That is the largest antichain of the dependency order over the running set
    (`passes: false`, narrowed to `only` when given): any set of mutually
    independent slices is ready together once their ancestors have landed. It is
    NOT the largest topological wave, which undercounts — a slice two levels down
    can be ready beside a root. By Dilworth's theorem the largest antichain is
    the number of slices minus a maximum matching over the transitive closure.
    """
    by_id = {s["id"]: s for s in slices}
    for s in slices:
        for d in s["depends_on"]:
            if d not in by_id:
                raise PlanError("unknown-dependency", f"slice {s['id']} depends on unknown slice {d}")
    ancestors, state = {}, {}

    def anc(i):
        if state.get(i) == "open":
            raise PlanError("dependency-cycle", f"dependency cycle through slice {i}")
        if i not in ancestors:
            state[i] = "open"
            acc = set()
            for d in by_id[i]["depends_on"]:
                acc |= {d} | anc(d)
            ancestors[i], state[i] = acc, "done"
        return ancestors[i]

    for i in by_id:
        anc(i)
    if only is None:
        run = [i for i in by_id if not by_id[i]["passes"]]
    else:
        unknown = [i for i in only if i not in by_id]
        if unknown:
            raise PlanError("unknown-only-id", "no such slice: " + ",".join(unknown))
        run = [i for i in by_id if i in set(only) and not by_id[i]["passes"]]
        for i in run:
            unmet = [d for d in by_id[i]["depends_on"] if d not in only and not by_id[d]["passes"]]
            if unmet:
                raise PlanError("unmet-dependency-outside-only",
                                f"slice {i} depends on {','.join(unmet)}, neither passed nor in --only")
    match = {}  # right node -> left node

    def augment(u, seen):
        for v in run:
            if u in ancestors[v] and v not in seen:
                seen.add(v)
                if v not in match or augment(match[v], seen):
                    match[v] = u
                    return True
        return False

    matched = sum(1 for u in run if augment(u, set()))
    return len(run) - matched


def cmd_size(args):
    pos, flags = parse_flags(args, {"--max-parallel", "--pool-max", "--only"})
    if len(pos) != 1:
        raise Usage("size-takes-one-slices-file")
    caps = [positive_int(flags[f], f[2:]) for f in ("--max-parallel", "--pool-max") if f in flags]
    only = None
    if "--only" in flags:
        only = [x.strip() for x in flags["--only"].split(",") if x.strip()]
        if not only:
            raise Usage("only-names-no-slice")
    try:
        width = dag_width(parse_slices(pos[0]), only)
    except (OSError, ValueError) as e:
        note(f"worktree-pool size: {e}")
        return verdict("size", "error", reason="unreadable-plan")
    except PlanError as e:
        note(f"worktree-pool size: {e}")
        return verdict("size", "error", reason=e.reason)
    pool = min([width, *caps])
    return verdict("size", "ok", width=width, pool=pool if pool >= 2 else 0)


# --- shared git state ----------------------------------------------------------

def checkout():
    """The main checkout this is run from, and the task branch it has checked out."""
    rc, top, _ = git("rev-parse", "--show-toplevel")
    if rc != 0:
        raise Usage("not-a-git-checkout")
    rc, branch, _ = git("symbolic-ref", "--short", "-q", "HEAD")
    if rc != 0:
        raise Usage("checkout-is-detached-no-task-branch")
    return os.path.realpath(top), branch


def worktrees():
    _, out, _ = git("worktree", "list", "--porcelain")
    return [os.path.realpath(l[len("worktree "):]) for l in out.splitlines() if l.startswith("worktree ")]


def pool_member(path, top):
    real = os.path.realpath(path)
    if real == top:
        raise Usage("refusing-the-main-checkout")
    if real not in worktrees():
        raise Usage("not-a-worktree-of-this-repo")
    return real


def default_root(top, flags):
    root = os.path.realpath(flags.get("--root") or f"{top}-pool")
    if re.search(r"\s", root):
        raise Usage("whitespace-in-pool-root")
    return root


def unlanded(wt, upstream):
    """Commits in the worktree whose change is not on `upstream` (`git cherry` `+`).

    By patch, not by sha: a landed commit is a cherry-pick, so the branch holds
    an equivalent commit under a different sha and ancestry alone would call
    every landed slice unlanded.
    """
    _, out, _ = git("cherry", upstream, "HEAD", cwd=wt)
    return [l[2:] for l in out.splitlines() if l.startswith("+ ")]


# --- provision / reset / land / teardown -------------------------------------------

def cmd_provision(args):
    pos, flags = parse_flags(args, {"--root"})
    if len(pos) != 1:
        raise Usage("provision-takes-a-count")
    n = positive_int(pos[0], "count")
    top, branch = checkout()
    root = default_root(top, flags)
    _, tip, _ = git("rev-parse", branch)
    made, registered = [], worktrees()
    for i in range(1, n + 1):
        path = os.path.join(root, f"wt-{i}")
        if os.path.realpath(path) in registered:
            # Reuse is for a tree a previous run left clean. One holding work —
            # an escalated slice's files, or a commit not on the branch — is what
            # teardown refused to remove; the reset that follows provisioning
            # would clean it away, so it is refused here, across runs.
            real = os.path.realpath(path)
            if git("status", "--porcelain", cwd=real)[1] or unlanded(real, branch):
                return verdict("provision", "refused", reason="reused-worktree-holds-work", path=enc([real]))
            note(f"reused {path}")
        elif os.path.exists(path):
            return verdict("provision", "refused", reason="path-exists-not-a-worktree", path=enc([path]))
        else:
            rc, _, err = git("worktree", "add", "--detach", path, tip)
            if rc != 0:
                note(err)
                return verdict("provision", "failed", step="worktree-add", path=enc([path]))
            note(f"added {path}")
        made.append(path)
    return verdict("provision", "provisioned", n=n, branch=branch, tip=tip, root=enc([root]), worktrees=enc(made))


def run_host(cmd, wt):
    if cmd.strip() == "":
        return "none", 0
    r = subprocess.run(cmd, shell=True, cwd=wt, stdout=sys.stderr.fileno())
    return "ran", r.returncode


def cmd_reset(args):
    pos, flags = parse_flags(args, {"--install", "--build"})
    if "--install" not in flags or "--build" not in flags:
        raise Usage("reset-needs---install-and---build")
    if len(pos) != 2:
        raise Usage("reset-takes-worktree-and-tip")
    top, _ = checkout()
    wt = pool_member(pos[0], top)
    rc, tip, _ = git("rev-parse", "--verify", "-q", pos[1] + "^{commit}")
    if rc != 0:
        raise Usage("tip-does-not-resolve")
    held = unlanded(wt, tip)
    if held:
        note("unlanded: " + " ".join(held))
        return verdict("reset", "refused", reason="unlanded", worktree=enc([wt]))
    _, dirty, _ = git("status", "--porcelain", "--untracked-files=no", cwd=wt)
    if dirty:
        note(dirty)
        return verdict("reset", "refused", reason="dirty", worktree=enc([wt]))
    for step, argv in (("switch", ["switch", "--detach", "--quiet", tip]), ("clean", ["clean", "-fd", "--quiet"])):
        rc, _, err = git(*argv, cwd=wt)
        if rc != 0:
            note(err)
            return verdict("reset", "failed", step=step, worktree=enc([wt]))
    ran = {}
    for step in ("install", "build"):
        ran[step], rc = run_host(flags["--" + step], wt)
        if rc != 0:
            return verdict("reset", "failed", step=step, rc=rc, worktree=enc([wt]))
    return verdict("reset", "reset", worktree=enc([wt]), tip=tip, install=ran["install"], build=ran["build"])


def landed_equivalent(top, sha):
    """The commit on the checked-out branch that already carries `sha`'s change, or None.

    What makes `land` idempotent: a run that crashed between a land and its
    record re-lands the same sha on resume, and a cherry-pick of a change that
    is already there stops as an empty pick. `sha` itself when it is reachable;
    otherwise the newest commit since the merge base with the same stable patch id.
    """
    if git("merge-base", "--is-ancestor", sha, "HEAD", cwd=top)[0] == 0:
        return sha
    rc, base, _ = git("merge-base", sha, "HEAD", cwd=top)
    if rc != 0:
        return None

    def patch_ids(*log_args):
        log = subprocess.run(["git", *log_args], cwd=top, capture_output=True)
        ids = subprocess.run(["git", "patch-id", "--stable"], cwd=top, input=log.stdout, capture_output=True)
        return [line.split() for line in ids.stdout.decode().splitlines() if len(line.split()) == 2]

    want = patch_ids("show", sha)
    if not want:
        return None
    for pid, commit in patch_ids("log", "-p", f"{base}..HEAD"):
        if pid == want[0][0]:
            return commit
    return None


def cmd_land(args):
    pos, flags = parse_flags(args, {"--base"})
    if len(pos) != 2:
        raise Usage("land-takes-worktree-and-sha")
    if "--base" not in flags:
        raise Usage("land-needs---base")
    top, branch = checkout()
    wt = pool_member(pos[0], top)
    rc, sha, _ = git("rev-parse", "--verify", "-q", pos[1] + "^{commit}")
    if rc != 0:
        raise Usage("sha-does-not-resolve")
    rc, base, _ = git("rev-parse", "--verify", "-q", flags["--base"] + "^{commit}")
    if rc != 0:
        raise Usage("base-does-not-resolve")
    if git("merge-base", "--is-ancestor", sha, "HEAD", cwd=wt)[0] != 0:
        return verdict("land", "refused", reason="sha-not-in-worktree", source=sha)
    # The reset tip, or anything older, is not a slice commit: it is what a worker
    # that never committed still has at HEAD, and it is always "on the branch", so
    # without this the idempotent path below would call an unbuilt slice landed.
    if git("merge-base", "--is-ancestor", sha, base, cwd=top)[0] == 0:
        return verdict("land", "refused", reason="sha-not-after-base", source=sha, base=base)
    equivalent = landed_equivalent(top, sha)
    if equivalent:
        note(f"already on {branch} as {equivalent}")
        return verdict("land", "landed", already="true", sha=equivalent, source=sha, branch=branch)
    # Tracked modifications only: untracked files in the main checkout (the
    # orchestrator's own scratch) are accepted, and git itself refuses a pick
    # that would overwrite one — reported below as failed step=cherry-pick.
    _, dirty, _ = git("status", "--porcelain", "--untracked-files=no", cwd=top)
    if dirty:
        note(dirty)
        return verdict("land", "refused", reason="main-checkout-dirty", source=sha)
    _, before, _ = git("rev-parse", "HEAD", cwd=top)
    rc, _, err = git("cherry-pick", sha, cwd=top)
    if rc == 0:
        _, after, _ = git("rev-parse", "HEAD", cwd=top)
        return verdict("land", "landed", already="false", sha=after, source=sha, branch=branch)
    _, conflicted, _ = git("diff", "--name-only", "--diff-filter=U", cwd=top)
    paths = conflicted.splitlines()
    in_progress = git("rev-parse", "-q", "--verify", "CHERRY_PICK_HEAD", cwd=top)[0] == 0
    if in_progress:
        git("cherry-pick", "--abort", cwd=top)
    note(err)
    _, now, _ = git("rev-parse", "HEAD", cwd=top)
    if now != before:
        return verdict("land", "error", reason="tip-moved-after-abort", tip=now, before=before)
    if paths:
        for p in paths:
            note(f"conflict: {p}")
        return verdict("land", "conflict", paths=enc(paths), tip=before, source=sha)
    # An equivalent commit was already ruled out above, so an empty pick here is
    # a change that vanished against the branch without a matching patch.
    reason = "empty-no-equivalent-commit" if in_progress else "cherry-pick-refused"
    return verdict("land", "failed", step="cherry-pick", reason=reason, tip=before, source=sha)


def cmd_teardown(args):
    pos, flags = parse_flags(args, {"--root"})
    if pos:
        raise Usage("teardown-takes-no-positional-args")
    top, branch = checkout()
    root = default_root(top, flags)
    members = [w for w in worktrees() if w.startswith(root + os.sep)]
    held = [w for w in members if unlanded(w, branch)]
    if held:
        return verdict("teardown", "refused", reason="unlanded", worktrees=enc(held))
    dirty = [w for w in members if git("status", "--porcelain", cwd=w)[1]]
    if dirty:
        return verdict("teardown", "refused", reason="dirty", worktrees=enc(dirty))
    for w in members:
        rc, _, err = git("worktree", "remove", w)
        if rc != 0:
            note(err)
            return verdict("teardown", "failed", step="worktree-remove", worktrees=enc([w]))
        note(f"removed {w}")
    if os.path.isdir(root) and not os.listdir(root):
        os.rmdir(root)
    return verdict("teardown", "removed", n=len(members), root=enc([root]))


COMMANDS = {"size": cmd_size, "provision": cmd_provision, "reset": cmd_reset,
            "land": cmd_land, "teardown": cmd_teardown}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDS:
        note(__doc__.strip().splitlines()[0])
        return verdict(argv[1] if len(argv) > 1 and re.fullmatch(r"[a-z]+", argv[1]) else "none",
                       "error", reason="unknown-subcommand")
    try:
        return COMMANDS[argv[1]](argv[2:])
    except Usage as e:
        return verdict(argv[1], "error", reason=str(e))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
