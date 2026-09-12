## C1 — The PR body stays short and links to the committed files
bar: hard
raisedBy: ticket owner (XL-27 reporter) · step: build
quote: "Do not bloat the PR body. The operator wants the structure back in files, not a longer description."
why: The unit exists to move per-work-item knowledge back into committed files; a PR body that re-grows the design narrative duplicates them and brings back the failure the ticket measured.
verify: /verify-build Step 6's PR-body template is a short summary plus a Record section linking design.md, decisions.md, concerns.md and build-summary.md, with no promoted design narrative; this PR's own body follows it.
verdict: met
evidence: plugins/bett3r-ai-workflow/commands/verify-build.md:200-212 — the template is "a short summary plus links to the committed record", a "two to four sentences … a summary, not the design" lead and a Record section linking all four files; Step 5 line 107 says the design narrative is not copied into the body. This PR's body was written to that template before ruling: one summary paragraph, the four Record links, Slices, Verification, Decisions, Coherence review — no design narrative (the 465-line design.md is linked, not restated).

## C2 — Durable decisions still go to ADRs
bar: hard
raisedBy: ticket owner (XL-27 reporter) · step: build
quote: "Keep the plugin's promotion discipline: durable decisions still go to ADRs. The build summary sits between design and ADR; it does not replace the ADR."
why: build-summary.md and decisions.md are per-work-item records; if they absorbed decisions that outlive the ticket, the ADR log would stop being the durable record.
verify: verify-build.md Step 5 still requires owed ADRs to be written before the PR opens; this unit ships ADR-005 (slice 8); no command or skill text says build-summary.md or decisions.md replaces an ADR.
verdict: met
evidence: verify-build.md:100 still requires an owed ADR "written BEFORE the PR is opened, never filed as a follow-up", and its Principles (line 289) say "put decisions that outlive this work item in ADRs"; the plugin README Core principle says "ADRs still own the durable decisions that outlive a work item". ADR-005 is committed (67e8a5d) and unique across every ref (git log --all --name-only | grep -oE 'ADR-[0-9]+' → highest ADR-005, none on origin/master). grep -rniE for build-summary/decisions.md "replac|instead of|in place of … ADR" over plugins/, docs/adr and README returned no hits.

## C3 — Concerns keep speaker attribution and are checked at landing
bar: soft
raisedBy: ticket owner (XL-27 reporter) · step: build
quote: "Keep the _Raised by_ + quote + how-to-verify shape, and keep `/verify-build` checking each one."
why: Speaker attribution plus owner authority is what the knowledge store cannot otherwise express; a concern that is captured but never checked at landing is noise.
verify: The concern skill's C-entry carries raisedBy, quote and verify; /verify-build Step 5a rules every entry with evidence and runs concerns-check --decisions before the PR opens.
verdict: met
evidence: skills/concern/SKILL.md:22-26 fixes the C-entry shape with raisedBy, quote and verify, and line 35 keeps quote as the verbatim raising quote; verify-build.md Step 5a rules every entry with evidence and runs concerns-check --decisions (line 134). This ruling is that step's first live run: all three entries ruled with evidence, checked with concerns-check --decisions against this folder before the PR opened. Local gate: merge-multi-concerns 86 passed, flow-seams 383 passed.
