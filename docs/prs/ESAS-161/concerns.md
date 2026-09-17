## C1 — A fork-count mismatch stops the render
bar: hard
raisedBy: ticket owner · step: design
quote: "The renderer prints the fork count it rendered next to the draft's own count, and a mismatch stops the step. The risk here is a fork silently dropped and then accepted under \"not answered = agree\"."
why: The page's own rule is that a fork left unanswered is taken on its recommendation, so a fork missing from the page is accepted without the owner ever seeing it, and nothing downstream can tell a dropped fork from an agreed one.
verify: Run the design-map render with a fixture whose map.json holds fewer forks than the expected draft count; confirm the verdict line reports both counts, outcome is not ok, and no artifact HTML is left for publishing. Then confirm the matching-count case reports both counts and succeeds.
verdict: met
evidence: `design-map render scripts/fixtures/design-map/impact-map-11-forks.json --expect 12` → `outcome=error reason=count-mismatch expected=12 payload=11` and no file at --out (ls: No such file); --expect 11 → `outcome=ok expected=11 payload=11 rendered=11`; page-missing-forks and missing-expect covered by scripts/test-design-map.sh (149 passed under sh, dash and bash, 2026-09-16).

## C2 — Map payloads never carry a bare actor
bar: hard
raisedBy: ticket owner · step: design
quote: "The schema is committed and versioned. Map payloads spell the who-level `mapActor`, never a bare `actor`."
why: In ESAS an actor is who wrote an op (ActorId); a map's who-level is a role. A bare `actor` field lets the two be joined by accident once the board reads the same payloads (esas CONTEXT.md "Actor (map)").
verify: Confirm the committed schema names the who-level node `mapActor` and carries a schema version; run the validator on a fixture containing a bare `actor` key anywhere in the payload and confirm it is refused.
verdict: met
evidence: map.schema.json:7,10,14 — `schemaVersion` required with const 1, who-level is `mapActors`; `render scripts/fixtures/design-map/bare-actor.json` → `outcome=error reason=bare-actor at=/forks/1/options/0/actor`; refusal runs before the schema (design-map.py:274-276); test-design-map.sh green.
