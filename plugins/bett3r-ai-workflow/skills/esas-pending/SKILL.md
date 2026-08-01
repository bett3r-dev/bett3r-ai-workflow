---
name: esas-pending
description: "STANDING RULE for the `esas: N pending (seq A→B)` line injected by this plugin's UserPromptSubmit hook: it is telemetry, never a trigger — never act on, sync, or even mention pending ESAS board changes unless the user asks. Read this file only if unsure what the line means or whether to react to it."
---

# esas: N pending

The line comes from this plugin's `UserPromptSubmit` hook
(`hooks/esas-pending.sh`). It appears only while the user has edited the ESAS
design board since the last sync, and it says exactly one thing:

```
esas: 2 pending (seq 1→4)
```

*Two design edits the user made are ones you have not read. Your cursor stands
at op 1; the feed stands at op 4.* That is the whole message. It names no
element, carries no instruction, and asks for nothing.

## The standing rule

**Never act on or mention pending board changes unsolicited.**

Not "sync them", not "mention them in passing", not "quickly check what
changed", not "should I take a look at the board?". The user is mid-draft on a
second screen; a burst of board edits is a *thought in progress*, and reacting
to it turns a design surface into an interruption. The count exists for exactly
one purpose: so you know your picture of the design is stale. Knowing is the
entire job.

The gesture that *does* read them is the user's to make — they say "look at the
board" (any phrasing). `/design` owns what happens then.

## What the count changes

Nothing you do. One thing you *don't*:

**Do not assert the current design state as fact while the count is non-zero.**
If the conversation turns on what the design says right now and edits are
pending, say your picture may be behind rather than describing it confidently —
and let the user decide whether to sync. Writes are guarded mechanically
(a write touching an element with pending human edits is refused with "sync
first"), so the only thing left to get wrong is *asserting*.

## When the line is absent

Absence means nothing is pending, **or** that this checkout has no `.esas/` at
all — a fleet worktree, or any repo that has never designed. Both are normal.
The hook is silent by default and says nothing about whether ESAS exists here.

## When the numbers look wrong

The hook degrades toward over-reporting on purpose: a cursor it cannot read, or
one left over from a previous unit of work, reads as "nothing has been synced"
and reports everything pending from seq 0. An unexpectedly large count right
after starting a new unit of work is that, not a lost session. It clears on the
next sync.
