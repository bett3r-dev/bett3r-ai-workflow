# bett3r-pv3-ai-skills

A Claude Code plugin that ships the **PV3 DDD framework skills** — the `create-*` scaffolders and
a `ddd-patterns` reference for the PV3 event-sourcing/CQRS framework (AggregateBuilder,
ReadmodelBuilder, PolicyBuilder, the MDU/lift composition model). Install it in **any PV3 repo**;
it reads that repo's own package names and paths from `.esas.config.json` instead of hardcoding
Teselly's, so the same patterns propagate everywhere PV3 runs.

It is the **framework half** of the flow. Pair it with [`bett3r-ai-workflow`](../bett3r-ai-workflow)
(the project-agnostic methodology: start → design → plan → build → verify-build → capture-learnings).
A PV3 repo installs both; a non-PV3 repo installs just the workflow plugin.

## Skills

| Skill | What it scaffolds |
|-------|-------------------|
| `create-schema` | Event/value-object/aggregate/command/readmodel schemas (jsonschema-definer) + events. |
| `create-aggregate` | An `AggregateBuilder` aggregate: event reducers + command handlers + scope invariants. |
| `create-policy` | A `PolicyBuilder` policy that reacts to events and drives downstream commands (replay-safe). |
| `create-readmodel` | A `ReadmodelBuilder` projection: projectors + authenticated, scoped queries. |
| `create-tests` | Given/When/Then unit tests for aggregates, policies, and read models. |
| `create-integration-test` | A full-pipeline in-process integration suite (command → … → readmodel) via the harness. |
| `create-module` | Orchestrates all of the above to scaffold a complete bounded-context module. |
| `ddd-patterns` | The PV3 DDD pattern reference — the framework conventions, gotchas, and hard-won lessons the `create-*` skills assume. (Model-invoked, not always-on.) |
| `event-storming-to-spec` | Turns event-storming output (Mermaid / structured text) into a PV3 DDD specification that feeds `create-module`. |
| `miro-to-mermaid` | Extracts event-storming artifacts from a Miro board into structured Mermaid flowcharts. Requires a host-repo Miro frame-data fetcher (see the skill's Step 1). |

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
