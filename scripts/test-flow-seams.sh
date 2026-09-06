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
UNIT_LANE_MD="$PLUGIN/agents/unit-lane.md"
LANE_STEP_FIXTURES="$ROOT/scripts/fixtures/lane-step"
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
# the coupling invariant, and it is asserted as a TABLE of (seam file x
# forbidden consumer term) rather than one hard-coded grep over five hard-coded
# file variables. Adding a seam file, or a second forbidden consumer, is a row
# added to one of the two lists below — never a second grep elsewhere.
#
# COUPLING_SEAM_FILES may be overridden by the environment (one "label|path"
# row per line) so a mutation test can point this same check at a scratch
# copy of the plugin tree without ever touching the tracked seam files.
COUPLING_SEAM_FILES=${COUPLING_SEAM_FILES:-"CONTEXT-PROVIDERS.md|$PROVIDERS_MD
design.md|$DESIGN_MD
start.md|$START_MD
plan.md|$PLAN_MD
build.md|$BUILD_MD
unit-lane.md|$UNIT_LANE_MD"}

# COUPLING_FORBIDDEN_TERMS may likewise be overridden, one term per line.
# Terms are combined into a single case-insensitive alternation.
COUPLING_FORBIDDEN_TERMS=${COUPLING_FORBIDDEN_TERMS:-"knowledge store
knowledge-store"}

coupling_regex=$( printf '%s' "$COUPLING_FORBIDDEN_TERMS" | tr '\n' '|' )
coupling_regex=${coupling_regex%|}

# The two lists above are environment INPUTS, which is what makes this guard
# executable against a scratch tree — and also what makes it neuterable.
# `${VAR:-default}` catches an EMPTY override but never a WRONG one: a terms
# list naming something that appears nowhere, or a table truncated to one row,
# leaves every surviving row "passing" against nothing and prints a green tally
# byte-identical to a real full pass. A detector that can be silenced without
# saying so is not a detector. So the table asserts itself against a hard-coded
# floor before it is used; these two lists are deliberately NOT overridable.
#
# The floor is keyed on LABELS, not paths, because pointing the table at a
# scratch copy of the plugin tree is the supported use: paths move, the seams
# they name do not. A new seam file goes in BOTH lists: adding it to the table
# alone checks it but never notices its removal, which is a silent under-assert.
#
# The residual, named so nobody reads the floor as more than it is: it bounds
# WHICH SEAMS and WHICH TERMS, never WHICH BYTES. Pointing every required label
# at one benign file still clears the floor and still exits green. That is
# inherent to supporting retargeting at a scratch copy, and it takes a variable
# CI never sets — the floor closes term substitution and table truncation, and
# those two only.
COUPLING_REQUIRED_LABELS='CONTEXT-PROVIDERS.md
design.md
start.md
plan.md
build.md
unit-lane.md'
COUPLING_REQUIRED_TERMS='knowledge store
knowledge-store'

# Blank rows are dropped once, here, so that the row count the loop reconciles
# against is the same number of rows the loop actually sees.
printf '%s\n' "$COUPLING_SEAM_FILES" | grep -v '^[[:space:]]*$' > "$TMP/coupling-seam-files"
coupling_rows=$( wc -l < "$TMP/coupling-seam-files" | tr -d ' ' )
printf '%s\n' "$COUPLING_FORBIDDEN_TERMS" | grep -v '^[[:space:]]*$' > "$TMP/coupling-terms"

if [ "$coupling_rows" -gt 0 ]; then
  pass "coupling table is non-empty ($coupling_rows rows)"
else
  fail 'coupling table is non-empty' \
       'COUPLING_SEAM_FILES yielded no rows: the coupling invariant would assert nothing and still exit green.'
fi

cut -d'|' -f1 "$TMP/coupling-seam-files" > "$TMP/coupling-labels"
coupling_missing_labels=
while IFS= read -r want; do
  grep -Fxq "$want" "$TMP/coupling-labels" || coupling_missing_labels="$coupling_missing_labels $want"
done <<EOF
$COUPLING_REQUIRED_LABELS
EOF
if [ -z "$coupling_missing_labels" ]; then
  pass 'coupling table still covers all known seam files'
else
  fail 'coupling table still covers all known seam files' \
       "missing rows for:$coupling_missing_labels" \
       'a truncated COUPLING_SEAM_FILES silently stops checking the seams it dropped.'
fi

coupling_missing_terms=
while IFS= read -r want; do
  grep -Fxiq "$want" "$TMP/coupling-terms" || coupling_missing_terms="$coupling_missing_terms '$want'"
done <<EOF
$COUPLING_REQUIRED_TERMS
EOF
if [ -z "$coupling_missing_terms" ]; then
  pass 'coupling table still forbids all known consumer terms'
else
  fail 'coupling table still forbids all known consumer terms' \
       "missing terms:$coupling_missing_terms" \
       'a substituted COUPLING_FORBIDDEN_TERMS makes every row pass against a term no file contains.'
fi

# Written to a file rather than piped into the while loop below: a pipe would
# run the loop in a subshell, and the passed/failed counters it updates would
# be lost the moment the subshell exits.
coupling_asserted=0
while IFS='|' read -r label path rest; do
  coupling_asserted=$(( coupling_asserted + 1 ))
  # A malformed row must be RED, never skipped and never green. A row with no
  # separator parses as label=<the whole path>, path=<empty>, and a grep
  # against an empty path merely errors — which would otherwise fall through
  # to the else branch and emit pass() for a file that was never read.
  if [ -z "$label" ] || [ -z "$path" ] || [ -n "$rest" ]; then
    fail "coupling row is well-formed: '$label${path:+|}$path'" \
         'each row must be exactly "label|path" — this one is not, so its seam file was never checked.'
    continue
  fi
  if [ ! -f "$path" ]; then
    fail "$label stays store-agnostic" \
         "no such file: $path — the row names a seam that does not exist, so nothing was checked."
    continue
  fi
  if grep -qiE "$coupling_regex" "$path"; then
    fail "$label stays store-agnostic" \
         'mentions a forbidden consumer term — the base flow plugin must carry no consumer knowledge.'
  else
    pass "$label stays store-agnostic"
  fi
done < "$TMP/coupling-seam-files"

if [ "$coupling_asserted" -eq "$coupling_rows" ]; then
  pass "every coupling row was asserted ($coupling_asserted/$coupling_rows)"
else
  fail 'every coupling row was asserted' \
       "asserted $coupling_asserted of $coupling_rows rows — a row was skipped, and a skipped row is a seam nobody checked."
fi

# Scope: /design only, with the three rejections recorded.
present "$PROVIDERS_MD" 'Scope: `/design` only' 'the seam is scoped to /design'
present "$PROVIDERS_MD" 'no human to answer a fork' '/build is rejected, with its reason'
present "$PROVIDERS_MD" 'already self-skips when unattended' '/plan is rejected, with its reason'

# ---------------------------------------------------------------------------
printf '\nSeam C — the LANE-STEP:v1 step-outcome marker\n\n'
# ---------------------------------------------------------------------------
#
# ADR-004: a step reports what happened as a `LANE-STEP:v1` line, structured
# facts as attributes on the marker, emitted as the LAST line of the step. Two
# things are executed here rather than reviewed.
#
# First, the fenced spec block in `agents/unit-lane.md` — which, exactly like
# `mode.yaml`'s block in `commands/start.md`, is the ONLY specification of the
# format, so it is extracted verbatim and parsed. A block edited into something
# unparseable, or that quietly grows a fourth EMITTED outcome, fails here.
#
# Second, the parse rule itself — `take the last line-anchored, line-terminated
# match, and require it to be the final line` — against a decoy corpus. This
# half is the reason the marker needs a suite at all: `GATE-STEP:`'s producer is
# a shell script and cannot emit one by accident, but `LANE-STEP:`'s producer is
# a MODEL whose stdout also carries its own prose about the marker. It can
# mention the token, quote a full example inline, and print one at column 0
# inside a fence, all before the real line; it can narrate the marker
# mid-sentence on its very last line, which is the shape only anchoring rejects;
# and it can start the last line correctly and then append an aside after the
# attributes, which is the shape only the end-of-line clause rejects.

awk '/^```yaml$/{f=1;next} /^```$/{if(f)exit} f' "$UNIT_LANE_MD" > "$TMP/lane-step.yaml"

if [ ! -s "$TMP/lane-step.yaml" ]; then
  fail 'the LANE-STEP spec block is extractable from unit-lane.md' \
       'no fenced ```yaml block found — the step-outcome contract is now specified nowhere executable'
else
  pass 'the LANE-STEP spec block is extractable from unit-lane.md'

  # Same narrow `key: value` grammar the mode.yaml block is held to, plus the
  # two facts ADR-004 makes load-bearing: the EMITTED vocabulary, and that
  # `infra` is derived from the line's ABSENCE and never emitted. A step that
  # is being OOM-killed cannot emit anything, so an `infra` emission path would
  # be a promise nothing can keep.
  "$MARKER_PY" - "$TMP/lane-step.yaml" > "$TMP/lane-step-keys" 2>"$TMP/err" <<'PY'
import re, sys
fields = {}
order = []
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.rstrip("\n").strip()
    if not line:
        continue
    m = re.fullmatch(r"([a-z_][a-z0-9_]*):\s+(\S.*)", line)
    if not m:
        sys.exit("unparseable LANE-STEP spec line: %r" % line)
    if m.group(1) in fields:
        sys.exit("duplicate key in LANE-STEP spec block: %r" % m.group(1))
    fields[m.group(1)] = m.group(2).strip()
    order.append(m.group(1))
for want in ("marker", "attributes", "emits", "absent", "position", "parse"):
    if want not in fields:
        sys.exit("LANE-STEP spec block is missing the %r key" % want)
if fields["marker"] != "LANE-STEP:v1":
    sys.exit("this is not the LANE-STEP block: marker=%r" % fields["marker"])
emits = [v.strip() for v in fields["emits"].split("|")]
if any(not v for v in emits):
    sys.exit("empty value in emits: %r" % fields["emits"])
print(" ".join(emits))
print(fields["absent"])
PY
  if [ $? -ne 0 ]; then
    fail 'the LANE-STEP spec block parses' "$( cat "$TMP/err" )"
  else
    pass 'the LANE-STEP spec block parses'

    lane_emits=$( sed -n 1p "$TMP/lane-step-keys" )
    if [ "$lane_emits" = 'success gate-red blocked-on' ]; then
      pass 'a step emits exactly success / gate-red / blocked-on, in order'
    else
      fail 'a step emits exactly success / gate-red / blocked-on, in order' \
           "got: $lane_emits" \
           'a fourth emitted outcome is a vocabulary the reader of the line knows nothing about.'
    fi

    lane_absent=$( sed -n 2p "$TMP/lane-step-keys" )
    case " $lane_emits " in
      *' infra '*)
        fail 'infra is derived from absence and has no emission path' \
             "emits: $lane_emits" \
             'a step being OOM-killed cannot emit a line; an infra emission path is a promise nothing can keep.' ;;
      *)
        if [ "$lane_absent" = 'infra' ]; then
          pass 'infra is derived from absence and has no emission path'
        else
          fail 'infra is derived from absence and has no emission path' \
               "absent: ${lane_absent:-<none>}" \
               'the absence of the line IS the infra signal, and the block must say so.'
        fi ;;
    esac
  fi
fi

# --- executed: the parse rule, against the decoy corpus ---
#
# The rule under test, written once here, is the contract's: LAST line-anchored
# match, and it must be the final line (trailing blank lines tolerated — the
# `design-multi` precedent is deliberately tolerant of transport mangling).
# Exit 3 means NO VERDICT, which the reader reads as `infra`.
cat > "$TMP/lane-step-parse.py" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
while lines and not lines[-1].strip():
    lines.pop()
# Column 0 is enforced ONCE, by `match()` (which anchors at position 0). A
# leading `^` here as well would be redundant, and a redundant anchor is
# unkillable: with both present, `inline-marker-transcript.txt` stays green
# under either mutation alone, so neither clause is load-bearing. One anchor,
# and swapping it for `search()` turns that fixture red.
token = re.compile(r"LANE-STEP:v(\d+)((?:\s+[A-Za-z_][A-Za-z0-9_]*=\S+)+)\s*$")
hits = [i for i, line in enumerate(lines) if token.match(line)]
if not hits:
    sys.exit(3)
i = hits[-1]
if i != len(lines) - 1:
    sys.exit(3)
print(lines[i].strip())
PY

lane_decoy="$LANE_STEP_FIXTURES/decoy-transcript.txt"
if [ ! -f "$lane_decoy" ]; then
  fail 'the decoy transcript fixture exists' "no such file: $lane_decoy"
else
  got=$( "$MARKER_PY" "$TMP/lane-step-parse.py" "$lane_decoy" 2>"$TMP/err" )
  want='LANE-STEP:v1 step=build outcome=success slices=3/3 commits=3'
  if [ "$got" = "$want" ]; then
    pass 'the parse rule returns the real last line, not the prose or the fenced example'
  else
    fail 'the parse rule returns the real last line, not the prose or the fenced example' \
         "got:  ${got:-<no verdict>}" \
         "want: $want" \
         'first-match, or match-anywhere, returns the model'\''s own explanation of the marker.'
  fi
fi

lane_trailing="$LANE_STEP_FIXTURES/trailing-prose-transcript.txt"
if [ ! -f "$lane_trailing" ]; then
  fail 'the trailing-prose transcript fixture exists' "no such file: $lane_trailing"
else
  got=$( "$MARKER_PY" "$TMP/lane-step-parse.py" "$lane_trailing" 2>"$TMP/err" )
  rc=$?
  if [ "$rc" -eq 3 ] && [ -z "$got" ]; then
    pass 'a marker followed by more prose is NO VERDICT, so absence still means infra'
  else
    fail 'a marker followed by more prose is NO VERDICT, so absence still means infra' \
         "rc=$rc got: ${got:-<none>}" \
         'dropping the final-line requirement lets a model'\''s afterthought report success.'
  fi
fi

# The marker must start the line. This is the shape the contract's `position:`
# clause exists for and the only one the other two fixtures cannot see: a model
# narrating the marker mid-sentence on its LAST line satisfies both `take the
# last match` and `it is the final line`. Anchoring is what rejects it, and the
# embedded marker says `gate-red`, so a rule that accepts it does not merely
# return different text — it reports the wrong verdict for a step that passed
# no gate. Anchoring lives in exactly one place, `token.match()`; swapping it
# for `token.search()` turns this assertion red and leaves the other six green.
lane_inline="$LANE_STEP_FIXTURES/inline-marker-transcript.txt"
if [ ! -f "$lane_inline" ]; then
  fail 'the inline-marker transcript fixture exists' "no such file: $lane_inline"
else
  got=$( "$MARKER_PY" "$TMP/lane-step-parse.py" "$lane_inline" 2>"$TMP/err" )
  rc=$?
  if [ "$rc" -eq 3 ] && [ -z "$got" ]; then
    pass 'a marker embedded in prose on the final line is NO VERDICT, not a gate-red'
  else
    fail 'a marker embedded in prose on the final line is NO VERDICT, not a gate-red' \
         "rc=$rc got: ${got:-<none>}" \
         'an unanchored match reads the model'\''s narration as the step'\''s own verdict.'
  fi
fi

# The marker must END the line. This is the shape the contract's `position:`
# clause means by "nothing after it", and it is ADR-004's second mitigation:
# give the token a shape that does not occur in prose ABOUT it. A model that
# starts the line correctly, on the last line, and then appends an aside after
# the attributes satisfies last-match, final-line AND column 0 — the other
# three fixtures are all blind to it. The trailing `\s*$` is what rejects it;
# drop that clause and the parser hands the reader the whole line, aside and
# all, as the step's verdict: a "success" whose attribute list ends in
# unparseable prose. Dropping it turns this assertion red and leaves the other
# seven green.
lane_same_line="$LANE_STEP_FIXTURES/same-line-prose-transcript.txt"
if [ ! -f "$lane_same_line" ]; then
  fail 'the same-line-prose transcript fixture exists' "no such file: $lane_same_line"
else
  got=$( "$MARKER_PY" "$TMP/lane-step-parse.py" "$lane_same_line" 2>"$TMP/err" )
  rc=$?
  if [ "$rc" -eq 3 ] && [ -z "$got" ]; then
    pass 'a marker with prose appended after the attributes is NO VERDICT, not a success'
  else
    fail 'a marker with prose appended after the attributes is NO VERDICT, not a success' \
         "rc=$rc got: ${got:-<none>}" \
         'without the end-of-line clause the model'\''s aside is returned as part of the verdict.'
  fi
fi

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
