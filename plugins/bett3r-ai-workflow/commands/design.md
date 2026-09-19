---
description: Design step. Ground the ticket against the code, grill the forks the code cannot settle, critique the result, then write and commit the design doc with its map.
---

# /design

This is the `design` step; its verdict is `LANE-STEP:v1 step=design …`. Its mode marker reads `mode: design`. It ends with a committed `design.md` and map in the folder `work-docs-path` names.

## Argument: $ARGUMENTS

The thing to design: a ticket id, a feature description, or "the active work".

## Step protocol

**Brief.** If `.work/lane.yaml` exists you are an unattended lane: take every input (`work_item`, `branch`, `worktree`, `runDir`, `gateDeferred`, `sliceBudget`, `mapProvenance`, `preconditions`, the rest) from it and ask no one anything. A fact it hands down is a claim to verify against the tree before you build on it. Without the file you run attended: inputs come from the user and the working tree.

**Mode marker.** Rewrite `.work/mode.yaml` whole: `mode: <this step>`, `work_item:` and `branch:` carried forward exactly as `/start` recorded them, `updated:` now. The file is replaced, not merged or appended; only `/start` clears it.

**Verdict.** Your last line is `LANE-STEP:v1 step=<this step> outcome=<success|gate-red|blocked-on>` with this step's attributes, at column 0 with nothing after it. Run `lane-step-record '<the identical line>'` immediately before printing it (it records the verdict on the branch when the brief opts in). Printing the line ends the run: take no turn after it.

## Step 0 — Board gates

Two gates, in this order. **On a no, say nothing at all**: no offer, no mention that a gate was consulted. When it is close, unsure means silent.

### The map gate

A design map is posted with the `design-map` skill and needs no `.esas/`, which is why this gate comes first. If `.work/lane.yaml` exists, the run is unattended: the map gate is a silent no. Otherwise it is a yes when the drafted tree has at least one open owner fork, a decision only the owner can make. Shape: **impact** for an epic parent, **decision** for a lone ticket. A map is live when `design-map` reports `DESIGN-MAP:v1 … outcome=ok`.

### The eventstorming gate

No `.esas/` in this repo is a no for this gate, and silent like every no. Otherwise the board is on when it is both **possible** (`.esas/` with a `graph.json`, `esas-mcp` registered) and **warranted** (the design's forks name graph artifacts: commands, events, policies, read models, aggregates). Classify by the tree in front of you, not the label on the ticket ("frontend" is not outside the model: `ui` is a node type). Relevance runs before the preflight, whose verdict table speaks, and is never a preflight key. Re-ask at every new artifact-touching fork: a design that opens on config and turns structural at fork 4 arms then. Capability is `esas-design/PREFLIGHT.md`; everything downstream of a yes is [BOARD-SETUP.md](../skills/esas-design/BOARD-SETUP.md).

### Combining the gates

Judge the five inputs and run the block; its one line is the verdict for both gates. `open_owner_forks` and `artifact_forks` count forks in the drafted tree; `epic_parent`, `lane` (`.work/lane.yaml` exists) and `esas_capable` are `1` or `0`. `map=yes` sends you to `design-map`, `es=offer` to the preflight; anything else is silence.

<!-- BOARD-GATE:v1 -->
```sh
# usage: sh board-gate.sh open_owner_forks artifact_forks epic_parent lane esas_capable
map=no; shape=-; es=silent
if [ "$4" -eq 0 ] && [ "$1" -ge 1 ]; then
  map=yes
  if [ "$3" -eq 1 ]; then shape=impact; else shape=decision; fi
fi
if [ "$5" -eq 1 ] && [ "$2" -ge 1 ]; then es=offer; fi
printf 'BOARD-GATE:v1 map=%s shape=%s es=%s\n' "$map" "$shape" "$es"
```

Completion: the block has printed its line and you have acted on exactly what it says.

## Step 1 — Ground

Under a brief, the ticket is `ticket.body` and each `handedDownFacts` entry keeps its `applies` / `verify whether it applies` label; say which mode you run under. Read the ticket, then the bounded context's `CONTEXT.md` (via `.esas.config.json` `domainEventsPath`). Where there is none, fall back through `docs/adr/` to the module headers of the symbols the ticket names, reading the headers even when the ADRs hit; write "grounding degraded: no CONTEXT.md" into the doc and recommend `/seed-context`. The glossary is evidence to verify, not ground truth.

**Seed concerns from explicit bars in the ticket.** An explicit bar states a condition of shipping ("must not exceed 200ms"); an acceptance criterion phrased as a feature is not one. For each bar, capture it now with the `concern` skill (`raisedBy: ticket owner · step: design`, `quote:` the ticket's own sentence). When unsure whether a sentence is a bar, capture it `soft`. A ticket with no bar seeds nothing.

**Context providers.** A repo may declare `contextProviders` in `.claude/bett3r-ai-workflow.json`; the contract is [CONTEXT-PROVIDERS.md](../CONTEXT-PROVIDERS.md). The base plugin ships none and zero providers is the normal case: with none declared, do not mention that an extension point was consulted. A provider that errors, times out or returns nothing never fails `/design`: note `grounding degraded:` with its own reason and continue. Where one is declared, call it anchored on the cited code paths and glossary terms, and keep every returned item beside its citation id and verbatim span. Only a contribution the provider marks canonical may settle a fork; anything pending, backfilled or text-matched opens one. A refusal is never written up as "no recorded decisions", a claim about the corpus where all you have is an outage: the fork stays open as `store-unreachable`, distinct from `no-atoms-matched` and `only-pending`.

### The ticket is evidence, not spec

Where the ticket and the code disagree, the code wins, and the doc says so. Symbol and count discipline is [EVIDENCE.md](../EVIDENCE.md) §3. Probe in this order, since each layer reframes the ones below:

1. **History before body.** `git log --oneline <BASE> --grep=<ID>`: hits make the body a historical document and the deliverable a per-section SHIPPED / OUTSTANDING ledger with shas.
2. **Citations by identity.** Re-locate cited code by symbol (`grep` the identifier), confirm a cited ADR section is about the cited subject, and cite as `symbol (file:line)`.
3. **Existence claims.** `git log --all --grep=<ID>` for a cited sibling ticket; a concept-noun grep for the mechanism, host surface or "does not reuse X" item the ticket assumes; a hit count is a classified list, never a number. A negative ("no such mechanism exists") is settled by searching the engine's own source by concept noun and recording the search that failed, and a subagent's negative is re-run by you before you act on it.
4. **The load-bearing claim**, the one that forecloses an option, verified at the frame that constructs the object it names, on the lane it was observed on; "throw or return?" is answered at the caller, "does data X exist?" at a writer of X. A claim repeated in ticket, comment and ADR is one claim when each cites the previous, and when false every site carrying it is work; an auto-resolution's prerequisite chain is checked before it settles; an edge case with no precedent keeps the invariant; a widening is additive only after grepping every other reference to the type.
5. **Prior art is a convention, not correctness.** An option a prior ADR rejected is re-checked mechanism by mechanism, including any "right if X" condition it named, and the outcome recorded as a bisection (`Superseded` is for a decision that no longer binds); for "mirror X", one probe goes to the cross-cutting concerns X gets wrong (erasure, authorization grants, redelivery, account scoping); a "stand up a new <thing>" checklist comes from `git show --stat --find-renames` over the last genuine greenfield series.
6. **Assumptions about behaviour are run, not read**: render the template, call the function, grep the assertion string rather than the test file's name.
7. **Achievability.** Name the mechanism that satisfies each acceptance criterion; where none can exist, withdraw the AC by name as the headline finding, and check the ACs against each other under the named invariant. A command dispatched by a rule, policy or cron names its principal and the gate that catches a missing grant; where none exists, the grant is an acceptance criterion.
8. **A replaced mechanism gets a DIES / SURVIVES inventory per repo**; oracles name the implementation surface, never the ubiquitous-language term, and every component names the repo that contains it, established by locating the file.

Across all eight: check the *mechanism* behind a stated rationale, not just the ask; a claim about another repo's runtime checks the artifact that executes; a worked example of the defect in the ticket is run; when the ticket says a comment is wrong, `git log -S` the phrase, since its size is the set of decisions citing the claim. An override of ticket-prescribed architecture is a rejected option and an open fork, never a silent correction; an ADR that corrects a premise ships the corrected reason, and one that kills a repeated claim carries a grep-and-fix over the existing occurrences.

Completion: every claim the design rests on carries its probe and result, or is marked `UNVERIFIED`.

## Step 2 — A resolved-design block

Grep the ticket for `design-multi:resolved:v2`. Present, this run is a verification second pass, not a fresh grill: treat each decision as a pre-answer, confirm it against current code (under a brief, `drift` is the provisioner's verdict on the block at BASE; read it first), and re-open a fork only where the code contradicts it; an undrifted ticket flows straight to Step 4. Verify the block's claims, not that its prose fits: a decision that re-argues an existing behaviour is re-derived, a mitigation is verified beside its risk, and a decision may be kept while its false premise is corrected in the PR body. Where `<path>/map.json` exists it governs the block's decision text (ADR-007): run `map-tree check --map <path>/map.json --ticket <work_item> --dialect jira <block file>` when the block carries a `map-tree:v1` region; `stale` or `tampered` is a correction Step 4 regenerates. Then enumerate what the block does not decide: for each rule it names, ask which sibling component performs the same operation, and emit the ones it is silent on as **unspecified seams**.

Completion: every decision in the block is marked confirmed, re-opened or corrected.

## Step 3 — Grill, then critique

Call the Skill tool with "grill". It layers the flow's fork shape over `grilling`. Where a canonical contribution from Step 1 settles a fork, quote its claim and span in the walk and carry its citation id into the fork's map status as `resolvedBy` beside `source`: a citation that lives only in the draft is destroyed by the next regeneration (ADR-007). Where the map gate said yes, Call the Skill tool with "design-map" and post the tree as it describes. Where the eventstorming gate offered and the user took the board, `esas-design` owns that surface.

Call the Skill tool with "domain-modeling" only when the interview changes the model: a term is challenged, a glossary entry resolves, or a decision earns an ADR, whose number comes from the brief's `adrAllocations` where there is one.

**Recording an answer.** Where the `contextProviders` declaration names a call for recording a decision, make it as each fork is answered, here rather than in Step 4: run `design-map record <path>/map.json` once the answer is in the map and make the declared call once per payload it prints, as the fields read. Where the call hands back an id, that id has one home: the sidecar the verdict names as `sidecar=`, keyed by fork id, committed with `map.json`; never `map.json` itself, never `resolvedBy`. Recording is never a gate: on a refusal repeat its own words, name the unrecorded fork, and continue; where nothing is declared, say nothing. Never probe whether the provider is up before calling: the call's own answer tells you.

Then Call the Skill tool with "critique" (`arch,ops`) on the resolved tree: one adversarial pass, not a second grill. Fold in what is right, return to the grill for a genuine fork it surfaces, and carry a weakness with no answer into **Risks**.

Completion: no fork is open, or every open fork is named as a `blocked-on` for a human.

## Step 4 — Write and commit the design

**Resolve the folder with `work-docs-path`**, passing the work item from `.work/mode.yaml` untouched: `work-docs-path --item <work_item>` — a Jira key, `#<n>` for a GitHub issue, or with no id the `<yyyy-mm-dd>-<slug>` that `/start` dated once. The script owns the root (`docs/prs` unless `.claude/bett3r-ai-workflow.json` sets `workDocsRoot`) and the id normalisation. Read its last line: `outcome=ok` names the folder as `path=`; `outcome=error` stops this step with its `reason=` and ends `blocked-on`. Never fall back to the default root or to a copy under `.work/`.

**An existing folder is overwritten only when it is this work item's**, and the design itself says whose it is: every design opens with an ownership header, rewritten on every pass, `work_item:` spelled as `.work/mode.yaml` spells it (a GitHub issue as `gh-<n>` or quoted, since a bare `#268` is a YAML comment) and `branch:` the branch writing it:

```yaml
---
work_item: TV1-2400
branch: TV1-2400-delete-items
---
```

Call the script once more as the writer, with the branch: `work-docs-path --item <work_item> --owner-branch "$(git branch --show-current)"`. It reads that header, never git history; readers never pass the flag, and it does not change `path=`; its verdict line carries `owner=`. Act on it and nothing else:

- `owner=none` — no folder, or only a provisioned `map.json` whose `mapId` is this work item: write `design.md` fresh, header first.
- `owner=self` — the header names this work item and this branch: overwrite `design.md` in place.
- `owner=other`, or `owner=unowned` — another work item's or branch's design, or a folder that proves no owner. Write nothing and end `blocked-on`, saying which and what the human does: run `/start` for a new work item, or, having confirmed the folder is this work's, edit the header's `branch:`/`work_item:` by hand, commit that, and re-run.
- `outcome=error reason=malformed-owner-branch` — a detached HEAD owns nothing. Write nothing and end `blocked-on`.
- `outcome=error reason=<any other>` — the config, the work item or the flags are unusable. Write nothing and end `blocked-on`, naming the reason.
- `no verdict line` — the script died before concluding. Write nothing and end `blocked-on`.

**The same rule holds for a `--item` folder**: one ticket can have two live branches, each branch's committed design is that branch's record, so a ticket folder written from another branch stops too, and re-designing on a new branch costs one hand edit of `branch:` that records the takeover. A renamed branch is likewise a false stop, the accepted safe direction. Its mirror is the one accepted false overwrite: a no-id branch deleted and recreated for unrelated work **on the same day** gets the same dated `work_item` from `/start`, so the header matches and the verdict is `owner=self`.

Every stop above writes none of `design.md`, `map.json`, `map.html`. On `owner=none|self`, in this order, every byte of both map files goes through `design-map`:

1. **The map.** An existing `<path>/map.json` is used as-is only when `.work/lane.yaml` carries `mapProvenance: carried`: it is the fleet's record of the owner's answers and is never re-authored in the lane; a design change that would alter its forks is an escalation to the orchestrator (a `/design-multi` re-run). Otherwise (the single flow, or `mapProvenance: lost`) every pass re-authors it: `mkdir -p <path>` and `design-map write <path>/map.json` with the drafted tree on stdin. A refused `write` commits nothing and ends `blocked-on reason=<its reason>`.
2. **Render.** `design-map render <path>/map.json --expect <n> --out <path>/map.html`, `<n>` the fork count of the tree you drafted, never derived from the file. On any verdict but `outcome=ok`, remove the `map.json` this pass wrote (a provisioned one stays), write no `design.md`, and end `blocked-on reason=<r>`; a refused render on an `owner=self` re-run leaves the tracked `map.html` deleted and uncommitted, which you name in the report and leave for the human.
3. **The doc, its decision text, the commit.** Write `<path>/design.md`: the header, then the sections below, one of them under the literal line `## Resolved decision tree` with nothing else on that line. Then `map-tree write --map <path>/map.json --ticket <work_item> --insert-after "## Resolved decision tree" --on-tamper displace <path>/design.md` and read its `MAP-TREE:v1` line: `written` proceeds; `displaced` proceeds and is named in the report (a hand edit inside the region moved under `### Displaced from generated section (<date>)`); `error` ends `blocked-on reason=<its reason>` with nothing committed. The region is the map's projection: change the map, not the region. Then commit it on every pass, a re-run included, with its map: `git add -- <path>/design.md <path>/map.json <path>/map.html && git commit -m "docs(<id>): design" -- <path>/design.md <path>/map.json <path>/map.html`. An unchanged re-run has nothing to commit. `lane-step-record` folds the verdict into this commit's message while that commit is unpushed, so do not push before it.

**Sections of `design.md`**, in the ubiquitous language. File paths and code are not design content (they rot); a `symbol (file:line)` citation, a Provenance command and a prototype's decision-carrying snippet are evidence and stay:

- **Problem** and **Solution**: what the user faces and what changes, from the user's side.
- **User Stories**: numbered, `As a <actor>, I want <feature>, so that <benefit>`, covering the whole feature.
- **Resolved decision tree**, under the literal line `## Resolved decision tree`: the generated region, each pivotal fork with its answer, why, and the rejected options.
- **Implementation Decisions**: modules and interfaces touched, schema and contract changes, a Mermaid diagram of the key flow and any new boundary crossed.
- **Testing Decisions**: the test seams (existing over new, the highest, the fewest, ideally one, each with prior art to mirror), confirmed with the user since they become the slices' oracles; and the riskiest thing nothing catches automatically, the tracer bullet.
- **Risks**: each weakness with no good answer, and what would surface it.
- **Out of Scope**: explicit in and out, follow-ups, and the **unspecified seams** this design deliberately does not decide, above all one adjacent to a specified seam, where the stated rule is what will be reused.
- **Provenance**: the commands that produced this design's numbers and claims, so the next context can re-run them.

Completion: `<path>/design.md`, `<path>/map.json` and `<path>/map.html` are committed together as `docs(<id>): design`.

## Step 5 — Hand off

Answer this first: could a fresh session holding only this repo and the committed `<path>/design.md` run `/plan` without loss? Enumerate what this session produced (files, commands and their outputs, counts, external state) and confirm each is in the doc, committed, or re-derivable by a command the doc names. An artifact the design names as a test seam, gate or tracer-bullet instrument is committed, or the doc says the first slice creates it. A citation target must be reachable from the base its reader branches from, so anything outside this session (a ticket, a sibling, a fleet brief, an ADR) cites the committed `<path>/design.md`, never a path under `.work/`.

Summarise the resolved design, the `CONTEXT.md`/ADR updates and the open risks:

> Review `<path>/design.md` (committed). When it's right, run `/plan` to cut it into vertical slices.

**Verdict.** `outcome=success` when the tree is resolved and `<path>/design.md` is committed. `outcome=blocked-on` when a fork needs a human and no reading settles it (in a lane that is an escalation, since a guessed fork reads as resolved) or when `work-docs-path` answered `outcome=error`. No gate runs here.
