#!/bin/sh
# Host gate for this repo — the committed local equivalent of
# .github/workflows/validate-plugins.yml (ESAS-186 D1).
#
# Why it exists: when CI does not run, every gate runs on a laptop, and fleet lanes were
# hand-copying the workflow's `run:` lines into their own ad-hoc loops — each copy
# a chance to drop a step and still report green. This file is the one copy, and
# scripts/test-gate-drift.sh fails if any `run:` command line in the workflow is
# missing from it.
#
# Every step runs INDEPENDENTLY — there is no fail-fast. The workflow's own
# "SEPARATE JOB on purpose" comment records why: a red step that ends a run turns
# every later step into a `skipped` indistinguishable from a pass, which once
# silently removed the version gate from two PRs. Here a red step is reported and
# the next step still runs. Order follows the workflow: job `validate`, then job
# `version-gate`.
#
# Run from anywhere inside the repo:
#   sh .claude/gate.sh            # same as --full
#   sh .claude/gate.sh --full     # every step
#   sh .claude/gate.sh --fast     # python source-tree checks, drift, version bump;
#                                 # the shell suites print SKIP
#
# Output (the full-gate skill's contract): one
#   GATE-STEP: <name> PASS|FAIL|SKIP|INCONCLUSIVE  <detail>
# per step, then `GATE-MODE: --full|--fast`, then `GATE: PASS` or
# `GATE: FAIL <n> step(s)`. Exit is non-zero iff any step is FAIL.
#
# Base ref: the workflow passes "origin/${{ github.base_ref || 'master' }}"; the
# gate spells that "${GATE_BASE}", defaulting to origin/master (override with
# GATE_BASE=<ref>). scripts/test-gate-drift.sh applies the same mapping.
#
# Deliberate differences from CI:
#   - the run-metrics block's `python3 -c 'import yaml' ... || sudo apt-get
#     install -y python3-yaml` line is an installer, not a check, and is not run;
#     if PyYAML cannot be imported that step is INCONCLUSIVE instead.
#   - a line that needs `dash` where dash is not installed is not run; its step
#     reports INCONCLUSIVE naming the line, never a silent drop.

MODE=--full
case $# in
  0) ;;
  1) case $1 in
       --full|--fast) MODE=$1 ;;
       *) echo "usage: sh .claude/gate.sh [--fast|--full]" >&2; exit 2 ;;
     esac ;;
  *) echo "usage: sh .claude/gate.sh [--fast|--full]" >&2; exit 2 ;;
esac

ROOT=$(git rev-parse --show-toplevel) || { echo "gate: not inside a git repo" >&2; exit 2; }
cd "$ROOT" || exit 2
GATE_BASE=${GATE_BASE:-origin/master}
export GATE_BASE
LOGDIR=$(mktemp -d "${TMPDIR:-/tmp}/gate.XXXXXX") || exit 2
ESC=$(printf '\033')
FAILS=0
HAVE_DASH=1
command -v dash >/dev/null 2>&1 || HAVE_DASH=0

# step <name> <fast|full>  — reads the step's command lines on stdin, one per line.
step() {
  name=$1 tier=$2
  if [ "$MODE" = --fast ] && [ "$tier" = full ]; then
    cat >/dev/null
    echo "GATE-STEP: $name SKIP  not in --fast"
    return
  fi
  n=0 bad=0 inc=0 detail=
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=$((n + 1))
    log="$LOGDIR/$name.$n.log"
    case " $line" in
      *" dash "*|*"=dash "*)
        if [ "$HAVE_DASH" -eq 0 ]; then
          inc=$((inc + 1)); detail="$detail [$n] dash not installed: $line;"
          continue
        fi ;;
    esac
    sh -c "$line" </dev/null >"$log" 2>&1
    rc=$?
    count=$(sed "s/${ESC}\[[0-9;]*m//g" "$log" | grep -E 'passed|failed' | tail -n 1)
    # No count line (the python checks): fall back to the last non-blank line.
    [ -n "$count" ] || count=$(sed "s/${ESC}\[[0-9;]*m//g" "$log" | grep . | tail -n 1)
    if [ "$rc" -ne 0 ]; then
      bad=$((bad + 1)); detail="$detail [$n] FAILED (exit $rc): $line ${count:+($count) }(log: $log);"
    elif [ -n "$count" ]; then
      detail="$detail [$n] $count;"
    fi
  done
  if [ "$bad" -gt 0 ]; then
    FAILS=$((FAILS + 1)); echo "GATE-STEP: $name FAIL $detail"
  elif [ "$inc" -gt 0 ]; then
    echo "GATE-STEP: $name INCONCLUSIVE $detail"
  else
    echo "GATE-STEP: $name PASS $detail"
  fi
}

# ---- job: validate ----------------------------------------------------------
step validate-plugins fast <<'EOF'
python3 scripts/validate-plugins.py
EOF
step artifact-links fast <<'EOF'
python3 scripts/check-artifact-links.py
EOF
step needles fast <<'EOF'
python3 scripts/check-needles.py
EOF
step eval-coverage fast <<'EOF'
python3 scripts/check-eval-coverage.py
EOF
step closes-syntax fast <<'EOF'
python3 scripts/check-closes-syntax.py "${GATE_BASE}"
EOF
step hooks full <<'EOF'
sh scripts/test-hooks.sh
HOOK_SH=dash sh scripts/test-hooks.sh
HOOK_SH=bash sh scripts/test-hooks.sh
EOF
step xp-layer-hooks full <<'EOF'
sh scripts/test-xp-layer-hooks.sh
HOOK_SH=dash sh scripts/test-xp-layer-hooks.sh
HOOK_SH=bash sh scripts/test-xp-layer-hooks.sh
EOF
step flow-seams full <<'EOF'
sh scripts/test-flow-seams.sh
EOF
step esas-design full <<'EOF'
sh scripts/test-esas-design.sh
PREFLIGHT_SH=dash sh scripts/test-esas-design.sh
PREFLIGHT_SH=bash sh scripts/test-esas-design.sh
EOF
step worktree-pool full <<'EOF'
sh scripts/test-worktree-pool.sh
POOL_SH=dash dash scripts/test-worktree-pool.sh
POOL_SH=bash bash scripts/test-worktree-pool.sh
EOF
step work-docs-path full <<'EOF'
sh scripts/test-work-docs-path.sh
WDP_SH=dash dash scripts/test-work-docs-path.sh
WDP_SH=bash bash scripts/test-work-docs-path.sh
EOF
step design-map full <<'EOF'
sh scripts/test-design-map.sh
DM_SH=dash dash scripts/test-design-map.sh
DM_SH=bash bash scripts/test-design-map.sh
EOF
step design-multi-subjects full <<'EOF'
sh scripts/test-design-multi-subjects.sh
DMS_SH=dash dash scripts/test-design-multi-subjects.sh
DMS_SH=bash bash scripts/test-design-multi-subjects.sh
EOF
step design-snapshot full <<'EOF'
sh scripts/test-design-snapshot.sh
DS_SH=dash dash scripts/test-design-snapshot.sh
DS_SH=bash bash scripts/test-design-snapshot.sh
EOF
step map-tree full <<'EOF'
sh scripts/test-map-tree.sh
MT_SH=dash dash scripts/test-map-tree.sh
MT_SH=bash bash scripts/test-map-tree.sh
EOF
step plan-candidates full <<'EOF'
sh scripts/test-plan-candidates.sh
PC_SH=dash dash scripts/test-plan-candidates.sh
PC_SH=bash bash scripts/test-plan-candidates.sh
EOF
step merge-multi-concerns full <<'EOF'
sh scripts/test-merge-multi-concerns.sh
dash scripts/test-merge-multi-concerns.sh
bash scripts/test-merge-multi-concerns.sh
EOF
# CI installs PyYAML here when missing; locally a missing PyYAML is INCONCLUSIVE.
if [ "$MODE" = --full ] && ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "GATE-STEP: run-metrics INCONCLUSIVE  python3 cannot import yaml (PyYAML); CI installs it, the gate does not"
else
step run-metrics full <<'EOF'
sh scripts/test-run-metrics.sh
dash scripts/test-run-metrics.sh
EOF
fi
step skill-shadows full <<'EOF'
sh scripts/test-skill-shadows.sh
SHADOW_PY=python3 sh scripts/test-skill-shadows.sh
EOF
step gate-drift fast <<'EOF'
sh scripts/test-gate-drift.sh
EOF

# ---- job: version-gate ------------------------------------------------------
# The version script prints `SKIP reason=deferred-to-merge-multi` (exit 0) in a
# lane whose version judgement is deferred; that is a SKIP, not a PASS.
vlog="$LOGDIR/version-bump.log"
vcmd=$(cat <<'EOF'
sh scripts/check-plugin-version-bump.sh "${GATE_BASE}"
EOF
)
sh -c "$vcmd" </dev/null >"$vlog" 2>&1
vrc=$?
if [ "$vrc" -eq 0 ] && grep -q 'SKIP reason=deferred-to-merge-multi' "$vlog"; then
  echo "GATE-STEP: version-bump SKIP reason=deferred-to-merge-multi"
elif [ "$vrc" -eq 0 ]; then
  echo "GATE-STEP: version-bump PASS  $(tail -n 1 "$vlog")"
else
  FAILS=$((FAILS + 1))
  echo "GATE-STEP: version-bump FAIL  exit $vrc: $(tail -n 1 "$vlog") (log: $vlog)"
fi
step version-gate-tests full <<'EOF'
sh scripts/test-version-gate.sh
GATE_SH=dash dash scripts/test-version-gate.sh
GATE_SH=bash bash scripts/test-version-gate.sh
EOF

echo "GATE-MODE: $MODE"
if [ "$FAILS" -eq 0 ]; then
  echo "GATE: PASS"
  exit 0
fi
echo "GATE: FAIL $FAILS step(s)"
exit 1
