---
description: Grill the design to shared understanding while sharpening the domain model, then write a reviewable design doc. Composes the grill + domain-modeling skills.
---

# /design — grill + model the design

Resolve the design through a relentless interview, sharpening the ubiquitous language as you go, and leave a **reviewable** design doc plus durable glossary/ADR updates. This is "grill-with-docs": the `grill` skill drives the interview, the `domain-modeling` skill maintains the model.

## Argument: $ARGUMENTS
The thing to design (a ticket id, a feature description, or "the active work").

---

## Step 0 — Board mode (skip unless this repo has a `.esas/`)

Where ESAS is set up, this interview has a second surface: the decisions land in `.work/design.md` as always, and the **structure** lands on a live board the user watches on another screen while you talk. Board mode is off by default and costs one command to rule out.

Two gates decide it, and they ask different questions. **Capability asks whether a board is possible; relevance asks whether it is warranted.** Both must say yes — board mode is **on** only when they both do, and the `grill` skill's canvas subsection, which defers to "`/design` has put board mode on" rather than restating either half, reads it as that conjunction. (The `esas-design` skill is scoped differently on purpose: its standing rules fire wherever the `mcp__esas__*` tools exist, so "look at the board" still syncs correctly in a session where board mode was never armed.) Relevance is first, and it is cheaper than one command: it costs none.

**Both gates are in this step; everything downstream of them is not.** Registering `esas-mcp` and the restart that makes it real, seeding the design layer, the launch offer, and what board mode changes about Steps 2–3 are [BOARD-SETUP.md](../skills/esas-design/BOARD-SETUP.md), and each row of the verdict table below names the section there that answers it. **It is opened only on a double yes** — on either no you do not read it and you do not mention it, per the silence rule under Gate 1.

### Gate 1 — relevance: what the decision tree names

**Board mode is armed by what the drafted decision tree names.** Draft the tree first — the `grill` skill opens the interview with it — then read it back: does any track name **a command, an event, an aggregate, a policy, a read model, or a coupling** between them? One is enough. If none does, the design is not about structure, and a board would render nothing but the questions' own text: a canvas of stickies nobody asked for, on a second screen the user now has to close.

So Step 0 is *settled* before the first proposal, not *finished* before Step 1. Ground the interview, draft the tree, answer this gate — and only on a yes go on to the preflight below. It keeps the number 0 because board mode has to be decided before anything is written, not because it is the first thing that happens.

**Relevance runs before the preflight, never after it.** The order is the mechanism, not a preference: the preflight prints verdicts and the table under it turns them into things you say out loud — *run the extractor*, *here is the launch line*, *another repo holds the port*. Run it first and the silent path has already spoken by the time the gate answers no. Which is also why relevance is **not** a preflight key and must never become one: a shell block cannot read a decision tree, and a key it printed would have to be answered before there was anything to answer about. The cost of this order is real and it lands on one path — a repo that needs the `esas-mcp` restart now hits that stop after the grounding rather than before it, and under the mid-interview fallback later still, after forks the user has already answered. All of it is re-done in the new session, which is why the restart copy in BOARD-SETUP.md names what it costs instead of promising the stop is free. That is still the cheaper half of the trade; the alternative is every design in the repo opening with board talk, structural or not.

**On a no, say nothing at all about boards.** Not a shorter version, not a footnote — nothing. No offer, no "this repo has ESAS set up but we won't need it", no mention that a gate was consulted. Run Steps 1–4 exactly as written. A mention is not free: it hands the user a second surface to have an opinion about in a design where the answer is already known.

**The fallback is to arm mid-interview at the first artifact-touching fork.** This gate is answered at the moment of least knowledge, so a design that opens on config and turns structural at fork 4 must not be locked out by its opening. Re-ask it whenever a new fork names an artifact; on a yes, run the preflight then and pick board mode up from there. A late board loses nothing — it is a projection, and it catches up the moment it opens.

**When it is close, unsure means silent.** This gate asks for a judgement, and nothing in this repo's suite can tell a right call from a wrong one — the only thing that makes prose safe here is which way it fails, so it is stated as a rule rather than left to taste. A false yes costs the user a screen they did not want and a paragraph of board talk in a design with no structure in it; a false no costs a board that arrives one fork later through the fallback above. Those are not the same size. And do not resolve the doubt by asking: *"should I open a board?"* is exactly the output this gate exists to suppress.

**Frontend, infrastructure, PV3-internal plumbing and work outside the modelled subdomains are the usual no's — as worked examples, never as a rule.** Classify by kind of work and you are wrong precisely at the edges: `ui` is a node type in the extractor's own graph, and teselly's `.esas.config.json` carries a `webAppPath`, so "frontend" is not outside the model by definition. Read the tree in front of you, not the label on the ticket.

### Gate 2 — capability: what is actually on disk

Run the preflight from the repo root. It reports facts and decides nothing:

```sh
# --- esas preflight ---
# Facts about this checkout's design layer. Decides nothing; the table below
# does that. Every `key: value` line it can print has a row there, and
# scripts/test-esas-design.sh asserts both halves of that.
#
# The plugin line leads because it is the one fact that can invalidate every
# line under it — and the whole command around them. A session runs the build
# the version-keyed cache holds, not the source tree you are reading, so if
# those two have drifted, everything below is a correct report from the wrong
# copy of this file. That is worth one line at the top rather than four JSON
# files under ~/.claude/plugins/ once somebody suspects it.
#
# No `exit` anywhere and every variable prefixed: this runs in whatever shell
# the tool call lands in, and it has no business ending it or renaming
# somebody's `path`.

# `CLAUDE_PLUGIN_ROOT` is substituted for *hook* invocations only, so it is
# unset here and cannot answer this. `PATH` can: the cache `bin` directory of
# every enabled plugin is on it, and that directory is keyed by the version —
#     …/plugins/cache/<marketplace>/bett3r-ai-workflow/<version>/bin
# The marketplace directory happens to share this plugin's name, which is why
# the pattern insists on a path segment *before* the plugin one: without it the
# sibling `bett3r-pv3-ai-skills` under the same marketplace would read as this
# plugin, and report its version as ours.
esas_plugin_version=''
esas_path_rest=$PATH
while [ -n "$esas_path_rest" ]; do
  esas_path_entry=${esas_path_rest%%:*}
  case $esas_path_rest in
    *:*) esas_path_rest=${esas_path_rest#*:} ;;
    *)   esas_path_rest='' ;;
  esac
  case $esas_path_entry in
    */plugins/cache/*/bett3r-ai-workflow/*/bin)
      esas_plugin_version=${esas_path_entry%/bin}
      esas_plugin_version=${esas_plugin_version##*/} ;;
  esac
done
if [ -n "$esas_plugin_version" ]; then
  printf 'plugin: loaded\n'; printf '  version: %s\n' "$esas_plugin_version"
else
  printf 'plugin: unknown\n'
fi

esas_port=${ESAS_BOARD_PORT:-3727}

if [ ! -d .esas ]; then
  printf 'esas_dir: absent\n'
else
  printf 'esas_dir: present\n'
  if [ -f .esas/graph.json ];  then printf 'graph: present\n';  else printf 'graph: absent\n';  fi
  if [ -f .esas/design.json ]; then printf 'design: present\n'; else printf 'design: absent\n'; fi
  if [ -f .esas/ops.jsonl ];   then printf 'ops: present\n';    else printf 'ops: absent\n';    fi

  if [ ! -f .mcp.json ]; then
    printf 'mcp: absent\n'
  else
    esas_registered=no
    while IFS= read -r esas_line || [ -n "$esas_line" ]; do
      case $esas_line in *esas-mcp/bin/esas-mcp.mjs*) esas_registered=yes ;; esac
    done < .mcp.json
    if [ "$esas_registered" = yes ]
      then printf 'mcp: registered\n'
      else printf 'mcp: unregistered\n'
    fi
  fi

  if ! command -v curl >/dev/null 2>&1; then
    printf 'board: unknown\n'
  else
    esas_body=$( curl -fs --max-time 2 "http://127.0.0.1:$esas_port/api/esas/status" 2>/dev/null )
    # Which checkout the board serves is not a question about how it spells the
    # path or serialises the answer, so both spellings of this directory are
    # tried (the board resolves symlinks, a shell does not), spaced and
    # compact. A false `other-repo` sends the user hunting for a rival board
    # that is not there, which is worse than the ambiguity it would report.
    esas_serving=no
    for esas_path in "$PWD" "$( pwd -P )"; do
      case $esas_body in
        *"\"repoPath\":\"$esas_path\""*|*"\"repoPath\": \"$esas_path\""*) esas_serving=yes ;;
      esac
    done
    if [ -z "$esas_body" ]; then
      printf 'board: off\n'
    elif [ "$esas_serving" = yes ]; then
      printf 'board: serving\n';    printf '  status: %s\n' "$esas_body"
    else
      printf 'board: other-repo\n'; printf '  status: %s\n' "$esas_body"
    fi
  fi
fi
# --- end esas preflight ---
```

### What each verdict means

| report | what it means | what you do |
|---|---|---|
| `plugin: loaded` | A version-keyed cache directory for this plugin is on `PATH`, and the `version:` line under it is the build **this session** is running. That is a different question from which source tree you are editing: the cache is copied afresh only when the version string changes, so an edited plugin whose version stayed put is still being served from the old copy. | Nothing, in the ordinary case — read it and carry on. It earns its place on one path: if you have just changed this plugin and the number here is the previous release, **the change is not loaded**, and nothing you are reading in this session is what is running. Say so before acting on any of it; the fix is a version bump and a fresh session, not another edit to a file nobody is executing. |
| `plugin: unknown` | No cache directory for this plugin on `PATH` — the session is running the plugin from source, or it was never installed from the marketplace at all. | **Not an error, and not a thing to fix.** It means this one line cannot answer the question, so carry on exactly as normal. If the answer turns out to matter — a command behaving like a version you do not recognise — read `~/.claude/plugins/installed_plugins.json` instead. |
| `esas_dir: absent` | No design layer here — a fleet worktree, or a repo the extractor has never run in. | **Board mode off.** Run Steps 1–4 exactly as written. Never create `.esas/` to switch it on; the directory is the marker of "this checkout designs". |
| `esas_dir: present`, `graph: absent` | `.esas/` exists but the extractor has not produced a graph. | Board mode off until it has. Ask the user to run the repo's extractor (`yarn esas` in teselly), then re-run the preflight. Proposals against a graph that isn't there have nothing to attach to. |
| `esas_dir: present`, `graph: present` | Reality is on disk. | Board mode is possible — continue down this table. |
| `design: absent`, `ops: absent` | No design session has started here. | The normal, clean start. There is nothing to create — BOARD-SETUP.md §*Seeding*. |
| `design: present` or `ops: present` | A design layer is already on disk. | It is either the unit of work you are resuming or the residue of one that shipped. **Ask whose session it is** — BOARD-SETUP.md §*Seeding*. |
| `mcp: registered` | The entry is in `.mcp.json`. That is not the same as the server running. | Call the `status` tool now — BOARD-SETUP.md §*Registering* for the three ways this answers. |
| `mcp: unregistered` / `mcp: absent` | This repo's `.mcp.json` does not register the server. That is all the preflight can see — it reads the project file only. | Write the entry, then **stop** — BOARD-SETUP.md §*Registering* — **unless the `mcp__esas__*` tools are already available in this session**, which means it is registered elsewhere (a user-scoped `~/.claude.json`). Then skip the write: it would cost a needless restart and put a duplicate entry in a git-tracked file. |
| `board: off` | Nothing is serving this repo on :3727. | The normal state before the user launches it. **Carry on** — the offer comes later, when the first batch of questions is ready, not here; BOARD-SETUP.md §*The board*. |
| `board: serving` | A board is up on this checkout. The `status:` line under it is the board's whole answer, including `sessions` — how many sessions are holding the summon channel (`/api/esas/ws`) open. | Compare its `lastSeq` with the `status` tool's. Same number ⇒ the link is live. Then read `sessions`: **`"sessions":0` means nobody would hear the *Ask Claude* button** — open the channel (`esas-design` skill, §*The summon*). A number ≥ 1 is not a guarantee anyone is listening (there is no heartbeat, so a half-open socket still counts), so never use it to decide *not* to open one; and an older board omits the field entirely, which is unknown, never zero. |
| `board: other-repo` | Something holds :3727 serving a *different* checkout, and the `status:` line under the verdict says which. | **Name the repo that holds it** — the `repoPath` in the `status:` line is the project root that board serves — and say so before the first proposal: until it is closed this repo's board cannot claim the port (`strictPort` never drifts), and the screen the user is watching will never move. Naming it is the difference between a thing the user can close and a board they may not remember starting. Then carry on. |
| `board: unknown` | No `curl` here, so the board was not probed at all. | Say it was not verified rather than reporting it down, and carry on. |

**On a double yes, the rest of board mode is [BOARD-SETUP.md](../skills/esas-design/BOARD-SETUP.md)** — registering `esas-mcp` and the restart it needs, seeding the design layer, the launch offer, and what changes in Steps 2–3. Read it once, then run Steps 1–4 with those changes folded in. On either no it is never opened, and Steps 1–4 run exactly as written below.

---

## Step 1 — Ground the interview

- Read the ticket / context. Read the relevant bounded context's `CONTEXT.md` (locate it via `.esas.config.json` `domainEventsPath`, per the `domain-modeling` skill) so you speak the project's ubiquitous language from the first question. **Where there is none**, the fallback is a chain, not a single alternative: `CONTEXT.md` → `docs/adr/` → **the module headers of the symbols you were told to grep** — and read the headers *even when the first two hit*. In a repo that writes doctrine into headers, the ADRs are the summary and the headers are the source, including the rejected alternatives and why. Say "grounding degraded: no CONTEXT.md" in the doc, route glossary deltas into the ADR that motivates each term, and recommend `/seed-context` as the durable fix. Treat the glossary itself as **evidence to verify, not ground truth** — a stale entry describing a deleted component sends a code-first pass to the wrong surface.
- Explore the codebase for anything the design depends on — **answer from the code, not speculation**, wherever a question can be settled that way.
- **The ticket is evidence, not spec — verify it before trusting it.** Stale tickets are the norm. Building from the text alone routinely re-implements something already shipped, builds machinery for a rationale that never existed, or under-scopes by half. (In one 4-ticket run three descriptions were stale and a fourth's premise was simply false; in a 12-ticket run, three independent lanes each found a load-bearing falsehood.) This is minutes of work, and it is what the design-first gate is *for*:
  1. **Grep for the ticket's central symbol** — the flag, event, or command it names. Does it already exist? Quote it **as the source spells it**; a paraphrased identifier (`parseMoney` for `parseAmountToMinorUnits`) is indistinguishable from a real one until you grep. State what any count counts — "5 files / 7 call expressions", never "five call sites".
  2. **`git log -S <symbol>`** — shipped? reverted? tests deleted? Its yield depends on the repo's commit style: high in a slice-committing repo (one call dates a symbol to its slice and reveals it is not on master), near-zero in a squash-merging one, where `grep -rn` over **doc comments** is the provenance probe that pays instead.
  3. **Check the ticket's *premise*, and the *mechanism* behind any rationale it states** — a deferral's reasoning, a stated blocker, an "already handled by X". Each is usually one probe from being materially different: one deferral's "balance is re-derived on every replay" was mechanically false, which collapsed the whole proposed fix. `gh api /orgs/<org>/packages` showed a package "blocked on publishing 1.4.0" had never been published at any version — a first publish with no owner, not a bump someone owed.
  4. **A uniqueness or exhaustiveness claim is a probe, never a premise.** "The only surface", "nothing else reads this", "three call sites" — grep for the other consumers first. One such probe returned three corrections and relocated the ticket's real observable.
  5. **If the ticket ships a worked example of the defect, run it.** A synthetic in-memory project costs nothing; a plausible-but-wrong mental model propagating into the fixture set is expensive and silent — the fixtures pass and the actual defect ships behind a green suite. One example did not reproduce the defect it illustrated.
  6. **Treat ticket-prescribed architecture as a claim** ("build this as a domain operation") to check against the code's own rules. An override is recorded as a rejected option **and** surfaced as an open fork for the human — never silently corrected in either direction.
  7. **Flag inherited claims** — a ticket split from another, or cut mid-fleet. A handoff is a claim, not evidence, and a residual ticket goes stale against its own fleet's tail merges: diff its premises against everything that landed after it was written.
  8. **If the claim is about another repo's behaviour, verify the artifact that actually executes** — the installed package, the version-keyed plugin cache, the deployed build — not only its source. Every gate in a repo reads the source tree, so a source-tree grep can invert a ticket's whole premise: `grep -rn summon` over the plugin cache returned zero while the source at `origin/master` had 38, because cache dirs are version-keyed and nothing propagates without a `plugin.json` bump. When a ticket's evidence is "grep returns zero", restate **what corpus was searched** and check the sibling corpus. (Comparing a loaded skill's own description against BASE's frontmatter is a zero-cost in-session drift check.)
  9. **A generated artifact is evidence only if you can name the commit that produced it.** `mtime` is not provenance, and siblings written in the same second can come from different producers — one mid-branch `.esas/` disagreed with itself, and grading against it would have produced plausible numbers that were partly noise. For a measurement, name the **pin you regenerate from**, not the path you read.
  10. **When the ticket is "this claim/comment is wrong", grep the claim, not the file.** Its real size is the set of decisions that **cite** the claim, not the set of lines that state it — one such ticket went from one line to four sites, one of which had *reasoned from* the falsehood to justify a shipped behaviour. `git log -S` the distinctive phrase to date the claim against the change that falsified it: *stale* and *never true* call for different corrections.
  11. Where the ticket and the code disagree, **the code wins** — and the design doc says so, so the reader knows what the real change is.

  Probe hygiene matters more here than anywhere: a read-only probe returning a false negative is used as *evidence* that a handler is dead, a premise stale, a file absent. See [EVIDENCE.md](../EVIDENCE.md) — the three ways it fails silently on the default macOS shell, and the positive control that catches all of them.

## Step 1.5 — If the ticket carries a resolved-design block (second pass)

If the ticket has a `design-multi:resolved:vN` block (grep the token — it is emitted as an HTML comment *and* as a visible inline-code line, since some trackers strip comment nodes), its design was already resolved in an earlier `/design-multi` interview. **This run is a verification second pass, not a fresh grill.** Those are prior decisions, each with its rejected options and the evidence that settled it — treat them as **authoritative pre-answers**, the same way you treat the code:

- **Verify, don't re-derive.** For each resolved decision, confirm it still holds against the *current* code (the same step-1 protocol). Only **re-open** a fork the code now **contradicts** — e.g. the block was grounded against an older base and something it assumed has since shipped or changed.
- On a ticket whose code hasn't drifted, the grill has **nothing to ask** and flows straight to Step 2.5 / the doc. This is exactly what lets `/start-multi` run such a ticket unattended.
- Where a resolved decision no longer holds, surface it as a normal fork (Step 2). Running standalone, you ask the user; under `/start-multi`, that unit escalates.

**This pass verifies the block's claims and reasoning — not that its cited sites still read as quoted.** *The prose fitting is not the claim being true.* A decision can be **interview-resolved, zero-drift, paste-ready and factually false**: one such replaced a false rationale with a second false rationale, citing an ADR line range that says the opposite of what it was cited for, in a ticket whose entire subject was a false comment. A conformance check returns PASS on all of it — the sites did still say what the block claimed. Because the interview happens once and `/start-multi` runs unattended on the result, an error introduced *during* the interview has **no downstream gate**, and zero drift makes this worse, not better, because zero drift reads as nothing to check. Four cheap defences:

- **Any resolved decision citing a doc or ADR by line range: actually read that range.** This alone would have caught it.
- **A decision that re-argues an existing behaviour rather than changing anything is the highest-risk kind** — it ships as prose, has no test, and no oracle can fail. Flag it for mandatory re-derivation.
- **Verify the mitigation, not just the risk.** A block's own Risks section with a named mitigation is a ready-made checklist. In that case the risk fired *through* its mitigation, which was itself the false claim.
- **You may keep a resolved decision while declining to assert a falsehood it rests on** — record the correction in the PR body rather than escalating. Ship-blocking a human for "your stated reason is wrong but your decision stands" is the wrong trade.

**Then enumerate what the block does *not* decide.** Drift-checking is by construction a check against what the block **says**, so its silence is invisible to this pass — and the more complete and well-evidenced the block is, the more confidently an executor will generalise from it into the gaps. For each decision that names a rule (a merge, an ordering, a degrade direction, a precedence), ask **which other component performs the same class of operation**, and whether the block says anything about it. Emit the unanswered ones as a short **"unspecified seams"** list, and pass it to `/plan` and `/build` as explicit *non-guidance*: *the design does not decide this; do not infer it from the adjacent rule; if you must choose, flag it as a deviation.* (A block with 13 evidenced decisions and zero drift still shipped a defect in its one unmentioned seam: the executor reused the document's only merge rule on the adjacent path, where it inverted the safe direction and made a stale watermark immortal.)

## Step 2 — Grill (using the `grill` + `domain-modeling` skills)

Run the interview: walk every branch of the decision tree, one question at a time (under board mode the independent forks batch to the canvas and only the dependent ones stay serial — the `grill` skill's split), each with your recommended answer; resolve dependencies between decisions before moving on.

**Every fork you put to the user is presented picture → scenarios → per-option walk** (the `grill` skill's *Presenting a fork* section owns the shape; this is where it is mandatory):

1. **The concrete full picture** of what the fork is about — the surface, today's behaviour, who calls it, what would change. Two option labels are not a question; the user cannot tell from them whether you are discussing the same thing they are.
2. **The scenarios this fork has to cover**, enumerated — the normal path plus the ones that discriminate between the answers (retry, concurrent edit, empty set, crash between two steps, replay).
3. **Each scenario walked per option** as a use case + timeline with an outcome line, diverging step marked. Where the fork has N options, do all three steps **per option**; where it is a yes/no, both sides get walked.

Write it under `grill`'s literal headings — **The Problem** / **Use Case** / **Options** / **Recommendation** — and **restate every reference at every mention** (`TV1-1234` (*what it is*), `R1` (*what it is*)), never a bare id. Bold the load-bearing claim in each paragraph so a skim of bold-only gives the fork and your recommendation.

This is not reserved for data-flow forks — it is how a fork is asked. Under board mode it is what goes **into the comment**: the terminal keeps the one-line map, the picture, scenarios and walks live on the anchored comment. Where every scenario walks identically across the options, there is no fork — resolve it yourself and record it as an autonomous decision.

While you interview:

- **Sharpen the language** — challenge terms against the glossary, propose canonical terms for fuzzy ones, stress-test relationships with concrete edge-case scenarios, and **cross-reference claims against the code**.
- **Update `CONTEXT.md` inline** the moment a term resolves (glossary only — no implementation detail).
- **Offer an ADR** only when a decision is hard-to-reverse **and** surprising **and** a real trade-off.

Continue until you reach genuine shared understanding — every pivotal fork resolved, no hand-waving.

## Step 2.5 — Critique the resolved design (using the `critique` skill)

Before writing it down, turn the lens on the design. The grill was *convergent* — it built the design *with* the user; the `critique` skill is *divergent* — it attacks the resolved position. Run `critique` (default `arch,ops` lenses) against the resolved decision tree and surface the verdict: the top weaknesses, the severity, and kill-or-continue.

- If critique lands a **fix that's clearly right**, fold it back into the design before writing the doc.
- If it surfaces a **genuine fork the grill missed**, drop back into Step 2 and resolve it.
- A weakness with **no good answer** is a risk — carry it into the design doc's *Risks* section rather than pretending it's solved.

Don't let this become a second grill; it's one focused adversarial pass on what's already decided.

## Step 3 — Write the design doc → `.work/design.md`

Write the resolved design to `.work/design.md` (create `.work/` if absent; it is gitignored and ephemeral). **Markdown + Mermaid** so it renders in an editor with a mermaid preview. Aim for a doc a teammate can review in one pass:

- **Problem & intent** — what we're solving, in the ubiquitous language.
- **The resolved decision tree** — each pivotal fork and the chosen answer, with the why.
- **Seams / flow** — a Mermaid diagram of the key flow (e.g. command → event → policy → …) and any new boundary the design crosses.
- **Test seams** — where the feature will be *verified*. Prefer existing seams to new ones; use the highest seam possible; minimize their number (ideal: one). Note a prior-art test to mirror for each. These become the slices' oracles in `/plan` — confirm them with the user before finishing.
- **Risks / the gate-less seam** — the riskiest part nothing automatically catches (this becomes the tracer bullet in `/plan`).
- **Unspecified seams** — what this design deliberately does *not* decide, so nobody infers it from the rule next door. An unspecified seam **adjacent to a specified one** is the highest-risk place in the document, because the stated rule is exactly what will be reused there; read-modify-write pairs, the client and server halves of one document, and the read and write paths over one piece of state are the recurring shapes.
- **Scope boundaries** — explicit in/out, and any follow-ups to spin off.
- **Provenance / how to re-derive** — the commands that produced this design's numbers and claims. Cheap to write, it converts every empirical finding from a claim into something the next context can re-run, and it doubles as the verification recipe at `/verify-build` (where, resumed cold, it is reliably the most useful section in the doc).

This doc is **ephemeral** — it is the review surface and the input to `/plan`. Its durable conclusions live in the glossary/ADR updates (committed) and, later, the PR body. Do **not** commit `design.md`.

## Step 4 — Hand off (self-containment gate first)

**Answer this before handing off: "could a fresh session holding only this repo and `.work/design.md` run `/plan` without loss?"** Enumerate what this session produced — files created, commands run and their outputs, counts and lists derived, external state touched — and for each confirm it is **in the doc**, **committed**, or **explicitly declared re-derivable with the command to re-derive it**.

Two rules that fall out of it:

- **Any artifact the design names as a test seam, gate, or tracer-bullet instrument must be committed, not left untracked.** A design that depends on an uncommitted file is neither reviewable nor resumable — `git add` it, or state plainly that the first slice creates it. (One doc asserted its primary test harness was "already built and run": true in exactly one working directory, and `/plan` in a worktree would have sliced around an instrument that was not there.)
- The same boundary exists at `/plan` → `/build` → `/verify-build`: **a pipeline step may not hand off state that lives only in its own context.** Each step runs in a separate session and `.work/` is gitignored, so the failure **scales with how good the session was** — the more empirical spikes it ran, the more it produced that the doc format never asked for.

Then summarise: the resolved design, any `CONTEXT.md`/ADR updates made, and the open risks. Then:

> Review `.work/design.md`. When it's right, run `/plan` to cut it into vertical slices.

## Principles

- The grill is the engine; the docs are a side effect, not the goal. Don't let doc-writing slow the interview.
- `CONTEXT.md` updates are durable and committed; `design.md` is ephemeral.
- Speak the ubiquitous language — if the design needs a term the glossary lacks, that's a term to resolve and record.
