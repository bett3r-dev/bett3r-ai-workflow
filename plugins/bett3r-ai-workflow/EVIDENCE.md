# What counts as evidence

Referenced by `/build`, `/verify-build`, `/merge-multi`, `/design`, `/design-2`, `/design-multi`, `/design-multi-2`, `/start-multi`, the `full-gate` skill and the `executor` / `verifier` / `test-runner` / `provisioner` / `unit-lane` agents. Those artifacts carry the **triggers** — the greppable condition each one must watch for. This file carries the four facts every trigger falls out of, so they are stated once instead of nine times.

That line is a **manifest, not prose**: `scripts/check-artifact-links.py` parses it and enforces the backlink in both directions, because this file shipped linked from 5 artifacts while needed by 8 — the stated risk of putting shared facts in one place is that a reference is only as good as the reference being followed. Add a consumer to that line when you add the link, or the gate fails.

---

## 1 — A verdict is evidence only about what it actually executed

A gate reports on the path it ran, and nothing else. Every way that path turns out narrower than it looks has been paid for here at least once:

- **It ran nothing.** `Tests: 0 total`, an all-skipped env-gated tier, a suite that died at collection — all exit 0. A run with no parsed summary line, or a zero count, is **inconclusive**: never green, and never usable as a baseline.
- **It could not see your code.** Ignore-patterns and `include` globs decide what collects — `*.test.tsx` under an `include` of `*.test.ts` has never run, ever. Compare test files **on disk** against the files the runner **reported**; a material gap is a config defect, not coverage.
- **It ran the other direction.** A reversible operation (suspend/resume, apply/undo, migrate-on-read vs on-write) usually takes two *different* write paths — one a merge, one a replace; one a dot-path, one a whole-row rebuild. Forward-green is not evidence about the inverse.
- **It ran the wrong adapter.** An in-memory double silently ignores options the real one honours, and its query operators mean different things. Prove a persistence-semantic claim on the real adapter, or state plainly that it is unproven.
- **Its corpus lacked the shape.** A zero delta over a pinned corpus, a golden file or a fixture set is evidence only about shapes that corpus *contains*. Before reading a delta as a pass, state **which shapes relevant to this change the corpus does not contain** — one sentence, answerable from the fixtures you just wrote. A fixture that abbreviates away the coincidence it exists to guard (two path segments that share a name, shortened to one) looks like coverage and discriminates nothing.
- **Its environment differed.** An assertion reading ambient `PATH` / `HOME` / `TZ` / locale / git config / installed-tool state has a verdict that is a property of *who ran it* — green on the laptop, red on CI, for no defect. The fixture must set or scrub it, and each branch must be asserted against a synthesized value.
- **The load was different.** A wall-clock ceiling — asserted by the test, *or* imposed by the runner's own default timeout, which nobody wrote and nobody can see in the test body — fails under contention on out-of-process work (fs watches, `git`, CLI subprocesses). Outside the diff surface **and** green when re-run idle ⇒ an environment artifact, named as such; never a regression.

**The rule: a gate states its blind spot in the same breath as its verdict.** "Green" with no named blind spot is a claim, not a result.

**The corollary, which catches the whole class on its own:** *a negative result is evidence only if the probe could have produced a positive.* Every absence claim — zero callers, no offenders, no consumers, nothing drifted — ships with a **positive control**: something the probe must flag, run in the same breath. A detector that has never been seen to fire is not evidence of calm.

**Ask of every check whether it fails alarming or fails reassuring.** A false alarm is investigated in a minute. The identical defect in a success check — "no errors in ten minutes, therefore green" — is believed. Reassuring-failing checks are the ones that need the positive control.

## 2 — A green oracle proves the code matches the test, never that the test matches the design

RED-before-GREEN rules out a **vacuous** test. It offers no protection against a **confidently wrong** one — genuinely red first, genuinely discriminating, and encoding the wrong rule. Such a test is indistinguishable from a good one at any mechanical gate, and it is worse than no test: the next reader sees a named `describe` block asserting the wrong invariant and treats it as settled.

Two things discriminate, and only two:

- **Mutation.** Break the production line the test claims to catch, and watch it go red — reporting which assertion failed, with what values, and **which consumers** the mutation reached. A predicate claimed as single-source-of-truth should fail at least one test per declared consumer; a shortfall *is* the finding, because a second inline copy of the rule is mutation-blind. Where a slice's deliverable **is** a test or a guard there is no natural RED at all, so mutation is the only evidence available. A guard asserting an *absence* additionally needs a positive and a negative control, and if it walks a tree, its traversal pinned — or it passes by never descending.
- **An independent reader who is told what to doubt.** An executor's self-flagged deviations are the highest-value input a verifier gets, and they are free: the doubt has already been noticed and written down. Discarded at the step boundary, it is a bug report filed into a document nobody reads.

Say out loud what cannot be mutation-checked, rather than leaving it looking un-needled.

## 3 — An inherited statement is a claim with a provenance and an expiry

Ticket prose. A resolved-design block. An orchestrator directive. A sweep agent's *clean* verdict. An ADR citation. A baseline. A conflict inventory. A generated artifact. An installed build. Each arrives carrying authority, and none of it is evidence.

- **Verify the reasoning against behaviour, not the text against the text.** That a cited site still reads as quoted proves the quote, not the claim. A decision can be interview-resolved, zero-drift, perfectly-fitting prose and factually false — and zero drift makes it *worse*, because zero drift reads as nothing to check. The highest-risk kind **re-argues an existing behaviour** rather than changing anything: it ships as prose, has no test, and no oracle can fail.
- **Verify the mechanism, not only the defect.** A deferral's rationale, a stated blocker, a named mitigation, a worked example the ticket ships — each is usually one probe from being materially different than stated. Run the example; make the API call; read the cited line range. A deferral is written at the moment of least scrutiny and then inherited as though it had a design pass.
- **A uniqueness or exhaustiveness claim is a probe, never a premise.** "The only surface", "nothing else reads this", "three call sites" — grep before building on it. State what a count counts ("5 files / 7 call expressions", not "five call sites"), and quote symbols **as the source spells them**: a paraphrased identifier is indistinguishable from a real one until you grep.
- **Name the corpus you searched.** The source tree is not the shipped artifact — an installed package, a version-keyed plugin cache, a deployed build all diverge from it, and every gate in a repo reads the source. `mtime` is not provenance: a generated artifact is evidence only if you can name the commit that produced it, and siblings written in the same second can come from different producers. A directory listing shows only what reached *your* branch.
- **Every inherited fact has an expiry.** A conflict inventory dies on the next sibling merge. A pinned base moves when someone outside the run merges. A residual ticket goes stale against its own fleet's tail merges. A recorded `agentId` dies with its session. Stamp a claim with the sha, ref or moment it was computed against, and re-derive it before acting.
- **In-session behaviour is evidence about the loaded version, not about the design question.** The trap whenever this flow reasons about itself: an absence in the running session is never an argument against adding something.

When a claim survives, the useful output shape is a **falsification table** — `claim → probe run → holds / FALSE`.

## 4 — Silence generalizes

A specification's gaps get filled by whatever rule sits next to them. **An unspecified seam adjacent to a specified one is the highest-risk place in a design**, because the specified rule is exactly what will be reused there — and the two seams frequently want opposite answers. The recurring shapes: read-modify-write pairs, the client and server halves of one document, and the read and write paths over one piece of state. Completeness raises this risk rather than lowering it: the better-evidenced the document, the more confidently its rule is generalised into the gap.

So a design's job is not only to decide — it is to **name what it did not decide**, so nobody infers it.

The same silence bites at every step boundary. Each pipeline step runs in a **separate context** and `.work/` is gitignored, so whatever a step discovered, built or measured is lost at the hand-off unless it is in the doc, committed, or declared re-derivable **with the command that re-derives it**. A step may not hand off state that lives only in its own context — and this fails *worse* the better the session was, because a session that ran more spikes produced more that the doc format never asked for.

## Probe hygiene

Everything above rests on probes being trustworthy. Three ways a read-only probe returns a clean, plausible, wrong answer — all on the default macOS shell and grep, none of them machine-local:

- `--include` placed **after** the path operands: BSD `getopt` stops parsing options at the first operand, so the flag becomes a filename. Prints nothing, exits 0, nothing on stderr. Flags first.
- An **unquoted** glob flag (`--include=*.ts`): zsh expands it before `grep` sees it, and aborts the whole command.
- A `cd` inside a compound command **persists into later calls**, silently invalidating every relative path afterwards. Use absolute paths, `git -C <path>`, or a subshell — `( cd X && … )`.

None of these looks like an error, and the first fails in the reassuring direction with every ordinary tell intact — the glob quoted, the flag spelled right, the command reading perfectly. The positive control from §1 is what catches all three.
