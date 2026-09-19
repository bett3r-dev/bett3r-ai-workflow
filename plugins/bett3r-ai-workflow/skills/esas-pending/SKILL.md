---
name: esas-pending
description: "The `esas: N pending (seq A→B)` hook line: telemetry, never a trigger. Act on, sync or mention pending board edits only when the user asks; a summon on /api/esas/ws is the ask."
---

# esas: N pending

The `UserPromptSubmit` hook `hooks/esas-pending.sh` prints one line when the user has edited the ESAS design board since your last sync:

```
esas: 2 pending (seq 1→4)
```

Two human edits you have not read: cursor at op 1, feed at op 4. It names no element and asks for nothing.

## The standing rule

The count says your picture of the design is stale; knowing is the entire job, and it is telemetry, never a trigger. Act on it, mention it or sync because of it only when the user asks ("look at the board", any phrasing); `esas-design` owns the gesture. Meanwhile say your picture may be behind rather than asserting what the design says.

## The one ask

**A summon is the user asking.** The board's *Ask Claude* button broadcasts one frame on the ESAS session channel (`/api/esas/ws`) this session holds open with `Monitor`, so you arrive at a turn nobody typed. Sync, whole, as `esas-design` says. A press is a sentence; the count is a thermometer.

Absent means nothing pending, or no `.esas/` here (a fleet worktree); both normal. An inflated count right after a new unit of work is a stale cursor reporting from seq 0; it clears on the next sync.
