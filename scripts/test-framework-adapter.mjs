// Oracle for every plugins/*/skills/framework-adapter/SKILL.md: a framework
// adapter is the vocabulary a Blueprint design run reads before modelling, so it
// maps each of the board's eight fixed kinds, and it holds no rule of the method
// (those live in the server's method text, sha-checked there). The rule half is
// asserted by wordlist: none of METHOD_WORDS appears, case-insensitively, as a
// whole word. A kind counts as mapped when it is the last cell of a table row.
//
// Run locally:  node --test scripts/test-framework-adapter.mjs

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const PLUGINS = join(ROOT, 'plugins')

export const KINDS = ['command', 'event', 'aggregate', 'policy', 'read model', 'external system', 'screen', 'invariant']
export const METHOD_WORDS = ['refuse', 'refused', 'must', 'stage', 'Map agreed', 'Design done']

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

// The kinds named in the last cell of any markdown table row.
export function mappedKinds(text) {
  const found = new Set()
  for (const line of text.split('\n')) {
    const cells = line.trim().match(/^\|(.*)\|$/)?.[1].split('|').map(c => c.trim())
    if (!cells || cells.length < 2) continue
    const last = cells[cells.length - 1].toLowerCase()
    for (const k of KINDS) if (new RegExp(`^${esc(k)}\\b`).test(last)) found.add(k)
  }
  return KINDS.filter(k => found.has(k))
}

// Each line carrying a method word, as "<line no>: <word>".
export function methodWords(text) {
  const hits = []
  text.split('\n').forEach((line, i) => {
    for (const w of METHOD_WORDS) {
      if (new RegExp(`\\b${esc(w)}\\b`, 'i').test(line)) hits.push(`${i + 1}: ${w}`)
    }
  })
  return hits
}

const adapters = readdirSync(PLUGINS)
  .map(p => join(PLUGINS, p, 'skills', 'framework-adapter', 'SKILL.md'))
  .filter(existsSync)

test('positive control: the detectors fire on a bad specimen and pass a good one', () => {
  const bad = '| x | command |\n| y | event |\nYou must refuse at the map stage.\nOnce Map agreed, write Design done.'
  assert.deepEqual(mappedKinds(bad), ['command', 'event'])
  assert.deepEqual(methodWords(bad), ['3: refuse', '3: must', '3: stage', '4: Map agreed', '4: Design done'])
  const good = KINDS.map(k => `| t | ${k} (note) |`).join('\n') + '\nMustard and staged are other words.'
  assert.deepEqual(mappedKinds(good), KINDS)
  assert.deepEqual(methodWords(good), [])
})

test('at least one framework adapter exists', () => {
  assert.ok(adapters.length > 0, 'no plugins/*/skills/framework-adapter/SKILL.md found')
})

for (const file of adapters) {
  const rel = file.slice(ROOT.length + 1)
  const text = readFileSync(file, 'utf8')
  test(`${rel} maps all 8 board kinds`, () => {
    assert.deepEqual(mappedKinds(text), KINDS, `missing: ${KINDS.filter(k => !mappedKinds(text).includes(k)).join(', ')}`)
  })
  test(`${rel} carries no method word`, () => {
    assert.deepEqual(methodWords(text), [])
  })
}
