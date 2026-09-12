## C1 — The PR body stays short and links to the committed files
bar: hard
raisedBy: ticket owner (XL-27 reporter) · step: build
quote: "Do not bloat the PR body. The operator wants the structure back in files, not a longer description."
why: The unit exists to move per-work-item knowledge back into committed files; a PR body that re-grows the design narrative duplicates them and brings back the failure the ticket measured.
verify: /verify-build Step 6's PR-body template is a short summary plus a Record section linking design.md, decisions.md, concerns.md and build-summary.md, with no promoted design narrative; this PR's own body follows it.
verdict: —
evidence: —

## C2 — Durable decisions still go to ADRs
bar: hard
raisedBy: ticket owner (XL-27 reporter) · step: build
quote: "Keep the plugin's promotion discipline: durable decisions still go to ADRs. The build summary sits between design and ADR; it does not replace the ADR."
why: build-summary.md and decisions.md are per-work-item records; if they absorbed decisions that outlive the ticket, the ADR log would stop being the durable record.
verify: verify-build.md Step 5 still requires owed ADRs to be written before the PR opens; this unit ships ADR-005 (slice 8); no command or skill text says build-summary.md or decisions.md replaces an ADR.
verdict: —
evidence: —

## C3 — Concerns keep speaker attribution and are checked at landing
bar: soft
raisedBy: ticket owner (XL-27 reporter) · step: build
quote: "Keep the _Raised by_ + quote + how-to-verify shape, and keep `/verify-build` checking each one."
why: Speaker attribution plus owner authority is what the knowledge store cannot otherwise express; a concern that is captured but never checked at landing is noise.
verify: The concern skill's C-entry carries raisedBy, quote and verify; /verify-build Step 5a rules every entry with evidence and runs concerns-check --decisions before the PR opens.
verdict: —
evidence: —
