#!/bin/sh
# Oracle for the two generic flow seams added by ESAS-94:
#
#   Seam A — `/start`, `/design`, `/plan` and `/build` record the current mode
#            and work item in `.work/mode.yaml`, overwritten and never appended,
#            and `/start` CLEARS a stale one.
#   Seam B — `/design` Step 1 is a declared extension point where an optional
#            repo-local context provider may contribute grounding items.
#
# Both seams are text a model reads, so most of what they promise can only be
# reviewed. That is not a reason to assert nothing: the failure these seams exist
# to prevent is a *deletion* — the clearing sentence dropped in a tidy-up, or the
# failure-tolerance rule lost when the reference file is next reorganised — and
# deletion is exactly what a presence oracle catches. Wrongness is a review.
#
# One part can be **executed**, and this suite executes it: the marker's own
# field list. `commands/start.md` documents `.work/mode.yaml` as a fenced YAML
# block, and that block is the only specification of the format any of the four
# commands writes. It is extracted here verbatim and parsed, so a block edited
# into something that does not parse — or that quietly grows a fifth field the
# other three commands know nothing about — fails here rather than in a session.
#
# The four assertions named in ESAS-94's "Test seams" line are tagged [SEAM n]
# below, so a reader can check the ticket's contract against this file directly:
#
#   [SEAM 1] `/design` with zero providers is unchanged
#   [SEAM 2] a stale marker from a prior branch is cleared by `/start`
#   [SEAM 3] a throwing provider does not fail `/design`
#   [SEAM 4] the marker distinguishes a re-run `/design` from `/build` on one branch
#
# Run locally:  sh scripts/test-flow-seams.sh
# Exit code is non-zero if anything is broken, so CI fails the PR.
#
# MARKER_PY selects the interpreter that parses the extracted YAML block.

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
PLUGIN="$ROOT/plugins/bett3r-ai-workflow"
START_MD="$PLUGIN/commands/start.md"
DESIGN_MD="$PLUGIN/commands/design.md"
PLAN_MD="$PLUGIN/commands/plan.md"
BUILD_MD="$PLUGIN/commands/build.md"
PROVIDERS_MD="$PLUGIN/CONTEXT-PROVIDERS.md"
PENDING_MD="$PLUGIN/skills/esas-pending/SKILL.md"
MARKER_PY=${MARKER_PY:-python3}

TMP=$( mktemp -d "${TMPDIR:-/tmp}/flow-seams-test.XXXXXX" ) || exit 1
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

# present <file> <literal> <description>
#
# Compares against a whitespace-NORMALISED copy of the file, and normalises the
# needle the same way. These artifacts are hard-wrapped prose: a sentence that
# reflows when a word is added would otherwise break an assertion that is still
# true, and an oracle that goes red on reflow is one that gets edited to agree
# with the file rather than believed. Line structure is not what is being
# asserted here — the sentence surviving is.
norm(){
  cache="$TMP/norm.$( printf '%s' "$1" | tr -c 'A-Za-z0-9' '_' )"
  [ -f "$cache" ] || tr '\n' ' ' < "$1" | tr -s ' ' > "$cache"
  printf '%s' "$cache"
}

present(){
  needle=$( printf '%s' "$2" | tr '\n' ' ' | tr -s ' ' )
  if grep -qF "$needle" "$( norm "$1" )"; then
    pass "$3"
  else
    fail "$3" "expected literal not found in ${1#"$ROOT"/}:" "  $2"
  fi
}

# ---------------------------------------------------------------------------
printf '\nSeam A — the mode/work-item marker\n\n'
# ---------------------------------------------------------------------------

# The file itself, named in every command that writes it. If the path is
# renamed, it must be renamed in all four or the flow silently keeps two
# markers — which is the residue bug wearing a new hat.
for f in "$START_MD" "$DESIGN_MD" "$PLAN_MD" "$BUILD_MD"; do
  present "$f" '.work/mode.yaml' "${f##*/} names .work/mode.yaml"
done

# [SEAM 4] Each command claims its OWN mode. This is the assertion that makes a
# re-run `/design` distinguishable from `/build` on one branch: if `/design`
# stopped writing `mode: design`, the marker would still exist, still parse, and
# still be wrong — the exact silent failure the seam was built to end.
present "$DESIGN_MD" 'mode: design' '[SEAM 4] /design writes mode: design'
present "$PLAN_MD"   'mode: plan'   '[SEAM 4] /plan writes mode: plan'
present "$BUILD_MD"  'mode: build'  '[SEAM 4] /build writes mode: build'
present "$START_MD"  'mode: start'  '[SEAM 4] /start writes mode: start'

# [SEAM 2] The load-bearing half. `/start` must CLEAR, not merge — a marker that
# survives a new `/start` is confidently wrong about the work item.
present "$START_MD" 'clear and rewrite' '[SEAM 2] /start clears the marker before writing it'
present "$START_MD" 'never merge with, patch, or preserve a field' \
  '[SEAM 2] /start is forbidden from preserving a prior work item'\''s fields'
present "$START_MD" 'A marker that survives a new `/start` is worse than no marker' \
  '[SEAM 2] and the reason the clearing matters is stated, not just the rule'

# Overwrite-not-append, in all four. Append-only reproduces the residue bug.
present "$START_MD"  'never appended' '/start states overwrite-not-append'
present "$DESIGN_MD" 'never appended' '/design states overwrite-not-append'
present "$PLAN_MD"   'never an append' '/plan states overwrite-not-append'
present "$BUILD_MD"  'never an append' '/build states overwrite-not-append'

# A repo not using this must be unaffected — the marker lives in the already
# gitignored workspace and nothing else changes.
present "$START_MD" 'already-gitignored' 'the marker is confined to the gitignored .work/'

# --- executed: the marker format actually parses, and is exactly four fields ---
#
# Extract the first fenced ```yaml block from start.md. That block IS the format
# specification — there is no second copy to drift against.
awk '/^```yaml$/{f=1;next} /^```$/{if(f)exit} f' "$START_MD" > "$TMP/marker.yaml"

if [ ! -s "$TMP/marker.yaml" ]; then
  fail 'the marker format block is extractable from start.md' \
       'no fenced ```yaml block found — the format is now specified nowhere executable'
else
  pass 'the marker format block is extractable from start.md'

  # Parsed without a YAML dependency: the block is four `key: value` lines with
  # `#` comments, which is deliberately the whole grammar. Anything richer than
  # that in a marker four commands must write identically is a defect, so the
  # narrow parser is the assertion.
  "$MARKER_PY" - "$TMP/marker.yaml" > "$TMP/keys" 2>"$TMP/err" <<'PY'
import re, sys
keys = []
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.split("#", 1)[0].strip()
    if not line:
        continue
    m = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*):\s*(\S.*)?", line)
    if not m:
        sys.exit("unparseable marker line: %r" % line)
    keys.append(m.group(1))
print(" ".join(keys))
PY
  if [ $? -ne 0 ]; then
    fail 'the documented marker parses' "$( cat "$TMP/err" )"
  else
    pass 'the documented marker parses'
    actual=$( cat "$TMP/keys" )
    if [ "$actual" = 'mode work_item branch updated' ]; then
      pass 'the marker is exactly mode / work_item / branch / updated, in order'
    else
      fail 'the marker is exactly mode / work_item / branch / updated, in order' \
           "got: $actual" \
           'four commands write this file; a field one of them does not know about is residue.'
    fi
  fi

  # The documented `mode:` value must be one of the four the commands write —
  # an example naming a fifth mode is a specification of a mode nothing sets.
  m=$( sed -n 's/^mode:[[:space:]]*\([A-Za-z]*\).*/\1/p' "$TMP/marker.yaml" )
  case "$m" in
    start|design|plan|build) pass "the documented mode value ($m) is one a command actually writes" ;;
    *) fail 'the documented mode value is one a command actually writes' "got: ${m:-<none>}" ;;
  esac
fi

# ---------------------------------------------------------------------------
printf '\nSeam B — /design Step 1 context contributions\n\n'
# ---------------------------------------------------------------------------

# The pointer, and the file it points at. `check-eval-coverage.py` proves a
# scenario exists for this split; this proves the link itself still exists.
present "$DESIGN_MD" '(../CONTEXT-PROVIDERS.md)' '/design Step 1 links CONTEXT-PROVIDERS.md'
if [ -f "$PROVIDERS_MD" ]; then
  pass 'CONTEXT-PROVIDERS.md exists'
else
  fail 'CONTEXT-PROVIDERS.md exists' 'the pointer in /design resolves to nothing'
fi

# [SEAM 1] Zero providers is the normal case, and the no-provider path is
# SILENT. A seam that announces itself in every repo that does not use it has
# become the interruption it was designed to avoid.
present "$DESIGN_MD"    'zero providers is the normal case' \
  '[SEAM 1] /design states zero providers is the normal case'
present "$DESIGN_MD"    'do not mention that an extension point was consulted' \
  '[SEAM 1] with no providers, /design says nothing at all'
present "$PROVIDERS_MD" 'behaves exactly as it did before this file existed' \
  '[SEAM 1] the no-provider path is specified as byte-for-byte unchanged'

# [SEAM 3] Failure tolerance. The seam is optional enrichment; a design session
# that cannot start because it is down has inverted the priority.
present "$DESIGN_MD"    'never fails `/design`' \
  '[SEAM 3] /design states a failing provider does not fail the command'
present "$PROVIDERS_MD" 'Failure is tolerated, always' \
  '[SEAM 3] CONTEXT-PROVIDERS.md makes failure tolerance a named rule'
present "$PROVIDERS_MD" 'errors, times out, returns nothing, or returns something unparseable' \
  '[SEAM 3] and enumerates the failure modes, so none is left to improvisation'
present "$PROVIDERS_MD" 'Never retry in a loop, and never block on one' \
  '[SEAM 3] a hanging provider is bounded, not merely caught'
present "$PROVIDERS_MD" 'grounding degraded' \
  '[SEAM 3] the degrade is recorded in the existing voice, not a new one'

# The rejected alternative, and the evidence it was rejected on. This is the
# part most likely to be lost in a future tidy-up, and losing it is how the
# hook gets rebuilt by someone who never saw why it was suppressed.
present "$PROVIDERS_MD" 'telemetry, never a trigger' \
  'the hook alternative is rejected quoting the standing rule verbatim'
present "$PENDING_MD"   'telemetry, never a trigger' \
  'and that quote still matches skills/esas-pending/SKILL.md — the evidence, not a paraphrase'
present "$PROVIDERS_MD" 'esas-pending.sh' \
  'the rejected surface is named by the file that implements it'

# Neither seam may mention a knowledge store: the base flow plugin stays
# store-agnostic and the store adapts to the flow, never the reverse. This is
# the coupling invariant, and it is asserted rather than trusted.
for f in "$PROVIDERS_MD" "$DESIGN_MD" "$START_MD" "$PLAN_MD" "$BUILD_MD"; do
  if grep -qiE 'knowledge store|knowledge-store' "$f"; then
    fail "${f##*/} stays store-agnostic" \
         'mentions a knowledge store — the base flow plugin must carry no consumer knowledge.'
  else
    pass "${f##*/} stays store-agnostic"
  fi
done

# Scope: /design only, with the three rejections recorded.
present "$PROVIDERS_MD" 'Scope: `/design` only' 'the seam is scoped to /design'
present "$PROVIDERS_MD" 'no human to answer a fork' '/build is rejected, with its reason'
present "$PROVIDERS_MD" 'already self-skips when unattended' '/plan is rejected, with its reason'

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
