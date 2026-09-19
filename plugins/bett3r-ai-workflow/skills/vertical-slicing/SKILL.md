---
name: vertical-slicing
description: Cut a design into vertical slices (tracer bullet first, prefactor first) instead of horizontal layers, so each unit is independently verifiable and committable. Use when planning/decomposing a feature into execution units, or when a plan looks layer-by-layer.
---

# Vertical slicing

## The principle

A **slice** is the smallest independently-**observable, verifiable behavior**, cut top-to-bottom through *all* the layers it needs (schema → domain logic → projection/read side → the one endpoint/UI that exercises it → a test that drives it end-to-end).

A slice is **not** a horizontal layer ("build all the schemas", "build the readmodels"). Horizontal layers are the default trap and they are wrong for an automated flow, for one concrete reason:

> Only a vertical slice has its own **green signal** (a test that passes when the slice works). A horizontal layer has no standalone oracle — "the schema layer" can't be verified until other layers exist. No oracle → the loop can't verify or commit it independently → you're forced back into a manual, serialized, prose-tracked build.

So vertical slicing is the upstream precondition that makes the rest of the flow (per-slice dual gate, commit-per-slice, deterministic drive) possible at all.

## Tracer bullet first

Order slices so the **first** one is the thinnest end-to-end path through the **riskiest, gate-less seam** — the part of the architecture that *nothing* automatically catches if it's wrong (a generated-artifact / deployment seam, a new integration boundary, a cross-aggregate contract). A tracer bullet is real, kept code — just thin. Prove the seam holds before fleshing anything out; later slices build on a validated skeleton. A tracer bullet is not a prototype; you keep it.

## Prefactor first

"Make the change easy, then make the easy change." Before the feature slices, look for **prefactoring** — reshaping existing code so the feature drops in cleanly (extract a seam, rename to the ubiquitous language, pull a shared helper). When it exists, prefactoring is the **earliest slice(s)**, done before any feature slice. A clean prefactor slice is often the easiest first commit and de-risks everything after it.

## Self-referential enforcement — order it so it proves itself

When a slice introduces a mechanism that governs the repo's **own** changes (a CI gate, a lint rule, a schema check, a pre-commit hook), order the slices so a **later slice in the same PR is its first live subject**. Put the mechanism in a slice that does not trigger itself, and let the next slice be what it governs. The PR then *demonstrates* the rule instead of asserting it.

Both other orderings fail. Mechanism-last means it is never exercised by its own PR and ships asserted-but-unproven — and for an enforcement mechanism that is the whole risk: **a gate that never fired is indistinguishable from a gate that cannot fire.** Both-in-one-slice turns CI red on the introducing commit, and the natural fix under pressure is to weaken or exempt the gate. This is the class where "the tests pass" is weakest evidence, because the fixture was written by whoever wrote the rule; a live proof inside the same PR is much stronger and is free if the slices are ordered for it.

## What a good slice looks like (event-sourced / DDD)

The canonical slice is **one command, end-to-end**:

> command → event → aggregate **with its invariants whole** → projection/read model → the one endpoint or UI that exercises it → an integration test that drives the real command.

Do **not** defer invariants to "a later slice" — every invariant belongs on its aggregate, complete, the moment the aggregate appears. Framework scaffolders (e.g. `create-aggregate`, `create-readmodel`) are **tools used inside a slice**, not units of planning.

(For non-DDD work the same shape holds: one user-observable behavior, through every layer it touches, with a test.)

## Name and describe slices well

- **Name in the ubiquitous language.** Use the bounded context's `CONTEXT.md` vocabulary, and respect ADRs in the area. A slice title should read as a domain behavior, not an implementation task.
- **Describe behavior, not implementation.** Say what the slice does end-to-end; avoid file paths and code snippets — they go stale. *Exception:* a decision-rich snippet from a prototype (a state machine, reducer, schema, or type shape) that encodes a decision more precisely than prose — inline just the decision-bearing bits, noted as from a prototype.

## Each slice carries its own oracle — at the layer where its claim lives

Every slice declares the **test** that proves it (its oracle) and a `passes` flag. The slice is "done" only when that test is green **and** the verifier confirms the project's invariants — the dual gate. Then it is committed (one slice commit per slice).

**An oracle for a write-side guarantee asserts that guarantee's own artifact.** Where the behavior names convergence, idempotency, exactly-once, ordering or dedup, the assertion is on the event stream, the event count or the version — never on a read-model row or a query result, because the projection's own `upsert` dedups independently and passes a non-convergent implementation green. "The same message twice yields ONE row" was satisfied by an implementation that wrote a fresh random stream per delivery; asserting the **stream set across the whole eventstore** caught two wrong mechanisms before implementation, one of them a silent cross-tenant collapse. A thin complete path still asserts at the layer its claim lives.

**A declaration-only slice needs a named oracle too.** A purely additive vocabulary or type slice compiles, breaks nothing, and passes every gate vacuously; the answer to *"what test fails if this slice is wrong?"* is a test pinned to **existing** behavior — round-trip the inputs the only live producer supplies today — which is falsifiable without changing anything.

## Review the breakdown before building

`/plan` step 4 owns the review — numbered list, granularity, dependencies, merge/split — and its unattended branch. The slice boundaries are the highest-leverage decision in the build.

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
    scenarios:                     # REQUIRED, >=1. check-plan refuses the plan without it.
      - scenario: "<what this case is called>"
        given: "<the state the case starts in>"
        when: "<the one thing that happens>"
        then: "<what must be observably true — the assertion, not the setup>"
      - scenario: "<a census, where the rule is 'every X must do Y'>"
        kind: structural           # keeps prose: Given/When/Then has no room for the
        text: >                    #   negative half, and the negative half is the point
          every <writer> does <Y>, and no module outside <owner> does <Y>
    gates: ["<project invariant the verifier must confirm>", ...]
    surface: { files: 4, sites: 60 }  # counted at the base; over 10 files or 200 sites → split,
                                   #   unless `atomic: <why it cannot compile half-done>`
    model: sonnet                  # OPTIONAL. Present only on mechanical slices; absent means opus.
    designs: [subdomain_pol_slug]  # OPTIONAL. Design node ids this slice delivers, when the
                                   #   unit has an .esas/design.json. Scopes /build's scaffold.
    jira: TICKET-NNN               # only when published as a sub-task (--publish)
  - id: 2
    name: "..."
    passes: false
    depends_on: []                 # independent of slice 1 → can run in parallel
review: human                      # human | unattended — set by /plan Step 5, always
candidateOracles:                  # OPTIONAL. Only when a <path>/map.json existed at Step 1;
                                    #   [{fork, option, scenario, source, example, slice, status}]
```

`scenarios` is the slice's oracle in a form nobody can quietly re-read. `oracle:` stays the narrative; `scenarios:` is what must be made true. It is required on every slice because the measured failure is not that slices are too big — across 966 classified fix rounds `ripple`, the only cause slice size controls, is **6%**, while `oracle-wrong` (the test encoded the wrong rule, went green, and was caught only by the verifier) is **41%**. Where a design map's fork was decided and its walk confirmed, that walk *is* the scenario; where there is no map, write them here — the two runs on record with 0% first-pass green had no map at all.

`seams:` is the unit's answer to *"where do we test this"*, written once and inherited by every oracle. Prefer an **existing** seam to a new one and the **highest** one that can still observe the claim, and keep the count down — the ideal is one. Left unpressured, eight slices invent eight oracle locations, and each is an independent chance to assert below the level the claim lives at: the worst defect on record is that shape — the oracle sat at the unit, not the composition root, so both wiring lines could be deleted with `tsc` clean and 738 tests green. *Highest* is a judgement and stays one; what is mechanical is that the seam is **named, located and defended** — `check-plan` refuses `plan-unseamed`, `slice-unseamed`, `unnamed-seam` and an undefended extra or new seam. A `why:` is the entire cost of a second seam, deliberately: a cap would be wrong (some units need two) and silence was what was wrong before.

`passes` flags + git commits **are** the build progress. There is no separate progress doc. `touches: [paths]` may be added as a hint, but lead with `behavior`. `model:` routes the slice's executor — set it only where the implementation is genuinely mechanical, and never on the tracer bullet, which is by construction the slice whose seam nobody has proven yet. `designs:` names the design-layer node ids the slice delivers, so `/build` can scaffold this slice's artifacts and not the whole design's; leave it out when the unit has no design layer, and never guess an id — a wrong one scaffolds the wrong artifact, while an absent one just means "nothing designed here".

## Anti-patterns

- **Slicing by component/layer** (one ticket per schema/aggregate/readmodel) — the trap *The principle* opens on, usually a sign the plan was shaped to fit specialized tooling. Re-cut by behavior.
- **Over-slicing below an observable behavior.** The floor is "smallest *observable behavior*", not "smallest *change*". Below that you pay loop/setup overhead for sub-behaviors. **The ceiling belongs to the fix round**: a sweep over 10 files or 200 sites is split (`/plan` Step 3), because one finding anywhere in it re-opens the whole sweep.
- **A seam per slice.** Every slice picking its own oracle location, one at a time, with nothing comparing them. It never looks wrong slice by slice — each oracle is green and each is about the right behaviour — and the unit still ends with no test anywhere that would notice the composition being unwired. Name the seams first, then cut.
- **Deferring invariants** to a later slice — produces half-formed aggregates that pass tests and ship defects.
- **Slicing only one side of a contract.** When a unit introduces a contract between two parties — a producer and a consumer, a writer and a reader, a caller and a callee — name the slice that builds **each** side, or state which side is out of scope and why. A unit that ships one side is **green by construction**: the tests can only exercise the half that exists, and the specified degrade path is indistinguishable from the system working. One unit sliced the *reading* of a step contract three ways — spec, parser, reader, plus a uniqueness guard — shipped 41→77 tests, both gates green on every slice, and the marker was emitted by nothing. This is not the tracer bullet rule: every slice there was genuinely vertical and individually complete; the gap is **between** slices, in the set, which is why it belongs to `/plan` and no single slice's gate can see it. The check is one question over the slice list: *for every contract this unit introduces, which slice writes it and which slice reads it?*
- **Pure-vertical-from-line-one** when a genuinely shared foundation (a schema five slices depend on, a migration) is needed first. That is exactly what prefactoring + the tracer bullet establish — just-enough shared skeleton, once, then go vertical.
