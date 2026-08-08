# Behavioral eval

Every other gate in `scripts/` asserts **presence**: a needle is still in the corpus, a link resolves, an artifact loads. Presence is the right assertion for a *move* — content relocating between files is exactly what those gates tolerate by design.

It is the wrong assertion for a *split*. Once a rule lives behind a pointer, the question stops being *"is the fact there"* and becomes *"is the pointer followed"*, and grep cannot answer it. That gap is the standing risk of every split in this repo, and it has been paid once already: `EVIDENCE.md` shipped linked from 5 artifacts while needed by 8, with every gate green, because both the link and its absence parse fine.

So this suite runs the artifacts. Each scenario puts a real headless session in front of a real artifact with a concrete situation and asserts on what the session **did** — which file it opened (read from the tool-use stream, not inferred from the prose) and which rule reached its answer.

```sh
python3 scripts/eval/run-behavioral-eval.py                  # full suite
python3 scripts/eval/run-behavioral-eval.py --dry-run        # free; prints prompts + assertions
python3 scripts/eval/run-behavioral-eval.py --runs 1         # cheap smoke
python3 scripts/eval/run-behavioral-eval.py --scenario provisioner-reached
```

## Not a CI gate, deliberately

It costs money (~$0.20 and 30–60s per session, so a full pass is a few dollars), needs an authenticated `claude` CLI, and is non-deterministic. Those three properties make a *required* check actively harmful. Run it when you split an artifact, and when you change one that carries a pointer.

## Two things the design depends on

**The tool call is the evidence, not the answer.** A session can produce a perfectly correct-sounding response out of its own priors while never opening the referenced file — and that response is not evidence the split works, it is evidence the model already knew. Only `must_open` discriminates.

**At least one scenario must be a negative control.** `base-check-not-delegated` asserts that a rule which deliberately did *not* move is still owned by the orchestrator. Without it the suite would report green on a corpus that had delegated everything away, because every "was the pointer followed" question would still answer yes.

## The suite can be wrong about what correct looks like

`provisioner-reached` originally asserted that `/start-multi` would state `build:all`. It opened `provisioner.md` 3/3 and failed the text assertion 3/3 — because after the split the orchestrator is *right* not to recite the agent's internals. That is what delegating means. The assertion had encoded a pre-split expectation.

The repair is the shape to copy: one scenario proves the pointer is followed, a second (`provisioner-states-its-own-rules`) proves the moved content works in its new home. When a scenario goes red, establish which of the two is failing before editing anything — and read `_calibration` on a scenario that carries one.
