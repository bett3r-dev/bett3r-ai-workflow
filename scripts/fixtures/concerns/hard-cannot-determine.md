## C1 — no PII in logs
bar: hard
raisedBy: ticket owner · step: design
quote: "nothing personally identifiable may reach the logs"
why: compliance requirement
verify: grep the log output for known PII fields
verdict: cannot-determine
evidence: the log sink is a third-party service the verifier cannot inspect
