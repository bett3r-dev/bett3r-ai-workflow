# esas-design fixtures

Host repos for `scripts/test-esas-design.sh`, which runs `/design`'s board-mode
preflight — extracted verbatim from `commands/design.md` — inside a copy of
each one.

Unlike the `esas-pending` fixtures, these are **not** store output and do not
need to be: the preflight stats file names and reads `.mcp.json`; it never
parses a graph or a design. What has to be faithful here is the *shape of a
host repo* — a `.esas/` beside a `.mcp.json` beside a `package.json` — so the
`graph.json` and `diagnostics.json` are minimal but real-shaped, and the
`.mcp.json` files carry other servers alongside (or instead of) the esas entry,
because a repo with exactly one MCP server is not the case that breaks a
detector.

**One input these directories cannot own: `PATH`.** The preflight's first line
reports which build of the plugin the session loaded, read off the version-keyed
cache directory on `PATH` — a fact about the session, not about the checkout, so
no fixture can carry it. The suite scrubs plugin-cache entries out of `PATH`
before every run (`CLEAN_PATH`), which is what makes the report identical on CI
and on the one machine where such a directory is always present: the machine of
whoever is editing this plugin. The `loaded` branch is then asserted once against
a synthesized entry, spelled with the marketplace segment in full, because the
marketplace and the plugin share a name and that doubling is the trap the glob
has to survive.

| fixture | what it is | the verdict it pins |
|---|---|---|
| `no-esas` | a repo the extractor never ran in — or a fleet worktree | `esas_dir: absent`, and nothing is probed below it |
| `no-graph` | `.esas/` exists, the extractor has not produced a graph | `graph: absent` — reality is not on disk yet |
| `no-mcp-json` | extracted, and the repo has no `.mcp.json` at all | `mcp: absent` — the entry has to create the file |
| `unregistered` | extracted, `.mcp.json` carries other servers but no esas | `mcp: unregistered` — the case that must not read as absent |
| `board-ready` | extracted, registered, no design layer yet | the clean board-mode start |

Two more cases are composed at run time rather than committed:

- **a session already in progress** — `board-ready` plus the `design.json`,
  `ops.jsonl` and `.claude-cursor` from `scripts/fixtures/esas-pending/pending/`,
  which *are* real `@bett3r-dev/esas-store` output. Borrowed rather than copied:
  one set of store bytes in this repo, with one provenance story.
- **a board on the port** — a stub HTTP server answering `/api/esas/status`.
  Its body matches the board's `JSON.stringify(status)` byte for byte
  (compact separators, `{repoPath, gitSha, lastSeq}`), because a stub that
  merely looks like the real answer is how a reader passes its own tests and
  fails against the thing it reads. The suite also drives it in a
  pretty-printed variant and through a symlinked checkout — the two spellings
  of "the same repo" that would otherwise surface as a false `other-repo` and
  send the user hunting for a rival board that does not exist.

The `.mcp.json` entries name `/Users/dev/…` paths on purpose: they are read as
text by a substring match on `esas-mcp/bin/esas-mcp.mjs`, and nothing here
should resolve on the machine running the suite.
