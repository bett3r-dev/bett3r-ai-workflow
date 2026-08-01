# esas-pending fixtures

Every `.esas/` here was written by the **real `@bett3r-dev/esas-store`** (the
esas repo, `packages/esas-store`) — the hook reads two files written by another
repository, and a fixture that merely *looks* like store output would let the
hook pass its own tests and fail in production. So the generator drives the
store's public API (`propose`, `markSynced`, `appendOp`) and copies what lands
on disk.

Two exceptions, disclosed in the table below by their `writerSha: fixturesha`:
the `position` and `resolve` payloads are hand-built, because the store has no
verb for either yet (they belong to the board middleware and to D4's comment
surface). Their *framing* — seq, attribution, line format, append path — is
still the store's; only the payload object is written by hand. The
`corrupt-cursor`, `torn-cursor-tail` and `cursor-out-of-range` cursors are
likewise damaged by hand, which is the entire point of them.

That is why they carry `design.json` and `design.json.bak` too. The hook never
reads them; they are here because a faithful fixture is one the store produced,
not one trimmed to what the reader happens to want.

Regenerating them needs a checkout of the esas repo; they are committed so the
suite runs anywhere, including CI.

| fixture | cursor `seq` / `byteOffset` | `ops.jsonl` size | what it is |
|---|---|---|---|
| `synced` | 2 / 748 | 748 | `byteOffset == size` — the cheap gate says nothing changed |
| `pending` | 1 / 376 | 1504 | seqs 2–4 unread; 2 and 4 are human semantic, 3 is ai |
| `layout-only` | 1 / 376 | 1111 | seqs 2–4 are two `position` writes and a `lock-takeover` |
| `ai-only` | 1 / 376 | 1120 | unread semantic ops exist, but they are Claude's own |
| `stale` | 6 / 2280 | 760 | the feed was deleted and restarted under the cursor |
| `corrupt-cursor` | torn write | 1504 | `{\n  "seq": 1,\n  "byteOff` — half a cursor |
| `no-cursor` | — | 1126 | nothing has ever synced |
| `empty-feed` | — | 0 | `.esas/` scaffolded, feed still empty |
| `nested-author` | 1 / 376 | 1063 | seq 2 is an **ai** op whose payload says `"author":"human"` |
| `torn-tail` | 1 / 376 | 784 | a writer killed between the last op and its newline |
| `torn-cursor-tail` | 1 / 376, truncated at byte 60 | 1504 | both contract fields perfect, document unparseable |
| `cursor-out-of-range` | 4 / 2^63 | 1504 | a `byteOffset` no shell's `test` can compare |

Three of these are the states a naive reader gets wrong, and each cost is
asymmetric:

- **`stale`** is not an exotic corruption — it is the *default* state at the
  start of every unit of work after the first. `.esas/` is ephemeral and deleted
  after merge, while `.claude-cursor` can outlive the feed it bookmarks and then
  points far past a feed that begins again at seq 1. A reader without the
  staleness rule goes silent exactly when a human edit is pending.
- **`nested-author`** is why the count is read brace-depth-aware. `author`
  appears at the top level of an op *and* inside its payload; an ai op that
  resolves a human's comment carries `"author":"human"` in the payload, and a
  substring match files Claude's own write as a pending user edit.
- **`corrupt-cursor`** still contains a syntactically perfect `"seq": 1` line.
  The store's `readCursor` JSON-parses the whole file and requires *both*
  contract fields, so it reads this as unsynced; a reader that trusted the
  surviving half would run ahead of every other reader of the same file.
- **`torn-cursor-tail`** is the same hazard's larger half, and it is the one
  that caught a shipped defect. The cursor is written
  `{ seq, byteOffset, writerId, ts }`, so a truncation in the `writerId`/`ts`
  tail leaves *both contract fields perfect* while the document is
  unparseable. A reader that checked only "both fields present" disagreed with
  the store at **94 of the 126** truncation points of the `pending` cursor,
  every time by claiming synced where the store says unsynced. `corrupt-cursor`
  alone did not catch it: at 24 bytes it sits inside the 30-byte prefix where
  the two agree. The hook now requires the document to be *balanced*, which no
  prefix of a JSON object can be — verified at all 126 points × 3 shells.
- **`cursor-out-of-range`** is not about JSON at all. `test` does not return
  false on an operand past 2^63-1: it **fails**, with a diagnostic. Behind
  `&& cursor_seq=0` a failed test is indistinguishable from a false one, so the
  staleness rule silently did not fire *and* the shell printed to stderr in
  front of the user's prompt.

## Regenerating

The generator lives with this slice's working notes rather than in this repo —
it imports the esas store by absolute path, which only resolves on a machine
that has both checkouts. To rebuild, run a script that drives
`createEsasStore({ repoPath })` per fixture and copy the resulting `.esas/`
directories here. Keep the expected values in `scripts/test-hooks.sh` in step:
the counts and seq ranges there are derived from these bytes.
