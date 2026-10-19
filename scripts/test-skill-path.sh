#!/bin/sh
# Oracle for plugins/bett3r-ai-workflow/bin/skill-path (BP-196 D2).
#
# `skill-path <plugin>:<skill>` names the SKILL.md a session would load for that
# skill, read from installed_plugins.json, so a worker without the Skill tool can
# open it by file. The failure it exists to stop is a quiet one: the plugin
# cache keeps every version it ever installed (0.15.0, 0.16.0 and 0.17.0 of one
# plugin, each with a different scaffold-from-design), and only the manifest
# says which one is live. A resolver that globbed the cache, or took the newest
# directory, would hand the executor a stale skill and nothing would go red.
#
# Every case runs the real bin/skill-path over the fixture tree in
# scripts/fixtures/skill-path/, copied to a temp dir with its `@FIXTURE@`
# placeholder rewritten to that copy's absolute path, and asserts on the fields
# of the last stdout line (`SKILL-PATH:v1 outcome=... reason=... file=...`),
# never on the exit code alone.
#
# The fixture owns everything ambient the script reads: HOME points at the
# fixture's home/ for every run (so `~/.claude` is the fixture's, never the
# machine's), and CLAUDE_CONFIG_DIR is set per case or scrubbed. No case can
# read the real ~/.claude, whatever plugins the machine running it has.
# GIT_CEILING_DIRECTORIES stops git's repository search at the temp dir, so a
# TMPDIR that sits inside some checkout cannot make the plain-directory
# fixtures one repository; the worktree cases build their own repos below it.
#
# Run locally:  sh scripts/test-skill-path.sh   (also under dash and bash)

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
BIN="$ROOT/plugins/bett3r-ai-workflow/bin/skill-path"
FIXTURE="$ROOT/scripts/fixtures/skill-path"

TMP=$( mktemp -d "${TMPDIR:-/tmp}/skill-path-test.XXXXXX" ) || exit 1
TMP=$( CDPATH= cd -P -- "$TMP" && pwd )
trap 'rm -rf "$TMP"' EXIT INT TERM

# Every variable that names a repository location for git, unset for the whole
# suite (and again inside git_fixture), so a caller's GIT_DIR reaches nothing.
GIT_LOCATION_VARS="GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_PREFIX GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT"
unset $GIT_LOCATION_VARS

failed=0
passed=0
ok(){ passed=$(( passed + 1 )); printf '  ok   %s\n' "$1"; }
fail(){
  failed=$(( failed + 1 ))
  printf '  FAIL %s\n' "$1"
  [ -s "$TMP/out" ] && sed 's/^/         out: /' "$TMP/out"
  [ -s "$TMP/err" ] && sed 's/^/         err: /' "$TMP/err"
}

[ -f "$BIN" ] || { printf 'test-skill-path: missing %s\n' "$BIN" >&2; exit 2; }
[ -x "$BIN" ] || { printf 'test-skill-path: %s is not executable\n' "$BIN" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf 'test-skill-path: python3 not on PATH\n' >&2; exit 2; }

# The fixture copy, with every manifest's placeholder rewritten.
FX="$TMP/fx"
cp -R "$FIXTURE" "$FX"
for m in $( find "$FX" -name installed_plugins.json ); do
  sed "s#@FIXTURE@#$FX#g" "$m" > "$m.tmp" && mv "$m.tmp" "$m"
done
PV3="$FX/cache/bett3r-ai-workflow/bett3r-pv3-ai-skills"
SFD=skills/scaffold-from-design/SKILL.md

# run <config-dir|-> <args...>: config "-" leaves CLAUDE_CONFIG_DIR unset.
# HOME is always the fixture's home, so the default config dir is never the
# real ~/.claude.
run(){
  cfg=$1; shift
  if [ "$cfg" = - ]; then
    env -u CLAUDE_CONFIG_DIR HOME="$FX/home" GIT_CEILING_DIRECTORIES="$TMP" "$BIN" "$@" >"$TMP/out" 2>"$TMP/err"
  else
    env HOME="$FX/home" GIT_CEILING_DIRECTORIES="$TMP" CLAUDE_CONFIG_DIR="$cfg" "$BIN" "$@" >"$TMP/out" 2>"$TMP/err"
  fi
  rc=$?
}

# field <key>: the value of <key>= on the last stdout line, empty if absent.
field(){
  tail -n 1 "$TMP/out" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -n 1
}

# expect <key> <expected> <label>: asserts the field and prints both on failure.
expect(){
  got=$( field "$1" )
  if [ "$got" = "$2" ]; then ok "$3"; else
    fail "$3 -- $1: expected '$2', got '$got'"
  fi
}

# expect_verdict: the last line carries the versioned verdict token.
expect_verdict(){
  if tail -n 1 "$TMP/out" | grep -q '^SKILL-PATH:v1 outcome='; then ok "$1"; else
    fail "$1 -- last stdout line is not a SKILL-PATH:v1 verdict"
  fi
}

printf '\ntest-skill-path\n\n'

# --- the manifest names the live version, not the cache --------------------
run "$FX/config/live" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect_verdict "the last stdout line is a SKILL-PATH:v1 verdict"
expect outcome ok "manifest names 0.17.0 while stale 0.15.0 sits in the cache: outcome=ok"
expect file "$PV3/0.17.0/$SFD" "manifest names 0.17.0 while stale 0.15.0 sits in the cache: file is 0.17.0's"
expect version 0.17.0 "manifest names 0.17.0: version=0.17.0"
expect root "$PV3/0.17.0" "manifest names 0.17.0: root is that installPath"
[ "$rc" -eq 0 ] && ok "outcome=ok exits 0" || fail "outcome=ok exits 0 -- got exit $rc"

# Neither the oldest nor the newest cache directory: the one the manifest names.
run "$FX/config/pinned" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.16.0/$SFD" "manifest names 0.16.0 between cached 0.15.0 and 0.17.0: file is 0.16.0's"

# --- not installed ---------------------------------------------------------
# ddd sits in the cache but in no manifest: not installed, whatever the cache holds.
run "$FX/config/live" --repo "$FX/repo" ddd:scaffold-from-design
expect outcome error "a plugin absent from the manifest: outcome=error"
expect reason not-installed "a plugin absent from the manifest: reason=not-installed"
expect plugin ddd "a plugin absent from the manifest: the line names ddd"
[ "$rc" -eq 2 ] && ok "outcome=error exits 2" || fail "outcome=error exits 2 -- got exit $rc"

# --- no such skill ---------------------------------------------------------
run "$FX/config/live" --repo "$FX/repo" bett3r-pv3-ai-skills:create-aggregate
expect reason no-such-skill "a skill directory without SKILL.md: reason=no-such-skill"
run "$FX/config/live" --repo "$FX/repo" bett3r-pv3-ai-skills:create-nothing
expect reason no-such-skill "a skill the live version does not have: reason=no-such-skill"

# --- precedence and ambiguity ----------------------------------------------
run "$FX/config/project" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.17.0/$SFD" "a project-scope entry for this repo beats the user-scope one"
run "$FX/config/project-elsewhere" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.15.0/$SFD" "a project-scope entry for another repo does not apply: the user entry wins"
run "$FX/config/ambiguous" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect outcome error "two marketplaces install one plugin name: outcome=error"
expect reason ambiguous "two marketplaces install one plugin name: reason=ambiguous"
expect candidates "bett3r-pv3-ai-skills@bett3r-ai-workflow,bett3r-pv3-ai-skills@other-market" "ambiguous names both manifest keys"

# --- managed and local scopes ----------------------------------------------
# managed is user-level, local is project-level; most specific wins:
# local over project over user/managed.
run "$FX/config/local" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.17.0/$SFD" "a local-scope entry for this repo beats the project and user ones"
run "$FX/config/local-elsewhere" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.15.0/$SFD" "a local-scope entry for another repo does not apply: the user entry wins"
run "$FX/config/managed" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.16.0/$SFD" "a managed-scope entry alone applies everywhere"
run "$FX/config/managed-project" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.17.0/$SFD" "a project-scope entry for this repo beats the managed one"
run "$FX/config/managed-user" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect reason ambiguous "managed and user entries for one plugin share a level: reason=ambiguous"

# --- a project entry without a projectPath ---------------------------------
# No projectPath (or an empty one) names no repo, so it never applies, not
# even to the working directory.
( cd "$FX/repo" && env HOME="$FX/home" GIT_CEILING_DIRECTORIES="$TMP" CLAUDE_CONFIG_DIR="$FX/config/project-no-path" "$BIN" bett3r-pv3-ai-skills:scaffold-from-design >"$TMP/out" 2>"$TMP/err" )
expect file "$PV3/0.15.0/$SFD" "a local entry with an empty projectPath does not apply to the working directory"
( cd "$FX/repo" && env HOME="$FX/home" GIT_CEILING_DIRECTORIES="$TMP" CLAUDE_CONFIG_DIR="$FX/config/project-missing-path" "$BIN" bett3r-pv3-ai-skills:scaffold-from-design >"$TMP/out" 2>"$TMP/err" )
expect file "$PV3/0.15.0/$SFD" "a project entry with no projectPath does not apply to the working directory"

# --- worktrees and subdirectories of the project ----------------------------
# A project entry applies wherever the repo's root is the entry's, the rule
# Claude Code keys project entries by: the folder holding `.git`, except that
# a linked worktree (a `.git` file whose gitdir sits in <common>/worktrees/ and
# points back at it) maps to its main checkout. So the main checkout, a
# subdirectory of it and a linked worktree match; a submodule or a repo with a
# separate git dir keeps its own folder, though their git dirs sit side by side.
# Built with git here, config scrubbed so no global hook or signing applies.
#
# git_fixture: every git call runs in this subshell with each GIT_* variable
# that names a repository location unset, so a GIT_DIR exported by whoever runs
# the suite (a hook does) cannot turn these commits into commits in that repo.
G="$TMP/git"
git_fixture(){
  (
    unset $GIT_LOCATION_VARS
    export HOME="$FX/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CEILING_DIRECTORIES="$TMP"
    c="git -c user.name=t -c user.email=t@t -c protocol.file.allow=always"
    mkdir -p "$G/main/sub" "$G/other" "$G/cfg/plugins" "$G/lib" "$G/super" "$G/fake" "$G/gitdirs" &&
    cd "$G/main" && git init -q && $c commit -q --allow-empty -m init &&
      git worktree add -q "$G/wt" 2>/dev/null &&
      cd "$G/other" && git init -q &&
      cd "$G/lib" && git init -q && $c commit -q --allow-empty -m init &&
      cd "$G/super" && git init -q &&
      $c submodule add -q "$G/lib" a 2>/dev/null && $c submodule add -q "$G/lib" b 2>/dev/null &&
      git init -q --separate-git-dir "$G/gitdirs/sx" "$G/sx" &&
      git init -q --separate-git-dir "$G/gitdirs/sy" "$G/sy" &&
      cp "$G/wt/.git" "$G/fake/.git" &&
      $c clone -q --bare "$G/lib" "$G/bare.git" && git -C "$G/bare.git" worktree add -q "$G/bwt" 2>/dev/null &&
      $c clone -q --bare "$G/lib" "$G/odd" && git -C "$G/odd" worktree add -q "$G/owt" 2>/dev/null &&
      mkdir "$G/odd/.git" &&
      mkdir "$G/moved" && cp -R "$G/main/.git/worktrees/wt" "$G/gitdirs/moved" &&
      printf 'gitdir: %s\n' "$G/gitdirs/moved" > "$G/moved/.git" &&
      printf '%s\n' "$G/moved/.git" > "$G/gitdirs/moved/gitdir" &&
      printf '%s\n' "$G/main/.git" > "$G/gitdirs/moved/commondir"
  )
}
# The suite runs git_fixture with GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE
# pointing at a throwaway repo, and asserts that repo gained no commit.
CALLER="$TMP/caller"
mkdir -p "$CALLER"
caller_commits(){
  ( unset $GIT_LOCATION_VARS; git -C "$CALLER" rev-list --count HEAD 2>/dev/null )
}
( unset $GIT_LOCATION_VARS; export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CEILING_DIRECTORIES="$TMP"
  cd "$CALLER" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m caller ) ||
  fail "caller fixture: git setup failed"
before=$( caller_commits )
( export GIT_DIR="$CALLER/.git" GIT_WORK_TREE="$CALLER" GIT_INDEX_FILE="$CALLER/.git/index"; git_fixture ) ||
  fail "worktree fixture: git setup failed"
after=$( caller_commits )
if [ "$before" = 1 ] && [ "$after" = 1 ]; then
  ok "an exported GIT_DIR does not receive the fixture's commits"
else
  fail "an exported GIT_DIR does not receive the fixture's commits -- caller commits: expected '1' then '1', got '$before' then '$after'"
fi

# cfg_project <dir> <projectPath>: a manifest with a user entry (0.15.0) and a
# project entry for <projectPath> (0.17.0).
cfg_project(){
  mkdir -p "$1/plugins"
  cat > "$1/plugins/installed_plugins.json" <<JSON
{ "version": 2, "plugins": { "bett3r-pv3-ai-skills@bett3r-ai-workflow": [
  { "scope": "user", "installPath": "$PV3/0.15.0", "version": "0.15.0" },
  { "scope": "project", "projectPath": "$2", "installPath": "$PV3/0.17.0", "version": "0.17.0" }
] } }
JSON
}
cfg_project "$G/cfg" "$G/main"
run "$G/cfg" --repo "$G/main" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.17.0/$SFD" "a project entry applies in its own checkout"
run "$G/cfg" --repo "$G/wt" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.17.0/$SFD" "a project entry applies in a linked worktree of its repo"
run "$G/cfg" --repo "$G/main/sub" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.17.0/$SFD" "a project entry applies in a subdirectory of its repo"
run "$G/cfg" --repo "$G/other" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.15.0/$SFD" "a project entry does not apply in an unrelated git repo: the user entry wins"
# A .git file naming the worktree's gitdir, whose back-pointer names $G/wt, not
# this folder: not a linked worktree of main, so its root is its own folder.
run "$G/cfg" --repo "$G/fake" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.15.0/$SFD" "a .git file the worktree's back-pointer does not name is not that worktree: the user entry wins"
# A gitdir that names main's common dir and points back, but sits outside
# main/.git/worktrees/: not a linked worktree, so its root is its own folder.
run "$G/cfg" --repo "$G/moved" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.15.0/$SFD" "a gitdir outside <common>/worktrees/ is not a linked worktree: the user entry wins"
# A GIT_DIR inherited from a hook names another repo; the root is still --repo's.
( env HOME="$FX/home" GIT_CEILING_DIRECTORIES="$TMP" GIT_DIR="$G/other/.git" CLAUDE_CONFIG_DIR="$G/cfg" "$BIN" --repo "$G/wt" bett3r-pv3-ai-skills:scaffold-from-design >"$TMP/out" 2>"$TMP/err" )
expect file "$PV3/0.17.0/$SFD" "an inherited GIT_DIR does not decide the repo's root"

# Submodules a and b of one superproject: git dirs super/.git/modules/a and /b.
cfg_project "$G/cfg-sub" "$G/super/a"
run "$G/cfg-sub" --repo "$G/super/a" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.17.0/$SFD" "a project entry for a submodule applies in that submodule"
run "$G/cfg-sub" --repo "$G/super/b" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.15.0/$SFD" "a project entry for one submodule does not apply in its sibling: the user entry wins"
run "$G/cfg-sub" --repo "$G/super" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.15.0/$SFD" "a project entry for a submodule does not apply in its superproject: the user entry wins"
# Repos made with --separate-git-dir whose git dirs share one parent folder.
cfg_project "$G/cfg-sep" "$G/sx"
run "$G/cfg-sep" --repo "$G/sx" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.17.0/$SFD" "a project entry for a separate-git-dir repo applies in that repo"
run "$G/cfg-sep" --repo "$G/sy" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.15.0/$SFD" "a project entry for one separate-git-dir repo does not apply in another beside it: the user entry wins"
# A linked worktree of a bare repo maps to the bare repo's folder, unless that
# folder holds a .git of its own.
cfg_project "$G/cfg-bare" "$G/bare.git"
run "$G/cfg-bare" --repo "$G/bwt" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.17.0/$SFD" "a project entry for a bare repo applies in a linked worktree of it"
cfg_project "$G/cfg-odd" "$G/odd"
run "$G/cfg-odd" --repo "$G/owt" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.15.0/$SFD" "a bare repo folder holding a .git of its own is not its worktree's root: the user entry wins"

# --- no manifest -----------------------------------------------------------
run "$FX/config/no-manifest" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect reason no-manifest "a config dir without installed_plugins.json: reason=no-manifest"
expect manifest "$FX/config/no-manifest/plugins/installed_plugins.json" "no-manifest names the path it looked at"
run "$FX/config/garbled" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect reason no-manifest "an installed_plugins.json that is not JSON: reason=no-manifest"
run "$FX/config/wrong-shape" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect reason no-manifest "an installed_plugins.json whose plugins is not an object: reason=no-manifest"

# --- malformed entries --------------------------------------------------------
# A manifest whose entries are the wrong shape is no manifest, with the verdict
# still the last line: never a traceback.
for c in bad-entry-string bad-entries-dict bad-install-path bad-project-path bad-other-entry; do
  run "$FX/config/$c" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
  expect_verdict "$c: the last stdout line is a SKILL-PATH:v1 verdict"
  expect reason no-manifest "$c: reason=no-manifest"
  [ "$rc" -eq 2 ] && ok "$c: exits 2" || fail "$c: exits 2 -- got exit $rc"
done
run "$FX/config/bad-other-entry" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect entry "unrelated@somewhere" "a malformed manifest names the entry it rejected"

# --- manifest entries missing a field ----------------------------------------
# An entry with no installPath must not resolve relative to the working
# directory, which here holds a matching skills/ tree.
( cd "$PV3/0.17.0" && env HOME="$FX/home" CLAUDE_CONFIG_DIR="$FX/config/no-install-path" "$BIN" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design >"$TMP/out" 2>"$TMP/err" )
expect reason no-such-skill "an entry with no installPath: reason=no-such-skill, never a path under the working directory"
run "$FX/config/no-version" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect version unknown "an entry with no version: version=unknown"
# null is absent, not malformed: the manifest still resolves.
( cd "$FX/repo" && env HOME="$FX/home" GIT_CEILING_DIRECTORIES="$TMP" CLAUDE_CONFIG_DIR="$FX/config/null-fields" "$BIN" bett3r-pv3-ai-skills:scaffold-from-design >"$TMP/out" 2>"$TMP/err" )
expect file "$PV3/0.17.0/$SFD" "null fields are absent fields: a null projectPath never applies, the user entry resolves"
expect version unknown "an entry with a null version: version=unknown"

# --- bare names ------------------------------------------------------------
run "$FX/config/live" --repo "$FX/repo" both
expect file "$FX/repo/.claude/skills/both/SKILL.md" "a bare name in both places resolves to the repo's .claude/skills first"
expect root "$FX/repo/.claude" "a bare repo skill: root is the repo's .claude"
expect version none "a bare skill: version=none"
run "$FX/config/live" --repo "$FX/repo" user-only
expect file "$FX/config/live/skills/user-only/SKILL.md" "a bare name only at user level resolves to \$CLAUDE_CONFIG_DIR/skills"
run "$FX/config/live" --repo "$FX/repo" nowhere
expect reason no-such-skill "a bare name in neither place: reason=no-such-skill"
# Without --repo the repo is the working directory.
( cd "$FX/repo" && env HOME="$FX/home" CLAUDE_CONFIG_DIR="$FX/config/live" "$BIN" repo-only >"$TMP/out" 2>"$TMP/err" )
expect file "$FX/repo/.claude/skills/repo-only/SKILL.md" "without --repo, the working directory is the repo"

# --- CLAUDE_CONFIG_DIR honoured --------------------------------------------
# home/.claude names 0.15.0, config/live names 0.17.0.
run - --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.15.0/$SFD" "CLAUDE_CONFIG_DIR unset: the manifest under \$HOME/.claude is read"
run "$FX/config/live" --repo "$FX/repo" bett3r-pv3-ai-skills:scaffold-from-design
expect file "$PV3/0.17.0/$SFD" "CLAUDE_CONFIG_DIR set: its manifest is read, not \$HOME/.claude's"

# --- bad names -------------------------------------------------------------
for bad in "" "a:b:c" ":skill" "plugin:" "../skill" "plugin:../x" "a b"; do
  run "$FX/config/live" --repo "$FX/repo" "$bad"
  expect reason bad-name "a malformed argument '$bad': reason=bad-name"
done
run "$FX/config/live" --repo "$FX/repo"
expect reason bad-name "no argument at all: reason=bad-name"
expect name none "no argument at all: name=none"
run "$FX/config/live" --repo "$FX/repo" "a b"
expect name a_b "a name with a space is printed with _ so the line stays one token per field"

printf '\n'
if [ "$failed" -gt 0 ]; then
  printf '%d failed, %d passed\n\n' "$failed" "$passed"
  exit 1
fi
printf '%d passed\n\n' "$passed"
