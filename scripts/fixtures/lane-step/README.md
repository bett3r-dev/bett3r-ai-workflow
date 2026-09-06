# `LANE-STEP:` decoy corpora

Four transcripts for the parse rule in `agents/unit-lane.md`: **take the last
match, require it to start the line, require it to end the line, and require it
to be the final line.**

`LANE-STEP:`'s producer is a **model**, not a shell script, so its stdout also
carries its own prose *about* the marker. These fixtures are the shapes that
prose actually takes. Each one kills exactly one weakening of the rule, and each
claim below is executed as an assertion in `scripts/test-flow-seams.sh` (Seam C)
— run `sh scripts/test-flow-seams.sh` to measure them.

* `decoy-transcript.txt` — a mention of the bare token in a sentence, a full
  marker quoted **inline** in prose, an example line at column 0 **inside a
  fenced block**, and then the real line, last. This kills **first-match**: the
  first line-anchored match is the fenced `step=plan outcome=gate-red` example,
  and the first match anywhere is the inline `slices=9/9` one. The contract's
  rule returns `step=build outcome=success slices=3/3 commits=3`.

  It does **not** kill anchoring: a last-match-anywhere rule returns the same
  correct string here, because the real line is last either way. That is what
  `inline-marker-transcript.txt` is for.

* `trailing-prose-transcript.txt` — a well-formed marker at column 0 with the
  model carrying on afterwards. There is a match, and it is the last one, but it
  is not the final line, so the rule yields **no verdict** — which the reader
  reads as `infra` by absence (ADR-004). This kills the **final-line**
  requirement: without it, the model's afterthought reports `success`.

* `inline-marker-transcript.txt` — a well-formed marker embedded mid-sentence on
  the **final** line. It satisfies last-match and final-line, so only the
  column-0 requirement rejects it, and the rule yields **no verdict**. This
  kills **anchoring**, which is why the parser anchors in exactly one place
  (`token.match()`, no redundant `^` — a redundant anchor survives either
  mutation alone and so is held by nothing). The embedded marker says
  `outcome=gate-red`, so a rule that accepts it does not merely return different
  text: it reports the wrong verdict for a step that passed no gate.

* `same-line-prose-transcript.txt` — a well-formed marker at column 0 on the
  **final** line, with the model appending an aside **on that same line**, after
  the attributes. It satisfies last-match, final-line and column 0, so only the
  end-of-line requirement rejects it, and the rule yields **no verdict**. This
  kills the trailing `\s*$` clause — the half of ADR-004's *"give the token a
  shape that does not occur in prose about it"* that the other three fixtures
  are blind to. Without it the parser returns the whole line, aside and all, as
  the verdict: a `success` whose attribute list ends in unparseable prose.

  It is distinct from `trailing-prose-transcript.txt`, where the model's extra
  prose is on *subsequent* lines and the final-line requirement is what rejects
  it.
