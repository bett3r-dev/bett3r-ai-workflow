# Fix-round causes — what was DONE about each one

Every fix round is classified before it is dispatched (`/build` step 3), and the
classification lands in the unit's `build-summary.md`. This file is the other
half: what happened *next*. A cause recorded three or more times across the
corpus must appear here, and `scripts/check-repeat-causes.py` is red until it
does.

The rule, from Pocock's `retro`: **classify the violation first.** A mechanical
one — a fixed syntactic pattern, a banned API, an import shape, a file-location
rule — gets a **deterministic check, full stop**. Prose is reserved for genuine
judgement calls. Writing the rule down a second time is not a disposition; it is
the outcome the guard exists to make visible, because the second statement of a
rule costs attention in every future session and changes nothing about the run
that would have broken it.

The related placement rule, same source: **a standard is imposed by the review
agent, not the implementation agent** — the implementation agent is under the
most context pressure at exactly the moment it would have to remember. In this
flow that means a new judgement rule goes where the verifier reads, and a new
mechanical rule goes in `scripts/`; neither belongs in the executor's brief.

Format, read by the guard:

```
## <cause>
- classification: mechanical | judgement
- check: <repo-relative path>     # mechanical only — must exist
- why: <one line>                 # judgement only
```

---

## oracle-wrong

- classification: mechanical
- check: plugins/bett3r-ai-workflow/scripts/design-map.py

The largest cause in the corpus, and the one that could not be seen by the gate
that was supposed to catch it: a test encoding the wrong rule is genuinely red
before the code exists and green after, so RED→GREEN passes it cleanly and only
the verifier ever caught one — each catch re-paying a fresh executor context.

Three checks now fire in `check-plan`, all in the named file and all driven by
`scripts/test-plan-candidates.sh`:

- the **walk contract** — a decided fork's chosen option arrives as
  Given/When/Then (`walk-unstructured`, `decided-nowalk`), so what is promoted
  into an oracle is not prose;
- **`scenarios:` on every slice** (`slice-unscened`, `scenario-unstructured`),
  which is the half that reaches a unit with no `map.json` — both measured
  0%-first-pass-green runs were exactly that;
- **oracle adequacy** — `slice-unprobed` (the mutation that must turn the oracle
  red, named at plan time) and `scenario-unsourced` (the expected value comes
  from an independent source and cites it).

Discrimination — a RED that is an assertion with values, never a hang or an
import error — is the part of this cause that is a property of the run rather
than the plan, and is enforced in `agents/executor.md` and `/build`'s fix-round
causes. It is deliberately not a YAML field: a field claiming it would be a
claim.

## design-silent

- classification: judgement
- why: the mechanical halves are checked; the residue is "the design did not say", which has no syntactic signature — absence of a decision looks exactly like a decision nobody needed

The checkable parts were taken and are real gates: a slice may name nothing that
does not resolve at the base (`/plan` step 3), the unit's seams are named once
and a slice may not test at an undeclared one (`unnamed-seam`), and a decided
fork with no walk is refused rather than counted (`decided-nowalk`). What is
left is a design that was silent on a seam the executor then had to guess — and
no pattern over the text distinguishes that from a design that was silent
because there was nothing to decide. The disposition is therefore where the
judgement is: `/design`'s grill pass and the verifier's falsification table,
which attacks the design's claims rather than checking the diff against them.

**This entry is an admission, not a resolution.** 17 recorded rounds is the
largest count in the corpus, and if a syntactic signature for it is ever found,
this entry should become `mechanical` with a check beside it.

## invariant

- classification: mechanical
- check: .claude/gate.sh

A repo rule that was not followed is the definitional mechanical cause, and the
disposition is the one the rule states: it becomes a step that goes red. In this
repo that is the gate, whose guards are exactly this shape — `validate-plugins`
(every artifact's frontmatter and manifest), `needles` (an absorbed fact that
left with the words carrying it), `artifact-links`, `skill-shadows`,
`closes-syntax`, `no-full-gate`, and now `repeat-causes` itself. A rule that
cannot be added to that list is not yet a rule.

**Honesty about this entry's evidence:** the four recorded rounds were not
individually re-read when it was written, so it records the *disposition rule*
for this cause, not a root cause per instance. The guard's job is to force the
entry to exist; grading it is the reader's.
