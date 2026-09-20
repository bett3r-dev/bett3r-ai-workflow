<!-- design-multi:resolved:v2 status=ready base=793270ca9e074cb7c72e56d8559284144dfdcfa2 run=design-multi-XL-56-57-58-59-60-61-62-63 -->
## Resolved Design (design-multi)

`design-multi:resolved:v2 status=ready base=793270ca9e074cb7c72e56d8559284144dfdcfa2 run=design-multi-XL-56-57-58-59-60-61-62-63`

**Done is verifiable by:** After `/design` Step 4 (`cross-repo bett3r-ai-workflow@e4b8ee8:plugins/bett3r-ai-workflow/commands/design.md:179`) on a work item whose `map.json` holds at least one decided fork, the **committed** `docs/prs/<item>/design.md` carries exactly one column-0 `resolved_by:` line per decided fork (using the five-value grammar: `atom:<id> | neotoma:<entity_id> | human | code | recommendation`); `node --import tsx ./scripts/xp-resolved-by-census.ts` over that corpus reports `invalid: 0` and a non-zero total whose per-kind counts equal the map's decided counts under the R1 mapping. **Original AC, preserved verbatim (proved unsatisfiable at BASE — see below):** *"a /design-multi or /design run produces drafts whose every resolved fork carries `resolved_by`, and XL-48's census script parses them."* The `/design-multi` half of this cannot ever pass: `/design-multi` writes its ticket block via `render_jira` into Jira (`cross-repo bett3r-ai-workflow@e4b8ee8:plugins/bett3r-ai-workflow/commands/design-multi.md:96`), never into a committed `design.md`, and the census reads only `<root>/<work-item>/design.md` at its latest commit (`packages/xp-mcp/src/resolved-by.ts` `runOf`). Only the `/design` (single-ticket) path can ever be counted.

## Resolved decision tree

<!-- map-tree:v1 ticket=XL-62 gen=1 src=sha256:b849b760460399ea6f4731b2181387d6c6625cd7914c59128edd3d76fbe643ac out=sha256:965b21a2fa2a8c6ba8c4304751b3a2ba9622439836e18ea2272cfe832478eb7e -->
`map-tree:v1 ticket=XL-62 gen=1 src=sha256:b849b760460399ea6f4731b2181387d6c6625cd7914c59128edd3d76fbe643ac out=sha256:965b21a2fa2a8c6ba8c4304751b3a2ba9622439836e18ea2272cfe832478eb7e`
- **XL-62-F1 — What resolved_by value a decided fork gets when the map carries no resolvedBy: Fall back to the source literal, minting the literal `recommendation`** — decided(recommendation)
- Why: It is the only option that keeps a distinction the flow already records: source has had three values since esas minted the enum, and COUNT_KEYS at map-tree.py:55 already counts recommendation separately in the verdict line, so the writer side has always treated it as its own thing. Collapsing it at the census boundary (B, D) destroys exactly the signal XL-24 was built to read, and C leaves the census structurally unable to produce a ratio. The cost is one reading call this lane may not make for the owner: whether ADR-064 section 2's 'sixth census counter' clause bars A. My reading is that it does not - the sentence's subject is the `open/negative` half and its stated harm is about ABSENCE, not arity, while recommendation is a positive fact about a fork that IS resolved and DOES produce a line. But that is a reading of someone else's words; if the owner reads it the other way, C is the fallback, not B or D.
- Rejected — Fall back, but map recommendation to the existing literal `human`: design-multi.md:74 says in terms 'silence is not assent, and a default named is not a decision laundered'; B is that laundering, and it collides with ADR-064 section 5, which reserves the literal human for 'a person answered in this session'. (cross-repo `bett3r-ai-workflow@e4b8ee8:plugins/bett3r-ai-workflow/commands/design-multi.md:74`, ADR-064 section 5)
- Rejected — Emit a line ONLY where status.resolvedBy is present: The documented invariant at `packages/xp-mcp/src/resolved-by.ts:34-36` ('a draft that records N forks carries N such lines') becomes false and must be rewritten; the census loses its denominator, so XL-24 and XL-52 must take the fork count from map.json instead. Realistically the census stays at or near zero until recall runs live. (`packages/xp-mcp/src/resolved-by.ts:34-36` (BASE))
- Rejected — Fall back, mapping recommendation to the existing literal `code`: Asserts the code settled forks the code did not settle - the same laundering as B pointed at a different literal - and it corrupts the one counter meant to measure code-answerability.

- **XL-62-F2 — Does the xp-layer half of XL-62 exist at all, and does this stay one ticket or split into two: One ticket, two PRs, xp-layer (parser) lands FIRST** — decided(recommendation)
- Why: The cross-repo conformance check is the ticket's single real risk and it only exists when both halves are in view; splitting it across two tickets is exactly how a two-repo grammar drifts. Parser-first makes the transient window a no-op instead of a false `invalid`. Conditional on F1 != C; if F1 = C this fork is moot.
- Rejected — One ticket, two PRs, the plugin lands first: Strictly worse than A for no gain.
- Rejected — Split into two tickets - XL-62 keeps the renderer, a new ticket owns the literal: Costs a new Jira key and a second design, and splits the cross-repo conformance check (test seam 2) across two tickets that cannot be verified independently - that seam spans both repos by construction.

- **XL-62-F3 — Should render_md surface an open fork's reason at all: Render it inline, mirroring the moot branch: OPEN - recommended: <label> (<reason>)** — decided(recommendation)
- Why: It costs three lines, it is exactly symmetric with the moot branch two lines above it in the same function (map-tree.py:140), and it makes a fact ADR-064 deliberately created - the typed open reason - visible to the person reading the design, which is the only thing ADR-064 left undone about it. It is distinctly NOT the open_reason: line section 2 rejected: no column 0, no parse, no counter.
- Rejected — Render nothing (status quo): Zero risk of being read as re-litigating ADR-064 section 2, but the recorded reason stays invisible in every artifact a person reads - a slow way to discover that lanes have stopped recording it correctly. Nothing in either repo reads open.reason today except test-design-map.sh.
- Rejected — Render it, and additionally warn when the value is outside the three-code vocabulary: Puts a vocabulary judgement in the renderer, which is the wrong layer - validation belongs in design-map validate - and it is scope XL-62 was not filed for.

- **XL-62-F4 — Is cross-repo census reach in XL-62's scope: Out of scope, but file the follow-up now and cite it from the Risks section** — decided(owner)
- Why: A's reasoning is right and still exact at BASE - the reader's reach belongs to the reader - but A as it stands ships a system whose headline metric reads zero BY CONSTRUCTION, with the explanation living only in a design doc nobody will re-read. ADR-064's own Consequences already warn about a narrower version of the same trap ('the oracle reads an empty corpus and reports a confident zero'). One filed follow-up converts a silent-zero trap into a tracked gap for the cost of a ticket.
- Rejected — Out of scope - XL-62 is the writer only: no reason recorded
- Rejected — Add --repo / multi-root to the census driver inside XL-62: Makes XL-62 a cross-repo PR pair AND puts it inside `scripts/xp-resolved-by-census.ts`, a file XL-48 shipped and XL-24 reads; it must also answer what 'last N' means across repos with independent commit histories, which is a real design question of its own. Materially enlarges a ticket that has just been correctly shrunk.

- **XL-62-F5 — May the store-agnostic plugin hardcode a consumer's grammar term (promoted by self-critique): Hardcode resolved_by: (and, under F1=A, the literal mapping) in map-tree.py** — decided(recommendation)
- Why: B is the architecturally correct answer and is also a different ticket - a host-configured renderer is new machinery with its own failure mode, and XL-62 was filed as a ~20-line writer. What makes A acceptable is WRITING THE COUPLING DOWN in plugin ADR-007 or a new plugin ADR - that it is an accepted, named exception to ADR-003, that test-flow-seams.sh's table does not cover map-tree.py, and that a second consumer is the trigger to make it host-configured. That costs a paragraph. What makes A dangerous is shipping it silently past a guard that happens not to cover this file.
- Rejected — The key and the source-to-value mapping come from the host's `.claude/bett3r-ai-workflow.json`: ADR-003-true and symmetric with work-docs-path.py, which already reads that config - but it is new machinery with its own failure mode: map-tree.py reads no config at all today (json.load only on the map itself, :324), it would gain a dependency on the host repo root, and a missing declaration silently emits nothing, which is the confident-zero failure ADR-064 already warns about for --root.
- Rejected — Hardcode the key resolved_by: but emit only status.resolvedBy verbatim (equals F1 = C): no reason recorded
`/map-tree:v1`
<!-- /map-tree:v1 -->

### Seams / flow

**Every bare `map-tree.py`, `design-map.py`, `commands/design.md`, `commands/verify-build.md`,
`scripts/test-*.sh`, `scripts/fixtures/map-tree/*` and `plugins/bett3r-ai-workflow/.claude-plugin/
plugin.json` reference below is `cross-repo bett3r-ai-workflow@e4b8ee8:plugins/bett3r-ai-workflow/
<path>` (this repo's own `git cat-file -e` cannot and does not resolve them — that IS the proof of
label, per Task 4). `packages/xp-mcp/...` and `docs/adr/...` paths are this repo (xp-layer) at BASE.**

`/design` Step 3 lane (`commands/design.md:141`) writes `status.resolvedBy` (or leaves it absent) on
the map's decided branch → `map-tree.py` `render_md` (`:134-156`) is the ONLY renderer that emits the
column-0 `resolved_by:` line, using R1's fallback mapping when `resolvedBy` is absent, and (per P8)
also renders an open fork's typed `reason` inline, symmetric with the existing `moot` branch → the
generated region is committed in the same commit as `map.json` by `/design` Step 4
(`commands/design.md:179`) or `/verify-build` 5a2 (`commands/verify-build.md:152`) → xp-layer's
`censusResolvedBy` (`packages/xp-mcp/src/resolved-by.ts:129`, this repo at BASE) parses the committed
`design.md` and counts kinds, gaining `recommendation` as a sixth value (R1). `render_jira`
(`map-tree.py:191`) emits neither the `resolved_by:` line nor the rendered `reason` — Jira output is
out of the census's reach by construction, and XL-80 (cross-repo census reach, R6) reports per-root,
never merging across roots.

### Test seams

1. `scripts/test-map-tree.sh` + extended fixtures (plugin repo root): a map carrying a decided fork
   of each `source` (`owner`, `code`, `recommendation`), a decided fork carrying `resolvedBy`, an
   `open` fork with a `reason`, an `open` fork without one, and a `moot`. Assert exact column-0 lines
   and counts; read the `MAP-TREE:v1` verdict line, never the exit code. Must pass under `sh`, `dash`
   and `bash` (CI runs all three).
2. The cross-repo conformance seam (the ticket's single real risk): run `censusResolvedBy` over the
   rendered fixture text from seam 1 and assert `invalid: 0` with kind counts equal to the fixture's
   decided counts (five kinds including `recommendation`). A checked-in copy of the rendered fixture
   plus a plugin-side byte-equality assertion is the drift signal. Per R3, the xp-layer parser PR
   (adding the `recommendation` literal to `RESOLVED_BY_LITERALS`) lands FIRST, so this seam never
   observes a plugin-emitted `recommendation` line the parser does not yet accept.
3. The `GEN` test: an existing `gen=1` region classifies `stale` after the bump to `GEN = 2`
   (`scripts/fixtures/map-tree/legacy-v2-block.md` is prior art for a stale-region case).
4. End-to-end negative→positive: `node --import tsx ./scripts/xp-resolved-by-census.ts` in xp-layer
   reads all-zero across five counters at BASE (verified 2026-09-18/19, 21 runs). After the first
   `/design` Step 4 pass with the new renderer, the same command must read non-zero with `invalid: 0`
   — report only after it has actually been run.

### Risks

- **Regeneration noise from `GEN = 2`.** Every committed `map-tree:v1` region on every branch reads
  `stale` at once and is rewritten by the next `/design` or `verify-build` pass — including this
  wave's own ticket blocks, rendered by the `GEN = 1` renderer at `e4b8ee8`. Correct behaviour, not a
  defect.
- **The R1 risk — read this before overturning nothing else in this block.** Minting the literal
  `recommendation` for a decided fork with no `resolvedBy` adds a SIXTH value to `ResolvedByCensus`
  (today `atom, neotoma, human, code, invalid`). ADR-064 §2's rejection clause reads, word for word:
  *"Rejected: an `open_reason:` line **and a sixth census counter** — that reopens the module
  ADR-053 §10 has just ratified."* Whether that phrase bars any sixth counter, or only the
  open/negative-half counter it was written about, is **genuinely ambiguous in the ADR text**. This
  run adopted the **NARROW reading** (scoped to the open/negative half: the argument is about
  *absence* — "a census over text can only count lines that exist" — not about *arity*; `recommendation`
  is a positive fact about a fork that IS resolved and DOES produce a line; `COUNT_KEYS`
  (`map-tree.py:55`) already counts `recommendation` separately in the verdict line, so the writer
  side has always treated it as its own thing). Under the **BROAD reading**, R1 is exactly the sixth
  counter the ADR forbids, and the fallback should instead map `recommendation → code` in **Option C**
  of the original fork walk (emit a line only where `resolvedBy` is present — no xp-layer change at
  all, no new literal, no ADR-053 amendment). **This is the single most overturnable decision in this
  block. A reviewer who reads §2 broadly should flip R1 to Option C, not patch around it.**
- **Two-repo grammar drift**, mitigated but not removed by test seam 2 (a conformance fixture catches
  drift at build time, not write time, and only if someone runs both sides).
- **The census cannot reach other repos' designs** (`xp-resolved-by-census.ts` resolves `--root`
  against `REPO_ROOT`). XL-62 shipping does not by itself move XL-24's numbers — most `/design` runs
  commit in teselly and pv3. Filed as XL-80 (R6), out of this ticket's scope.
- **`open.reason` is free text**, not an enforced enum (schema: `{"type":"string","minLength":1}`).
  P8 renders whatever string is there, including one outside the three documented codes
  (`store-unreachable`, `no-atoms-matched`, `only-pending`). Recorded as a risk, not designed here —
  tightening it is a schema change to a file XL-67 shipped and is out of scope.
- **`resolvedBy` is dropped on an owner overturn** (`design-map.py:1189-1190` carries it forward only
  where `prior["option"] == answer["pick"]`). An overturned fork's line silently falls back to the
  `source` literal; the census's `atom` count drops by one with nothing red. Inherited, not designed
  here.
- **Coupling accepted by R2, not enforced by any guard.** `map-tree.py` hardcodes the xp-layer term
  `resolved_by:` (and, under R1, its five-value mapping) inside a plugin whose ADR-003 keeps the base
  flow store-agnostic. `scripts/test-flow-seams.sh`'s coupling table covers seven seam files and does
  **not** include `map-tree.py` — the guard is silent here by construction, not because the coupling
  was checked and cleared elsewhere. R2 requires a plugin ADR paragraph naming this coupling as a
  knowingly accepted debt, not a silent violation.

### Unspecified seams (for the build lane)

- The exact rendered spelling of the blank lines around the new `resolved_by:` line and the rendered
  `reason` text — `render_md` builds a flat list of strings; the build lane decides the precise
  insertion index relative to the `Why:` line. `out_hash` normalises leading/trailing blanks only, so
  an interior difference is a real byte difference and every fixture hash must be regenerated with it.
- Whether the `MAP-TREE:v1` verdict line gains a `cited=<n>` (or similar) counter. `COUNT_KEYS`
  (`map-tree.py:55`) already carries `recommendation`; adding a new key is a verdict-line contract
  change belonging to whoever owns that line — not designed here.

### Scope

**IN (bett3r-ai-workflow @ `e4b8ee8`):**
- `plugins/bett3r-ai-workflow/scripts/map-tree.py`: `render_md` (`:134-156`) emits the column-0
  `resolved_by:` line under the decided branch (`:151-152`) using R1's fallback mapping, and (P8)
  renders an open fork's `reason` inline in the open branch (`:146-150`), symmetric with the `moot`
  branch (`:140`); `GEN` (`:46`) bumped 1 → 2.
- `scripts/fixtures/map-tree/design.map.json` — extended with a `code`-source decided fork, a decided
  fork carrying `resolvedBy`, and an open fork carrying a `reason`.
- `scripts/test-map-tree.sh` — assertions on exact column-0 lines and counts, via the `MAP-TREE:v1`
  verdict line, under `sh`/`dash`/`bash`.
- `plugins/bett3r-ai-workflow/.claude-plugin/plugin.json` — version bump required, `0.88.0` → next
  (`scripts/check-plugin-version-bump.sh:122`). Direction is not judged by the gate on a long-lived
  branch — check against `origin/master` by hand before opening the PR.

**IN (xp-layer @ BASE), lands SECOND per R3:** `packages/xp-mcp/src/resolved-by.ts:54, :62, :105-112`
(`RESOLVED_BY_LITERALS`, `ResolvedByKind`, `ResolvedByCensus`) gains the `recommendation` literal,
plus its test, and the ADR-053 §10 grammar line is amended to five values.

**OUT:** cross-repo census reach (filed as XL-80, R6); `atom:` values and their producer (XL-67,
Done); the Neotoma sidecar (XL-70, Done); `record_decision` call-site wiring (XL-70, Done); any
Jira-dialect emission (`render_jira`, `map-tree.py:191`); `design-map decisions` output (the census
never reads `decisions.md`); host-configuring the `resolved_by:` key or mapping (F5 Option B —
different ticket); tightening `open.reason` to an enum (a schema change to a file XL-67 shipped).

**AC/rejected-option intersection check:** the rewritten "Done is verifiable by" names the `/design`
(single-ticket) path only. The ORIGINAL AC's `/design-multi` clause is not "resolved silently" by any
option above — it is stated as unsatisfiable, governing only the reader's expectation, not the
renderer surface (which is `md`-dialect only, per the withdrawn D4/A4 auto-decision carried from the
draft).

### File overlap vs siblings

- No sibling in this wave touches `map-tree.py`, `test-map-tree.sh`, or any other
  `bett3r-ai-workflow` plugin file. XL-62 is the only plugin unit in this run.
- `packages/xp-mcp/src/resolved-by.ts` — XL-62 touches `:54, :62, :105-112`. XL-52 (separate, prior
  work) adds a census alongside `censusResolvedBy` in the same file: disjoint lines, merge-order only.
  XL-48 (Done) owns the line contract at `:31-50` and must stay stable.
- `docs/adr/ADR-053-the-facade-composes-two-stores-by-section-and-identity-stays-with-the-harness.md:24` — XL-62 amends one line; ADR-064 already amended §10 once. Re-check for a
  sibling amendment before landing (OBLIGATION-3 applies to numbering, not this line-edit).
- XL-24 reads the census kinds for `xp.fork_outcomes.resolved_by`; its vocabulary changes to five
  kinds because of R1.
- XL-80 (new ticket, R10-R12): depends on this ticket shipping the sixth (`recommendation`) value
  before its per-root report can be complete. See obligations.md.

### Glossary/ADR deltas

- **ADR-053 §10** (`docs/adr/ADR-053-the-facade-composes-two-stores-by-section-and-identity-stays-with-the-harness.md:24`) — delta: specified, deferred to build. The grammar line
  becomes `resolved_by: atom:<id> | neotoma:<entity_id> | human | code | recommendation` at column 0,
  with `recommendation` meaning "applied on the drafted recommendation without an owner answer".
  Amends an existing ADR; **reserves no new number** (next free is ADR-067, allocated to XL-79 per
  decisions.md Part 6 P-ADR067 — XL-62 does not take a number).
- **Plugin ADR-007 amendment, or a new plugin ADR (plugin repo's own numbering — NOT this repo's
  ADR-067)** — delta: specified, deferred to build, per R2. Must record: (a) the md projection carries
  one machine-read line per decided fork, valued from `status.resolvedBy` verbatim where present, else
  the R1 fallback; (b) any render change adding or removing a machine-read line bumps `GEN`; (c) that
  `map-tree.py` hardcodes one xp-layer-defined grammar term (`resolved_by`) as a knowingly accepted
  exception to plugin ADR-003 (store-agnostic base flow), because `scripts/test-flow-seams.sh`'s
  coupling table does not cover `map-tree.py` (`COUPLING_SEAM_FILES`); and (d) a second consumer
  repo wanting a different key/vocabulary is the named trigger to make this host-configured instead.
  Waits on: the plugin PR being scoped (R3 says xp-layer parser lands first; this ADR note ships with
  the plugin PR).
- **ADR-064 — no amendment.** The R1 risk paragraph above is the record of the ambiguity in ADR-064
  §2's text; this run resolved it (narrow reading) rather than amending the ADR itself.

### CC1 re-pricing

Per decisions.md Part 5: **unaffected by CC1.** P8 (render an open fork's `reason`) and R1/R2/R3
(the flow-plugin renderer decisions) act entirely inside the plugin's md projection, independent of
xp-layer recall traffic — CC1 (the idle experience layer) does not re-price any part of this ticket.
