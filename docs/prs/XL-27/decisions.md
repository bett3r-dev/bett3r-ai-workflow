# Decisions — XL-27

Post-design decisions for XL-27, append-only, in the header `/build` specifies
(`commands/build.md`, *The committed record*). The design as resolved is `design.md`
in this folder; every entry below is a place the build departed from it, filled a
seam it left silent, found a premise false, or knowingly shipped a finding.

## D1 — The version bump is 0.67.0 → 0.68.0, not the design's 0.65.0 → 0.66.0
kind: false-premise
step: plan · slice: — · decidedBy: orchestrator
sources: [code:version (plugins/bett3r-ai-workflow/.claude-plugin/plugin.json), adr:ADR-001, design:Resolved without a fork]
rejected: bump to 0.66.0 as designed — origin/master was already 0.67.0, so it would be a downgrade
supersedes: —
The design was grounded on a base where the plugin was 0.65.0; by plan time master
had shipped 0.67.0. ADR-001 still asks for a minor bump because the payload changes, so
the target moved one minor up. It landed in slice 1 so the version gate is green on
every commit of the PR.

## D2 — "decisions.md written once" is proven in slice 3, not by the tracer bullet
kind: deviation
step: plan · slice: 1 · decidedBy: orchestrator
sources: [design:R2, design:F6]
rejected: prove it in slice 1 as R2 states — decisions.md does not exist until slice 3 introduces it
supersedes: —
R2's tracer bullet listed "decisions.md written once" among its proofs. Slice 1 proved
the single-writer rule on the file that exists then — slices.yaml recording landed
shas — and slice 3 extends the same rule to decisions.md and build-summary.md.

## D3 — The work-docs root and id rule is one script, bin/work-docs-path
kind: deviation
step: plan · slice: 2 · decidedBy: human
sources: [design:F7, code:main (plugins/bett3r-ai-workflow/scripts/work-docs-path.py), code:bin/resolved-marker-lint, human]
rejected: restate F7's root/id table in every command that reads the design — ten prose copies of one rule drift apart
supersedes: —
F7 fixes the rule but names no mechanism. The operator approved a tested script at plan
review, following the bin/resolved-marker-lint launcher precedent; every command calls it
instead of restating the table. Slice 2's verifier recorded it again as an
operator-approved deviation.

## D4 — The build branch is cut from master after PR #344 merged
kind: deviation
step: build · slice: — · decidedBy: orchestrator
sources: [code:branch (.work/slices.yaml), human]
rejected: build on the plan-time branch — it merged to master as PR #344 at 12:24, so its commits are already on master
supersedes: —
xl-27/committed-work-record was cut from master 242c321, which contains the plan-time
base f2fa61e and the design's e6283b7, so nothing the plan was grounded on is missing.

## D5 — provision only cuts worktrees; install and build run in reset, before every take
kind: deviation
step: build · slice: 1 · decidedBy: executor
sources: [code:cmd_provision (plugins/bett3r-ai-workflow/scripts/worktree-pool.py), code:cmd_reset (plugins/bett3r-ai-workflow/scripts/worktree-pool.py), design:F6]
rejected: provision also installs and builds and the first reset skips them — that makes reset conditional, against remote-ai-agents D6
supersedes: —
The design lists install and build under both provisioning and reset. Keeping them only in
the unconditional reset means one code path for a warm tree and a cold one. The accepted
cost is that a slice's first take can pay for install and build twice: once when the
provisioner prepares the worktree, and again in the reset.

## D6 — land requires --base, the tip of that worktree's last reset
kind: deviation
step: build · slice: 1 · decidedBy: executor
sources: [code:cmd_land (plugins/bett3r-ai-workflow/scripts/worktree-pool.py), design:F6]
rejected: land any sha the worktree holds — a commit from before its last reset could land as this slice's
supersedes: —
Only a sha strictly after the reset tip can be this slice's commit. The design's land
takes a worktree and a sha. The base is what lets the script refuse a stale or foreign
commit (reason=sha-not-after-base) instead of landing it.

## D7 — size --only with a pending parent outside the set is an error
kind: deviation
step: build · slice: 1 · decidedBy: executor
sources: [code:dag_width (plugins/bett3r-ai-workflow/scripts/worktree-pool.py), code:cmd_size (plugins/bett3r-ai-workflow/scripts/worktree-pool.py), design:F6]
rejected: size the targeted slices anyway — the child would be built on a branch without its parent
supersedes: —
A targeted run whose slice has a parent that is neither passed nor targeted gets
reason=unmet-dependency-outside-only, and /build asks for the parent to be included.

## D8 — A worktree whose slice did not land is retired until teardown; a re-land reads as landed
kind: silent-seam
step: build · slice: 1 · decidedBy: executor
sources: [design:F6, code:cmd_land (plugins/bett3r-ai-workflow/scripts/worktree-pool.py), code:cmd_teardown (plugins/bett3r-ai-workflow/scripts/worktree-pool.py)]
rejected: reset the worktree for the next slice — the reset's switch and clean -fd would erase an escalated slice's uncommitted files
supersedes: —
F6 says a cherry-pick conflict escalates but not what happens to the worktree afterwards,
or to a crash between a land and its record. Retry 1, classified design-silent, filled
both. The worktree takes no further slice, teardown's refusal keeps its work on disk for a
human, and a land whose change is already on the branch reports already=true.

## D9 — On resume, provision refuses a worktree that still holds work
kind: silent-seam
step: build · slice: 1 · decidedBy: executor
sources: [design:Unspecified seams, code:cmd_provision (plugins/bett3r-ai-workflow/scripts/worktree-pool.py), code:unlanded (plugins/bett3r-ai-workflow/scripts/worktree-pool.py)]
rejected: reuse or recreate a previous run's worktree on resume — either discards an escalated slice's files or an unlanded commit
supersedes: —
The design deliberately leaves pool re-provisioning on resume unspecified ("beyond reset
before use"). Retry 2, classified design-silent, filled it. provision answers
reason=reused-worktree-holds-work, and /build runs that invocation without a pool and names
the held path for a human.

## D10 — P1: a stale --base after reuse cycles can report a false already=true
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:cmd_land (plugins/bett3r-ai-workflow/scripts/worktree-pool.py), code:landed_equivalent (plugins/bett3r-ai-workflow/scripts/worktree-pool.py)]
rejected: fix it before landing slice 1 — verifier PASS carried it; fix candidates are land requiring sha^ == base, or build.md forbidding the tip= from provision or a first reset as --base
supersedes: —
This is the one carried finding that can write a wrong record. If the orchestrator passes
a --base older than the worktree's last reset, a sha from an earlier cycle can read as
already landed. The slice would then get passes: true with a sha that is not its
work.

Slice 3 widens it. The slice-3 verifier simulated this with the real worktree-pool.py.
Slice A lands, a docs(record) commit follows, a worktree resets, and no worker commit
is made. Passing the previous land's sha as --base now reads landed already=true, with
the record commit's sha: a false pass. Without the record commit, the same mistake was
refused as sha-not-after-base. The correct --base (the reset tip) still refuses both.
The candidate fix, land requiring sha^ == base, closes both cases.

## D11 — P2, P10: the already=true path is mostly unreachable, and an identical-patch sibling triggers it
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:landed_equivalent (plugins/bett3r-ai-workflow/scripts/worktree-pool.py), code:build.md Step 2 step 5 (plugins/bett3r-ai-workflow/commands/build.md)]
rejected: remove or rework the resume re-land reading in slice 1 — it fails safe by escalating
supersedes: —
P2: build.md's "resumed run re-landing" reading is effectively unreachable. The worker's
tip is lost, and a resumed run resets first. P10: a sibling slice whose patch is
identical reads as already=true, because landed_equivalent compares patch ids.

## D12 — P3, P4: refusals report incompletely
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:cmd_provision (plugins/bett3r-ai-workflow/scripts/worktree-pool.py), code:cmd_teardown (plugins/bett3r-ai-workflow/scripts/worktree-pool.py)]
rejected: report every held worktree and remove clean siblings in slice 1 — a refusal still stops safely, it just says less
supersedes: —
P3: provision names only the first held worktree. P4: a teardown refusal leaves the clean
sibling worktrees in place along with the held one.

## D13 — P5: --base given as a branch name falsely refuses a same-sha landed slice
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:cmd_land (plugins/bett3r-ai-workflow/scripts/worktree-pool.py)]
rejected: accept a branch name for --base — build.md passes the reset verdict's tip= sha, and refusing is the conservative direction
supersedes: —
The refusal is not documented. It errs toward not landing, never toward a wrong land.

## D14 — P6, P9, P11, P12: worktree-pool suite gaps
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:dag_width (plugins/bett3r-ai-workflow/scripts/worktree-pool.py), code:landed_equivalent (plugins/bett3r-ai-workflow/scripts/worktree-pool.py), code:scripts/test-worktree-pool.sh]
rejected: add the cases in slice 1 — the gated behaviour is covered, and these are its edges
supersedes: —
Untested: P6, a size DAG that separates transitive ancestors from direct depends_on (the
bow-tie a,b→c→d,e). P9, the newest-equivalent-commit ordering. P11, the empty pick with no
equivalent commit. P12, reason-specific assertions for the size errors other than those
the suite names.

## D15 — P7, P8: two pool guarantees rest on build.md prose alone
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:build.md Step 2 (plugins/bett3r-ai-workflow/commands/build.md), code:scripts/test-flow-seams.sh]
rejected: pin them in slice 1 — agent choice is the residual gate-less seam R2 names
supersedes: —
P7: no flow-seams needles pin reused-worktree-holds-work, sha-not-after-base or --base in
build.md. P8: within a run, an escalated slice's untracked files are safe only because
build.md tells the orchestrator to retire the worktree, and nothing executes that.

## D16 — P13: the scaffolder's --design/--graph flags are unverified from a pool worktree
kind: shipped-finding
step: build · slice: 1 · decidedBy: verifier
sources: [code:build.md Step 3 step 0 (plugins/bett3r-ai-workflow/commands/build.md)]
rejected: verify against a PV3 scaffolder in slice 1 — this repo ships no design layer or scaffolder
supersedes: —
build.md tells a pool slice to run the scaffolder from the worktree with --design/--graph
pointed at the main checkout's .esas files. This repo cannot exercise that call.

## D17 — A workDocsRoot inside .work/ is refused
kind: deviation
step: build · slice: 2 · decidedBy: executor
sources: [code:work_docs_root (plugins/bett3r-ai-workflow/scripts/work-docs-path.py), design:F1, design:F7]
rejected: accept any configured root — a root under the gitignored .work/ recreates the uncommitted copy F1 removes
supersedes: —
An executor addition the design did not list. The script answers outcome=error instead
of naming a folder no commit can hold.

## D18 — No-id folder ownership decided from git history (fork point + git log)
kind: silent-seam
step: build · slice: 2 · decidedBy: executor
sources: [design:F7, code:scripts/test-flow-seams.sh]
rejected: overwrite any existing <date>-<slug> folder — a second work item with the same slug would overwrite the first
supersedes: —
F7 gives a no-id item a <date>-<slug> folder but says nothing about a folder that already
exists. Retry 1, classified design-silent, filled the seam by deciding ownership from
merge-base plus git log. Retry 2, classified oracle-wrong, fixed a seam test pinned to a
stale known-baseline base. The verifier then escalated: git history falsely claimed
another work item's folder in stacked, merged-feature and stale-origin topologies.

## D19 — Q1: the work-docs census is token-shaped
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:scripts/test-flow-seams.sh]
rejected: parse call shapes in slice 2 — the census still catches a deleted reference and a literal fallback path
supersedes: —
The positive census accepts the token work-docs-path anywhere, so a prose-only mention
passes. The negative census matches the literal old path only, so a reworded fallback
passes.

## D20 — Q2, Q12: work-docs-path test gaps
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:work_docs_root (plugins/bett3r-ai-workflow/scripts/work-docs-path.py), code:normalise_item (plugins/bett3r-ai-workflow/scripts/work-docs-path.py), code:scripts/test-work-docs-path.sh]
rejected: add the fixtures and pin CI's python in slice 2 — the documented cases are covered
supersedes: —
Q2: untested are a dangling-symlink config (a lexists→exists mutant survives), #0 and
gh-0268, and a file rather than a folder named <date>-<slug>. Q12: CI's python is
unpinned, and the --date 20260912 test is blind on Python 3.10, where fromisoformat
already refuses the value.

## D21 — Q3, Q4: roots and repos the script accepts without complaint
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:work_docs_root (plugins/bett3r-ai-workflow/scripts/work-docs-path.py), code:repo_root (plugins/bett3r-ai-workflow/scripts/work-docs-path.py)]
rejected: refuse them in slice 2 — git add refuses the bad root later, and no command passes --repo
supersedes: —
Q3: a root under .git/, or a gitignored one (.WORK/x on a case-insensitive filesystem), is
accepted. Q4: --repo pointing at a directory that is not a repository returns ok with the
default root.

## D22 — Q5: handon opens a legacy .work design cited by a pre-0.68 handoff
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:skills/handon/SKILL.md, design:C3]
rejected: special-case legacy handoffs — the operator ruled out any fallback reader of the old path (C3)
supersedes: —
A handoff written before 0.68.0 cites the old gitignored path, and handon opens it as if it
were the design.

## D23 — Q6: workItem (design F3) vs work_item (mode.yaml) naming drift
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [design:F3, code:commands/start.md]
rejected: settle it in slice 2 — build-summary.md is written in slice 3
supersedes: —
The design's build-summary frontmatter spells workItem. The marker and the ownership
header spell work_item. The choice was deferred to the slice that writes the file.

## D24 — Q7: the ADR-003 flow-seams check pins a source literal
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:scripts/test-flow-seams.sh, adr:ADR-003]
rejected: a behaviour fixture in slice 2 — the literal check is red on the regression it names
supersedes: —
A behaviour fixture — a config under .esas.config.json that must be ignored — would be
sturdier than grepping the script for the config path.

## D25 — Q8, Q9: start.md's no-id slug derivation has unspecified edges
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:commands/start.md, code:normalise_item (plugins/bett3r-ai-workflow/scripts/work-docs-path.py)]
rejected: specify every edge in slice 2 — an empty slug already fails loud as malformed at /design
supersedes: —
Q8: an empty derived slug (a branch ending in /, or with no alphanumerics) is
unspecified; start.md now says to ask the user. Q9: derivation drops non-ASCII letters
(ünïcode → n-code), and a branch named main becomes the slug main.

## D26 — Q10: known-baseline-failures.md has no parseable format
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:commands/start.md]
rejected: specify a format in slice 2 — nothing in this unit parses the file
supersedes: —
start.md tells /start to write the base sha and branch, but in no fixed shape.

## D27 — Q11: a stacked branch's parent folder can count as owned
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:ownership (plugins/bett3r-ai-workflow/scripts/work-docs-path.py)]
rejected: fix it inside the merge-base rule — the rule itself was escalated
supersedes: —
Under the merge-base rule, a parent feature branch's dated folder with the same slug read
as owned by the stacked child. The finding was correct against that rule. D29 replaced
the rule, which makes the finding moot rather than wrong, so this entry is not superseded.

## D28 — Q13, Q15: git-history ownership edge cases
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:ownership (plugins/bett3r-ai-workflow/scripts/work-docs-path.py)]
rejected: harden the merge-base path — it was being replaced by recorded ownership
supersedes: —
Q13: a merge-base failure was safe only by accident. Q15: a missing origin/HEAD blocked
no-id re-runs. Both depend on consulting git history, so both are moot once it is no
longer consulted (D29). They were correct findings, made moot rather than overturned,
so this entry is not superseded.

## D29 — Ownership of a design folder is recorded in the design's header, never inferred from git history
kind: deviation
step: build · slice: 2 · decidedBy: human
sources: [code:header_fields (plugins/bett3r-ai-workflow/scripts/work-docs-path.py), code:ownership (plugins/bett3r-ai-workflow/scripts/work-docs-path.py), design:F7, human]
rejected: git-history ownership (fork point + git log) — cannot tell who wrote a folder; never overwrite slug folders — ambiguous slug for readers; require an id — reverses F7 row 3; accept and document — leaves a false overwrite
supersedes: D18
Human decision, 2026-09-12 13:58 -03, after the slice-2 escalation. design.md carries a
work_item + branch header, and work-docs-path decides owner=none|self|other|unowned from
it. /design writes only on none or self. Accepted cost: a renamed branch is a false stop.

## D30 — Q14: an interrupted own pass false-stops on re-run
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:ownership (plugins/bett3r-ai-workflow/scripts/work-docs-path.py)]
rejected: infer ownership of a headerless folder — that reintroduces a guess the header exists to remove
supersedes: —
A /design pass interrupted before its header was written leaves a folder that reads
unowned, so the next pass stops. It fails safe.

## D31 — R1: the ownership header parser is lenient
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:header_fields (plugins/bett3r-ai-workflow/scripts/work-docs-path.py)]
rejected: a strict frontmatter parser in slice 2 — /design writes the header itself, in the documented shape
supersedes: —
An indented --- opener is accepted, a nested indented key is read as top-level, and
branch: > is taken literally. A BOM makes the design read unowned, but nothing pins it (a
strip-BOM mutation survives).

## D32 — R2, R3, R4: --owner-branch value edges
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:owner_branch (plugins/bett3r-ai-workflow/scripts/work-docs-path.py), code:commands/design.md Step 4]
rejected: special-case them in slice 2 — each one stops, never overwrites
supersedes: —
R2: in --owner-branch --slug, the --slug is taken as the branch value. git forbids a
leading -, so this is theoretical. R3: an unquoted empty --owner-branch $(…) on a
detached HEAD answers missing-value-owner-branch, which Step 4 does not list, but it
still stops. R4: a reader who copies the owner call "exactly as Step 4" false-stops on a
detached HEAD.

## D33 — R5: frontmatter copied verbatim into a PR body renders as a rule and a heading
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:commands/design.md Step 4]
rejected: change the header shape for PR rendering — the header is for the script, and the effect is cosmetic
supersedes: —
Copied into a PR body, the --- lines render as a horizontal rule and the key lines as a
heading.

## D34 — R6: #<n> in mode.yaml is a YAML comment, so a GitHub-issue item false-stops
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:commands/start.md, code:normalise_item (plugins/bett3r-ai-workflow/scripts/work-docs-path.py)]
rejected: change the #<n> spelling in slice 2 — the gap is in the marker spec, and it fails safe
supersedes: —
An unquoted work_item: #268 parses as an empty value. Every pass then reads unowned and
stops. The defect was already in the spec; this unit made it visible.

## D35 — R7: a flow-seams needle starting with - would read as a grep option
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:scripts/test-flow-seams.sh]
rejected: rewrite every loop in slice 2 — no current needle starts with -
supersedes: —
In the refute loops that run `if grep -qF "$old"`, a needle starting with - makes grep
exit 2, and the if reads that as not found, which is a false green. New loops pass -e.

## D36 — A no-id work item is dated once at /start, and resolved to that exact folder
kind: deviation
step: build · slice: 2 · decidedBy: human
sources: [code:normalise_item (plugins/bett3r-ai-workflow/scripts/work-docs-path.py), code:commands/start.md, design:F7, human]
rejected: a per-start token in mode.yaml — a fifth marker field three commands must preserve on every full rewrite; accept as a named residual — leaves a false overwrite of an unrelated design
supersedes: —
Human decision, 2026-09-12 14:18 -03, after the second escalation. A branch name reused on
a later day derived the same slug, the lookup found the old dated folder, the header
matched, and an unrelated design was overwritten. The fix: work_item = <yyyy-mm-dd>-<slug>
is fixed at /start and carried unchanged by every command, writers never reuse a folder by
lookup, and the header's work_item is the dated id. Step 4's outcome→action map is now
parsed and asserted rather than presence-checked. Accepted residual: the same branch name
deleted and recreated on the same day. This amends D29's header rather than removing it.

## D37 — S1: Step 4's outcome→action classifier is lexical
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:scripts/test-flow-seams.sh]
rejected: tighten the verb lists further — a prose guard cannot close this fully (known limit)
supersedes: —
Three rewordings survive. X4: "replace design.md in place…; end blocked-on only if the
commit fails". X8: "never end blocked-on here; take the folder over". X7: an Exception
paragraph outside the bullet list. A tighter classifier would require Write nothing plus
end blocked-on for a stop, refuse never/only if/unless near blocked-on, and count
replace/take over/adopt/continue/proceed as write verbs.

## D38 — S2: the migration remedy for an undated in-flight work item is unstated
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:commands/design.md Step 4]
rejected: an automatic migration — re-dating is exactly what the dated-work-item decision forbids
supersedes: —
An in-flight branch with an undated slug work_item answers malformed-item, and a legacy
header answers other. Step 4 names the reason but not the fix, which is to set work_item
to <start date>-<slug>.

## D39 — S3: critique and handon say "the current work item" without naming .work/mode.yaml
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:skills/critique/SKILL.md, code:skills/handon/SKILL.md]
rejected: reword them in slice 2 — both call work-docs-path exactly as /design Step 4 does, which names the marker
supersedes: —
critique/SKILL.md:26 and handon do not say where the work item is read from.

## D40 — T1, T2: carry-forward wording gaps in plan.md, build.md and design.md
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:commands/plan.md, code:commands/build.md Step 1, code:commands/design.md]
rejected: reword in slice 2 — the gap is literal only; the rule is stated and seam-checked
supersedes: —
T1: plan.md:22 and build.md:22 say "before reading anything else", yet also "read it from
the existing mode.yaml before the rewrite"; they could add "(other than that old marker)".
T2: design.md:42 lacks the read-before-rewrite clause that plan and build carry. The
dated run's ripple retry was this rule missing from plan.md and build.md.

## D41 — T3: the carry-forward seam loop is presence-only
kind: shipped-finding
step: build · slice: 2 · decidedBy: verifier
sources: [code:scripts/test-flow-seams.sh]
rejected: execute it in the seam suite — reading before overwriting is agent behaviour, an eval, not a text seam
supersedes: —
The loop checks that each command states the rule, not that an agent follows it.

## D42 — build-summary.md's frontmatter spells work_item:, not the design's workItem:
kind: deviation
step: build · slice: 3 · decidedBy: executor
sources: [design:F3, code:commands/start.md, code:commands/design.md Step 4, code:commands/build.md]
rejected: workItem: as F3's example spells it — a third spelling of one field beside the marker and the ownership header
supersedes: D23
.work/mode.yaml and design.md's ownership header both spell work_item, and the value is
the same value carried forward. build.md's build-summary block uses work_item: and says
so.

## D43 — Grammar gaps filled in the D-entry header
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [design:F2, code:scripts/test-flow-seams.sh, code:commands/build.md]
rejected: hold decisions.md to F2's example comments alone — they leave plan-wide decisions, multi-entry overturns and no-alternative decisions with no legal spelling
supersedes: —
F2's example leaves five things open, and build.md and Seam I now fix them. slice: — marks a
decision about the plan as a whole. supersedes: takes one or more earlier ids (D3, D5).
rejected: — marks a decision with no alternative. step is a lowercase step name. A
decisions.md with no entries fails the check, because zero decisions is stated in
build-summary.md as postDesignDecisions: [], not as an empty log. The ` · ` step line is
parsed as one header line holding several keys, and its trailing comment belongs to the
last key.

## D44 — Decisions are committed in their own docs(record) commit, right after the slice lands
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [design:F6, design:C1, code:cmd_land (plugins/bett3r-ai-workflow/scripts/worktree-pool.py), code:commands/build.md Step 4]
rejected: fold the entries into the slice's commit — Step 4's scope check counts them out of scope and a pool worker would have to write them; batch them to /build's end — a crash loses them and an uncommitted edit refuses the next land
supersedes: —
A slice's entries are appended right after its commit (in a pool, its land) and committed
in the same turn, before the next land, because a tracked edit in the main checkout
refuses a land with main-checkout-dirty. Step 6's commits= counts slice commits only. This
placement is what widens D10.

## D45 — build-summary.md is written at Step 6, on every outcome that ran a slice
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [design:F3, code:commands/build.md Step 6, adr:ADR-004]
rejected: write it in Step 5 — Step 5 runs only when every slice passed, and F3 requires a partial end to leave a record
supersedes: —
Step 6 writes and commits it before the LANE-STEP line, whether the outcome is success,
gate-red or blocked-on. The only skip is a run that stopped before any slice ran: a Step 1
work-docs-path error or a Step 2 size error.

## D46 — /build resolves the record folder in Step 1 and stops before any slice on error
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [code:commands/design.md Step 4, code:main (plugins/bett3r-ai-workflow/scripts/work-docs-path.py), adr:ADR-004]
rejected: resolve it when first writing — every slice would build first and then have nowhere to record its decisions; fall back to a default root — a record no reader finds
supersedes: —
work-docs-path is called as /design Step 4 calls it. outcome=error ends the run blocked-on
before any dispatch, as /design does.

## D47 — A resumed or partial /build carries earlier slice facts verbatim only while they agree with the passes flag, writes null for unproven ones, and lists every planned slice
kind: silent-seam
step: build · slice: 3 · decidedBy: verifier
sources: [design:F2, design:F3, code:commands/build.md, code:scripts/test-flow-seams.sh]
rejected: one entry per slice this run ran or found passed, with a never-started slice left off — an earlier session's attempts, retries, verifier and redBeforeGreen had no source and would be guessed, and a missing slice reads as an unplanned one
supersedes: —
Slice 3's first pass had no source for a slice an earlier session passed, and it left
never-started slices off the list. The verifier's finding settled it. The orchestrator
classified that retry design-silent. /build reads the existing build-summary.md. A slice this run did not run keeps
its entry verbatim only while the entry's passed matches the slice's passes: flag in
slices.yaml (D53). A passed slice with no entry, or with a stale one, gets commit (found
as D54 says), passed: true, and postDesignDecisions from decisions.md. id, name and origin
come from slices.yaml (D50). mode, attempts, retries, verifier and redBeforeGreen are null. A never-started slice is listed with
mode: null, commit: null, passed: false, attempts: 0, retries: [], verifier: null,
redBeforeGreen: null, and postDesignDecisions set to the ids decisions.md records for it
(usually []). A /verify-build usage or verifyBuild block already in the file is left
untouched.

## D48 — Seam I finds this unit's decisions.md through work-docs-path --repo
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [code:main (plugins/bett3r-ai-workflow/scripts/work-docs-path.py), code:scripts/test-flow-seams.sh]
rejected: spell docs/prs/XL-27 in the test — the root rule would then have a second, unchecked copy
supersedes: —
RECORD_ROOT overrides the repo so the check can be mutation-tested on a copy. The copy
must be a git repository (git init). The real tree does not depend on Q4 (D21).

## D49 — verify-build.md and the README still say "one commit per slice"
kind: shipped-finding
step: build · slice: 3 · decidedBy: verifier
sources: [code:commands/verify-build.md, code:README.md]
rejected: edit them in slice 3 — verify-build.md's Step 1 is slice 6's surface and the README principles are slice 8's
supersedes: —
verify-build.md:17 expects git log to show one commit per slice, and README.md:50 says
"One commit per slice". With D44's docs(record) commits, both should say one slice commit
per slice.

## D50 — A build-summary slice entry's id, name and origin always come from slices.yaml; mode and the gate facts may be null
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [design:F3, code:.work/slices.yaml, code:commands/verify-build.md, code:commands/build.md, code:scripts/test-flow-seams.sh]
rejected: null for every unproven key including origin — no slices.yaml carries an origin field today and verify-build.md has no fix-slice mechanism, so origin would read unknown on every resumed entry; origin: null as a legal enum value — a slice in slices.yaml was put there by /plan or a fix step, so its origin is never unknown
supersedes: —
Slice 3's retry 1 made null legal for commit and verifier, but its own rules also nulled
mode and redBeforeGreen, which the parsed block's enums did not allow. Retry 2, classified
invariant, closed the gap. mode and redBeforeGreen now carry | null. id and name come from
slices.yaml and are never null. origin is the slice's own origin: field, else plan, and
is never null. The null list is enumerated key by key so no key is nulled by accident.

## D51 — The record section's softening refute is lexical
kind: shipped-finding
step: build · slice: 3 · decidedBy: verifier
sources: [code:scripts/test-flow-seams.sh, code:commands/build.md]
rejected: a semantic parse of the record section's rules — a prose guard cannot close this fully, and the design-named mitigations are pinned by exact sentences
supersedes: —
The refute catches estimat*, guess*, omit*, optional, absent, left out, may append, may
write and infer*. Additive synonyms still pass: "skip the key when there are none", "a
worker can add its entry at landing", "never-started ones can be dropped". What holds is
that the exact sentences stay pinned. The reverse cost: legitimate prose in the record
section that uses one of those words goes red and must be reworded.

## D52 — A scoped final fix for slice 3 after its retries were exhausted
kind: deviation
step: build · slice: 3 · decidedBy: human
sources: [human]
rejected: commit as-is and record the gap — a resumed or crashed /build records landed slices as unlanded; stop the build
supersedes: —
Human decision, 2026-09-12 15:34 -03. Slice 3 had used both retries when the verifier
found B-V. The human authorised one more pass, limited to B-V and its polish, instead of
Step 3's ESCALATE.

## D53 — An existing build-summary entry is kept verbatim only while it agrees with the passes flag
kind: silent-seam
step: build · slice: 3 · decidedBy: verifier
sources: [design:F3, code:commands/build.md Step 1, code:commands/build.md Step 4]
rejected: keep any existing entry verbatim — an escalated or never-started entry outlives the session that later landed the slice, and it contradicts the passes flag forever
supersedes: —
Repro: in session 1, slice 2 escalates and slice 3 never starts. In session 2 both land,
then a transport error kills the session before Step 6; a human landing slice 2 by hand
has the same effect. In session 3, the summary would keep session 1's passed: false,
commit: null for both. The design never said what a stale entry means, so this is a
filled seam, not an overturned decision. A disagreeing entry is rewritten from the flag. A passes: true slice is written as a slice
an earlier session passed. A passes: false slice (a human reverted or flipped it) keeps its
entry with passed: false and commit: null. It does not become never-started: its
attempts: 0 would claim a slice that ran never did.
It amends D47's verbatim rule without overturning it.

## D54 — An earlier-session slice's commit is the recorded landed sha, else the one commit its Step 4 message names, else null
kind: silent-seam
step: build · slice: 3 · decidedBy: executor
sources: [code:commands/build.md Step 2, code:commands/build.md Step 4]
rejected: the most recent matching commit — picks silently between a re-run's duplicates; escalate when no single commit is found — blocks a finished build over a telemetry field
supersedes: —
Take the sha slices.yaml records (a pool land records it). Otherwise take the single commit
that git log --format=%H -E --grep '^Slice <id> of <work_item> ' <base>..HEAD finds, where
<base> is the frontmatter's base:. The anchor and trailing space make the id an exact
token: git log --grep matches per line, so XL-2 never matches XL-27. The range keeps
master's history of other work items out. The first form of this rule was an unanchored
grep over all of HEAD's history. On this repo, 'Slice 1 of XL-2' matched XL-27's 14d9083,
and the verifier showed a hand commit without the line would record the foreign sha.
docs(record) commits never carry the line. Zero or several matches write commit: null,
and What shipped says why, so passed: true with commit: null is legal. Step 4's example
line now reads Slice <id> of <work_item> — so a no-id item carries the dated slug the
lookup searches for. The lookup still depends on the host repo's convention keeping that
line.

## D55 — A second scoped fix for slice 3, to anchor and range the commit lookup
kind: deviation
step: build · slice: 3 · decidedBy: human
sources: [human]
rejected: ship without the commit lookup — records fewer shas; commit as-is — a resumed /build could write another ticket's sha
supersedes: —
Human decision, 2026-09-12 15:42 -03 (option 1). The verifier found the D54 lookup matching
another work item's commit and the reverse-mismatch rule writing attempts: 0 for a slice
that ran. The human authorised one more pass, limited to those two and their polish.

## D56 — Step 6's "unless the run stopped before any slice ran" is ambiguous when every slice already passed
kind: shipped-finding
step: build · slice: 3 · decidedBy: verifier
sources: [code:commands/build.md Step 6, code:commands/build.md Step 1]
rejected: reword it in slice 3 — out of the scoped fix's items
supersedes: —
In a session where every slice is already passes: true, no slice runs, and the session
only writes the summary. Read literally, that run "stopped before any slice ran" and
skips build-summary.md, which is the one thing it came to do.

## D57 — The commit lookup can still pick a docs(record) commit that quotes the Step 4 line
kind: shipped-finding
step: build · slice: 3 · decidedBy: verifier
sources: [code:commands/build.md Step 5 record section, design:F3]
rejected: filter record commits in slice 3 — out of the second scoped fix's items
supersedes: —
build.md says a docs(record) commit never carries the `Slice <id> of <work_item>` line,
but nothing enforces it. A hand-committed slice that drops the line, followed by a record
commit whose body quotes it at column 0, makes the lookup return the record commit's sha.
A subject line that starts with the same text matches the same way. Both can only return
a commit of this same work item and slice id, never another ticket's (D54 holds). Fix
candidate: drop subjects starting `docs(record)` from the matches.

## D58 — A reverted slice's kept null attempts and retries read oddly beside passed: false
kind: shipped-finding
step: build · slice: 3 · decidedBy: verifier
sources: [code:commands/build.md build-summary block comments]
rejected: —
supersedes: —
When the stale entry was itself an earlier-session passed entry, the reverse-mismatch rule
keeps its `attempts: null` and `retries: null` next to `passed: false`. The comment's
"null = passed in an earlier session with no record of it" stays historically true but
reads as a contradiction. A `## What shipped` note naming reverted slices would clear it.

## D59 — A kept-verbatim entry can carry a stale name after re-planning
kind: shipped-finding
step: build · slice: 3 · decidedBy: verifier
sources: [code:commands/build.md build-summary rules, code:.work/slices.yaml]
rejected: —
supersedes: —
If /plan renamed a slice, "kept verbatim" carries the old `name:`, which contradicts D50's
rule that id and name come from slices.yaml. Fix candidate: verbatim except id, name and
origin, which are always re-read from slices.yaml.

## D60 — D54's reason for the range overstates what the range does
kind: shipped-finding
step: build · slice: 3 · decidedBy: verifier
sources: [code:commands/build.md Step 5 record section]
rejected: —
supersedes: —
D54 and build.md say the range keeps other work items' history out; the line-start anchor
with its trailing space already does that. What the range adds is excluding this work
item's own earlier runs from before `base:`. It also does not exclude master commits merged
into the branch, which can only match the same work item.

## D61 — concerns-check takes a file path, and an absent file is an error
kind: deviation
step: build · slice: 5 · decidedBy: executor
sources: [design:F4, code:plugins/bett3r-ai-workflow/scripts/concerns-check.py]
rejected: resolve the file with --item through work-docs-path — /merge-multi must check other units' heads with git show, which work-docs-path cannot resolve from an unrelated branch; an absent file passing — a bad path must never look like a unit that raised no concerns
supersedes: —
concerns-check reads a concerns.md given as a path and prints a CONCERNS-CHECK:v1 verdict
line. A missing or unreadable file is outcome=error, exit 2.

## D62 — A concerns.md with no entries passes only when it is empty
kind: silent-seam
step: build · slice: 5 · decidedBy: executor
sources: [design:C5, code:plugins/bett3r-ai-workflow/scripts/concerns-check.py, code:scripts/fixtures/concerns/]
rejected: pass any file with zero well-formed entries — the first pass did, and a file whose real hard bars sat under ### C1, ## C1 -, ## Concern 1 or a bullet list passed as "no concerns"; allow a leading # title line — the skill never writes one
supersedes: —
Zero entries pass only for an empty or whitespace-only file after one BOM. Any other line
that is not a well-formed `## C<n> — <label>` header, a field, or blank is an error: a
near-miss header is malformed-header, stray content is malformed-unrecognised-content, a
non-field line inside an entry is malformed-entry, and a key outside the seven is
malformed-unknown-field. Found by the verifier on retry 1; the fixture that pinned the
fail-open (empty.md holding prose) is now zero bytes.

## D63 — A C-entry's quote is the raising quote; a waiver is cited from evidence
kind: deviation
step: build · slice: 5 · decidedBy: verifier
sources: [design:F4, code:plugins/bett3r-ai-workflow/skills/concern/SKILL.md, code:plugins/bett3r-ai-workflow/scripts/concerns-check.py]
rejected: require only a non-empty quote for verdict: waived — every entry already has one, so any entry could be flipped to waived with no owner consent; overwrite quote with the waiver's words — contradicts the append-only raising record
supersedes: —
F4's "verdict: waived requires the verbatim quote and appends a decisions.md entry" is read
as the waiver's own quote. quote: stays the owner's raising quote. A waived entry's
evidence: must cite the waiver as decisions.md#D<n>; concerns-check checks only that the
citation is present. /verify-build (slice 6) must verify the cited entry exists in this
unit's own decisions.md with kind: waiver, decidedBy: human, and the owner's verbatim quote.

## D64 — Required C-entry fields are non-empty, and placeholders count as empty
kind: silent-seam
step: build · slice: 5 · decidedBy: executor
sources: [design:F4, code:plugins/bett3r-ai-workflow/scripts/concerns-check.py]
rejected: leave why and verify unchecked; allow a ruled verdict with no evidence
supersedes: —
raisedBy, quote, why and verify must be non-empty on every entry, and evidence whenever
verdict is not —. A blank value, —, -, or a whole <…> template counts as empty. So
verdict: met with evidence: — is an error, while a freshly captured entry (verdict: — and
evidence: —) still fails as missing-verdict.

## D65 — A trailing comment on bar or verdict is ignored
kind: silent-seam
step: build · slice: 5 · decidedBy: executor
sources: [code:plugins/bett3r-ai-workflow/skills/concern/SKILL.md, code:plugins/bett3r-ai-workflow/scripts/concerns-check.py, code:scripts/test-flow-seams.sh]
rejected: strip comments on every field — evidence legitimately holds #D3; tell the model not to copy the template's comments — the example would still fail its own checker
supersedes: —
The skill's C-entry template carries inline # comments that list the allowed values, and a
model copying it literally failed concerns-check (verifier, retry 2). A value matching
^(\S+)\s+#.*$ on bar or verdict is ruled by the token before the comment. A comment-only
value, a # with no space, or two words before the comment stay malformed. A seam runs the
filled template itself through the checker.

## D66 — C-entry ids may have gaps; the skill allocates them
kind: silent-seam
step: build · slice: 5 · decidedBy: executor
sources: [code:plugins/bett3r-ai-workflow/skills/concern/SKILL.md, code:plugins/bett3r-ai-workflow/scripts/concerns-check.py]
rejected: treat non-contiguous ids as malformed — that would forbid ever retiring a concern
supersedes: —
The skill allocates the next id as the file's highest C<n> + 1. concerns-check never
allocates, and a duplicate id is an error. The header grammar rejects C0 and C01.

## D67 — /design seeds concerns only from explicit bars, and capture uses the reader path
kind: silent-seam
step: build · slice: 5 · decidedBy: executor
sources: [design:F4, code:plugins/bett3r-ai-workflow/commands/design.md, code:plugins/bett3r-ai-workflow/skills/concern/SKILL.md]
rejected: an enum for raisedBy — the design gives none; the writer form of work-docs-path — appending a concern never overwrites, so the design.md ownership check does not apply
supersedes: —
/design Step 1 treats a ticket sentence as a bar when it is phrased as a shipping condition
(must, can't ship unless, a red line), not as a feature description; when unsure it
captures a soft concern rather than dropping it. raisedBy is free text,
`<who> · step: <step>`. The concern skill resolves its folder with the reader form of
work-docs-path, with no --owner-branch.

## D68 — Every concerns-check verdict-line value is percent-encoded
kind: deviation
step: build · slice: 5 · decidedBy: executor
sources: [adr:ADR-004, code:plugins/bett3r-ai-workflow/scripts/concerns-check.py]
rejected: replacing spaces with _ — not reversible
supersedes: —
Values with spaces (value=unmet (see PR), a path with spaces) broke a key=value reader.
Space, tab, %, = and control bytes are percent-encoded on every field, including detail=.

## D69 — Some concern shapes still pass that a stricter checker would reject
kind: shipped-finding
step: build · slice: 5 · decidedBy: verifier
sources: [code:plugins/bett3r-ai-workflow/scripts/concerns-check.py]
rejected: —
supersedes: —
Free-text fields are not comment-stripped, so a placeholder followed by a comment counts as
non-empty: verdict: waived with quote: — # x and a citation passes, and verdict: met with
evidence: — # x passes. A comment that contradicts its token (bar: soft # hard) passes
silently. The waiver regex only needs the citation substring, so "not decisions.md#D3" and
a path-prefixed citation pass here; slice 6's cross-file check is the gate.

## D70 — Minor concerns-check behaviours are unpinned
kind: shipped-finding
step: build · slice: 5 · decidedBy: verifier
sources: [code:plugins/bett3r-ai-workflow/scripts/concerns-check.py, code:scripts/fixtures/concerns/, code:scripts/test-flow-seams.sh]
rejected: —
supersedes: —
A file holding only non-breaking spaces passes as empty. Quotes are stripped from bar and
verdict, so verdict: "met" passes, and a vertical tab splits a line. With the near-miss
header check removed, malformed files still fail closed, but the suite goes red only
because the reason= text changes. malformed-bar-two-words-comment.md does not distinguish
the regex ^(\S+)\s+# from the equivalent ^(.+?)\s+# while bar values are single words.
