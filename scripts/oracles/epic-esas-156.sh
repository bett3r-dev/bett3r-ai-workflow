#!/bin/sh
# The ESAS-156 epic oracle (ESAS-178 D8) — "a design's forks are answered on a
# visual map by choose or comment, the answers land as decided(owner) in one
# record, and the map is regenerable from map.json".
#
# Committed RED on purpose (P10/C6): most verbs this drives (validate, write,
# v2 apply-answers, candidates, map-tree, select, post) either do not exist
# yet on `bin/design-map` (unknown-verb) or the shipped launcher still speaks
# v1 over a v2-shaped fixture (schema/shape mismatch). That is the expected
# state until slices 2-7 land the vocabulary, the writer and the readers.
#
# Every stage prints exactly one line:
#   ORACLE:v1 stage=<n> outcome=ok|fail|error [reason=<reason>]
# `outcome=error` means a verb call itself did not conclude `outcome=ok`
# (crash, unknown-verb, schema refusal, ...) — the underlying reason is
# propagated verbatim, and `reason=unknown-verb` is never turned into a skip.
# `outcome=fail` means every verb call concluded ok but an assertion this
# oracle makes about the result did not hold. `reason=no-verdict` covers a
# run that printed no DESIGN-MAP:v1 line at all (crashed before concluding).
#
# Exit 0 only when all 7 stages are ok. ESAS_CHECKOUT unset/empty prints
# `ORACLE:v1 stage=0 outcome=error reason=no-esas-checkout` and exits 2
# before anything else runs.
#
# Run locally:  sh scripts/oracles/epic-esas-156.sh
#               dash scripts/oracles/epic-esas-156.sh
#               ESAS_CHECKOUT=/path/to/esas sh scripts/oracles/epic-esas-156.sh

ROOT=$( CDPATH= cd -- "$( dirname -- "$0" )/../.." && pwd )
DM="$ROOT/plugins/bett3r-ai-workflow/bin/design-map"
FIX="$ROOT/scripts/fixtures/epic-esas-156"

if [ -z "${ESAS_CHECKOUT:-}" ]; then
  printf 'ORACLE:v1 stage=0 outcome=error reason=no-esas-checkout\n'
  exit 2
fi

TMP=$( mktemp -d "${TMPDIR:-/tmp}/epic-esas-156.XXXXXX" ) || exit 1
TMP=$( CDPATH= cd -P -- "$TMP" && pwd )
trap 'rm -rf "$TMP"' EXIT INT TERM

overall=0

# verdict_line <file> — the last DESIGN-MAP:v* verdict line in the file, if
# any (mirrors scripts/test-design-map.sh's own `verdict`).
verdict_line(){
  awk 'NF{l=$0} END{print l}' "$1" | grep -E '^DESIGN-MAP:v[0-9]+ outcome=[a-z]+( [A-Za-z_-]+=[^ ]*)*$'
}

# attr <verdict-line> <key>
attr(){
  printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1
}

DMOUT="$TMP/dm.out"

# dm <args…> — run the real launcher `bin/design-map` from inside $TMP (the
# launcher's own shim picks the interpreter; this driver is what must run
# under sh/dash/bash). Sets $rc and $LINE.
dm(){
  ( cd "$TMP" && "$DM" "$@" ) > "$DMOUT" 2>&1
  rc=$?
  LINE=$( verdict_line "$DMOUT" )
}

# dm_result — after a `dm` call, sets RESKIND (ok|error) and RESREASON.
dm_result(){
  if [ -z "$LINE" ]; then
    RESKIND=error; RESREASON=no-verdict
    return
  fi
  if [ "$( attr "$LINE" outcome )" = ok ]; then
    RESKIND=ok; RESREASON=
    return
  fi
  RESKIND=error
  RESREASON=$( attr "$LINE" reason )
  [ -n "$RESREASON" ] || RESREASON=unspecified
}

# stage <n> <outcome> [reason] — the one line this oracle owns per stage.
stage(){
  n=$1 outcome=$2 reason=${3:-}
  if [ -n "$reason" ]; then
    printf 'ORACLE:v1 stage=%s outcome=%s reason=%s\n' "$n" "$outcome" "$reason"
  else
    printf 'ORACLE:v1 stage=%s outcome=%s\n' "$n" "$outcome"
  fi
  [ "$outcome" = ok ] || overall=1
}

MAP="$FIX/draft.map.json"

# ---------------------------------------------------------------------------
# Stage 1 — validate + render --expect 5 ok, 5 cards, owner and recommendation
# drawn distinctly.
# ---------------------------------------------------------------------------
dm validate "$MAP"
dm_result
if [ "$RESKIND" = ok ]; then
  PAGE="$TMP/s1.page.html"
  dm render "$MAP" --expect 5 --out "$PAGE"
  dm_result
  if [ "$RESKIND" = ok ]; then
    if [ "$( attr "$LINE" rendered )" != 5 ]; then
      stage 1 fail rendered-count-mismatch
    elif [ ! -f "$PAGE" ]; then
      stage 1 fail page-missing
    else
      cards=$( grep -o 'data-fork-id="[A-Z][A-Z0-9]*-[0-9]*-F[0-9]*"' "$PAGE" | sort -u | wc -l | tr -d ' ' )
      if [ "$cards" != 5 ]; then
        stage 1 fail card-count-mismatch
      else
        owner_style=$( grep -c 'class="[^"]*owner[^"]*"' "$PAGE" 2>/dev/null || true )
        rec_style=$( grep -c 'class="[^"]*recommendation[^"]*"' "$PAGE" 2>/dev/null || true )
        if [ "${owner_style:-0}" -ge 1 ] && [ "${rec_style:-0}" -ge 1 ]; then
          stage 1 ok
        else
          stage 1 fail owner-recommendation-not-distinct
        fi
      fi
    fi
  else
    stage 1 error "$RESREASON"
  fi
else
  stage 1 error "$RESREASON"
fi
STAGE1_PAGE="$PAGE"

# ---------------------------------------------------------------------------
# Stage 2 — delete the page and re-render; byte-identical.
# ---------------------------------------------------------------------------
if [ -f "$STAGE1_PAGE" ]; then
  STAGE1_COPY="$TMP/s1.page.copy.html"
  cp "$STAGE1_PAGE" "$STAGE1_COPY"
  rm -f "$STAGE1_PAGE"
  dm render "$MAP" --expect 5 --out "$STAGE1_PAGE"
  dm_result
  if [ "$RESKIND" = ok ]; then
    if [ ! -f "$STAGE1_PAGE" ]; then
      stage 2 fail page-not-rewritten
    elif cmp -s "$STAGE1_COPY" "$STAGE1_PAGE"; then
      stage 2 ok
    else
      stage 2 fail not-byte-identical
    fi
  else
    stage 2 error "$RESREASON"
  fi
else
  # Stage 1 never produced a page to delete and re-render (RED at this
  # slice: validate/render are unknown-verb or refuse the v2 fixture).
  stage 2 error prereq-failed
fi

# ---------------------------------------------------------------------------
# Stage 3 — apply-answers (pass1 folds into $S3MAP), then write (card on
# unlock: the folded $S3MAP plus ESAS-900-F1's card, copied from
# unlocked.map.json, is what `write` reads), then apply-answers --final -> owner=2 recommendation=2 moot=1 open=0
# (design.md "Verified at BASE" correction of the block's owner 2 /
# recommendation 1 / moot 1: after --final no fork stays open, and
# owner+recommendation+moot = 5 across the fixture's 5 forks).
# ---------------------------------------------------------------------------
S3MAP="$TMP/s3.map.json"
S3_OK=0
S3FINAL=
cp "$MAP" "$S3MAP"
dm apply-answers "$S3MAP" "$FIX/answers/pass1"
dm_result
if [ "$RESKIND" != ok ]; then
  stage 3 error "$RESREASON"
else
  UNLOCKED_OUT="$TMP/s3.unlocked.json"
  UNLOCKED_IN="$TMP/s3.unlocked.in.json"
  # Paths go in via argv, never interpolated into the python source.
  if ! python3 - "$S3MAP" "$FIX/unlocked.map.json" "$UNLOCKED_IN" > "$DMOUT" 2>&1 <<'PY'
import json, sys
folded_path, unlocked_path, out_path = sys.argv[1:4]
with open(folded_path) as fh:
    folded = json.load(fh)
with open(unlocked_path) as fh:
    unlocked = json.load(fh)
card = next(f['card'] for f in unlocked['forks'] if f['id'] == 'ESAS-900-F1')
for f in folded['forks']:
    if f['id'] == 'ESAS-900-F1':
        f['card'] = card
with open(out_path, 'w') as fh:
    json.dump(folded, fh, indent=2)
PY
  then
    RESKIND=error; RESREASON=unlock-build-failed
  else
    ( cd "$TMP" && "$DM" write "$UNLOCKED_OUT" < "$UNLOCKED_IN" ) > "$DMOUT" 2>&1
    rc=$?
    LINE=$( verdict_line "$DMOUT" )
    dm_result
  fi
  if [ "$RESKIND" != ok ]; then
    stage 3 error "$RESREASON"
  else
    dm apply-answers "$UNLOCKED_OUT" "$FIX/answers/pass2" --final
    dm_result
    if [ "$RESKIND" != ok ]; then
      stage 3 error "$RESREASON"
    else
      owner=$( attr "$LINE" owner )
      recommendation=$( attr "$LINE" recommendation )
      moot=$( attr "$LINE" moot )
      open=$( attr "$LINE" open )
      if [ "$owner" = 2 ] && [ "$recommendation" = 2 ] && [ "$moot" = 1 ] && [ "$open" = 0 ]; then
        stage 3 ok
        S3_OK=1
        S3FINAL="$UNLOCKED_OUT"
      else
        stage 3 fail final-count-mismatch
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Stage 4 — in a tmp git repo, write + render + `map-tree write` land as one
# 3-file commit; an overturn makes `map-tree check` stale, and after
# `map-tree write` regenerates, the tree file's bytes OUTSIDE the map-tree
# region are equal to the committed ones. The region marker format is owned
# by ESAS-163 and unknown here: this oracle assumes lines containing
# `map-tree:begin` / `map-tree:end`, and reports `reason=region-markers-absent`
# (never a silent pass) when no committed tree file carries them.
# ---------------------------------------------------------------------------
GIT_DIR="$TMP/s4-repo"
mkdir -p "$GIT_DIR"
( cd "$GIT_DIR" && git init -q && git config user.email oracle@example.com && git config user.name oracle )
S4MAP="$GIT_DIR/map.json"
( cd "$TMP" && "$DM" write "$S4MAP" < "$FIX/final.map.json" ) > "$DMOUT" 2>&1
LINE=$( verdict_line "$DMOUT" )
dm_result
if [ "$RESKIND" != ok ]; then
  stage 4 error "$RESREASON"
elif ! command -v map-tree >/dev/null 2>&1 && [ ! -x "$ROOT/plugins/bett3r-ai-workflow/bin/map-tree" ]; then
  stage 4 error unknown-verb
else
  MAPTREE="map-tree"
  command -v map-tree >/dev/null 2>&1 || MAPTREE="$ROOT/plugins/bett3r-ai-workflow/bin/map-tree"
  S4PAGE="$GIT_DIR/map.page.html"
  dm render "$S4MAP" --expect 5 --out "$S4PAGE"
  dm_result
  if [ "$RESKIND" != ok ]; then
    stage 4 error "$RESREASON"
  else
    ( cd "$GIT_DIR" && "$MAPTREE" write ) > "$DMOUT" 2>&1
    LINE=$( verdict_line "$DMOUT" )
    dm_result
    if [ "$RESKIND" != ok ]; then
      stage 4 error "$RESREASON"
    else
      files=$( cd "$GIT_DIR" && git show --name-only --format= -1 | grep -c . || true )
      if [ "${files:-0}" != 3 ]; then
        stage 4 fail commit-not-three-files
      else
        # An overturn: flip F2's decided option and re-write, then map-tree
        # check must call the tree stale.
        python3 - "$S4MAP" "$TMP/s4.overturned.json" <<'PY'
import json, sys
src, dst = sys.argv[1:3]
with open(src) as fh:
    m = json.load(fh)
for f in m['forks']:
    if f['id'] == 'ESAS-900-F2':
        f['status']['option'] = 'b'
with open(dst, 'w') as fh:
    json.dump(m, fh)
PY
        ( cd "$TMP" && "$DM" write "$S4MAP" < "$TMP/s4.overturned.json" ) > "$DMOUT" 2>&1
        LINE=$( verdict_line "$DMOUT" )
        dm_result
        if [ "$RESKIND" != ok ]; then
          stage 4 error "$RESREASON"
        else
          ( cd "$GIT_DIR" && "$MAPTREE" check ) > "$DMOUT" 2>&1
          LINE=$( verdict_line "$DMOUT" )
          dm_result
          if [ "$RESKIND" = ok ]; then
            stage 4 fail overturn-not-detected-stale
          elif [ "$RESREASON" = stale ]; then
            # Tree files = the commit's files other than map.json and the page.
            TREEFILES=$( cd "$GIT_DIR" && git show --name-only --format= -1 | grep -v -x -e map.json -e map.page.html )
            # Snapshot the committed bytes BEFORE the re-write: map-tree write
            # commits, so reading HEAD afterwards would compare a file with itself.
            s4n=0
            for tf in $TREEFILES; do
              s4n=$((s4n + 1))
              ( cd "$GIT_DIR" && git show "HEAD:$tf" ) > "$TMP/s4.before.$s4n" 2>/dev/null
            done
            ( cd "$GIT_DIR" && "$MAPTREE" write ) > "$DMOUT" 2>&1
            LINE=$( verdict_line "$DMOUT" )
            dm_result
            if [ "$RESKIND" != ok ]; then
              stage 4 error "$RESREASON"
            else
              region_seen=0 region_diff=0 s4n=0
              for tf in $TREEFILES; do
                s4n=$((s4n + 1))
                grep -q 'map-tree:begin' "$TMP/s4.before.$s4n" && region_seen=1
                awk '/map-tree:begin/{skip=1} !skip{print} /map-tree:end/{skip=0}' "$TMP/s4.before.$s4n" > "$TMP/s4.before.out"
                awk '/map-tree:begin/{skip=1} !skip{print} /map-tree:end/{skip=0}' "$GIT_DIR/$tf" > "$TMP/s4.after.out" 2>/dev/null
                cmp -s "$TMP/s4.before.out" "$TMP/s4.after.out" || region_diff=1
              done
              if [ "$region_seen" = 0 ]; then
                stage 4 error region-markers-absent
              elif [ "$region_diff" = 1 ]; then
                stage 4 fail out-of-region-bytes-changed
              else
                stage 4 ok
              fi
            fi
          else
            stage 4 error "$RESREASON"
          fi
        fi
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Stage 5 — candidates count. Run against scripts/fixtures/epic-esas-156/
# final.map.json (the fixture's own post-stage-3 state, kept static so this
# stage is deterministic even when stage 3 itself cannot fold the map yet).
#
# Arithmetic (one candidate per walk of a decided fork's CHOSEN option only):
#   ESAS-900-F1 decided(owner, "go")            -> 1 walk  = 1
#   ESAS-900-F2 decided(owner, "a")              -> 2 walks = 2
#   ESAS-900-F3 decided(recommendation, "b")     -> 2 walks = 2
#   ESAS-901-F1 decided(recommendation, "a")     -> 1 walk  = 1
#   ESAS-901-F2 moot                              -> excluded
#   total = 1 + 2 + 2 + 1 = 6
# ---------------------------------------------------------------------------
EXPECTED_CANDIDATES=6
dm candidates "$FIX/final.map.json"
dm_result
if [ "$RESKIND" != ok ]; then
  stage 5 error "$RESREASON"
else
  n=$( attr "$LINE" candidates )
  if [ "$n" = "$EXPECTED_CANDIDATES" ]; then
    stage 5 ok
  else
    stage 5 fail candidate-count-mismatch
  fi
fi

# ---------------------------------------------------------------------------
# Stage 6 — the esas half: `npx --no vitest run -c vitest.oracle.config.ts`
# from the esas REPO ROOT ($ESAS_CHECKOUT; the config lives there and its
# include is root-relative, packages/esas-mcp/oracles/**/*.oracle.test.ts —
# the block's "in packages/esas-mcp" names where the test lives). Never
# installs anything: `--no` refuses a download, and a checkout without a
# local vitest is `reason=vitest-unavailable`. The esas test writes only into
# its own mkdtemp dir, so this stage leaves no captures behind (stage 7).
# ---------------------------------------------------------------------------
if [ ! -f "$ESAS_CHECKOUT/vitest.oracle.config.ts" ]; then
  stage 6 error esas-half-missing
elif [ ! -x "$ESAS_CHECKOUT/node_modules/.bin/vitest" ]; then
  stage 6 error vitest-unavailable
else
  ( cd "$ESAS_CHECKOUT" && npx --no vitest run -c vitest.oracle.config.ts ) > "$TMP/s6.out" 2>&1
  if [ $? = 0 ]; then
    stage 6 ok
  else
    stage 6 error vitest-failed
  fi
fi

# ---------------------------------------------------------------------------
# Stage 7 — select --phase probe / --phase start over the captures, then
# post --expect 5 ok, and the status multiset equals stage 3's runtime output
# map ($S3FINAL). Captures are read from the directory named by
# $ESAS_ORACLE_CAPTURES; unset or not a directory -> `reason=no-captures`
# (stage 6 persists none). Stage 3 not ok -> `reason=prereq-failed`.
# ---------------------------------------------------------------------------
if [ -z "${ESAS_ORACLE_CAPTURES:-}" ] || [ ! -d "$ESAS_ORACLE_CAPTURES" ]; then
  RESKIND=error; RESREASON=no-captures
elif [ "$S3_OK" != 1 ]; then
  RESKIND=error; RESREASON=prereq-failed
else
  dm select --phase probe --captures "$ESAS_ORACLE_CAPTURES"
  dm_result
fi
if [ "$RESKIND" != ok ]; then
  stage 7 error "$RESREASON"
else
  dm select --phase start --captures "$ESAS_ORACLE_CAPTURES"
  dm_result
  if [ "$RESKIND" != ok ]; then
    stage 7 error "$RESREASON"
  else
    if [ "$( attr "$LINE" target )" != board ]; then
      stage 7 fail target-not-board
    else
      dm post --expect 5
      dm_result
      if [ "$RESKIND" != ok ]; then
        stage 7 error "$RESREASON"
      else
        actual_multiset=$( python3 - "$S3FINAL" <<'PY'
import json, sys
with open(sys.argv[1]) as fh:
    m = json.load(fh)
print(','.join(sorted(f['status']['kind'] + ':' + f['status'].get('source', '-') for f in m['forks'])))
PY
)
        posted_multiset=$( attr "$LINE" statuses )
        if [ "$posted_multiset" = "$actual_multiset" ]; then
          stage 7 ok
        else
          stage 7 fail status-multiset-mismatch
        fi
      fi
    fi
  fi
fi

exit $overall
