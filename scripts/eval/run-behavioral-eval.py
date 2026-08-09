#!/usr/bin/env python3
"""Behavioral eval: does a session actually *follow* an artifact, or merely contain it?

Every other gate in this repo asserts **presence**. `check-needles.py` proves a
fact is still somewhere in the corpus; `check-artifact-links.py` proves a link
resolves and that a declared consumer links back; `validate-plugins.py` proves
an artifact loads at all. Presence is the right assertion for a *move* — content
relocating between files is exactly what those gates are built to tolerate.

Presence is the wrong assertion for a *split*. The moment a rule stops living
inline and starts living behind a pointer, the question stops being "is the fact
there" and becomes "is the pointer followed" — and no amount of grepping answers
it. That gap is the standing risk of every split this repo has made:

    a referenced file is only as good as the reference being followed.

It has already been paid once: EVIDENCE.md shipped linked from 5 artifacts while
needed by 8, and every gate was green, because both the link and its absence
parse fine.

So this harness runs the artifact. Each scenario puts a real headless session in
front of a real artifact with a concrete situation, and asserts on what the
session *did*:

  * **must_open**  — did it actually Read the reference file? Parsed from the
    tool-use stream, not inferred from the prose. A session can produce a
    perfectly correct-sounding answer out of its own priors while never opening
    the file, and that answer is not evidence the split works: it is evidence
    the model already knew. Only the tool call discriminates.
  * **must_state** — did the rule survive into the answer? Groups are OR within,
    AND across, so a rule can be phrased several ways without the assertion
    turning into a paraphrase check.
  * **must_not_state** — the inverse, for the rules whose failure mode is doing
    something rather than omitting it.

**Non-determinism is handled by repetition, not by pretending.** Each scenario
runs `runs` times and needs `min_pass` of them. A scenario that passes 3/3 today
and 1/3 next month has detected real drift in an artifact's legibility, which is
precisely the signal a presence gate cannot produce.

**At least one scenario must be a negative control.** `base-check-not-delegated`
asserts that a rule which deliberately did *not* move is still owned by the
orchestrator. Without it, this suite would happily report green on a corpus that
had delegated everything, because every "did it follow the pointer" question
would still answer yes. A detector never seen to fire is not evidence of calm.

**The model is pinned, in `defaults.model`.** Left to the CLI default it is a
silent variable: a scenario dropping from 3/3 to 1/3 would be ambiguous between
"the artifact drifted" and "the default model changed", and only the first is
visible, so only the first gets blamed. Every verdict prints the model it ran on.

Overriding it is the *useful* move, not a fallback. The plugin's own subagents
(`executor`, `verifier`, `test-runner`, `provisioner`) do not necessarily run on
the strongest model, so **a rule only the strongest model follows is a rule that
breaks in a cheaper subagent.** Re-running a scenario with `--model` turns this
suite into a legibility measure rather than only a regression check.

## Why this is not in CI

It consumes real usage and real minutes (30-60s per session), it needs an
authenticated `claude` CLI, and it is non-deterministic — three properties that
make a required PR check actively harmful. The static half of the contract lives
in `scripts/check-eval-coverage.py`, which *is* CI-safe: it asserts every split
has a scenario without running one. Run this one deliberately: before merging a
split, and after changing any artifact that carries a pointer.

Note the reported cost is the CLI's own `total_cost_usd`, which is a notional
API-equivalent figure. On a subscription-authenticated CLI nothing is billed at
that rate — it consumes usage limits instead — so read it as a relative measure
of how heavy a pass is, not as an invoice.

    python3 scripts/eval/run-behavioral-eval.py                     # everything
    python3 scripts/eval/run-behavioral-eval.py --scenario provisioner-reached
    python3 scripts/eval/run-behavioral-eval.py --dry-run           # free; prints prompts
    python3 scripts/eval/run-behavioral-eval.py --runs 1            # cheap smoke
    python3 scripts/eval/run-behavioral-eval.py --model claude-haiku-4-5-20251001

Exit code is non-zero if any scenario falls below its threshold.
"""

import argparse
import json
import pathlib
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SCENARIOS = pathlib.Path(__file__).resolve().parent / "scenarios.json"


def load() -> tuple[dict, list[dict]]:
    if not SCENARIOS.is_file():
        sys.exit(f"no scenarios file at {SCENARIOS}")
    try:
        data = json.loads(SCENARIOS.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        sys.exit(f"{SCENARIOS}: invalid JSON — {e}")
    scenarios = data.get("scenarios") or []
    if not scenarios:
        # Same guard as every other gate here: an empty corpus is an error, not
        # a silent pass. A suite that checks nothing must never report green.
        sys.exit(f"{SCENARIOS}: no scenarios defined — this suite would verify nothing")
    return data.get("defaults", {}), scenarios


def run_once(scenario: dict, defaults: dict, model: str | None) -> dict:
    """One headless session. Returns what it opened, what it said, what it cost."""
    tools = scenario.get("allowed_tools", defaults.get("allowed_tools", "Read,Grep,Glob"))
    cmd = [
        "claude", "-p", scenario["prompt"],
        "--output-format", "stream-json", "--verbose",
        "--allowedTools", tools,
    ]
    # The model is pinned, never inherited. Unpinned, a scenario dropping from
    # 3/3 to 1/3 is ambiguous between "the artifact drifted" and "the CLI's
    # default model changed" — and the second is invisible, so the first gets
    # blamed. A result is only comparable to the run before it if this is the
    # same. It is printed with every verdict for the same reason.
    if model:
        cmd += ["--model", model]
    try:
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        return {"error": "timed out after 600s", "reads": [], "text": "", "cost": 0.0}

    reads: list[str] = []
    text_parts: list[str] = []
    cost = 0.0
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") == "assistant":
            for block in event.get("message", {}).get("content", []):
                if block.get("type") == "tool_use":
                    path = block.get("input", {}).get("file_path") or block.get("input", {}).get("path")
                    if path:
                        reads.append(str(path))
                elif block.get("type") == "text":
                    text_parts.append(block.get("text", ""))
        elif event.get("type") == "result":
            cost = event.get("total_cost_usd") or 0.0
            if event.get("result"):
                text_parts.append(str(event["result"]))

    if not text_parts and proc.returncode != 0:
        return {"error": (proc.stderr or "no output").strip()[:300], "reads": reads, "text": "", "cost": cost}
    return {"error": None, "reads": reads, "text": "\n".join(text_parts), "cost": cost}


def judge(scenario: dict, result: dict) -> tuple[bool, list[str]]:
    """A run passes only if every assertion holds. Returns (passed, reasons-it-failed)."""
    if result["error"]:
        return False, [f"run error: {result['error']}"]

    failures = []
    reads_blob = "\n".join(result["reads"])
    for needed in scenario.get("must_open", []):
        if needed not in reads_blob:
            failures.append(f"never opened {needed}")

    haystack = result["text"].lower()
    for group in scenario.get("must_state", []):
        if not any(alt.lower() in haystack for alt in group):
            failures.append(f"stated none of {group}")
    for forbidden in scenario.get("must_not_state", []):
        if forbidden.lower() in haystack:
            failures.append(f"stated the forbidden {forbidden!r}")

    return not failures, failures


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--scenario", help="run only this scenario id")
    ap.add_argument("--runs", type=int, help="override runs per scenario")
    ap.add_argument("--dry-run", action="store_true", help="print prompts and assertions, spend nothing")
    ap.add_argument("--jobs", type=int, default=4, help="concurrent sessions (default 4)")
    ap.add_argument("--model", help="override the pinned model (e.g. to test legibility on a cheaper one)")
    args = ap.parse_args()

    defaults, scenarios = load()
    model = args.model or defaults.get("model")
    if args.scenario:
        scenarios = [s for s in scenarios if s["id"] == args.scenario]
        if not scenarios:
            sys.exit(f"no scenario with id {args.scenario!r}")

    if args.dry_run:
        for s in scenarios:
            print(f"\n\033[1m{s['id']}\033[0m — {s.get('guards_split','')}")
            print(f"  why: {s['why']}")
            print(f"  must_open: {s.get('must_open', [])}")
            print(f"  must_state: {s.get('must_state', [])}")
            print(f"  prompt: {s['prompt'][:300]}…")
        print(f"\n{len(scenarios)} scenario(s); nothing was run. model would be: {model or '<CLI default — UNPINNED>'}")
        return 0

    jobs: list[tuple[dict, int]] = []
    for s in scenarios:
        n = args.runs or s.get("runs", defaults.get("runs", 3))
        jobs.extend((s, i) for i in range(n))

    print(f"running {len(jobs)} session(s) across {len(scenarios)} scenario(s), "
          f"{args.jobs} at a time, on {model or '<CLI default — UNPINNED, results not comparable>'}\n")
    results: dict[str, list] = {s["id"]: [] for s in scenarios}
    total_cost = 0.0
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(run_once, s, defaults, model): (s, i) for s, i in jobs}
        for fut in as_completed(futures):
            s, _ = futures[fut]
            outcome = fut.result()
            total_cost += outcome["cost"]
            passed, why = judge(s, outcome)
            results[s["id"]].append((passed, why))
            print(f"  {'✓' if passed else '✗'} {s['id']}" + (f"  — {'; '.join(why)}" if why else ""))

    print("\n" + "─" * 72)
    failed_scenarios = []
    for s in scenarios:
        runs = results[s["id"]]
        n_pass = sum(1 for p, _ in runs if p)
        # Clamp the threshold to the number of runs actually performed. Without
        # this, `--runs 1` reports every scenario failed against a min_pass of 2
        # — a gate that fails in the *alarming* direction, which is the cheap
        # way to be wrong, but still wrong: five red lines hide the one real
        # finding among them.
        need = min(s.get("min_pass", defaults.get("min_pass", 2)), len(runs))
        ok = n_pass >= need
        if not ok:
            failed_scenarios.append(s)
        print(f"{'✓' if ok else '✗'} {s['id']:<34} {n_pass}/{len(runs)} passed (needs {need})")
        if not ok:
            print(f"    guards: {s.get('guards_split','')}")
            for _, why in runs:
                if why:
                    print(f"      - {'; '.join(why)}")

    print(f"\nmodel: {model or '<CLI default — UNPINNED>'}    reported cost: ${total_cost:.2f}"
          "  (notional API-equivalent; a subscription CLI consumes usage, not dollars)")
    if failed_scenarios:
        print(
            f"\n✗ {len(failed_scenarios)} scenario(s) below threshold.\n\n"
            "A scenario fails when the artifact stopped being followed — most often because a\n"
            "pointer lost the trigger that made it get opened, not because the fact went\n"
            "missing (check-needles.py would have caught that). Read the artifact at the\n"
            "pointer and ask what condition now tells the reader to open it.\n",
            file=sys.stderr,
        )
        return 1
    print(f"\n✓ {len(scenarios)} scenario(s) held")
    return 0


if __name__ == "__main__":
    sys.exit(main())
