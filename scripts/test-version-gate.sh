#!/bin/sh
# Oracle for scripts/check-plugin-version-bump.sh — the release gate.
#
# The gate it drives is the only check in this repo that reads the *diff* rather
# than the source tree, because it guards the one failure the source tree cannot
# show: a plugin whose files changed while its `version` string did not never
# reaches a user at all. The cache the runtime loads from is keyed by that
# string, and the copy into it fires on nothing else — so a green PR with a
# perfect source tree is exactly what shipping stale code looks like. See the
# header of the gate itself for the whole chain.
#
# That makes the gate a strange artifact to keep honest: it only ever runs on
# somebody *else's* pull request, and a gate that has quietly stopped judging
# looks identical to a repo where nobody forgot. It cannot be tested against
# this checkout either — the interesting inputs are branches that do not exist
# here and must not. So every case below builds a throwaway git repo in a temp
# dir, commits a shape into it, and runs the real script over it, asserting the
# one thing CI acts on: the exit status.
#
# The six shapes are the six the gate has to tell apart:
#
#   1. a plugin file changed, no bump           → refuse
#   2. a plugin file changed, version bumped    → allow
#   3. nothing under plugins/ changed at all    → allow (the workflow, scripts/)
#   4. only plugins/<name>/README.md changed    → refuse: the README ships
#                                                 *inside* the payload
#   5. a plugin that does not exist on the base → allow: no prior version to
#                                                 differ from
#   6. two plugins touched, one bumped          → refuse, and *name* the other
#
# A seventh is asserted beyond that list: a plugin deleted outright has no
# manifest left to read, and a gate that treats "cannot read the version" as
# "not bumped" would make removing a plugin impossible.
#
# And an eighth, which is about the plumbing rather than the shape of the change:
# git C-quotes any path carrying a non-ASCII byte, so `plugins/alpha/skills/café.md`
# leaves `git diff --name-only` as `"plugins/alpha/skills/caf\303\251.md"` — a
# leading quote that defeats an anchor on `^plugins/`. A gate that maps paths back
# to plugin names sees nothing touched and exits 0 on a change that ships stale
# bytes. That failure wears the exact signature this whole gate exists to remove:
# quietly green, on a real change, with nothing said.
#
# Case 6 is the one that matters most in the room where it fails: whoever hits
# this is mid-PR and did not know the rule existed, so the report has to name the
# plugin and both version strings. A gate that only sets an exit code sends them
# to read this script, which is a worse day than the one it prevented.
#
# Run locally:  sh scripts/test-version-gate.sh
# Exit code is non-zero if anything is broken, so CI fails the PR.
#
# GATE_SH selects the interpreter the *gate* runs under. CI spawns it as
# `sh scripts/check-plugin-version-bump.sh`, and `sh` is dash on Debian/Ubuntu
# and bash-in-POSIX-mode on macOS. The suite is POSIX itself, so both halves are
# covered by running the pair together:
#     for s in sh dash bash; do GATE_SH=$s $s scripts/test-version-gate.sh; done

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
GATE="$ROOT/scripts/check-plugin-version-bump.sh"
GATE_SH=${GATE_SH:-sh}

TMP=$( mktemp -d "${TMPDIR:-/tmp}/esas-version-gate-test.XXXXXX" ) || exit 1
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

# ── Throwaway repos ───────────────────────────────────────────────────────────
#
# Every fixture is a real git repo with a real merge-base, because the property
# under test is a property of git history — a stubbed `git diff` would assert
# that this suite understands three-dot notation, which is not the thing that
# breaks.

# write_plugin <repo> <name> <version>
# The shape the runtime actually reads: a manifest under .claude-plugin, a README
# that ships with the payload, and one artifact deep enough to prove the gate
# maps an arbitrary path back to its plugin dir rather than matching a fixed one.
write_plugin(){
  mkdir -p "$1/plugins/$2/.claude-plugin" "$1/plugins/$2/skills/demo"
  printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "$2" "$3" \
    >"$1/plugins/$2/.claude-plugin/plugin.json"
  printf '# %s\n' "$2" >"$1/plugins/$2/README.md"
  printf -- '---\nname: demo\ndescription: a demo skill\n---\n\nBody.\n' \
    >"$1/plugins/$2/skills/demo/SKILL.md"
}

# set_version <repo> <name> <version> — a bump, written the way a human writes it.
set_version(){
  printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "$2" "$3" \
    >"$1/plugins/$2/.claude-plugin/plugin.json"
}

commit_all(){
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" commit -q -m "$2" >/dev/null 2>&1
}

# new_repo <name> — a repo on `master` carrying two plugins, with a `feature`
# branch checked out and nothing on it yet. The caller writes the case's change.
new_repo(){
  repo="$TMP/$1"
  rm -rf "$repo"
  mkdir -p "$repo"
  git -C "$repo" init -q >/dev/null 2>&1
  # Named outright while HEAD is still unborn: `init -b` is too new for some
  # runners and `init.defaultBranch` is whatever the machine happens to prefer,
  # so neither is allowed to decide what this suite's base branch is called.
  git -C "$repo" symbolic-ref HEAD refs/heads/master
  # CI has no global git identity, and a machine that signs every commit by
  # default would hang this suite on a passphrase prompt. Both are pinned in a
  # repo that lives for one case.
  git -C "$repo" config user.email 'gate@example.invalid'
  git -C "$repo" config user.name 'version gate oracle'
  git -C "$repo" config commit.gpgsign false

  write_plugin "$repo" alpha 1.0.0
  write_plugin "$repo" beta 2.0.0
  mkdir -p "$repo/.github/workflows" "$repo/scripts"
  printf 'name: validate-plugins\n' >"$repo/.github/workflows/validate-plugins.yml"
  printf '#!/bin/sh\ntrue\n' >"$repo/scripts/some-tool.sh"
  commit_all "$repo" 'base state'
  git -C "$repo" checkout -q -b feature
}

# The base is passed by name, as CI passes `origin/<base_ref>`. `master` here is
# a local branch for the same reason: what the gate must not do is guess.
run_gate(){
  ( cd "$1" && "$GATE_SH" "$GATE" master ) >"$TMP/out" 2>"$TMP/err"
  status=$?
}

# assert_gate <repo> <allow|refuse> <description> [needle ...]
# Needles are searched across stdout and stderr together: which stream carries
# the report is a formatting choice, and pinning it here would make a tidy-up
# look like a regression.
assert_gate(){
  gate_repo=$1
  gate_expect=$2
  gate_desc=$3
  shift 3

  run_gate "$gate_repo"
  gate_out=$( cat "$TMP/out" "$TMP/err" )

  if [ "$gate_expect" = allow ] && [ "$status" -ne 0 ]; then
    fail "$gate_desc" "expected exit 0, got $status — the gate blocked a PR it should pass" \
      'report:' "$gate_out"
    return
  fi
  if [ "$gate_expect" = refuse ] && [ "$status" -eq 0 ]; then
    fail "$gate_desc" 'expected a non-zero exit, got 0 — the gate let stale bytes through' \
      'report:' "$gate_out"
    return
  fi
  for needle in "$@"; do
    case $gate_out in
      *"$needle"*) ;;
      *)
        fail "$gate_desc" \
          "the report never says [$needle] — the fix has to be obvious without reading the gate" \
          'report:' "$gate_out"
        return ;;
    esac
  done
  pass "$gate_desc"
}

printf '\nthe release gate\n'

if [ ! -f "$GATE" ]; then
  fail 'the gate script exists' "no file at $GATE"
else
  pass 'the gate script exists'
fi

# ── The six shapes ────────────────────────────────────────────────────────────

# 1. The failure this whole gate exists for: real behaviour changed, and the
#    version string that decides whether anyone receives it did not.
new_repo unbumped
printf 'A changed body.\n' >>"$repo/plugins/alpha/skills/demo/SKILL.md"
commit_all "$repo" 'change a skill, forget the bump'
assert_gate "$repo" refuse \
  'a plugin file changed with no version bump is refused, naming the plugin and the version' \
  'plugins/alpha' '1.0.0'

# 2. The same change, shipped. Nothing else about the PR differs — which is the
#    point: the bump is the entire release contract.
new_repo bumped
printf 'A changed body.\n' >>"$repo/plugins/alpha/skills/demo/SKILL.md"
set_version "$repo" alpha 1.1.0
commit_all "$repo" 'change a skill, bump the plugin'
#    The needle is not decoration: `No plugin payloads changed` also exits 0, so a
#    fixture that quietly stopped producing a diff would pass this case while
#    asserting the opposite of its own name. Every allow-case below names the
#    verdict it expects for the same reason.
assert_gate "$repo" allow \
  'the same change with the version bumped is allowed' \
  'plugins/alpha: 1.0.0 → 1.1.0'

# 3. Everything outside plugins/ — this workflow, scripts/, docs/. None of it is
#    in the payload the cache copies, so none of it can go stale there. A gate
#    that demanded a bump here would tax every unrelated PR and be turned off.
new_repo workflow-only
printf '\n# a new comment\n' >>"$repo/.github/workflows/validate-plugins.yml"
commit_all "$repo" 'edit the workflow'
assert_gate "$repo" allow \
  'a change outside plugins/ needs no bump at all'

# 4. The README is the case that reads like an exception and is not one: it sits
#    inside plugins/<name>/, so it is copied into the cache with everything else
#    and a stale one is a user reading last release's instructions. "It's only
#    docs" is the sentence that adds the first hole to a rule like this.
new_repo readme-only
printf '\nA new section.\n' >>"$repo/plugins/alpha/README.md"
commit_all "$repo" 'edit only the plugin README'
assert_gate "$repo" refuse \
  'plugins/<name>/README.md counts as a touch — it ships inside the payload' \
  'plugins/alpha'

# 5. A plugin that does not exist on the base has no previous version for the new
#    one to differ from, so there is nothing to compare and nothing stale to
#    receive. Refusing here would make adding a plugin impossible.
new_repo brand-new
write_plugin "$repo" gamma 0.1.0
commit_all "$repo" 'add a brand-new plugin'
assert_gate "$repo" allow \
  'a brand-new plugin absent from the base is allowed — there is no prior version' \
  'plugins/gamma: new since master'

# 6. The one that decides whether the report is worth reading. Bumping the plugin
#    you happened to think of is the normal way this rule is half-kept, and an
#    exit code alone tells the author only that *something* is wrong on a PR that
#    already contains a bump.
new_repo one-of-two
printf 'A changed body.\n' >>"$repo/plugins/alpha/skills/demo/SKILL.md"
printf 'A changed body.\n' >>"$repo/plugins/beta/skills/demo/SKILL.md"
set_version "$repo" beta 2.1.0
commit_all "$repo" 'touch both plugins, bump one'
assert_gate "$repo" refuse \
  'two plugins touched and one bumped is refused, and the report names the unbumped one' \
  'plugins/alpha' '1.0.0'

# 7. Deleting a plugin touches every path under it and leaves no manifest to read
#    at HEAD. A gate that read "no version here" as "not bumped" would make
#    removing a plugin from the marketplace impossible — the one shape where
#    nobody can receive stale bytes, because nobody receives anything.
new_repo deleted
rm -rf "$repo/plugins/beta"
commit_all "$repo" 'remove a plugin outright'
assert_gate "$repo" allow \
  'a deleted plugin is allowed — there is no manifest left to bump' \
  'plugins/beta: removed at HEAD'

# 8. Case 1 again, wearing a filename git will not print plainly. `core.quotePath`
#    defaults to true, so one non-ASCII byte anywhere in a path makes git emit the
#    whole thing C-quoted and wrapped in double quotes, and the leading quote walks
#    straight past an anchor on `^plugins/`. The gate then reports that no plugin
#    payload changed and exits 0 — on a diff that ships stale bytes to every user.
#    Nothing about that outcome looks wrong in a CI log, which is why it is asserted
#    here rather than left to the day somebody names a skill in their own language.
new_repo accented-path
printf 'A skill body.\n' >"$repo/plugins/alpha/skills/café.md"
commit_all "$repo" 'add a skill whose filename is not ASCII'
assert_gate "$repo" refuse \
  'a plugin file whose name is not ASCII still counts as a touch — git C-quotes it' \
  'plugins/alpha' '1.0.0'

# ── The base ref is never guessed ─────────────────────────────────────────────
#
# The failure that is invisible on a laptop: a depth-1 checkout has no base ref,
# so `git diff <base>...HEAD` has nothing to resolve. Erring towards silence
# there would make the gate pass every PR on a runner missing `fetch-depth: 0` —
# green, permanently, for the entire reason it was written.

printf '\nan unresolvable base\n'

new_repo no-base
printf 'A changed body.\n' >>"$repo/plugins/alpha/skills/demo/SKILL.md"
commit_all "$repo" 'change a skill, forget the bump'
( cd "$repo" && "$GATE_SH" "$GATE" origin/does-not-exist ) >"$TMP/out" 2>"$TMP/err"
status=$?
gate_out=$( cat "$TMP/out" "$TMP/err" )
if [ "$status" -eq 0 ]; then
  fail 'a base ref that does not resolve fails loudly, never silently passes' \
    'exit 0 — a shallow checkout would disable the gate and nothing would say so' \
    'report:' "$gate_out"
else
  case $gate_out in
    *does-not-exist*) pass 'a base ref that does not resolve fails loudly, naming the ref' ;;
    *) fail 'a base ref that does not resolve names the ref it could not find' \
         'report:' "$gate_out" ;;
  esac
fi

printf '\n'
if [ "$failed" -gt 0 ]; then
  printf '\033[31m✗ %d failed\033[0m, %d passed\n\n' "$failed" "$passed"
  exit 1
fi
printf '\033[32m✓ %d passed\033[0m\n\n' "$passed"
