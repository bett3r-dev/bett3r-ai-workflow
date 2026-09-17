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

## D6 — The D+ provisioned-map path is unreachable today: a map.json-only folder reads owner=unowned
kind: false-premise
step: build · slice: 2 · decidedBy: verifier
sources: [code:work-docs-path --owner-branch (plugins/bett3r-ai-workflow/bin/work-docs-path), design:block F1 D+ and D2]
rejected: change work-docs-path in this unit — out of the block's scope; a silent owner rule is a design decision
supersedes: —
D2 stops on `unowned`, and the provisioner (ESAS-166) leaves only `map.json`. Step 4 says the case is unreachable until a map-only-folder owner rule exists. Escalated as E162-1 (recommendation: the provisioner writes the ownership header, or work-docs-path reads a no-design.md folder holding a map.json as `none`).

## D7 — An owner=self re-run uses its own previously committed map.json as-is
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [design:block F1 "uses an existing map.json as-is"]
rejected: rewrite on every self re-run — contradicts "use as-is" for the provisioned case, which Step 4 cannot distinguish
supersedes: —
A re-run whose tree changed but kept its fork count commits the stale map; a changed count stops on count-mismatch. Escalated as E162-2 for ESAS-163 (next to touch Step 4).

## D8 — design.md is written only after render passes; a refused render on a self re-run leaves the prior map.html deleted, uncommitted, for the human
kind: silent-seam
step: build · slice: 2 · decidedBy: executor
sources: [code:render (design-map.py) removes the page on refusal, design:block D3]
rejected: write design.md first — then a refusal must remove it too
supersedes: —
Also: a `design-map write` refusal writes and commits nothing, and ends blocked-on with its reason. The AC3 single-writer grep's blind spots are recorded in design.md Risks.

## D9 — The drift refresh runs the owner check before `design-map write`, not after render
kind: deviation
step: verify-build · slice: — · decidedBy: lane
sources: [design:block D2 and D5, code:commands/verify-build.md Step 5a2]
rejected: D5's literal order (get_map → write → render → owner check) — overwrites map.json in a folder another work item owns before discovering it
supersedes: —
D2 says none of the three files is written on `other|unowned|error`; D5's listed order contradicts it. D2 wins. A refused render on refresh flags and commits nothing.

## D10 — ADR-006 states that the single-writer grep is partial and that the D+ carry path is unreachable today
kind: shipped-finding
step: verify-build · slice: — · decidedBy: lane
sources: [code:scripts/test-design-snapshot.sh AC3 grep, design:decisions D6]
rejected: leave the ADR asserting full coverage and a working carry — an ADR outlives the PR
supersedes: —
