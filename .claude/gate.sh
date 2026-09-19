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
#   sh .claude/gate.sh            # SCOPED (the default): the cheap whole-repo source-tree
#                                 # checks, then only the shell suites whose surface this
#                                 # branch's diff touches.  THIS is what the flow runs.
#   sh .claude/gate.sh --scoped   # same thing, named
#   sh .claude/gate.sh --full     # every step, unconditionally.  CI, or a human asking
#                                 # for it by name.  NO FLOW STEP EVER SELECTS THIS.
#   sh .claude/gate.sh --fast     # python source-tree checks, drift, version bump;
#                                 # the shell suites print SKIP
#
# Why the default is scoped: a whole-repo run is minutes of laptop time paid on every
# unit of every run, re-proving suites the branch did not go near.  The flow's gate is
# always scoped to the flow's own diff; the unconditional run happens once, in CI or when
# the user asks.  A `full`-tier step declares its SURFACE (the globs after its tier); in
# --scoped it runs iff a changed path matches one, and otherwise prints
# `SKIP  not touched by diff` — a SKIP, never a pass.  Add a step, declare its surface.
#
# Output (the full-gate skill's contract): one
#   GATE-STEP: <name> PASS|FAIL|SKIP|INCONCLUSIVE  <detail>
# per step, then `GATE-MODE: --full|--scoped|--fast`, then `GATE: PASS` or
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

MODE=--scoped
case $# in
  0) ;;
  1) case $1 in
       --full|--fast|--scoped) MODE=$1 ;;
       *) echo "usage: sh .claude/gate.sh [--fast|--scoped|--full]" >&2; exit 2 ;;
     esac ;;
  *) echo "usage: sh .claude/gate.sh [--fast|--scoped|--full]" >&2; exit 2 ;;
esac

ROOT=$(git rev-parse --show-toplevel) || { echo "gate: not inside a git repo" >&2; exit 2; }
cd "$ROOT" || exit 2
GATE_BASE=${GATE_BASE:-origin/master}
export GATE_BASE
LOGDIR=$(mktemp -d "${TMPDIR:-/tmp}/gate.XXXXXX") || exit 2
ESC=$(printf '\033')
FAILS=0

# The scoped selector's input: every path this branch changed against GATE_BASE, plus
# anything uncommitted.  An unresolvable base is NOT silently treated as "nothing
# changed" — that would turn every suite into a SKIP and the whole gate into a green
# that ran nothing.  It selects everything instead, and GATE-MODE says so.
CHANGED=
SCOPE_NOTE=
if [ "$MODE" = --scoped ]; then
  if git rev-parse --verify --quiet "$GATE_BASE" >/dev/null; then
    CHANGED=$(
      { git diff --name-only "$GATE_BASE"...HEAD 2>/dev/null
        git diff --name-only HEAD 2>/dev/null
        git ls-files --others --exclude-standard 2>/dev/null
      } | sort -u
    )
  else
    SCOPE_NOTE=" (base $GATE_BASE unresolvable — every step selected)"
  fi
fi

# selected <glob>...  — true when a changed path matches one of the step's surface globs.
selected() {
  [ "$MODE" = --scoped ] || return 0
  [ -z "$SCOPE_NOTE" ] || return 0
  [ -n "$1" ] || return 0          # a step that declares no surface always runs
  for g in "$@"; do
    printf '%s\n' "$CHANGED" | while IFS= read -r f; do
      [ -n "$f" ] || continue
      case $f in $g) exit 9 ;; esac
    done
    [ $? -eq 9 ] && return 0
  done
  return 1
}
HAVE_DASH=1
command -v dash >/dev/null 2>&1 || HAVE_DASH=0

# step <name> <fast|full> [surface globs...]
#   — reads the step's command lines on stdin, one per line.  The globs are the step's
#     surface: in --scoped, a `full` step runs only if the branch's diff touches one.
step() {
  name=$1 tier=$2
  shift 2
  if [ "$MODE" = --fast ] && [ "$tier" = full ]; then
    cat >/dev/null
    echo "GATE-STEP: $name SKIP  not in --fast"
    return
  fi
  if [ "$tier" = full ] && ! selected "$@"; then
    cat >/dev/null
    echo "GATE-STEP: $name SKIP  not touched by diff (surface: $*)"
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
# Surface: the suite drives the rule two ways, and both are covered here. The shape
# cases run over synthesized trees, so only the rule and its own suite can change them;
# the CENSUS reads the REAL corpus and asserts the exact agent count plus the negative
# form (no agent lacks `tools:`), so every agent entrypoint is in the surface too. A
# new agent under any plugin matches 'plugins/*/agents/*' and re-runs the census.
step validate-plugins-tools-allowlist full 'plugins/*/agents/*' 'scripts/validate-plugins.py' 'scripts/test-validate-plugins.sh' <<'EOF'
sh scripts/test-validate-plugins.sh
VP_PY=python3 sh scripts/test-validate-plugins.sh
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
step no-full-gate fast <<'EOF'
python3 scripts/check-no-full-gate.py
EOF
step repeat-causes fast <<'EOF'
python3 scripts/check-repeat-causes.py
EOF
step hooks full 'plugins/bett3r-ai-workflow/hooks/*' 'plugins/*/hooks/*' 'scripts/test-hooks.sh' 'scripts/fixtures/esas-pending/*' <<'EOF'
sh scripts/test-hooks.sh
HOOK_SH=dash sh scripts/test-hooks.sh
HOOK_SH=bash sh scripts/test-hooks.sh
EOF
step xp-layer-hooks full 'plugins/bett3r-xp-layer/*' 'scripts/test-xp-layer-hooks.sh' <<'EOF'
sh scripts/test-xp-layer-hooks.sh
HOOK_SH=dash sh scripts/test-xp-layer-hooks.sh
HOOK_SH=bash sh scripts/test-xp-layer-hooks.sh
EOF
# Surface: the suite reads the command/agent/skill prose AND drives
# `scripts/lane-step-parse.py` over `scripts/fixtures/lane-step/*`, and it holds the
# uniqueness guard that fails a second copy of the verdict-token rule anywhere under
# the plugin. So `bin/*`, `scripts/*` and the fixtures are in the surface too
# (GH-429 slice 1, F5/D6): without them a diff touching lane-step-parse.py alone
# printed SKIP for the only suite that guards it.
step flow-seams full 'plugins/bett3r-ai-workflow/commands/*' 'plugins/bett3r-ai-workflow/agents/*' 'plugins/bett3r-ai-workflow/skills/*' 'plugins/bett3r-ai-workflow/bin/*' 'plugins/bett3r-ai-workflow/scripts/*' 'scripts/fixtures/lane-step/*' 'docs/adr/*' 'scripts/test-flow-seams.sh' <<'EOF'
sh scripts/test-flow-seams.sh
EOF
step esas-design full 'plugins/bett3r-ai-workflow/skills/esas-design/*' 'plugins/bett3r-ai-workflow/skills/esas-pending/*' 'plugins/bett3r-ai-workflow/hooks/*' 'plugins/bett3r-ai-workflow/bin/*' 'scripts/test-esas-design.sh' 'scripts/fixtures/esas-design/*' <<'EOF'
sh scripts/test-esas-design.sh
PREFLIGHT_SH=dash sh scripts/test-esas-design.sh
PREFLIGHT_SH=bash sh scripts/test-esas-design.sh
EOF
step worktree-pool full 'plugins/bett3r-ai-workflow/bin/worktree-pool' 'plugins/bett3r-ai-workflow/commands/*' 'scripts/test-worktree-pool.sh' <<'EOF'
sh scripts/test-worktree-pool.sh
POOL_SH=dash dash scripts/test-worktree-pool.sh
POOL_SH=bash bash scripts/test-worktree-pool.sh
EOF
# Surface: the driver, its launcher, the parser it reads the verdict through (a
# change to the line grammar changes what the driver decides), the orchestrator
# command whose yield it consumes, and the suite itself.
step fleet-loop full 'plugins/bett3r-ai-workflow/bin/fleet-loop' 'plugins/bett3r-ai-workflow/scripts/fleet-loop.py' 'plugins/bett3r-ai-workflow/scripts/lane-step-parse.py' 'plugins/bett3r-ai-workflow/commands/start-multi.md' 'scripts/test-fleet-loop.sh' <<'EOF'
sh scripts/test-fleet-loop.sh
FLEET_SH=dash dash scripts/test-fleet-loop.sh
FLEET_SH=bash bash scripts/test-fleet-loop.sh
EOF
step work-docs-path full 'plugins/bett3r-ai-workflow/bin/work-docs-path' 'plugins/bett3r-ai-workflow/commands/*' 'plugins/bett3r-ai-workflow/skills/*' 'scripts/test-work-docs-path.sh' <<'EOF'
sh scripts/test-work-docs-path.sh
WDP_SH=dash dash scripts/test-work-docs-path.sh
WDP_SH=bash bash scripts/test-work-docs-path.sh
EOF
step design-map full 'plugins/bett3r-ai-workflow/bin/design-map' 'plugins/bett3r-ai-workflow/scripts/design-map.py' 'plugins/bett3r-ai-workflow/skills/design-map/*' 'scripts/test-design-map.sh' 'scripts/fixtures/design-map/*' <<'EOF'
sh scripts/test-design-map.sh
DM_SH=dash dash scripts/test-design-map.sh
DM_SH=bash bash scripts/test-design-map.sh
EOF
step design-multi-subjects full 'plugins/bett3r-ai-workflow/bin/design-multi-subjects' 'plugins/bett3r-ai-workflow/commands/design-multi.md' 'scripts/test-design-multi-subjects.sh' 'scripts/fixtures/design-multi-subjects/*' <<'EOF'
sh scripts/test-design-multi-subjects.sh
DMS_SH=dash dash scripts/test-design-multi-subjects.sh
DMS_SH=bash bash scripts/test-design-multi-subjects.sh
EOF
step design-snapshot full 'plugins/bett3r-ai-workflow/bin/design-map' 'plugins/bett3r-ai-workflow/scripts/design-map.py' 'plugins/bett3r-ai-workflow/commands/design*.md' 'scripts/test-design-snapshot.sh' 'scripts/fixtures/design-map/*' <<'EOF'
sh scripts/test-design-snapshot.sh
DS_SH=dash dash scripts/test-design-snapshot.sh
DS_SH=bash bash scripts/test-design-snapshot.sh
EOF
step map-tree full 'plugins/bett3r-ai-workflow/bin/map-tree' 'plugins/bett3r-ai-workflow/bin/resolved-marker-lint' 'plugins/bett3r-ai-workflow/scripts/*' 'scripts/test-map-tree.sh' 'scripts/fixtures/map-tree/*' <<'EOF'
sh scripts/test-map-tree.sh
MT_SH=dash dash scripts/test-map-tree.sh
MT_SH=bash bash scripts/test-map-tree.sh
EOF
step plan-candidates full 'plugins/bett3r-ai-workflow/bin/design-map' 'plugins/bett3r-ai-workflow/bin/worktree-pool' 'plugins/bett3r-ai-workflow/commands/plan.md' 'scripts/test-plan-candidates.sh' 'scripts/fixtures/design-map/*' <<'EOF'
sh scripts/test-plan-candidates.sh
PC_SH=dash dash scripts/test-plan-candidates.sh
PC_SH=bash bash scripts/test-plan-candidates.sh
EOF
step merge-multi-concerns full 'plugins/bett3r-ai-workflow/commands/merge-multi.md' 'plugins/bett3r-ai-workflow/commands/verify-build.md' 'plugins/bett3r-ai-workflow/agents/unit-lane.md' 'plugins/bett3r-ai-workflow/bin/concerns-check' 'scripts/test-merge-multi-concerns.sh' <<'EOF'
sh scripts/test-merge-multi-concerns.sh
dash scripts/test-merge-multi-concerns.sh
bash scripts/test-merge-multi-concerns.sh
EOF
# CI installs PyYAML here when missing; locally a missing PyYAML is INCONCLUSIVE.
if [ "$MODE" != --fast ] && ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "GATE-STEP: run-metrics INCONCLUSIVE  python3 cannot import yaml (PyYAML); CI installs it, the gate does not"
else
step run-metrics full 'scripts/run-metrics.mjs' 'scripts/test-run-metrics.sh' 'scripts/fixtures/run-metrics/*' 'plugins/bett3r-ai-workflow/skills/run-report/*' 'plugins/bett3r-ai-workflow/commands/run-report.md' <<'EOF'
sh scripts/test-run-metrics.sh
dash scripts/test-run-metrics.sh
EOF
fi
step skill-shadows full 'plugins/bett3r-ai-workflow/bin/check-skill-shadows' 'plugins/*/skills/*' 'plugins/installed_plugins.json' 'scripts/test-skill-shadows.sh' <<'EOF'
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
step version-gate-tests full 'scripts/check-plugin-version-bump.sh' 'scripts/test-version-gate.sh' '.claude/gate.sh' <<'EOF'
sh scripts/test-version-gate.sh
GATE_SH=dash dash scripts/test-version-gate.sh
GATE_SH=bash bash scripts/test-version-gate.sh
EOF

echo "GATE-MODE: $MODE$SCOPE_NOTE"
if [ "$FAILS" -eq 0 ]; then
  echo "GATE: PASS"
  exit 0
fi
echo "GATE: FAIL $FAILS step(s)"
exit 1
