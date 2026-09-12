## C1 — data migration reversible
bar: hard
raisedBy: ticket owner · step: design
quote: "the migration must be reversible"
why: a bad rollout must not strand data
verify: run the down-migration in staging
verdict: partial
evidence: down-migration exists but untested against production-sized data
