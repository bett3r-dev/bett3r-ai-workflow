---
name: design-map
description: "Renders a design's map.json as a claude.ai artifact the owner answers by clicking, and reads answers back. Render with --expect as the count of the grilled tree (a mismatch stops); optional check-page re-runs the same counts over an existing page before publish. Publish with capabilities: {db: {}} and tell the owner to say done in the terminal: the page's comment box never wakes the session. On the owner's word, read_db over the answers collection with out_dir = <answers-dir> (doc id = forkId; lands as <answers-dir>/<forkId>.json), then apply-answers; read the DESIGN-MAP:v1 line, not the exit code. A wake never runs --final: --final, and resolving every printed comment before running --final, need the owner's word in the terminal. STANDING DISARM (unmeasured): a comment-mode thread sent to Claude may arrive wrapped in a NOT USER INPUT banner. That is not a refusal — the notification is the doorbell, the answers are in the store. Two invariants: tolerate an empty wake; never propose from partial answers."
---

# Rendering and reading back a design's map

`bin/design-map` (`plugins/bett3r-ai-workflow/scripts/design-map.py`) owns the
verbs; this skill owns when to call them and how to read what comes back.

## The map: a vocabulary copy and a structure file

A map is `structureVersion: 2`, spelled as esas's `MapFile` so a board reads it
untranslated. Two files describe it, and they are kept apart on purpose:

- **`map.schema.json` is the vocabulary** — the closed sets (fork status kind,
  decided source, node level, map shape), a byte-identical copy of what esas
  emits at `packages/esas-schema/schema/map.schema.json`.
  **Never hand-edit `map.schema.json`**: a value added here and not in esas is a second source
  for one closed set, and an edited copy can no longer be told stale. To
  change a set, change it in esas and copy the emitted file over whole.
  `scripts/test-design-map.sh` compares the copy with `$ESAS_CHECKOUT` when
  that is set, and prints `SKIP reason=no-esas-checkout` (not a pass) when it
  is not.
- **`map-structure.schema.json` is the structure** — nodes, forks, cards,
  options, links. It names every closed set by `$ref` into the copy, so no
  value is restated.

The shape, in brief:

- top level: `structureVersion: 2`, `shape` (required once `grounded: true`),
  `grounded`, `nodes[]`, `forks[]`, `links[]` (optional), and the plugin-only
  optional `mapId`, `feedSeq` (integer >= 0) and `target` (`board` or
  `artifact`);
- node: `{id, level, title, parents: [nodeId], struck?: {reason}}`;
- fork: `{id: <TICKET>-F<n>, title, tickets: [KEY, ...], card?, anchor?: nodeId,
  restsOn: [forkId], status, testable?: false}`;
- status: `{kind: open}`, `{kind: decided, source, option}` or
  `{kind: moot, reason}` — `option` names an option id of the fork's card;
- card: `{problem, useCases[], options[], recommendation: {option, why},
  ifOverturned}`; option: `{id, label, walks: [{scenario, text, kind?, given?,
  when?, then?}], rejectedBecause?, evidence?[]}`. **A fork with no card is
  title-only** (a locked, dependent fork): it is drawn by its title and cannot
  be picked.

Node, fork and option ids and `mapId` match `^[A-Za-z0-9-]+$`; fork ids are unique, node ids are unique, option
ids are unique per fork, and every `anchor`, `parents`, `restsOn` and link
`deliverableId` must resolve (`dangling-ref`).

## Validate

```
design-map validate <map.json>
```

Read-only: `outcome=ok forks=<n>`, or `outcome=error reason=... [at=...]`. It
accepts an ungrounded draft, so run it on every draft before a render.

## Write — the only structural authoring path

```
design-map write <map.json> < draft.json
```

Every structural change to a map — a new draft, a card added when a
title-only fork unlocks, a projection — goes through `write`, never a shell
redirection into `map.json`. It reads the full map on stdin, runs exactly the
`validate` checks, and replaces the target whole via a temporary file in its
own directory: `outcome=ok verb=write forks=<n> map=<path>`. It does not merge
with the file it replaces — carrying answered statuses across a re-`write` is
the caller's job. On any refusal (`missing-map`, `map-dir-missing`,
`map-unparseable` for stdin that is not JSON, or any `validate` reason) the
target is byte-identical, and an absent target is not created. Answers never
enter through `write`; they enter only through `apply-answers`.

## Render, before publishing

Once the grilled decision tree is settled and written into `map.json`, render
it:

```
design-map render <map.json> --expect <n> [--out <page.html>]
```

**--expect is the count of the grilled tree** — the number of forks I hold in
my own head after the interview, not a count read back off the payload or the
page. It is mandatory (C1/F2): the two counts it gates catch different drops —
`--expect` against the payload catches a fork lost between the interview and
the file I wrote; the renderer's own page-vs-payload count catches one lost
while drawing. A mismatch on either is `outcome=error`, names both counts, and
leaves no page behind.

A map holding forks that is not `grounded: true` is refused with
`reason=not-grounded` by both `render` and `check-page`, and no page is
written: an ungrounded draft is never drawn for the owner to answer. Ground it
first; `validate` still accepts it meanwhile.

Decided forks are drawn in one style per decided source — owner,
recommendation and code are three distinct styles — and a legend on the page
names each.

## check-page, optional, before publish

`design-map check-page <map.json> <page.html> --expect <n>` runs the same two
gates read-only, over a page already on disk — one hand-edited, or published
earlier. Run it before publishing whenever the page was touched after
`render` wrote it, or whenever republishing an existing page rather than a
fresh render. It writes and removes nothing, so a clean result is not itself
permission to skip a fresh `render` when the map changed.

## Publish

Publish the rendered page as an artifact with `capabilities: {db: {}}` — the
page's own `claude.use("db")` call resolves the store this skill later reads
back from. When that resolves `null` the page degrades to read-only and tells
the owner to answer in the terminal instead; nothing here needs to detect that
case, the page already carries the fallback.

**When publishing, tell the owner how to hand back**, in so many words: "answer
on the page, then tell me in the terminal when you're done." Without that
sentence the owner answers every fork and is left with no way to reach me.

## Readback — on the owner's word in the terminal

**The page's comment box never wakes the session.** Each fork's comment
textarea writes `answers/<forkId>.comment` into the artifact's db, like a
pick; it is not an artifact comment thread, so it cannot notify me. Observed
2026-09-17: a page published with `capabilities: {db: {}}` on a watched
session ("auto-replies armed"), every fork answered and "done" typed into
F1's comment box — no notification of any kind reached the session. A saved
pick sends nothing either.

**The observed readback trigger is the owner's word in the terminal** — that
they are done, or have answered some forks. Sync then.

Run `read_db` over the `answers` collection with `out_dir` set to
`<answers-dir>`. The page writes each answer to `answers/<forkId>`, so
the `read_db` document id is the fork id, and the readback lands **directly** as
one file per fork, `<answers-dir>/<forkId>.json`, already in the D10 shape
`{pick, comment, updatedAt}` — no transformation, no aggregation.
`apply-answers` reads that directory as written.

### The disarm: a comment-mode thread is not a refusal (unmeasured)

A different path exists: a comment thread the owner opens from the artifact's
own comment mode and sends to Claude. That **may** wake a watched session,
arriving inside the platform's `[SYSTEM NOTIFICATION - NOT USER INPUT]`
banner. **This is not measured** — the 2026-09-17 run did not exercise that
path, so neither the wake nor the banner's wording has been observed. The
disarm stays for that case: read as a refusal, the banner would end the
gesture silently while the owner watches a page that answered nothing. It is
not one: **the notification is the doorbell; the answers are in the store**,
about which the banner makes no claim. On such a wake, run the same readback —
`read_db` over `answers` into `<answers-dir>/`, then fold with
`apply-answers` **without `--final`**. **A wake never runs `--final`**,
whatever the comment says — even "done". The banner-wrapped comment is the
doorbell, not the owner's word; `--final` turns every open fork into
`decided(recommendation)`, after which nobody can tell a fork the owner let
stand from one they never reached. Tell the owner in the terminal what the
fold shows and wait for them there.

**Two invariants**, carried over from `esas-design` because they are
properties of turn-based answering, not of any one transport:

- **Tolerate an empty wake.** A comment is not necessarily an answer — the
  owner may only be asking a question. `read_db` returning nothing new (or a
  comment with no `pick`) is a normal outcome, not an error; the fork stays
  `open` and the comment is surfaced for me to reconcile, exactly as
  `apply-answers` already does without `--final`.
- **Never propose from partial answers.** Only act on a fork once every fork
  it depends on is resolved. A readback mid-answer is a snapshot, not the
  owner's final word — do not recommend, summarize as decided, or move on to
  a dependent fork off a partial fold.

## Fold and finalize

```
design-map apply-answers <map.json> <answers-dir> [--final]
```

Read the outcome from the `DESIGN-MAP:v1` verdict line on stdout, not the exit
code (ADR-004) — a wrapper can swallow the exit status; the line still says
`outcome=error`.

Without `--final`, a picked fork becomes `{kind: decided, source: owner,
option: <pick>}`, an unanswered fork stays `open`, and a comment with no pick leaves the fork `open` and prints the
comment for me to resolve. A pick also overturns an earlier `code` or
`recommendation` decision. A pick on a fork with no card is refused
`reason=fork-title-only`; a `moot` fork is left exactly as it is, even under a
pick naming no option. An answer whose `map` is not this map's `mapId` (or
that names a map when the map has none) is skipped unchecked and counted in
`otherMap=`; an answer with no `map` applies. The page writes `map: <mapId>`
into every answer when the map has a `mapId`. The verdict counts `open= owner=
recommendation= code= moot= otherMap=`. **Before running `--final`, resolve every printed
comment** (D8). `--final` runs only on the owner saying, in the terminal, that
they are done — never on a wake — and a comment still open at that point is
resolved by the owner's answer or explicit sign-off that it stands as asked,
**given in the terminal**, before the remaining `open` forks
convert to `{kind: decided, source: recommendation, option:
card.recommendation.option}`. `--final` refuses `reason=title-only-open`
(naming the first such fork) while any fork with no card is still open: write
its card first. A `moot`
fork is never deleted by either pass.

## The walk contract — a decided choice arrives as a testable scenario

A walk is where an oracle is born. `scenario` names it and `text` is what the
board renders; `given`/`when`/`then` are what a test can be written from without
re-deciding anything.

**The measured reason this is a rule and not a suggestion.** Across 966
classified fix rounds, `oracle-wrong` — the test encoded the wrong rule — is
**41%**, the largest single cause, and in the runs where it was itemised *every*
round came from a verifier finding and *none* from a red test. A test built from
prose goes red before the code exists and green after, and is still wrong: RED →
GREEN is an anti-tautology gate, and it cannot tell whether the rule asserted is
the rule that was decided. The only cause slice size controls, `ripple`, is 6%.

- **A behavioural walk carries all three of `given`, `when`, `then`.** Partial is
  refused at `validate` (`walk-partial-gwt`, naming what it has): a walk with a
  `given` and a `when` and no `then` renders exactly like a deliberate one, and
  it is the half-written one that yields an oracle asserting a setup instead of
  an outcome.
- **`kind: structural` keeps prose, deliberately.** A census assertion — *"every
  appender declares it, and no module outside `<owner>` appends"* — has a
  negative half that Given/When/Then has no room for. `/plan` already mandates
  that form for an "every X must do Y" rule, and it is the form that caught the
  worst defect in the corpus (a composition root whose two wiring lines could be
  deleted with 738 tests still green). Carrying both is refused
  (`walk-structural-gwt`): one of them is then decoration and nobody can tell
  which.
- **The contract binds a *decided* fork only.** An open fork is the state this
  whole tool exists to hold: nothing is chosen, so there is nothing to write a
  scenario against, and `candidates` skips it as it always did. The obligation
  lands the moment the fork resolves and its walk is about to become somebody's
  test — which is also the last moment it is cheap to fix.
- **Enforced at the promotion boundary, not in the schema.** `given`/`when`/
  `then`/`kind` are additive and optional in `map-structure.schema.json` so that
  every map written before this change still validates and still renders: esas
  types `MapOptionWalk` structurally with no runtime validator, so extra keys
  pass a board untouched. `candidates` is what refuses, because that is the one
  moment a walk becomes a test somebody writes.

## Plan candidates and the unattended-never-promotes contract (ESAS-165)

```
design-map candidates <map.json>
design-map check-plan <slices.yaml>
```

`candidates` validates the map, then reads it (never writing anything) and
prints zero or more compact JSON lines on stdout, one per walk of a **decided**
fork's **chosen** option (`status.option`) — never a rejected option's walk,
since a rejected option is a confidently-wrong oracle:

```
{"fork":"ESAS-1-F1","option":"A","scenario":"...","source":"owner","example":"..."}
```

in that fixed key order (fork, option, scenario, source, example). A fork is
skipped and counted, never printed:

- `skipped-open` — still `open`
- `skipped-moot` — `moot` (its id is never named in the output)
- `skipped-nowalk` — **can no longer happen**, and is kept on the verdict line
  at `0` because `/plan` parses that line and its zero is the proof the refusal
  fired rather than a fork being quietly dropped. A decided fork whose chosen
  option carries no walk is now `outcome=fail reason=decided-nowalk`: a choice
  somebody made that nobody can test, whose slice gets an oracle invented
  downstream from prose
- `skipped-untestable` — the fork carries `testable: false` (a process-rule
  card the design lane marks unoracled, ESAS-164); when both zero-walk and
  `testable: false` hold, `skipped-untestable` wins

Two refusals, both `outcome=fail` (exit 1 — a fixable map, not a broken tool):
`reason=decided-nowalk id=<fork> option=<id>`, and `reason=walk-unstructured
id=<fork> option=<id> walk=<index>` when a chosen option's walk is prose. The
walk's **index**, never its scenario text: every attribute on a verdict line is
space-free by contract, and a refusal nobody can parse reads downstream as no
refusal at all.

The verdict: `outcome=ok verb=candidates forks=<n> candidates=<n>
skipped-open=<n> skipped-moot=<n> skipped-nowalk=<n> skipped-untestable=<n>`.
`--map` is not a flag `candidates` knows — the map path is positional, refused
as `unknown-flag-map` otherwise.

`check-plan` reads a `.work/slices.yaml` (PyYAML; a Python without it is
`reason=yaml-unavailable`, never a silent pass) and enforces that an
unattended `/plan` never promotes a candidate into a slice's `oracle:` without
a human:

- `outcome=fail reason=unattended-confirmed` (exit 1) — top-level `review:
  unattended` and some `candidateOracles[].status` is `confirmed`.
- `outcome=fail reason=candidate-in-oracle slice=<id>` (exit 1) — a
  non-confirmed candidate's example appears verbatim in a slice oracle
  (`slice=unknown` when that slice has no id). A `confirmed` candidate's
  example copied into an oracle is the attended promotion (ESAS-165 D4) and
  passes.
- `outcome=fail reason=slice-unscened slice=<id>` (exit 1) — a slice carries no
  `scenarios:` at all.
- `outcome=fail reason=scenario-unstructured slice=<id> why=<detail>` (exit 1) —
  a scenario is not a mapping, has no `scenario:`, names an unknown `kind:`, is
  behavioural and missing a half (`why=missing-then`), or is `kind: structural`
  and either carries no `text:` or carries Given/When/Then as well.
- `outcome=fail reason=plan-unseamed` (exit 1) — the plan declares no `seams:`.
- `outcome=fail reason=seam-unstructured seam=<name> why=<detail>` (exit 1) — a
  declared seam has no `name:` (`seam=<index>`) or no `at:`, repeats a name,
  names an unknown `kind:`, or is a seam after the first / a `kind: new` one
  with no `why:` (`why=extra-unjustified|new-unjustified`). The name is emitted
  with its whitespace squashed to `_`, since a verdict is space-separated
  `key=value` and a prose name would otherwise be read truncated.
- `outcome=fail reason=slice-unseamed slice=<id>` (exit 1) — a slice names no
  `seam:`.
- `outcome=fail reason=unnamed-seam slice=<id> seam=<name>` (exit 1) — a slice's
  `seam:` is not one the plan declared: it tests somewhere nobody agreed to.
- else `outcome=ok review=<human|unattended|none> candidates=<n> scenarios=<n>
  seams=<n>` (exit 0).

**`scenarios:` is the half of the contract that reaches a unit with no map at
all**, and that is the half that was costing: both measured 0%-first-pass-green
runs were `review: unattended` with no `map.json`, so this whole candidate
pipeline emitted nothing and every oracle in fifteen slices was written freehand
from prose. A walk contract enforced only inside `candidates` would have left
exactly those runs untouched. `oracle:` keeps its meaning — the narrative of the
test; `scenarios:` is what the executor must make true, in a form it cannot
quietly re-interpret. The `candidate-in-oracle` search covers a slice's
`scenarios:` as well as its `oracle:`, or renaming the field would have been the
whole of the bypass.

**The seams are named once per unit, before the oracles.** Fewest, highest,
existing over new — the ideal number is one. Unpressured, eight slices invent
eight oracle locations, and each is an independent chance to assert below the
level the claim lives at; that is the shape of the worst defect in the corpus,
where the oracle sat at the unit rather than the composition root and both
wiring lines could be deleted with `tsc` clean and 738 tests green. *Highest* is
a judgement and stays one — what is checkable is that the seam is named,
located (`at:`) and defended, so the first seam is free and every one after it
owes a line saying why the named ones cannot hold the claim. A cap would be
wrong: some units genuinely need two. Silence was what was wrong.

`outcome=fail` (exit 1) is distinct from `outcome=error` (exit 2, e.g.
`plan-unreadable`, `plan-unparseable`, `missing-plan`): a plan `check-plan`
could read but that fails one of its two assertions is a different event from
one it could not read at all (ADR-004 — the line is the contract, and a shell
caller still needs the two exit codes apart).

## Fleet readers: stack, project, decisions (ESAS-166)

```
design-map render --stack <m1> <m2>... --expect <n1> <n2>... --out <page.html>
design-map project --ticket <K> <map>... | design-map write <units/K.map.json>
design-map decisions <map.json> [--closed]
```

`render --stack` draws several maps on one page. Every map is validated and
must be grounded, with the same refusals as a single render plus `map=<path>`
naming the map refused. There is one `--expect` per map, in argument order: a
different number of values is `reason=expect-count-mismatch`, and one map's
miss is `reason=count-mismatch map=<path>`. `--out` is required
(`reason=missing-out`), because no one map's directory is the stack's home. A
fork id in two maps is `reason=duplicate-fork-id`, since answers are keyed by
fork id. Any refusal leaves no page, and removes an earlier rendered page at
`--out`. The page holds one `<section data-map-id>` per map, in a fixed
order:

1. most `open` forks first;
2. then the lowest ticket key over all the map's forks' `tickets`, compared
   by project and then by number as an integer (`ESAS-9` before `ESAS-11`).
   A map with no forks sorts last;
3. then argument order.

A re-render is byte-identical, and the page gate counts every fork of every
map exactly once. Each answer the page saves carries `map: <mapId>` of the
fork's own map, when that map has a `mapId`. Verdict: `outcome=ok
verb=render maps=<n> forks=<sum> expected=<sum> page=<path>`. `check-page` does
not take `--stack`.

`project --ticket K` validates every input (a refusal names `map=`) and prints
a v2 map on stdout. It holds only the forks whose `tickets` contain K, in input
order. Its nodes are each kept fork's `anchor` and all of that node's ancestors.
`restsOn` entries naming a dropped fork are pruned, and a link is kept only
when its `deliverableId` is a kept node. `mapId` is K. `grounded` and `shape`
come from the inputs, and inputs that disagree are refused
(`grounded-mismatch`, `shape-mismatch`). A node id defined differently in two
inputs is `node-conflict`, and a fork id in two inputs is
`duplicate-fork-id`. `feedSeq` and `target` are not carried over. The verdict
`outcome=ok verb=project ticket=K forks=<n> nodes=<n>` is the last stdout
line, after the JSON. `write` drops a last stdin line that is `project`'s ok
verdict. If the last line is any other verdict line, `write` refuses
`reason=upstream-refused` and does not create the target, so a refused
projection cannot be written as a map.

`decisions` prints per-ticket Markdown: a `## <ticket>` heading per ticket
(ordered by ticket key), then one line per fork carrying that ticket:
`- <forkId> <title>: owner — <option> (<label>)`, `applied on recommendation —
…`, `code — …`, `moot — <reason>`, or `open`. A fork with two tickets is listed
under both and counted once. Verdict: `outcome=ok verb=decisions open=<n>
owner=<n> recommendation=<n> code=<n> moot=<n>`. With `--closed`, any open
fork is `outcome=fail reason=open-forks` (exit 1), and the Markdown is still
printed before it.

See [`map-structure.schema.json`](./map-structure.schema.json) for the full
payload shape and [`map.schema.json`](./map.schema.json) for the vocabulary it
refers to.

## Record — the payloads for an answered fork (XL-70)

```
design-map record <map.json>
```

`record` is pure over files, like `apply-answers`: no network call, no
subprocess, no tool of its own. It prints, before the verdict line, a JSON
array of one payload per fork the map says is **answered** — every fork with a
`decided` status, in map order — each carrying `forkKey` (the fork's own map
id, the join key), `question` (its title), `options` (every option label),
`chosen` (the map's `status.option`: the option **id**, not its label),
`chosenLabel`, `rationale` (the card's `recommendation.why`), `source` and
`tickets`. The whole derivation is therefore testable with nothing reachable,
and no caller retypes a fork id or an option from a transcript.

An `open` or `moot` fork counts in `unresolved=` and gets no payload: nothing
has been answered to record. A decided fork with no card counts in `nocard=`
and gets none either — its options and rationale live on the card, and a
payload missing them is a different claim, not a smaller one.

`sidecar=` names where the id a recorder hands back is written:
`<map path without its .json>.resolved-by.json`, beside the map, a JSON object
keyed by fork id, committed with the map. **Beside, not inside:** the fork
object is closed (`additionalProperties: false`), as is every `status` branch,
and the status kind refs the byte-identical copy of esas's vocabulary — so an
id in the map would be a cross-repo vocabulary change, not a field addition. **Named after its own map**, not a flat
`resolved-by.json`, because a run dir holds one map per subject in one
directory. That file is the id's one home. It is distinct from `resolvedBy` on
a fork's status, which carries what **settled** the fork; an id handed back by
a recorder says only where the answer was filed.

`record` **reads** the sidecar and never writes it: a fork whose id it already
holds counts in `already=` and is not offered again, so re-running the step
after a later batch of answers cannot post an earlier one twice. A sidecar that
does not parse is `reason=sidecar-unparseable` — never an empty start, which
would re-offer every answer in the map.

## Count and drift (ESAS-162)

```
design-map count <map.json> [--lane <lane.yaml>] [--line]
design-map drift <map.json> (--feed-seq <n> | --no-feed)
```

`count` is a read-only reporter: `outcome=ok verb=count forks=<M> owner=<N>
code=<C> recommendation=<R> open=<O> moot=<K>`, counted over each fork's
`status.kind`/`status.source`. With `--line` it also prints exactly one
PR-body line first — `N of M forks answered by the owner (C by code, R on
recommendation, O open, K moot)` — or `map: none` with no file, or (`--lane`
naming a lane brief with `mapProvenance: lost`) `map: owner answers not
carried: run dir absent`, which takes precedence over a missing map. This is
the line `/verify-build` pastes under `### Record`, per ADR-006.

`drift` compares the map's own `feedSeq` (a **Map snapshot**'s own
last-folded position — see Glossary) against a caller-supplied `--feed-seq`,
never the live feed itself: `outcome=current|drifted|skip|error mapSeq=<n|
none> feedSeq=<n|none> [reason=]`. `--no-feed` is `outcome=skip
reason=no-map-feed`; a map with no `feedSeq` plus a live `--feed-seq` is
`outcome=drifted mapSeq=none`; a missing map is `outcome=error`. Neither verb
writes the file — `count` and `drift` are reporters, per ADR-006's one-writer
rule.

## Choosing the target: board or artifact (ESAS-174, ADR-009)

```
design-map select --phase probe --captures <dir> [--map <map.json>] [--lane <lane.yaml>]
design-map select --phase start --captures <dir> [--map <map.json>] [--lane <lane.yaml>]
```

`select` is pure over files: no network call, no subprocess, no MCP tool of its own. Everything it
reads comes from a **captures directory** the agent assembles from what the session already showed
it, one file per input, always these names:

- `tools.txt` — the tool names from the session's own tool list, one per line (a bare name or a
  `mcp__<server>__<name>` one; either form counts). Absent or missing `status` reads as no MCP in the
  session at all.
- `status.json` — the body the `status` tool returned (success or `{ok:false,error:{code}}`), whole.
- `board.json` — the body of `curl -s --max-time 2 http://127.0.0.1:${ESAS_BOARD_PORT:-3727}/api/esas/status`.
  Only an empty or non-JSON body reads as the board being off (`board-off`); a JSON body with no
  `repoPath`, or with another repo's, reads as `board-other-repo`. That timeout is a ceiling, not a
  retry budget (D4: `select` never polls and never retries).
- `start.json` — only after a `board-candidate` probe leads the agent to call `start_map_session`;
  its body goes here for `--phase start` to read. Required for that phase: its absence is
  `outcome=error reason=missing-start`, exit 2.
- `pwd.txt` (optional) — the logical and physical cwd, one per line, for row 7's comparison against
  the board's `repoPath`. Absent means `select` falls back to the process's own `$PWD` and
  `realpath`.

**`probe` first, and only a `board-candidate` calls anything.** `select --phase probe` evaluates
rows 0-8 of the decision tree and returns `target=board-candidate reason=ok` or `target=artifact
reason=<row>` — never `board`. Only on `board-candidate` does the agent call `start_map_session`
itself (the one side effect in the whole path, because it is the call that creates `.esas/`,
ADR-009), capture its body as `start.json`, and then call `select --phase start`, which re-evaluates
rows 0-8 fresh (a stale probe is never promoted to `board`) and applies rows 9-11 over `start.json`.
Read the `DESIGN-MAP:v1 outcome=ok verb=select target=… reason=… probe=…` line, not an exit code —
`probe=skipped` marks a row-0 pin or a row-1 fleet lane, `probe=done` marks a table walk that ran.

**The silence contract.** Nothing in an artifact-target design's rows, prose or verdict lines names a
board, a port, or `.esas/` — the whole point of the table is that a repo that will never see a board
never learns the vocabulary exists. Two named exceptions. Row 7: the verdict's reason is only the token
`board-other-repo`; the agent's own message to the owner names the repo, read from `board.json`'s
`repoPath`, because that is the one fact the owner needs to know what is running where. And row 6
(`board-off`), in an attended sitting only,
prints the launch line **once, as information, never as a question** — it does not ask the owner
whether to start a board, it states that one could be. The launch line, when a repo has no graph at
all (`ESAS_DIR_MISSING`), names `esas-session-server --non-anchor` (BOARD-SETUP.md); with a graph, it
names the ordinary launch this skill already documents elsewhere.

**D3 — never launch anything (this skill, or `select`, does not spawn a process).** The choice of
target never triggers a launch by itself; a board only exists because something else already started
one, or because the owner acts on the one-time launch line above.

**D4 — never hang.** No row of the table retries, polls, or waits past the `--max-time 2` on the one
network call (`board.json`'s curl) it is built from. A slow or wedged board reads exactly like no
board: `board.json` is empty, row 6 fires, the design proceeds on the artifact.

**D5 — the board dies mid-sitting.** This is not a `select` row; it is what the agent does at a sync
point when `board.json`'s curl comes back empty on a design that is already `target=board`. Call
`get_map` once (no retry). If it answers, merge its readback statuses onto the local `map.json` by
fork id — a fork the readback does not mention keeps its local status untouched, and a fork only in
the readback (never locally known) is ignored — set the merged map's `feedSeq` to the readback's
`mapSeq`, and pipe the result into `design-map write <map.json>` on stdin (there is no dedicated merge
verb; `write`'s existing whole-file replace already expresses it). Tell the owner once, using the same
launch-line wording as row 6. If the board is **still** down at the next sync point, stop trying it at
all and render the artifact from `map.json` as it now stands. A failed MCP tool call anywhere in this
recipe (not just `get_map`) means no more MCP tool calls for the rest of the session.

**D9 — pinning the target.** The first `select` call whose phase is `start` (or whose probe already
resolves definitively) is followed by a `design-map write` that carries the resolved `target` in
`map.json`. From then on every `select` call short-circuits at row 0: `payload.target == "artifact"`
returns `artifact reason=pinned probe=skipped` with no table walk at all. The pin is only read when
`select` is passed `--map <map.json>`; without it there is no row 0 to match. A `board` pin is **not**
final the same way — it re-probes at the next sync point, and a probe failure there is D5's territory,
not a table row.

**D7 — proving board parity by reading the store back, never by comparing pixels.** After any upsert
to the board (a `map_post` or a `map_choose`), call `get_map` and check it with
`design-map post --expect <n> --map <map.json> --readback <getmap.json>`. It fails on a fork count
other than `--expect`, or on a different multiset of `(kind, source, reason, option)` across the two
sides; its verdict line adds `statuses=<sorted kind:source,...>` for the epic oracle to read.

**Board flow order.** `map_ground` replays before any fork's `map_post` — a fork can only be posted
onto ground the board already has. `map_choose`'s `seenSeq` is always the map's own `mapSeq`; it never
passes `source` (that is `map_post`'s field, for an owner decision arriving out of band — `map_choose`
is the interactive click path and the board derives its own source).

**Grill and the render/post verbs.** A grill (ESAS-164) treats `verb=render` or `verb=post` with
`outcome=ok` as evidence the design is live on its target — either is sufficient, neither implies the
other ran.

**D10 — no session label, no `ticketRefs`.** Neither is any part of this table or its captures;
ESAS-166 owns whatever eventually carries them.

**E19 — `/design-multi` calls `select` once per subject, never stacked.** Before ESAS-171b lands, a
multi-subject design does not accumulate multiple subjects onto one board session — each subject gets
its own `select` walk over its own captures.

## Glossary

- **Map snapshot** — the committed `docs/prs/<id>/map.json`: whatever
  `design-map write` or `apply-answers` last produced, carried into the repo
  by `/design` Step 4's commit (or, for a fleet lane, by the provisioner's
  copy of the run dir's projection, ADR-006). It is a point-in-time copy, not
  a live view of the feed.
- **`feedSeq`** — the map snapshot's own record of the feed position it was
  last folded against (optional, `map-structure.schema.json`). `drift`'s
  `mapSeq=` is this value, read from the file; the feed's current position is
  supplied by the caller as `--feed-seq` and reported back as `feedSeq=`.
- **Generated region** — the bytes between a `map-tree:vN` pair (HTML comment
  plus twin inline-code line, open and close), written only by `map-tree
  write` from one ticket's projection of `map.json` (ADR-007). **Stale**: its
  `src=` no longer matches the projection (or its `gen=` is old) — the map
  moved, and `write` regenerates it. **Tampered**: its body no longer matches
  its own `out=` — someone edited generated bytes; `design.md` displaces the
  edit, a Jira write stops. Not a dispatch marker: `design-multi:resolved:v2`
  is unchanged by it.
