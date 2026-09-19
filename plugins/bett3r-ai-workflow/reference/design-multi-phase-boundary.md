# The phase boundary (`/design-multi`)

Why `/design-multi` ends its context at the A/B and B/C boundaries instead of running a
design run to completion, and what each phase restarts from. Extracted from
[`commands/design-multi.md`](../commands/design-multi.md) under ADR-012's ceiling;
**normative** — read it before ending a phase. Its counterpart for fleet execution is
[`start-multi-tick-boundary.md`](./start-multi-tick-boundary.md).


**Each phase is a tick, not a session.** `/design-multi` ends its context twice — at the A/B and the B/C boundary — and each phase opens cold against the run dir, exactly as `/start-multi` ends at a wave (**The tick boundary**, [`start-multi`](../commands/start-multi.md)). Ending loses nothing because each phase's primary source is already on disk, and the two ends are the same **kind** of end: the context stops, nothing is carried over in memory, and the next phase reconstructs what it needs by reading it back from the run dir. The phase is read from `units[].step` and never stored: `pending`/`drafting` is Phase A running, every unit `critiqued` or `failed` is the A/B boundary, every unit `resolved` is the B/C boundary, and `written`/`done` is Phase C finished. A `phase:` key in `run.yaml` would be a second and staler answer to a question `units[].step` already answers.

1. **A/B.** Step 3's collect is the A/B boundary: print the A/B verdict and **end your context**. Phase B opens cold and restarts from `<run>/units/`, which is its primary source — each unit's `.ticket.md` snapshot, `.design-draft.md` and `.map.json` fragment, plus the run dir's `VERIFIED-FACTS.md` — and it re-runs `design-multi-subjects group <run>/units` over that directory rather than trusting a remembered grouping, an equal `subjectsFingerprint` reusing it silently as Step 4 says. A resumed sitting reads the owner's answers back with `read_db` over the `answers` collection, never from any surviving session state, as the [`design-map`](../skills/design-map/SKILL.md) skill's readback specifies; a sitting the owner half-answered and left therefore resumes from the artifact db with the answered forks already answered.
2. **The owner opens Phase B by hand, and no driver ever does.** The sitting is attended by definition, so a driver re-dispatching it opens a session nobody is sitting in and every remaining fork is taken on its recommendation with no one present to notice. That is enforced rather than requested: the A/B verdict is

        FLEET-STEP:v1 outcome=blocked-on blockedOn=awaiting-owner-sitting phases=1/3 units=<t>/<u>

    at column 0 with nothing after it, and `blocked-on` is what a reader of the line ([`lane-step`](../bin/lane-step), which prints the attributes and decides nothing) hands its driver as a stop, never a tick-again. `t` is the units at `critiqued` or `failed` and `u` every unit in `run.yaml`.
3. **B/C.** Step 4's completion — every open fork answered, applied or dependency-named — is the B/C boundary, and the B/C boundary ends this context the same way, printing `FLEET-STEP:v1 outcome=success phases=2/3 units=<t>/<u>`. Phase C opens cold and restarts from `<run>/subjects/` and `<run>/answers/`: the subject maps carry the resolved forks, and every answer the sitting took in the terminal is written as a row in `<run>/answers/` — in the shape Step 5.2 reads, `map: <S>` included — **before** this context ends, because a terminal answer that exists only in the sitting is the one thing this boundary can lose. Phase C re-verifies the pinned base anyway (Step 5.1), so a fresh context changes nothing it was not already going to re-derive, and its own end prints `phases=3/3`.

This boundary is `/design-multi`'s, and **nothing here licenses a `/merge-multi` yield by analogy** — that command's length is its unit count and a per-unit yield on this pattern is possible, but it is deliberately undesigned; inventing one from this section would be inventing a boundary nobody chose.

## run.yaml

```yaml
runId: design-multi-...
groundedBaseSha: <pinned origin/default>          # start-multi verifies drift against this
flags: { maxParallel: 4 }
subjects:                                           # Phase B item 1; orchestrator is the only writer
  - { id: ESAS-156, units: [TV1-123, TV1-124], basis: epic,   # epic | seam | singleton
      confirmed: true, confirmedAt: 2026-09-16T10:00:00Z }
subjectsFingerprint: <sha256 from design-multi-subjects>  # equal on resume → reuse silently
units:
  - { id: TV1-123, step: critiqued, status: in_progress,
      draft: units/TV1-123.design-draft.md,
      openForks: 2, ticketWritten: false }
    # step: pending | drafting | critiqued | resolved | written | done
```
