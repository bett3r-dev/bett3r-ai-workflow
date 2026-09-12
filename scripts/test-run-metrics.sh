#!/bin/sh
# Oracle for `run-metrics --usage-fragment` — the generated usage numbers that
# /verify-build writes into build-summary.md before it opens the PR (XL-27 F3b).
#
# An agent cannot observe its own usage, so every number in build-summary.md's
# `usage` blocks must come from the transcripts. This suite drives the REAL
# script over a transcript fixture and recomputes the expected numbers from the
# fixture's rows in python (below). Recomputed independently: token sums and
# their dedupe by message id, slice attribution, model/effort choice, and the
# /verify-build proration. Mirrored from run-metrics on purpose (so a change
# there must change here): which subagents count toward the branch (the
# gitBranch filter, including the detached-HEAD drop) and the active-time gap
# rule (busy spans, reasoning gaps capped at 3 minutes).
#
# The fixture (scripts/fixtures/run-metrics/projects/) is one session on branch
# `feat/fixture`: `/build` at 10:00, `/verify-build` at 11:00, and subagents
# under `<session>/subagents/` with `.meta.json` descriptions:
#   slice 1  executor (one API response written twice — tokens dedupe by id),
#            test-runner, verifier (a 280-second life with no tool call — only
#            3 minutes of it active),
#            scope-check (a role the fragment does not carry)
#   slice 2  a sonnet executor, an opus `retry 1`, test-runner, verifier
#   slice 12 an executor — must never be read as slice 1
#   an executor described `fix the flaky timing test` — unattributed
#   R7: three pool-worktree executors with a `/fixture/repo-pool/wt-N` cwd —
#       slice 4 stamped with the task branch, slice 3 stamped `HEAD` (a detached
#       worktree — dropped, and counted as droppedDetached=1), slice 5 with
#       no gitBranch at all
#   a verify-build sweep (`Explore`)
#
# Transcript directory override: none is added. run-metrics resolves both the
# transcripts (`~/.claude/projects`) and its store (`~/.claude/bett3r-metrics`)
# from `homedir()`, so the fixture owns HOME — which also keeps every `--emit`
# here away from the real store.
#
# Run locally:  sh scripts/test-run-metrics.sh
# Exit code is non-zero if anything is broken, so CI fails the PR.
#
# RM_NODE selects the node binary, RM_PY the python that parses the YAML.

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
PLUGIN="$ROOT/plugins/bett3r-ai-workflow"
RUN_METRICS="$PLUGIN/scripts/run-metrics.mjs"
BUILD_MD="$PLUGIN/commands/build.md"
VERIFY_BUILD_MD="$PLUGIN/commands/verify-build.md"
FIXTURE="$ROOT/scripts/fixtures/run-metrics"
RM_NODE=${RM_NODE:-node}
RM_PY=${RM_PY:-python3}
BRANCH=feat/fixture

TMP=$( mktemp -d "${TMPDIR:-/tmp}/run-metrics-test.XXXXXX" ) || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

# The fixture owns everything ambient the script reads: HOME (transcripts and
# store), the working directory (fleet-lane discovery reads ./.work), and TZ.
unset CLAUDE_CONFIG_DIR
TZ=UTC; export TZ

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

# new_home <dir> — a HOME holding only the fixture transcripts.
new_home(){
  mkdir -p "$1/.claude" "$1/cwd"
  cp -R "$FIXTURE/projects" "$1/.claude/projects"
}

# rm_run <home> <args…> — the real script, from an empty cwd, under that HOME.
rm_run(){
  h=$1; shift
  ( cd "$h/cwd" && HOME="$h" "$RM_NODE" "$RUN_METRICS" "$@" )
}

printf '\nrun-metrics --usage-fragment — the usage blocks of build-summary.md\n\n'

if [ ! -d "$FIXTURE/projects" ]; then
  fail 'the transcript fixture exists' "missing: ${FIXTURE#"$ROOT"/}/projects"
  printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
  exit 1
fi

H1="$TMP/home-fragment"
new_home "$H1"

rm_run "$H1" --help > "$TMP/help.txt" 2>&1
if grep -qF -e '--usage-fragment' "$TMP/help.txt"; then
  pass 'the help text documents --usage-fragment'
else
  fail 'the help text documents --usage-fragment' "$( head -5 "$TMP/help.txt" )"
fi

rm_run "$H1" "$BRANCH" --usage-fragment --quiet > "$TMP/fragment.yaml" 2> "$TMP/fragment.err"
frag_rc=$?
verdict=$( grep -F 'RUN-METRICS-USAGE:v1' "$TMP/fragment.yaml" | tail -1 )
last=$( tail -1 "$TMP/fragment.yaml" )
case $last in
  '# RUN-METRICS-USAGE:v1 outcome=ok '*) pass 'the fragment ends with an outcome=ok verdict line (a YAML comment)' ;;
  *) fail 'the fragment ends with an outcome=ok verdict line (a YAML comment)' "rc=$frag_rc last line: $last" "stderr: $( head -3 "$TMP/fragment.err" )" ;;
esac

# PyYAML is required, never optional: a judge that cannot parse would otherwise
# read as a suite with nothing to check.
if ! "$RM_PY" -c 'import yaml' 2>/dev/null; then
  fail 'PyYAML is importable by '"$RM_PY" 'install it (e.g. python3 -m pip install pyyaml, or apt python3-yaml)'
  printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
  exit 1
fi

# Everything numeric is judged in one python pass that recomputes the expected
# values from the fixture rows and compares; it prints `ok|bad<TAB>label<TAB>detail`.
"$RM_PY" - "$FIXTURE/projects" "$TMP/fragment.yaml" "$BUILD_MD" "$VERIFY_BUILD_MD" "$BRANCH" > "$TMP/judged" 2> "$TMP/judged.err" <<'PY'
import json, os, re, sys, glob
import yaml

projects, frag_path, build_md, vb_md, BRANCH = sys.argv[1:6]
STALL = 180000
out = []
def check(label, ok, detail=""):
    out.append("%s\t%s\t%s" % ("ok" if ok else "bad", label, str(detail).replace("\n", " ")))

def ts(s):
    from datetime import datetime
    return int(round(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp() * 1000))

def jrows(p):
    return [json.loads(l) for l in open(p) if l.strip()]

def usage_of(rows):
    """tokens deduped by message.id, and the tokens each model/effort consumed"""
    seen = {}
    for r in rows:
        m = r.get("message") or {}
        if r.get("type") == "assistant" and m.get("usage"):
            seen[m["id"]] = (m.get("model"), r.get("effort"), m["usage"])
    kinds = {"input": 0, "cacheWrite": 0, "cacheRead": 0, "output": 0}
    by_model, by_effort = {}, {}
    for model, effort, u in seen.values():
        t = [u.get("input_tokens", 0), u.get("cache_creation_input_tokens", 0),
             u.get("cache_read_input_tokens", 0), u.get("output_tokens", 0)]
        for k, v in zip(kinds, t):
            kinds[k] += v
        by_model[model] = by_model.get(model, 0) + sum(t)
        by_effort[effort] = by_effort.get(effort, 0) + sum(t)
    return kinds, by_model, by_effort

def active_intervals(rows):
    """run-metrics' rule 2, restated: a run is busy from each tool_use to its
    tool_result; every gap between busy spans (and before the first, after the
    last) is reasoning, but only its first 3 minutes — the rest is stalled.
    A run with no tool call is therefore one gap: min(its life, 3 minutes)."""
    t = sorted(ts(r["timestamp"]) for r in rows if r.get("timestamp"))
    used = {}
    for r in rows:
        if r.get("type") == "assistant" and isinstance((r.get("message") or {}).get("content"), list):
            for c in r["message"]["content"]:
                if c.get("type") == "tool_use":
                    used[c["id"]] = ts(r["timestamp"])
    busy = []
    for r in rows:
        if r.get("type") == "user" and isinstance((r.get("message") or {}).get("content"), list):
            for c in r["message"]["content"]:
                if c.get("type") == "tool_result" and c.get("tool_use_id") in used:
                    busy.append((used[c["tool_use_id"]], ts(r["timestamp"])))
    merged = []
    for a, b in sorted(busy):
        if merged and a <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], b))
        else:
            merged.append((a, b))
    out, cursor = list(merged), t[0]
    for a, b in merged + [(t[-1], t[-1])]:
        if a > cursor:
            out.append((cursor, cursor + min(a - cursor, STALL)))
        cursor = max(cursor, b)
    return out

def dominant_branch(rows):
    votes = {}
    for r in rows:
        if isinstance(r.get("gitBranch"), str):
            votes[r["gitBranch"]] = votes.get(r["gitBranch"], 0) + 1
    return max(votes, key=votes.get) if votes else None

ROLE = {"executor": "executor", "verifier": "verifier", "test-runner": "testRunner"}
session = glob.glob(os.path.join(projects, "*", "*.jsonl"))[0]
main_rows = jrows(session)
envelope = (min(ts(r["timestamp"]) for r in main_rows), max(ts(r["timestamp"]) for r in main_rows))

runs = []   # (description, role, rows, branch)
for p in sorted(glob.glob(os.path.join(session[:-6], "subagents", "*.jsonl"))):
    meta = json.load(open(p[:-6] + ".meta.json"))
    rows = jrows(p)
    runs.append({"desc": meta["description"], "role": meta["agentType"].split(":")[-1],
                 "rows": rows, "branch": dominant_branch(rows), "file": os.path.basename(p)})

def cell(rs):
    if not rs:
        return None
    kinds = {"input": 0, "cacheWrite": 0, "cacheRead": 0, "output": 0}
    models, efforts, active = {}, {}, 0
    for r in rs:
        k, bm, be = usage_of(r["rows"])
        for x in kinds: kinds[x] += k[x]
        for m, v in bm.items(): models[m] = models.get(m, 0) + v
        for e, v in be.items(): efforts[e] = efforts.get(e, 0) + v
        active += sum(b - a for a, b in active_intervals(r["rows"]))
    return {"model": max(models, key=models.get), "effort": max(efforts, key=efforts.get),
            "tokens": sum(kinds.values()), "activeMs": active}

def slice_of(desc):
    m = re.search(r"\bslice (\d+)\b", desc)
    return int(m.group(1)) if m else None

# --- the fragment parses as YAML --------------------------------------------
try:
    frag = yaml.safe_load(open(frag_path))
    check("the fragment parses as YAML into a mapping", isinstance(frag, dict), type(frag).__name__)
except Exception as e:
    frag = None
    check("the fragment parses as YAML into a mapping", False, e)
if not isinstance(frag, dict):
    print("\n".join(out)); sys.exit(0)

slices = {}
for s in frag.get("slices") or []:
    if isinstance(s, dict) and "id" in s:
        slices[s["id"]] = s

# --- expected, from the fixture ---------------------------------------------
# A subagent counts toward this branch when its dominant gitBranch is the branch,
# or it carries none and started inside the session's window.
# DELIBERATELY MIRRORS run-metrics' collectRun filter, including its R7 gap: a
# worker stamped gitBranch=HEAD (a detached pool worktree) is dropped. If
# run-metrics ever attributes detached workers, this must change with it.
def counted(r):
    if r["branch"] is not None:
        return r["branch"] == BRANCH
    first = min(ts(x["timestamp"]) for x in r["rows"] if x.get("timestamp"))
    return envelope[0] <= first <= envelope[1]

expected = {}
unattributed = {}
for r in runs:
    if r["role"] not in ROLE or not counted(r):
        continue
    sid = slice_of(r["desc"])
    target = unattributed if sid is None else expected.setdefault(sid, {})
    target.setdefault(ROLE[r["role"]], []).append(r)

for sid in sorted(expected):
    for role in ("executor", "verifier", "testRunner"):
        want = cell(expected[sid].get(role, []))
        got = ((slices.get(sid) or {}).get("usage") or {}).get(role, "<missing key>")
        check("slice %d %s usage equals the fixture's rows" % (sid, role), got == want, "want %s got %s" % (want, got))

# Slices whose only dispatches are detached-HEAD workers are judged by the R7
# assertion alone, so a future fix that attributes them fails there, not here.
detached_ids = {slice_of(r["desc"]) for r in runs if r["role"] in ROLE and r["branch"] == "HEAD"} - set(expected)
cmp_slices = {k: v for k, v in slices.items() if k not in detached_ids}
check("the fragment names exactly the attributed slices of the fixture",
      sorted(cmp_slices) == sorted(expected), "want %s got %s" % (sorted(expected), sorted(cmp_slices)))

want_un = {role: cell(unattributed.get(role, [])) for role in ("executor", "verifier", "testRunner")}
check("the un-named dispatch is reported under unattributed", frag.get("unattributed") == want_un,
      "want %s got %s" % (want_un, frag.get("unattributed")))
un_tokens = want_un["executor"]["tokens"]
slice_total = sum(c["tokens"] for s in cmp_slices.values() for c in ((s.get("usage") or {}).values()) if c)
want_total = sum(cell(rs)["tokens"] for d in expected.values() for rs in d.values())
check("no slice absorbs the unattributed tokens (slice totals = attributed rows only)",
      slice_total == want_total, "slices sum %s, attributed rows %s, unattributed %s" % (slice_total, want_total, un_tokens))

s1 = ((slices.get(1) or {}).get("usage") or {}).get("executor") or {}
s12 = ((slices.get(12) or {}).get("usage") or {}).get("executor") or {}
only_s1 = cell([r for r in runs if r["desc"] == "slice 1 executor"])
check("slice 12 is its own slice and never counted as slice 1",
      s1.get("tokens") == only_s1["tokens"] and 12 in slices and s12.get("tokens") != s1.get("tokens"),
      "slice 1 executor %s (want %s), slice 12 executor %s" % (s1.get("tokens"), only_s1["tokens"], s12.get("tokens")))

scope = cell([r for r in runs if r["role"] == "scope-check"])["tokens"]
check("a scope-check dispatch is in no slice's usage", "scopeCheck" not in json.dumps(frag) and slice_total == want_total,
      "scope-check tokens %s" % scope)

# --- verifyBuild.usage: every non-slice-role run, clipped to /verify-build --
starts = [ts(r["timestamp"]) for r in main_rows
          if r.get("type") == "user" and isinstance(r["message"].get("content"), str)
          and "<command-name>/verify-build</command-name>" in r["message"]["content"]]
all_runs = [{"rows": main_rows}] + [r for r in runs if counted(r)]
run_end = max(max(ts(x["timestamp"]) for x in r["rows"] if x.get("timestamp")) for r in all_runs)
win = (starts[0], run_end)
tokens, active, models, efforts = 0, 0, {}, {}
for r in [{"rows": main_rows, "role": "orchestrator"}] + [r for r in runs if counted(r) and r["role"] not in ROLE]:
    iv = active_intervals(r["rows"])
    total = sum(b - a for a, b in iv)
    clipped = sum(max(0, min(b, win[1]) - max(a, win[0])) for a, b in iv)
    if clipped <= 0:
        continue
    share = clipped / total
    kinds, bm, be = usage_of(r["rows"])
    part = sum(int(v * share + 0.5) for v in kinds.values())
    tokens += part
    active += clipped
    for m, v in bm.items(): models[m] = models.get(m, 0) + v * share
    for e, v in be.items(): efforts[e] = efforts.get(e, 0) + v * share
want_vb = {"model": max(models, key=models.get), "effort": max(efforts, key=efforts.get), "tokens": tokens, "activeMs": active}
got_vb = (frag.get("verifyBuild") or {}).get("usage")
check("verifyBuild.usage equals the fixture's /verify-build window (slice roles excluded)", got_vb == want_vb,
      "want %s got %s" % (want_vb, got_vb))

# --- R7: pool-worktree workers ----------------------------------------------
check("R7: a worktree-cwd worker stamped with the task branch is counted (slice 4)", 4 in slices, sorted(slices))
check("R7: a worktree-cwd worker with no gitBranch, inside the session window, is counted (slice 5)", 5 in slices, sorted(slices))
verdict_line = [l for l in open(frag_path).read().splitlines() if "RUN-METRICS-USAGE:v1" in l][-1:]
dd = re.search(r"\bdroppedDetached=(\d+)\b", verdict_line[0]) if verdict_line else None
check("R7: a detached-HEAD worker (slice 3) is not attributed, and the verdict counts it droppedDetached=1",
      3 not in slices and dd is not None and dd.group(1) == "1",
      "slices %s, verdict %s" % (sorted(slices), verdict_line))

# --- one contract, two readers: key names vs the commands' blocks -----------
bm = open(build_md).read()
blocks = re.findall(r"```markdown\n(.*?)```", bm, re.S)
summary = [b for b in blocks if re.search(r"^slices:", b, re.M)]
if len(summary) != 1:
    check("build.md carries one build-summary frontmatter block", False, "found %d" % len(summary))
else:
    b = summary[0]
    top = re.findall(r"^([A-Za-z_]+):", b, re.M)
    item = re.findall(r"^  - ([A-Za-z_]+):", b, re.M)
    check("build.md's block spells work_item (never workItem) and lists slices by id",
          "work_item" in top and "slices" in top and item[:1] == ["id"] and "workItem" not in b, "top %s item %s" % (top, item))
    check("build.md names the usage and verifyBuild blocks it leaves to /verify-build",
          "The `usage` blocks and the `verifyBuild` block" in bm, "")
    check("the fragment's top keys are build-summary's slices and verifyBuild, plus unattributed",
          set(frag) == {"slices", "verifyBuild", "unattributed"} and "workItem" not in json.dumps(frag), sorted(frag))
    check("each fragment slice entry is the build-summary join key `id` plus `usage`",
          all(set(s) == {"id", "usage"} for s in slices.values()), [sorted(s) for s in slices.values()])

vb = open(vb_md).read()
vblocks = [x for x in re.findall(r"```yaml\n(.*?)```", vb, re.S) if "verifyBuild:" in x and "usage:" in x]
if len(vblocks) != 1:
    check("verify-build.md carries one usage block to fill", False, "found %d" % len(vblocks))
else:
    v = vblocks[0]
    roles = re.findall(r"^\s{6}([A-Za-z]+):\s*\{", v, re.M)
    fields = [re.findall(r"([A-Za-z]+):", body) for body in re.findall(r"\{([^}]*)\}", v)]
    check("verify-build.md's usage block roles are executor, verifier, testRunner",
          roles == ["executor", "verifier", "testRunner"], roles)
    check("verify-build.md's usage block keys the slices by build.md's `slices` / `id`",
          re.search(r"^slices:", v, re.M) is not None and re.search(r"^  - id:", v, re.M) is not None, v[:60])
    want_fields = fields[0] if fields else []
    check("every usage cell in verify-build.md's block has the same fields",
          want_fields == ["model", "effort", "tokens", "activeMs"] and all(f == want_fields for f in fields), fields)
    for sid, s in sorted(slices.items()):
        u = s.get("usage") or {}
        check("slice %d usage roles match verify-build.md's block" % sid, sorted(u) == sorted(roles), sorted(u))
        for role, c in u.items():
            if c is not None:
                check("slice %d %s fields match verify-build.md's block" % (sid, role), list(c) == want_fields, list(c))
    if isinstance(got_vb, dict):
        check("verifyBuild.usage fields match verify-build.md's block", list(got_vb) == want_fields, list(got_vb))

print("\n".join(out))
PY
if [ $? -ne 0 ] || [ ! -s "$TMP/judged" ]; then
  fail 'the fragment judge ran' "$( tail -5 "$TMP/judged.err" )"
fi
while IFS='	' read -r verdict_word label detail; do
  if [ "$verdict_word" = ok ]; then pass "$label"; else fail "$label" "$detail"; fi
done < "$TMP/judged"

case $verdict in
  *' unattributed=1'*) pass 'the verdict line counts the unattributed dispatches' ;;
  *) fail 'the verdict line counts the unattributed dispatches' "got: $verdict" ;;
esac

# A fragment-only run reads; it never writes the machine-local index.
if [ ! -e "$H1/.claude/bett3r-metrics/index.jsonl" ] && [ ! -d "$H1/.claude/bett3r-metrics/runs" ]; then
  pass '--usage-fragment writes no run document and no index row'
else
  fail '--usage-fragment writes no run document and no index row' "$( ls -R "$H1/.claude/bett3r-metrics" 2>&1 | head -5 )"
fi

# ---------------------------------------------------------------------------
printf '\nA failure to measure is a verdict, never invented numbers\n\n'
# ---------------------------------------------------------------------------

rm_run "$H1" no/such-branch --usage-fragment --quiet > "$TMP/missing.yaml" 2> "$TMP/missing.err"
missing_last=$( tail -1 "$TMP/missing.yaml" )
case $missing_last in
  '# RUN-METRICS-USAGE:v1 outcome=error reason=no-transcripts'*) pass 'a branch with no transcripts ends outcome=error reason=no-transcripts' ;;
  *) fail 'a branch with no transcripts ends outcome=error reason=no-transcripts' "last line: $missing_last" ;;
esac
if grep -qE 'tokens|activeMs' "$TMP/missing.yaml"; then
  fail 'the error fragment carries no usage numbers' "$( cat "$TMP/missing.yaml" )"
else
  pass 'the error fragment carries no usage numbers'
fi

# ---------------------------------------------------------------------------
printf '\nExisting behaviour: --emit writes runs/ + index.jsonl, replacing its row\n\n'
# ---------------------------------------------------------------------------

H2="$TMP/home-emit"
new_home "$H2"
mkdir -p "$H2/.claude/bett3r-metrics"
printf '%s\n' '{"branch":"other/branch","repo":"repo","runStart":"2025-12-01T00:00:00.000Z"}' > "$H2/.claude/bett3r-metrics/index.jsonl"

rm_run "$H2" "$BRANCH" --emit --quiet > "$TMP/emit1.txt" 2>&1
emit1_rc=$?
rm_run "$H2" "$BRANCH" --emit --quiet > "$TMP/emit2.txt" 2>&1
emit2_rc=$?
INDEX="$H2/.claude/bett3r-metrics/index.jsonl"
if [ "$emit1_rc" -eq 0 ] && [ "$emit2_rc" -eq 0 ] && [ -f "$H2/.claude/bett3r-metrics/runs/repo__feat_fixture.json" ]; then
  pass '--emit writes runs/<repo>__<branch>.json'
else
  fail '--emit writes runs/<repo>__<branch>.json' "rc=$emit1_rc/$emit2_rc" "$( ls "$H2/.claude/bett3r-metrics/runs" 2>&1 )"
fi
rows_total=$( grep -c . "$INDEX" 2>/dev/null )
rows_ours=$( grep -cF '"branch":"feat/fixture","repo":"repo"' "$INDEX" 2>/dev/null )
rows_other=$( grep -cF '"branch":"other/branch"' "$INDEX" 2>/dev/null )
if [ "$rows_total" = 2 ] && [ "$rows_ours" = 1 ] && [ "$rows_other" = 1 ]; then
  pass '--emit twice leaves one row for the branch (replaced, not appended) and keeps the other row'
else
  fail '--emit twice leaves one row for the branch (replaced, not appended) and keeps the other row' \
       "rows total=$rows_total ours=$rows_ours other=$rows_other"
fi
if grep -qF 'RETRY LEDGER' "$TMP/emit1.txt" && ! grep -qF 'RUN-METRICS-USAGE' "$TMP/emit1.txt"; then
  pass '--emit still prints the report, and no fragment'
else
  fail '--emit still prints the report, and no fragment' "$( head -3 "$TMP/emit1.txt" )"
fi

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
