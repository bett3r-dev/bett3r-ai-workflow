---
description: Fleet designer. Resolve N tickets' designs in parallel and unattended, batch the genuine forks into one human sitting, write each resolved design back into its ticket. Phase A is `design-lane`.
---

# /design-multi

Take a list of tickets through the code-answerable half of `/design` in parallel, compress the human half into one batched sitting, and leave each ticket carrying a resolved design that `/start-multi` consumes unattended. You are the orchestrator: you dispatch read-only `design-lane` agents, hold the one interview yourself, and write back. `/design`'s engine is `grill`, which has no mechanical gate, so the split is by what settles each fork: the code (Phase A, unattended), the owner's intent (Phase B, one sitting), then the write-back (Phase C). Run state is `.work/design-multi/<run-id>/run.yaml`, ephemeral and resumable.

Three rules hold in everything the owner reads. **Refer to tickets and forks by name**, never a bare id or a run-local label ("Fork R2"); the labels die with the run directory. **The fork list is an index, not a store**: a decision's detail lives in its ticket block, the list gists and points. **Fog is not out of scope**: a question in scope but not yet sharp enough to decide is named as fog; work ruled beyond this run is out of scope and never graduates.

## Argument: $ARGUMENTS

Ticket ids (with optional descriptions), then flags: `--max-parallel N` (concurrent lanes; read-only, so the machine tolerates more than `/start-multi`, while the bill does not: say what the wave is expected to cost), `--run-id <id>`, `--fresh`. The default run id is `design-multi-` plus the sorted ids.

## Step 0 — Acquire, snapshot, pin

Resolve the run id; resume if `run.yaml` exists and not `--fresh`. Otherwise fetch each ticket once into `<run>/units/<id>.ticket.md`, body verbatim; lanes read the snapshot, never the tracker. When the tracker has an epic link, the snapshot's header block (column 0, before the first blank line) carries `parent: <EPIC>`, the only place Phase B's grouping reads it. Grep each snapshot for `design-multi:resolved:v(\d+)` and read its `run=`. This run's marker short-circuits the unit to a verification pass recording `already_done`, `still_valid` or `stale` (Phase A runs and replaces the block; the marker is the section's identity, so one block only). Another run's marker stops you to ask the owner (reuse, replace, or drop the unit), since Phase C could not write over it.

Pin `BASE=$(git rev-parse origin/<default>)` after `git fetch origin`, the base `/start-multi` will branch from. Prove the tree the lanes read is the pin: `git merge-base --is-ancestor` in both directions, and `HEAD == BASE` stated. On a mismatch, pin `HEAD` and record it, or brief every lane to prove its cited paths are identical at both (`git diff --name-only $BASE HEAD -- <paths>` empty) before emitting a `file:line`. Record `treeClean` only paired with the sha it is clean at. Re-verify the pin at Phase C.

Completion: every unit has a snapshot on disk, `run.yaml` records `groundedBaseSha`, and the tree is proven at it.

## Step 0.5 — Wave-0 fact audit

Before any lane, one read-only agent surveys the shared surface (the bounded contexts the tickets name) and writes `VERIFIED-FACTS.md`: what exists, as `symbol (file:line)`; a section for every place ticket text contradicts the code; the modules it did not look at and the queries it did not run. Its brief asks what a per-ticket lane pays for N times and cannot act on:

- Does every `Depends on:` dependency exist in code, and is every ticket the wave should contain in the run set? A designed-but-unbuilt supplier is a window, not a block: the consumer asks whether its job is to amend the supplier's design and names what closes the window (a merge, a deploy, production data), and every lane re-derives its own dependencies rather than inheriting the line.
- Is every shared grounding doc the brief cites still true? A stale shared doc is a false premise multiplied by N.
- Is every name a ticket proposes to mint free? `grep -rn "^export \(type\|interface\|const\|function\) <Name>"`, `ls` the package dir, `git ls-tree <BASE>` the records dir; report a collision with the existing definition's location and consumer count, and propose the vocabulary split.
- For each premise "X is an instance of the class Y handles", verify the membership, not that X and Y exist; sweep the uncited "since X" / "because X" clauses; establish "F returns X over C" by running F over C.
- Every count and negative universal ("the only", "none of", "all N sites") carries the command that swept it and its complement query (additive DDL net of its `drop`, a moved derivation's inverse, an extractor's branches against the variant table); a handed-down enumeration is a sample unless it carries its sweep.
- "Not in this tree" is not "unverifiable": a gitignored or per-checkout artifact is probed in another checkout of the repo on this machine and reported `EMPIRICAL — <path>@<sha>, out-of-tree`.
- Smoke-test any live dependency a probe needs (`nc -z localhost 5432`) and hand each lane `probe infra: UP` or `DOWN — do not spend calls`.

The auditor writes its own greps under `design-lane`'s probe hygiene (quote every glob; the shell may be zsh).

Completion: `VERIFIED-FACTS.md` exists with its three sections: exists, contradicts, did not look at.

## Step 1 — No worktrees

Phase A is read-only: every lane reads the one working tree, sound while it matches the pin and stays clean, and a lane notes in its draft if it grounded against uncommitted work.

## Step 2 — Dispatch `design-lane`, one per ticket

Up to `--max-parallel`, each grounded at `BASE`. The agent owns the protocol; you own:

- **Single writer.** Only you write `run.yaml`. A lane that fails unrecoverably is `failed`; the others continue.
- **The snapshot is the ticket.** Refuse to dispatch a lane whose `units/<id>.ticket.md` is not on disk; every brief points at that file as the ticket of record and says the brief's prose is commentary.
- **Labelled facts, with a stamp.** Every inherited statement is a claim with a provenance and an expiry ([EVIDENCE.md](../EVIDENCE.md) §3), so every handed-down fact is `APPLIES [verified <date> via <command>]` or `VERIFY`. `VERIFY` regardless: no stamp or one older than the base; a count or negative universal without its sweep and complement; anything in the audit's did-not-look-at list; a fact sourced from a sibling's design rather than code; a path or symbol that is designed, not built (`designed, not built (owner <TICKET>)`). A fact in more than one ticket is verified once, by you, and the verified form handed down. The brief lists the unit's downstream consumers beside its suppliers and carries each supplier's mode decisions (substrate, transport, who writes which file) into every consumer's facts.
- **Collect from disk.** `stat` the `units/<id>.*` files, and when `design-map` is on `PATH` and the draft has an open fork, require `units/<id>.map.json`. A task-completion notification is evidence the agent stopped, never evidence it produced anything.

Between Phase A and B, run the probes the lanes parked as orchestrator-runnable (a committed sandbox certificate, a vendor SDK in the repo), batched per external system, and label every answer `EMPIRICAL — <env> <date>`; a sandbox accepting something is not proof production will.

Completion: every unit in `run.yaml` is `critiqued` with its draft (and, where forks are open, its fragment) on disk, or `failed` with a reason.

## Step 3 — Collect

Aggregate per-unit state into `run.yaml`. On resume a unit continues from its next incomplete step; one already `critiqued` with a draft on disk is skipped.

Completion: every unit in `run.yaml` has a `step:` and a `status:`.

## Step 4 — Phase B: the one sitting

Phase B is one `grilling` round over the cross-ticket frontier: every open fork across all tickets, asked together. Call the Skill tool with "grill" and present every fork as it says. The owner arrives cold on N tickets and the answers run unattended with no gate behind them, so the walks are what make the collapses below visible.

**Item 1 is the grouping into subjects.** Run `design-multi-subjects group <run>/units [--seams <accepted.json>] [--prior <grouping.json>]` and read its `DESIGN-MULTI-SUBJECTS:v1` line. The default subject is the epic (`parent:`); a unit with none is a singleton. From the seam index below, propose splits of an epic subject or merges of singletons sharing an artifact, each with its basis; only accepted proposals go into `--seams`. Persist `subjects[{id, units, basis: epic|seam|singleton, confirmed, confirmedAt}]` and `subjectsFingerprint` to `run.yaml`. On resume an equal fingerprint reuses the grouping silently; otherwise run with `--prior` and re-ask only the `asked=` subjects.

**Three gates before anything is asked.** Whose call is it: a fork that more reading or thinking settles is the engineer's (check sibling ADRs for precedent on the same kind of decision); only one that turns on what the owner wants (market, customer, risk appetite) is theirs. Are the options exclusive: an N-way fork whose answer is "all of them" is a mis-framing. The seam index: group every draft's open forks and resolved contract clauses (timeouts, transports, who writes which file) by the concrete artifact touched, across this run and its supplier runs; an artifact in two lanes' entries is one fork with both positions shown, or your ruling in `decisions.md`.

Then the collapses only this sitting can make. Present a root fork before the forks that depend on it, and resolve a dependent one to a single recommendation or mark it *depends on <root, named>*. Re-frame an answer that names an impossible combination onto the option that delivers its intent, with the evidence. After the answers, re-verify the one or two claims those answers made load-bearing. When an answer establishes a cross-cutting fact, re-scan every unit's drafted recommendations against it and record what it kills as withdrawn-with-reason. Unify overlapping glossary terms and duplicated scope across tickets, carrying corrections to shared docs as one action. Recommendations are quoted from the critiqued draft's fork section, never from a ticket or an earlier summary. A fork `grill` would resolve itself (identical walks) is auto-resolved with its rejected options before the sitting. Where the owner answers neither way on "take the recommendations", the report says they were applied on recommendation, since silence is not assent.

**One map per subject.** Call the Skill tool with "design-map"; its fleet companion carries the how. In outline: after the gates and collapses, compose each subject map in memory from the unit fragments (`mapId: <S>`; `grounded` and `shape` from the fragments, which must agree; forks concatenated in unit order; nodes unioned by id, a conflicting id escalated) and pipe it through `design-map validate` and `design-map write <run>/subjects/<S>.map.json`; `design-map select` per subject chooses board or artifact; `design-map render --stack` renders every subject on one page, each subject's `--expect` re-derived from its fork count. The terminal keeps one line per fork; the card holds the picture, scenarios, walks and recommendation.

**On the canvas**, where `/design` Step 0's two gates, answered once for the run, both say yes and `design-map` is absent, Call the Skill tool with "esas-design"; it owns the surface. Here: `comment` and `resolve` are the only verbs, and no agent writes to the design layer (The design layer is scoped to one unit of work and Phase B holds N, so you post the batch, one `comment` call with arrays in). Prefix every comment with its ticket id and title, since comments are one flat list per anchor. Resolve each comment as its fork is answered. Above roughly fifteen open forks, keep the whole list in the terminal. Hold the summon channel open across the sitting: one `Monitor({ ws: { url: 'ws://127.0.0.1:3727/api/esas/ws' }, persistent: true })`, opened as you post. With `design-map` present, forks go to the subject maps and never to canvas comments; the canvas only anchors an element question a map links to.

Completion: every open fork has an owner answer, an applied recommendation, or a named dependency on another fork.

## Step 5 — Phase C: finalize and write back

Confirm before writing to the tracker; it is outward-facing.

1. **Re-ground.** Re-verify the pin (Step 0), re-run each unit's premise probes and re-resolve its `groundedShas`; a fix the owner shipped mid-sitting collapses its ticket. Stamp each block with the sha it was written against.
2. **Every answer takes one path.** Answers from page or terminal are rows carrying `map: <S>` in `<run>/answers/`; each subject enters through `design-map apply-answers <run>/subjects/<S>.map.json <run>/answers/`, and a row whose `map` is another subject's is skipped and counted in `otherMap=`. Resolve every comment `apply-answers` prints; then, only on the owner's word in the terminal and never on a wake, `apply-answers … --final` per subject. Where the repo declares a recording call, `design-map record` per subject offers the answers back as `/design` Step 3 does, ids into the per-subject sidecar; a refusal or no declaration never fails the sitting.
3. **One answer per fork.** `decisions.md` in the run dir is Phase B's record: cross-cutting policies first, hand-written; the per-ticket part generated by `design-map decisions` over the subject maps. An override of a pre-sitting auto-resolution edits the original entry to `SUPERSEDED BY P<N>`. Before fold-back, `design-map decisions --closed` over each subject map (`design-map decisions <run>/subjects/<S>.map.json --closed`) prints `DESIGN-MAP:v1 outcome=ok verb=decisions open=0 …`; read the verdict line, and `reason=open-forks` stops fold-back.
4. **Project one map per ticket.** `design-map project --ticket <id> <run>/subjects/<S>.map.json | design-map write <run>/units/<id>.map.json`. That projection feeds the fold-back's `map-tree write`, the `/start-multi` provisioner, and the tracker-writer brief. A fleet map is frozen here; an overturn is a `/design-multi` re-run.
5. **Fold back, join, then write.** Per-unit fold-back agents run in parallel, write-scoped to their unit: each rewrites Open forks into Resolved forks (rejected options kept), applies ripple edits, emits `<id>.ticket-block.md` marker-line-first with its decision text generated by `map-tree write --dialect jira --map <run>/units/<id>.map.json --ticket <id> --insert-after "<the block's decision-tree heading>" <id>.ticket-block.md` (a non-`written` verdict refuses the block), and emits an `obligations-on-siblings` list (target, obligation, why). Join the lists: every target block carries its obligation or is patched or re-dispatched, and obligations are diffed against each other by target with a third outcome beyond present and absent, **contradicted**, adjudicated on reasoning and a retired row recorded as retired. A deferral naming another unit is a ticket; one naming no owner is refused: before the first write and again before the report, `grep -rn -i -e "TO FILE" -e "UNOWNED" -e "NO OWNER" -e "no verified owner"` over every `decisions.md` and `*.obligations.md` in the run dir, and every hit names a ticket key or blocks the write ("the orchestrator" is no owner). Where an acceptance criterion and a rejected option constrain the same surface, the block states which governs. In a dependency-ordered campaign a supplier block for a later wave is held or written expecting addenda, said which in `decisions.md`. A critique-promoted AC the sitting de-collided to a sibling is an `owner: <ID>` cross-reference, not an AC.
6. **The epic's goal oracle.** The epic gets one goal-level oracle, owned by no unit, asserting its own "Done is verifiable by" end to end across every seam it spans (cross-repo included), committed RED before the first unit is cut; `/merge-multi` reports it. A tracer bullet's oracle touches every seam its scope sentence names.
7. **ADRs first, then blocks.** The ADR/glossary agent (single writer) finishes before any ticket or epic block is written; cross-references are by reserved identifier from `run.yaml`. Numbers are allocated as `domain-modeling`'s "In this flow" says, against the re-verified Phase-C base; diff them against what `run.yaml` reserved and print old → new on a collision. Glossary/ADR deltas ride in the block as `delta: specified, deferred to build` (which section, what it must say, what it waits for), discharged by `/build` or `/verify-build` on the branch; a delta cited by two tickets names its owning unit, and only a delta documenting an already-shipped decision is committed here, on a proper branch.
8. **The block**, appended after a `---` separator (read-modify-append), the description being the single machine-readable channel `/start-multi` reads:

    ```
    <!-- design-multi:resolved:v2 status=ready base=<BASE-sha> run=<run-id> -->
    ## Resolved Design (design-multi)
    `design-multi:resolved:v2 status=ready base=<BASE-sha> run=<run-id>`
    { the map-tree:v1 region from `map-tree write --dialect jira` · seams/flow ·
      test seams · risks · unspecified seams · scope · file overlap vs siblings }
    ```

    The block's sections are `/design`'s spine (Problem, Solution, User Stories, Resolved decision tree, Implementation Decisions, Testing Decisions, Risks, Out of Scope, Provenance) plus **File overlap with siblings**, which `/start-multi` reads for `deps` and waves. `status` is required, one of `ready | deferred | blocked | umbrella`; a ticket ready once a named sibling lands is `status=ready deps=<TICKET-ID>`, never a coined word, since `/start-multi` reads only the four and silently drops a fifth. Every non-`ready` verdict carries `buildableNow`, `blockProof` (needs X, dependency gives only Y, therefore Z) and `resolutionPath`. The marker is emitted twice, HTML comment and inline code, every structured attribute (`status`, `base`, `run`, `deps`) on both lines identically, never only in prose; `resolved-marker-lint <id>.ticket-block.md` runs before every write and a non-zero exit refuses the block. Readers tolerate whitespace between marker and heading; `:vN` bumps only when the block's shape changes, and the inner `map-tree:v1` pair is not a second dispatch marker. Every path a block, addendum or filed ticket cites is proved reachable from the `base` it stamps (`git cat-file -e <BASE>:<path>`) or labelled `new (created by <TICKET>)`, `cross-repo <repo>@<sha>:<path>` or `non-repo read: <command>`.
9. **Every tracker write goes through one [`tracker-writer`](../agents/tracker-writer.md) agent per wave**, sequential, never parallel or inline; it owns the preflight, the ADF budget, the preserved region and the read-back diff. Your brief per item: key, source file, kind, `<run>/units/<id>.map.json`, `run-id`, the stamped `BASE`, and whether another session is active with its *no other writer* claim. Check its report: one `TRACKER-WRITE:` line per dispatched item and a `TRACKER-WAVE:` line; a missing line is an unwritten item, and every `stopped` item and failed re-verify goes to the owner rather than around. Where it reports another run's block, cross-check this run's cross-cutting policies against that block before deciding.

Completion: every `ready` unit's description carries exactly one `design-multi:resolved:v2` block that passed lint, and every non-ready unit's block carries its three fields.

## Step 6 — Report and capture

Per ticket: forks auto-resolved, forks the owner resolved, what was written (with any `CONTENT_LIMIT_EXCEEDED` refusal and what was compressed), deltas, the `BASE`; short-circuited units (Step 0) reported distinctly. Re-derive any status you quote from the tickets, not from a mid-run table. Aggregate `<run>/units/*.learnings.md` with your own Phase B/C friction and run `/capture-learnings` once.

Completion: every unit appears in the report, and `/capture-learnings` has run once.

If Phase B used the canvas, the handoff names the teardown: this run's comments live in a design layer scoped to one unit of work, so tell the owner to delete `.esas/design.json`, `.esas/design.json.bak`, `.esas/ops.jsonl` and `.esas/.claude-cursor` once done reading, and only after any unit built in this checkout (`/build`'s scaffold step reads `design.json`); never delete the files yourself, since they are gitignored and the only copy of the sitting's intent.

> Designs resolved and written to the tickets. Run `/start-multi <ids>`: it detects the resolved designs and runs `design` as a verification second pass, so the fleet stays unattended unless the code has drifted.

## The phase boundary

**Each phase is a tick, not a session.** `/design-multi` ends its context twice — at the A/B and the B/C boundary — and each phase opens cold against the run dir, exactly as `/start-multi` ends at a wave (**The tick boundary**, [`start-multi`](start-multi.md)). Ending loses nothing because each phase's primary source is already on disk, and the two ends are the same **kind** of end: the context stops, nothing is carried over in memory, and the next phase reconstructs what it needs by reading it back from the run dir. The phase is read from `units[].step` and never stored: `pending`/`drafting` is Phase A running, every unit `critiqued` or `failed` is the A/B boundary, every unit `resolved` is the B/C boundary, and `written`/`done` is Phase C finished. A `phase:` key in `run.yaml` would be a second and staler answer to a question `units[].step` already answers.

1. **A/B.** Step 3's collect is the A/B boundary: print the A/B verdict and **end your context**. Phase B opens cold and restarts from `<run>/units/`, which is its primary source — each unit's `.ticket.md` snapshot, `.design-draft.md` and `.map.json` fragment, plus the run dir's `VERIFIED-FACTS.md` — and it re-runs `design-multi-subjects group <run>/units` over that directory rather than trusting a remembered grouping, an equal `subjectsFingerprint` reusing it silently as Step 4 says. A resumed sitting reads the owner's answers back with `read_db` over the `answers` collection, never from any surviving session state, as the [`design-map`](../skills/design-map/SKILL.md) skill's readback specifies; a sitting the owner half-answered and left therefore resumes from the artifact db with the answered forks already answered.
2. **The owner opens Phase B by hand, and no driver ever does.** The sitting is attended by definition, so a driver re-dispatching it opens a session nobody is sitting in and every remaining fork is taken on its recommendation with no one present to notice. That is enforced rather than requested: the A/B verdict is

        FLEET-STEP:v1 outcome=blocked-on blockedOn=awaiting-owner-sitting phases=1/3 units=<t>/<u>

    at column 0 with nothing after it, and `blocked-on` is what a reader of the line ([`lane-step`](../bin/lane-step), which prints the attributes and decides nothing) hands its driver as a stop, never a tick-again. `t` is the units at `critiqued` or `failed` and `u` every unit in `run.yaml`.
3. **B/C.** Step 4's completion — every open fork answered, applied or dependency-named — is the B/C boundary, and the B/C boundary ends this context the same way, printing `FLEET-STEP:v1 outcome=success phases=2/3 units=<t>/<u>`. Phase C opens cold and restarts from `<run>/subjects/` and `<run>/answers/`: the subject maps carry the resolved forks, and every answer the sitting took in the terminal is written as a row in `<run>/answers/` — in the shape Step 5.2 reads, `map: <S>` included — **before** this context ends, because a terminal answer that exists only in the sitting is the one thing this boundary can lose. Phase C re-verifies the pinned base anyway (Step 5.1), so a fresh context changes nothing it was not already going to re-derive, and its own end prints `phases=3/3`.

This boundary is `/design-multi`'s, and **nothing here licenses a `/merge-multi` yield by analogy** — that command's length is its unit count and a per-unit yield on this pattern is possible, but it is deliberately undesigned; inventing one from this section would be inventing a boundary nobody chose.

## run.yaml

```yaml
runId: design-multi-...
groundedBaseSha: <pinned origin/default>          # start-multi verifies drift against this
flags: { maxParallel: 4 }
subjects:                                           # Phase B item 1; orchestrator is the only writer
  - { id: ESAS-156, units: [TV1-123, TV1-124], basis: epic,   # epic | seam | singleton
      confirmed: true, confirmedAt: 2026-09-16T10:00:00Z }
subjectsFingerprint: <sha256 from design-multi-subjects>  # equal on resume → reuse silently
units:
  - { id: TV1-123, step: critiqued, status: in_progress,
      draft: units/TV1-123.design-draft.md,
      openForks: 2, ticketWritten: false }
    # step: pending | drafting | critiqued | resolved | written | done
```
