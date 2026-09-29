---
work_item: ESAS-200
branch: ESAS-200-hosted-turn-adr011-superseded
---
# ESAS-200: mark plugin ADR-011 superseded by blueprint ADR-107

Mode: unattended lane, verification second pass over the `design-multi:resolved:v2` block (base 377f63c, drift none). Grounding degraded: no CONTEXT.md in this plugin repo; grounded through docs/adr and the ADR-011 header.

## Problem

ADR-011 still records a sandboxed hosted-turn design with a plugin skill. Under blueprint ADR-100 there is no sandbox: the customer's runner spawns the agent in the customer's checkout, without our plugin. ADR-011 (`**Status:** Proposed`) misleads plugin maintainers.

## Solution

The owner closed the build into ESAS-205: the Blueprint server serves the hosted-turn instructions with each claimed design job. ESAS-200's residual scope is one docs-only edit: mark ADR-011 `Superseded by blueprint ADR-107` with a short note. No skill, no needle, no README line, no version bump (the version gate counts only `plugins/**`).

## User Stories

1. As a plugin maintainer, I want ADR-011 to say the plugin no longer owns a hosted contract and where it went, so that I do not build a skill for it.
2. As a customer running a runner without our plugin, I want the hosted rules to arrive with the job, so that no install step is needed (built in ESAS-205).
3. As the platform admin, I want to change the instructions without a redeploy (ESAS-205).
4. As a customer security reviewer, I want each job's instruction version and hash recorded (ESAS-205).

## Resolved decision tree

<!-- map-tree:v1 ticket=ESAS-200 gen=2 src=sha256:5553ff9a6ae9664ff287e135da124f8cee9990cefd7fdbcacf3827c07885c4c2 out=sha256:0c4a9169c409e7963a3db965b3cf9a4dbc9c5b7c9a3f7d93f0488dace1350b66 -->
`map-tree:v1 ticket=ESAS-200 gen=2 src=sha256:5553ff9a6ae9664ff287e135da124f8cee9990cefd7fdbcacf3827c07885c4c2 out=sha256:0c4a9169c409e7963a3db965b3cf9a4dbc9c5b7c9a3f7d93f0488dace1350b66`
### ESAS-200-F1 — Hosted-turn contract: plugin skill, or the runner's own prompt?: Close ESAS-200 into ESAS-205; the server serves the instructions with each claimed job from a store the platform admin edits at runtime (bundled default on the server); ADR-011 superseded (owner reframe 2026-09-28)

decided(owner)

Why: The customer-hosted runner cannot assume our workflow plugin, and a prompt the runner already ships is the only copy that reaches a plugin-less machine with zero install steps.

resolved_by: human

- Rejected — Plugin skill blueprint-hosted-turn; runner loads the plugin and allows Skill: no reason recorded
- Rejected — Plugin is source; runner vendors SKILL.md and passes it via --append-system-prompt: no reason recorded

### ESAS-200-F2 — Can a runner decline or pin the server-served instructions, and does it keep a bundled fallback prompt?: Always served: no runner opt-out and no bundled fallback; a job without instructions fails with a clear error; the instruction version and hash are recorded per job

decided(owner)

Why: Owner rule 2026-09-29: the server is the brain and the runner holds no business logic; supersedes the 'runner keeps only a fallback' clause of ESAS-200-F1.

resolved_by: human

- Rejected — Served by default, with a runner flag (--instructions bundled) to use its own copy: a choice inside the runner is business logic; the runner is an interface only (owner, 2026-09-29)
- Rejected — Served, with the runner's bundled prompt as a fallback when none arrives: the runner would decide what the agent is told
`/map-tree:v1`
<!-- /map-tree:v1 -->

## Implementation Decisions

- Edit only `docs/adr/ADR-011-a-hosted-turn-is-one-headless-look-at-the-board.md`: line 3 becomes `**Status:** Superseded by blueprint ADR-107 (ADR-107-runner-is-an-interface-and-the-server-decides.md)`, plus a short note under the header: the hosted-turn contract is the instructions the Blueprint server serves with each claimed design job (ESAS-205); no plugin skill is built; the decisions below are kept as history. Decision sections are not rewritten.
- The ADR-107 filename is verified on blueprint branch ESAS-205-runner-design-jobs @ 25d1c9ec; re-derive it at build if ESAS-205 renamed it.
- No new plugin ADR number (015 stays free).
- Obligations for ESAS-205 (store, claim field, no-fallback runner, default text, refusal table, argv test, versioning, isolation) live in the ticket block and are built there, not here.

```mermaid
flowchart LR
  ADR011[plugin ADR-011 Proposed] -->|superseded by| ADR107[blueprint ADR-107]
  ADR107 --> Server[server serves instructions per claimed job]
```

## Testing Decisions

Seams are greps and guards, no new tests:
1. `grep -n '^\*\*Status:\*\*'` on ADR-011 prints `Superseded by blueprint ADR-107` (red at base: `Proposed`).
2. `grep -n 'served with each claimed'` hits and `grep -c ESAS-205` rises (red at base).
3. `git diff --name-only origin/master...HEAD` lists exactly the ADR-011 file.
4. `sh scripts/check-plugin-version-bump.sh origin/master` exits 0.
5. `sh .claude/gate.sh` scoped (docs/adr selects test-flow-seams.sh); report the mode; deferred gate per lane.

Tracer bullet: the flow-seams suite reacting to an ADR edit, the one thing the greps do not catch.

## Risks

- ADR-011 must not cite ADR-107 before it exists; the filename is verified on the ESAS-205 branch only, so if ESAS-205 renames it the citation goes stale.
- Runners deployed before ESAS-205 ignore served instructions; ESAS-205 owns that treatment.

## Out of Scope

Everything ESAS-205 builds, ESAS-210's commit bundle exclusions, ESAS-229, ESAS-263. Unspecified seams: whether other plugin ADRs cite ADR-011 as live (not swept; a follow-up grep for `ADR-011` in docs/ is cheap at build).

## Provenance

- `git -C /Users/tomasruiz/Documents/development/bp-int cat-file -e origin/ESAS-205-runner-design-jobs:docs/adr/ADR-107-runner-is-an-interface-and-the-server-decides.md` (exit 0)
- `grep -n '^\*\*Status:' docs/adr/ADR-011-*.md` prints `Proposed` at 377f63c
- `git log --oneline -1` is 377f63c; `work-docs-path --item ESAS-200 --owner-branch ...` gave owner=none
- Block claims about blueprint-runner line numbers were not re-verified in this repo (UNVERIFIED here; ESAS-205's).
