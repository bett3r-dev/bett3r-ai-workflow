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
- why: measured — 61 of 78 recorded silent seams cost no fix round, and the shape of the 17 that did also matches 44 that did not (~16% precision), so no syntactic signature separates them

The checkable parts were taken and are real gates: a slice may name nothing that
does not resolve at the base (`/plan` step 3), the unit's seams are named once
and a slice may not test at an undeclared one (`unnamed-seam`), and a decided
fork with no walk is refused rather than counted (`decided-nowalk`). What is
left is a design that was silent on a seam the executor then had to guess — and
no pattern over the text distinguishes that from a design that was silent
because there was nothing to decide. The disposition is therefore where the
judgement is: `/design`'s grill pass and the verifier's falsification table,
which attacks the design's claims rather than checking the diff against them.

**The search for a signature was made, and it failed on the evidence.** All 17
rounds were re-read (XL-27 6, ESAS-166 3, ESAS-162/163/186 2 each, ESAS-161/178
1 each), and the measurement that settles it is this: the corpus records **78
decisions of `kind: silent-seam` and only 17 `design-silent` fix rounds** — so
**61 of 78 design silences were filled by the executor at no cost at all.**
Silence is the norm, not the defect, which is the "absence looks like a decision
nobody needed" objection turned from an admission into a number.

The 17 do cluster — second-run/resume/already-exists/crash-after/missing-case
(7), two conditions collapsed onto one outcome or a self-contradiction (4), the
design stating something false (1), and a residue where nobody opened the fork
(5) — but the largest cluster is **not a signature**: that same shape matches
**44 of the 78** silent seams, so a `/plan` check keyed on it would refuse about
six innocent slices for every round it prevented (~16% precision). A gate at
that rate is routed around with a token scenario, which is worse than no gate.
The cluster was also read off the 17 instances it would be validated against —
the tautology this repo already refused — and the corpus is 10 build summaries
from this repo alone, so a 7-instance cluster inside it is not out-of-sample
evidence of anything.

**Classification stays `judgement`, now on evidence rather than as an
admission.** Do not re-read the 17; re-open this only against an out-of-sample
corpus (host-repo runs: teselly, pv3, esas), where the 78-vs-17 ratio and the
44-vs-7 precision are the two numbers to recompute first.

One taxonomy defect surfaced by the read: ESAS-178's round is recorded
`kind: false-premise` in its `decisions.md` but counted `design-silent` in its
build summary — the design was wrong, not silent. The true count is 16.

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
