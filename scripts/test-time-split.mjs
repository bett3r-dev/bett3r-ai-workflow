// Oracle for plugins/bett3r-ai-workflow/scripts/lib/time-split.mjs, the one
// classifier of a run's time (ADR-145 points 3-5): run-metrics imports it and
// Steward vendors it. The fixture is a stream-shaped record file holding a call
// of every activity, three parallel calls issued together, a Read overlapping a
// spawn, a 20-minute gap, two spawns and a message written twice. expected.json
// is computed by hand from it (its _comment walks the timeline).
//
// run-metrics' own output is held byte-identical by scripts/test-run-metrics.sh.
//
// Run locally:  node --test scripts/test-time-split.mjs

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SCRIPTS = join(ROOT, 'plugins', 'bett3r-ai-workflow', 'scripts')
const MODULE = join(SCRIPTS, 'lib', 'time-split.mjs')
const FIXTURE = join(SCRIPTS, 'fixtures', 'time-split')

const { timeSplit, ACTIVITIES } = await import(MODULE)
const records = readFileSync(join(FIXTURE, 'records.jsonl'), 'utf8').split('\n').filter(Boolean).map(l => JSON.parse(l))
const expected = JSON.parse(readFileSync(join(FIXTURE, 'expected.json'), 'utf8'))

const pick = (o, keys) => Object.fromEntries(keys.map(k => [k, o[k]]))
const wallSum = (a) => ACTIVITIES.reduce((t, k) => t + a[k].ms, 0) + Object.values(a.subagent).reduce((t, x) => t + x.ms, 0)

test('the classic split: tool, child, reason, stalled, tokens deduped by message id, lines', () => {
  const s = timeSplit(records)
  const e = expected.default
  assert.deepEqual(pick(s, Object.keys(e.fields)), e.fields)
})

test('every call carries its activity, by the rule order', () => {
  const s = timeSplit(records)
  assert.deepEqual(s.calls.map(c => [c.id, c.activity]), expected.default.callActivities)
})

test('activities: first-started wins on overlap, spawns are subagent time by role, gaps think then idle', () => {
  const s = timeSplit(records)
  assert.deepEqual(s.activities, expected.default.activities)
})

test('activity ms sum to exactly the wall time, never more', () => {
  const s = timeSplit(records)
  assert.equal(wallSum(s.activities), s.elapsedMs)
})

test('usageByModel: per model, deduped by message id, thinkingTokens only where a record carries it', () => {
  const s = timeSplit(records)
  assert.deepEqual(s.usageByModel, expected.default.usageByModel)
})

test('declared testCommands / buildCommands override the built-in patterns, and move only activities', () => {
  const e = expected.declared
  const s = timeSplit(records, e.options)
  assert.deepEqual(s.calls.map(c => [c.id, c.activity]), e.callActivities)
  assert.deepEqual(s.activities, e.activities)
  assert.equal(wallSum(s.activities), s.elapsedMs)
  const base = timeSplit(records)
  const strip = (x) => { const { activities, calls, ...rest } = x; return { ...rest, calls: calls.map(({ activity, ...c }) => c) } }
  assert.deepEqual(strip(s), strip(base))
})

test('stallMs moves the thinking / idle line of a gap', () => {
  const e = expected.stall
  const s = timeSplit(records, e.options)
  assert.deepEqual(pick(s, Object.keys(e.fields)), e.fields)
  assert.equal(s.activities.thinking.ms, e.thinkingMs)
  assert.equal(s.activities.idle.ms, e.idleMs)
  assert.equal(wallSum(s.activities), s.elapsedMs)
})

test('transcript camelCase toolUseResult reads the same as stream snake_case tool_use_result', () => {
  const camel = records.map(r => {
    if (!r.tool_use_result) return r
    const { tool_use_result: t, ...rest } = r
    return { ...rest, toolUseResult: t }
  })
  const a = timeSplit(camel), b = timeSplit(records)
  assert.equal(a.linesAdded, 2)
  assert.deepEqual(a, b)
})

test('records with no timestamp are ignored; none at all is null', () => {
  assert.equal(timeSplit([]), null)
  assert.equal(timeSplit(records.map(({ timestamp, ...r }) => r)), null)
})

test('the module is vendorable: it imports nothing', () => {
  const src = readFileSync(MODULE, 'utf8')
  assert.equal(/^\s*import\s/m.test(src) || /\bimport\s*\(/.test(src) || /\brequire\s*\(/.test(src), false)
})

test('role and model names that are Object.prototype members stay own keys and mutate nothing', () => {
  const t = (s) => `2026-02-01T10:00:${s}.000Z`
  const spawn = (id, mid, model, desc, at) => ({ type: 'assistant', timestamp: t(at), message: { id: mid, model, usage: { input_tokens: 1, output_tokens: 1 }, content: [{ type: 'tool_use', id, name: 'Agent', input: { description: desc } }] } })
  const done = (id, at) => ({ type: 'user', timestamp: t(at), message: { content: [{ type: 'tool_result', tool_use_id: id, content: 'ok' }] } })
  const recs = [
    spawn('p1', 'a1', 'constructor', 'constructor work', '00'),
    done('p1', '10'),
    spawn('p2', 'a2', '__proto__', '__proto__ work', '20'),
    done('p2', '30'),
    spawn('p3', 'a3', 'toString', 'toString work', '40'),
    done('p3', '50'),
  ]
  const s = timeSplit(recs)
  for (const k of ['constructor', '__proto__', 'toString']) {
    assert.equal(Object.hasOwn(s.activities.subagent, k), true, `role ${k} is an own key`)
    assert.equal(Object.hasOwn(s.usageByModel, k), true, `model ${k} is an own key`)
  }
  assert.equal(s.activities.subagent.constructor.calls, 1)
  assert.equal(Object.calls, undefined)
  assert.equal(Object.prototype.ms, undefined)
  assert.equal(Object.prototype.calls, undefined)
  assert.equal(({}).inputTokens, undefined)
  assert.equal(wallSum(s.activities), s.elapsedMs)
})
