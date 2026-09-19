# What counts as evidence

Referenced by `/build`, `/verify-build`, `/design`, `/design-multi`, `/evolve`, the `full-gate` skill and the `executor` / `verifier` / `test-runner` / `design-lane` agents. Those artifacts carry the **triggers** — the greppable condition each one must watch for. This file carries the four facts every trigger falls out of, so they are stated once instead of ten times.

That line is a manifest: `scripts/check-artifact-links.py` enforces the backlink both ways; add a consumer there when you add the link.

---

## 1 — A verdict is evidence only about what it actually executed

A gate reports on the path it ran and nothing else. How that path is narrower than it looks:

- **It ran nothing.** `Tests: 0 total`, an all-skipped env-gated tier, a suite that died at collection, all exit 0. A run with no parsed summary line, or a zero count, is inconclusive: never green, and never usable as a baseline.
- **It could not see your code.** Ignore-patterns and `include` globs decide what collects: compare test files on disk with what the runner reported.
- **It never ran.** A fail-fast runner reports every step after its first red one as `skipped`; a runner hardcoded to named paths collects nothing from a new artifact kind. A gate list is a list of runners, not a map of what they observe: resolve each to its paths before reading green as coverage, and run what a red step prevented.
- **It ran the other direction.** A reversible operation usually takes two write paths; forward-green says nothing about the inverse.
- **It ran the wrong adapter.** An in-memory double ignores options the real one honours; prove a persistence claim on the real adapter or say it is unproven.
- **Its corpus lacked the shape.** A zero delta over a pinned corpus is evidence only about shapes the corpus contains: name the relevant shapes it lacks before reading the delta as a pass.
- **Its environment differed.** An assertion reading ambient `PATH`, `HOME`, `TZ`, locale or git config has a verdict that is a property of who ran it; the fixture sets or scrubs it.
- **The load was different.** A wall-clock ceiling (asserted, or the runner's default timeout) fails under contention; outside the diff surface and green when re-run idle, it is an environment artifact.

**The rule: a gate states its blind spot in the same breath as its verdict.** "Green" with no named blind spot is a claim, not a result.

**The corollary: a negative result is evidence only if the probe could have produced a positive.** Every absence claim ships with a positive control, something the probe must flag, run in the same breath; a detector never seen to fire is not evidence of calm.

**A check that takes configuration is verifiable only on the path it is configured right**: the configured-wrong path gets its own assertion (non-empty table, known subjects covered, row count reconciled).

**Ask of every check whether it fails alarming or fails reassuring.** A false alarm is investigated in a minute; the same defect in a success check is believed, so those need the positive control.

## 2 — A green oracle proves the code matches the test, never that the test matches the design

RED-before-GREEN rules out a vacuous test, not a confidently wrong one, which passes every mechanical gate and the next reader treats as settled. Two things discriminate:

- **Mutation.** Break the production line the test claims to catch and watch it go red, naming the assertion. A predicate claimed as single-source-of-truth fails at least one test per declared consumer; a shortfall is the finding, because a second inline copy of the rule is mutation-blind. Per clause, one mutation that kills it and one assertion that catches it; two clauses enforcing one predicate make each other unkillable, so delete the twin. Where the deliverable is a test or a guard there is no natural RED, so mutation is the only evidence; a guard over prose is mutated by rewording (a contradicting sentence added, the rule inverted, the sentence moved past the action it gates), which a presence needle survives and a closed set (every unit of the section pinned and keyed, so any addition, edit or move fails and names the unit; a legitimate rewording updates the list) does not.
- **An independent reader who is told what to doubt.** An executor's self-flagged deviations are the highest-value input a verifier gets, and free; discarded at the step boundary, they are a bug report nobody reads.

Say what cannot be mutation-checked.

## 3 — An inherited statement is a claim with a provenance and an expiry

Ticket prose, a resolved block, a directive, a clean sweep verdict, an ADR citation, a baseline, a generated artifact: each arrives with authority; none is evidence.

- **Verify the reasoning against behaviour, not the text against the text.** A cited site still reading as quoted proves the quote, not the claim; the highest-risk kind re-argues an existing behaviour as prose, and no oracle can fail.
- **Verify the *mechanism* behind a stated rationale, not only the defect.** A deferral's reason, a stated blocker, a named mitigation, a worked example: run it, make the call, read the cited lines.
- **A uniqueness or exhaustiveness claim is a probe, never a premise.** Grep before building on it. State what a count counts ("5 files / 7 call expressions", not "five call sites") and quote symbols as the source spells them: a paraphrased identifier is indistinguishable from a real one until you grep.
- **A measured figure carries the command that produced it, with its flags, and the predicate it tested.** A count equal to the limit passed is a lower bound, not a population; when one command answers two questions, name which the figure belongs to.
- **Name the corpus you searched.** An installed package, a plugin cache and a deployed build diverge from the source tree the gates read; `mtime` is not provenance; a directory listing shows only what reached your branch.
- **Every inherited fact has an expiry.** A conflict inventory dies on the next sibling merge; a pinned base moves when someone else merges; a recorded `agentId` dies with its session; a green CI check is void once its base moves. Stamp a claim with the sha, ref or moment it was computed against and re-derive it before acting; read a check's sha and timestamp, never its colour.
- **In-session behaviour is evidence about the loaded version, not about the design question.** An absence in the running session is never an argument against adding something.

When a claim survives, the useful output shape is a falsification table: `claim → probe run → holds / FALSE`.

## 4 — Silence generalizes

A specification's gaps get filled by whatever rule sits next to them. **An unspecified seam adjacent to a specified one is the highest-risk place in a design**: the specified rule is exactly what gets reused there, and the two seams frequently want opposite answers (read-modify-write pairs, the two halves of one document, the read and write paths over one state). The better-evidenced the document, the more confidently its rule fills the gap; a design also names what it did not decide.

The same silence bites at every step boundary: each step runs in a separate context and `.work/` is gitignored, so what a step discovered is lost unless committed or declared re-derivable, with the command.

## Probe hygiene

How a read-only probe returns a clean, plausible, wrong answer:

- **A pattern that matches nothing returns a clean zero, so a negative-universal sweep carries a positive control on its own filter or pathspec** (the same probe on a known-present token). Silent zeros: `--include` after the path operands (BSD `getopt` stops parsing options at the first operand); a wrong extension in the filter; a quoted git pathspec with `**` and no `:(glob)`; three zsh quoting shapes.
- **A `cd` inside a compound command persists into later calls.** Use absolute paths, `git -C <path>`, or a subshell.
- **`$?` after a pipeline or a redirect-then-echo is the last command's**, not the tool's: capture `rc=$?` on its own line, or `${PIPESTATUS[0]}`, and judge on the printed verdict.
- **`find -maxdepth N` silently excludes deeper paths**; an empty depth-bounded find is inconclusive, exactly like `Tests: 0 total`.
- **Backticks expand in any unquoted shell context, double quotes included**: a `<<PY` heredoc and `gh … --body "<markdown>"` both substitute them and exit 0. Use `<<'PY'` and `--body-file`; when a command should affect N things, print N and check it.
- **`cat` on a large file returns a short preview and persists the rest**: read a known-large artifact with `Read` or a windowed `sed -n` after an index pass, and keep source greps out of `build/` and `dist/`.

None looks like an error; the positive control from §1 catches them. A count of hits is not a positive control, and never a finding until each hit is classified.
