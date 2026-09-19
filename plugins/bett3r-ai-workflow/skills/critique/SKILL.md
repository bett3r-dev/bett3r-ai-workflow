---
name: critique
description: Critique a design or technical decision adversarially through structured lenses (arch, ops, user, investor) and return a ranked verdict. Use for honest, unfiltered feedback on a resolved position.
---

# Critique

One divergent pass over a resolved position: where `grill` converges with you, `critique` attacks the result before you commit to it. Project-agnostic: it judges the design on its own terms and against the host repo's conventions.

## Arguments

`$ARGUMENTS`: the target (everything that is not a flag), `--lens arch|ops|user|investor|all` (default `arch,ops`) and `--tone normal|brutal` (default `normal`). With no target, critique the active design: `design.md` in the folder `work-docs-path --item <work_item>` names, called as `/design` Step 4 calls it.

## Input: facts, not a summary

The input carries the grounding pass's verified facts (`symbol (file:line)` citations, grep and enumeration results, the call sites checked), not only the narrative. A prose summary is self-consistent by construction, so lenses fed one return opinion the author could have produced; fed facts, they catch the argument being wrong about the code. Restatement-heavy output is a cost signal, not a clean bill of health: the input was too abstract.

## Tone, always on

Substance over compliments, with no preamble praise. State the problem ("this breaks when Y"), not "have you considered". Name the unstated assumptions. Every criticism says what is wrong and what would fix it. Evaluate as a colleague protecting the author's time. `--tone brutal` drops every qualifier: only "will" and "does".

## Lenses

`arch` (core): the implicit assumptions and which are fragile; the tightest coupling and what breaks when it changes; the scaling wall at 10× load; the complexity introduced and whether the problem justifies it; a simpler design at a fraction of the cost.

`ops` (core): deploy without downtime and roll back; observe it working; debug it at 3am; run old and new side by side; the blast radius on failure.

`user` (opt-in): what confuses or frustrates; the most common task and its step count; recovery from a mistake; what is missing; where latency shows.

`investor` (opt-in): opportunity cost; time-to-value; the risk that makes it worthless; a cheaper experiment; the fatal flaw a skeptic names.

## Verdict

The top three weaknesses ranked by severity, each with why it matters and a concrete fix; a severity score 0–100 (0–30 rethink, 31–50 major issues first, 51–70 viable with risks to manage, 71–85 solid with gaps, 86–100 minor refinements); kill-or-continue in one sentence. Before presenting, re-read your own critique for pulled punches and fix-less findings and rewrite the weakest points; deliver only the improved version.

```
## Critique: <short title>

### <Lens> Analysis
<numbered findings — problem + fix>

---

### Verdict

**Top 3 weaknesses:**
1. <weakness> — <why it matters> — <fix>
2. …
3. …

**Severity: <X>/100** — <one-line justification>

**Kill-or-continue:** <decision + one sentence>
```
