# Post-design decisions — GH-429

Every decision made after the design was resolved. Append-only; ids are never reused.

## D1 — The uniqueness guard's needle moved from the `LANE-STEP:v(` literal to the marker-independent attribute clause
kind: deviation
step: build · slice: 1 · decidedBy: executor
sources: [code:lane_token_needle (scripts/test-flow-seams.sh), code:token (plugins/bett3r-ai-workflow/scripts/lane-step-parse.py), design:Scenarios/still one parser, human]
rejected: keep the literal needle — it was ALREADY RED at base (d04a3cd's docs/prs/GH-429/design.md:46, map.json:196 and map.html quote the regex verbatim), and after parameterisation the literal no longer occurs in the parser at all, so it would have become a guard over the empty set that passes silently
supersedes: —
Slice 1's structural scenario spelled the needle as a literal. The verifier independently reproduced the base-red state with `git archive d04a3cd` and confirmed both halves of the executor's claim, then mutation-checked the replacement: the new needle matches the production parser (positive control), catches a `FLEET-STEP` copy the old literal could not, and no longer matches a document that merely quotes the rule. Residual weakening, accepted: a second parser spelling a looser attribute clause would now escape. The gate "must stay green" is honoured in substance, not by the letter of the needle.

## D2 — The marker surface is a `--marker NAME` flag, not an env var or a second positional
kind: silent-seam
step: build · slice: 1 · decidedBy: executor
sources: [code:main (plugins/bett3r-ai-workflow/bin/lane-step), design:Behavior]
rejected: an env var (invisible at the call site) — a second positional (collides with the existing single-path contract)
supersedes: —
The slice said "asking for the FLEET-STEP marker" without naming a surface. A flag keeps the default path byte-identical for the five shipped callers, and the default is test-pinned: flipping `DEFAULT_MARKER` to `FLEET-STEP` reds ten assertions.

## D3 — A lone `--marker` with no value exits 2 rather than dying in a traceback
kind: silent-seam
step: build · slice: 1 · decidedBy: executor
sources: [code:main (plugins/bett3r-ai-workflow/scripts/lane-step-parse.py)]
rejected: treat it as a path — a traceback reads to a caller as `infra` rather than as its own usage error
supersedes: —
Unspecified by the slice. Shipped unasserted; recorded as D3 and as finding F4 below rather than pretending a test covers it.

## D4 — The FLEET trailing-prose assertion is shipped without a mutation that reds it alone
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:scripts/test-flow-seams.sh:626-635, code:scripts/fixtures/lane-step/README.md:86-90]
rejected: another fix round to make it independently load-bearing — the clause it guards is now provably shared (one `token()`, one `.match()`, one `\s*$`), and the pre-existing default-marker fixture reds under the same mutation
supersedes: —
Its comment claims it catches a parameterisation that loses a clause for every marker but the default; no mutation reds it alone, so that sentence is aspirational. Either soften it or name the divergence it uniquely kills.

## D5 — docs/prs/GH-429/design.md still cites a surface the slice removed
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:docs/prs/GH-429/design.md:46, code:docs/prs/GH-429/design.md:242]
rejected: amending the design doc inside slice 1 — out of the slice's touches, and the design is the committed record of what was decided, not of what shipped
supersedes: —
`:46` cites `TOKEN = re.compile(…)` at `lane-step-parse.py:64` and `:242` cites `sed -n '60,67p'` as the evidence that the marker is hardcoded. `TOKEN` no longer exists. Worth a one-line amendment in a later slice — and `:46` is the very text that made the old guard needle unusable (D1).

## D6 — The gate's `flow-seams` surface does not list the paths slices 2 and 3 touch
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:.claude/gate.sh:194]
rejected: widening the surface inside slice 1 — .claude/gate.sh is not in slice 1's touches; slice 2 already owns that file
supersedes: —
Pre-existing, not created here. `flow-seams` is scoped to `commands/*`, `agents/*`, `skills/*`, `docs/adr/*` and `scripts/test-flow-seams.sh`, but not to `plugins/bett3r-ai-workflow/scripts/*`, `bin/*` or `scripts/fixtures/lane-step/*`. Slice 1's suite ran only because it edited the test file; a future diff touching `lane-step-parse.py` alone would print `SKIP` for the only suite guarding it. Carried into slice 2, which edits `.claude/gate.sh`.
