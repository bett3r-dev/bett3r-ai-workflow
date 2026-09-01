---
description: (experimental, v2 of /capture-learnings) Capture what this session taught, routed to the repo that owns the artifact — with a raised filing bar, so the backlog stays a to-do list instead of a sediment layer.
---

# /capture-learnings-2 — origin-aware learning capture

Turn what this session taught into durable records, each routed to where its source-of-truth lives. A learning about a shared skill, discovered here, becomes an issue in that skill's plugin repo, so every project that installs it benefits on the next update.

**This is the experimental v2.** The routing is unchanged. What changed is the **bar**: v1 filed anything "non-obvious and reusable", and the artifacts it feeds grow monotonically as a result. Three filters now stand between a session and an issue, and **most sessions should file fewer issues than they used to.** A session that files nothing is a normal outcome, not a failure to notice.

## Step 1 — Gather

Read **`.work/learnings.md`** first — the in-flight `record` buffer, the primary input. Then review the session for anything not yet recorded.

## Step 2 — The three filters

Every candidate passes all three, in this order. **Say which filter killed the ones that die** — that report is how you and the user calibrate the bar.

### Filter 1 — the model-default test

**Would a competent model, with no guidance at all, get this wrong?**

If the answer is no, it is not a learning; it is a description of the model doing its job. Guidance that restates a default costs attention in every future session and buys nothing, and this is the filter that keeps the shared artifacts from filling with instructions to be careful.

Two things pass it easily and should be looked for first:

- **A fact about *this* system that no amount of competence supplies** — the port is claimed strictly, the round-trip strips comment nodes, the caser splits internal capitals, `find -newermt` matches nothing on BSD.
- **A failure whose signature is *absence*** — a green gate that collected nothing, a closing keyword that bound to one issue, a skill that never loaded. Nothing goes red, so no amount of care catches it.

What usually fails it: exhortations ("verify before asserting", "read the whole file"), restatements of a rule already stated in the same artifact, and a defence against a specific mistake made once in one session.

**When it is a real trap but caution alone cannot avoid it, prefer a gate to a paragraph.** A reviewer who has to *remember* to look is not a control — that is why `scripts/` exists.

### Filter 2 — the locality test

**Is this true everywhere, or only here and now?**

A workaround for a local or transient condition — a token missing a scope, a stale tool version, a temporarily-broken command — is **not a learning. It is a bug report about your machine. Fix the machine.** Filing it propagates one machine's misconfiguration to every repo that installs the plugin, where it becomes a permanent detour that outlives its cause, because the workaround *works* and nothing prompts a re-check.

**Stale guidance is worse than no guidance:** absent guidance makes an agent think; wrong-but-plausible guidance makes it confidently take the wrong path. (Real miss: a `gh api -X PATCH` detour written into `/verify-build` and distributed everywhere, solely because one machine's token lacked `read:org`. The token was fixable in a minute; the guidance would have misled every reader forever.)

If a workaround genuinely must be recorded, record **why** it was needed and **the condition under which it expires**.

### Filter 3 — amend, don't append

**Find the rule this belongs to before proposing a new one.** Search the owning artifact for what already covers this ground. Then choose, and say which you chose:

- **Sharpens an existing rule** → propose an *edit* to that rule, quoting the current text. This is the preferred outcome and should be the most common one.
- **A second instance of a rule already stated** → the rule is not landing. The right proposal is to make the existing rule *fire* — move it to where the decision is made, or gate it — never to state it a second time somewhere else.
- **Genuinely new ground** → a new rule, and then it must name **what it replaces or what it sits next to**, so the next reader can see it belongs to a frame rather than being bullet N+1.

An artifact that gains a bullet per session eventually reads as N unrelated rules, and every one of them competes for the same finite attention. That is the failure this filter exists to prevent.

## Step 3 — Route the survivors

Routing key: **where does this learning's source-of-truth live?**

| If the learning is about… | Owner | Destination |
|---|---|---|
| The flow — a workflow command/skill/agent | `bett3r-ai-workflow` | GitHub issue in that repo |
| A PV3 / DDD framework pattern or skill | `bett3r-pv3-ai-skills` | GitHub issue in that repo |
| A CDSE frontend pattern or skill | `bett3r-cdse-ai-skills` | GitHub issue in that repo |
| This repo's own domain / conventions | host repo | `.claude/rules` / `CONTEXT.md` / an ADR, here |
| Cross-session context for the assistant | local | memory |

Propose the target; the user can redirect. **Default to local/memory when ambiguous** — a wrong-repo issue is worse than a local note. A learning may have two homes.

## Step 4 — File plugin-owned learnings

Resolve the repo from the plugin's `plugin.json` `repository` (else `origin`). **Dedupe first** — `gh issue list --label ai-learning --search "<keywords>"`; comment on a near-duplicate rather than re-filing. Then auto-compose and create — **one confirm, no form to fill**:

```
gh issue create -R <owner>/<repo> --label ai-learning --title "<concise>" --body "<template>"
```

```
## Observed
What happened, in context (link the session / PR if useful).

## Why it matters
The cost of leaving it / the value of fixing it.

## Proposed change
The concrete edit — which artifact, and preferably **which existing rule to
amend**, quoting its current text. Behavior, not a full diff.

## Expiry
How we would know this has stopped being true — the version, tool, model
behaviour or repo shape it depends on. Write "structural" only if it genuinely
cannot expire.

## Filters
Model-default: <why a competent model gets this wrong with no guidance>
Locality: <why this is true everywhere, not just here and now>
Amend-or-add: <the rule this sharpens, or why it is new ground>
```

The **Expiry** field is what makes this backlog prunable later: without it, every rule is permanent by default and `/evolve` has nothing to test a stale one against.

## Step 5 — Apply local learnings, drain, report

Local facts → `.claude/rules` / `CONTEXT.md` / an ADR. Assistant context → memory. **Clear the processed entries from `.work/learnings.md`.**

Report: each learning filed with its destination, **each candidate dropped with the filter that killed it**, and the raw → filed count. Then:

> Run `/evolve` inside a plugin repo to turn its `ai-learning` issues into reviewed PRs.

## Principles
- **The bar is the feature.** Filing less is the point of v2; a session that files nothing is a normal outcome.
- **Route by ownership** — don't dump everything locally; that's how propagation dies.
- **Amend before you append.** A bullet per session is how a coherent artifact becomes a list.
- **True everywhere, or only here and now?** A local workaround is a bug report about your machine.
- **A failure whose signature is absence needs a gate, not a paragraph.**
- **Every rule carries an expiry**, or it is permanent by default.
- Issues are *actionable changes to shared artifacts*; memory is *assistant context*.
