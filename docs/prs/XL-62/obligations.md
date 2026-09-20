# Obligations placed by XL-62's fold-back on sibling tickets

**Target: XL-80** (new ticket, filed and designed this run — decisions.md Part 8, R10-R12; cross-repo
census reach for `xp-resolved-by-census.ts`).

- **Obligation:** XL-80's per-root census report is only complete once XL-62 ships (fork F1, resolved
  to Option A / decisions.md R1): XL-62 adds a sixth counted value, `recommendation`, to
  `packages/xp-mcp/src/resolved-by.ts`'s `RESOLVED_BY_LITERALS` / `ResolvedByKind` /
  `ResolvedByCensus`. Until XL-62's xp-layer half lands, any `resolved_by: recommendation` line a
  plugin PR emits reads as `invalid` under the pre-XL-62 grammar (this is also why XL-62 itself
  requires the xp-layer parser PR to land BEFORE the plugin renderer PR — decisions.md R3 — so the
  transient window is a no-op rather than a false `invalid`).
  **Why this belongs to XL-80 and not XL-62:** XL-80 aggregates and reports the census across
  multiple repo roots; if XL-80 builds or ships before XL-62's xp-layer half lands, its per-root
  aggregate is running against a five-kind (not six-kind) grammar and its report is silently
  incomplete rather than wrong — a build lane on XL-80 must sequence after, or explicitly gate on,
  XL-62's xp-layer PR.

No other sibling ticket in this run is obligated by XL-62's resolution.
