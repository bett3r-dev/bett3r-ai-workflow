#!/usr/bin/env python3
"""Validate that every published plugin artifact actually loads.

These plugins fail *silently*: a command/skill/agent whose YAML frontmatter
doesn't parse is not an error — it simply never registers, and disappears from
the available list in every consuming repo. Three artifacts (`/verify-build`,
`/start`, `create-readmodel`) sat broken this way, each invisible until someone
diffed the skills list against the file tree by hand.

So this checks the things whose failure mode is *absence*:

  1. Every entrypoint (commands/*.md, skills/**/SKILL.md, agents/*.md) opens
     with parseable YAML frontmatter carrying a non-empty `description`.
  2. No `description` exceeds the platform's ~1024-character cap. Skill
     descriptions in these plugins are not summaries — they carry *standing
     rules* (`esas-design`'s sync ordering, `esas-pending`'s never-a-trigger
     rule) which work precisely because the description is what stays resident
     in every session. Past the cap the tail is truncated, and truncation is
     not an error: the file stays green in every suite while the rules that
     were amputated read as present. Same failure shape as (1), one layer in.
  3. Every plugin.json / marketplace.json is valid JSON with its required keys,
     and each marketplace `source` path resolves to a real plugin.

Run locally:  python3 scripts/validate-plugins.py
Exit code is non-zero if anything is broken, so CI fails the PR.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLUGINS = ROOT / "plugins"

# `---\n<yaml>\n---\n` at the very top. The `(?!-)` guards the real-world bug:
# a `---` followed immediately by a `## description:` markdown heading and no
# closing fence, which yields an empty/unparseable block.
FRONTMATTER = re.compile(r"\A---\r?\n(?!-)(.*?)\r?\n---\r?\n", re.DOTALL)

# The platform truncates a frontmatter `description` at roughly this many
# characters when loading it resident into a session. Warn well before the
# edge, because the margin is what gets spent: a description at 95% is one
# clarifying clause away from silently losing its last standing rule.
DESCRIPTION_MAX = 1024
DESCRIPTION_WARN = int(DESCRIPTION_MAX * 0.90)

errors: list[str] = []
warnings: list[str] = []
checked = 0


def rel(p: pathlib.Path) -> str:
    return str(p.relative_to(ROOT))


def entrypoints(plugin_dir: pathlib.Path):
    """The files Claude Code registers. Nested references/*.md are support docs
    and legitimately carry no frontmatter — don't flag them."""
    yield from sorted((plugin_dir / "commands").glob("*.md"))
    yield from sorted((plugin_dir / "agents").glob("*.md"))
    yield from sorted((plugin_dir / "skills").glob("*/SKILL.md"))


def check_frontmatter(path: pathlib.Path) -> None:
    global checked
    checked += 1
    text = path.read_text(encoding="utf-8")

    m = FRONTMATTER.match(text)
    if not m:
        hint = ""
        if re.match(r"\A---\s*\n\s*\n?##\s*(description|name)\s*:", text):
            hint = (
                "  -> looks like `---` + a `## description:` heading with no closing `---`. "
                "Use:\n     ---\n     description: ...\n     ---"
            )
        errors.append(f"{rel(path)}: frontmatter does not parse — this artifact will NOT load.{hint}")
        return

    body = m.group(1)
    # Deliberately not importing PyYAML: keep this dependency-free so it runs
    # anywhere. Frontmatter here is flat `key: value`, so a line scan is enough.
    keys = {
        k.strip(): v.strip()
        for k, _, v in (line.partition(":") for line in body.splitlines() if line.strip() and not line.startswith((" ", "\t", "-")))
    }
    description = keys.get("description")
    if not description:
        errors.append(f"{rel(path)}: frontmatter parses but has no non-empty `description` — it won't be discoverable.")
        return

    # Strip one layer of the quoting YAML requires when a description contains
    # a `:` — the cap applies to the value, not to its quotes.
    if len(description) >= 2 and description[0] == description[-1] and description[0] in "\"'":
        description = description[1:-1]

    n = len(description)
    if n > DESCRIPTION_MAX:
        errors.append(
            f"{rel(path)}: `description` is {n} chars, over the ~{DESCRIPTION_MAX} cap — "
            f"the last {n - DESCRIPTION_MAX} chars are silently truncated when loaded."
        )
    elif n >= DESCRIPTION_WARN:
        warnings.append(
            f"{rel(path)}: `description` is {n} chars, {DESCRIPTION_MAX - n} under the "
            f"~{DESCRIPTION_MAX} cap — any addition risks truncating a standing rule."
        )


def check_manifest(path: pathlib.Path, required: list[str]) -> dict | None:
    global checked
    checked += 1
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        errors.append(f"{rel(path)}: invalid JSON — {e}")
        return None
    for key in required:
        if not data.get(key):
            errors.append(f"{rel(path)}: missing required key `{key}`")
    return data


def main() -> int:
    if not PLUGINS.is_dir():
        print(f"no plugins/ directory at {ROOT}", file=sys.stderr)
        return 1

    for plugin_dir in sorted(p for p in PLUGINS.iterdir() if p.is_dir()):
        check_manifest(plugin_dir / ".claude-plugin" / "plugin.json", ["name", "version", "description"])
        for f in entrypoints(plugin_dir):
            check_frontmatter(f)

    market_path = ROOT / ".claude-plugin" / "marketplace.json"
    market = check_manifest(market_path, ["name", "plugins"])
    if market:
        for entry in market.get("plugins", []):
            src = (ROOT / entry.get("source", "")).resolve()
            if not (src / ".claude-plugin" / "plugin.json").is_file():
                errors.append(
                    f"{rel(market_path)}: plugin `{entry.get('name')}` points at "
                    f"`{entry.get('source')}`, which has no .claude-plugin/plugin.json"
                )

    if warnings:
        print(f"\n! {len(warnings)} warning(s):\n", file=sys.stderr)
        for w in warnings:
            print(f"  {w}", file=sys.stderr)

    if errors:
        print(f"\n✗ {len(errors)} problem(s) across {checked} artifact(s):\n", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        print(
            "\nThese failures are silent at runtime — a broken artifact does not error, "
            "it just never registers.\n",
            file=sys.stderr,
        )
        return 1

    print(f"✓ {checked} artifacts valid (frontmatter + manifests)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
