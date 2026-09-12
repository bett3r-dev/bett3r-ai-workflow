## C1 — latency budget
bar: hard  # hard | soft
raisedBy: ticket owner · step: design
quote: "p95 must stay under 200ms"
why: a regression here breaks the SLA
verify: run the load test at /verify-build
verdict: unmet # met
evidence: load test run 42, p95=340ms
