---
name: record
description: Capture one thought, learning, gotcha or improvement to a buffer the moment it is noticed, or when the user says "record / note / remember / don't forget / capture this". Routed later.
---

# Record

Capture one thought, now, so it survives until `/capture-learnings` routes it. No classification, no routing, no confirm.

## What to capture

Anything worth keeping that would otherwise be gone by the end of the session: a flaw or improvement in the flow, a skill or an agent; a framework gotcha; a repo-specific surprise; a "we should change X". When in doubt, record it.

## How

Append one entry to `.work/learnings.md` (create `.work/` if missing; it is gitignored). Append only:

```
- [<context cue: phase / slice / what you were doing>] <the thought, 1–2 sentences>
  hint: <optional: which artifact or repo it is probably about>
```

Then carry on. Routing and filing are `/capture-learnings`' job; pulling them forward defeats the fast capture. Done when the entry is on disk.

## Boundary

`record` captures and nothing else: it files no issue and updates no rule or memory. Drain the buffer with `/capture-learnings` before the work ends and before `/start` replaces `.work/`. A [concern](../concern/SKILL.md), an owner's stated bar captured with attribution, is the sibling shape, consumed by `/verify-build` instead.
