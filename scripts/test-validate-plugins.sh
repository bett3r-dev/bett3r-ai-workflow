#!/bin/sh
# Oracle for the agent `tools:` allowlist rule in scripts/validate-plugins.py.
#
# An agent entrypoint whose frontmatter carries no `tools:` key does not fail —
# it inherits every tool registered in the session, including any mcp write verb
# the host happens to have loaded. /design-multi then dispatches that agent
# unattended — and cuts no worktrees for it, since "All agents read the one
# working tree" (commands/design-multi.md) — with a strictly larger grant than
# any file in this repo states. The failure signature is ABSENCE again: nothing errors,
# nothing warns, the agent loads and runs.
#
# So the rule is over the SHAPE of the declaration only — "an agent names its
# tools" — and names no store, no tool and no repo. This suite drives it two
# ways:
#
#   * over throwaway plugin trees in a temp dir (the shape cases), following
#     scripts/test-skill-shadows.sh: the real script is copied beside a
#     synthesized plugins/ tree so its ROOT resolves there, and the one thing a
#     caller acts on — the exit status — is asserted;
#   * over the REAL corpus (the census), because a rule that is only ever run
#     against fixtures cannot tell a clean corpus from a corpus it never read.
#     The census asserts the observed agent count AND the negative form: no
#     agent outside the recorded offender list lacks a `tools:` key.
#
# The recorded offender list is now EMPTY: every agent in the corpus carries an
# allowlist (`tracker-writer` was the last one, fixed alongside this flip). The
# list is not decoration — emptying it without fixing the file fails the census,
# and so does fixing the file while leaving a name recorded here, because the
# assertion is an EXACT match in both directions. A future agent added without a
# `tools:` key fails here rather than being recorded.
#
# The prose cases are load-bearing: an agent body that *discusses* tool grants
# must neither satisfy the rule nor trip it. Only the block between the first
# two `---` lines counts, and a `#`-commented line inside that block is not a
# declaration.
#
# Run locally:  sh scripts/test-validate-plugins.sh
# Exit code is non-zero if anything is broken, so CI fails the PR.
#
# VP_PY selects the interpreter, matching how the other suites vary theirs.

set -u

VP_PY=${VP_PY:-python3}
ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
SCRIPT="$ROOT/scripts/validate-plugins.py"

# The corpus census, and the agents recorded as not yet carrying an allowlist.
EXPECTED_AGENTS=8
OFFENDERS=""

[ -f "$SCRIPT" ] || { printf 'test-validate-plugins: missing %s\n' "$SCRIPT" >&2; exit 2; }

TMP=$( mktemp -d "${TMPDIR:-/tmp}/validate-plugins-test.XXXXXX" ) || exit 1
TMP=$( CDPATH= cd -P -- "$TMP" && pwd )
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

# mktree <name> -> a repo-shaped dir with the REAL script at scripts/, one
# plugin with a valid manifest, and a marketplace entry pointing at it. The
# script resolves ROOT from its own location, so a copy beside a synthesized
# tree judges that tree and nothing else.
mktree(){
  d="$TMP/$1"
  mkdir -p "$d/scripts" "$d/plugins/alpha/.claude-plugin" "$d/.claude-plugin"
  cp "$SCRIPT" "$d/scripts/validate-plugins.py"
  printf '{ "name": "alpha", "version": "1.0.0", "description": "test plugin" }\n' \
    > "$d/plugins/alpha/.claude-plugin/plugin.json"
  printf '{ "name": "test", "plugins": [ { "name": "alpha", "source": "./plugins/alpha" } ] }\n' \
    > "$d/.claude-plugin/marketplace.json"
  printf '%s' "$d"
}

# add_agent <tree> <name> <frontmatter-extra-lines> [body]
add_agent(){
  mkdir -p "$1/plugins/alpha/agents"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$2"
    printf 'description: an agent used by this suite\n'
    [ -n "$3" ] && printf '%s\n' "$3"
    printf -- '---\n'
    printf '%s\n' "${4:-body text}"
  } > "$1/plugins/alpha/agents/$2.md"
}

add_command(){
  mkdir -p "$1/plugins/alpha/commands"
  printf -- '---\ndescription: a command used by this suite\n---\nbody\n' > "$1/plugins/alpha/commands/$2.md"
}

add_skill(){
  mkdir -p "$1/plugins/alpha/skills/$2"
  printf -- '---\nname: %s\ndescription: a skill used by this suite\n---\nbody\n' "$2" \
    > "$1/plugins/alpha/skills/$2/SKILL.md"
}

run(){ # run <tree> -> exit status in $rc
  ( cd "$1" && "$VP_PY" scripts/validate-plugins.py ) >"$TMP/out" 2>"$TMP/err"
  rc=$?
}

printf '\ntest-validate-plugins (%s)\n\n' "$VP_PY"

# --- 1. an agent WITH an allowlist is accepted ----------------------------
d=$( mktree with_tools ); add_agent "$d" scribe 'tools: Read, Grep'
run "$d"
if [ "$rc" -eq 0 ]; then ok "an agent declaring \`tools:\` is accepted"
else fail "an agent declaring \`tools:\` is accepted — expected exit 0, got $rc"; fi

# --- 1b. the BLOCK-LIST spelling is the one the real agents use -----------
# Every agent in this repo writes `tools:` with an indented YAML list under it,
# so the key line's own value is empty. A rule that only accepted the inline
# spelling would refuse the entire real corpus.
d=$( mktree block_tools ); add_agent "$d" scribe 'tools:
  - Read
  - Grep'
run "$d"
if [ "$rc" -eq 0 ]; then ok "an agent declaring \`tools:\` as an indented block list is accepted"
else fail "an agent declaring \`tools:\` as an indented block list is accepted — expected 0, got $rc"; fi

# --- 2. an agent WITHOUT one is refused, and named ------------------------
d=$( mktree no_tools ); add_agent "$d" scribe ''
run "$d"
if [ "$rc" -ne 0 ] && grep -q 'agents/scribe.md' "$TMP/err"; then
  ok "an agent with no \`tools:\` key is refused and the offending file is named"
else
  fail "an agent with no \`tools:\` key is refused and named — rc=$rc"
fi

# --- 3. an EMPTY allowlist is not an allowlist ----------------------------
# `tools:` with no value inherits exactly as a missing key does.
d=$( mktree empty_tools ); add_agent "$d" scribe 'tools:'
run "$d"
if [ "$rc" -ne 0 ] && grep -q 'agents/scribe.md' "$TMP/err"; then
  ok "an agent whose \`tools:\` value is empty is refused — an empty grant still inherits"
else
  fail "an agent whose \`tools:\` value is empty is refused — rc=$rc"
fi

# --- 4. prose is not a declaration ----------------------------------------
# The body of a real agent discusses its grants. Matching the file instead of
# the frontmatter block would let that prose satisfy the rule silently.
d=$( mktree prose_tools ); add_agent "$d" scribe '' \
  'This agent runs with tools: Read, Grep and nothing else.
tools: Write'
run "$d"
if [ "$rc" -ne 0 ] && grep -q 'agents/scribe.md' "$TMP/err"; then
  ok "\`tools:\` in the BODY does not satisfy the rule — only the frontmatter block counts"
else
  fail "\`tools:\` in the BODY does not satisfy the rule — rc=$rc"
fi

# --- 5. a commented-out declaration is not a declaration ------------------
d=$( mktree commented_tools ); add_agent "$d" scribe '# tools: Read'
run "$d"
if [ "$rc" -ne 0 ] && grep -q 'agents/scribe.md' "$TMP/err"; then
  ok "a \`#\`-commented \`tools:\` line in frontmatter does not satisfy the rule"
else
  fail "a \`#\`-commented \`tools:\` line in frontmatter does not satisfy the rule — rc=$rc"
fi

# --- 5b. a block list whose every item is COMMENTED OUT is not a list ------
# The corpus uses the block spelling exclusively, so this — not the inline
# `# tools:` above — is the shape a commented-out allowlist really takes here.
# It read as declared until XL-75 fix round 1.
d=$( mktree commented_block ); add_agent "$d" scribe 'tools:
  # - Read
  # - Bash'
run "$d"
if [ "$rc" -ne 0 ] && grep -q 'agents/scribe.md' "$TMP/err"; then
  ok "a block list whose every item is commented out is refused"
else
  fail "a block list whose every item is commented out is refused — rc=$rc"
fi

# --- 5c. negative control: a comment BESIDE a live item is still a list ----
d=$( mktree commented_plus_item ); add_agent "$d" scribe 'tools:
  # dropped Bash deliberately
  - Read'
run "$d"
if [ "$rc" -eq 0 ]; then ok "a comment above a live item does not invalidate the block list"
else fail "a comment above a live item does not invalidate the block list — expected 0, got $rc"; fi

# --- 5d. YAML spellings of "nothing" in the VALUE position ----------------
# Each leaves the key present and the allowlist absent. `[]` is refused by
# decision, not by accident: nothing here can verify whether the platform reads
# an empty list as "grant nothing" or as "unset, so inherit", and the two
# readings differ in the dangerous direction.
for spec in \
  'tools: # nothing at all|a value that is only a comment' \
  'tools: null|an explicit null' \
  'tools: ~|YAML'"'"'s tilde null' \
  'tools: []|an empty flow list' \
  ; do
  decl=${spec%%|*}; label=${spec#*|}
  d=$( mktree "empty_$( echo "$label" | tr -c 'a-z' _ )" ); add_agent "$d" scribe "$decl"
  run "$d"
  if [ "$rc" -ne 0 ] && grep -q 'agents/scribe.md' "$TMP/err"; then
    ok "$label is refused — the key is present, the allowlist is not"
  else
    fail "$label is refused — rc=$rc (declaration: $decl)"
  fi
done

# --- 5e. an inline value with a trailing comment is a real allowlist ------
d=$( mktree inline_trailing_comment ); add_agent "$d" scribe 'tools: Read, Grep # no Write on purpose'
run "$d"
if [ "$rc" -eq 0 ]; then ok "an inline allowlist with a trailing \`#\` comment is accepted"
else fail "an inline allowlist with a trailing \`#\` comment is accepted — expected 0, got $rc"; fi

# --- 5g. the empty spellings survive FORMATTING ---------------------------
# An exact-string refusal of `[]` is defeated by one space. Every spelling the
# docstring's EMPTY_VALUES claims is pinned here — that list and these cases
# are meant to be read together.
i=0
for decl in 'tools: [ ]' 'tools: {}' "tools: ''" 'tools: ""'; do
  i=$(( i + 1 ))
  d=$( mktree "empty_fmt_$i" ); add_agent "$d" scribe "$decl"
  run "$d"
  if [ "$rc" -ne 0 ] && grep -q 'agents/scribe.md' "$TMP/err"; then
    ok "\`$decl\` is refused — an empty allowlist however it is spelled"
  else
    fail "\`$decl\` is refused — rc=$rc"
  fi
done

# --- 5h. `none` is a TOOL NAME, not a null --------------------------------
# YAML has no `none` null. Accepting it is deliberate: the alternative refuses
# an agent whose only grant happens to be named that. A typo for `null` is
# accepted as the price.
d=$( mktree tools_none ); add_agent "$d" scribe 'tools: none'
run "$d"
if [ "$rc" -eq 0 ]; then ok "\`tools: none\` is accepted — \`none\` is a tool name, not a YAML null"
else fail "\`tools: none\` is accepted — expected 0, got $rc"; fi

# --- 5i. a COLUMN-0 comment inside the block does not end it --------------
# The only input that distinguishes the continuation scan's comment-skip: an
# unindented comment line would otherwise read as the next top-level key and
# FALSELY REFUSE an agent that does declare its tools. The indented-comment
# case (5c) cannot catch a refactor that drops the skip; this one can.
d=$( mktree column0_comment ); add_agent "$d" scribe 'tools:
# dropped Bash deliberately
  - Read'
run "$d"
if [ "$rc" -eq 0 ]; then ok "a column-0 comment between \`tools:\` and its first item does not end the block"
else fail "a column-0 comment between \`tools:\` and its first item does not end the block — expected 0, got $rc"; fi

# --- 5f. a comment does not rescue a null value ---------------------------
# `tools: null # temporarily` is the one case where stripping the trailing
# comment changes the verdict — without the strip the whole string is truthy
# and an explicitly nulled allowlist reads as declared.
d=$( mktree null_with_comment ); add_agent "$d" scribe 'tools: null # temporarily, see XL-75'
run "$d"
if [ "$rc" -ne 0 ] && grep -q 'agents/scribe.md' "$TMP/err"; then
  ok "a trailing comment does not rescue an explicitly null allowlist"
else
  fail "a trailing comment does not rescue an explicitly null allowlist — rc=$rc"
fi

# --- 6. an agent that merely DISCUSSES tools but declares them is clean ---
# The negative control for case 4: prose must not trip the rule either.
d=$( mktree prose_and_tools ); add_agent "$d" scribe 'tools: Read' \
  'Never grant this agent a tools: Write verb.'
run "$d"
if [ "$rc" -eq 0 ]; then
  ok "prose about tools does not TRIP the rule when the frontmatter declares them"
else
  fail "prose about tools does not trip the rule — expected exit 0, got $rc"; fi

# --- 7. the rule is scoped to agents --------------------------------------
# Commands and skills are not dispatched as autonomous sessions and carry no
# allowlist. Requiring one of them would be a different (and wrong) invariant.
d=$( mktree other_kinds ); add_agent "$d" scribe 'tools: Read'
add_command "$d" ship; add_skill "$d" drafting
run "$d"
if [ "$rc" -eq 0 ]; then ok "commands and skills are not required to declare \`tools:\`"
else fail "commands and skills are not required to declare \`tools:\` — expected 0, got $rc"; fi

# --- 7b. an agent NESTED under agents/ is refused, not silently ignored ---
# The rule reaches `agents/*.md`, because that is what Claude Code registers.
# That scope is correct but silent: a file one directory deeper is neither
# loaded nor checked for an allowlist, so a missing `tools:` there would fail
# OPEN — the same absence-shaped failure this whole suite exists to catch.
# The boundary is therefore asserted rather than assumed.
d=$( mktree nested_agent ); add_agent "$d" scribe 'tools: Read'
mkdir -p "$d/plugins/alpha/agents/archive"
printf -- '---\ndescription: an agent hidden one level down\n---\nbody\n' \
  > "$d/plugins/alpha/agents/archive/buried.md"
run "$d"
if [ "$rc" -ne 0 ] && grep -q 'archive/buried.md' "$TMP/err"; then
  ok "markdown nested under agents/ is refused and named, not silently unchecked"
else
  fail "markdown nested under agents/ is refused and named — rc=$rc"
fi

# --- 7c. negative control: a flat agents/ dir is untouched by 7b ----------
# The nesting rule must not fire on the ordinary shape, or every clean tree
# above would be failing for the wrong reason.
d=$( mktree flat_agent ); add_agent "$d" scribe 'tools: Read'; add_agent "$d" herald 'tools: Read'
run "$d"
if [ "$rc" -eq 0 ]; then ok "a flat agents/ directory does not trip the nesting rule"
else fail "a flat agents/ directory does not trip the nesting rule — expected 0, got $rc"; fi

# --- 8. the pre-existing checks still fire --------------------------------
# The new rule must not displace what the script already refused. An agent
# WITH an allowlist and no description is still a failure, and the ✓ summary
# line still counts every artifact on a clean tree.
d=$( mktree still_description )
mkdir -p "$d/plugins/alpha/agents"
printf -- '---\nname: scribe\ntools: Read\n---\nbody\n' > "$d/plugins/alpha/agents/scribe.md"
run "$d"
if [ "$rc" -ne 0 ] && grep -q 'no non-empty `description`' "$TMP/err"; then
  ok "the pre-existing \`description\` check still fires (check_frontmatter unchanged)"
else
  fail "the pre-existing \`description\` check still fires — rc=$rc"
fi

d=$( mktree clean_summary ); add_agent "$d" scribe 'tools: Read'
add_command "$d" ship; add_skill "$d" drafting
run "$d"
if [ "$rc" -eq 0 ] && grep -q '✓ .* artifacts valid' "$TMP/out"; then
  ok "a clean tree still prints the ✓ artifacts-valid summary line"
else
  fail "a clean tree still prints the ✓ artifacts-valid summary line — rc=$rc"
fi

# --- 9. the census over the REAL corpus -----------------------------------
# Enumerated from source with the script's own frontmatter pattern, not from a
# recorded list: a census that reads a list cannot notice a new agent.
census=$( "$VP_PY" - "$ROOT" <<'PY' 2>"$TMP/err"
# A SECOND COPY of validate-plugins.py's declares_tools, not an independent
# re-derivation — it is the same logic, kept here only so the census does not
# call the checker it is auditing. Treat that honestly: a bug in the shape rule
# is copied into both, and this census will NOT catch it (one already was — a
# fully commented-out block list read as declared in both, XL-75 fix round 1).
# What the census does catch is the corpus drifting out from under the rule: a
# new agent, or a recorded offender list edited without the file being fixed.
# The fixture cases above are what test the shape itself. Keep the two copies
# in step by hand.
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
FRONTMATTER = re.compile(r"\A---\r?\n(?!-)(.*?)\r?\n---\r?\n", re.DOTALL)


# The spellings that leave the `tools:` key present with no allowlist behind
# it. Compared against the value with all whitespace removed, so `[ ]` cannot
# slip past `[]` on one space — an exact-string refusal is defeated by
# formatting, which is the cheapest possible way to lose this rule.
EMPTY_VALUES = ("", "null", "Null", "NULL", "~", "[]", "{}")


def _meaningful(value: str) -> bool:
    """Is this YAML scalar/item an actual value, once a trailing `#` comment,
    one layer of quotes and YAML's spellings of "nothing" are removed?

    Note what is deliberately NOT empty: `tools: none` reads as a tool literally
    named `none`, because `none` is not a YAML null spelling. It is accepted,
    and a typo for `null` is therefore accepted too — the alternative is
    refusing an agent whose only tool happens to be named that.
    """
    v = value.strip()
    if v.startswith("#"):
        return False
    v = v.split(" #", 1)[0].split("\t#", 1)[0].strip()
    # One layer of quotes: `tools: ''` is the key with an empty scalar.
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1].strip()
    return "".join(v.split()) not in EMPTY_VALUES


def declares_tools(body: str) -> bool:
    """Does this frontmatter block declare a non-empty `tools:` allowlist?

    Both spellings in the corpus count: inline (`tools: Read, Grep`) and the
    indented YAML block list the agents here actually use

        tools:
          - Read
          - Write

    Neither counts when it is EMPTY, because an empty allowlist inherits
    exactly as a missing key does. "Empty" is not a universal claim about YAML
    — it is exactly the spellings in `EMPTY_VALUES` (`null`, `~`, `[]`, `{}`,
    the empty scalar, each modulo quotes and internal whitespace), plus a bare
    `tools:` with nothing under it, plus — the case the corpus is most exposed
    to — a block list whose every item is COMMENTED OUT. Each has a fixture in
    scripts/test-validate-plugins.sh; a spelling with no fixture is not
    claimed here.

    A `#` line is a comment at any indent, so the continuation scan skips it as
    the top-level loop does. That skip is load-bearing in BOTH directions:
    `tools:` over `  # - Read` is an agent with no allowlist (in the one
    spelling every agent in this repo uses), while a comment at COLUMN 0
    between `tools:` and its first item must NOT end the block — without the
    skip that unindented line reads as the next key and falsely refuses a
    legitimately-declared agent.

    `tools: []` is REFUSED rather than read as a deliberate zero grant: this
    rule cannot verify what the platform does with an empty list, and the two
    readings ("grant nothing" vs "unset, so inherit") differ in exactly the
    dangerous direction. An agent that truly needs nothing can say so in a
    comment beside a minimal grant.

    Only the frontmatter block is read (the caller has already sliced it), so
    an agent body that *discusses* tool grants must neither satisfy this nor
    trip it.
    """
    lines = body.splitlines()
    for i, line in enumerate(lines):
        if not line.strip() or line.startswith((" ", "\t", "-", "#")):
            continue
        key, sep, value = line.partition(":")
        if not sep or key.strip() != "tools":
            continue
        if _meaningful(value):
            return True
        # An empty value is a block list only if some following line is an
        # indented (or `-`) item with real content. Comments and blank lines
        # are skipped; the first line back at the top level ends the block.
        for nxt in lines[i + 1:]:
            if not nxt.strip() or nxt.lstrip().startswith("#"):
                continue
            if not nxt.startswith((" ", "\t", "-")):
                return False
            if _meaningful(nxt.lstrip(" \t-")):
                return True
        return False
    return False

missing = []
files = sorted(root.glob("plugins/*/agents/*.md"))
for f in files:
    m = FRONTMATTER.match(f.read_text(encoding="utf-8"))
    if not m or not declares_tools(m.group(1)):
        missing.append(f.stem)
print(len(files))
print(" ".join(sorted(missing)))
PY
)
count=$( printf '%s\n' "$census" | sed -n 1p )
observed=$( printf '%s\n' "$census" | sed -n 2p )

if [ "$count" = "$EXPECTED_AGENTS" ]; then
  ok "the corpus holds $EXPECTED_AGENTS agent entrypoints"
else
  fail "the corpus holds $EXPECTED_AGENTS agent entrypoints — observed '$count'"
fi

if [ "$observed" = "$OFFENDERS" ]; then
  if [ -n "$OFFENDERS" ]; then
    ok "no agent outside the recorded offender list lacks \`tools:\` (recorded: $OFFENDERS)"
  else
    ok "no agent lacks \`tools:\` — the offender list is empty and the corpus agrees"
  fi
else
  fail "agents lacking \`tools:\` must be exactly '$OFFENDERS' — observed '$observed'"
fi

printf '\n'
if [ "$failed" -gt 0 ]; then
  printf '\033[31m✗ %d failed\033[0m, %d passed\n\n' "$failed" "$passed"
  exit 1
fi
printf '\033[32m✓ %d passed\033[0m\n\n' "$passed"
