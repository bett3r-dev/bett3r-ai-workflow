# Slices may list edge keys in `designs:`, and an edge stub rides with its new end

**Status:** Accepted. **Date:** 2026-10-16. **Ticket:** BP-267 (F2). **Related:** [ADR-015](./ADR-015-the-design-ends-in-a-scaffold-commit-the-declared-typecheck-is-its-bar.md); blueprint ADR-129.

## Context

A scaffold commit now carries edge stubs: insert-only fragments for a proposed edge whose code-bearing end is already in
code (blueprint ADR-129). Each is a `TODO(scaffold)` marker `/build` must leave owned by exactly one slice. A slice's
`designs:` names artifacts, and an edge stub's `node` is the existing end, which is not the slice's artifact.

## Decision

- **An edge rides with its new end.** `designs:` already names that node, so a slice plan stays as short as before and the
  stub's marker is `TODO(scaffold) [<nodeId>]`.
- **An edge between two existing artifacts is listed by its key**, `edge:<from>|<to>|<kind>` (the store's anchor key). Its
  marker is `TODO(scaffold) [edge:<from>|<to>|<kind>]`. `/plan` says to list a key only when both ends exist.
- **`/build` matches by either end.** The report carries no owner stamp, so the hand-off matches an edge entry's
  `edge.from`/`edge.to` against the slice's `designs:` nodes, else by key; the marker is authoritative. An implied `emits`
  rides with the `produces` that implies it. The verifier scopes a marker by either form.
- **Listing the key of an edge with a new end selects nothing and exits 0**; `build.md` warns.

## Consequences

- No edge stub is ownerless; common slice plans are unchanged.
- `scaffold-commit.py` owes edge stubs. Its `classify` owes only registration, but an edge stub is topology, so it enters
  prepare's `worklist[]`, and finish owes one the agent left as `not-placed` (`detail` its file) and an edge unit the core
  deferred as `deferred` (`detail` its `waitsOn`). Such a row's `node` is the edge's existing end (a pv3 `produces` stub has
  no `at`, so it is owed, is topology and lands on the worklist). `/build` matches the row to its `scaffolder` fragment or
  `scaffolder.deferred[]` entry by `node` and `detail`, then hands the stub by that entry's ends, key or marker, never by the
  row's `node`.
- The edits: in bett3r-ai-workflow, `commands/plan.md`, `commands/build.md`, `agents/verifier.md`, the vertical-slicing
  skill, the plugin README (the scaffold-commit glossary's topology entry) and `scaffold-commit.py` (`is_topology`,
  `fragment_key` as the runner's); in bett3r-pv3-ai-skills, the scaffold-from-design skill; in bett3r-routine,
  `commands/routine-plan.md`. Each of the three plugins owes a version bump at land time (decisions D20): bett3r-ai-workflow
  a minor on top of 0.111.0, bett3r-pv3-ai-skills from 0.17.0, bett3r-routine from 0.1.0.

## Alternatives rejected

- **Every edge listed by its own key.** Longer slice plans for the common case.
- **An edge belongs to its new end's slice; an edge between two existing artifacts has no owner.** Leaves a stub owned by nobody.
- **Stamp an owner on edge stubs.** Needs code in the core, pv3 and kixie (D19).
