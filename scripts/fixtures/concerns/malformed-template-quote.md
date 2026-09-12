## C1 — latency budget
bar: hard
raisedBy: ticket owner · step: design
quote: "<verbatim>"
why: a regression here breaks the SLA
verify: run the load test at /verify-build
verdict: met
evidence: load test run 42, p95=180ms
