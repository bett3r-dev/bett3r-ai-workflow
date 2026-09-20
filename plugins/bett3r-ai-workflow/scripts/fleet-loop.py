#!/usr/bin/env python3
"""Re-invoke one fresh orchestrator tick per wave, until the run is terminal.

A fleet orchestrator (`/start-multi`) ends its context at a wave boundary and
reports `FLEET-STEP:v1 outcome=success waves=k/N units=i/M` (GH-429-F3). Some
process outside every context has to decide whether to start another one, and
GH-429-F2 makes that a shell driver rather than a human or an in-session loop.
This is that driver's implementation; `bin/fleet-loop` is its launcher.

The whole decision, and nothing else:

  * `outcome=success` with `k < N`  -> tick again on a FRESH context
  * `outcome=success` with `k = N`  -> the run is terminal; exit 0
  * `k` unchanged across two consecutive ticks -> stop, `blocked-on=fleet-no-progress`
  * no verdict line at all -> `outcome=infra` (ADR-004: absence IS the signal)
  * any other outcome -> stop; the run's own rules apply, not the driver's

The no-progress guard is `agents/unit-lane.md`'s `build-no-progress` rule one
level up: "k did not advance between two consecutive dispatches -> stop and
report `blocked-on=build-no-progress` with both lines; a yield that resumes onto
the same slice forever is the one way this loop costs more than it saves."

**The driver holds no state but the previous tick's `waves=k/N`.** There is no
state file and nothing is written to the run dir: every other fact about the run
lives in `run.yaml` and `units/<id>.state.yaml`, which the orchestrator owns, and
a second writer of run state is exactly the drift `start-multi.md` names ("only
you write `run.yaml`").

**The verdict is read through the shipped parser, never a regex here.** The line
grammar has one implementation — `scripts/lane-step-parse.py`, invoked as
`bin/lane-step --marker FLEET-STEP` — and `scripts/test-flow-seams.sh`'s
uniqueness guard fails a second copy of the token rule.

**The plugin version is checked AFTER each tick, never before the first**
(GH-429 design risk 4). `claude -p` resolves this plugin from the installed
cache, not from the branch, and a cache one minor behind ships a different agent
roster: a human hits that once and notices, while a driver ticking ten times
makes it systematic and silent. But only the orchestrator can observe which copy
`claude -p` loaded — it *is* the loaded plugin — so the orchestrator is the
writer: `commands/start-multi.md` step 0 records `pluginVersion` in `run.yaml`
from its own loaded manifest, on every tick including the resume path. Before
tick 1 there is nothing to compare: on a fresh run `run.yaml` does not exist yet
(step 0 creates it), so a missing file and an absent `pluginVersion` both
PROCEED. After a tick the driver refuses on three things: a `pluginVersion` that
changed between two ticks, one that disagrees with the version this launcher
resolved, and one still absent — which after a tick means the orchestrator did
not write it, i.e. contract drift rather than a cold start. Nothing backfills the
key into an existing run: a guessed value would make `recorded == resolved` and
turn the guard into a false pass, so an old run pays exactly one honestly
unguarded tick and is guarded from the second.

Usage:
    fleet-loop --run <run-dir> --tick <shell-command>

Both are required; neither is guessed. `--tick` is run through the shell once per
tick, with its combined output echoed and then parsed — in practice

    CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 claude -p '/bett3r-ai-workflow:start-multi <ids>'

**That env var is not optional.** A tick runs until every unit of its wave is
terminal, which is hours, while print mode terminates background tasks after
600 s by default — so without it the orchestrator is killed before its step 8,
never prints `FLEET-STEP:v1`, and the driver correctly reads the absence as
`infra`. A truncated tick and a failed one are indistinguishable from the
verdict, which is why the ceiling is lifted at the invocation rather than
diagnosed afterwards. `0` means no ceiling.

Exit codes. The contract is the printed line, never the status (ADR-004); these
exist so `fleet-loop && <next>` composes:
    0  the run reached `waves=N/N`
    1  the driver stopped: no progress, infra, a non-success outcome, the tick
       cap, or a version refused after a tick
    2  bad invocation
"""

import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN_ROOT = os.path.dirname(HERE)
LANE_STEP = os.path.join(PLUGIN_ROOT, "bin", "lane-step")
MANIFEST = os.path.join(PLUGIN_ROOT, ".claude-plugin", "plugin.json")

STOPPED = 1
USAGE = 2

# `pluginVersion: 0.95.0` at the top level of run.yaml. A top-level scalar is
# read with a line match rather than a YAML parser because PyYAML is not an
# unconditional dependency of this plugin's scripts (only `design-map.py` imports
# it, lazily; the host gate treats a missing PyYAML as INCONCLUSIVE rather than
# installing it), and one scalar does not justify adding one.
PLUGIN_VERSION_IN_RUN = re.compile(r"^pluginVersion:[ \t]*['\"]?([^'\"\s]+)")

# `waves=k/N` as the verdict carries it. The MARKER line itself is parsed by
# bin/lane-step; this is only the shape of one attribute's value, after that
# parser has already accepted it.
WAVES = re.compile(r"^([0-9]+)/([0-9]+)$")


def resolved_version():
    """The version of the plugin copy this launcher belongs to.

    Nothing more is claimed. `PLUGIN_ROOT` comes from `__file__` with no symlink
    resolution, so invoked by path out of a branch checkout this reports the
    BRANCH's version, and invoked as a bare `fleet-loop` off `PATH` it reports the
    installed cache entry's. The driver does not need to know which: it compares
    this against the version the orchestrator REPORTED having loaded, rather than
    predicting what the subprocess will load.
    """
    with open(MANIFEST, encoding="utf-8") as handle:
        return json.load(handle)["version"]


def recorded_version(run_yaml):
    """The `pluginVersion` run.yaml recorded, or None when it recorded none.

    A run.yaml that does not exist reads as None for the same reason an existing
    one without the key does: on a fresh run the orchestrator creates the file in
    its own step 0, so before tick 1 both states mean "nothing to compare yet",
    and after a tick both mean the orchestrator did not write it.
    """
    if not os.path.isfile(run_yaml):
        return None
    with open(run_yaml, encoding="utf-8") as handle:
        for line in handle:
            match = PLUGIN_VERSION_IN_RUN.match(line)
            if match:
                return match.group(1)
    return None


def read_verdict(transcript):
    """The tick's verdict as a dict, or None for NO VERDICT.

    Shells out to `bin/lane-step --marker FLEET-STEP`: the parse rule has one
    implementation and this is not it.
    """
    result = subprocess.run(
        [LANE_STEP, "--marker", "FLEET-STEP", transcript],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        return None
    verdict = {}
    for line in result.stdout.decode("utf-8", "replace").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            verdict[key] = value
    return verdict


def run_tick(command):
    """Run one tick, echo its output, and return the path of its transcript."""
    handle, path = tempfile.mkstemp(prefix="fleet-tick.", suffix=".log")
    os.close(handle)
    with open(path, "wb") as sink:
        subprocess.run(command, shell=True, stdout=sink, stderr=subprocess.STDOUT)
    with open(path, encoding="utf-8", errors="replace") as source:
        sys.stdout.write(source.read())
    sys.stdout.flush()
    return path


def main(argv):
    run_dir = None
    tick = None
    args = argv[1:]
    while args:
        if args[0] == "--run" and len(args) >= 2:
            run_dir = args[1]
            args = args[2:]
        elif args[0] == "--tick" and len(args) >= 2:
            tick = args[1]
            args = args[2:]
        else:
            sys.stderr.write("usage: fleet-loop --run <run-dir> --tick <command>\n")
            return USAGE
    # Neither is defaulted. A guessed `--tick` would invoke some other
    # orchestrator, and without `--run` there is no run.yaml to read the recorded
    # version back out of, which is the one guard that must not be optional.
    if not run_dir or not tick:
        sys.stderr.write("usage: fleet-loop --run <run-dir> --tick <command>\n")
        return USAGE

    # A missing run.yaml is NOT an error here: a fresh run legitimately has none
    # until the orchestrator's step 0 creates it, during tick 1. Refusing on it
    # would mean the driver could never start a fresh run at all.
    run_yaml = os.path.join(run_dir, "run.yaml")
    resolved = resolved_version()
    recorded = recorded_version(run_yaml)
    if recorded is None:
        print(
            "fleet-loop: proceeding — %s records no pluginVersion yet (resolved=%s). "
            "Nothing has loaded the plugin before tick 1, so there is nothing to "
            "compare; the orchestrator records it in step 0 and the guard is live "
            "from tick 2." % (run_yaml, resolved)
        )

    previous_recorded = recorded
    previous_k = None
    previous_line = None
    tick_number = 0
    # The cap: a run needs at most one tick per wave, so N ticks bound any
    # healthy run. It is a termination floor under the no-progress guard, not a
    # substitute for it — a k that oscillates advances at every comparison and
    # would otherwise tick forever.
    cap = None

    while True:
        tick_number += 1
        print(
            "fleet-loop: tick %d — plugin resolved=%s recorded=%s"
            % (tick_number, resolved, previous_recorded or "not-yet-recorded")
        )
        transcript = run_tick(tick)
        verdict = read_verdict(transcript)
        os.unlink(transcript)

        # The version guard, before anything reads the verdict: a tick run by the
        # wrong plugin copy produces a verdict that is not this run's to act on,
        # terminal or not, so no verdict shape may bypass this.
        recorded = recorded_version(run_yaml)
        changed = (
            previous_recorded is not None
            and recorded is not None
            and recorded != previous_recorded
        )
        if changed:
            print(
                "fleet-loop: refused after tick %d — pluginVersion changed mid-run: "
                "recorded=%s, previous tick recorded=%s. The orchestrator writes it "
                "from the manifest it actually loaded, so a change means two ticks of "
                "one run ran different plugin versions."
                % (tick_number, recorded, previous_recorded)
            )
            return STOPPED
        if recorded is None:
            # Two very different facts wear the same absence. A run dir that does
            # not exist is operator error — a typo in `--run`, or the driver
            # launched from the wrong working directory — and naming it "contract
            # drift" sends the reader after the orchestrator for a mistake one
            # `os.path.isdir` identifies. The check belongs here and not before
            # tick 1, because refusing up front on a missing `run.yaml` is exactly
            # the refusal that broke every fresh run.
            if not os.path.isdir(run_dir):
                print(
                    "fleet-loop: refused after tick %d — the run directory %s does not "
                    "exist. Step 0 creates run.yaml inside an existing run dir, so a dir "
                    "that is still absent after a tick means --run names a path that is "
                    "not there: check the path and the working directory you launched "
                    "from. This is not contract drift." % (tick_number, run_dir)
                )
                return STOPPED
            print(
                "fleet-loop: refused after tick %d — %s still records no pluginVersion. "
                "Step 0 records it from the orchestrator's own loaded manifest on every "
                "tick, resume included, so absence after a tick is contract drift, not a "
                "cold start." % (tick_number, run_yaml)
            )
            return STOPPED
        if recorded != resolved:
            print(
                "fleet-loop: refused after tick %d — plugin version mismatch: "
                "resolved=%s recorded=%s. `claude -p` resolves the installed cache, not "
                "the branch; a driver would make that silent on every tick."
                % (tick_number, resolved, recorded)
            )
            return STOPPED
        previous_recorded = recorded

        if verdict is None:
            print(
                "fleet-loop: stopped after tick %d — outcome=infra: the tick printed "
                "no FLEET-STEP:v1 verdict line, and absence is the infra signal "
                "(ADR-004), never a wave that advanced." % tick_number
            )
            return STOPPED

        outcome = verdict.get("outcome", "")
        if outcome != "success":
            print(
                "fleet-loop: stopped after tick %d — outcome=%s: not a yield, so the "
                "run's own rule applies and the driver does not re-dispatch."
                % (tick_number, outcome)
            )
            return STOPPED

        waves = WAVES.match(verdict.get("waves", ""))
        if not waves:
            print(
                "fleet-loop: stopped after tick %d — outcome=infra: the verdict "
                "carried waves=%r, which is not k/N, so there is no wave count to "
                "compare." % (tick_number, verdict.get("waves", ""))
            )
            return STOPPED
        k, total = int(waves.group(1)), int(waves.group(2))
        line = "FLEET-STEP:v1 " + " ".join(
            "%s=%s" % (key, value) for key, value in verdict.items()
        )

        if k >= total:
            print(
                "fleet-loop: run terminal after %d tick(s) — waves=%d/%d, outcome=success."
                % (tick_number, k, total)
            )
            return 0

        if previous_k is not None and k == previous_k:
            print(
                "fleet-loop: stopped after tick %d — blocked-on=fleet-no-progress: "
                "waves=%d/%d did not advance between two consecutive ticks.\n"
                "  previous tick: %s\n"
                "  this tick:     %s" % (tick_number, k, total, previous_line, line)
            )
            return STOPPED

        if cap is None:
            cap = total
        if tick_number >= cap:
            print(
                "fleet-loop: stopped after tick %d — blocked-on=fleet-tick-cap: a run "
                "of %d waves cannot need more than %d ticks, and waves=%d/%d is not "
                "terminal." % (tick_number, total, cap, k, total)
            )
            return STOPPED

        previous_k = k
        previous_line = line


if __name__ == "__main__":
    sys.exit(main(sys.argv))
