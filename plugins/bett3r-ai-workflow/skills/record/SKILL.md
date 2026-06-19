---
name: record
description: Instantly capture a thought, learning, gotcha, or improvement to a buffer so it isn't lost — without stopping to route or process it. Use the moment something worth keeping is noticed, or when the user says "record / note / remember / don't forget / capture this". /capture-learnings processes the buffer later.
---

# Record

Capture **one thought, right now**, frictionlessly — so it survives until `/capture-learnings` routes it. No classification, no routing, no confirm. The whole point is to not lose an insight in the middle of work: capture is cheap, forgetting is not.

## What to capture

Anything worth keeping that would otherwise be gone by end of session: a flaw or improvement in the flow / a skill / an agent; a framework gotcha; a repo-specific surprise; a "we should change X". When in doubt, record it.

## How

Append **one entry** to `.work/learnings.md` (create `.work/` if missing — it's gitignored). **Append-only** — never overwrite or reorder. A few lines:

```
- [<context cue: phase / slice / what you were doing>] <the thought, 1–2 sentences>
  hint: <optional — which artifact or repo it's probably about, if obvious>
```

Then **carry on** with what you were doing. Do **not** stop to classify, route, or file it — that is `/capture-learnings`' job, and pulling that work forward defeats the purpose of a fast capture.

## Boundary

`record` only *captures*. It does not route to repos, file issues, or update rules/memory. Drain the buffer with `/capture-learnings` before finishing the work — and before `/start` replaces `.work/` — so a flow-level insight isn't lost with the ticket.

(Sibling pattern: a *concern* — something to re-check before landing — is the same capture-now / process-later shape, consumed by `/verify-build` instead.)
