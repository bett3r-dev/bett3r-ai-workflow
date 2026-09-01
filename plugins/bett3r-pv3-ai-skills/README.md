# bett3r-pv3-ai-skills

A Claude Code plugin that ships the **PV3 DDD framework skills** — the `create-*` scaffolders and
a `ddd-patterns` reference for the PV3 event-sourcing/CQRS framework (AggregateBuilder,
ReadmodelBuilder, PolicyBuilder, the MDU/lift composition model). Install it in **any PV3 repo**;
it reads that repo's own package names and paths from `.esas.config.json` instead of hardcoding
Teselly's, so the same patterns propagate everywhere PV3 runs.

It is the **framework half** of the flow. Pair it with [`bett3r-ai-workflow`](../bett3r-ai-workflow)
(the project-agnostic methodology: start → design → plan → build → verify-build → capture-learnings).
A PV3 repo installs both; a non-PV3 repo installs just the workflow plugin.

## The mechanical pass, and what's left after it

The design graph already fixes an artifact's file path, builder wiring, event names, placement,
registration — and the **node id the ESAS extractor will read back**. `scaffold-from-design`
generates that half with a tested program
([`@bett3r-dev/esas-pv3-scaffold`](https://github.com/bett3r-dev/eventstorming--visual-editor)),
so it is derived rather than retyped.

That is not about typing speed. It is about **convergence**: a hand-written artifact that drifts by
one word in a label reads back as a different node, the design's proposal never flips to
`satisfied`, and the board reports a phantom forever — while the code compiles and the tests pass.

Everything the graph cannot carry stays here, in the `create-*` skills, because an ESAS node has a
label, a subdomain and a resource key and **no fields**. Schemas, invariants, handler bodies,
projections, stream strategy and idempotency are hand-written, and the generator refuses to guess
any of them. Each generated file states its own `STILL OWED` list.

The generator also refuses rather than guessing a **location**, and rather than silently dropping a
projection it cannot resolve. Those refusals are findings — a design question surfacing as a
scaffold block — not obstacles to route around by hand-placing the file.

## Skills

| Skill | What it scaffolds |
|-------|-------------------|
| `scaffold-from-design` | **Run first.** The mechanical half of a slice's designed artifacts, slice-scoped: whole files for policies/read models, fragments for a command on an existing aggregate, a new event, and every registration line. |
| `create-schema` | Event/value-object/aggregate/command/readmodel schemas (jsonschema-definer) + events. Never generated — a node carries no fields — so this is the first `STILL OWED` item of every scaffolded artifact. |
| `create-aggregate` | An `AggregateBuilder` aggregate: event reducers + command handlers + scope invariants. |
| `create-policy` | The judgment half of a `PolicyBuilder` policy: handler bodies, dependency declaration, replay safety. Placement and wiring come from the scaffolder. |
| `create-readmodel` | The judgment half of a `ReadmodelBuilder` projection: what each projector writes, queries, indexes, scope. |
| `create-tests` | Given/When/Then unit tests for aggregates, policies, and read models. |
| `create-integration-test` | A full-pipeline in-process integration suite (command → … → readmodel) via the harness. |
| `create-module` | Orchestrates all of the above — starting from the scaffolder — to build a complete bounded-context module. |
| `ddd-patterns` | The PV3 DDD pattern reference — the framework conventions, gotchas, and hard-won lessons the `create-*` skills assume. (Model-invoked, not always-on.) |
| `event-storming-to-spec` | Turns event-storming output (Mermaid / structured text) into a PV3 DDD specification that feeds `create-module`. |
| `miro-to-mermaid` | Extracts event-storming artifacts from a Miro board into structured Mermaid flowcharts. Requires a host-repo Miro frame-data fetcher (see the skill's Step 1). |

`ddd-patterns` is a **hub plus six references**, not one file: its `SKILL.md` holds the
project-configuration preamble, the rules that apply to *every* artifact kind (the MDU/lift
factory contract, the composition-root boundary, invariant placement, endpoint identity), and
a trigger table — one row per reference, naming the condition to open it and what skipping it
has cost. The per-kind material lives beside it in
[AGGREGATES.md](skills/ddd-patterns/AGGREGATES.md),
[SCHEMAS.md](skills/ddd-patterns/SCHEMAS.md),
[DELIVERY.md](skills/ddd-patterns/DELIVERY.md),
[POLICIES.md](skills/ddd-patterns/POLICIES.md),
[READMODELS.md](skills/ddd-patterns/READMODELS.md) and
[MODULES.md](skills/ddd-patterns/MODULES.md), each pointed at from the `create-*` skill that
already sends you there. `DELIVERY.md` is deliberately its own file rather than folded into a
per-artifact one: the at-least-once contract, the per-stream version watermark and
`isRedelivery` bind **any** consumer — policy, read model, or an external non-PV3 service —
and buried under one artifact kind the other two would never find them.

## The `.esas.config.json` seam

Every PV3 repo carries an `.esas.config.json` at its root. The skills resolve these fields
(Teselly's values shown as examples):

| Field | Meaning | Example (Teselly) |
|---|---|---|
| `domainEventsPath` | Where domain schemas/events live | `src/packages/shared/teselly-domain` |
| `domainEventsPackageName` | Domain package import name | `@bett3r-dev/teselly-domain` |
| `serverPath` | Server service root | `src/services/server` |
| `clientLibraryPackageName` | Generated client-library import name | `@bett3r-dev/teselly-client-library` |
| `domainUtilsPackageName` | Domain utilities import name (scope invariants, projection transformers, process-manager helpers). **Optional** — defaults to `domainEventsPackageName` + `-utils`. | `@bett3r-dev/teselly-domain-utils` |

> **Setup note:** `domainUtilsPackageName` is **optional** — if a repo's `.esas.config.json`
> omits it, the `create-aggregate` / `create-policy` / `create-readmodel` skills derive it as
> `domainEventsPackageName` + `-utils` (e.g. `@bett3r-dev/teselly-domain` →
> `@bett3r-dev/teselly-domain-utils`). Declare it explicitly only if your utilities package
> doesn't follow that convention. The PV3 framework packages (`@bett3r-dev/pv3-types`,
> `@bett3r-dev/jsonschema-definer`, the `ports` module) are identical in every PV3 repo and are
> not config-driven.

## Relationship to the host repo

This plugin ships **framework patterns**, not domain knowledge. Repo-specific architecture
invariants, war-stories, and business rules stay in the host repo (its `.claude/rules/`, ADRs, and
memory). The generic PV3 lessons that any PV3 repo benefits from live here in `ddd-patterns`;
Teselly's domain-specific lessons remain in Teselly.

## Bundled tooling

`scripts/miro-cli/` ships a self-contained Miro frame-data fetcher used by the `miro-to-mermaid`
skill's Step 1 — so that skill works in any repo without a host-provided script. One-time setup:
`cd scripts/miro-cli && npm install && cp .env.example .env` (set `MIRO_ACCESS_TOKEN`). See
`scripts/miro-cli/README.md`.

## Install

Both plugins ship from the same marketplace repo (`bett3r-ai-workflow`):

```bash
claude plugin marketplace add <this-repo-url>
claude plugin install bett3r-pv3-ai-skills
# or for local dev, from your clone of this repo:
claude --plugin-dir ./plugins/bett3r-pv3-ai-skills
```
