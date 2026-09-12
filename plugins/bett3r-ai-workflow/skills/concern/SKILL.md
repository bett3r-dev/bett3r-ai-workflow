---
name: concern
description: Instantly capture an owner's stated bar — a ticket owner, reviewer, or human collaborator saying what must hold true before this ships — the moment it is said, from any step (design, build, verify, a review comment). Use when someone states a hard requirement, a "must", a "this can't ship unless", a red line, or an explicit acceptable-risk waiver. Not for ordinary acceptance criteria already tracked elsewhere — only for a bar an owner is stating as the thing that decides whether the unit lands. Writes to committed concerns.md; verified later at /verify-build by concerns-check.
---

# Concern

Capture **one owner-stated bar, right now**, frictionlessly — so attribution and the verbatim quote survive until `/verify-build` rules it. No classification, no verification, no confirm. The whole point is to not lose *who said what must hold* in the middle of work: capture is cheap, and a bar remembered only as paraphrase loses the one thing the store cannot otherwise express — the speaker's own words.

## When

The moment an owner states a bar, from **any** step — `/design`, `/build`, `/verify-build`, a review comment, a live conversation. `/design` Step 1 also seeds concerns from explicit bars stated in the ticket itself, using this same skill.

## How

Resolve `<path>` with `work-docs-path --item <work_item>`, called exactly as `/design` Step 4 calls it — the work item exactly as `.work/mode.yaml` records it, never re-derived or hardcoded to `docs/prs`. Read the verdict line (ADR-004), never the exit code alone: `outcome=ok` names the folder as `path=`; `outcome=error` means write nothing and say the `reason=` in your prose.

Append **one entry** to `<path>/concerns.md` (create it if it does not exist — this is the first concern of the unit). **Append-only** — never overwrite or renumber an existing entry. Allocate the id as the file's highest existing `## Cn` id + 1 (1 if the file is new or empty).

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

Write exactly this shape: the file holds only entries — no title, no prose, no list. The `# …` comments name the allowed values; a trailing comment after `bar:` or `verdict:` is ignored. `concerns-check` rejects anything else loudly.

- **`bar`** — `hard` when the owner is stating a red line (the unit must not ship if it fails); `soft` when it is a preference or nice-to-have the owner still wants named.
- **`raisedBy`** — who said it and at which step, e.g. `ticket owner · step: design`, `reviewer · step: build`.
- **`quote`** — the owner's own words, verbatim, in quotes. Never a paraphrase — attribution is the one thing a bare acceptance criterion cannot carry. `quote:` is always this **raising** quote and is never overwritten; a later waiver's verbatim quote is recorded in `decisions.md` (kind: waiver, decidedBy: human) and cited from `evidence:` as `decisions.md#D<n>`.
- **`why` / `verify`** — why it matters, and how a later reader (a human or `/verify-build`) checks it. Write `verify` as an instruction the ruler can follow without you.
- **`verdict` / `evidence`** — always `—` when this skill writes the entry. **This skill never sets either field** — ruling a concern with evidence is `/verify-build`'s job (a later slice), not the capture step's. Setting them here would let capture and verification silently collapse into one untrustworthy step.

Then **carry on** with what you were doing. Do not stop to verify the concern, negotiate the bar, or check whether it is already met — that is `/verify-build`'s job, and pulling that work forward defeats the purpose of a fast, faithful capture.

## Boundary

`concern` only *captures*, with attribution. It does not verify, does not classify hard vs. soft beyond what the owner said, and does not decide whether the unit can land — `concerns-check` and `/verify-build` do that, reading the file this skill writes.

(Sibling pattern: a *[record](../record/SKILL.md)* — a thought worth keeping for later routing — is the same capture-now / process-later shape, but is processed by `/capture-learnings` rather than ruled at landing.)
