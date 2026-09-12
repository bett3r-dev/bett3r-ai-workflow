#!/usr/bin/env python3
"""Refuse a resolved-design block whose two marker lines disagree.

`/design-multi` emits the `design-multi:resolved:vN` marker twice — an HTML
comment and a visible inline-code line — because some trackers strip comment
nodes outright. The inline line is therefore the FALLBACK, and a fallback
carrying fewer attributes fails silently exactly when it is needed: every check
that reads the comment line passes. Per-unit fold-back agents once emitted the
pair with different attribute sets on 4 of 5 blocks, and a `run=` count passed
anyway because of an unrelated occurrence elsewhere in the text.

So this parses both lines and requires them to be identical in version and in
every attribute, and requires the attributes `/start-multi` reads (`status`,
`base`, `run`) with a `status` it knows.

Usage: resolved-marker-lint <block.md> [<block.md> ...]
Exit 0 when every block passes; 1 with a reason per failing block.
"""
import re
import sys

COMMENT = re.compile(r"^\s*<!--\s*design-multi:resolved:v(\d+)((?:\s+[^\s=]+=\S+)*)\s*-->\s*$")
INLINE = re.compile(r"^\s*`design-multi:resolved:v(\d+)((?:\s+[^\s=`]+=[^\s`]+)*)\s*`\s*$")
STATUSES = {"ready", "deferred", "blocked", "umbrella"}
REQUIRED = ("status", "base", "run")


def attrs(raw):
    out = {}
    for tok in raw.split():
        key, _, val = tok.partition("=")
        if key in out:
            raise ValueError(f"attribute `{key}` repeated")
        out[key] = val
    return out


def lint(path):
    text = open(path, encoding="utf-8").read().splitlines()
    comments = [m for m in map(COMMENT.match, text) if m]
    inlines = [m for m in map(INLINE.match, text) if m]
    if len(comments) != 1 or len(inlines) != 1:
        return [f"expected exactly one comment marker and one inline marker, found {len(comments)} and {len(inlines)}"]
    try:
        c, i = attrs(comments[0].group(2)), attrs(inlines[0].group(2))
    except ValueError as e:
        return [str(e)]
    errors = []
    if comments[0].group(1) != inlines[0].group(1):
        errors.append(f"version differs: comment v{comments[0].group(1)}, inline v{inlines[0].group(1)}")
    for key in sorted(set(c) | set(i)):
        if c.get(key) != i.get(key):
            errors.append(f"`{key}` differs: comment {c.get(key, '<absent>')!r}, inline {i.get(key, '<absent>')!r}")
    for key in REQUIRED:
        if key not in c and key not in i:
            errors.append(f"`{key}` absent from both marker lines")
    status = c.get("status", i.get("status"))
    if status is not None and status not in STATUSES:
        errors.append(f"status `{status}` is not one of {sorted(STATUSES)} — /start-multi silently drops it")
    return errors


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[-2], file=sys.stderr)
        return 2
    failed = 0
    for path in argv[1:]:
        errors = lint(path)
        if errors:
            failed += 1
            print(f"✗ {path}")
            for e in errors:
                print(f"    {e}")
        else:
            print(f"✓ {path}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
