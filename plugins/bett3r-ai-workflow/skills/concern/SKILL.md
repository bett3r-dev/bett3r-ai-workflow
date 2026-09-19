---
name: concern
description: Capture an owner's stated bar the moment it is said (a "must", a "can't ship unless", a red line, an accepted-risk waiver), from any step, into the committed concerns.md that /verify-build rules.
---

# Concern

Capture one owner-stated bar, right now, with attribution and the verbatim quote; classify, verify and rule nothing here. `/verify-build` rules it later with `concerns-check`. An ordinary acceptance criterion tracked elsewhere is not a concern.

## When

The moment an owner (ticket owner, reviewer, human collaborator) states a bar, from any step: `/design` (which also seeds concerns from explicit bars in the ticket), `/build`, `/verify-build`, a review comment, a live conversation.

## How

Resolve `<path>` with `work-docs-path --item <work_item>`, the work item exactly as `.work/mode.yaml` records it. Read the verdict line: `outcome=ok` names the folder as `path=`; on `outcome=error`, write nothing and say the `reason=`.

Append one entry to `<path>/concerns.md` (create it for the unit's first concern), id = the file's highest `## Cn` + 1, or 1. Append only: an existing entry keeps its id and text.

```markdown
## C1 — <label>
bar: hard                # hard | soft
raisedBy: ticket owner · step: design
quote: "<verbatim>"
why: <why it matters>
verify: <how to verify at /verify-build>
verdict: —               # met | partial | unmet | cannot-determine | waived — set by /verify-build
evidence: —
```

The file holds only entries, no title or prose; `concerns-check` refuses anything else. `bar` is `hard` for a red line (the unit does not ship if it fails) and `soft` for a named preference. `quote` is the owner's own words and stays the raising quote for the entry's life; a later waiver's quote lives in `decisions.md` (`kind: waiver`, `decidedBy: human`) and is cited from `evidence:` as `decisions.md#D<n>`. `verify` is an instruction the ruler can follow without you. `verdict` and `evidence` are `—` when written here: ruling is `/verify-build`'s, and capture and ruling stay two steps.

Then carry on with what you were doing. The same capture-now, process-later shape holds for a thought worth keeping: that is `record`, drained by `/capture-learnings`.
