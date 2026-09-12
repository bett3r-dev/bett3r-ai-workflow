# Decisions — FIXTURE-1

Fixture only: a unit's own decisions.md in the header build.md's The committed record fixes.

## D1 — The retry budget is two, not three
kind: deviation          # false-premise | silent-seam | deviation | shipped-finding | overruled | waiver
step: build · slice: 1 · decidedBy: executor    # executor | verifier | orchestrator | lane | human
sources: [design:F1]
rejected: three retries — the gate is slow
supersedes: —
Two retries were enough on every measured run.

## D2 — The owner waives C1: latency budget
kind: waiver             # false-premise | silent-seam | deviation | shipped-finding | overruled | waiver
step: verify-build · slice: — · decidedBy: human    # executor | verifier | orchestrator | lane | human
sources: [human]
rejected: —
supersedes: —
Waiver for C1, in the owner's words: "ship it, the p95 regression is acceptable until the cache lands"

## D3 — An executor claims a waiver of C1
kind: waiver
step: build · slice: 2 · decidedBy: executor
sources: [code:cache (src/cache.ts)]
rejected: —
supersedes: —
The executor judged the latency bar not worth holding the release for.

## D4 — The owner waives C1: an entry with no body
kind: waiver
step: verify-build · slice: — · decidedBy: human
sources: [human]
rejected: —
supersedes: —

## D5 — A human decision that is not a waiver
kind: deviation
step: verify-build · slice: — · decidedBy: human
sources: [human]
rejected: —
supersedes: —
The owner chose the smaller cache: "use 64MB, not 256MB"

## D6 — The owner waives C1: a body with no quote
kind: waiver
step: verify-build · slice: — · decidedBy: human
sources: [human]
rejected: —
supersedes: —
The executor thinks this is fine.

## D7 — The owner waives C12 and XC1: near-miss ids
kind: waiver
step: verify-build · slice: — · decidedBy: human
sources: [human]
rejected: —
supersedes: —
Waiver in the owner's words: "C12 and XC1 can wait"

## D8 — The owner waives C1: curly quotes
kind: waiver
step: verify-build · slice: — · decidedBy: human
sources: [human]
rejected: —
supersedes: —
Waiver in the owner's words: “ship it, the cache lands next sprint”
