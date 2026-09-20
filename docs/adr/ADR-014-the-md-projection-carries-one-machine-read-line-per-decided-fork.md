# The md projection carries one machine-read line per decided fork — and hardcoding that line's key is a named exception to ADR-003, not an oversight

`map-tree.py` renders `map.json` into the "Resolved decision tree" region of a committed
`docs/prs/<id>/design.md` ([ADR-007](./ADR-007-derived-decision-text-is-a-hashed-projection.md)).
Until XL-62 everything in that region was prose for a person. XL-62 added a line that is **read by a
program in another repository**, and that single fact is what needs a record: the flow plugin is
store-agnostic by [ADR-003](./ADR-003-two-generic-seams-keep-the-flow-plugin-store-agnostic.md), and
a key defined by one named consumer is exactly the coupling ADR-003 exists to keep out.

The decision is to hardcode it anyway, and to write down that it is hardcoded. What makes that
acceptable is this file. What would have made it dangerous is shipping it silently past a guard that
happens not to cover the file it lives in.

## The projection rule: one machine-read line per decided fork, and its value has one source

**The md projection carries one machine-read line per decided fork.** It is the column-0 line
`resolved_by: <value>` emitted in `render_md` for every fork whose status is decided — never for an
open, moot or locked fork, and never in the `jira` dialect, whose reader is Jira and not a census.

**The value is `status.resolvedBy` verbatim where the map carries it, and the `status.source`
fallback otherwise.** Verbatim means verbatim: `map-tree.py` does not validate, normalise or
re-vocabulate a citation the map already holds. Where the map holds none, the value is minted from
`status.source` through `RESOLVED_BY_FALLBACK` — `owner` to `human`, `code` to `code`, and
`recommendation` to its own literal `recommendation` rather than being laundered into `human`
(XL-62-F1 option A, `docs/prs/XL-62/ticket-block.md`). The laundering is refused for a reason worth
keeping: `commands/design-multi.md:70` already says that where the owner answers neither way, the
report records the recommendations as applied *"since silence is not assent"* — so a recommendation
applied without an owner answer is not a person answering, and the projection must not spell it as
one.

An open fork's typed `reason` is rendered **inline** on its OPEN line, mirroring the
`moot — <reason>` shape beside it. It is presentation only: no column-0 line, and nothing parses it
(XL-62-F3). That asymmetry is the rule doing its job — "machine-read" is a property a line either
has or does not, and only the decided fork's line has it.

## The generation rule: adding or removing a machine-read line bumps `GEN`

**Any render change that adds or removes a machine-read line bumps `GEN`.** `map-tree.py`'s `GEN` is
the projection's shape generation; it is stamped into the region marker as `gen=<n>`, and a region
whose `gen` differs from `GEN` is **re-rendered, never counted as tampered**. So an existing
committed region rendered under the old shape is not reported as a hand edit the moment the renderer
learns a new line — which is precisely what would happen if the shape changed under a constant `GEN`,
because `out=` is a hash of the body.

XL-62 moved `GEN` from 1 to 2 when it added the `resolved_by:` line, and deliberately did **not**
move it again when it added the open fork's inline reason: the inline reason is inside a line that
already existed and adds no machine-read line, so the bump rule does not fire. The rule is about the
machine-read surface, not about every byte of the body — the body's bytes are already covered by
`out=`.

## The exception: `map-tree.py` hardcodes one consumer-defined grammar term, knowingly

**`map-tree.py` hardcodes the key `resolved_by:` and the five-value vocabulary around it, and that
key and vocabulary are defined by a consumer outside this plugin.** They belong to the experience
layer's census, which lives in another repository; nothing in the base flow plugin needs the word
`resolved_by` for its own sake. **This is an accepted, named exception to ADR-003, not an oversight.**

It is worth being exact about which half of ADR-003 is being excepted. ADR-003's invariant is that
the base flow plugin stays store-agnostic and a consumer adapts to the flow, never the reverse; its
mechanical expression is that `scripts/test-flow-seams.sh` asserts no seam file mentions a consumer.
XL-62 hardcodes a consumer's *term* in a renderer — one grammar term, in one function, in one
dialect — rather than teaching a command about a consumer's *existence*. That is a smaller thing
than the shape ADR-003 refused, and it is still on the wrong side of the line, which is why it is
recorded here instead of argued away.

**No coupling guard covers this file.** `scripts/test-flow-seams.sh`'s coupling table,
`COUPLING_SEAM_FILES`, lists nine seam artifacts — `CONTEXT-PROVIDERS.md`, the four command files,
the two `reference/` files, `unit-lane.md` and `provisioner.md` — and `map-tree.py` is not among
them, nor is any script. The guard is therefore **silent here by construction**: it did not weigh
this coupling and pass it, it never looked. Anyone reading a green `flow-seams` run as evidence that
this renderer is store-agnostic is reading a check that was never pointed at it.

So the absence is asserted rather than left implied. `scripts/test-flow-seams.sh` now checks that
`COUPLING_SEAM_FILES` really does not list `map-tree.py`, and that assertion fails the moment someone
adds it — at which point this record is wrong and must be revisited, which is the entire reason for
writing the exception down instead of relying on nobody noticing.

The rejected alternative was to take the key and the source-to-value mapping from the host's
`.claude/bett3r-ai-workflow.json`, the way `work-docs-path.py` already reads that config. It is the
ADR-003-true answer and it was still rejected **for now**: `map-tree.py` reads no config at all today
(its only `json.load` is the map itself), it would gain a dependency on the host repo root, and a
missing declaration would silently emit nothing — a confident zero in the consumer's census, which is
the failure shape the census's own ADR already warns about.

## The trigger: a second consumer repo makes this host-configured

**A second consumer repo wanting a different key or a different vocabulary is the named trigger to
make this host-configured instead.** That is the rejected option above, deferred rather than
abandoned: it is the architecturally correct answer and a different ticket, and XL-62 was filed as a
~20-line writer, not as new configuration machinery with a failure mode of its own.

One consumer with one key is a hardcoded literal that is trivially readable and trivially changed.
Two consumers with two keys is a table, and a table read from the wrong place — this plugin — is the
coupling ADR-003 actually forbids. So the trigger is not "when someone objects on principle"; it is a
**second consumer**, which is a fact anyone can check rather than a judgement anyone can defer.
Nothing in this record licenses building the config seam before then, and nothing in it licenses
adding a third consumer's term beside the first.

## What this does not decide

* **The vocabulary is not validated anywhere.** No layer enforces the five-value grammar, and no
  layer enforces the three documented codes for an open fork's `reason`. Validation belongs in
  `design-map validate`, not in the renderer (XL-62-F3 rejected option C), and it is not built. This
  is a known, unmitigated gap, recorded in XL-62's Risks and not closed here.
* **Cross-repo census reach is out of scope** and filed separately; this record covers the writer
  only.
* **The consumer's own grammar line is amended in the consumer's repository, not here.** This file
  records what *this* plugin emits and why it is allowed to know the term at all.

## Status

Accepted. Extends [ADR-007](./ADR-007-derived-decision-text-is-a-hashed-projection.md): the hashed
projection now has a machine-read surface as well as a human-read one, and `GEN` is what keeps the
two versions of that surface apart. Excepts
[ADR-003](./ADR-003-two-generic-seams-keep-the-flow-plugin-store-agnostic.md) narrowly and by name,
for one key in one renderer, until a second consumer exists.
