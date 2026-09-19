---
description: Capture what this session taught and route each learning to the repo that owns the artifact, filed with its filters and expiry. Most sessions file nothing.
---

# /capture-learnings

`Call the Skill tool with "writing-for-agents"`. Its pruning section is the filing bar: a candidate that fails the no-op test, duplicates a rule that already has a home, or cannot name what retires it is not a learning. A session that files nothing is a normal outcome.

## Step 1 — Gather

Read `.work/learnings.md`, the `record` buffer, and in a fleet run `<run>/learnings.md`, the merged file (the per-unit `<run>/units/*.learnings.md` when the merge has not run); then review the session for anything not yet recorded. Done when every candidate is listed with where it came from.

## Step 2 — Classify: mechanical or judgement

Ask of each candidate whether the thing it guards against is mechanical: a fixed syntactic pattern, a banned API, an import shape, a file-location rule, a census over call sites, a required field, an artifact that must exist. If so it gets a deterministic check, full stop: a script in the plugin's `scripts/` (or its gate) or a hook, and writing a rule is the fallback, because a rule a future agent has to remember competes with every other rule for attention and the same defect ships again with every gate green. What remains is judgement, where no pattern separates the good case from the bad one; it becomes prose where the **verifier** reads, never a line in the executor's brief, since the implementer is under the most context pressure at exactly the moment it would have to remember.

A fix-round cause that `build-summary.md` records again and again is the strongest input here and is already measured: `/build` classifies every fix round from its closed cause set, and a cause recorded three times owes a disposition in `docs/causes.md` (`scripts/check-repeat-causes.py` stays red until it names the check that now fires or the judgement no check can make). Done when every candidate carries `mechanical` or `judgement` and the kind of destination that follows.

## Step 3 — Filter

Run each candidate through writing-for-agents' pruning tests and keep the three answers the issue body asks for: why a competent model gets this wrong with no guidance (a fact about this system, or a failure whose signature is absence, passes; an exhortation fails); whether it is true everywhere rather than here and now (a workaround for one machine, token or tool version is a bug report about that machine, and if it must be recorded it records why and what expires it); and which existing rule it sharpens (an edit quoting the current text is the preferred outcome; a second instance of a stated rule means the rule is not landing, so make it fire instead of restating it). Done when every dropped candidate names the test that killed it.

## Step 4 — Route by ownership

| The learning is about… | Owner | Destination |
|---|---|---|
| the flow: a command, skill or agent of this plugin | `bett3r-ai-workflow` | GitHub issue in that repo |
| a PV3 / DDD framework pattern or skill | `bett3r-pv3-ai-skills` | GitHub issue in that repo |
| a CDSE frontend pattern or skill | `bett3r-cdse-ai-skills` | GitHub issue in that repo |
| this repo's own domain or conventions | host repo | `.claude/rules` / `CONTEXT.md` / an ADR, here |
| cross-session context for the assistant | local | memory |

Propose the target; the user can redirect; default to local when ambiguous, since a wrong-repo issue is worse than a local note. Before writing to `.claude/rules/<x>.md` or `.claude/skills/<x>/`, run `check-skill-shadows` (on `PATH` from this plugin's `bin/`): a local file named after an installed plugin skill, command or agent is a shadow, and a learning written there strands in one repo while both copies load. File it in the owning plugin instead. Done when each survivor has one destination (two when it genuinely has two homes).

## Step 5 — File plugin-owned learnings

Resolve the repo from the plugin's `plugin.json` `repository` (else `origin`). Dedupe first with `gh issue list --label ai-learning --search "<keywords>"` and comment on a near-duplicate rather than re-filing. Then compose and create, one confirm:

```
gh issue create -R <owner>/<repo> --label ai-learning --title "<concise>" --body-file <path>
```

Write the body to a file: `--body "<markdown>"` is a shell string, so backticked paths are command-substituted away while `gh` exits 0. The body:

```
## Observed
What happened, in context (link the session / PR if useful).

## Why it matters
The cost of leaving it / the value of fixing it.

## Proposed change
The concrete edit: which artifact, and preferably **which existing rule to
amend**, quoting its current text. Behavior, not a full diff.

## Expiry
How we would know this has stopped being true: the version, tool, model
behaviour or repo shape it depends on. "structural" only if it cannot expire.

## Filters
Model-default: <why a competent model gets this wrong with no guidance>
Locality: <why this is true everywhere, not just here and now>
Amend-or-add: <the rule this sharpens, or why it is new ground>
```

`Expiry` is what lets `/evolve` prune later. Done when every plugin-owned survivor is an issue or a comment on one.

## Step 6 — Ledger the evidence

An incident, a measurement or a war story is evidence for a rule, not a rule. In the owning plugin it goes to the ledger, the file `LEDGER.md` at the root of the plugin's payload next to its `README.md`, as one entry with five fields: the rule it supports, the source it came from, the evidence verbatim, when it was recorded, and what retires it. The artifact gets only the rule, with at most one clause of reason. In an issue, the story sits under `Observed` and the rule under `Proposed change`, so `/evolve` can split them the same way. Done when no proposed edit carries a date, a figure or a "once" story as instruction text.

## Step 7 — Apply, drain, report

Local facts go to `.claude/rules`, `CONTEXT.md` or an ADR; assistant context to memory. Clear the processed entries from `.work/learnings.md`. Report each learning filed with its destination, each candidate dropped with the test that killed it, and the raw → filed count. Then:

> Run `/evolve` inside a plugin repo to turn its `ai-learning` issues into reviewed PRs.
