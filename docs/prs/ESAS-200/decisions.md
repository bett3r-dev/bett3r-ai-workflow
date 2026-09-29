## D1 — Oracle check 3 read against the slice diff, not the branch diff
kind: deviation
step: build · slice: 1 · decidedBy: verifier
sources: [design:Testing Decisions item 3, code:git diff origin/master (docs/prs/ESAS-200/*)]
rejected: reading the branch diff literally — it also lists the design commit's docs/prs/ESAS-200 files, which are not the slice's
supersedes: —
The check `git diff --name-only origin/master...HEAD lists exactly ADR-011` was written without the design commit d7e8d5e. The slice's own diff is the ADR-011 file only; the verifier and scope-check both confirmed it.
