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

## Each slice carries its own oracle

Every slice declares the **test** that proves it (its oracle) and a `passes` flag. The slice is "done" only when that test is green **and** the verifier confirms the project's invariants — the dual gate. Then it is committed (one commit per slice).

## Review the breakdown before building

Present the proposed slices as a numbered list (title · blocked-by · behavior) and confirm with the user: is the granularity right, are the dependencies correct, should any merge or split? Iterate to approval before writing `slices.yaml` or publishing — the slice boundaries are the highest-leverage decision in the build.

## `.work/slices.yaml`

```yaml
ticket: TICKET-ID
title: "..."
adr: docs/.../ADR-NNN-....md      # durable decision record (committed)
branch: ...
slices:
  - id: 1
    name: "TRACER BULLET — <thinnest end-to-end path through the riskiest seam>"
    passes: false
    depends_on: []
    behavior: "<the one observable behavior, end to end, in the ubiquitous language>"
    oracle: "<the test that proves it — what it asserts>"
    gates: ["<project invariant the verifier must confirm>", ...]
    model: sonnet                  # OPTIONAL. Present only on mechanical slices; absent means opus.
    jira: TICKET-NNN               # only when published as a sub-task (--publish)
  - id: 2
    name: "..."
    passes: false
    depends_on: []                 # independent of slice 1 → can run in parallel
```

`passes` flags + git commits **are** the build progress. There is no separate progress doc. `touches: [paths]` may be added as a hint, but lead with `behavior`. `model:` routes the slice's executor — set it only where the implementation is genuinely mechanical, and never on the tracer bullet, which is by construction the slice whose seam nobody has proven yet.

## Anti-patterns

- **Slicing by component/layer** (one ticket per schema/aggregate/readmodel). The classic trap — usually a sign the plan was shaped to fit specialized tooling rather than verifiability. Re-cut by behavior.
- **Over-slicing below an observable behavior.** The floor is "smallest *observable behavior*", not "smallest *change*". Below that you pay loop/setup overhead for sub-behaviors.
- **Deferring invariants** to a later slice — produces half-formed aggregates that pass tests and ship defects.
- **Pure-vertical-from-line-one** when a genuinely shared foundation (a schema five slices depend on, a migration) is needed first. That is exactly what prefactoring + the tracer bullet establish — just-enough shared skeleton, once, then go vertical.
