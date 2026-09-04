---
description: Grill the design to shared understanding while sharpening the domain model, then write a reviewable design doc. Constraint-shaped rewrite — same outputs, less procedure.
---

# /design — grill + model the design

Resolve the design through a relentless interview, sharpening the ubiquitous language as you go, and leave a **reviewable** design doc plus durable glossary/ADR updates. The `grill` skill drives the interview; `domain-modeling` maintains the model; `critique` attacks the result.

**This command states what must be true and what must be produced, and leaves the procedure to you.**

## Argument: $ARGUMENTS
The thing to design (a ticket id, a feature description, or "the active work").

---

## Board mode

If this repo has no `.esas/`, skip this section entirely and **say nothing about boards.**

If it does: board mode is on only when a board is both **possible** (`.esas/` with a `graph.json`, `esas-mcp` registered) and **warranted** (the design's forks name graph artifacts — commands, events, policies, read models, aggregates). Run the preflight in `../skills/esas-design/PREFLIGHT.md` for capability, and read `../skills/esas-design/BOARD-SETUP.md` for the seeding rules and what changes below; `esas-design` owns the standing rules once the tools are live.

Three constraints on the gate itself:

- **On a no, say nothing at all** — no offer, no "we won't need it", no mention a gate was consulted. A mention hands the user a second surface to have an opinion about in a design where the answer is already known.
- **When it is close, unsure means silent**, and never resolve the doubt by asking. A false yes costs a screen the user did not want; a false no costs a board that arrives one fork later. Those are not the same size.
- **Re-ask at every new artifact-touching fork.** The gate is answered at the moment of least knowledge, so a design that opens on config and turns structural at fork 4 arms then. A late board loses nothing — it is a projection and catches up when it opens.

Classify by the tree in front of you, not the label on the ticket. "Frontend" is not outside the model by definition (`ui` is a node type in the extractor's own graph).

---

## Step 1 — Ground

Read the ticket, then the relevant bounded context's `CONTEXT.md` (locate via `.esas.config.json` `domainEventsPath`). Where there is none, fall back through `docs/adr/` to **the module headers of the symbols you were told to grep** — and read the headers even when the ADRs hit; in a repo that writes doctrine into headers, the ADRs are the summary and the headers are the source. Say "grounding degraded: no CONTEXT.md" in the doc and recommend `/seed-context`.

Treat the glossary as **evidence to verify, not ground truth**.

### The ticket is evidence, not spec

Stale tickets are the norm — in one 4-ticket run three descriptions were stale and a fourth's premise was false. Verifying costs minutes and is what the design-first gate is *for*. **Where the ticket and the code disagree, the code wins, and the doc says so.**

You know how to verify a claim against a repo. What is worth stating is the shape of the failures, because each one reads as evidence when it is not:

- **A paraphrased identifier is indistinguishable from a real one until you grep.** Quote every symbol as the source spells it, and state what a count counts — "5 files / 7 call expressions", never "five call sites".
- **A uniqueness or exhaustiveness claim is a probe, never a premise** — "the only surface", "nothing else reads this", "three call sites".
- **Check the *mechanism* behind a stated rationale, not just the ask.** A deferral's reasoning, a stated blocker, an "already handled by X" — each is usually one probe from being materially different, and a false one collapses the proposed fix.
- **Ticket-prescribed architecture is a claim**, checked against the code's own rules. An override is recorded as a rejected option *and* surfaced as an open fork — never silently corrected in either direction.
- **When the ticket says "this claim/comment is wrong", grep the claim, not the file.** Its real size is the set of decisions that *cite* the claim. `git log -S` the distinctive phrase: *stale* and *never true* call for different corrections.
- **When the claim is about another repo's runtime behaviour, check the artifact that executes** — the installed package, the version-keyed plugin cache, the deployed build — not only its source. Restate what corpus a "grep returns zero" searched, and check the sibling corpus.
- **A generated artifact is evidence only if you can name the commit that produced it.** `mtime` is not provenance.
- **If the ticket ships a worked example of the defect, run it.**

A read-only probe returning a false negative is used as evidence that a handler is dead or a file absent. [EVIDENCE.md](../EVIDENCE.md) has the three ways this fails silently on the default macOS shell and the positive control that catches all of them.

## Step 2 — If the ticket carries a resolved-design block

Grep for `design-multi:resolved:vN` (emitted as an HTML comment *and* a visible inline-code line). If present, its design was resolved in an earlier `/design-multi` interview. **This run is a verification second pass, not a fresh grill:** treat the decisions as authoritative pre-answers, confirm each still holds against current code, and re-open a fork only where the code now *contradicts* it. On a ticket whose code has not drifted the grill has nothing to ask and flows straight to Step 4. That is what lets `/start-multi` run such a ticket unattended.

**Verify the block's claims, not that its prose fits.** A decision can be interview-resolved, zero-drift, paste-ready and factually false — the interview happens once and runs unattended afterwards, so an error introduced *during* the interview has no downstream gate, and zero drift reads as nothing to check. Four cheap defences:

- Any decision citing a doc or ADR **by line range: read that range.**
- A decision that **re-argues an existing behaviour** rather than changing anything is the highest-risk kind — it ships as prose, has no test, no oracle can fail it. Re-derive it.
- **Verify the mitigation, not just the risk.** A block's own Risks section is a ready-made checklist; the known case had the risk fire *through* its mitigation, which was itself the false claim.
- You may **keep a decision while declining to assert a falsehood it rests on** — record the correction in the PR body. Ship-blocking a human for "your reason is wrong but your decision stands" is the wrong trade.

Then **enumerate what the block does not decide.** Drift-checking is a check against what the block *says*, so its silence is invisible — and the better-evidenced the block, the more confidently an executor generalises into the gaps. For each decision naming a rule (a merge, an ordering, a degrade direction, a precedence), ask which other component performs the same class of operation and whether the block speaks to it. Emit the unanswered ones as **unspecified seams** and pass them down as explicit non-guidance.

## Step 3 — Grill, then critique

Run the interview (`grill` + `domain-modeling`): every branch of the decision tree, one question at a time, each with your recommended answer, dependencies resolved before moving on. Under board mode the independent forks batch to the canvas and the dependent ones stay serial.

**Every fork is presented picture → scenarios → per-option walk** — `grill`'s *Presenting a fork* owns the shape and this is where it is mandatory. Two option labels are not a question: the user cannot tell from them whether you are discussing the same thing they are. Where every scenario walks identically across the options there is no fork — resolve it and record it as an autonomous decision.

While you interview: challenge terms against the glossary, update `CONTEXT.md` inline the moment a term resolves (glossary only), and offer an ADR only when a decision is hard-to-reverse **and** surprising **and** a real trade-off.

Then run `critique` (`arch,ops`) against the resolved tree — one focused adversarial pass, not a second grill. Fold in what is clearly right; drop back to the grill for a genuine fork it surfaces; carry a weakness with no good answer into *Risks*.

## Step 4 — Write `.work/design.md`

Markdown + Mermaid, reviewable in one pass, ephemeral and **not committed**. Its durable conclusions live in the committed glossary/ADR updates and, later, the PR body. Sections:

- **Problem & intent**, in the ubiquitous language.
- **The resolved decision tree** — each pivotal fork, the chosen answer, the why, the rejected options.
- **Seams / flow** — a Mermaid diagram of the key flow and any new boundary crossed.
- **Test seams** — where this gets verified. Prefer existing seams, the highest seam possible, the fewest (ideal: one), each with a prior-art test to mirror. These become the slices' oracles — confirm them with the user.
- **Risks / the gate-less seam** — the riskiest part nothing automatically catches. This becomes the tracer bullet.
- **Unspecified seams** — what this design deliberately does not decide. An unspecified seam **adjacent to a specified one** is the highest-risk place in the document, because the stated rule is exactly what will be reused there. Recurring shapes: read-modify-write pairs, the client and server halves of one document, the read and write paths over one piece of state.
- **Scope boundaries** — explicit in/out, follow-ups to spin off.
- **Provenance** — the commands that produced this design's numbers and claims. Cheap to write; it converts every empirical finding into something the next context can re-run, and resumed cold it is reliably the most useful section in the doc.

## Step 5 — Hand off

**Answer this before handing off: could a fresh session holding only this repo and `.work/design.md` run `/plan` without loss?** Enumerate what this session produced — files, commands and their outputs, counts, external state — and confirm each is in the doc, committed, or declared re-derivable with the command to re-derive it. The failure **scales with how good the session was**: the more empirical spikes it ran, the more it produced that the doc format never asked for.

Corollary: **any artifact the design names as a test seam, gate, or tracer-bullet instrument is committed, not left untracked** — or the doc states plainly that the first slice creates it. A design depending on an uncommitted file is neither reviewable nor resumable.

Then summarise the resolved design, the `CONTEXT.md`/ADR updates, and the open risks:

> Review `.work/design.md`. When it's right, run `/plan` to cut it into vertical slices.

## Principles
- The grill is the engine; the docs are a side effect. Don't let doc-writing slow the interview.
- `CONTEXT.md` is durable and committed; `design.md` is ephemeral.
- Speak the ubiquitous language — a term the glossary lacks is a term to resolve and record.
