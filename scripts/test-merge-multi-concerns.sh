#!/bin/sh
# Oracle for XL-27 slice 7 — /merge-multi rules each unit's concerns from its
# OWN HEAD COMMIT before merging, and refuses on anything but outcome=pass.
#
# Two halves:
#
#   1. EXECUTABLE — merge-multi.md's own fenced command block (Step 1b) is
#      extracted verbatim, its two placeholders (<sha>, <path>) substituted,
#      and run for real in a throwaway git repo against unit branches this
#      suite builds. This is the lesson from slices 2-6: a presence-only check
#      on prose lets an inverted meaning (e.g. reading the working tree
#      instead of the head) pass silently. Running the actual block is the
#      only oracle that cannot be fooled by wording.
#
#   2. SEAM — merge-multi.md is parsed for ORDER (the concerns check precedes
#      the merge step) and for the refusal mapping, and mutated copies (never
#      the tracked file) are run back through the same parser to prove each
#      assertion is load-bearing.
#
# Run locally: sh scripts/test-merge-multi-concerns.sh

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/.." && pwd )
PLUGIN="$ROOT/plugins/bett3r-ai-workflow"
MERGE_MULTI_MD="$PLUGIN/commands/merge-multi.md"
MARKER_PY=${MARKER_PY:-python3}

TMP=$( mktemp -d "${TMPDIR:-/tmp}/merge-multi-concerns-test.XXXXXX" ) || exit 1
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

# ---------------------------------------------------------------------------
printf '\nSeam — /merge-multi rules each unit'"'"'s concerns from its own head, before merging (XL-27 slice 7)\n\n'
# ---------------------------------------------------------------------------

# --- extract Step 1b's fenced sh block, anchored on the concerns-check
# --decisions line, which is unique to this one block in the whole file ---
BLOCK_RAW="$TMP/block-raw.sh"
awk '
  /^```sh$/ { buf=""; capturing=1; next }
  capturing && /^```$/ {
    if (buf ~ /concerns-check --decisions/) { printf "%s", buf; found=1 }
    capturing=0; buf=""; next
  }
  capturing { buf = buf $0 "\n" }
  END { if (!found) exit 1 }
' "$MERGE_MULTI_MD" > "$BLOCK_RAW"
if [ ! -s "$BLOCK_RAW" ]; then
  fail 'merge-multi.md Step 1b'\''s concerns fenced sh block is extractable' \
       'no fenced ```sh block containing `concerns-check --decisions` found'
else
  pass 'merge-multi.md Step 1b'\''s concerns fenced sh block is extractable'
fi

# Fail loudly if the substitution grammar this test depends on (the literal
# placeholders <sha>, <run-id>, <unit-id>, and the $DOCS folder the block
# resolves) has drifted — a silent block edit here must not quietly stop
# testing anything.
if grep -qF '<sha>:$DOCS/concerns.md' "$BLOCK_RAW" && grep -qF '<sha>:$DOCS/decisions.md' "$BLOCK_RAW" \
   && grep -qF '.work/multi/<run-id>/units/<unit-id>.state.yaml' "$BLOCK_RAW"; then
  pass 'the block'\''s substitution grammar (<sha>, <run-id>, <unit-id>, $DOCS) is intact'
else
  fail 'the block'\''s substitution grammar (<sha>, <run-id>, <unit-id>, $DOCS) is intact' \
       'expected literal <sha>:$DOCS/concerns.md, <sha>:$DOCS/decisions.md and .work/multi/<run-id>/units/<unit-id>.state.yaml in the extracted block:' \
       "$( cat "$BLOCK_RAW" )"
fi

# --- build a throwaway repo with unit branches at a fixed work-docs path ---
REPO="$TMP/repo"
mkdir -p "$REPO"
# The branch is named explicitly: an ambient `init.defaultBranch` (say
# `trunk`) must not change which commit every unit branch is cut from.
git -C "$REPO" init -q -b master
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test
git -C "$REPO" commit -q --allow-empty -m 'root'

UNIT_PATH="docs/prs/UNIT-1"

write_unit(){
  # write_unit <branch> <concerns-content-or-none> <decisions-content-or-none> [path]
  branch=$1; concerns=$2; decisions=$3; wpath=${4:-$UNIT_PATH}
  # Every unit is cut from the root commit on master, never stacked on the
  # previous unit: a stacked unit inherits its sibling's concerns.md, and the
  # "no concerns.md" case then tests a file that is present.
  if ! git -C "$REPO" checkout -q -b "$branch" master; then
    fail "fixture: unit branch $branch is cut from master" 'git checkout -b failed; every outcome below would be meaningless'
    exit 1
  fi
  mkdir -p "$REPO/$wpath"
  if [ "$concerns" != "NONE" ]; then
    printf '%s' "$concerns" > "$REPO/$wpath/concerns.md"
    git -C "$REPO" add "$wpath/concerns.md"
  fi
  if [ "$decisions" != "NONE" ]; then
    printf '%s' "$decisions" > "$REPO/$wpath/decisions.md"
    git -C "$REPO" add "$wpath/decisions.md"
  fi
  git -C "$REPO" commit -q -m "unit $branch" --allow-empty
}

ALL_MET='## C1 — must not lose data
bar: hard
raisedBy: owner · step: design
quote: "must not lose data"
why: it matters
verify: check it
verdict: met
evidence: verified in review
'

HARD_UNMET='## C1 — must not lose data
bar: hard
raisedBy: owner · step: design
quote: "must not lose data"
why: it matters
verify: check it
verdict: unmet
evidence: not addressed
'

MALFORMED='## C1 not a real header
this is not the entry grammar at all
'

WAIVED_FAKE_D='## C1 — must not lose data
bar: hard
raisedBy: owner · step: design
quote: "must not lose data"
why: it matters
verify: check it
verdict: waived
evidence: waived, see decisions.md#D7
'

EMPTY=''

# a) all met -> merge allowed
write_unit unit-all-met "$ALL_MET" NONE
sha_all_met=$( git -C "$REPO" rev-parse unit-all-met )

# b) hard unmet -> refuse
write_unit unit-hard-unmet "$HARD_UNMET" NONE
sha_hard_unmet=$( git -C "$REPO" rev-parse unit-hard-unmet )

# c) malformed -> refuse (error)
write_unit unit-malformed "$MALFORMED" NONE
sha_malformed=$( git -C "$REPO" rev-parse unit-malformed )

# d) waived citing a D-entry that does not exist in decisions.md -> refuse
write_unit unit-fake-waiver "$WAIVED_FAKE_D" "## D1 — an unrelated decision
kind: deviation
step: build · slice: 1 · decidedBy: executor
sources: [none]
rejected: —
supersedes: —
unrelated body
"
sha_fake_waiver=$( git -C "$REPO" rev-parse unit-fake-waiver )

# d2) waived citing a real, human-decided waiver record — for a DIFFERENT
# concern (C2) -> refuse
WAIVED_D1='## C1 — must not lose data
bar: hard
raisedBy: owner · step: design
quote: "must not lose data"
why: it matters
verify: check it
verdict: waived
evidence: waived, see decisions.md#D1
'
write_unit unit-foreign-waiver "$WAIVED_D1" '## D1 — waive C2
kind: waiver
step: build · slice: — · decidedBy: human
sources: [human]
rejected: —
supersedes: —
The owner said "C2 can wait".
'
sha_foreign_waiver=$( git -C "$REPO" rev-parse unit-foreign-waiver )

# e) no concerns.md at head -> refuse
write_unit unit-no-concerns NONE NONE
sha_no_concerns=$( git -C "$REPO" rev-parse unit-no-concerns )

# f) empty committed concerns.md -> allowed
write_unit unit-empty "$EMPTY" NONE
sha_empty=$( git -C "$REPO" rev-parse unit-empty )

# h) a unit whose run.yaml id (UNIT-2) names a folder that IS all-met at its
# head — but whose state file records no work_item. A block that fell back to
# units[].id would pass it; the state file is the only source, so it refuses.
write_unit unit-two "$ALL_MET" NONE docs/prs/UNIT-2
sha_unit2=$( git -C "$REPO" rev-parse unit-two )

# The orchestrator checkout's run dir: one state file per unit, as each lane
# writes it (`work_item:` copied from its own /start's .work/mode.yaml).
# Untracked, like the real `.work/` — git show never sees it.
STATE_DIR="$REPO/.work/multi/multi-test/units"
mkdir -p "$STATE_DIR"
printf 'step: done\nstatus: passed\nwork_item: UNIT-1   # copied from .work/mode.yaml\n' > "$STATE_DIR/unit-a.state.yaml"
printf 'step: done\nwork_item: "UNIT-1"\n' > "$STATE_DIR/unit-quoted.state.yaml"
printf 'step: done\nstatus: passed\n' > "$STATE_DIR/UNIT-2.state.yaml"
printf 'work_item:\nstep: done\n' > "$STATE_DIR/unit-empty-key.state.yaml"

# g) working tree differs from head: head is met, working tree (uncommitted)
# is unmet -> must pass on the HEAD content; a block reading the checkout on
# disk would print outcome=fail here instead.
write_unit unit-worktree-drift "$ALL_MET" NONE
sha_worktree_drift=$( git -C "$REPO" rev-parse unit-worktree-drift )
git -C "$REPO" checkout -q unit-worktree-drift
printf '%s' "$HARD_UNMET" > "$REPO/$UNIT_PATH/concerns.md"   # uncommitted, working-tree only

run_block(){
  # run_block <sha> -> the block's whole output, for the unit named $UNIT_ID
  sha=$1
  sed -e "s|<sha>|$sha|g" -e "s|<run-id>|multi-test|g" -e "s|<unit-id>|$UNIT_ID|g" "$BLOCK_RAW" > "$TMP/run.sh"
  ( cd "$REPO" && PATH="$PLUGIN/bin:$PATH" sh "$TMP/run.sh" ) 2>&1
}

check_outcome(){
  # check_outcome <sha> <outcome> <reason|-> <label>
  # Asserts on the LAST line only (the verdict line, ADR-004), token-exact:
  # `outcome=<outcome>` and, when <reason> is not `-`, `reason=<reason>`; when
  # it is `-`, the line must carry no reason token at all. Matching only the
  # outcome let a fixture built wrong (a unit that DID contain concerns.md)
  # pass the "no concerns.md" case for the wrong reason.
  out=$( run_block "$1" )
  last=$( printf '%s\n' "$out" | tail -1 )
  ok=1
  case "$last" in "CONCERNS-CHECK:v1 "*) ;; *) ok=0 ;; esac
  case " $last " in *" outcome=$2 "*) ;; *) ok=0 ;; esac
  if [ "$3" = "-" ]; then
    case " $last " in *" reason="*) ok=0 ;; esac
  else
    case " $last " in *" reason=$3 "*) ;; *) ok=0 ;; esac
  fi
  if [ "$ok" -eq 1 ]; then
    pass "$4"
  else
    fail "$4" "expected a last line CONCERNS-CHECK:v1 … outcome=$2 (reason: $3) for sha $1" "got: $out"
  fi
}

check_refused(){
  # check_refused <sha> <label> — the unit's work item did not resolve: the
  # block ran no concerns-check (no CONCERNS-CHECK line, which the mapping
  # refuses) and its last line says refuse.
  out=$( run_block "$1" )
  if printf '%s\n' "$out" | grep -q '^CONCERNS-CHECK:'; then
    fail "$2" 'expected no CONCERNS-CHECK line (the work item must not resolve)' "got: $out"
  elif printf '%s\n' "$out" | tail -1 | grep -q 'refuse'; then
    pass "$2"
  else
    fail "$2" 'expected a last line saying refuse' "got: $out"
  fi
}

UNIT_ID=unit-a
check_outcome "$sha_all_met"        pass  -                   'a unit whose committed concerns.md is all met -> merge allowed (outcome=pass, no reason)'
check_outcome "$sha_hard_unmet"     fail  hard-unmet          'a unit with an unmet hard concern -> refused (outcome=fail reason=hard-unmet)'
check_outcome "$sha_malformed"      error malformed-header    'a unit whose concerns.md is malformed -> refused (outcome=error reason=malformed-header)'
check_outcome "$sha_fake_waiver"    error waiver-record-missing 'a unit waiving via a D-entry absent from its decisions.md -> refused (outcome=error reason=waiver-record-missing, proves --decisions is passed)'
check_outcome "$sha_foreign_waiver" error waiver-record-other-concern 'a unit waiving via a human D-entry that waives a DIFFERENT concern -> refused (outcome=error reason=waiver-record-other-concern)'
check_outcome "$sha_no_concerns"    error file-not-found      'a unit with no concerns.md at its head -> refused (outcome=error reason=file-not-found)'
check_outcome "$sha_empty"          pass  -                   'a unit with an empty committed concerns.md -> allowed (outcome=pass, no reason)'
check_outcome "$sha_worktree_drift" pass  -                   'the block reads the unit HEAD, not the working tree (head is all-met -> pass despite an uncommitted unmet copy)'

UNIT_ID=unit-quoted
check_outcome "$sha_all_met"        pass  -                   'a quoted work_item: in the state file resolves the same folder -> pass'
UNIT_ID=unit-ghost
check_refused "$sha_all_met" 'a unit with no state file -> refused, no concerns-check run'
UNIT_ID=UNIT-2
check_refused "$sha_unit2"   'a state file with no work_item: -> refused, although units[].id (UNIT-2) names an all-met folder at the head (no fallback)'
UNIT_ID=unit-empty-key
check_refused "$sha_all_met" 'an empty work_item: -> refused'

# ---------------------------------------------------------------------------
printf '\nSeam — merge-multi.md: ORDER, the refusal mapping, and mutation controls\n\n'
# ---------------------------------------------------------------------------

first_line(){ grep -nF -e "$2" "$1" | head -1 | cut -d: -f1; }

check_seams(){
  # check_seams <file> -> emits ok|bad lines, same protocol as slice 6's parser
  "$MARKER_PY" - "$1" <<'PYMM'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
lines = text.splitlines()
out = []
def check(ok, label, detail=""):
    out.append(("ok" if ok else "bad") + "|" + label + "|" + detail.replace("|", "/").replace("\n", " "))

def first(needle):
    for i, l in enumerate(lines, 1):
        if needle in l:
            return i
    return None

# ORDER: the concerns check (Step 1b) precedes the merge step (Step 2).
step1b = first('1b — Rule each unit')
step2 = first('2 — Merge into integration')
check(step1b is not None and step2 is not None and step1b < step2,
      "ORDER: Step 1b (rule concerns) precedes Step 2 (merge into integration)",
      "1b=%s 2=%s" % (step1b, step2))

# The refusal mapping: a bullet list `- `outcome=<o>` → ... unit.` naming each
# outcome exactly once, mapping pass -> merge and fail|error -> refuse.
MAP = re.compile(r"^- `outcome=([a-z-]+)`.*\b(merge|refuse)\b")
pairs = []
for l in lines:
    m = MAP.match(l.strip())
    if m:
        pairs.append((m.group(1), m.group(2)))
outcomes = sorted(o for o, _ in pairs)
check(outcomes == ["error", "fail", "pass"],
      "refusal mapping names each of pass/fail/error exactly once",
      "got: %s" % pairs)
check(dict(pairs).get("pass") == "merge" and dict(pairs).get("fail") == "refuse"
      and dict(pairs).get("error") == "refuse" and len(pairs) == 3,
      "refusal mapping is exactly pass -> merge, fail -> refuse, error -> refuse",
      "got: %s" % pairs)

# Missing verdict line -> refuse: checked below, on the bullet's own sentence
# (a file-wide `.*refuse` under re.S matched any later "refuse" and passed
# `- No verdict line at all → merge the unit.`).

# A missing concerns.md at the unit head -> refusal, not "no concerns".
flat_mc = re.sub(r"\s+", " ", text)
check(bool(re.search(r"missing `concerns\.md` at the unit head is a refusal, not", flat_mc)),
      "a missing concerns.md at the unit head is stated as a refusal, not 'no concerns'")

# No sentence trusts the flow/concerns status to decide the merge. The file
# never uses the word "trust" today (grepped at design time), so ANY sentence
# pairing "trust" with "flow/concerns status" is new and wrong.
flat = re.sub(r"\s+", " ", text.replace("**", ""))
trust = re.findall(r"[^.]*\btrust\w*\b[^.]*\bflow/concerns\b[^.]*\.|[^.]*\bflow/concerns\b[^.]*\btrust\w*\b[^.]*\.", flat, re.I)
check(not trust, "no sentence trusts the flow/concerns status to decide the merge", " || ".join(trust))

# Sentence-splitting rule used by every sentence guard below: the file is cut
# into blocks on blank lines; within a block `**` is removed and all
# whitespace (newlines included) collapses to one space; the block is then
# split after `.`, `!` or `?` followed by whitespace. So `concerns.md` never
# splits (no space after its dot) and a heading or list item separated by a
# blank line is its own sentence.
def sentences(t):
    res = []
    for block in re.split(r"\n\s*\n", t):
        b = re.sub(r"\s+", " ", block.replace("**", "")).strip()
        if b:
            res.extend(s for s in re.split(r"(?<=[.!?])\s+", b) if s)
    return res

def section(start_needle, end_needle):
    s = first(start_needle)
    e = first(end_needle)
    if s is None or e is None or e <= s:
        return None
    return "\n".join(lines[s - 1:e - 1])

all_sentences = sentences(text)

# Every sentence naming flow/concerns carries a word that keeps it advisory.
# Keyed on the SENTENCE, not on a forbidden word: "If the flow/concerns status
# is success, skip the check and merge." never says "trust".
FC_OK = re.compile(r"\b(advisory|never|not|display)\b", re.I)
fc_bad = [s for s in all_sentences if "flow/concerns" in s and not FC_OK.search(s)]
check(not fc_bad,
      "every sentence mentioning flow/concerns contains advisory|never|not|display",
      " || ".join(fc_bad))

# Dependents: a refused unit's stacked dependents are refused too — pinned on
# the actual sentence, and no sentence about stacked units / dependents may
# let them merge past a refusal (an ADDED sentence keeps the pins intact).
check("A refusal blocks its dependents" in flat
      and "refuse every unit stacked (directly or transitively) on a refused one" in flat,
      "Step 1b states a refused unit blocks its dependents",
      "pinned: 'A refusal blocks its dependents' + 'refuse every unit stacked (directly or transitively) on a refused one'")
DEP = re.compile(r"\b(stacked|dependents?)\b", re.I)
DEP_BAD = re.compile(r"\banyway\b|\bnot block|\bstill merge|\bmerge them\b", re.I)
dep_bad = [s for s in all_sentences if DEP.search(s) and DEP_BAD.search(s)]
check(not dep_bad,
      "no sentence about stacked units or dependents lets them merge past a refusal",
      " || ".join(dep_bad))

# Every path that merges a unit head re-rules that exact head.
step2_text = section("2 — Merge into integration", "3 — Run the full gate")
step3_text = section("3 — Run the full gate", "4 — Collect the closing keywords")
# CLOSED SETS. Keyword heuristics admit rewrites that undo a rule ("Its
# children land regardless." names no forbidden word), so each rule-bearing
# family of sentences is compared, as a set, with an exact pinned list, using
# the sentence-splitting rule above. Any extra, missing or edited sentence
# fails; the detail prints the offender and, for an edit, a word diff against
# the nearest pinned sentence. A line reflow is not an edit (whitespace
# collapses); a changed character, backticks included, is.
import difflib

def word_diff(pinned, found):
    return "DIFF: " + " ".join(d for d in difflib.ndiff(pinned.split(" "), found.split(" "))
                               if d[:2] in ("- ", "+ "))

def closed_set(label, found, pinned):
    extra = [s for s in found if s not in pinned]
    missing = [s for s in pinned if s not in found]
    notes = []
    for m in missing:
        near = difflib.get_close_matches(m, extra, n=1, cutoff=0.6)
        if near:
            notes.append("EDITED: " + near[0] + " :: " + word_diff(m, near[0]))
            extra.remove(near[0])
        else:
            notes.append("MISSING: " + m)
    notes += ["EXTRA: " + s for s in extra]
    check(not notes and len(found) == len(pinned), label, " || ".join(notes))



# 3. Step 2's whole moved-head sentence, verbatim.
STEP2_MOVED = "Merge exactly the head sha Step 1b ruled (`gh pr merge <n> --match-head-commit <sha>`, or `git merge <sha>` in the integration worktree), never whatever the branch points at now: if the head has moved since that ruling, re-run Step 1b at the new head sha and refuse on anything but `outcome=pass`."
s2 = sentences(step2_text or "")
if STEP2_MOVED in s2:
    check(True, "Step 2 merges exactly the head sha Step 1b ruled — the whole moved-head sentence, verbatim")
else:
    near = difflib.get_close_matches(STEP2_MOVED, s2, n=1, cutoff=0.5)
    check(False, "Step 2 merges exactly the head sha Step 1b ruled — the whole moved-head sentence, verbatim",
          ("EDITED: " + near[0] + " :: " + word_diff(STEP2_MOVED, near[0])) if near else "MISSING: " + STEP2_MOVED)

# Missing verdict line -> refuse, on the bullet's own sentence only.
check(any(re.fullmatch(r"- No verdict line at all\b[^.→]*→ refuse the unit\.", s) for s in all_sentences),
      "a missing verdict line is stated as a refusal",
      "no sentence of the form `- No verdict line at all (…) → refuse the unit.`")


# 5. THE WHOLE FILE, as one closed MULTISET of (section, unit) pairs.
#
#    SECTION KEY. Scanning line by line, outside fenced blocks only, a new
#    section starts at (a) a markdown heading `#`, `##` or `###` — its key is
#    the heading text after the hashes — or (b) a bold step lead: a line that
#    opens with `**<N> — …**` (N digits with an optional letter, as in `1b`) —
#    its key is the text between the `**`, whitespace collapsed. Everything
#    before the first such line, the YAML front matter included, is keyed
#    `(preamble)`. The heading or step-lead line is itself a unit of its own
#    section. So the same sentence in another step is a different pair.
#
#    UNITS, within each section:
#    - FRONTMATTER: the leading `---` block, pinned like a fence.
#    - FENCE[<info>]: EVERY fenced block, the executed Step 1b block included
#      (the fixture still runs that block; this pins its text). Per line: runs
#      of spaces/tabs become one space, ends stripped; blank lines dropped;
#      lines joined with ` ⏎ `. Re-indenting is not a change; an added comment,
#      line or branch is.
#    - ROW: every table row (first non-blank character `|`), whitespace
#      collapsed — one row, one unit.
#    - every remaining prose sentence, by the sentence rule above. Fences and
#      rows are cut out first, each leaving a blank line.
#
#    Order within a section is not pinned. A failure names each offending pair:
#    MOVED (the same unit gone from one section and new in another), EDITED
#    (with a word diff against the nearest pinned unit), MISSING or EXTRA.
from collections import Counter

FENCE_ANY = re.compile(r"^```([^\n]*)\n(.*?)^```[ \t]*$", re.S | re.M)
EXECUTED_MARK = "concerns-check --decisions"
HEADING = re.compile(r"^#{1,3} (.+?)\s*$")
STEP_LEAD = re.compile(r"^\*\*(\d+[a-z]? — .+?)\*\*")

def norm_lines(body):
    out = []
    for line in body.split("\n"):
        line = re.sub(r"[ \t]+", " ", line).strip()
        if line:
            out.append(line)
    return " ⏎ ".join(out)

def split_sections(t):
    """[(key, text)] in document order; fences never start a section."""
    parts, key, buf, in_fence = [], "(preamble)", [], False
    for line in t.split("\n"):
        if line.startswith("```"):
            in_fence = not in_fence
        m = None if in_fence else (HEADING.match(line) or STEP_LEAD.match(line))
        if m and not line.startswith("```"):
            parts.append((key, "\n".join(buf)))
            key, buf = re.sub(r"\s+", " ", m.group(1)).strip(), []
        buf.append(line)
    parts.append((key, "\n".join(buf)))
    return parts

def section_units(body, executed):
    units = []
    def fence(m):
        if EXECUTED_MARK in m.group(2):
            executed[0] += 1
        units.append("FENCE[" + m.group(1).strip() + "]: " + norm_lines(m.group(2)))
        return "\n\n"
    body = FENCE_ANY.sub(fence, body)
    kept = []
    for line in body.split("\n"):
        if line.lstrip().startswith("|"):
            units.append("ROW: " + re.sub(r"\s+", " ", line).strip())
            kept.append("")
        else:
            kept.append(line)
    units.extend(sentences("\n".join(kept)))
    return units

def file_units(t):
    """([(section, unit)], executed_fence_count)."""
    pairs, executed = [], [0]
    fm = re.match(r"---\n(.*?)\n---[ \t]*\n", t, re.S)
    if fm:
        pairs.append(("(preamble)", "FRONTMATTER: " + norm_lines(fm.group(1))))
        t = t[fm.end():]
    for key, body in split_sections(t):
        pairs.extend((key, u) for u in section_units(body, executed))
    return pairs, executed[0]

def closed_sections(label, found, pinned):
    fc, pc = Counter(found), Counter(pinned)
    extra = list((fc - pc).elements())
    missing = list((pc - fc).elements())
    notes = []
    for m in list(missing):
        moved = next((e for e in extra if e[1] == m[1] and e[0] != m[0]), None)
        if moved:
            notes.append("MOVED: " + m[1] + " from [" + m[0] + "] to [" + moved[0] + "]")
            extra.remove(moved)
            missing.remove(m)
    for m in missing:
        same = [e[1] for e in extra if e[0] == m[0]]
        near = difflib.get_close_matches(m[1], same, n=1, cutoff=0.6)
        if near:
            e = (m[0], near[0])
            notes.append("EDITED in [" + m[0] + "]: " + near[0] + " :: " + word_diff(m[1], near[0]))
            extra.remove(e)
        else:
            notes.append("MISSING from [" + m[0] + "]: " + m[1])
    notes += ["EXTRA in [" + e[0] + "]: " + e[1] for e in extra]
    check(not notes, label, " || ".join(notes))

PINNED_FILE = [
    ["(preamble)", "FRONTMATTER: description: Land a finished fleet — merge each reviewed unit PR into the run's integration branch (conflicts resolved once), run the full gate there, and open the single integration PR to the default branch."],
    ["/merge-multi — land the fleet", "# /merge-multi — land the fleet"],
    ["/merge-multi — land the fleet", "`/start-multi` ends with N reviewable PRs open against the run's integration branch `int/<run-id>`, and nothing merged."],
    ["/merge-multi — land the fleet", "You review them at your own pace."],
    ["/merge-multi — land the fleet", "This command is the landing, run afterwards — in a fresh session."],
    ["/merge-multi — land the fleet", "Run it fresh; do not reopen the fleet conversation."],
    ["/merge-multi — land the fleet", "That session is the largest context in the run — it dispatched N lanes, collected N escalations, aggregated N state files — and re-invoking it to perform a mechanical merge sequence re-sends all of it."],
    ["/merge-multi — land the fleet", "Everything this command needs is on disk (`run.yaml`) or on GitHub (`gh pr view`)."],
    ["/merge-multi — land the fleet", "The bookkeeping is cheap; the memory is not."],
    ["Argument: $ARGUMENTS", "ROW: | Flag | Effect |"],
    ["Argument: $ARGUMENTS", "ROW: |---|---|"],
    ["Argument: $ARGUMENTS", "ROW: | `--dry-run` | Print the inventory (step 1), run step 1b's read-only ruling and report the would-refuse set, then stop. Merges nothing. |"],
    ["Argument: $ARGUMENTS", "ROW: | `--only <ids>` | Land a subset; the rest stay open against integration. |"],
    ["Argument: $ARGUMENTS", "ROW: | `--land` | Also merge the integration PR into the default branch (step 6). **Off by default** — that is the last irreversible act. |"],
    ["Argument: $ARGUMENTS", "## Argument: $ARGUMENTS Optional run-id."],
    ["Argument: $ARGUMENTS", "Default: the most recent run in `.work/multi/` for this repo."],
    ["Why an integration branch at all", "## Why an integration branch at all"],
    ["Why an integration branch at all", "Each unit branch is cut from `int/<run-id>`, and each unit PR's base is `int/<run-id>`."],
    ["Why an integration branch at all", "That buys three things at once, and they are otherwise in tension:"],
    ["Why an integration branch at all", "- Reviews stay per-unit."],
    ["Why an integration branch at all", "A unit PR's diff against integration is exactly that unit's work — no sibling noise."],
    ["Why an integration branch at all", "- Conflicts are resolved once."],
    ["Why an integration branch at all", "Inter-unit conflicts surface when units merge into integration, and are resolved *there*, as merge commits."],
    ["Why an integration branch at all", "Merging the units individually into the default branch instead would resolve the same conflicts a second time, against a moving target."],
    ["Why an integration branch at all", "- The full gate runs once."],
    ["Why an integration branch at all", "Cross-unit breakage exists only on the assembled tree, so no per-unit gate can see it — and running the full gate N times to look for something structurally invisible to it is the fleet's most wasteful step."],
    ["Why an integration branch at all", "Units run `--fast`; integration runs `--full`."],
    ["Steps", "## Steps"],
    ["1 — Inventory. Report; do not act.", "FENCE[sh]: gh pr view <n> --json number,title,state,baseRefName,headRefName,headRefOid,mergeable,mergeStateStatus,reviewDecision"],
    ["1 — Inventory. Report; do not act.", "1 — Inventory."],
    ["1 — Inventory. Report; do not act.", "Report; do not act."],
    ["1 — Inventory. Report; do not act.", "Read `.work/multi/<run-id>/run.yaml` for the unit set, the wave order, and the integration branch."],
    ["1 — Inventory. Report; do not act.", "`git fetch origin`."],
    ["1 — Inventory. Report; do not act.", "Then, per unit, read the real state from GitHub rather than from `run.yaml` — the state file was written before review:"],
    ["1 — Inventory. Report; do not act.", "Print one row per unit and stop on any of these, naming the unit:"],
    ["1 — Inventory. Report; do not act.", "- Base is not `int/<run-id>`."],
    ["1 — Inventory. Report; do not act.", "Do not merge it."],
    ["1 — Inventory. Report; do not act.", "A PR merged into the wrong target returns exit 0, shows `MERGED`, and delivers nothing where you meant it — the merge itself reports success, so this is the one precondition with no downstream tell."],
    ["1 — Inventory. Report; do not act.", "Retarget (`gh pr edit <n> --base int/<run-id>`) or exclude the unit."],
    ["1 — Inventory. Report; do not act.", "- State is already `MERGED`."],
    ["1 — Inventory. Report; do not act.", "Skip it — this command is idempotent and re-running after a partial land is the expected path."],
    ["1 — Inventory. Report; do not act.", "- `reviewDecision` is `CHANGES_REQUESTED`."],
    ["1 — Inventory. Report; do not act.", "Stop; that is the human's outstanding objection."],
    ["1 — Inventory. Report; do not act.", "- The unit never reached `passed` in `run.yaml`, or has no PR."],
    ["1 — Inventory. Report; do not act.", "`--dry-run` continues into step 1b, because that ruling is read-only and is exactly what a dry run exists to show: it reports the would-refuse set (each refused unit with its verdict line, plus its stacked dependents) and stops before step 2."],
    ["1 — Inventory. Report; do not act.", "The two steps act differently on purpose: a finding above acts on the unit it names, as its bullet says — skip it, retarget or exclude it, or stop on the human's outstanding objection — while a step-1b refusal removes that unit and its stacked dependents from the landing, and the rest proceed."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "FENCE[sh]: STATE=\".work/multi/<run-id>/units/<unit-id>.state.yaml\" ⏎ WORK_ITEM=$(sed -n 's/^work_item:[[:space:]]*//p' \"$STATE\" 2>/dev/null | head -n 1 \\ ⏎ | sed -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' -e \"s/^[\\\"']\\(.*\\)[\\\"']$/\\1/\") ⏎ DOCS= ⏎ [ -n \"$WORK_ITEM\" ] && DOCS=$(work-docs-path --item \"$WORK_ITEM\" | tail -n 1 \\ ⏎ | sed -n 's/^WORK-DOCS-PATH:v1 outcome=ok .* path=\\([^ ]*\\) .*$/\\1/p') ⏎ if [ -z \"$DOCS\" ]; then ⏎ echo \"unit <unit-id>: refuse — no work_item in $STATE, or work-docs-path did not resolve it\" ⏎ else ⏎ TMP=$(mktemp -d) ⏎ git show \"<sha>:$DOCS/concerns.md\" > \"$TMP/concerns.md\" 2>/dev/null || rm -f \"$TMP/concerns.md\" ⏎ git show \"<sha>:$DOCS/decisions.md\" > \"$TMP/decisions.md\" 2>/dev/null || rm -f \"$TMP/decisions.md\" ⏎ concerns-check --decisions \"$TMP/decisions.md\" \"$TMP/concerns.md\" ⏎ fi"],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "1b — Rule each unit's concerns, before merging it."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "Never the `flow/concerns` status."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "`/verify-build` posted a `flow/concerns` commit status on each unit's head, but that status is advisory only (a private free-plan repo cannot make it required) and a human can merge over a red one."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "This command is the hard block (design F4/C2): before merging a unit (step 2), rule it yourself, from files taken off *its own head commit* — never the working tree, never a sibling's checkout, and never by reading the GitHub status back."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "The unit's work-docs folder comes from its lane's own record: read `work_item:` from `.work/multi/<run-id>/units/<unit-id>.state.yaml` — the exact value the unit's lane copied from its `/start`'s `.work/mode.yaml` — and resolve it with `work-docs-path --item <work_item>`."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "The state file is found by the unit's `units[].id`, which is not itself the work item."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "A missing state file, a missing or empty `work_item:`, or a `work-docs-path` verdict other than `outcome=ok` refuses the unit: the block below then runs no `concerns-check` and prints no verdict line."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "Never fall back to `run.yaml`'s `units[].id` as the work item."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "`<sha>` is the head sha step 1's inventory already read (`headRefOid`)."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "Read the last line, `CONCERNS-CHECK:v1 outcome=pass|fail|error …`, never the exit code (ADR-004)."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "The mapping is exactly this, each outcome named once:"],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "- `outcome=pass` → merge the unit."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "- `outcome=fail` → refuse the unit."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "- `outcome=error` → refuse the unit."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "This is not-success exactly like `fail` — a malformed file, a fabricated or foreign waiver citation, or a corrupt `decisions.md` never reads as a pass or as \"no concerns\"."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "- No verdict line at all (the command produced nothing, died before printing one, or never ran because the unit's work item did not resolve) → refuse the unit."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "A missing `concerns.md` at the unit head is a refusal, not \"no concerns\"."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "`/verify-build` always commits the file, empty when the unit raised none, so `git show` failing to find it at that sha means that unit's `/verify-build` did not complete — and the `git show` above already reproduces that: with no file written to `$TMP/concerns.md`, `concerns-check` itself returns `outcome=error reason=file-not-found`, which the mapping above already refuses."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "A missing `decisions.md` is not by itself a refusal — `concerns-check` only reads it when a concern is waived, exactly the behaviour `/verify-build` already relies on; an absent one simply means this unit raised no waiver."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "Report a refused unit by id, with the verdict line, and do not merge it; that same line goes into the integration PR body under step 4's `declared − landed` heading, as the reason the unit did not land."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "A refusal blocks its dependents: a stacked child's branch is cut from its parent's tip (`/start-multi` step 2), so merging the child without the parent already in `int/<run-id>` would deliver the parent's unruled work into integration by the back door — refuse every unit stacked (directly or transitively) on a refused one, and say so."],
    ["1b — Rule each unit's concerns, before merging it. Never the `flow/concerns` status.", "Units in other waves with no dependency on the refused one are unaffected and still merge."],
    ["2 — Merge into integration, in dependency order.", "FENCE[]: ## D<n> — <title> ⏎ kind: silent-seam # false-premise | silent-seam | deviation | shipped-finding | overruled | waiver ⏎ step: merge-multi · slice: — · decidedBy: orchestrator ⏎ sources: [code:<symbol> (<file>), adr:ADR-NNN, design:<section>, xp:<atom-id>, human] ⏎ rejected: <option> — <why not> ⏎ supersedes: — # set when this overturns an earlier entry"],
    ["2 — Merge into integration, in dependency order.", "2 — Merge into integration, in dependency order."],
    ["2 — Merge into integration, in dependency order.", "Follow `run.yaml`'s waves — a stacked child after its parent."],
    ["2 — Merge into integration, in dependency order.", "Merge each unit PR into `int/<run-id>`."],
    ["2 — Merge into integration, in dependency order.", "Merge exactly the head sha Step 1b ruled (`gh pr merge <n> --match-head-commit <sha>`, or `git merge <sha>` in the integration worktree), never whatever the branch points at now: if the head has moved since that ruling, re-run Step 1b at the new head sha and refuse on anything but `outcome=pass`."],
    ["2 — Merge into integration, in dependency order.", "A stacked child's PR targets its parent's branch, so `gh pr edit <n> --base int/<run-id>` before merging it — merged in place it reports MERGED and delivers nothing to integration — and delete no unit branch while a PR still targets it: deleting a base closes the child unmerged ([verify-build](./verify-build.md) step 6)."],
    ["2 — Merge into integration, in dependency order.", "Resolve conflicts in the integration worktree, as merge commits."],
    ["2 — Merge into integration, in dependency order.", "Never by rewriting a unit branch — the unit branch is the artifact the human reviewed and approved, and rebasing it invalidates that review silently."],
    ["2 — Merge into integration, in dependency order.", "Rules that apply to any merge in this flow apply here:"],
    ["2 — Merge into integration, in dependency order.", "- Generated / codegen files: `git checkout --theirs`, then re-run the generator."],
    ["2 — Merge into integration, in dependency order.", "Never hand-merge them."],
    ["2 — Merge into integration, in dependency order.", "- Hand-authored additive files: splice complete units."],
    ["2 — Merge into integration, in dependency order.", "A marker-strip breaks on array tails and interleaves two partial blocks at their shared prefix."],
    ["2 — Merge into integration, in dependency order.", "- Check for `*.orig` residue before committing."],
    ["2 — Merge into integration, in dependency order.", "A `.ts.orig` is not compiled, so it passes every gate invisibly."],
    ["2 — Merge into integration, in dependency order.", "A pinned counter touched by N units is RECOMPUTED, never picked."],
    ["2 — Merge into integration, in dependency order.", "For any monotonic pin several units moved — tier counts, node-registry census, deployment-unit counts, topology ratchets — every branch's value is correct on its own base and wrong on the merged tree, so there is no side to take: `ours`/`theirs` ships a wrong pin the suite then *enforces*, surfacing as an authorization defect rather than a merge defect."],
    ["2 — Merge into integration, in dependency order.", "Write `base + Σ (each unit's delta measured against its own base)` — `run.yaml`'s step-8 report carries the addends — and verify by running the suite, which prints the received length, not by the merge being clean."],
    ["2 — Merge into integration, in dependency order.", "One fleet's correct value (704) appeared on no branch."],
    ["2 — Merge into integration, in dependency order.", "A clean merge does not discharge a cross-unit obligation."],
    ["2 — Merge into integration, in dependency order.", "Before merging, list every obligation the units recorded for the merge — `owesSiblings` in each `units/<id>.state.yaml`, and any PR-body \"for the <sibling> merge\" section."],
    ["2 — Merge into integration, in dependency order.", "Check each against the merged file whether or not git conflicted there, apply it on integration with a test that is red without it, and record it as a resolution like any conflict; an obligation with no matching resolution blocks step 5."],
    ["2 — Merge into integration, in dependency order.", "One was written three times — design, state file, PR body — and merged away cleanly with every gate green, because no unit's tests could reach the intersection."],
    ["2 — Merge into integration, in dependency order.", "Record every resolution as you make it — which units, which file, what was kept and what was dropped, and why."],
    ["2 — Merge into integration, in dependency order.", "This is the one part of what lands that nobody reviewed: the reviewer approved unit diffs, and what ships is those diffs *plus* your resolutions."],
    ["2 — Merge into integration, in dependency order.", "It goes in the integration PR body (step 5), which is the only section there allowed to be verbose, and as a `decisions.md` entry in the run-level folder below — the body keeps being written exactly as before; the entry is additive, not a replacement."],
    ["2 — Merge into integration, in dependency order.", "The run-level `decisions.md` is `<root>/<run-id>/decisions.md`, for every fleet run, resolved with `work-docs-path --item <run-id>` (`run.yaml`'s `runId:`) — never a hardcoded root."],
    ["2 — Merge into integration, in dependency order.", "It holds this command's own conflict resolutions only, since no single unit owns them."],
    ["2 — Merge into integration, in dependency order.", "`/design-multi` Phase B's cross-cutting policies are not restated there: each unit's committed `design.md` already carries its resolved design."],
    ["2 — Merge into integration, in dependency order.", "If `work-docs-path --item <run-id>` refuses (a hand-made run id, or one built from a unit id `work-docs-path` cannot carry, such as a Jira key with an underscore), write no run-level `decisions.md` entry: put its `WORK-DOCS-PATH:v1` verdict line in the integration PR body under *Conflict resolutions* instead, and continue merging."],
    ["2 — Merge into integration, in dependency order.", "`/merge-multi` is the file's single writer, allocating each `## D<n> — <title>` id the way `commands/build.md`'s *The committed record* does (one more than the highest id already in the file, read at the moment of the append) and never editing or removing an entry it did not just write, using the exact header grammar `concerns-check`'s docstring quotes back from `build.md`:"],
    ["3 — Run the full gate, once, on integration.", "3 — Run the full gate, once, on integration."],
    ["3 — Run the full gate, once, on integration.", "Per the [full-gate](../skills/full-gate/SKILL.md) skill: `node .claude/gate.mjs --full` (or the repo's `.claude/gate.sh`) on `int/<run-id>`, verdict read from the `GATE-STEP:` lines and baseline-diffed against the default branch."],
    ["3 — Run the full gate, once, on integration.", "Read that skill for the discovery order and the four ways a green read is wrong; do not re-derive them here."],
    ["3 — Run the full gate, once, on integration.", "They are all [EVIDENCE.md](../EVIDENCE.md) §1 — *a verdict is evidence only about what it actually executed* — and this is the one run in the whole fleet that certifies the assembled tree, so a misread here is unbacked by anything downstream."],
    ["3 — Run the full gate, once, on integration.", "The verdict names the ref it ran at and therefore which units it covers — the assembled tree covers every merged unit; a unit excluded with `--only` is not covered and is named as such."],
    ["3 — Run the full gate, once, on integration.", "A red gate is fixed on integration, not deferred."],
    ["3 — Run the full gate, once, on integration.", "If a failure traces cleanly to one unit and the fix is more than a line, push the fix to that unit's branch and re-merge — that keeps the unit PR an honest record of its own work."],
    ["3 — Run the full gate, once, on integration.", "A fix pushed to a unit branch changes its head: re-run Step 1b at the new head sha before re-merging, and refuse on anything but `outcome=pass`."],
    ["3 — Run the full gate, once, on integration.", "Otherwise fix on integration and name the unit in the commit message."],
    ["3 — Run the full gate, once, on integration.", "Do not open the integration PR over a red gate; an integration branch that looks landed and is red is the worst state this flow can produce, because the fleet is torn down and nobody owns it."],
    ["4 — Collect the closing keywords.", "4 — Collect the closing keywords."],
    ["4 — Collect the closing keywords.", "A PR merged into `int/<run-id>` does not close its issues."],
    ["4 — Collect the closing keywords.", "GitHub fires closing keywords only for PRs merged into the repository's default branch."],
    ["4 — Collect the closing keywords.", "Every `Closes #N` written into a unit PR body by `/verify-build` is therefore inert under this topology — well-formed, rendered as a cross-reference, and closing nothing."],
    ["4 — Collect the closing keywords.", "The failure has no tell anywhere: well-formed commits, PRs `MERGED`, gates green, and the only symptom is a backlog count nobody has a reason to read."],
    ["4 — Collect the closing keywords.", "So collect the union of issues referenced across every unit PR, and carry them into the integration PR body — one `closes` keyword per issue, repeated."],
    ["4 — Collect the closing keywords.", "`Closes #56, closes #62, closes #63`."],
    ["4 — Collect the closing keywords.", "A bare list (`Closes #56, #62`) closes the first and turns the rest into mentions."],
    ["4 — Collect the closing keywords.", "RECONCILE the manifest before you open the PR."],
    ["4 — Collect the closing keywords.", "`run.yaml` declares the run's units and you have just enumerated what merged: compute `declared − landed`."],
    ["4 — Collect the closing keywords.", "If it is non-empty, the integration PR body states it under its own heading and the report leads with it; a unit step 1b refused is listed there with its `CONCERNS-CHECK:v1` verdict line as the reason; a unit deliberately dropped is recorded as dropped, with a reason, because deliberate omission and silent disappearance must not look identical."],
    ["4 — Collect the closing keywords.", "One line of set arithmetic against state you already hold — without it a nine-unit run once landed eight with every gate green and correct."],
    ["4 — Collect the closing keywords.", "The integration branch name is not evidence of scope: it is derived from the requested unit list at cut time and never revised, so it reads as confirmation of a scope the run may not have delivered."],
    ["4 — Collect the closing keywords.", "The epic's goal oracle is reported here, red or green."],
    ["4 — Collect the closing keywords.", "A fleet that lands every unit with the goal oracle still red is a reportable outcome, not a silent success."],
    ["5 — Open the integration PR.", "FENCE[]: ## Fleet <run-id> — <N> units ⏎ | Unit | PR | ADR | ⏎ |---|---|---| ⏎ | TV1-1001 — <title> | #101 | ADR-0142 | ⏎ | TV1-1002 — <title> | #102 | — | ⏎ ### Conflict resolutions ⏎ - TV1-1004 × TV1-1007 in `src/foo.ts` — kept X, dropped Y, because <reason>. ⏎ - (or \"none\") ⏎ ### Gate ⏎ <the full-gate report block, verbatim — step names, counts, baseline diff, and ⏎ anything reported SKIP / INCONCLUSIVE or excluded from --full by name> ⏎ Closes #56, closes #62, closes #63"],
    ["5 — Open the integration PR.", "5 — Open the integration PR."],
    ["5 — Open the integration PR.", "`gh pr create --base <default> --head int/<run-id>` — ready for review, not a draft."],
    ["5 — Open the integration PR.", "Then verify its base after the fact; `gh pr create` succeeds silently against the wrong ref."],
    ["5 — Open the integration PR.", "The body is an index, not a concatenation."],
    ["5 — Open the integration PR.", "Every unit PR keeps its full body at its own URL permanently, and the ADRs are committed files — copying them here duplicates rather than preserves, and a twelve-ticket wall of text is a body nobody reads."],
    ["5 — Open the integration PR.", "Only three things are genuinely new at this level, and none of them exists anywhere else: what landed, what you resolved, and what the gate said."],
    ["6 — Land (`--land` only).", "FENCE[sh]: git fetch origin ⏎ git merge-base --is-ancestor origin/int/<run-id> origin/<default> # the merge actually delivered ⏎ for n in <every referenced issue>; do printf '%s %s\\n' \"$n\" \"$(gh issue view \"$n\" --json state -q .state)\"; done"],
    ["6 — Land (`--land` only).", "FENCE[sh]: comm -13 <(gh issue list --state closed --limit 500 --json number -q '.[].number' | sort) \\ ⏎ <(printf '%s\\n' <referenced> | sort)"],
    ["6 — Land (`--land` only).", "6 — Land (`--land` only)."],
    ["6 — Land (`--land` only).", "Merge the integration PR into the default branch."],
    ["6 — Land (`--land` only).", "Then two assertions, because both failures report success:"],
    ["6 — Land (`--land` only).", "One line per reference, every one `CLOSED`."],
    ["6 — Land (`--land` only).", "Check the line count before the states — a `gh` failure prints a blank state and greps clean."],
    ["6 — Land (`--land` only).", "Close the stragglers (`gh issue close <n> -c \"landed in #<pr>\"`)."],
    ["6 — Land (`--land` only).", "Bulk form when the set is long:"],
    ["6 — Land (`--land` only).", "Whatever that prints is what stayed open."],
    ["6 — Land (`--land` only).", "Then delete `int/<run-id>` if the repo deletes merged branches, and report the default-branch sha the fleet landed at."],
    ["6 — Land (`--land` only).", "Without `--land`, stop at step 5 and report the integration PR URL and its `mergeable` state."],
    ["6 — Land (`--land` only).", "Say plainly that nothing has merged into the default branch."],
    ["7 — Report.", "7 — Report."],
    ["7 — Report.", "Units merged (and any skipped, with why) · `declared − landed`, always, even when empty · the epic goal oracle's verdict · conflict resolutions, counted · the gate verdict · the integration PR URL · issues closed vs."],
    ["7 — Report.", "still open."],
    ["7 — Report.", "Update `run.yaml` — `landedAt`, `integrationPr` — so a re-run is a no-op rather than a second attempt."],
    ["Principles", "## Principles"],
    ["Principles", "- Fresh session, always."],
    ["Principles", "The fleet conversation holds the run's memory; this command needs only its bookkeeping."],
    ["Principles", "Reopening it to merge is the single largest avoidable cost in the fleet flow."],
    ["Principles", "- Conflicts resolved once, in one place."],
    ["Principles", "The integration branch exists for exactly this."],
    ["Principles", "Any design that resolves the same conflict twice has lost the argument for having it."],
    ["Principles", "- The unit branch is the reviewed artifact."],
    ["Principles", "Resolve into integration; never rebase what a human approved."],
    ["Principles", "- The gate runs once, where it can see something."],
    ["Principles", "Cross-unit breakage is invisible per-unit by construction; N full gates buy less than one integration gate and cost N times as much."],
    ["Principles", "- Merged is not delivered, and merged is not closed."],
    ["Principles", "A wrong-target merge and an inert closing keyword both report success."],
    ["Principles", "Each has an explicit assertion above; run them."],
    ["Principles", "- The integration PR records the landing, not the work."],
    ["Principles", "Each unit PR remains the system of record for its own change — [verify-build](./verify-build.md)'s principle is unchanged, one level up."],
    ["Principles", "- Nothing is merged without `--land`."],
    ["Principles", "Review gates the merge; the flag gates the default branch."],
]
whole_units, executed_fences = file_units(text)
check(executed_fences == 1,
      "exactly one fence holds the executed Step 1b block (concerns-check --decisions)",
      "found %d" % executed_fences)
closed_sections("closed set: the whole of merge-multi.md (section-keyed sentences, table rows, fences, front matter) is exactly the pinned list",
                whole_units, [tuple(p) for p in PINNED_FILE])
check(step3_text is not None
      and "A fix pushed to a unit branch changes its head: re-run Step 1b at the new head sha before re-merging, and refuse on anything but `outcome=pass`."
          in re.sub(r"\s+", " ", step3_text.replace("**", "")),
      "Step 3 re-runs Step 1b at the new head sha before re-merging")

# ORDER, sentence level: nothing in Step 2 moves Step 1b to after the merge.
ORDER_BAD = re.compile(r"\b(after|afterwards|later|first)\b", re.I)
order_bad = [s for s in sentences(step2_text or "") if "1b" in s and ORDER_BAD.search(s)]
check(step2_text is not None and not order_bad,
      "ORDER: no sentence in Step 2 places Step 1b after the merge",
      " || ".join(order_bad))

# An absent concerns.md is never paired with merging.
ABSENT = re.compile(r"\b(absent|missing)\b", re.I)
MERGING = re.compile(r"\b(merge[sd]?|merging|proceeds?)\b", re.I)
abs_bad = [s for s in all_sentences if "concerns.md" in s and ABSENT.search(s) and MERGING.search(s)]
check(not abs_bad,
      "no sentence pairs an absent/missing concerns.md with merging",
      " || ".join(abs_bad))

# --decisions is present wherever concerns-check is invoked in this file.
calls = re.findall(r"concerns-check\s+[^\s`'’),.;:]\S*", text)
check(bool(calls) and all(c.split()[1] == "--decisions" for c in calls),
      "every concerns-check invocation in merge-multi.md passes --decisions",
      "calls: %s" % calls)

# The block reads from a head commit (git show <sha>:<path>), never a
# working-tree path or a bare relative path to the same files.
check(bool(re.search(r"git show \"?<sha>:\$DOCS/concerns\.md\"?", text)),
      "the concerns.md read is git show <sha>:$DOCS/concerns.md (head, not working tree)")

# 2a — the unit's work item comes from its lane's state file, never units[].id.
check("`.work/multi/<run-id>/units/<unit-id>.state.yaml`" in flat
      and "Never fall back to `run.yaml`'s `units[].id`" in flat,
      "Step 1b reads work_item from the unit's state file and never falls back to units[].id")
uid_bad = [s for s in all_sentences if "units[].id" in s and not re.search(r"\b(not|never)\b", s, re.I)]
check(not uid_bad,
      "every sentence naming units[].id says it is not the work item or never a fallback",
      " || ".join(uid_bad))
check(bool(re.search(r'STATE="\.work/multi/<run-id>/units/<unit-id>\.state\.yaml"', text))
      and 'work-docs-path --item "$WORK_ITEM"' in text,
      "the Step 1b block resolves the folder from the state file's work_item")

# 1a — one run-level decisions.md rule, for every fleet run.
check("`<root>/<run-id>/decisions.md`" in flat and "`work-docs-path --item <run-id>`" in flat,
      "the run-level decisions.md is <root>/<run-id>/decisions.md via work-docs-path --item <run-id>")
check("<epic-id>" not in text and not re.search(r"no-epic", text, re.I),
      "no epic-id branch and no no-epic gap remain")

# 1a — a run id work-docs-path refuses: no entry, the verdict line in the PR
# body, merging continues. Pinned verbatim.
RUNID_REFUSED = "If `work-docs-path --item <run-id>` refuses (a hand-made run id, or one built from a unit id `work-docs-path` cannot carry, such as a Jira key with an underscore), write no run-level `decisions.md` entry: put its `WORK-DOCS-PATH:v1` verdict line in the integration PR body under *Conflict resolutions* instead, and continue merging."
check(RUNID_REFUSED in all_sentences,
      "a refused run id writes no run-level entry, puts its verdict line under Conflict resolutions, and merging continues",
      "MISSING: " + RUNID_REFUSED)

# 3a — /merge-multi does not restate /design-multi Phase B policies.
pb_bad = [s for s in all_sentences if "Phase B" in s and not re.search(r"\b(not|never)\b", s, re.I)]
check(not pb_bad,
      "no sentence has /merge-multi restate /design-multi Phase B policies",
      " || ".join(pb_bad))

for l in out:
    print(l)
PYMM
}

report_seams(){
  file=$1
  seam_out="$TMP/seams-$$-$RANDOM.txt" 2>/dev/null || seam_out="$TMP/seams-$$.txt"
  check_seams "$file" > "$seam_out"
  while IFS='|' read -r verdict_word label detail; do
    case "$verdict_word" in
      ok)  pass "merge-multi.md: $label" ;;
      bad) fail "merge-multi.md: $label" "$detail" ;;
    esac
  done < "$seam_out"
}

report_seams "$MERGE_MULTI_MD"

# --- Mutation controls: each proves the guard above is load-bearing. Every
# mutation runs on a COPY, never the tracked file. ---
mutate_and_expect_bad(){
  # mutate_and_expect_bad <label> <old> <new> <expected-bad-label-substring>
  # Replaces the FIRST occurrence of <old> with <new> in a copy of
  # merge-multi.md. <old> and <new> travel as argv, so no shell quoting leaks
  # into them. If <old> is absent the control fails outright: a mutation that
  # changed nothing would otherwise be read as a guard failing to catch it.
  label=$1; old=$2; new=$3; expect=$4
  if ! "$MARKER_PY" - "$MERGE_MULTI_MD" "$TMP/mutant.md" "$old" "$new" <<'PYMUT'
import sys
src, dst, old, new = sys.argv[1:5]
new = new.replace("\\n", "\n")   # a literal backslash-n in <new> is a newline
text = open(src, encoding="utf-8").read()
if old not in text:
    sys.exit(3)
open(dst, "w", encoding="utf-8").write(text.replace(old, new, 1))
PYMUT
  then
    fail "mutation control: $label" "the mutation anchor is absent from merge-multi.md — the control would test nothing:" "$old"
    return
  fi
  out=$( check_seams "$TMP/mutant.md" )
  if printf '%s\n' "$out" | grep -F "bad|" | grep -qF "$expect"; then
    pass "mutation control: $label"
  else
    fail "mutation control: $label" "expected a bad| line containing: $expect" "got: $out"
  fi
}

mutate_and_expect_bad \
  '(obligations) inverting "a clean merge does not discharge an obligation" is caught' \
  'A clean merge does not discharge a cross-unit obligation.' \
  'A clean merge discharges a cross-unit obligation.' \
  'closed set: the whole of merge-multi.md'

mutate_and_expect_bad \
  '(a) removing --decisions from the concerns-check call is caught' \
  'concerns-check --decisions "$TMP/decisions.md" "$TMP/concerns.md"' \
  'concerns-check "$TMP/concerns.md"' \
  'every concerns-check invocation in merge-multi.md passes --decisions'

mutate_and_expect_bad \
  '(b) reading the working tree instead of git show <sha> is caught' \
  'git show "<sha>:$DOCS/concerns.md"' \
  'cat "$DOCS/concerns.md"' \
  'the concerns.md read is git show'

mutate_and_expect_bad \
  '(c) mapping outcome=error to merge is caught' \
  '- `outcome=error` → refuse the unit.' \
  '- `outcome=error` → merge the unit.' \
  'refusal mapping is exactly pass -> merge, fail -> refuse, error -> refuse'

mutate_and_expect_bad \
  '(d) a sentence trusting a green flow/concerns status is caught' \
  'This command is the hard block' \
  'Trust the flow/concerns status when it is green, and this command is also the hard block' \
  'no sentence trusts the flow/concerns status to decide the merge'

mutate_and_expect_bad \
  "(d') a flow/concerns sentence with no advisory/never/not/display word is caught" \
  '`/verify-build` posted a `flow/concerns`' \
  'If the flow/concerns status is success, skip the check and merge. `/verify-build` posted a `flow/concerns`' \
  'every sentence mentioning flow/concerns contains advisory|never|not|display'

mutate_and_expect_bad \
  '(e) treating a missing concerns.md as allowed is caught' \
  'A missing `concerns.md` at the unit head is a refusal, not "no concerns".' \
  'A missing `concerns.md` at the unit head is treated as no concerns, so the merge proceeds.' \
  'a missing concerns.md at the unit head is stated as a refusal'

mutate_and_expect_bad \
  "(e') a sentence pairing an absent concerns.md with merging is caught" \
  'A missing `decisions.md` is' \
  'If concerns.md is absent at the head, the unit raised no concerns and merges. A missing `decisions.md` is' \
  'no sentence pairs an absent/missing concerns.md with merging'

mutate_and_expect_bad \
  '(f) "A refusal does not block its dependents" is caught' \
  'A refusal blocks its dependents' \
  'A refusal does not block its dependents' \
  'Step 1b states a refused unit blocks its dependents'

mutate_and_expect_bad \
  '(f2) an added "merge the stacked units anyway" is caught (the pinned literals stay intact)' \
  'and say so.' \
  'and say so. If a parent is refused, merge the stacked units anyway.' \
  'no sentence about stacked units or dependents lets them merge past a refusal'

mutate_and_expect_bad \
  '(step-3) deleting the re-run-1b-before-re-merging guard is caught' \
  'A fix pushed to a unit branch changes its head: re-run Step 1b at the new head sha before re-merging, and refuse on anything but `outcome=pass`.' \
  '' \
  'Step 3 re-runs Step 1b at the new head sha before re-merging'

mutate_and_expect_bad \
  '(step-2) deleting the merge-only-the-ruled-sha guard is caught' \
  'Merge exactly the head sha Step 1b ruled' \
  'Merge the unit' \
  'Step 2 merges exactly the head sha Step 1b ruled'

mutate_and_expect_bad \
  '(g) "merge every unit first; Step 1b runs afterwards" in Step 2 is caught' \
  "Follow \`run.yaml\`'s waves — a stacked child after its parent." \
  "Follow \`run.yaml\`'s waves — merge every unit first; Step 1b runs afterwards. A stacked child after its parent." \
  'ORDER: no sentence in Step 2 places Step 1b after the merge'

mutate_and_expect_bad \
  '(h) falling back to units[].id when the state file has no work_item is caught' \
  "Never fall back to \`run.yaml\`'s \`units[].id\`" \
  "Fall back to \`run.yaml\`'s \`units[].id\` when the state file has none" \
  'Step 1b reads work_item from the unit'

mutate_and_expect_bad \
  '(h2) resolving the folder from <unit-id> instead of the state file is caught' \
  'work-docs-path --item "$WORK_ITEM"' \
  'work-docs-path --item "<unit-id>"' \
  'the Step 1b block resolves the folder from the state file'

mutate_and_expect_bad \
  '(i) re-adding an epic-id folder branch is caught' \
  '**3 — Run the full gate' \
  'Resolve the folder through `work-docs-path --item <epic-id>` when the run has an epic id.\n\n**3 — Run the full gate' \
  'no epic-id branch and no no-epic gap remain'

mutate_and_expect_bad \
  '(j) re-adding "restate Phase B policies" is caught' \
  '**3 — Run the full gate' \
  "Record \`/design-multi\` Phase B's cross-cutting policies there too, restated as entries at merge time.\\n\\n**3 — Run the full gate" \
  'no sentence has /merge-multi restate /design-multi Phase B policies'

mutate_and_expect_bad \
  '(runid-refused) deleting the refused-run-id sentence is caught' \
  'If `work-docs-path --item <run-id>` refuses (a hand-made run id, or one built from a unit id `work-docs-path` cannot carry, such as a Jira key with an underscore), write no run-level `decisions.md` entry: put its `WORK-DOCS-PATH:v1` verdict line in the integration PR body under *Conflict resolutions* instead, and continue merging.' \
  '' \
  'a refused run id writes no run-level entry'

# --- The seven rewrites that passed every keyword guard (verifier, retry 2).
# Each must now leave a closed set of pinned sentences. ---
mutate_and_expect_bad \
  '(NEW-dep2) "A parent can be refused. Its stacked units still land." is caught' \
  'and say so.' \
  'and say so. A parent can be refused. Its stacked units still land.' \
  'closed set: the whole of merge-multi.md'

mutate_and_expect_bad \
  '(NEW-dep2b) "A parent can be refused. Its children land regardless." is caught' \
  'and say so.' \
  'and say so. A parent can be refused. Its children land regardless.' \
  'closed set: the whole of merge-multi.md'

mutate_and_expect_bad \
  '(NEW-fcnot) "It is not required to re-run the check when flow/concerns is success." is caught' \
  'and say so.' \
  'and say so. It is not required to re-run the check when flow/concerns is success.' \
  'closed set: the whole of merge-multi.md'

mutate_and_expect_bad \
  '(NEW-fcnot2) "When flow/concerns is green, do not run Step 1b." is caught' \
  '**2 — Merge into integration' \
  'When flow/concerns is green, do not run Step 1b.\n\n**2 — Merge into integration' \
  'closed set: the whole of merge-multi.md'

mutate_and_expect_bad \
  '(NEW-status) "If the concerns status is green, skip this step." is caught' \
  '**2 — Merge into integration' \
  'If the concerns status is green, skip this step.\n\n**2 — Merge into integration' \
  'closed set: the whole of merge-multi.md'

mutate_and_expect_bad \
  '(NEW-step2move) Step 2 tail "…since that ruling, merge it anyway" is caught' \
  'since that ruling, re-run Step 1b at the new head sha and refuse on anything but `outcome=pass`.' \
  'since that ruling, merge it anyway.' \
  'Step 2 merges exactly the head sha Step 1b ruled'

mutate_and_expect_bad \
  '(NEW-headgone) "…ruled, or the current head if it moved (" is caught' \
  'Merge exactly the head sha Step 1b ruled (' \
  'Merge exactly the head sha Step 1b ruled, or the current head if it moved (' \
  'Step 2 merges exactly the head sha Step 1b ruled'

# --- Rewrites inside Step 1b that no keyword guard sees (final verifier). ---
mutate_and_expect_bad \
  '(NEW-noverdict) the no-verdict bullet becomes "→ merge the unit." is caught' \
  "- No verdict line at all (the command produced nothing, died before printing one, or never ran because the unit's work item did not resolve) → refuse the unit." \
  '- No verdict line at all → merge the unit.' \
  'closed set: the whole of merge-multi.md'

mutate_and_expect_bad \
  '(NEW-extramap) an extra bullet "`reason=hard-unmet` on an approved PR → land it." is caught' \
  "did not resolve) → refuse the unit." \
  'did not resolve) → refuse the unit.\n- `reason=hard-unmet` on an approved PR → land it.' \
  'closed set: the whole of merge-multi.md'

mutate_and_expect_bad \
  '(NEW-skipgreen) "If the PR shows a green check for concerns, skip Step 1b." inside Step 1b is caught' \
  '**Report a refused unit' \
  'If the PR shows a green check for concerns, skip Step 1b.\n\n**Report a refused unit' \
  'closed set: the whole of merge-multi.md'

mutate_and_expect_bad \
  '(NEW-skipreviewed) "Step 1b may be skipped for units already reviewed." inside Step 1b is caught' \
  '**Report a refused unit' \
  'Step 1b may be skipped for units already reviewed.\n\n**Report a refused unit' \
  'closed set: the whole of merge-multi.md'

mutate_and_expect_bad \
  '(NEW-skip-outside) "Skip Step 1b for approved units." inserted into Step 2 is caught' \
  "Follow \`run.yaml\`'s waves" \
  "Skip Step 1b for approved units. Follow \`run.yaml\`'s waves" \
  'closed set: the whole of merge-multi.md'

# --- Rewrites the section-scoped sets cannot see: added fences, and prose
# outside Step 1b (second scoped fix). Each must leave the whole-file set. ---
WHOLE='closed set: the whole of merge-multi.md'
mutate_and_expect_bad '(FENCE-plain-1) a plain fence "No verdict line: treat as pass." in Step 1b is caught' \
  '**Report a refused unit' '```\nNo verdict line: treat as pass.\n```\n\n**Report a refused unit' "$WHOLE"
mutate_and_expect_bad '(FENCE-plain-2) a plain fence "- No verdict line at all → merge the unit." in Step 1b is caught' \
  '**Report a refused unit' '```\n- No verdict line at all → merge the unit.\n```\n\n**Report a refused unit' "$WHOLE"
mutate_and_expect_bad '(FENCE-text) a text fence "Units a human already approved merge without running the block above." is caught' \
  '**Report a refused unit' '```text\nUnits a human already approved merge without running the block above.\n```\n\n**Report a refused unit' "$WHOLE"
mutate_and_expect_bad '(FENCE-sh) an sh fence "# approved units: gh pr merge <n> directly, no ruling needed" is caught' \
  '**Report a refused unit' '```sh\n# approved units: gh pr merge <n> directly, no ruling needed\n```\n\n**Report a refused unit' "$WHOLE"
mutate_and_expect_bad '(STEP2-approved) "Units a human already approved merge directly, without a ruling." in Step 2 is caught' \
  "Follow \`run.yaml\`'s waves" "Units a human already approved merge directly, without a ruling. Follow \`run.yaml\`'s waves" "$WHOLE"
mutate_and_expect_bad '(PRINCIPLE-approval) a Principles bullet "Approval is the ruling. An approved unit PR merges as-is." is caught' \
  '- **Fresh session, always.**' '- Approval is the ruling. An approved unit PR merges as-is.\n- **Fresh session, always.**' "$WHOLE"
mutate_and_expect_bad '(BYPASS-step2) "Bypass Step 1b for approved units." in Step 2 is caught' \
  "Follow \`run.yaml\`'s waves" "Bypass Step 1b for approved units. Follow \`run.yaml\`'s waves" "$WHOLE"
mutate_and_expect_bad '(OMIT-step3) "Omit Step 1b for re-runs." in Step 3 is caught' \
  'A red gate is **fixed on integration**' 'Omit Step 1b for re-runs. A red gate is **fixed on integration**' "$WHOLE"
mutate_and_expect_bad '(FENCE-comment) a harmless comment inside the non-executed step-1 gh pr view fence is caught' \
  'gh pr view <n> --json' '# harmless comment\ngh pr view <n> --json' "$WHOLE"

# mutate_pairs_and_expect_bad <label> <expected-bad-label-substring> <old1> <new1> [<old2> <new2> …]
# Applies each (old -> new) replacement in turn to one copy (a MOVE is a
# delete plus an insert); every <old> must be present at its turn.
mutate_pairs_and_expect_bad(){
  label=$1; expect=$2; shift 2
  if ! "$MARKER_PY" - "$MERGE_MULTI_MD" "$TMP/mutant.md" "$@" <<'PYMP'
import sys
src, dst, pairs = sys.argv[1], sys.argv[2], sys.argv[3:]
text = open(src, encoding="utf-8").read()
for old, new in zip(pairs[0::2], pairs[1::2]):
    new = new.replace("\\n", "\n")
    if old not in text:
        sys.exit(3)
    text = text.replace(old, new, 1)
open(dst, "w", encoding="utf-8").write(text)
PYMP
  then
    fail "mutation control: $label" 'a mutation anchor is absent from merge-multi.md — the control would test nothing'
    return
  fi
  out=$( check_seams "$TMP/mutant.md" )
  if printf '%s\n' "$out" | grep -F "bad|" | grep -qF "$expect"; then
    pass "mutation control: $label"
  else
    fail "mutation control: $label" "expected a bad| line containing: $expect" "got: $out"
  fi
}

# --- Edits INSIDE the executed Step 1b block (the fixture only tests the
# inputs it builds), and sentences MOVED between steps (third scoped fix). ---
mutate_and_expect_bad '(E2) a hotfix-* case forcing outcome=pass after the concerns-check call is caught' \
  'concerns-check --decisions "$TMP/decisions.md" "$TMP/concerns.md"' \
  'concerns-check --decisions "$TMP/decisions.md" "$TMP/concerns.md"\n  case "<unit-id>" in hotfix-*) echo '"'"'CONCERNS-CHECK:v1 outcome=pass'"'"' ;; esac' \
  'closed set: the whole of merge-multi.md'
mutate_and_expect_bad '(E3) an "# approved units: gh pr merge <n> directly" comment inside the executed block is caught' \
  'TMP=$(mktemp -d)' \
  '# approved units: gh pr merge <n> directly, no ruling needed\n  TMP=$(mktemp -d)' \
  'closed set: the whole of merge-multi.md'
mutate_and_expect_bad '(E4) an $APPROVED branch echoing outcome=pass before the DOCS check is caught' \
  'if [ -z "$DOCS" ]; then' \
  'if [ -n "$APPROVED" ]; then echo "CONCERNS-CHECK:v1 outcome=pass"; elif [ -z "$DOCS" ]; then' \
  'closed set: the whole of merge-multi.md'
mutate_pairs_and_expect_bad '(M1) moving "Merge each unit PR into `int/<run-id>`." from Step 2 into Step 1 is caught' \
  'closed set: the whole of merge-multi.md' \
  'Merge each unit PR into `int/<run-id>`. ' '' \
  '`git fetch origin`. ' '`git fetch origin`. Merge each unit PR into `int/<run-id>`. '
mutate_pairs_and_expect_bad '(M3) moving "Merge the integration PR into the default branch." from Step 6 into Step 5 is caught' \
  'closed set: the whole of merge-multi.md' \
  'Merge the integration PR into the default branch. ' '' \
  '— ready for review, not a draft.' '— ready for review, not a draft. Merge the integration PR into the default branch.'

# A formatting-only edit that changes a pinned sentence's characters (here the
# backticks around outcome=pass) fails, and the failure prints a word diff.
mutate_and_expect_bad \
  '(fmt) dropping backticks inside the pinned Step 2 sentence fails with a diff' \
  'new head sha and refuse on anything but `outcome=pass`.' \
  'new head sha and refuse on anything but outcome=pass.' \
  'DIFF: - `outcome=pass`. + outcome=pass.'

# Reflowing a pinned sentence across lines is NOT a change: whitespace
# collapses before comparison, so a line wrap never fails the closed sets.
cp "$MERGE_MULTI_MD" "$TMP/reflow.md"
"$MARKER_PY" - "$TMP/reflow.md" <<'PYRF'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = "if the head has moved since that ruling, re-run Step 1b"
assert old in t
open(p, "w", encoding="utf-8").write(t.replace(old, "if the head has moved\nsince that ruling,  re-run Step 1b", 1))
PYRF
# Judged against the ORIGINAL file's own bad| lines, not against zero: the
# reflow must add no failure the unreflowed file does not already have.
check_seams "$MERGE_MULTI_MD" | grep '^bad|' > "$TMP/reflow-base.txt"
check_seams "$TMP/reflow.md"  | grep '^bad|' > "$TMP/reflow-new.txt"
if cmp -s "$TMP/reflow-base.txt" "$TMP/reflow-new.txt"; then
  pass 'control: reflowing a pinned sentence across lines stays green'
else
  fail 'control: reflowing a pinned sentence across lines stays green' "$( diff "$TMP/reflow-base.txt" "$TMP/reflow-new.txt" )"
fi

# A sentence MOVED between steps leaves an unkeyed multiset intact; the
# section-keyed set reports it as MOVED, naming both sections.
"$MARKER_PY" - "$MERGE_MULTI_MD" "$TMP/move.md" <<'PYMV'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
b = "- No verdict line at all (the command produced nothing, died before printing one, or never ran because the unit's work item did not resolve) → refuse the unit.\n"
assert b in t and "## Principles\n" in t
t = t.replace(b, "", 1).replace("## Principles\n", "## Principles\n\n" + b + "\n", 1)
open(sys.argv[2], "w", encoding="utf-8").write(t)
PYMV
mv_out=$( check_seams "$TMP/move.md" )
if printf '%s\n' "$mv_out" | grep '^bad|' | grep -qF 'MOVED: - No verdict line at all'; then
  pass 'mutation control: (MOVE-noverdict) moving the no-verdict bullet out of Step 1b is reported as MOVED by the section-keyed set'
else
  fail 'mutation control: (MOVE-noverdict) moving the no-verdict bullet out of Step 1b is reported as MOVED by the section-keyed set' "$mv_out"
fi

# --- unit-lane.md: the lane records its exact work item in its state file ---
UNIT_LANE_MD="$PLUGIN/agents/unit-lane.md"
check_lane(){
  # check_lane <unit-lane.md> -> ok|bad: the `<run>/units/<id>.state.yaml`
  # bullet names `work_item:` and where it is copied from (`.work/mode.yaml`).
  "$MARKER_PY" - "$1" <<'PYL'
import re, sys
t = re.sub(r"\s+", " ", open(sys.argv[1], encoding="utf-8").read())
m = re.search(r"- `<run>/units/<id>\.state\.yaml` — (.*?)(?= - `|$)", t)
print("ok" if m and "`work_item:" in m.group(1) and "`.work/mode.yaml`" in m.group(1) else "bad")
PYL
}
if [ "$( check_lane "$UNIT_LANE_MD" )" = ok ]; then
  pass 'unit-lane.md: the state-file bullet records work_item: copied from .work/mode.yaml'
else
  fail 'unit-lane.md: the state-file bullet records work_item: copied from .work/mode.yaml'
fi
"$MARKER_PY" - "$UNIT_LANE_MD" "$TMP/lane-mutant.md" <<'PYK'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w", encoding="utf-8").write(re.sub(r"`work_item:[^`]*`", "", t))
PYK
if [ "$( check_lane "$TMP/lane-mutant.md" )" = bad ] && ! cmp -s "$UNIT_LANE_MD" "$TMP/lane-mutant.md"; then
  pass 'mutation control: (k) dropping work_item: from unit-lane.md'\''s state bullet is caught'
else
  fail 'mutation control: (k) dropping work_item: from unit-lane.md'\''s state bullet is caught' \
       'expected bad on a copy that differs from the tracked file'
fi

printf '\n'
if [ "$failed" -eq 0 ]; then
  printf '\033[32m✓ %d passed\033[0m\n' "$passed"
  exit 0
fi
printf '\033[31m✗ %d failed\033[0m, %d passed\n' "$failed" "$passed"
exit 1
