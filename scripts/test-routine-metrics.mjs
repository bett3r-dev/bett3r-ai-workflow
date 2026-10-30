// Oracle for `run-metrics --routine-metrics`: the flat object a Blueprint Routine
// commits as <docs>/<KEY>/run-metrics.json in its signal commit (bett3r-routine
// /implement Step 7), for Steward to read at that sha.
//
// The fixture (scripts/fixtures/routine-metrics/projects/) is two sessions:
//   4444… opens on `main` (a haiku response before the checkout, Claude Code
//         2.1.300) and moves to `claude/T-1-reserve` (2.1.311): a sonnet response,
//         then opus ones (one written twice — tokens dedupe by message id), and an
//         executor subagent on the same branch.
//   5555… on `claude/T-2-unversioned`: its only assistant record carries no
//         `version`, the user record before it does (2.1.299).
// Every expected number below is summed by hand from those records.
//
// The default `run-metrics` output is held byte-identical by scripts/test-run-metrics.sh.
//
// Run locally:  node --test scripts/test-routine-metrics.mjs

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { cpSync, mkdtempSync, mkdirSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SCRIPT = join(ROOT, 'plugins', 'bett3r-ai-workflow', 'scripts', 'run-metrics.mjs')

// The fixture owns HOME: run-metrics reads ~/.claude/projects and caches under ~/.claude.
const homeWith = (projects) => {
  const h = mkdtempSync(join(tmpdir(), 'routine-metrics-'))
  mkdirSync(join(h, '.claude'), { recursive: true })
  if (projects) cpSync(projects, join(h, '.claude', 'projects'), { recursive: true })
  return h
}
const run = (home, ...args) => {
  const env = { ...process.env, HOME: home, TZ: 'UTC' }
  delete env.CLAUDE_CONFIG_DIR
  return execFileSync(process.execPath, [SCRIPT, ...args], { cwd: home, env, encoding: 'utf8' })
}

const FIXTURE = join(ROOT, 'scripts', 'fixtures', 'routine-metrics', 'projects')
const home = homeWith(FIXTURE)
process.on('exit', () => rmSync(home, { recursive: true, force: true }))

test('one compact line of flat scalars, schema 1, in the declared key order', () => {
  const out = run(home, 'claude/T-1-reserve', '--routine-metrics')
  assert.match(out, /^\{[^\n]*\}\n$/, 'one compact JSON line')
  assert.deepEqual(JSON.parse(out), {
    schema: 1,
    // a1 + a2 (once, deduped) + a3 + the executor's s1; never the haiku on main
    input_tokens: 10 + 5 + 5 + 1,
    output_tokens: 20 + 40 + 40 + 2,
    cache_read_tokens: 100 + 500 + 500 + 3,
    cache_write_tokens: 30 + 50 + 50 + 4,
    wall_ms: 60_000, // 10:00:00 → 10:01:00, the branch's records only
    active_ms: 70_000, // orchestrator 60s + executor 10s
    alive_ms: 60_000,
    stalled_ms: 0,
    agent_count: 1,
    api_calls: 4,
    model: 'claude-opus-5', // most tokens summed over usageByModel
    started_model: 'claude-sonnet-5', // the branch's first assistant record
    claude_version: '2.1.311', // that record's version, not main's 2.1.300
    cost_source: 'unpriced',
  })
})

test('never a cost, turns or api_ms; every number an integer', () => {
  const o = JSON.parse(run(home, 'claude/T-1-reserve', '--routine-metrics'))
  for (const k of ['cost_usd_micros', 'cost', 'turns', 'api_ms']) assert.ok(!(k in o), k)
  for (const [k, v] of Object.entries(o)) if (typeof v === 'number') assert.ok(Number.isInteger(v), k)
})

test('the branch filter: main reports only its own pre-checkout record', () => {
  const o = JSON.parse(run(home, 'main', '--routine-metrics'))
  assert.equal(o.input_tokens, 1000)
  assert.equal(o.model, 'claude-haiku-5')
  assert.equal(o.claude_version, '2.1.300')
})

test('claude_version falls back to the first versioned record', () => {
  const o = JSON.parse(run(home, 'claude/T-2-unversioned', '--routine-metrics'))
  assert.equal(o.started_model, 'claude-opus-5')
  assert.equal(o.claude_version, '2.1.299')
})

test('first_pass_green_permille is the summary firstPassGreen x 1000, omitted when unknown', () => {
  assert.ok(!('first_pass_green_permille' in JSON.parse(run(home, 'claude/T-1-reserve', '--routine-metrics'))))
  const h = homeWith(join(ROOT, 'scripts', 'fixtures', 'run-metrics', 'projects'))
  try {
    const summary = JSON.parse(run(h, 'feat/fixture', '--json'))
    const o = JSON.parse(run(h, 'feat/fixture', '--routine-metrics'))
    assert.ok(summary.firstPassGreen !== null)
    assert.equal(o.first_pass_green_permille, Math.round(summary.firstPassGreen * 1000))
    assert.equal(o.agent_count, summary.agentCount)
    assert.equal(o.wall_ms, summary.runElapsedMs)
  } finally { rmSync(h, { recursive: true, force: true }) }
})

test('no transcript for the branch, or no transcripts at all: exactly {"schema":1}', () => {
  assert.equal(run(home, 'claude/never-ran', '--routine-metrics'), '{"schema":1}\n')
  const empty = homeWith(null)
  try { assert.equal(run(empty, 'claude/T-1-reserve', '--routine-metrics'), '{"schema":1}\n') }
  finally { rmSync(empty, { recursive: true, force: true }) }
})
