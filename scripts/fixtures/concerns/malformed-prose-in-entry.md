## C1 — latency budget
bar: hard
raisedBy: ticket owner · step: design
quote: "p95 must stay under 200ms"
why: a regression here breaks the SLA
The owner repeated this twice in the kickoff call.
verify: run the load test at /verify-build
verdict: met
evidence: load test run 42, p95=180ms
