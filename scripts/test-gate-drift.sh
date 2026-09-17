#!/bin/sh
# Drift oracle for the host gate (ESAS-186 D1): every `run:` command line in
# .github/workflows/validate-plugins.yml must appear, verbatim, as a line of
# .claude/gate.sh.
#
# The gate is a hand-maintained copy of the workflow, and the failure of a copy is
# absence: a step added to the workflow and not to the gate leaves the local gate
# reporting PASS over a check it never ran. Presence is exactly what this can
# assert. Whether the gate runs a line *correctly* is the gate's own business.
#
# Extraction: a single-line `run: <cmd>` yields <cmd>; a `run: |` block yields
# each non-blank line indented deeper than the `run:` key. Any other `run:` form
# (`|-`, `|+`, `>`, a quoted value spanning lines) fails the test, named. Leading whitespace is
# stripped on both sides, and a gate line must match a workflow line EXACTLY
# (grep -xF), so `sh scripts/test-hooks.sh` is not satisfied by the longer
# `HOOK_SH=dash sh scripts/test-hooks.sh`, and a commented-out gate line
# (`# sh ...`) does not count.
#
# Mapping (the one place gate and workflow may differ in spelling):
#   "origin/${{ github.base_ref || 'master' }}"   ->   "${GATE_BASE}"
# (gate.sh defaults GATE_BASE to origin/master.)
# Excluded by name: the CI-only installer line
#   python3 -c 'import yaml' 2>/dev/null || sudo apt-get install -y python3-yaml
#
# A positive control runs the extractor over a built-in specimen first, and zero
# lines extracted from the real workflow is a failure — an extractor that finds
# nothing would otherwise report "no drift" in a clean tree's voice.
#
# Run locally:  sh scripts/test-gate-drift.sh
# WORKFLOW / GATE override the two paths (used by the mutation check).

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
WORKFLOW=${WORKFLOW:-$ROOT/.github/workflows/validate-plugins.yml}
GATE=${GATE:-$ROOT/.claude/gate.sh}
INSTALLER="python3 -c 'import yaml' 2>/dev/null || sudo apt-get install -y python3-yaml"

passed=0
failed=0
pass() { passed=$((passed + 1)); printf '  ok   %s\n' "$1"; }
fail() { failed=$((failed + 1)); printf '  FAIL %s\n' "$1"; }

# extract <file> — prints one command line per line, mapped, installer excluded.
extract() {
  awk '
    function indent(s) { match(s, /^ */); return RLENGTH }
    inblock {
      if ($0 ~ /^[ \t]*$/) next
      if (indent($0) > runind) { l = $0; sub(/^[ \t]+/, "", l); print l; next }
      inblock = 0
    }
    /^[ \t]*(- )?run:[ \t]*\|[ \t]*$/ { runind = indent($0); if ($0 ~ /^ *- /) runind += 2; inblock = 1; next }
    /^[ \t]*(- )?run:[ \t]*[^ \t|>]/ { l = $0; sub(/^[ \t]*(- )?run:[ \t]*/, "", l); print l }
  ' "$1" | sed "s#\"origin/\${{ github.base_ref || 'master' }}\"#\"\${GATE_BASE}\"#g" \
    | grep -vxF -- "$INSTALLER"
}

# unparsed <file> — prints every `run:` line neither extractor pattern handles:
# a block scalar other than a bare `|` (`|-`, `|+`, `>`, `>-` ...), or a quoted
# value whose closing quote is not on the same line (a multi-line scalar). The
# extractor would silently drop or truncate these, so the test fails closed.
unparsed() {
  awk '
    /^[ \t]*(- )?run:/ {
      v = $0; sub(/^[ \t]*(- )?run:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      if (v == "|") next
      if (v == "" || v ~ /^[|>]/) { print; next }
      q = substr(v, 1, 1)
      if ((q == "\"" || q == "\047") && (length(v) < 2 || substr(v, length(v), 1) != q)) { print; next }
    }
  ' "$1"
}

echo "positive control: extractor over a specimen workflow"
SPEC=$(mktemp "${TMPDIR:-/tmp}/drift-spec.XXXXXX")
cat >"$SPEC" <<'SPECEOF'
jobs:
  a:
    steps:
      - uses: actions/checkout@v4
      - name: one
        run: python3 one.py
      - name: two
        run: |
          sh two.sh
          X=dash dash two.sh

      # a comment
      - name: three
        run: sh three.sh "origin/${{ github.base_ref || 'master' }}"
      - name: four
        run: |
          python3 -c 'import yaml' 2>/dev/null || sudo apt-get install -y python3-yaml
          sh four.sh
SPECEOF
got=$(extract "$SPEC")
want='python3 one.py
sh two.sh
X=dash dash two.sh
sh three.sh "${GATE_BASE}"
sh four.sh'
if [ "$got" = "$want" ]; then
  pass "specimen yields the 5 expected lines (block, single-line, mapping, installer excluded)"
else
  fail "specimen extraction mismatch; got:"; printf '%s\n' "$got" | sed 's/^/         /'
fi
rm -f "$SPEC"

SPEC2=$(mktemp "${TMPDIR:-/tmp}/drift-spec2.XXXXXX")
cat >"$SPEC2" <<'SPECEOF'
jobs:
  a:
    steps:
      - name: ok
        run: sh ok.sh
      - name: folded
        run: >
          sh folded.sh
      - name: strip
        run: |-
          sh strip.sh
      - name: quoted
        run: "sh quoted.sh
          --more"
SPECEOF
got=$(unparsed "$SPEC2" | sed 's/^[ \t]*//')
want='run: >
run: |-
run: "sh quoted.sh'
if [ "$got" = "$want" ]; then
  pass "specimen: run: >, run: |- and an unclosed quoted value are reported unparsed"
else
  fail "specimen unparsed-detection mismatch; got:"; printf '%s\n' "$got" | sed 's/^/         /'
fi
rm -f "$SPEC2"

echo "workflow run: lines present in the gate"
UNPARSED=$(unparsed "$WORKFLOW")
if [ -z "$UNPARSED" ]; then
  pass "every run: line in $(basename "$WORKFLOW") is a form the extractor handles"
else
  printf '%s\n' "$UNPARSED" | while IFS= read -r u; do
    printf '  FAIL unparsed run: form (extend the extractor): %s\n' "$(printf '%s' "$u" | sed 's/^[ \t]*//')"
  done
  failed=$((failed + $(printf '%s\n' "$UNPARSED" | grep -c .)))
fi
LINES=$(extract "$WORKFLOW")
count=$(printf '%s\n' "$LINES" | grep -c .)
if [ "$count" -gt 0 ]; then
  pass "extracted $count command lines from $(basename "$WORKFLOW")"
else
  fail "extracted ZERO command lines from $WORKFLOW — extractor or path is broken"
fi
LINESF=$(mktemp "${TMPDIR:-/tmp}/drift-lines.XXXXXX")
GATEF=$(mktemp "${TMPDIR:-/tmp}/drift-gate.XXXXXX")
printf '%s\n' "$LINES" >"$LINESF"
sed 's/^[[:space:]]*//' "$GATE" >"$GATEF"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  if grep -qxF -- "$line" "$GATEF"; then
    pass "$line"
  else
    fail "missing from .claude/gate.sh: $line"
  fi
done <"$LINESF"
rm -f "$LINESF" "$GATEF"

echo
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
