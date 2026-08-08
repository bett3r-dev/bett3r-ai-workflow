# A plugin's version string is its release contract

Behaviour reaches a user through four steps — source tree → marketplace checkout → version-keyed cache copy → session load — and only the third is conditional. The checkout refreshes itself unconditionally, because that refresh is a `git pull`; the copy into `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` fires on exactly one condition, that the `version` string in `plugins/<name>/.claude-plugin/plugin.json` differs from the one a cache directory is already keyed by. So that string is not metadata. It is the release contract: change anything inside `plugins/<name>/**` without changing it and you have shipped nothing to anyone. A CI gate — `scripts/check-plugin-version-bump.sh`, wired into `.github/workflows/validate-plugins.yml` — now refuses any PR that touches a plugin's payload without bumping that plugin's version.

## Why this needed a gate rather than a note

The cache directory is *literally* keyed by version; on the machine that diagnosed this, `0.11.0/`, `0.12.0/` and `0.13.0/` sit side by side. Same string, no new directory, no copy — the pull still lands, the checkout is still correct, and every session goes on loading the bytes it already had.

That is what happened. `plugin.json` sat at `0.12.0`, last bumped in `008bbc7` (#92), while two behaviour-changing commits landed on top of it: `a8d71ad` (#116), which shipped the board's withdrawal gesture, and `a0eaab0` (#117), which shipped the summon watcher. Users kept receiving `0.12.0`. The defect survived both.

Every gate in both repos was green throughout, and green *correctly* — every gate tests the source tree, and the source tree was right. **A test cannot observe release drift from inside the tree it validates.** This is not a gap somebody forgot to cover; it is a class of defect that is structurally invisible to source-tree testing, because the defect lives in the relationship between a diff and a version string, and no file contains that.

The misdiagnosis is worth recording, because it cost more than the bump did. The ticket that filed this ran `grep -rni summon` over the *installed plugin cache*, got zero hits, and concluded the watcher had never been built. The same grep in the source tree returned 38. The ticket's premise was the exact inverse of the truth: the consumer existed, it just was not installed. **"The consumer exists" and "the consumer is installed" are different claims, and only the second one makes the button honest.**

The bump itself shipped as `b151774` (#124), `0.12.0 → 0.13.0`, and was verified live: the cache gained a `0.13.0/` directory and a fresh session picked up the new skill descriptions. The gate is the control against recurrence, not the fix.

## Consequences

**Only `plugin.json` is load-bearing.** Through the whole incident the marketplace checkout kept refreshing itself to the newest commit while `.claude-plugin/marketplace.json`'s own `metadata.version` sat at `0.9.0` — because that refresh is a `git pull`, independent of that field. Bumping `marketplace.json` is repo convention (`598cf13`, `9b22996` and `99b1e16` all did it) and nothing more. It propagates nothing. This has to be said plainly, or the next person bumps `metadata.version` alone and cannot work out why nothing moved.

**`plugins/<name>/README.md` is inside the payload**, so it is part of the release, so a stale one is a user reading last release's instructions. That is why the gate treats a README-only change as requiring a bump. The occasional unnecessary bump costs one line.

**The gate sits outside the payload** — in `.github/workflows/` and `scripts/` — and therefore does not fire on its own change. That is a property of where it lives, not an exemption it grants itself: nothing outside `plugins/**` is ever copied into any cache, so nothing outside `plugins/**` has anything to release.

**Verification is necessarily multi-session.** Plugins load at session start, so the session that makes a release fix can never confirm it — which is precisely how the original defect survived two releases, with a green tree in front of it the whole time. The confirmation step is: bump → merge → refresh → **a new session** → assert that the new version's cache directory exists and that the loaded skill text carries the change.

**The gate makes a weaker claim than it appears to.** It catches the *omission, at PR time*. It does not observe the cache, does not verify propagation, and cannot tell you that any user received anything. "We now detect release drift" would be the false version of this sentence; the true one is that we now refuse the one mistake that caused it.

## Considered options

- **A release toolchain — release-please, changesets.** Correct machinery for the general case and disproportionate to this one: two plugins, one monorepo, a single operator. The ceremony exceeds the problem.
- **Manual discipline — "remember to bump."** This is what we already had. It failed twice, silently, and survived two releases before anyone noticed. A rule nothing enforces is the rule that produced this ADR.
- **Running `/plugin update` when the symptom appears.** Fixes one machine, not the class, and leaves the version string still lying about what it names — every other user stays on the old build.
- **Symlinking the repo into the cache.** A local hack that ships nothing to anyone else, and it makes the machine most likely to notice this bug the one machine that can no longer experience it.
