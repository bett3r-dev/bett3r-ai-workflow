## C1 — latency budget
bar: hard
raisedBy: ticket owner · step: design
quote: "p95 must stay under 200ms"
why: a regression here breaks the SLA
verify: run the load test at /verify-build
verdict: met
evidence: load test run 42, p95=180ms

## C3 — logging (C2 was retired, id never reused)
bar: soft
raisedBy: engineer · step: build
quote: "would be nice to log the retry count"
why: eases future debugging
verify: grep the log line
verdict: met
evidence: log line present at retry.ts:12
