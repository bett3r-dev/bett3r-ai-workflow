---
description: Grill the design to shared understanding while sharpening the domain model, then write a reviewable design doc. Constraint-shaped rewrite — same outputs, less procedure.
---

# /design — grill + model the design

Resolve the design through a relentless interview, sharpening the ubiquitous language as you go, and leave a **reviewable** design doc plus durable glossary/ADR updates. The `grill` skill drives the interview; `domain-modeling` maintains the model; `critique` attacks the result.

**This command states what must be true and what must be produced, and leaves the procedure to you.**

## Argument: $ARGUMENTS
The thing to design (a ticket id, a feature description, or "the active work").

---

## Board mode

If this repo has no `.esas/`, skip this section entirely and **say nothing about boards.**

If it does: board mode is on only when a board is both **possible** (`.esas/` with a `graph.json`, `esas-mcp` registered) and **warranted** (the design's forks name graph artifacts — commands, events, policies, read models, aggregates). Run the preflight in `../skills/esas-design/PREFLIGHT.md` for capability, and read `../skills/esas-design/BOARD-SETUP.md` for the seeding rules and what changes below; `esas-design` owns the standing rules once the tools are live.

**Relevance runs before the preflight, never after it.** The order is the mechanism, not a preference: the preflight prints verdicts and the table under it turns them into things you say out loud — *run the extractor*, *here is the launch line*, *another repo holds the port*. Run it first and the silent path has already spoken by the time the gate answers no. Which is also why relevance is **not** a preflight key and must never become one: a shell block cannot read a decision tree.

Three constraints on the gate itself:

- **On a no, say nothing at all** — no offer, no "we won't need it", no mention a gate was consulted. A mention hands the user a second surface to have an opinion about in a design where the answer is already known.
- **When it is close, unsure means silent**, and never resolve the doubt by asking. A false yes costs a screen the user did not want; a false no costs a board that arrives one fork later. Those are not the same size.
- **Re-ask at every new artifact-touching fork.** The gate is answered at the moment of least knowledge, so a design that opens on config and turns structural at fork 4 arms then. A late board loses nothing — it is a projection and catches up when it opens.

Classify by the tree in front of you, not the label on the ticket. "Frontend" is not outside the model by definition (`ui` is a node type in the extractor's own graph).

---

## Step 1 — Ground

**Record the mode first.** Overwrite `.work/mode.yaml` with `mode: design` and the current work item before anything else in this step — the file is rewritten in full, never appended, so re-running `/design` on a branch that has already been through another command yields a marker naming `design` rather than whatever ran last. `/start` owns clearing it; every other command owns keeping it honest.

Read the ticket, then the relevant bounded context's `CONTEXT.md` (locate via `.esas.config.json` `domainEventsPath`). Where there is none, fall back through `docs/adr/` to **the module headers of the symbols you were told to grep** — and read the headers even when the ADRs hit; in a repo that writes doctrine into headers, the ADRs are the summary and the headers are the source. Say "grounding degraded: no CONTEXT.md" in the doc and recommend `/seed-context`.

Treat the glossary as **evidence to verify, not ground truth**.

**Then collect context contributions, if this repo declares any.** Step 1 is a declared extension point: an optional, repo-local **context provider** may contribute items to the grounding, and items that survive become ordinary Step 3 forks carrying their verbatim source span. The base plugin ships no provider and **zero providers is the normal case** — with none declared, do not go looking, do not mention that an extension point was consulted, and this step behaves exactly as it did before. A provider that errors, times out or returns nothing **never fails `/design`**: note the degrade beside "grounding degraded" and continue. The full contract — the shape of a contribution, why a hook was rejected on this repo's own measured evidence, and why this is `/design` only — is [CONTEXT-PROVIDERS.md](../CONTEXT-PROVIDERS.md).

### The ticket is evidence, not spec

Stale tickets are the norm — in one 4-ticket run three descriptions were stale and a fourth's premise was false. Verifying costs minutes and is what the design-first gate is *for*. **Where the ticket and the code disagree, the code wins, and the doc says so.** The general discipline — quote symbols as the source spells them, state what a count counts, treat a uniqueness claim as a probe, name the corpus you searched, `mtime` is not provenance — is [EVIDENCE.md](../EVIDENCE.md) §3 and is not repeated here. What follows is the **order** of probes, because each layer is cheap and the ones above it re-frame everything below.

**1. The ticket's own history, before its body.** `git log --oneline <BASE> --grep=<TICKET-ID>` — non-empty means the body is a **historical document**: seven of eleven sections had shipped under one ticket's own id, and the deliverable is a per-section SHIPPED / OUTSTANDING ledger with shas, not a design. Status fields say nothing; nobody transitions tickets.

**2. Every citation is re-resolved by identity, not followed by address.** An ADR cited by number rots into a real-but-wrong document (four tickets cited `ADR-090 §7`; the section lived in `ADR-097`, and 090 existed with no §7); a `file:line` rots on every commit and can still resolve to an unrelated file of the same name. Confirm the cited *section* is about the cited subject; re-locate code by **symbol** — `grep` the quoted identifier and let it say where the file lives now. A "VERIFIED at `<sha>`" stamp is a timestamp, not a warrant. **Write your own citations as `symbol (file:line)`** — `` `collapseChannelStock` (`publicationDesiredChannelStatePush.policy.ts:253`) `` — the line is the fast path when fresh and a hint when stale; the symbol is the contract, and a lane 66 commits later re-locates it in one grep instead of re-reading the file.

**3. Existence claims: the ticket asserts more than it states.**
- **A cited sibling ticket exists in code, not just in Jira** — `git log --all --grep=<ID>` catches *planned, never built*; a **concept-noun grep** (`supplier`, `csv`) catches the harder case where the cited work is not what the description imagines. Two tickets were sized as "mirror X" where X had never existed; where the ghost is named in an acceptance criterion, the AC is unverifiable — say so and re-size.
- **Name the host surface a pre-fill / extend / consume verb attaches to, and grep for it.** Every cited `file:line` in one ticket was correct and the form it pre-filled did not exist; the tell was a verified section listing four producer artifacts and zero consumers. Producer-only evidence is a finding.
- **A "does not reuse X" list is a probe in both directions** — each X still exists (a relocated module makes the exclusion a fossil), and a concept-noun grep for the near-duplicate the list omits (the omission was worth more than every item on one list).
- **"No such mechanism exists" is not settled by reading the callers.** Absence-of-use is not absence-of-capability: `ForEachNode` existed with no built-in user. Search the engine's own source by concept noun (`forEach`, `map`, `fanOut`, `iterate`) and record *the search that failed*, not the callers that happened not to use it. A subagent's **negative** existence claim is the highest-risk thing it can return — re-run the one-line `find` yourself before acting on it.
- **A hit count is not evidence a concept exists.** Six hits for `purchaseorder` were three vendor type dumps and three marketing strings; the deliverable is a **classified list** ("6 files, all under `sales-channels/*/types/` and `apps/landing/`"), never a number. The positive control validates the corpus and the flags, not hit quality — scope the corpus to the domain question.

**4. The load-bearing claim — the one that forecloses an option — is verified against the constructing frame, in its own scope.**
- **A claim repeated in ticket + code comment + ADR is ONE claim** if each cites the previous; trace provenance before counting sources. When it proves false, record every site that carries it as work, or the next spin-off batch re-seeds it.
- **An error / status / code claim cites the frame that constructs the object it names**, not the call site that triggers it — adapters remap SQLSTATEs invisibly from the caller, and a `code === 23505` branch was dead behind a green test that hand-built the shape. Unless the constructing frame was read, the claim is "this path fails", not "this path throws X".
- **A fact about a multi-entry-point symbol carries the lane it was observed on**, or it is `UNVERIFIED`: "`neto` is computed in the handler" was true of one of two issuance lanes. Unscoped is precisely where the design question lives.
- **"Throw or return?" is answered at the CALLER.** A gate relaxed to `return undefined` was, at its call site, an admin escalation — invisible from the gate's own file.
- **Population, not declaration.** "Does data X already exist?" is answered by grepping a *writer* of X, not its schema.
- **An auto-resolution's prerequisite chain is checked before it is settled** — the mapping that makes "wire the real buyer document into the ARCA call" safe collapsed three tax-id kinds to one wrong code.
- **An edge case with no precedent keeps the invariant**; "no existing pattern for cold start" is a design gap to fill, never grounds to relax the AC there.

**5. Prior art is evidence of a convention, not of correctness.** When the design revisits something a prior ADR **rejected**, check each stated reason's *mechanism* — still true? ever true? does it cite another document whose actual argument differs from the summary? — and check any *"right if X"* condition the ADR named: if X did not happen, say so. Record the outcome as a **bisection**, amending the half that failed and quoting the half that survives; `Superseded` is for a decision that no longer binds. When the core move is **"mirror X"**, spend one probe on what X gets wrong — the cross-cutting concerns a feature review skips (erasure, authorization grants, redelivery, account scoping); `sales.Customer` would have handed a new aggregate a live compliance defect. And for a "stand up a new <thing>" unit, derive the site checklist from `git show --stat --find-renames` over the last genuine greenfield commit series, never from memory — four of five candidates were renames.

**6. Two probes the second pass must RUN, because a reader who shares the premise re-confirms it.** Classify each item: a *claim about existing code* (a file, a line, a current value) is verified by reading and is reliably true when the design was grounded; an *assumption about behaviour* (what a helper does with `0`, what a literal expands to, what a classifier returns at an edge) is **not** verifiable by reading — render the template, run the function, print the expansion. Three of three real failures in one unit were the second kind. Two concrete forms: **grep every other reference to a type before accepting that a widening is "purely additive"** (a union widened for its readers broke a positional consumer inside a fenced function); and **when a design says "test X asserts Y", grep the assertion string, not the file name** — the real assertion was a shell probe wired to `test:chart`.

**7. Achievability, separately from the premise.** For each acceptance criterion name the mechanism that would satisfy it and confirm it can exist; where none can, that is the unit's headline finding — emit it, withdraw the AC by name, never design around it. Run the ACs against **each other** and against the named invariant's key too: two ACs can be satisfiable alone and contradictory under one invariant. And for any command dispatched by a **rule, policy or cron**: *who is the caller's principal, and which gate would catch a missing grant?* Where the answer is "none" (a frozen system-principal capability set, statically underivable), the grant is an acceptance criterion, not a risk.

**8. A replaced mechanism gets a verified DIES / SURVIVES inventory, per repo.** A domain term survives its transport: the press route and the client half of a summon were listed for deletion with the sentinel they merely carried, and a `grep summon → 0` oracle would have renamed the feature out of the codebase. Oracles name the *implementation* surface, never the ubiquitous-language term; and every component names the repo that actually contains it, established by locating the file, not by which repo it feels like it belongs to.

Three rules hold across all eight: **check the *mechanism* behind a stated rationale, not just the ask** — a deferral's reasoning, a stated blocker, an "already handled by X" is usually one probe from materially different; **a claim about another repo's runtime checks the artifact that executes** (installed package, plugin cache, deployed build), not only its source; and **if the ticket ships a worked example of the defect, run it.** Ticket-prescribed architecture is a claim checked against the code's own rules — an override is a rejected option *and* an open fork, never a silent correction. When the ticket says "this comment is wrong", `git log -S` the phrase: its real size is the set of decisions that *cite* the claim.

**When the ADR you write corrects a premise, it ships the corrected reason.** A decision can survive its premise's falsification — a fallback that "inherits monolith sizing" actually mis-sized in two directions, which *strengthened* hard-fail — and an ADR that keeps the original rationale because it reached the right verdict is a decision nobody can safely inherit. Say both. And an ADR whose purpose is to kill a widely-repeated claim carries a grep-and-fix over the existing occurrences, or the loud adjacent copy in a schema doc keeps winning against the ADR nobody opens.

A read-only probe returning a false negative is used as evidence that a handler is dead or a file absent. [EVIDENCE.md](../EVIDENCE.md) has the ways this fails silently on the default macOS shell and the positive control that catches them.

## Step 2 — If the ticket carries a resolved-design block

Grep for `design-multi:resolved:vN` (emitted as an HTML comment *and* a visible inline-code line). If present, its design was resolved in an earlier `/design-multi` interview. **This run is a verification second pass, not a fresh grill:** treat the decisions as authoritative pre-answers, confirm each still holds against current code, and re-open a fork only where the code now *contradicts* it. On a ticket whose code has not drifted the grill has nothing to ask and flows straight to Step 4. That is what lets `/start-multi` run such a ticket unattended.

**Verify the block's claims, not that its prose fits.** A decision can be interview-resolved, zero-drift, paste-ready and factually false — the interview happens once and runs unattended afterwards, so an error introduced *during* the interview has no downstream gate, and zero drift reads as nothing to check. Step 1's probes apply to the block exactly as to a ticket; three defences bite hardest here:

- A decision that **re-argues an existing behaviour** rather than changing anything is the highest-risk kind — it ships as prose, has no test, no oracle can fail it. Re-derive it.
- **Verify the mitigation, not just the risk.** A block's own Risks section is a ready-made checklist; the known case had the risk fire *through* its mitigation, which was itself the false claim.
- You may **keep a decision while declining to assert a falsehood it rests on** — record the correction in the PR body. Ship-blocking a human for "your reason is wrong but your decision stands" is the wrong trade.

Then **enumerate what the block does not decide.** Drift-checking is a check against what the block *says*, so its silence is invisible — and the better-evidenced the block, the more confidently an executor generalises into the gaps. For each decision naming a rule (a merge, an ordering, a degrade direction, a precedence), ask which other component performs the same class of operation and whether the block speaks to it. Emit the unanswered ones as **unspecified seams** and pass them down as explicit non-guidance.

## Step 3 — Grill, then critique

Run the interview (`grill` + `domain-modeling`): every branch of the decision tree, one question at a time, each with your recommended answer, dependencies resolved before moving on. Under board mode the independent forks batch to the canvas and the dependent ones stay serial.

**Every fork is presented picture → scenarios → per-option walk** — `grill`'s *Presenting a fork* owns the shape and this is where it is mandatory. Two option labels are not a question: the user cannot tell from them whether you are discussing the same thing they are. Where every scenario walks identically across the options there is no fork — resolve it and record it as an autonomous decision.

While you interview: challenge terms against the glossary, update `CONTEXT.md` inline the moment a term resolves (glossary only), and offer an ADR only when a decision is hard-to-reverse **and** surprising **and** a real trade-off.

Then run `critique` (`arch,ops`) against the resolved tree — one focused adversarial pass, not a second grill. Fold in what is clearly right; drop back to the grill for a genuine fork it surfaces; carry a weakness with no good answer into *Risks*.

## Step 4 — Write `.work/design.md`

Markdown + Mermaid, reviewable in one pass, ephemeral and **not committed**. Its durable conclusions live in the committed glossary/ADR updates and, later, the PR body. Sections:

- **Problem & intent**, in the ubiquitous language.
- **The resolved decision tree** — each pivotal fork, the chosen answer, the why, the rejected options.
- **Seams / flow** — a Mermaid diagram of the key flow and any new boundary crossed.
- **Test seams** — where this gets verified. Prefer existing seams, the highest seam possible, the fewest (ideal: one), each with a prior-art test to mirror. These become the slices' oracles — confirm them with the user.
- **Risks / the gate-less seam** — the riskiest part nothing automatically catches. This becomes the tracer bullet.
- **Unspecified seams** — what this design deliberately does not decide. An unspecified seam **adjacent to a specified one** is the highest-risk place in the document, because the stated rule is exactly what will be reused there. Recurring shapes: read-modify-write pairs, the client and server halves of one document, the read and write paths over one piece of state.
- **Scope boundaries** — explicit in/out, follow-ups to spin off.
- **Provenance** — the commands that produced this design's numbers and claims. Cheap to write; it converts every empirical finding into something the next context can re-run, and resumed cold it is reliably the most useful section in the doc.

## Step 5 — Hand off

**Answer this before handing off: could a fresh session holding only this repo and `.work/design.md` run `/plan` without loss?** Enumerate what this session produced — files, commands and their outputs, counts, external state — and confirm each is in the doc, committed, or declared re-derivable with the command to re-derive it ([EVIDENCE.md](../EVIDENCE.md) §4: this fails worse the better the session was).

Corollary: **any artifact the design names as a test seam, gate, or tracer-bullet instrument is committed, not left untracked** — or the doc states plainly that the first slice creates it. A design depending on an uncommitted file is neither reviewable nor resumable.

**And the same test applies to this document.** `.work/design.md` is gitignored, so it is a correct *scratch* location and a wrong *citation target*: a path under `.work/` resolves for one worktree on one machine and for no other reader, ever. The moment anything outside this session will point at the design — a ticket body, a sibling ticket, a fleet brief, an ADR — **the cited copy is committed and the citation names the committed path**, not the `.work/` one. Nothing errors either way, which is the whole problem: a lane on a fresh clone finds nothing at the cited path, does not stop, and builds from the ticket body — which this flow treats as a *summary* of the design rather than the design. Six lanes of one run read the doc only because they happened to run in the authoring worktree; mid-run it was committed elsewhere and corrected (531 → 586 lines: a falsified claim, a new rule), and every ticket still pointed at the dead path. **The rule that outlives the specifics: a citation target must be reachable from the base its reader branches from.**

Then summarise the resolved design, the `CONTEXT.md`/ADR updates, and the open risks:

> Review `.work/design.md`. When it's right, run `/plan` to cut it into vertical slices.

## Principles
- The grill is the engine; the docs are a side effect. Don't let doc-writing slow the interview.
- `CONTEXT.md` is durable and committed; `design.md` is ephemeral.
- Speak the ubiquitous language — a term the glossary lacks is a term to resolve and record.
