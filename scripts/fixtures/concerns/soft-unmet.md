## C1 — latency budget
bar: hard
raisedBy: ticket owner · step: design
quote: "p95 must stay under 200ms"
why: a regression here breaks the SLA
verify: run the load test at /verify-build
verdict: met
evidence: load test run 42, p95=180ms

## C2 — nice-to-have logging
bar: soft
raisedBy: engineer · step: build
quote: "would be nice to log the retry count"
why: eases future debugging
verify: grep the log line
verdict: unmet
evidence: no such log line was added
