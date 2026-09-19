---
name: grill
description: Grill me. Interview relentlessly over a printed decision tree, each fork under fixed headings, until shared understanding. Use for "grill me" or to stress-test a plan or design.
---

Call the Skill tool with "grilling". This skill is the flow's delta over it: the printed tree, the fork shape, the confirmation of a decided fork, and how the tree meets a live map.

## The tree

Open with the decision tree, before the first question: a numbered list, one line per fork, never the question restated, the fork's name and what it turns on. Keep the tree current: re-print it whenever its shape changes, a resolved fork collapsing to its answer in a few words and anything it opened joining as a new line. The tree names the forks; the questions arrive in `grilling`'s rounds.

## Presenting a fork

Every fork put to the user is written under these literal headings, in this order:

```
**The Problem:** one short statement of what is actually undecided.
**Use Case:** one concrete case that shows why it bites — named cast, real values.
**Options:** the options laid out so the divergence is visible on sight — a
  side-by-side/stacked per-scenario timeline where the fork is about how data
  moves, the per-option scenario walks otherwise. Never a trade-off paragraph.
**Recommendation:** your answer, and one line of why.
```

Under **Options**, name the scenarios the fork must cover (the normal path plus the ones that discriminate: the retry, the concurrent edit, the empty set, the crash between two steps) and walk each per option as a use case plus timeline with the diverging step marked and an outcome line, keeping each walk to the steps that differ. **Where every scenario walks identically across the options there is no fork**: resolve it yourself and record it as an autonomous decision with its rejected options. A simple fork answers all four headings in one line each.

Present the options as a numbered list; the user answers free-form. That is the whole picker, and `AskUserQuestion` has no place in this flow.

Two rules of address hold in every paragraph. **Restate every reference at every mention**, coined labels ("b3", "scenario A") and outside identifiers (ticket keys, requirement numbers, ADR ids, element names) alike, as a few words in parentheses saying what the thing *is*: *"**KEY-123** (*outbox redelivery drops the version watermark*)"*; a second identifier restates nothing. And **bold the load-bearing claim inside each paragraph**, so a bold-only skim gives the fork's shape and the recommendation.

## Confirming a decided fork

Once the fork is decided, show the chosen option's walk back as **Given/When/Then** and record it on the map as `given`/`when`/`then`: it is the test that will be written, and the owner reading a `then:` catches a mis-aimed oracle before an executor pays for it. `design-map candidates` and `check-plan` consume it and refuse a prose walk. Where the rule is "every X must do Y", the walk stays prose under `kind: structural`. **An open fork is presented, never pinned**: no Given/When/Then until an option is chosen.

Where a fork concerns the flow, a skill or a command this session is itself running, the session is a participant: an observation is evidence about the loaded version, never about the design question, so name the version.

### Where a map is live

A map is live when `design-map` reports `DESIGN-MAP:v1 … outcome=ok`; Call the Skill tool with "design-map" for what is posted and when. A dependent fork reaches the map as its title and what it waits on, until its answer unlocks it. With a live map the terminal keeps one line per fork and no full cards. **The tree is unconditional; the map is not**: with no map, every fork is asked in the terminal exactly as above. Where `/design` has put the eventstorming board on, `esas-design` owns that surface.

## High-leverage probes

Each collapses a branch in one move; fire the relevant one early.

- **Background-wake dependence.** Where the design relies on a background task re-invoking a session (a held socket, a watcher, a poll loop), ask what the consuming text says when the wake arrives inside the platform's `[SYSTEM NOTIFICATION - NOT USER INPUT]` banner; the design disarms it explicitly, as `esas-design` does.
- **Unverified platform behaviour.** Where a load-bearing fork turns on how a tool or platform behaves, measure it in-band: arm the observation, ask the next fork in the same message, let the turn end, and report what arrived with the version that produced it.
- **Side-effect reconcilability.** For a retried, non-idempotent external side-effect, ask whether the external system answers "does this already exist?" by a natural key. Yes: reconcile by it, with no local dedup store. No: check for idempotency or an existing dedup target; only a non-idempotent, non-reconcilable effect earns a best-effort local ledger.
