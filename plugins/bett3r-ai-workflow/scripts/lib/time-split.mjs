/**
 * time-split — classify one run's time into activities. Pure: no I/O, no clock,
 * no imports. run-metrics uses it for every transcript it reads, and Steward
 * vendors this file to classify a stream it timestamped itself (ADR-145 point 4:
 * one classifier, so two counters cannot drift). Change it here only.
 *
 *   timeSplit(records, { testCommands = [], buildCommands = [], stallMs = 180_000 } = {})
 *
 * `records` are transcript-shaped: `{ type, timestamp, message: { id, model, usage,
 * content }, toolUseResult? }`; stream-json's snake_case `tool_use_result` is read too.
 * A record with no parseable `timestamp` is ignored. Returns null when none has one.
 *
 * WHY THE NUMBERS ARE CLASSIFIED, NOT SUBTRACTED (each rule was measured wrong first):
 *  - Wall time is not work: every ms between the first and last record is put in
 *    exactly one bucket. A gap with no tool or child running is the model thinking
 *    up to `stallMs`; beyond that it is a parked session (idle / `stalledMs`).
 *  - One API response is written as several records sharing `message.id`, each
 *    repeating its `usage`. Tokens are deduped by message id.
 *  - A spawn (Agent, Task, Workflow) spans the child's whole run. It is child time
 *    (`childMs`, `activities.subagent[role]`), never the caller's own work.
 *
 * ACTIVITIES (`activities`, each `{ ms, calls }`; `subagent` is `{ [role]: { ms, calls } }`):
 *  - Agent / Task / Workflow -> subagent, role = input.subagent_type, else the first
 *    word of input.description, else `unknown`.
 *  - mcp__blueprint__* -> board. Read, Glob, Grep, mcp__blueprint_repo__*, WebFetch,
 *    WebSearch -> reading. Edit, Write, MultiEdit, NotebookEdit -> editing.
 *  - Bash: a command starting with a `testCommands` prefix -> tests, a
 *    `buildCommands` prefix -> building (declared prefixes win); else a wait (a
 *    `sleep`) -> idle; else by `classifyCommand`: test -> tests; build, typecheck,
 *    generate, lint, install -> building; git -> git; search/read -> reading; else other.
 *  - Monitor (a wait) -> idle. Any other tool -> other.
 *  - Gaps with nothing running: up to `stallMs` -> thinking, the rest -> idle.
 *
 * OVERLAP RULE: first-started wins. Parallel calls overlap; each ms of the run is
 * owned by exactly one interval, the one that started earliest among those running
 * at that ms (a tie goes to the one issued first in record order). So the activity
 * ms, subagents included, sum to exactly the wall time (`elapsedMs`), and never more.
 * A call fully shadowed by an earlier one still counts in its activity's `calls`
 * with 0 ms. `thinking.calls` is 0; `idle.calls` counts wait calls only.
 */

/** Non-tool silence beyond this is not the model working: it is a parked session. */
export const STALL_MS = 3 * 60_000
/** Dead gaps at or above this are listed individually, so "one lunch" != "ten pauses". */
export const GAP_REPORT_MS = 15 * 60_000
/** Spawning tools whose duration belongs to the child, never the caller. */
export const SPAWN_TOOLS = new Set(['Agent', 'Task', 'Workflow'])

export const ACTIVITIES = ['thinking', 'reading', 'editing', 'tests', 'building', 'git', 'board', 'other', 'idle']

const READING_TOOLS = new Set(['Read', 'Glob', 'Grep', 'WebFetch', 'WebSearch'])
const EDITING_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit'])

/** Merge overlapping [start,end] intervals and return their total covered span. */
export const unionMs = (iv) => {
  const s = iv.filter(([a, b]) => b > a).sort((x, y) => x[0] - y[0])
  const merged = []
  for (const [a, b] of s) {
    const last = merged[merged.length - 1]
    if (last && a <= last[1]) last[1] = Math.max(last[1], b)
    else merged.push([a, b])
  }
  return { merged, total: merged.reduce((t, [a, b]) => t + (b - a), 0) }
}

/** Bucket a shell command by what it costs, not by its exact text. */
export function classifyCommand(cmd) {
  const c = cmd.toLowerCase()
  const pairs = [
    [/\b(yarn|npm|pnpm)\s+(run\s+)?build\b|tsc\s+-b|turbo\s+run\s+build/, 'build'],
    [/\b(yarn|npm|pnpm)\s+(run\s+)?typecheck\b|tsc\s+--noemit/, 'typecheck'],
    [/\b(yarn|npm|pnpm)\s+(run\s+)?test\b|vitest|jest|node\s+--test/, 'test'],
    [/\b(yarn|npm|pnpm)\s+install\b|yarn\s*$/, 'install'],
    [/\b(yarn|npm|pnpm)\s+(run\s+)?lint\b|eslint/, 'lint'],
    [/\bgenerate/, 'generate'],
    [/^\s*git\b/, 'git'],
    [/\b(rg|grep|find|ls|cat|head|tail|wc|sed|awk)\b/, 'search/read'],
    [/\bgh\b/, 'gh'],
    [/\bdocker|kubectl|helm|k3d\b/, 'infra'],
  ]
  for (const [re, name] of pairs) if (re.test(c)) return name
  return 'other'
}

/** A call that only waits: a shell sleep or poll loop, or a Monitor. */
export const isWaitCall = (c) => c.tool === 'Monitor' || (c.tool === 'Bash' && /\bsleep\b/.test(c.cmd ?? ''))

const COMMAND_ACTIVITY = {
  test: 'tests', build: 'building', typecheck: 'building', generate: 'building', lint: 'building',
  install: 'building', git: 'git', 'search/read': 'reading',
}

const startsWithAny = (cmd, prefixes) => prefixes.some(p => typeof p === 'string' && p.trim() && cmd.startsWith(p.trim()))

/** The activity of one non-spawn call. `cmd` is the whitespace-collapsed command. */
export function activityOf(tool, cmd, { testCommands = [], buildCommands = [] } = {}) {
  if (tool.startsWith('mcp__blueprint__')) return 'board'
  if (READING_TOOLS.has(tool) || tool.startsWith('mcp__blueprint_repo__')) return 'reading'
  if (EDITING_TOOLS.has(tool)) return 'editing'
  if (tool === 'Bash') {
    const c = (cmd ?? '').trim()
    if (startsWithAny(c, testCommands)) return 'tests'
    if (startsWithAny(c, buildCommands)) return 'building'
    if (isWaitCall({ tool, cmd: c })) return 'idle'
    return COMMAND_ACTIVITY[classifyCommand(c)] ?? 'other'
  }
  if (isWaitCall({ tool, cmd })) return 'idle'
  return 'other'
}

/** A spawn's role: subagent_type, else the first word of its description, else `unknown`. */
export function subagentRole(input) {
  const i = input ?? {}
  if (typeof i.subagent_type === 'string' && i.subagent_type.trim()) return i.subagent_type.trim()
  const w = typeof i.description === 'string' ? i.description.trim().split(/\s+/)[0] : ''
  return w || 'unknown'
}

/**
 * First-started wins: each ms covered by any interval goes to the earliest-started
 * one running then (ties: lowest `order`). Returns ms owned per interval index.
 */
function ownMs(items) {
  const owned = items.map(() => 0)
  // started order; the earliest still running is always at `head`, since every
  // interval before it has ended
  const by = items.map((_, j) => j).filter(j => items[j].b > items[j].a)
    .sort((x, y) => items[x].a - items[y].a || items[x].order - items[y].order)
  const pts = [...new Set(by.flatMap(j => [items[j].a, items[j].b]))].sort((x, y) => x - y)
  let added = 0, head = 0
  for (let k = 0; k + 1 < pts.length; k++) {
    const lo = pts[k], hi = pts[k + 1]
    while (added < by.length && items[by[added]].a <= lo) added++
    while (head < added && items[by[head]].b <= lo) head++
    if (head < added) owned[by[head]] += hi - lo
  }
  return owned
}

export function timeSplit(records, { testCommands = [], buildCommands = [], stallMs = STALL_MS } = {}) {
  const ev = records.filter(r => r.timestamp).map(r => ({ ...r, t: Date.parse(r.timestamp) }))
    .filter(r => Number.isFinite(r.t)).sort((a, b) => a.t - b.t)
  if (!ev.length) return null

  // tool_use id -> when it was issued, and what it was
  const useAt = new Map(), useName = new Map(), useInput = new Map(), useRaw = new Map(), useOrder = new Map()
  for (const r of ev) {
    if (r.type !== 'assistant' || !Array.isArray(r.message?.content)) continue
    for (const c of r.message.content) {
      if (c.type !== 'tool_use') continue
      useAt.set(c.id, r.t); useName.set(c.id, c.name); useRaw.set(c.id, c.input ?? {})
      if (!useOrder.has(c.id)) useOrder.set(c.id, useOrder.size)
      const i = c.input ?? {}
      useInput.set(c.id, String(i.command ?? i.file_path ?? i.pattern ?? i.description ?? '').replace(/\s+/g, ' ').trim())
    }
  }

  // `calls`: every non-spawn call on its own, so one blocked call can be named
  // (BIGGEST SINGLE CALLS) instead of disappearing into `tool`.
  const toolIv = [], childIv = [], byTool = new Map(), bashCalls = [], calls = [], spawns = []
  let added = 0, removed = 0
  const files = new Set()

  for (const r of ev) {
    if (r.type !== 'user' || !Array.isArray(r.message?.content)) continue
    for (const c of r.message.content) {
      if (c.type !== 'tool_result' || !useAt.has(c.tool_use_id)) continue
      const a = useAt.get(c.tool_use_id), b = r.t
      const name = useName.get(c.tool_use_id) ?? '?'
      const dur = Math.max(0, b - a)

      const agg = byTool.get(name) ?? { n: 0, ms: 0 }
      agg.n++; agg.ms += dur; byTool.set(name, agg)

      // a spawn's duration is the child's run, never the caller's work
      if (SPAWN_TOOLS.has(name)) {
        childIv.push([a, b])
        spawns.push({ id: c.tool_use_id, role: subagentRole(useRaw.get(c.tool_use_id)), at: a, ms: dur })
      } else {
        toolIv.push([a, b])
        const cmd = useInput.get(c.tool_use_id)
        calls.push({ id: c.tool_use_id, tool: name, at: a, ms: dur, cmd, activity: activityOf(name, cmd, { testCommands, buildCommands }) })
      }
      if (name === 'Bash') bashCalls.push({ ms: dur, cmd: useInput.get(c.tool_use_id) ?? '' })

      const T = r.toolUseResult ?? r.tool_use_result
      if (T && typeof T === 'object') {
        if (Array.isArray(T.structuredPatch)) {
          if (T.filePath) files.add(T.filePath)
          for (const h of T.structuredPatch) for (const ln of (h.lines ?? [])) {
            if (ln.startsWith('+')) added++
            else if (ln.startsWith('-')) removed++
          }
        } else if (T.type === 'create' && typeof T.content === 'string') {
          if (T.filePath) files.add(T.filePath)
          added += T.content.split('\n').length
        }
      }
    }
  }

  const tool = unionMs(toolIv)
  const child = unionMs(childIv)
  // a spawn interval swallows the tools the parent ran concurrently; count each ms once
  const busy = unionMs([...toolIv, ...childIv])

  // Walk the lifetime and classify every gap that is not tool or child. Reasoning
  // is kept as INTERVALS, not just a total: a run is "alive" while it thinks.
  const span0 = ev[0].t, span1 = ev[ev.length - 1].t
  let reason = 0, stalled = 0, cursor = span0
  const deadGaps = [], reasonIv = []
  const classifyGap = (from, to) => {
    const gap = to - from
    if (gap <= 0) return
    const think = Math.min(gap, stallMs)
    reason += think
    reasonIv.push([from, from + think])
    stalled += Math.max(0, gap - stallMs)
    if (gap >= GAP_REPORT_MS) deadGaps.push({ from, to, ms: gap })
  }
  for (const [a, b] of busy.merged) {
    classifyGap(cursor, a)
    cursor = Math.max(cursor, b)
  }
  classifyGap(cursor, span1)

  // activities: busy time by first-started wins, gap time as thinking / idle
  const activities = Object.fromEntries(ACTIVITIES.map(k => [k, { ms: 0, calls: 0 }]))
  const subMap = new Map()
  const order = (id) => useOrder.get(id) ?? Infinity
  const items = [
    ...calls.map(c => ({ a: c.at, b: c.at + c.ms, order: order(c.id), add: (ms) => { activities[c.activity].ms += ms } })),
    ...spawns.map(s => ({ a: s.at, b: s.at + s.ms, order: order(s.id), add: (ms) => { subMap.get(s.role).ms += ms } })),
  ]
  for (const c of calls) activities[c.activity].calls++
  for (const s of spawns) {
    let x = subMap.get(s.role)
    if (!x) subMap.set(s.role, x = { ms: 0, calls: 0 })
    x.calls++
  }
  ownMs(items).forEach((ms, j) => items[j].add(ms))
  activities.subagent = Object.fromEntries(subMap)
  activities.thinking.ms += reason
  activities.idle.ms += stalled

  // dedupe usage by message id
  const usage = new Map(), usageModel = new Map()
  const models = new Map(), efforts = new Map()
  for (const r of ev) {
    if (r.type !== 'assistant' || !r.message?.usage) continue
    usage.set(r.message.id, r.message.usage)
    usageModel.set(r.message.id, r.message.model ?? 'unknown')
    if (r.message.model) models.set(r.message.model, (models.get(r.message.model) ?? 0) + 1)
    const eff = r.effort ?? null
    if (eff) efforts.set(eff, (efforts.get(eff) ?? 0) + 1)
  }
  const tok = { input: 0, cacheWrite: 0, cacheRead: 0, output: 0 }
  const modelMap = new Map()
  for (const [id, u] of usage) {
    tok.input += u.input_tokens ?? 0
    tok.cacheWrite += u.cache_creation_input_tokens ?? 0
    tok.cacheRead += u.cache_read_input_tokens ?? 0
    tok.output += u.output_tokens ?? 0
    const m = usageModel.get(id)
    let x = modelMap.get(m)
    if (!x) modelMap.set(m, x = { inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 })
    x.inputTokens += u.input_tokens ?? 0
    x.outputTokens += u.output_tokens ?? 0
    x.cacheReadTokens += u.cache_read_input_tokens ?? 0
    x.cacheWriteTokens += u.cache_creation_input_tokens ?? 0
    // only what the records carry: a thinking count appears when a usage block has one
    if (typeof u.thinking_tokens === 'number') x.thinkingTokens = (x.thinkingTokens ?? 0) + u.thinking_tokens
  }
  const usageByModel = Object.fromEntries(modelMap)
  const top = (m) => [...m.entries()].sort((a, b) => b[1] - a[1])
  const dominant = (m) => (top(m)[0]?.[0]) ?? 'unknown'

  // A fix round sent to an agent that already reported (SendMessage) writes no
  // new transcript: the resume lands in THIS one, as a later user row carrying
  // text. Count those, so a continued executor is still a second pass. The one
  // other later text row seen in real transcripts is the background-wake
  // banner, which is not a pass.
  const userText = (r) => {
    const c = r.message?.content
    if (typeof c === 'string') return c
    if (!Array.isArray(c) || c.some(x => x.type === 'tool_result')) return null
    const t = c.filter(x => x.type === 'text').map(x => x.text ?? '')
    return t.length ? t.join('\n') : null
  }
  const texts = ev.filter(r => r.type === 'user').map(userText).filter(t => t !== null)
  const resumes = texts.slice(1).filter(t => !t.startsWith('[SYSTEM NOTIFICATION')).length

  return {
    resumes,
    start: span0, end: span1,
    elapsedMs: span1 - span0,
    toolMs: tool.total, childMs: child.total, reasonMs: reason, stalledMs: stalled,
    activeMs: tool.total + reason,
    // tool and reason never overlap (reason is measured in the gaps between busy
    // spans), so their union is exactly activeMs and clipping stays additive.
    toolIntervals: tool.merged,
    reasonIntervals: unionMs(reasonIv).merged,
    activeIntervals: unionMs([...tool.merged, ...reasonIv]).merged,
    childIntervals: child.merged,
    model: dominant(models), models: top(models).map(([k, v]) => ({ model: k, calls: v })),
    effort: dominant(efforts), efforts: top(efforts).map(([k, v]) => ({ effort: k, calls: v })),
    apiCalls: usage.size,
    tokens: tok,
    toolCalls: [...byTool.values()].reduce((t, x) => t + x.n, 0),
    byTool: Object.fromEntries([...byTool.entries()].map(([k, v]) => [k, v])),
    linesAdded: added, linesRemoved: removed, filesTouched: files.size,
    bashCalls, calls, deadGaps,
    activities, usageByModel,
  }
}
