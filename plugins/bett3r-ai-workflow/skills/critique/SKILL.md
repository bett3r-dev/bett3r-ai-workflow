---
name: critique
description: Adversarially stress-test an idea, design, or technical decision through structured lenses (architecture, ops, user, business) and return a ranked verdict. Use when you want honest, unfiltered feedback — the divergent counterpart to grill's collaborative interview.
---

# Critique

A one-shot, multi-lens adversarial assessment of a design or technical decision. Where `grill` is *convergent* — an interactive interview that drives toward shared understanding *with* you — `critique` is *divergent*: it evaluates a resolved position *against* it, surfacing what's flawed before you commit. Use grill to reach a decision; use critique to attack it.

This skill is project-agnostic: it judges the design on its own terms and against the host repo's conventions, not against any baked-in framework.

## Arguments

`$ARGUMENTS`

Expected forms:
- `<idea or design description>` — defaults to the core lenses
- `--lens arch|ops|user|investor|all` — focus on a perspective (default: `arch,ops`; `all` runs every lens)
- `--tone normal|brutal` — directness (default: `normal`)

Examples:
- `/critique We're adding a new event-sourced aggregate for order fulfillment`
- `/critique --lens arch --tone brutal The API gateway fans out to 5 services per request`
- `/critique --lens all The checkout flow requires 4 steps before payment`

If no target is given, critique the active design — read `.work/design.md` if it exists.

## Tone (always on)

Whatever the `--tone`, these hold:

- **Substance over compliments.** Never soften criticism. No preamble praise — start with the analysis, not "great idea".
- **Don't hedge with "have you considered…".** State the problem: "This won't scale because X", "This coupling breaks when Y".
- **Name the assumptions.** If the design rests on an unstated assumption, call it out explicitly.
- **Specific and actionable.** Every criticism says *what* is wrong and *what would fix it*. No vague "this could get complex" — say why it's complex and what breaks.
- **Third-party framing.** Evaluate as if a colleague asked for honest feedback and you want to save them from wasting effort on something flawed. Protecting their time is the job.

`--tone brutal` amplifies this: no qualifiers, no "might/could" — only "will/does". Be blunt about what's broken.

## Input contract — hand the lenses facts, not a summary

**The input must carry the grounding pass's verified facts** — `file:line` citations, grep and enumeration results, the call sites actually checked — and not only the design narrative. This is an explicit requirement of the caller (`/design` Step 2.5, `/design-multi` Phase A), not something to be summarised away.

The reason is structural: **a prose summary of a design is self-consistent by construction**, so the lenses can only critique the *argument*, and they return architectural opinion the author could have produced themselves. Given facts, they can catch the argument being **wrong about the code** — which is the failure that actually matters and the one an author cannot catch by re-reading their own draft. One such pass returned a single finding that justified the whole cost: a call site discarding exactly the value the ticket was about, at exactly the site of the silent degrade. It flipped the recommended fix and invalidated the draft's proposed rendering outright.

**Restatement-heavy output is a cost signal, not a clean bill of health** — it means the input was too abstract, not that the design was sound.

## Step 1 — Parse

Extract the **target** (everything that isn't a flag), the **lens** set (default `arch,ops`), and the **tone**. Where a claim in the design can be settled by reading the code, read the code — critique from evidence, not speculation.

## Step 2 — Apply each active lens

#### `arch` — Architecture (core)
1. What **implicit assumptions** does this depend on? Which are fragile?
2. Where is the **tightest coupling**? What breaks if that dependency changes?
3. What's the **scaling wall** — which component fails first under 10× load?
4. What **complexity** is introduced, and is it justified by the problem?
5. Is there a **simpler design** that gets 80% of the benefit at 20% of the cost?

#### `ops` — Operations (core)
1. How do you **deploy** this without downtime? What's the rollback?
2. How do you **observe** it working — what metrics/alerts?
3. How do you **debug** it at 3am when it breaks?
4. What's the **data migration** story — can old and new run side by side?
5. What's the **blast radius** when this component fails?

#### `user` — End-user (opt-in)
1. What will users find **confusing or frustrating**?
2. What's the **most common task**, and how many steps does it take?
3. What happens when the user **makes a mistake** — is recovery easy?
4. What's **missing** that users will immediately ask for?
5. Will it feel **fast enough** — where is latency noticeable?

#### `investor` — Business (opt-in)
1. What's the **opportunity cost** — what are you *not* building to build this?
2. What's the **time-to-value**?
3. What's the **biggest risk** that makes this investment worthless?
4. Is there a **cheaper experiment** to validate the core assumption first?
5. What would a **skeptical investor** call the fatal flaw?

`--lens all` runs all four. The default (`arch,ops`) fits most engineering-flow critiques; reach for `user`/`investor` when the decision is product- or business-shaped.

## Step 3 — Verdict

1. **Top 3 weaknesses** — ranked by severity. Each: what's wrong · why it matters · a concrete fix or mitigation.
2. **Severity 0–100:**
   - 0–30: fundamentally flawed, needs rethinking
   - 31–50: major issues to address before proceeding
   - 51–70: viable but with significant risks to manage
   - 71–85: solid, some gaps to close
   - 86–100: strong, minor refinements only
3. **Kill-or-continue** — one sentence: proceed as-is, proceed with changes, or back to the drawing board.

## Step 4 — Self-grade (internal, not shown)

Before presenting, check your own critique: was it genuinely critical or did it pull punches? Did every criticism carry a specific fix? Did it challenge real assumptions or nitpick surface details? If it rates below 70/100 on usefulness, **rewrite the weakest points** first. Don't show the self-grading — just deliver the improved version.

## Output format

```
## Critique: <short title>

### <Lens> Analysis
<numbered findings — problem + fix>

### <next lens…>
…

---

### Verdict

**Top 3 weaknesses:**
1. <weakness> — <why it matters> — <fix>
2. …
3. …

**Severity: <X>/100** — <one-line justification>

**Kill-or-continue:** <decision + one sentence>
```
