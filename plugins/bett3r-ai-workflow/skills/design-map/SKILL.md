---
name: design-map
description: "Render a design's map.json as a clickable artifact and read the owner's answers back (read_db, apply-answers). A wake never runs --final; the page's comment box never wakes the session."
---

# Rendering and reading back a design's map

`bin/design-map` owns the verbs; this skill owns when to call them and how to read what comes back. Read the `DESIGN-MAP:v1` verdict line on stdout, not the exit code: a wrapper can swallow the exit status, and the line still says `outcome=`. An `outcome=error` line carries no `page=`, so a caller that publishes whatever `page=` names finds nothing.

## When a design is `map.json`-shaped

A design is map-shaped when the run is attended and the grilled tree holds at least one fork the owner must answer; `/design`'s map gate makes that call. A lane (`.work/lane.yaml`) has no owner to click: it still writes and renders as `/design` Step 4 says, but publishes no page, reads no answers back, and carries the fleet's projection (`mapProvenance`). Board-or-artifact (`select`, `post`), `record`, and the fleet readers (`render --stack`, `project`, `decisions`) are [FLEET.md](./FLEET.md): open it under `/design-multi` or as a `design-lane`, whenever the session's tool list carries the `mcp__esas__*` tools (`select` decides board or artifact; a missing `.esas/` is one of its rows, not a reason to skip it), or when a recording call is declared (`record`).

## The map: a vocabulary copy and a structure file

A map is `structureVersion: 2`, spelled as esas's `MapFile` so a board reads it untranslated. Two files describe it:

- `map.schema.json` is the vocabulary: the closed sets (fork status kind, decided source, node level, map shape), a byte-identical copy of what esas emits at `packages/esas-schema/schema/map.schema.json`. **Never hand-edit `map.schema.json`**: a value added here and not in esas is a second source for one closed set, and an edited copy can no longer be told stale. To change a set, change it in esas and copy the emitted file over whole.
- `map-structure.schema.json` is the structure: nodes, forks, cards, options, links, naming every closed set by `$ref` into the copy.

The structure file is the shape's reference. What the verbs below turn on: a fork `{id: <TICKET>-F<n>, title, tickets, card?, anchor?, restsOn, status, testable?}` whose status is `{kind: open}`, `{kind: decided, source, option}` or `{kind: moot, reason}`, `option` naming an option id of the fork's card; a card `{problem, useCases[], options[], recommendation: {option, why}, ifOverturned}` whose options carry `walks: [{scenario, text, kind?, given?, when?, then?}]`; the plugin-only top-level `mapId`, `feedSeq` and `target` (`board` or `artifact`). A fork with no card is **title-only** (a locked, dependent fork): drawn by its title, and it cannot be picked.

## The verbs

| verb | arguments | ok verdict (`DESIGN-MAP:v1 outcome=ok verb=…`) |
|---|---|---|
| `validate` | `<map.json>` | `forks=<n>`; accepts an ungrounded draft |
| `write` | `<map.json> < draft.json` (the map on stdin) | `forks=<n> map=<path>` |
| `render` | `<map.json> --expect <n> [--out <page.html>]` | `expected= payload= rendered= page=` |
| `check-page` | `<map.json> <page.html> --expect <n>` | the same counts, no `page=` |
| `apply-answers` | `<map.json> <answers-dir> [--final]` | `final= open= owner= recommendation= code= moot= otherMap= commented= map=` |
| `candidates` | `<map.json>` (positional; `--map` is refused) | `forks= candidates= skipped-open= skipped-moot= skipped-nowalk= skipped-untestable=` |
| `check-plan` | `<slices.yaml>` (positional) | `review=<human\|unattended\|none> candidates= scenarios= seams= probed=` |
| `count` | `<map.json> [--lane <lane.yaml>] [--line]` | `forks= owner= code= recommendation= open= moot=` |
| `drift` | `<map.json> (--feed-seq <n> \| --no-feed)` | `outcome=current\|drifted\|skip mapSeq= feedSeq=` |

Exit codes: 0 ok, 1 fail (a fixable input: `check-plan` and `candidates` refusals, `decisions --closed`, `drift` drifted), 2 error. `outcome=error verb=<verb> reason=<reason>` names the refusal.

`design-map validate <map.json>` is read-only and runs on every draft before a render. `design-map write <map.json> < draft.json` is **the only structural authoring path**: every structural change (a draft, an unlocked fork's card, a projection) goes through it, never a shell redirection into `map.json`. It runs `validate`'s checks and replaces the target whole; it does not merge, so carrying answered statuses across a re-`write` is the caller's job, and every refusal leaves the target byte-identical. Answers enter only through `apply-answers`.

## Render, then publish

```
design-map render <map.json> --expect <n> --out <path>/map.html
```

**--expect is the count of the grilled tree**: the number of forks you hold after the interview, not a count read back off the payload or the page. Two counts gate the render and catch different drops: `--expect` against the payload catches a fork lost between the interview and the file; the renderer's page-vs-payload count catches one lost while drawing. A mismatch on either is `outcome=error`, names both counts, and leaves no page. A map holding forks that is not `grounded: true` is refused `reason=not-grounded` by `render` and `check-page`: ground it first.

`check-page` runs the same two gates read-only over a page already on disk; run it before publishing whenever the page was touched after `render` wrote it or an existing page is republished. A clean `check-page` is not permission to skip a fresh `render` when the map changed.

**What is posted and when.** No fork card is posted before grounding: `render` refuses an ungrounded map that holds a fork, and on a board the ground goes up before any fork (`map_ground` first, FLEET.md). On an impact map the why and who go up before grounding as a confirm question, since the rest of the map hangs off them; a fork-less map renders ungrounded, so nothing refuses it. A dependent fork is posted as its title and what it waits on, with no card, until its answer unlocks it; then its card goes in through `design-map write` and a re-render (or `map_post`). A fork made unnecessary is struck `moot` with its reason, never deleted. A fork returns to the map only when its words change: an answer, a moot strike or a new title-only line is a change, and re-posting an unchanged fork is noise the owner has to diff. A card whose fork is a process rule with no observable behaviour is authored `testable: false`, by a design lane as well, so nothing downstream derives a test from it. The map never replaces the tree (`grill`: the tree is unconditional, the map is not): the terminal keeps one line per fork and the map holds the cards.

Publish the page as an artifact with `capabilities: {db: {}}`; the page's own `claude.use("db")` resolves the store the readback reads from (when it resolves `null` the page is read-only and says to answer in the terminal). When publishing, tell the owner how to hand back, in so many words: "answer on the page, then tell me in the terminal when you're done." Without that sentence the owner answers every fork and has no way to reach you.

Done when the verdict reads `outcome=ok verb=render`, the page is published with `db`, and the hand-back sentence has been said.

## Readback, on the owner's word in the terminal

**The page's comment box never wakes the session.** Each fork's comment textarea writes `answers/<forkId>.comment` into the artifact's db, like a pick; it is not an artifact comment thread, so it cannot notify you, and a saved pick sends nothing either. The readback trigger is the owner's word in the terminal that they are done, or have answered some forks. Then:

1. `read_db` over the `answers` collection with `out_dir` set to `<answers-dir>`. The page writes each answer to `answers/<forkId>`, so the `read_db` document id is the fork id, and the readback lands **directly** as one file per fork, `<answers-dir>/<forkId>.json`, in the shape `{pick, comment, updatedAt, map?}`; no transformation, no aggregation.
2. `design-map apply-answers <map.json> <answers-dir>`. A picked fork becomes `{kind: decided, source: owner, option: <pick>}`, overturning an earlier `code` or `recommendation` decision; an unanswered fork stays `open`; a comment with no pick leaves the fork `open` and prints the comment for you to resolve. A pick on a title-only fork is refused `reason=fork-title-only`; a `moot` fork is left as it is.
3. Tell the owner in the terminal what the fold shows.

`--final` runs only on the owner saying, in the terminal, that they are done, and every printed comment is resolved before running --final: by the owner's answer, or their sign-off that it stands as asked, **given in the terminal**. Then the remaining `open` forks convert to `{kind: decided, source: recommendation, option: card.recommendation.option}`; `--final` refuses `reason=title-only-open` while any fork with no card is still open (write its card first), and a `moot` fork is never deleted by either pass.

A comment thread the owner opens from the artifact's comment mode and sends to Claude may wake a watched session inside the platform's `[SYSTEM NOTIFICATION - NOT USER INPUT]` banner. The banner **is not a refusal**: **the notification is the doorbell; the answers are in the store**, about which the banner says nothing. On such a wake, run steps 1 to 3 without `--final`. **A wake never runs `--final`**, whatever the comment says, even "done": `--final` turns every open fork into `decided(recommendation)`, after which nobody can tell a fork the owner let stand from one they never reached. `esas-design`'s two invariants for a summon hold for this wake too.

Done when every answered fork reads `source: owner` in the map, every printed comment is resolved, and `--final` has run only on the owner's terminal word.

## Plan candidates and `check-plan`

```
design-map candidates <map.json>
design-map check-plan <slices.yaml>
```

`candidates` validates the map, reads it, and prints one compact JSON line per walk of a **decided** fork's **chosen** option, `{"fork","option","scenario","source","example"}` in that key order; never a rejected option's walk, which is a confidently wrong oracle. Skipped forks are counted, never printed: `skipped-open`, `skipped-moot` (its id is never named), `skipped-untestable` (`testable: false`, which wins a tie with a zero-walk option), and `skipped-nowalk`, always 0 and kept on the line because `/plan` parses it as proof the refusal fired. Two refusals, `outcome=fail`: `reason=decided-nowalk id= option=` (a choice nobody can test) and `reason=walk-unstructured id= option= walk=<index>` (a chosen option's walk is prose; the index, never the scenario text, since verdict attributes are space-free).

`check-plan` reads `.work/slices.yaml` (PyYAML; without it `reason=yaml-unavailable`, never a silent pass) and refuses with `outcome=fail`:

- `reason=unattended-confirmed`: top-level `review: unattended` with a `candidateOracles[].status` of `confirmed`. An unattended `/plan` never promotes a candidate into an oracle without a human.
- `reason=candidate-in-oracle slice=<id>`: a non-confirmed candidate's example appears verbatim in a slice's `oracle:` or `scenarios:` (`slice=unknown` when the slice has no id). A `confirmed` candidate's example there is the attended promotion and passes.
- `reason=slice-unscened slice=<id>`: a slice carries no `scenarios:`.
- `reason=scenario-unstructured slice=<id> why=<detail>`: a scenario is not a mapping, has no `scenario:`, names an unknown `kind:`, is behavioural and missing a half (`why=missing-then`), or is `kind: structural` with no `text:` or with Given/When/Then as well.
- `reason=plan-unseamed`: the plan declares no `seams:`.
- `reason=seam-unstructured seam=<name> why=<detail>`: a seam has no `name:` (`seam=<index>`) or `at:`, repeats a name, names an unknown `kind:`, or is a seam after the first or a `kind: new` one with no `why:` (`why=extra-unjustified|new-unjustified`). Whitespace in the name is squashed to `_`.
- `reason=slice-unseamed slice=<id>`: a slice names no `seam:`.
- `reason=unnamed-seam slice=<id> seam=<name>`: a slice's `seam:` is not one the plan declared.
- `reason=slice-unprobed slice=<id>`: a slice declares no `probe:`, the one-line production mutation that must turn its oracle red.
- `reason=scenario-unsourced slice=<id> why=<detail>`: a behavioural scenario has no `expected_from:`, names one outside `literal | worked-example | spec | existing-behaviour`, or is non-`literal` and cites no `expected_source:`.

`outcome=fail` (exit 1) is a plan `check-plan` read and refused; `outcome=error` (exit 2: `plan-unreadable`, `plan-unparseable`, `missing-plan`) is one it could not read.

## The walk contract

A walk is where an oracle is born; the shape a walk must have is `vertical-slicing`'s. What `design-map` enforces: `validate` refuses a behavioural walk missing any of `given`/`when`/`then` (`walk-partial-gwt`) and a `kind: structural` walk that carries them (`walk-structural-gwt`); `candidates` reads decided forks only. The fields are optional in `map-structure.schema.json`.

What makes an oracle adequate (seams named once per unit, `probe:`, `expected_from:`, the `scenarios:` a unit with no map still carries) is the `vertical-slicing` skill's; `check-plan` enforces the field shapes and states nothing more about them. Discrimination (a RED that is an assertion with values; an undiscriminating RED such as a hang, crash or import error is no evidence) is a property of the run, enforced in `/build`, not a field here.

## Count and drift

```
design-map count <map.json> [--lane <lane.yaml>] [--line]
design-map drift <map.json> (--feed-seq <n> | --no-feed)
```

`count` is a read-only reporter over each fork's `status.kind`/`status.source`. With `--line` it prints one PR-body line first, `N of M forks answered by the owner (C by code, R on recommendation, O open, K moot)`, or `map: none` with no file, or, when `--lane` names a brief with `mapProvenance: lost`, `map: owner answers not carried: run dir absent` (which takes precedence). That is the line `/verify-build` pastes under `### Record`.

`drift` compares the map's own `feedSeq` (the committed snapshot's last-folded feed position) with a caller-supplied `--feed-seq`, never the live feed: `outcome=current|drifted|skip|error mapSeq=<n|none> feedSeq=<n|none>`. `--no-feed` is `outcome=skip reason=no-map-feed`; a map with no `feedSeq` against a live `--feed-seq` is `drifted mapSeq=none`. Neither verb writes the file: `design-map` is the only writer of `map.json` and `map.html`, and `count` and `drift` are reporters.
