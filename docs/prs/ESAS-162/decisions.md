# ESAS-162 — decisions after the design

## D1 — In the `drift` verdict, `mapSeq` is the map file's `feedSeq` and `feedSeq` is the `--feed-seq` value
kind: deviation
step: build · slice: 1 · decidedBy: lane
sources: [design:block D5/D6 and AC4, design:docs/prs/ESAS-162/design.md Corrections #3]
rejected: mapSeq = the feed-side fold seq as D6 names it — contradicts AC4's `mapSeq=none` for a map without feedSeq
supersedes: —
AC4 is the executable half and governs. The esas "mapSeq" of D6 is what a caller passes as `--feed-seq`.

## D2 — Unspecified refusal reasons for count/drift
kind: silent-seam
step: build · slice: 1 · decidedBy: executor
sources: [code:load_map (plugins/bett3r-ai-workflow/scripts/design-map.py), code:map-structure.schema.json feedSeq minimum 0]
rejected: count's map-not-found for drift too — load_map already names the unreadable case
supersedes: —
drift on a missing map → `reason=map-unreadable`; neither/both feed flags → `missing-feed`/`conflicting-feed`; unreadable `--lane` → `lane-unreadable` (error, never read as "not lost"); negative `--feed-seq` → `bad-feed-seq`; error verdicts omit mapSeq/feedSeq; count validates the map before counting, so an invalid map errors even with `--line`.

## D3 — `main()` takes the outcome from the verb's return; EXIT_CODES gains current/skip 0 and drifted 1
kind: silent-seam
step: build · slice: 1 · decidedBy: executor
sources: [code:main, EXIT_CODES (design-map.py)]
rejected: a drift-specific exit path — duplicates the verdict machinery
supersedes: —
Three shared lines changed (EXIT_CODES, BOOLEAN_FLAGS/VALUE_FLAGS, main's return). Default outcome stays `ok`, so existing verbs are unchanged; expect a textual merge conflict with ESAS-164 on the flag tuples, not a behaviour one. `current` means equal (map ahead of feed is `drifted`), per the module docstring — D5 does not define it.

## D4 — A fleet lane's drift skip is the script's `no-map-feed`, relabelled `fleet-lane-no-feed` in the PR
kind: silent-seam
step: build · slice: 3 · decidedBy: verifier
sources: [design:block D5 lane bullet, code:drift (plugins/bett3r-ai-workflow/scripts/design-map.py)]
rejected: a script-side `fleet-lane-no-feed` reason — drift cannot know it runs in a lane without a new flag the block does not name
supersedes: —
D5 says "`--no-feed` → `skip reason=fleet-lane-no-feed`", but `--no-feed` prints `reason=no-map-feed`. The PR label is the agent's; verify-build.md and ADR-006 now say so.

## D5 — The drift step is numbered Step 5a2, not a renumbering of 5b onward
kind: deviation
step: build · slice: 3 · decidedBy: executor
sources: [code:commands/verify-build.md step headings, code:scripts/test-flow-seams.sh first_line lookups]
rejected: renumber Step 5b..9 — cascades through every citation and seam lookup
supersedes: —
