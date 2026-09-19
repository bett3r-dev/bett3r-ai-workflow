---
name: vertical-slicing
description: Cut a design into vertical slices (tracer bullet first, prefactor first), each verifiable alone and sized to one executor context. Use when decomposing a feature or when a plan looks layer-by-layer.
---

# Vertical slicing

A **slice** is the smallest independently observable behaviour, cut top to bottom through every layer it needs, with a test that drives it end to end. Only a vertical slice has its own green signal; a horizontal layer ("all the schemas", "all the read models") has no standalone oracle, so the per-slice dual gate and commit-per-slice loop cannot run on it.

## Rules of a slice

- Each slice cuts a narrow but complete path through every layer it touches: vertical, not a horizontal slice of one layer.
- A completed slice is demoable or verifiable on its own. It declares the test that proves it (its **oracle**) and is done when that test is green and the verifier confirms the repo's invariants; then it is committed, one slice per commit.
- A slice fits one fresh executor context. One that cannot (by its surface, its scenario count, or how many layers it opens at once) is split.
- Prefactoring comes first. "Make the change easy, then make the easy change": reshaping existing code so the feature drops in cleanly (extract a seam, rename to the ubiquitous language, pull a shared helper) is the earliest slice.
- Invariants are complete the moment their aggregate appears; no later slice finishes an invariant.
- Named in the ubiquitous language (the area's `CONTEXT.md`), respecting the ADRs there; described as behaviour, not file paths or snippets. Exception: a decision-rich prototype snippet (a state machine, reducer, schema or type shape), trimmed to the decision.

## Tracer bullet first

Slice 1 is the thinnest end-to-end path through the riskiest gate-less seam: the part nothing automatically catches when it is wrong (a generated-artifact or deployment seam, a new integration boundary, a cross-aggregate contract). It is kept code, not a prototype, and it proves the seam holds before anything is built on it. A genuinely shared foundation (a schema five slices depend on, a migration) is what prefactoring and the tracer bullet establish: just enough skeleton, then vertical.

## Wide refactors: expand–contract

One mechanical change whose blast radius fans across the codebase (rename a column, retype a shared symbol) cannot land green as a tracer bullet. Sequence it: expand (add the new form beside the old), migrate in batches sized by blast radius (per package, per directory), each batch its own slice blocked by the expand, then contract (delete the old form) in a slice blocked by every batch. When even the batches cannot stay green alone, they share an integration branch and a final integrate-and-verify slice is where green is promised. A sweep over 10 files or 200 sites is split the same way; the cap exists for the fix round, because one finding anywhere in a sweep re-opens the whole sweep.

## A mechanism that governs the repo's own changes

A CI gate, a lint rule, a schema check: order the slices so a later slice in the same PR is its first live subject. Mechanism-last ships it asserted but unproven, and a gate that never fired is indistinguishable from a gate that cannot fire; both-in-one-slice turns the introducing commit red and invites weakening the gate.

## Seams: named before oracles, fewest, highest, existing

A **seam** is the boundary the unit tests at. Write the unit's seams down as the top-level `seams:` block before any oracle, and let every slice's `seam:` point at one. Prefer an existing seam to a new one, and the highest one that can still observe the claim, so the oracle lands where the behaviour is composed rather than where a unit is convenient. The ideal count is one: the first seam is free, and every seam after it and every `kind: new` one owes a one-line `why:` the already-named seams cannot hold the claim (`check-plan` refuses `seam-unstructured why=extra-unjustified|new-unjustified`). Each seam records `at:`, the `file:line` it resolves to at the base. Left unpressured, eight slices invent eight oracle locations, each a separate chance to assert below the level the claim lives at.

## An oracle can be green, at the right seam, and prove nothing

RED→GREEN rules out a vacuous test and sees none of these three; each is red before the code exists and green after.

- **Tautology.** The assertion recomputes the expected value the way the code does, so it passes by construction and cannot disagree with the code. Every behavioural scenario says where its value comes from, `expected_from: literal | worked-example | spec | existing-behaviour`, and cites it in `expected_source:` for everything but a hand-checked literal. The citation is the check.
- **Reachability.** `probe:` is the one production line whose deletion must turn the oracle red, named at plan time so it cannot be invented afterwards to match what was built. A probe naming a test line is not a probe.
- **Discrimination.** The oracle fails by assertion, with values, not by hang, timeout, crash, import error, empty collection or skipped suite. This is a property of the RED the executor watches and is enforced there, not as a YAML field.

Two shapes with no natural behavioural oracle:

- **"Every X must do Y"** over a set of call sites ("all N call sites", "every appender", "no module outside X") needs a **structural oracle**: a test that enumerates the sites from source, asserts the census, and asserts the negative half ("no module outside `<owner>` performs `<operation>`"), excluding comments so prose cannot trip it. Its scenario is `kind: structural` with prose `text:`, because Given/When/Then has no room for the negative half, and that half is what catches the writer added next week.
- **A write-side guarantee** (convergence, idempotency, exactly-once, ordering, dedup) is asserted on its own artifact, the event stream, count or version, not on a read-model row, whose own upsert dedups independently. A declaration-only slice (vocabulary, a type) pins existing behaviour instead: round-trip the inputs the live producer supplies today.

## Both sides of a contract

For every contract the unit introduces (producer and consumer, writer and reader, caller and callee), name the slice that builds each side, or state which side is out of scope and why. A unit that ships one side is green by construction: the tests can only exercise the half that exists. The check is one question over the slice list, and no single slice's gate can ask it.

## `.work/slices.yaml`

```yaml
ticket: TICKET-ID
title: "..."
adr: docs/.../ADR-NNN-....md      # durable decision record (committed)
branch: ...
seams:                             # REQUIRED, >=1. The unit's test locations, named ONCE.
  - name: "<what this seam is called>"   #   Fewest, highest, existing over new — ideally one.
    at: "<file:line it resolves to at the base, checked when written>"
    kind: existing                 # existing | new
  - name: "<a second seam, if the unit genuinely needs one>"
    at: "..."
    kind: new
    why: "<why the seams already named cannot hold this slice's claim>"  # owed by every
                                   #   seam after the first, and by every `kind: new` one
slices:
  - id: 1
    seam: "<one of the names above>"   # REQUIRED. check-plan refuses an undeclared one.
    name: "TRACER BULLET — <thinnest end-to-end path through the riskiest seam>"
    passes: false
    depends_on: []
    behavior: "<the one observable behavior, end to end, in the ubiquitous language>"
    oracle: "<the test that proves it — what it asserts>"
    probe: "<the ONE production line whose deletion must turn this oracle red>"  # REQUIRED
    scenarios:                     # REQUIRED, >=1. check-plan refuses the plan without it.
      - scenario: "<what this case is called>"
        given: "<the state the case starts in>"
        when: "<the one thing that happens>"
        then: "<what must be observably true — the assertion, not the setup>"
        expected_from: spec        # literal | worked-example | spec | existing-behaviour
        expected_source: "<file:line, doc section or ticket>"   # REQUIRED unless `literal`
      - scenario: "<a census, where the rule is 'every X must do Y'>"
        kind: structural           # keeps prose: Given/When/Then has no room for the
        text: >                    #   negative half, and the negative half is the point
          every <writer> does <Y>, and no module outside <owner> does <Y>
    gates: ["<project invariant the verifier must confirm>", ...]
    surface: { files: 4, sites: 60 }  # counted at the base; over 10 files or 200 sites → split,
                                   #   unless `atomic: <why it cannot compile half-done>`
    touches: [paths]               # OPTIONAL hint; lead with behavior
    model: sonnet                  # OPTIONAL. Present only on mechanical slices; absent means opus.
    designs: [subdomain_pol_slug]  # OPTIONAL. Design node ids this slice delivers, when the
                                   #   unit has an .esas/design.json. Scopes /build's scaffold.
    origin: plan                   # plan (default, may be omitted) | verify-build (a fix slice)
    jira: TICKET-NNN               # only when published as a sub-task (--publish)
    commit: <sha>                  # written by /build at the land, pool slices only
  - id: 2
    name: "..."
    passes: false
    depends_on: []                 # independent of slice 1 → can run in parallel
review: human                      # human | unattended — set by /plan, always
candidateOracles:                  # OPTIONAL. Only when a <path>/map.json existed at /plan Step 1;
                                    #   [{fork, option, scenario, source, example, slice, status}]
```

`scenarios:` is the oracle in the form nobody can quietly re-read; `oracle:` stays the narrative. Where a design map's fork was decided and its walk confirmed, that walk is the scenario. `passes` flags and the slice commits are the build's progress. `review:` and `candidateOracles:` trail `slices:` because `worktree-pool`'s parser stops at the first indent-0 line after it. `design-map check-plan` refuses a plan missing any REQUIRED field above. An env-gated oracle (one the default run excludes behind a flag or a service) names its exact invocation, flag and services, in `oracle:`, so `/verify-build` can re-run it; such a slice is certified by that invocation, not by its `passes:` flag. `model: sonnet` marks a mechanical slice: a scaffold from a framework skill, config or wiring, a test-only or guard-only slice, a mechanical prefactor; the tracer bullet, a seam and anything touching an invariant leave it absent, which `/build` routes as `opus`, and so does doubt.

## Anti-patterns

- **By component or layer** (one slice per schema, aggregate or read model): re-cut by behaviour.
- **Below an observable behaviour**: the floor is the smallest observable behaviour, not the smallest change.
- **An oracle nobody said how to break**: every scenario asserted and no statement of what would turn any of it red.
- **A seam per slice**: each oracle green and about the right behaviour, and nothing that would notice the composition unwired.
- **Deferring invariants**: half-formed aggregates that pass tests and ship defects.
- **One side of a contract** (above).
- **Horizontal test-first**: all tests, then all implementation, verifying imagined behaviour. One test, one implementation, repeat, each a tracer bullet that responds to what the last cycle taught.
