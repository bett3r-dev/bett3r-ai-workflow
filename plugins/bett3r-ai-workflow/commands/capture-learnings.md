---
description: Capture what this session taught, routed to the repo that owns the artifact. Origin-aware — improvements to a shared plugin become GitHub issues there; repo-specific facts stay local.
---

# /capture-learnings — origin-aware learning capture

Turn what this session taught into durable, actionable records, **each routed to where its source-of-truth lives**. This is the propagation machine: a learning about a shared skill, discovered here, becomes an issue in that skill's plugin repo — so every project that installs it benefits on the next update.

## Step 1 — Gather (start from the record buffer)
Read **`.work/learnings.md`** first — the entries captured in-flight via the `record` skill. These are the primary input: things already flagged as worth keeping, so nothing was lost to "I'll remember it later". Then review the session for anything not yet recorded (a flaw or improvement in the flow / a skill / an agent; a framework pattern; a repo-specific gotcha; a fact worth remembering). Skip the trivial — keep what was **non-obvious and reusable**.

## Step 2 — Route each learning (the key step)
Routing key: **where does this learning's source-of-truth live?**

| If the learning is about… | Owner | Destination |
|---|---|---|
| The flow itself — a workflow command/skill/agent (grill, slicing, dual gate, design/plan/build) | `bett3r-ai-workflow` | GitHub issue in that repo |
| A PV3 / DDD framework pattern or skill (ddd-patterns, create-*) | `bett3r-pv3-ai-skills` | GitHub issue in that repo |
| A CDSE frontend pattern or skill | `bett3r-cdse-ai-skills` | GitHub issue in that repo |
| This repo's own domain / conventions (a rule, a `CONTEXT.md` term) | host repo | update `.claude/rules` / `CONTEXT.md` (or an ADR) here |
| Cross-session context for the assistant | local | memory |

Propose the target for each; the user can redirect. **Default to local/memory when ambiguous** — a wrong-repo issue is worse than a local note. A learning may have two homes (e.g. update memory **and** file a plugin issue) — that's fine; they're complementary.

## Step 3 — File plugin-owned learnings as issues
Resolve the target repo from the owning plugin's `plugin.json` `repository` field (else its git remote `origin`). **Dedupe first** — `gh issue list --label ai-learning --search "<keywords>"`; if a near-duplicate is open, comment on it or skip rather than re-file. Then auto-compose and create — **one confirm, no form to fill**:

```
gh issue create -R <owner>/<repo> --label ai-learning --title "<concise>" --body "<template>"
```

Body template:
```
## Observed
What happened, in context (link the session / PR if useful).

## Why it matters
The cost of leaving it / the value of fixing it.

## Proposed change
The concrete edit to the skill/command/agent — behavior, not a full diff.
```

## Step 4 — Apply local learnings
Repo-specific facts → update the relevant `.claude/rules` / `CONTEXT.md` / an ADR in this repo. Assistant context → memory.

## Step 5 — Drain the buffer & report
Once every learning is routed, **clear the processed entries from `.work/learnings.md`** so the buffer doesn't re-process or leak into the next ticket. Then list each learning, its destination (issue URL or file), and any skipped as duplicates. Then:
> Run `/evolve` inside a plugin repo to turn its `ai-learning` issues into reviewed PRs.

## Principles
- **Route by ownership** — don't dump everything locally; that's how propagation dies.
- **Frictionless or it won't happen** — auto-compose the issue, one confirm.
- **Dedupe against existing issues** — the backlog must stay actionable, or it becomes the new rot (the `docs/prs/` problem, relocated).
- Issues are *actionable changes to shared artifacts*; memory is *assistant context*. A learning can be both.
