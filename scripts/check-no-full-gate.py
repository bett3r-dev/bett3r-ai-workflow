#!/usr/bin/env python3
"""No flow artifact may instruct a step to run the host repo's gate in a whole-repo mode.

The rule (owner's, unconditional): every gate a flow runs is SCOPED to that flow's own
diff. The whole-repo run -- `--full`, `--all` -- happens once, elsewhere: in the CI
pipeline, or when the owner asks for it by name. A flow step that helps itself to one
spends minutes to tens of minutes of the owner's laptop time, on every unit of every run,
re-proving a tree the change never touched.

So this guard fails on any *instruction* to run it: a `--full` / `--all` argument to a
gate invocation inside a command, agent or skill of a flow plugin. Prose that names the
mode in order to forbid it, or to say who does run it, is allowed -- that is the rule
being written down, and a guard that forbade the words would forbid its own statement of
them. The test is therefore narrow on purpose: it fires on a gate COMMAND carrying the
flag, not on the flag appearing in a sentence.

Run: python3 scripts/check-no-full-gate.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# A gate invocation carrying a whole-repo mode: `node .claude/gate.mjs --full`,
# `sh .claude/gate.sh --all`, `yarn gate --full`, `.claude/gate.mjs --full`, ...
INVOCATION = re.compile(
    r"(?:node |sh |bash |yarn |npm run |pnpm )?"
    r"(?:\.claude/gate\.(?:mjs|sh)|yarn gate|gate)\s+--(?:full|all)\b"
)
# ...unless the same line is the rule itself: a negation, or an attribution to CI/the human.
EXEMPT = re.compile(
    r"never|Never|NEVER|not\b|no flow|No flow|CI|on request|by name|asks|owner|user's|forbid",
)

SEARCH_DIRS = ["commands", "agents", "skills"]


def main() -> int:
    bad = []
    checked = 0
    for plugin in sorted((ROOT / "plugins").iterdir()):
        if not plugin.is_dir():
            continue
        for sub in SEARCH_DIRS:
            for path in sorted((plugin / sub).rglob("*.md")):
                checked += 1
                for n, line in enumerate(path.read_text().splitlines(), 1):
                    if INVOCATION.search(line) and not EXEMPT.search(line):
                        bad.append(f"{path.relative_to(ROOT)}:{n}: {line.strip()}")

    if bad:
        print("✗ a flow artifact instructs a whole-repo gate run (--full / --all).")
        print("  The flow's gate is always scoped; the whole-repo run is CI's, or the owner's on request.")
        for b in bad:
            print("   " + b)
        return 1
    print(f"✓ no flow artifact runs the gate with --full/--all ({checked} artifacts)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
