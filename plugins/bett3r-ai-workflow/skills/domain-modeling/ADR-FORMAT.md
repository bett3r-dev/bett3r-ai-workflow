# ADR Format

> Adapted from Matt Pocock's `domain-modeling` skill.

## Location & numbering — match the repo

**Detect the repo's existing ADR convention and follow it** — do not impose a new one. Scan for an existing ADR directory (commonly `docs/adr/`, `docs/development/adr/`, or `docs/decisions/`) and copy its location and filename pattern.

Only if the repo has **no** ADRs yet, default to **`docs/adr/ADR-NNN-slug.md`** — the spelling the rest of this plugin renders into every host repo (`vertical-slicing`'s `slices.yaml` schema, `verify-build`'s PR-body template). This rule fires exactly once per repo, on the *first* ADR, and every later ADR inherits whatever it produced by "match what's there" — so a default that disagrees with the templates sets a convention the repo keeps forever, and one the flow's own artifacts then fail to match. The three must agree; if the zero-padded form is ever preferred, both templates change too. Create the directory lazily — only when the first ADR is needed.

**Never take the next number from a directory listing.** A listing shows only numbers that reached *your* branch, and numbers on unmerged siblings, open PRs and long-lived stacks are already claimed — invisible and taken. Scan every ref:

```sh
git log --all --name-only --pretty=format: | grep -oE 'ADR-[0-9]+' | sort -u | tail -5
```

and go above that. The collision is **silent**: different slugs mean different filenames, so nothing conflicts, the merge is clean, and both land. It is not a parallelism artifact either — two sequential sessions on two long-lived stacks produce it just as readily, and one repo's namespace reached 22% duplicated numbers this way. Duplicates break every inbound `ADR-0NN` citation permanently, and renumbering after merge is not a cleanup but a decision about breaking references — so the cheap moment is before the number is used. Under a fleet, the orchestrator allocates numbers rather than lanes self-numbering; `/verify-build` re-checks uniqueness **against the merge target** regardless, since a number can be claimed between design and merge.

Prefer **amending an existing ADR** where one already covers the ground, and release a reserved number you did not use.

## Template

```md
# {Short title of the decision}

{1–3 sentences: the context, what we decided, and why.}
```

An ADR can be a single paragraph. The value is recording *that* a decision was made and *why* — not filling out sections.

## Optional sections

Include only when they add genuine value (most ADRs won't need them):

- **Status** (`proposed | accepted | deprecated | superseded by ADR-NNNN`) — when decisions get revisited
- **Considered Options** — when the rejected alternatives are worth remembering
- **Consequences** — when non-obvious downstream effects need calling out

## When to offer an ADR — all three must be true

1. **Hard to reverse** — the cost of changing your mind later is meaningful.
2. **Surprising without context** — a future reader will look at the code and wonder "why on earth did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons.

If easy to reverse, skip it — you'll just reverse it. If unsurprising, nobody will wonder. If there was no real alternative, there's nothing to record.

### What qualifies

- **Architectural shape.** "The write model is event-sourced; the read model projects to Postgres."
- **Integration patterns between contexts.** "Ordering and Billing communicate via domain events, not synchronous HTTP."
- **Technology choices with lock-in.** Database, message bus, auth provider, deployment target — the ones that would take a quarter to swap.
- **Boundary & scope decisions.** "Customer data is owned by the Customer context; others reference it by ID only." The explicit *no*s are as valuable as the *yes*es.
- **Deliberate deviations from the obvious path.** "Manual SQL instead of an ORM because X." Stops the next engineer from "fixing" something deliberate.
- **Constraints not visible in the code.** Compliance, latency budgets, partner-API contracts.
- **Rejected alternatives when the rejection is non-obvious.** So nobody re-proposes it in six months.
