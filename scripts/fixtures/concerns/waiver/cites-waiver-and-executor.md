## C1 — latency budget
bar: hard
raisedBy: ticket owner · step: design
quote: "p95 must stay under 200ms"
why: a regression here breaks the SLA
verify: run the load test at /verify-build
verdict: waived
evidence: decisions.md#D2 and decisions.md#D3
