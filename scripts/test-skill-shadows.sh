#!/bin/sh
# Oracle for plugins/bett3r-ai-workflow/bin/check-skill-shadows.
#
# The detector it drives guards a failure whose whole signature is ABSENCE: a
# repo-local `.claude/skills/<x>/` and a plugin skill of the same name are both
# live in one session, the local one listed unprefixed and the plugin one
# prefixed, and nothing in either file says which wins. Both parse. Both load.
# Neither errors. One host repo carried ten such pairs for months and recorded
# the cost in its own cleanup commit: "the bare (local, staler) name is what won
# resolution. DDD work was being done against outdated copies while the plugin
# looked installed."
#
# So the detector is the only thing that would ever report it — which makes a
# detector that has silently stopped detecting indistinguishable from a clean
# fleet of repos. That is what this suite is for. It cannot use the real
# ~/.claude, because the interesting inputs are host repos and installed plugin
# sets that do not exist on this machine and must not: every case below builds a
# throwaway host repo and a throwaway plugin tree in a temp dir, runs the real
# script over them, and asserts the one thing a caller acts on — the exit status.
#
# The shapes are the ones the detector has to tell apart:
#
#   1. local skill == plugin skill              → shadow (the original ten)
#   2. local command == plugin command          → shadow (/design, /build)
#   3. local agent == plugin agent              → shadow (test-runner)
#   4. local RULE == plugin SKILL               → shadow: a rule is auto-loaded
#                                                 by path, so `ddd-patterns.md`
#                                                 shadows the skill of that name
#   5. local rule == plugin COMMAND             → clean: commands are addressed
#                                                 as /name, rules never by name
#   6. a name in neither                        → clean
#   7. no .claude/ at all                       → clean
#   8. a local artifact matching a DIFFERENT    → clean: a skill named after a
#      kind (skill vs command)                    command collides with nothing
#
# And two that are about judging vs failing to judge, which is the distinction
# the whole thing rests on:
#
#   9. no plugins installed / empty manifest    → exit 2, never 0. "Nothing
#                                                 installed" and "nothing
#                                                 shadowed" are different claims.
#  10. a manifest entry whose installPath is    → skipped with a note, not a
#      gone                                       crash: an unloadable plugin
#                                                 cannot be shadowed.
#
# README.md is excluded from every local surface, because `.claude/rules/README.md`
# is documentation about the directory and exists in real repos.
#
# SHADOW_PY selects the interpreter, matching how the other suites vary theirs.

set -u

SHADOW_PY=${SHADOW_PY:-python3}
ROOT=$( cd "$( dirname "$0" )/.." && pwd )
BIN="$ROOT/plugins/bett3r-ai-workflow/bin/check-skill-shadows"

[ -f "$BIN" ] || { printf 'test-skill-shadows: missing %s\n' "$BIN" >&2; exit 2; }

TMP=$( mktemp -d 2>/dev/null || mktemp -d -t shadow )
trap 'rm -rf "$TMP"' EXIT INT TERM

failed=0
passed=0

fail(){
  printf '\033[31m  ✗ %s\033[0m\n' "$1"
  [ -s "$TMP/out" ] && sed 's/^/      /' "$TMP/out"
  [ -s "$TMP/err" ] && sed 's/^/      /' "$TMP/err"
  failed=$(( failed + 1 ))
}
ok(){
  printf '\033[32m  ✓\033[0m %s\n' "$1"
  passed=$(( passed + 1 ))
}

# Build a plugin tree: mkplugin <dir> <name> <version> then artifacts.
mkplugin(){
  root="$1/$2/$3"
  mkdir -p "$root"
  printf '%s' "$root"
}
add_skill(){   mkdir -p "$1/skills/$2"; printf -- '---\nname: %s\n---\n' "$2" > "$1/skills/$2/SKILL.md"; }
add_command(){ mkdir -p "$1/commands";  printf -- '---\ndescription: x\n---\n' > "$1/commands/$2.md"; }
add_agent(){   mkdir -p "$1/agents";    printf -- '---\nname: %s\n---\n' "$2" > "$1/agents/$2.md"; }

# A manifest in the shape the real one has, pointing at those trees.
write_manifest(){
  cfg="$1"; shift
  mkdir -p "$cfg/plugins"
  {
    printf '{\n  "version": 2,\n  "plugins": {\n'
    first=1
    for spec in "$@"; do
      name=${spec%%=*}; path=${spec#*=}
      [ $first -eq 1 ] || printf ',\n'
      first=0
      printf '    "%s@test": [ { "scope": "user", "installPath": "%s", "version": "1.0.0" } ]' "$name" "$path"
    done
    printf '\n  }\n}\n'
  } > "$cfg/plugins/installed_plugins.json"
}

# Local host-repo artifacts.
add_local(){ # add_local <repo> <surface> <name>
  case "$2" in
    skills) mkdir -p "$1/.claude/skills/$3"; printf -- '---\nname: %s\n---\n' "$3" > "$1/.claude/skills/$3/SKILL.md" ;;
    *)      mkdir -p "$1/.claude/$2";        printf -- '---\nname: %s\n---\n' "$3" > "$1/.claude/$2/$3.md" ;;
  esac
}

run(){ # run <cfg> <repo>  -> exit status in $rc
  CLAUDE_CONFIG_DIR="$1" "$SHADOW_PY" "$BIN" "$2" >"$TMP/out" 2>"$TMP/err"
  rc=$?
}

assert(){ # assert <expected-rc> <label>
  if [ "$rc" -eq "$1" ]; then ok "$2"; else
    fail "$2 — expected exit $1, got $rc"
  fi
}

printf '\ntest-skill-shadows (%s)\n\n' "$SHADOW_PY"

# --- the shadowing shapes -------------------------------------------------
for case_spec in \
  "skills:skills:1:a local skill shadows a plugin skill" \
  "commands:commands:1:a local command shadows a plugin command" \
  "agents:agents:1:a local agent shadows a plugin agent" \
  "rules:skills:1:a local RULE shadows a plugin SKILL (path auto-load)" \
  "rules:commands:0:a local rule named after a plugin COMMAND is clean" \
  "skills:commands:0:a local skill named after a plugin COMMAND is clean" \
  "commands:skills:0:a local command named after a plugin SKILL is clean" \
  ; do
  local_surface=$( echo "$case_spec" | cut -d: -f1 )
  plugin_kind=$(   echo "$case_spec" | cut -d: -f2 )
  want=$(          echo "$case_spec" | cut -d: -f3 )
  label=$(         echo "$case_spec" | cut -d: -f4 )

  d="$TMP/c_${local_surface}_${plugin_kind}"
  p=$( mkplugin "$d/cache" alpha 1.0.0 )
  case "$plugin_kind" in
    skills)   add_skill   "$p" collide ;;
    commands) add_command "$p" collide ;;
    agents)   add_agent   "$p" collide ;;
  esac
  write_manifest "$d/cfg" "alpha=$p"
  mkdir -p "$d/repo"
  add_local "$d/repo" "$local_surface" collide
  run "$d/cfg" "$d/repo"
  assert "$want" "$label"
done

# --- a name in neither ----------------------------------------------------
d="$TMP/c_unrelated"; p=$( mkplugin "$d/cache" alpha 1.0.0 ); add_skill "$p" critique
write_manifest "$d/cfg" "alpha=$p"; mkdir -p "$d/repo"; add_local "$d/repo" skills e2e-instrument
run "$d/cfg" "$d/repo"; assert 0 "a repo-only skill with no plugin counterpart is clean"

# --- README.md is not an artifact -----------------------------------------
d="$TMP/c_readme"; p=$( mkplugin "$d/cache" alpha 1.0.0 ); add_skill "$p" README
write_manifest "$d/cfg" "alpha=$p"; mkdir -p "$d/repo/.claude/rules"
printf 'docs\n' > "$d/repo/.claude/rules/README.md"
run "$d/cfg" "$d/repo"; assert 0 ".claude/rules/README.md is documentation, never a shadow"

# --- no .claude/ ----------------------------------------------------------
d="$TMP/c_bare"; p=$( mkplugin "$d/cache" alpha 1.0.0 ); add_skill "$p" critique
write_manifest "$d/cfg" "alpha=$p"; mkdir -p "$d/repo"
run "$d/cfg" "$d/repo"; assert 0 "a repo with no .claude/ has nothing that can shadow"

# --- multiple shadows are all reported ------------------------------------
d="$TMP/c_many"; p=$( mkplugin "$d/cache" alpha 1.0.0 )
add_skill "$p" one; add_skill "$p" two; add_command "$p" three
write_manifest "$d/cfg" "alpha=$p"; mkdir -p "$d/repo"
add_local "$d/repo" skills one; add_local "$d/repo" skills two; add_local "$d/repo" commands three
run "$d/cfg" "$d/repo"
if [ "$rc" -eq 1 ] && [ "$( grep -c 'shadows alpha' "$TMP/out" )" -eq 3 ]; then
  ok "three shadows are all named, not just the first"
else
  fail "three shadows are all named, not just the first — rc=$rc, named $( grep -c 'shadows alpha' "$TMP/out" )"
fi

# --- judging vs failing to judge ------------------------------------------
# An empty plugin set must NOT read as a clean repo. This is the whole reason
# the exit codes are three-valued.
d="$TMP/c_empty"; mkdir -p "$d/cfg/plugins" "$d/repo"
printf '{ "version": 2, "plugins": {} }\n' > "$d/cfg/plugins/installed_plugins.json"
add_local "$d/repo" skills critique
run "$d/cfg" "$d/repo"; assert 2 "an empty plugin manifest exits 2 — it judged nothing, it is not clean"

d="$TMP/c_nomanifest"; mkdir -p "$d/cfg" "$d/repo"; add_local "$d/repo" skills critique
run "$d/cfg" "$d/repo"; assert 2 "a missing manifest exits 2, never 0"

# --- a manifest entry whose tree is gone ----------------------------------
d="$TMP/c_gone"; p=$( mkplugin "$d/cache" alpha 1.0.0 ); add_skill "$p" critique
q="$d/cache/ghost/1.0.0"
write_manifest "$d/cfg" "alpha=$p" "ghost=$q"
mkdir -p "$d/repo"; add_local "$d/repo" skills critique
run "$d/cfg" "$d/repo"
if [ "$rc" -eq 1 ] && grep -q 'installPath is missing' "$TMP/err"; then
  ok "a plugin whose installPath is gone is skipped with a note, and the rest still judged"
else
  fail "a plugin whose installPath is gone is skipped with a note — rc=$rc"
fi

# --- the detector's own positive control ----------------------------------
# The script self-checks over built-in specimens before judging. Prove that
# self-check is load-bearing by breaking the detector and requiring a refusal:
# a detector that reports clean after being broken is the exact failure this
# suite exists to catch, one level up.
d="$TMP/c_selfcheck"; p=$( mkplugin "$d/cache" alpha 1.0.0 ); add_skill "$p" critique
write_manifest "$d/cfg" "alpha=$p"; mkdir -p "$d/repo"; add_local "$d/repo" skills critique
sed 's/("skills", "dirs", ("skills",)),/("skills", "dirs", ()),/' "$BIN" > "$TMP/broken"
chmod +x "$TMP/broken"
CLAUDE_CONFIG_DIR="$d/cfg" "$SHADOW_PY" "$TMP/broken" "$d/repo" >"$TMP/out" 2>"$TMP/err"
rc=$?
if [ "$rc" -eq 2 ] && grep -q 'SELF-CHECK FAILED' "$TMP/err"; then
  ok "a detector edited into never matching fails loudly instead of reporting a clean repo"
else
  fail "a detector edited into never matching must exit 2 with SELF-CHECK FAILED — rc=$rc"
fi

printf '\n'
if [ "$failed" -gt 0 ]; then
  printf '\033[31m✗ %d failed\033[0m, %d passed\n\n' "$failed" "$passed"
  exit 1
fi
printf '\033[32m✓ %d passed\033[0m\n\n' "$passed"
