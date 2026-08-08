#!/bin/sh
# The release gate: a plugin whose files changed must ship under a new version.
#
# Nothing here is about semver hygiene. A plugin reaches a user through
#
#     source tree → marketplace checkout (a git pull) → version-keyed cache copy
#                 → the session that loads it
#
# and the copy into that cache fires on exactly one condition: the `version`
# string in `plugins/<name>/.claude-plugin/plugin.json` differs from the one the
# cache directory is already keyed by. Same string, no copy. The pull still
# lands, the checkout is still correct, and every session goes on loading the
# bytes it already had.
#
# That is how two behaviour-changing commits once shipped under an unchanged
# version and users ran stale code for two releases — with every CI gate green,
# and green *correctly*: every other check in this repo reads the source tree,
# and the source tree was never the thing that was wrong. The defect existed only
# in the relationship between a diff and a version string, which is a thing no
# file contains. So this gate reads the diff.
#
# Two consequences worth stating, because both look like edge cases and neither
# is:
#
#   * `plugins/<name>/README.md` counts. It is inside the plugin directory, so it
#     is inside the payload the cache copies, so a stale one is a user reading
#     last release's instructions. Everything *outside* `plugins/**` — this
#     script, the workflow, `scripts/`, `docs/` — is never copied anywhere and
#     needs no bump.
#   * The comparison is against the **merge base**, not the previous commit.
#     `HEAD~1` is wrong and must stay wrong here: a squash-merged or rebased
#     branch has a HEAD~1 that belongs to somebody else's work, so the gate would
#     read a version that was already bumped by an unrelated PR and pass. Three
#     dots — `git diff <base>...HEAD` — is the whole of the fix, and re-spelling
#     it as `HEAD~1` is the single most likely way this gate is quietly disabled.
#
# It fails loudly rather than quietly whenever it cannot judge (no base ref, no
# jq, an unreadable manifest), because the shape of every failure this guards
# against is a check that stayed green while meaning nothing.
#
# The verdict — every ✓ and every ✗ — goes to stdout as one ordered stream, and
# only the "cannot judge at all" errors go to stderr. Splitting the verdict
# across both would reorder it in a CI log, where stdout is block-buffered into a
# pipe and stderr is not: the refusal would print above the ✓ lines it belongs
# under, which is how a report stops being read.
#
# Run locally:  sh scripts/check-plugin-version-bump.sh [base-ref]
# Exit code is non-zero if a touched plugin was not bumped, so CI fails the PR.
# Oracle: scripts/test-version-gate.sh.

# CI passes `origin/<github.base_ref>`; the default is what a developer wants
# when checking their own branch before pushing it.
base=${1:-origin/master}

# Every path below is repo-relative — CI runs this from the checkout root, a
# human runs it from wherever they are standing.
root=$( git rev-parse --show-toplevel 2>/dev/null )
if [ -z "$root" ]; then
  printf 'check-plugin-version-bump: not inside a git checkout — nothing to judge.\n' >&2
  exit 1
fi
CDPATH= cd -- "$root" || exit 1

if ! command -v jq >/dev/null 2>&1; then
  printf 'check-plugin-version-bump: jq is required to read plugin manifests.\n' >&2
  exit 1
fi

# The failure that cannot be reproduced on a laptop, where every ref is already
# on disk: `actions/checkout` clones at depth 1 by default, and a depth-1 clone
# has no base branch to diff against. Erring towards silence here would leave the
# gate green on every PR for exactly the reason it was written, so it says which
# ref it could not find and what to do about it.
if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1; then
  printf 'check-plugin-version-bump: cannot resolve the base ref `%s`.\n' "$base" >&2
  printf '  In CI this means the checkout is shallow — actions/checkout needs `fetch-depth: 0`.\n' >&2
  # Spelled out rather than `$0`: this runs after the cd to the repo root, where
  # the relative path the caller typed no longer points at this file.
  printf '  Locally, `git fetch origin` first, or name a base ref:\n' >&2
  printf '    sh scripts/check-plugin-version-bump.sh <ref>\n' >&2
  exit 1
fi

# Three dots: the diff against the merge base, i.e. what this branch changed,
# not what happened on master meanwhile. See the header — HEAD~1 is the
# regression to watch for.
#
# `--no-renames` because a file moved *out* of a plugin is a change to that
# plugin, and rename detection reports only the destination path — which would
# hide the move under `docs/` and let the plugin ship a file it no longer has.
#
# `core.quotePath=false` because it defaults to *true*: one non-ASCII byte
# anywhere in a path and git prints the whole thing C-quoted and wrapped in
# double quotes — `"plugins/alpha/skills/caf\303\251.md"` — so the leading quote
# walks straight past the `^plugins/` anchor below, the plugin never lands in
# `touched`, and the gate reports that nothing changed and exits 0. Removing this
# looks like removing noise and is the shortest way back to a gate that is
# quietly green on somebody's café.md. Oracle case 8 holds it in place.
changed=$( git -c core.quotePath=false diff --no-renames --name-only "$base"...HEAD ) || exit 1

touched=$( printf '%s\n' "$changed" | sed -n 's|^plugins/\([^/]*\)/.*$|\1|p' | sort -u )

if [ -z "$touched" ]; then
  printf 'No plugin payloads changed against %s — no version bump required.\n' "$base"
  exit 0
fi

status=0

# Newline-only, so a plugin directory with a space in its name is one plugin and
# not two. This script owns its shell, so IFS is not restored.
IFS='
'
for name in $touched; do
  manifest="plugins/$name/.claude-plugin/plugin.json"

  # Deleting a plugin touches every path under it and leaves no manifest behind.
  # Nobody can receive stale bytes from a plugin nobody receives at all.
  if [ ! -f "$manifest" ]; then
    printf '  plugins/%s: removed at HEAD — nothing to bump.\n' "$name"
    continue
  fi

  head_version=$( jq -r '.version // empty' "$manifest" 2>/dev/null )
  if [ -z "$head_version" ]; then
    printf '\033[31m✗\033[0m plugins/%s: no readable `version` in %s\n' "$name" "$manifest"
    printf '    The cache directory is keyed by that string. Without it nothing ships.\n'
    status=1
    continue
  fi

  # Present at HEAD, absent on the base: a brand-new plugin. There is no previous
  # version for this one to differ from, and no cached copy to go stale.
  if ! git cat-file -e "$base:$manifest" 2>/dev/null; then
    printf '  plugins/%s: new since %s (version %s) — no previous version to bump from.\n' \
      "$name" "$base" "$head_version"
    continue
  fi

  # Both halves of the pipe are silenced, not just the first. `2>/dev/null` on
  # `git show` alone leaves `jq` free to print a parse error to stderr when the
  # manifest is malformed *on the base branch* — a verdict that is still correct
  # on stdout, arriving next to noise that reads like the gate itself broke.
  base_version=$( git show "$base:$manifest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null )

  if [ "$head_version" = "$base_version" ]; then
    # Both values, spelled out and stacked, because whoever reads this is mid-PR
    # and has probably never heard of the rule: the answer has to be in the
    # message, and two identical strings under each other *are* the answer.
    base_label=$( printf 'on %s:' "$base" )
    printf '\033[31m✗\033[0m plugins/%s changed, but its version did not.\n' "$name"
    printf '    %s\n' "$manifest"
    printf '      %-24s %s\n' "$base_label" "$base_version"
    printf '      %-24s %s\n' 'at HEAD:' "$head_version"
    status=1
  else
    # `:-` because a manifest that was unreadable on the base leaves the left side
    # blank, and `✓ plugins/x:  → 1.0.0` reads like a bug in the gate rather than
    # the correct verdict it is.
    printf '\033[32m✓\033[0m plugins/%s: %s → %s\n' \
      "$name" "${base_version:-(no version on $base)}" "$head_version"
  fi
done

if [ "$status" -ne 0 ]; then
  printf '\n'
  printf 'A plugin is copied into the version-keyed cache only when its `version` changes.\n'
  printf 'Unbumped, the change lands in the repo and reaches nobody. Bump the plugin(s)\n'
  # `marketplace.json` is named here as convention and explicitly *not* as a pin:
  # its `plugins[]` entries carry name/source/description and no version at all,
  # and the marketplace checkout refreshes by `git pull` regardless of
  # `metadata.version`. This text is what someone reads at the exact moment they
  # are failing this gate, so calling it a pin is how the next person bumps that
  # field alone and cannot work out why nothing moved.
  printf 'named above and push again. Bumping `.claude-plugin/marketplace.json` alongside\n'
  printf 'is repo convention, not propagation: it pins no plugin version, and bumping it\n'
  printf 'on its own ships nothing. See docs/adr/ADR-001.\n\n'
  exit 1
fi

exit 0
