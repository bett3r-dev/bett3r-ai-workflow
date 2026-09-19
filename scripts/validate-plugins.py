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
  2. Every AGENT entrypoint declares a non-empty `tools:` allowlist. An agent
     that omits it does not fail — it inherits every tool registered in the
     session, so the grant it actually runs with is whatever the host happened
     to load, and no file in this repo states it. `/design-multi` dispatches its
     lanes unattended and cuts no worktrees for them — "All agents read the one
     working tree" (commands/design-multi.md) — which is where that difference
     is paid. The rule is over the SHAPE of the declaration only: it names no
     tool and no repo.
  3. No `description` exceeds the platform's ~1024-character cap. Skill
     descriptions in these plugins are not summaries — they carry *standing
     rules* (`esas-design`'s sync ordering, `esas-pending`'s never-a-trigger
     rule) which work precisely because the description is what stays resident
     in every session. Past the cap the tail is truncated, and truncation is
     not an error: the file stays green in every suite while the rules that
     were amputated read as present. Same failure shape as (1), one layer in.
  4. Every plugin.json / marketplace.json is valid JSON with its required keys,
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


def check_agents_dir_is_flat(plugin_dir: pathlib.Path) -> None:
    """The `tools:` rule reaches exactly `agents/*.md`, because that is what
    Claude Code registers. That scope is deliberate, but it is SILENT: an agent
    added one directory deeper is neither registered nor checked, and nothing
    says so. Make the boundary loud instead of leaving it to be discovered.

    Note what this rule does NOT cover, and cannot: the BUILT-IN agent types
    (`general-purpose`, `claude`) carry `*` — every tool, including any mcp
    write verb — and are not files in this repo at all. An agent that declares
    `Agent` can dispatch them. See ADR-066 in bett3r-xp-layer: the tool grant
    and the lane marker are two mechanisms covering two different paths, and
    the built-in types sit outside both.
    """
    agents = plugin_dir / "agents"
    if not agents.is_dir():
        return
    for nested in sorted(agents.rglob("*.md")):
        if nested.parent != agents:
            errors.append(
                f"{rel(nested)}: markdown under `agents/` but not directly in it. "
                f"Claude Code registers `agents/*.md` only, so this file is never "
                f"loaded AND never checked for a `tools:` allowlist. Move it to "
                f"`agents/{nested.name}`, or out of `agents/` if it is a support doc."
            )


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
        for k, _, v in (line.partition(":") for line in body.splitlines() if line.strip() and not line.startswith((" ", "\t", "-", "#")))
    }
    description = keys.get("description")
    if not description:
        errors.append(f"{rel(path)}: frontmatter parses but has no non-empty `description` — it won't be discoverable.")
        return

    # Strip one layer of the quoting YAML requires when a description contains
    # a `:` — the cap applies to the value, not to its quotes.
    if len(description) >= 2 and description[0] == description[-1] and description[0] in "\"'":
        description = description[1:-1]

    if path.parent.name == "agents" and not declares_tools(body):
        errors.append(
            f"{rel(path)}: agent frontmatter declares no non-empty `tools:` allowlist — "
            f"it will INHERIT every tool registered in the session, including any write verb "
            f"the host has loaded. Add a `tools:` key naming what this agent may use."
        )

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


# The spellings that leave the `tools:` key present with no allowlist behind
# it. Compared against the value with all whitespace removed, so `[ ]` cannot
# slip past `[]` on one space — an exact-string refusal is defeated by
# formatting, which is the cheapest possible way to lose this rule.
EMPTY_VALUES = ("", "null", "Null", "NULL", "~", "[]", "{}")


def _meaningful(value: str) -> bool:
    """Is this YAML scalar/item an actual value, once a trailing `#` comment,
    one layer of quotes and YAML's spellings of "nothing" are removed?

    Note what is deliberately NOT empty: `tools: none` reads as a tool literally
    named `none`, because `none` is not a YAML null spelling. It is accepted,
    and a typo for `null` is therefore accepted too — the alternative is
    refusing an agent whose only tool happens to be named that.
    """
    v = value.strip()
    if v.startswith("#"):
        return False
    v = v.split(" #", 1)[0].split("\t#", 1)[0].strip()
    # One layer of quotes: `tools: ''` is the key with an empty scalar.
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1].strip()
    return "".join(v.split()) not in EMPTY_VALUES


def declares_tools(body: str) -> bool:
    """Does this frontmatter block declare a non-empty `tools:` allowlist?

    Both spellings in the corpus count: inline (`tools: Read, Grep`) and the
    indented YAML block list the agents here actually use

        tools:
          - Read
          - Write

    Neither counts when it is EMPTY, because an empty allowlist inherits
    exactly as a missing key does. "Empty" is not a universal claim about YAML
    — it is exactly the spellings in `EMPTY_VALUES` (`null`, `~`, `[]`, `{}`,
    the empty scalar, each modulo quotes and internal whitespace), plus a bare
    `tools:` with nothing under it, plus — the case the corpus is most exposed
    to — a block list whose every item is COMMENTED OUT. Each has a fixture in
    scripts/test-validate-plugins.sh; a spelling with no fixture is not
    claimed here.

    A `#` line is a comment at any indent, so the continuation scan skips it as
    the top-level loop does. That skip is load-bearing in BOTH directions:
    `tools:` over `  # - Read` is an agent with no allowlist (in the one
    spelling every agent in this repo uses), while a comment at COLUMN 0
    between `tools:` and its first item must NOT end the block — without the
    skip that unindented line reads as the next key and falsely refuses a
    legitimately-declared agent.

    `tools: []` is REFUSED rather than read as a deliberate zero grant: this
    rule cannot verify what the platform does with an empty list, and the two
    readings ("grant nothing" vs "unset, so inherit") differ in exactly the
    dangerous direction. An agent that truly needs nothing can say so in a
    comment beside a minimal grant.

    Only the frontmatter block is read (the caller has already sliced it), so
    an agent body that *discusses* tool grants must neither satisfy this nor
    trip it.
    """
    lines = body.splitlines()
    for i, line in enumerate(lines):
        if not line.strip() or line.startswith((" ", "\t", "-", "#")):
            continue
        key, sep, value = line.partition(":")
        if not sep or key.strip() != "tools":
            continue
        if _meaningful(value):
            return True
        # An empty value is a block list only if some following line is an
        # indented (or `-`) item with real content. Comments and blank lines
        # are skipped; the first line back at the top level ends the block.
        for nxt in lines[i + 1:]:
            if not nxt.strip() or nxt.lstrip().startswith("#"):
                continue
            if not nxt.startswith((" ", "\t", "-")):
                return False
            if _meaningful(nxt.lstrip(" \t-")):
                return True
        return False
    return False


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
        check_agents_dir_is_flat(plugin_dir)
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
