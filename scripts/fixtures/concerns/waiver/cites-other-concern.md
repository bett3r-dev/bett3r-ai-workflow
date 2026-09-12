## C1 — latency budget
bar: soft
raisedBy: ticket owner · step: design
quote: "p95 should stay under 200ms"
why: a regression here hurts the SLA
verify: run the load test at /verify-build
verdict: met
evidence: load test p95 = 170ms (scripts/load.sh)

## C2 — no data loss on restart
bar: hard
raisedBy: ticket owner · step: design
quote: "a restart must never lose a write"
why: writes are customer data
verify: run the crash-restart test at /verify-build
verdict: waived
evidence: owner waiver recorded as decisions.md#D2
