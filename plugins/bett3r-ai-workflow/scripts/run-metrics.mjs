#!/usr/bin/env node
/**
 * run-metrics — reconstruct where a unit of work's time and tokens actually went.
 *
 * Reads Claude Code's own transcripts (`~/.claude/projects/**`). Nothing is
 * instrumented and nothing is written by the flow itself, so this works
 * retroactively on every run already on disk.
 *
 * THE FOUR THINGS THAT MAKE THE NUMBERS TRUE — each one was measured wrong first:
 *
 *  1. A unit of work is NOT a session. `/clear` and `/handoff` mean design, plan
 *     and build routinely sit in different sessions; one real branch spanned 26.
 *     So the join key is the **git branch** (on every transcript record), never
 *     the session id.
 *
 *  2. Wall time is NOT elapsed time. first→last timestamp once reported 3,587
 *     minutes for an agent whose real work was 52 — the rest was one 2.4-day gap
 *     with the session parked. Every millisecond is therefore CLASSIFIED, not
 *     subtracted: tool / reason / child / stalled.
 *
 *  3. One API response is written as SEVERAL jsonl records sharing `message.id`,
 *     each repeating the same `usage` block. Summing rows inflates tokens 2-4x.
 *     Dedupe by message id.
 *
 *  4. A parent's `Agent` tool call spans the child's ENTIRE run. Counted as the
 *     parent's tool time it double-bills the child's hours (one fleet agent read
 *     89% "tool time" that was really 15 nested children). It is tracked
 *     separately as `child` and never as work the parent did.
 */

import { readFileSync, readdirSync, existsSync, statSync, mkdirSync, writeFileSync } from 'node:fs'
import { join, basename } from 'node:path'
import { homedir } from 'node:os'
import { execFileSync } from 'node:child_process'

const PROJECTS = join(homedir(), '.claude', 'projects')
const STORE = join(homedir(), '.claude', 'bett3r-metrics')
const INDEX = join(STORE, 'index.jsonl')
const CACHE = join(STORE, '.session-index.json')

/** Non-tool silence beyond this is not the model working — it is a parked session. */
const STALL_MS = 3 * 60_000
/** Dead gaps at or above this are listed individually, so "one lunch" != "ten pauses". */
const GAP_REPORT_MS = 15 * 60_000
/** Spawning tools whose duration belongs to the child, never the caller. */
const SPAWN_TOOLS = new Set(['Agent', 'Task', 'Workflow'])

const PIPELINE = ['start-multi', 'start', 'design-multi', 'design', 'plan', 'build',
  'verify-build', 'commit', 'capture-learnings', 'evolve', 'inline-fix', 'run-report']

// ─────────────────────────────────────────────────────────── helpers

const readJsonl = (p) => {
  const out = []
  for (const line of readFileSync(p, 'utf8').split('\n')) {
    if (!line) continue
    try { out.push(JSON.parse(line)) } catch { /* a torn last line is normal on a live session */ }
  }
  return out
}
const ms2min = (x) => x / 60_000
const fmtMin = (x) => `${ms2min(x).toFixed(1)}m`
const fmtDur = (x) => ms2min(x) >= 90 ? `${(x / 3_600_000).toFixed(1)}h` : `${ms2min(x).toFixed(1)}m`
const fmtTok = (x) => x >= 1e6 ? `${(x / 1e6).toFixed(2)}M` : x >= 1e3 ? `${Math.round(x / 1e3)}k` : `${x}`
const pct = (a, b) => b > 0 ? `${Math.round(100 * a / b)}%` : '—'

/** Merge overlapping [start,end] intervals and return their total covered span. */
const unionMs = (iv) => {
  const s = iv.filter(([a, b]) => b > a).sort((x, y) => x[0] - y[0])
  const merged = []
  for (const [a, b] of s) {
    const last = merged[merged.length - 1]
    if (last && a <= last[1]) last[1] = Math.max(last[1], b)
    else merged.push([a, b])
  }
  return { merged, total: merged.reduce((t, [a, b]) => t + (b - a), 0) }
}

// ─────────────────────────────────────────────────────────── session discovery

/**
 * Which sessions touched this branch? Every record carries `gitBranch`, but a
 * session that *created* the branch opens on the old one, so the whole file has
 * to be searched — not just its head. Results are cached by (size, mtime) so
 * repeat runs and backfills stay cheap.
 */
function findSessions(branch, { since = null, quiet = false } = {}) {
  let cache = {}
  if (existsSync(CACHE)) { try { cache = JSON.parse(readFileSync(CACHE, 'utf8')) } catch { cache = {} } }

  const hits = []
  let scanned = 0, reused = 0

  for (const proj of readdirSync(PROJECTS)) {
    const dir = join(PROJECTS, proj)
    let st
    try { st = statSync(dir) } catch { continue }
    if (!st.isDirectory()) continue

    for (const file of readdirSync(dir)) {
      if (!file.endsWith('.jsonl')) continue
      const p = join(dir, file)
      let fst
      try { fst = statSync(p) } catch { continue }
      if (since && fst.mtimeMs < since) continue

      const key = p
      const stamp = `${fst.size}:${Math.floor(fst.mtimeMs)}`
      let branches = cache[key]?.stamp === stamp ? cache[key].branches : null

      if (branches === null) {
        scanned++
        const text = readFileSync(p, 'utf8')
        const found = new Set()
        // cheap scan: pull every distinct gitBranch literal out in one pass
        const re = /"gitBranch":"((?:[^"\\]|\\.)*)"/g
        let m
        while ((m = re.exec(text)) !== null) found.add(m[1])
        branches = [...found]
        cache[key] = { stamp, branches }
      } else reused++

      if (branches.includes(branch)) hits.push(p)
    }
  }

  try { mkdirSync(STORE, { recursive: true }); writeFileSync(CACHE, JSON.stringify(cache)) } catch { /* cache is an optimisation */ }
  if (!quiet) console.error(`  scanned ${scanned} session file(s), ${reused} cached — ${hits.length} touched "${branch}"`)
  return hits
}

/** Every branch seen on disk, most-recently-touched first. */
function listBranches({ since = null } = {}) {
  const seen = new Map()
  for (const proj of readdirSync(PROJECTS)) {
    const dir = join(PROJECTS, proj)
    try { if (!statSync(dir).isDirectory()) continue } catch { continue }
    for (const file of readdirSync(dir)) {
      if (!file.endsWith('.jsonl')) continue
      const p = join(dir, file)
      let fst; try { fst = statSync(p) } catch { continue }
      if (since && fst.mtimeMs < since) continue
      const text = readFileSync(p, 'utf8')
      const re = /"gitBranch":"((?:[^"\\]|\\.)*)"/g
      let m
      while ((m = re.exec(text)) !== null) {
        const prev = seen.get(m[1])
        if (!prev || prev < fst.mtimeMs) seen.set(m[1], fst.mtimeMs)
      }
    }
  }
  return [...seen.entries()].sort((a, b) => b[1] - a[1])
}

// ─────────────────────────────────────────────────────────── one agent run

/**
 * Classify one transcript (a session's main thread, or one subagent) into
 * tool / reason / child / stalled, with tokens deduped and edits counted.
 */
function analyzeRun(rows, meta = {}) {
  const ev = rows.filter(r => r.timestamp).map(r => ({ ...r, t: Date.parse(r.timestamp) }))
    .filter(r => Number.isFinite(r.t)).sort((a, b) => a.t - b.t)
  if (!ev.length) return null

  // tool_use id -> when it was issued, and what it was
  const useAt = new Map(), useName = new Map(), bashCmd = new Map()
  for (const r of ev) {
    if (r.type !== 'assistant' || !Array.isArray(r.message?.content)) continue
    for (const c of r.message.content) {
      if (c.type !== 'tool_use') continue
      useAt.set(c.id, r.t); useName.set(c.id, c.name)
      if (c.name === 'Bash') bashCmd.set(c.id, String(c.input?.command ?? '').replace(/\s+/g, ' ').trim())
    }
  }

  const toolIv = [], childIv = [], byTool = new Map(), bashCalls = []
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

      // (4) a spawn's duration is the child's run, never the caller's work
      if (SPAWN_TOOLS.has(name)) childIv.push([a, b])
      else toolIv.push([a, b])
      if (name === 'Bash') bashCalls.push({ ms: dur, cmd: bashCmd.get(c.tool_use_id) ?? '' })

      const T = r.toolUseResult
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

  // (2) walk the lifetime and classify every gap that is not tool or child.
  // Reasoning is kept as INTERVALS, not just a total: a run is "alive" while it
  // thinks, so a total alone would let the report claim the machine was idle
  // during the 78% of a verifier's life that is pure reasoning.
  const span0 = ev[0].t, span1 = ev[ev.length - 1].t
  let reason = 0, stalled = 0, cursor = span0
  const deadGaps = [], reasonIv = []
  const classifyGap = (from, to) => {
    const gap = to - from
    if (gap <= 0) return
    const think = Math.min(gap, STALL_MS)
    reason += think
    reasonIv.push([from, from + think])
    stalled += Math.max(0, gap - STALL_MS)
    if (gap >= GAP_REPORT_MS) deadGaps.push({ from, to, ms: gap })
  }
  for (const [a, b] of busy.merged) {
    classifyGap(cursor, a)
    cursor = Math.max(cursor, b)
  }
  classifyGap(cursor, span1)

  // (3) dedupe usage by message id
  const usage = new Map()
  const models = new Map(), efforts = new Map()
  for (const r of ev) {
    if (r.type !== 'assistant' || !r.message?.usage) continue
    usage.set(r.message.id, r.message.usage)
    if (r.message.model) models.set(r.message.model, (models.get(r.message.model) ?? 0) + 1)
    const eff = r.effort ?? null
    if (eff) efforts.set(eff, (efforts.get(eff) ?? 0) + 1)
  }
  const tok = { input: 0, cacheWrite: 0, cacheRead: 0, output: 0 }
  for (const u of usage.values()) {
    tok.input += u.input_tokens ?? 0
    tok.cacheWrite += u.cache_creation_input_tokens ?? 0
    tok.cacheRead += u.cache_read_input_tokens ?? 0
    tok.output += u.output_tokens ?? 0
  }
  const top = (m) => [...m.entries()].sort((a, b) => b[1] - a[1])
  const dominant = (m) => (top(m)[0]?.[0]) ?? 'unknown'

  return {
    agentType: meta.agentType ?? null,
    description: meta.description ?? null,
    spawnDepth: meta.spawnDepth ?? 0,
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
    bashCalls, deadGaps,
  }
}

// ─────────────────────────────────────────────────────────── phases

/**
 * Keep only the records belonging to `branch`.
 *
 * One session routinely covers several branches — a real one covered six — and
 * without this every one of those branches reports the others' work as its own
 * (three unrelated branches once reported byte-identical totals). Records that
 * carry no `gitBranch` of their own inherit the last one seen, so bookkeeping
 * rows stay with the work they sit in.
 */
function rowsOnBranch(rows, branch) {
  const stamped = rows.filter(r => r.timestamp).sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp))
  const out = []
  let current = null
  for (const r of stamped) {
    if (typeof r.gitBranch === 'string') current = r.gitBranch
    if (current === branch) out.push(r)
  }
  return out
}

/** The branch a subagent ran on — agents inherit it, so one value dominates. */
function branchOfRun(rows) {
  const votes = new Map()
  for (const r of rows) if (typeof r.gitBranch === 'string') votes.set(r.gitBranch, (votes.get(r.gitBranch) ?? 0) + 1)
  return [...votes.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null
}

/** Pipeline command invocations, in time order, from a session's main thread. */
function extractPhaseMarks(rows) {
  const marks = []
  for (const r of rows) {
    if (r.type !== 'user' || typeof r.message?.content !== 'string' || !r.timestamp) continue
    const c = r.message.content
    const i = c.indexOf('<command-name>')
    if (i === -1) continue
    const j = c.indexOf('</command-name>', i)
    if (j === -1) continue
    const raw = c.slice(i + 14, j).trim().replace(/^\//, '').replace(/^bett3r-ai-workflow:/, '')
    const t = Date.parse(r.timestamp)
    if (!Number.isFinite(t)) continue
    if (raw === 'clear') { marks.push({ t, phase: null, raw }); continue }
    if (PIPELINE.includes(raw)) marks.push({ t, phase: raw, raw })
  }
  return marks
}

/**
 * Turn the marks into non-overlapping windows, each a distinct INVOCATION.
 *
 * Instances matter: a branch that ran `/build` twice has two passes over the
 * same slices, and merging them makes every slice look like it needed a retry
 * (a real branch read 0% first-pass-green purely from this). `build` and
 * `build #2` are therefore separate windows, never one bucket.
 */
function buildWindows(marks, runStart, runEnd) {
  const wins = []
  const seen = new Map()
  const open = (t, phase) => {
    let label = '(outside a command)'
    if (phase) {
      const n = (seen.get(phase) ?? 0) + 1
      seen.set(phase, n)
      label = n === 1 ? phase : `${phase} #${n}`
    }
    wins.push({ label, phase, start: t, end: runEnd })
  }
  if (!marks.length || marks[0].t > runStart) open(runStart, null)
  for (const m of marks) {
    if (wins.length) wins[wins.length - 1].end = m.t
    open(m.t, m.phase)
  }
  return wins.filter(w => w.end > w.start)
}

/** Total overlap between a set of merged intervals and a window. */
const clipTotal = (intervals, w) => intervals.reduce((t, [a, b]) => {
  const lo = Math.max(a, w.start), hi = Math.min(b, w.end)
  return t + Math.max(0, hi - lo)
}, 0)

/** The clipped intervals themselves, for unioning across runs. */
const clipIntervals = (intervals, w) => intervals
  .map(([a, b]) => [Math.max(a, w.start), Math.min(b, w.end)])
  .filter(([a, b]) => b > a)

// ─────────────────────────────────────────────────────────── the run

function collectRun(branch, sessionFiles) {
  const runs = [], marks = []
  const sessions = []
  const cwdVotes = new Map()

  for (const parentFile of sessionFiles) {
    const all = readJsonl(parentFile)
    const rows = rowsOnBranch(all, branch)
    if (!rows.length) continue
    const sid = basename(parentFile, '.jsonl')
    marks.push(...extractPhaseMarks(rows))
    for (const r of rows) if (r.cwd) cwdVotes.set(r.cwd, (cwdVotes.get(r.cwd) ?? 0) + 1)

    const main = analyzeRun(rows, { agentType: 'orchestrator' })
    if (main) { main.sessionId = sid; main.file = parentFile; runs.push(main) }
    sessions.push({ sessionId: sid, file: parentFile })

    const subDir = join(parentFile.replace(/\.jsonl$/, ''), 'subagents')
    if (!existsSync(subDir)) continue
    const envelope = [Math.min(...rows.map(r => Date.parse(r.timestamp))), Math.max(...rows.map(r => Date.parse(r.timestamp)))]
    for (const f of readdirSync(subDir)) {
      if (!f.endsWith('.jsonl')) continue
      const p = join(subDir, f)
      const sub = readJsonl(p)
      const subBranch = branchOfRun(sub)
      if (subBranch !== null && subBranch !== branch) continue
      if (subBranch === null) {
        // no branch stamped: keep it only if it ran inside this branch's window
        const t = sub.find(r => r.timestamp)?.timestamp
        const ts = t ? Date.parse(t) : null
        if (ts === null || ts < envelope[0] || ts > envelope[1]) continue
      }
      const mp = p.replace(/\.jsonl$/, '.meta.json')
      let meta = {}
      if (existsSync(mp)) { try { meta = JSON.parse(readFileSync(mp, 'utf8')) } catch { /* keep going */ } }
      const a = analyzeRun(sub, meta)
      if (a) { a.sessionId = sid; a.agentId = basename(f, '.jsonl'); runs.push(a) }
    }
  }

  marks.sort((a, b) => a.t - b.t)
  const workDir = [...cwdVotes.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null
  return { runs, marks, sessions, workDir }
}

// ─────────────────────────────────────────────────────────── retry ledger

/**
 * Executor attempts per slice — the lever, since a failed gate costs a whole
 * extra pass. Scoped to ONE build invocation: across two `/build` passes the
 * same slice legitimately has two executors and that is not a retry.
 */
function retryLedger(runs) {
  const slices = new Map()
  for (const r of runs) {
    const role = shortRole(r.agentType)
    if (role !== 'executor' && role !== 'verifier' && role !== 'test-runner') continue
    const d = r.description ?? ''
    const m = d.match(/slice\s*(\d+)/i) ?? d.match(/\bS(\d+)\b/)
    const key = m ? `slice ${m[1]}` : 'unattributed'
    const s = slices.get(key) ?? { slice: key, executor: 0, verifier: 0, test: 0, activeMs: 0, tokens: 0, added: 0, removed: 0, rework: false }
    if (role === 'executor') s.executor++
    if (role === 'verifier') s.verifier++
    if (role === 'test-runner') s.test++
    if (/rework|retry|correction/i.test(d)) s.rework = true
    s.activeMs += r.activeMs
    s.tokens += r.tokens.input + r.tokens.cacheWrite + r.tokens.cacheRead + r.tokens.output
    s.added += r.linesAdded; s.removed += r.linesRemoved
    slices.set(key, s)
  }
  return [...slices.values()].sort((a, b) => a.slice.localeCompare(b.slice, undefined, { numeric: true }))
}

/** first-pass-green over the slices we could attribute, or null if none. */
function firstPassGreen(ledger) {
  const a = ledger.filter(x => x.slice !== 'unattributed')
  if (!a.length) return null
  return a.filter(x => x.executor <= 1).length / a.length
}

const shortRole = (t) => (t ?? 'unknown').replace(/^bett3r-ai-workflow:/, '')

// ─────────────────────────────────────────────────────────── provenance

/**
 * `workDir` is the cwd the run actually happened in, read off the transcripts —
 * not `process.cwd()`. Backfilling another repo's branch from this one would
 * otherwise stamp every historical run with the wrong repo and SHA.
 */
function provenance(workDir = null, atMs = null) {
  const cwd = workDir ?? process.cwd()
  const out = {
    pluginVersion: null, pluginSha: null, pluginDirty: null, pluginShaSource: null,
    hostSha: null, hostRepo: null, workDir: cwd, capturedAt: new Date().toISOString(),
  }
  const mkt = join(homedir(), '.claude', 'plugins', 'marketplaces', 'bett3r-ai-workflow')
  const git = (cwd, args) => execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()

  // Backfilling a run from weeks ago must not stamp it with today's plugin —
  // that would collapse every historical run onto one version and silently
  // destroy the very comparison this field exists for. Resolve by date instead.
  if (atMs) {
    try {
      const sha = git(mkt, ['rev-list', '-1', `--before=${new Date(atMs).toISOString()}`, 'HEAD'])
      if (sha) {
        out.pluginSha = sha.slice(0, 7)
        out.pluginShaSource = 'resolved-by-date'
        try {
          const manifest = git(mkt, ['show', `${sha}:plugins/bett3r-ai-workflow/.claude-plugin/plugin.json`])
          out.pluginVersion = JSON.parse(manifest).version ?? null
        } catch { /* manifest may not exist that far back */ }
      }
    } catch { /* not a checkout — fall through to HEAD */ }
  }

  if (!out.pluginSha) {
    try {
      const manifest = join(mkt, 'plugins', 'bett3r-ai-workflow', '.claude-plugin', 'plugin.json')
      if (existsSync(manifest)) out.pluginVersion = JSON.parse(readFileSync(manifest, 'utf8')).version ?? null
    } catch { /* absent when run from a source checkout */ }
    try { out.pluginSha = git(mkt, ['rev-parse', '--short', 'HEAD']); out.pluginShaSource = 'head' } catch { /* not installed as a checkout */ }
    try { out.pluginDirty = git(mkt, ['status', '--porcelain']).length > 0 } catch { /* ignore */ }
  }
  if (existsSync(cwd)) {
    try { out.hostSha = git(cwd, ['rev-parse', '--short', 'HEAD']) } catch { /* worktree may be gone */ }
    try { out.hostRepo = basename(git(cwd, ['rev-parse', '--show-toplevel'])) } catch { /* ignore */ }
  }
  // a deleted `/start-multi` worktree still names its repo in the path
  if (!out.hostRepo) out.hostRepo = basename(cwd)
  return out
}

const currentBranch = () => {
  try { return execFileSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() } catch { return null }
}

// ─────────────────────────────────────────────────────────── aggregate

function summarize(branch, { runs, marks, sessions, workDir }) {
  const agents = runs.filter(r => r.agentType !== 'orchestrator')
  const orch = runs.filter(r => r.agentType === 'orchestrator')
  if (!runs.length) return null

  const runStart = marks.length ? Math.min(marks[0].t, ...runs.map(r => r.start)) : Math.min(...runs.map(r => r.start))
  const runEnd = Math.max(...runs.map(r => r.end))
  // alive = anything was working, thinking included — not merely running a tool
  const alive = unionMs(runs.flatMap(r => r.activeIntervals)).total

  const roll = (list) => {
    const t = { runs: list.length, elapsed: 0, active: 0, tool: 0, reason: 0, child: 0, stalled: 0, calls: 0, apiCalls: 0, added: 0, removed: 0, tokens: { input: 0, cacheWrite: 0, cacheRead: 0, output: 0 } }
    for (const r of list) {
      t.elapsed += r.elapsedMs; t.active += r.activeMs; t.tool += r.toolMs; t.reason += r.reasonMs
      t.child += r.childMs; t.stalled += r.stalledMs; t.calls += r.toolCalls; t.apiCalls += r.apiCalls
      t.added += r.linesAdded; t.removed += r.linesRemoved
      for (const k of Object.keys(t.tokens)) t.tokens[k] += r.tokens[k]
    }
    return t
  }

  const byRole = new Map()
  for (const r of runs) {
    const k = shortRole(r.agentType)
    if (!byRole.has(k)) byRole.set(k, [])
    byRole.get(k).push(r)
  }
  const roles = [...byRole.entries()].map(([role, list]) => ({
    role, ...roll(list),
    models: [...new Set(list.map(r => r.model))].filter(m => m !== 'unknown'),
    efforts: [...new Set(list.map(r => r.effort))].filter(e => e !== 'unknown'),
  })).sort((a, b) => b.active - a.active)

  // Phases are time windows, so a run is clipped into every window it spans —
  // an orchestrator lives across the whole pipeline and belongs to all of them.
  // Tokens and lines have no timestamps of their own, so they are prorated by
  // each run's share of active time in the window (stated, not hidden).
  const windows = buildWindows(marks, runStart, runEnd)
  const phases = windows.map(w => {
    const parts = []
    for (const r of runs) {
      const active = clipTotal(r.activeIntervals, w)
      if (active <= 0) continue
      const share = r.activeMs > 0 ? active / r.activeMs : 0
      parts.push({ r, active, share, clipped: clipIntervals(r.activeIntervals, w) })
    }
    const tokens = { input: 0, cacheWrite: 0, cacheRead: 0, output: 0 }
    let added = 0, removed = 0, calls = 0
    for (const p of parts) {
      for (const k of Object.keys(tokens)) tokens[k] += Math.round(p.r.tokens[k] * p.share)
      added += Math.round(p.r.linesAdded * p.share)
      removed += Math.round(p.r.linesRemoved * p.share)
      calls += Math.round(p.r.toolCalls * p.share)
    }
    const agentParts = parts.filter(p => shortRole(p.r.agentType) !== 'orchestrator')
    return {
      phase: w.label, command: w.phase, start: w.start, end: w.end,
      windowMs: w.end - w.start,
      wallMs: unionMs(parts.flatMap(p => p.clipped)).total,
      active: parts.reduce((t, p) => t + p.active, 0),
      tool: parts.reduce((t, p) => t + clipTotal(p.r.toolIntervals, w), 0),
      reason: parts.reduce((t, p) => t + clipTotal(p.r.reasonIntervals, w), 0),
      runs: agentParts.length, calls, tokens, added, removed,
      ledger: w.phase === 'build' ? retryLedger(agentParts.map(p => p.r)) : [],
    }
  }).map(p => ({ ...p, firstPassGreen: p.ledger.length ? firstPassGreen(p.ledger) : null }))

  const total = roll(runs)
  const tk = total.tokens
  const tokTotal = tk.input + tk.cacheWrite + tk.cacheRead + tk.output
  // opus-class relative weights, expressed in input-token equivalents
  const weighted = tk.input + tk.cacheWrite * 1.25 + tk.cacheRead * 0.1 + tk.output * 5

  const cmdClasses = new Map()
  const cmdByRole = new Map()
  for (const r of runs) {
    const role = shortRole(r.agentType)
    for (const b of r.bashCalls) {
      const cls = classifyCommand(b.cmd)
      const c = cmdClasses.get(cls) ?? { cls, n: 0, ms: 0, slowest: 0 }
      c.n++; c.ms += b.ms; c.slowest = Math.max(c.slowest, b.ms)
      cmdClasses.set(cls, c)

      const key = `${role} ${cls}`
      const rc = cmdByRole.get(key) ?? { role, cls, n: 0, ms: 0 }
      rc.n++; rc.ms += b.ms
      cmdByRole.set(key, rc)
    }
  }
  const commands = [...cmdClasses.values()].sort((a, b) => b.ms - a.ms)
  const commandsByRole = [...cmdByRole.values()].sort((a, b) => b.ms - a.ms)

  // One agent = one (role, model, effort) cell. Kept at this grain because the
  // question "is the cheaper model good enough for the verifier?" cannot be
  // answered from a role total that averages two models together.
  const cellMap = new Map()
  for (const r of runs) {
    const key = `${shortRole(r.agentType)} ${r.model} ${r.effort}`
    const c = cellMap.get(key) ?? {
      role: shortRole(r.agentType), model: r.model, effort: r.effort,
      runs: 0, active: 0, tool: 0, reason: 0, stalled: 0, calls: 0, apiCalls: 0,
      added: 0, removed: 0, tokens: 0, output: 0, weighted: 0,
    }
    c.runs++; c.active += r.activeMs; c.tool += r.toolMs; c.reason += r.reasonMs
    c.stalled += r.stalledMs; c.calls += r.toolCalls; c.apiCalls += r.apiCalls
    c.added += r.linesAdded; c.removed += r.linesRemoved
    const t = r.tokens
    c.tokens += t.input + t.cacheWrite + t.cacheRead + t.output
    c.output += t.output
    c.weighted += t.input + t.cacheWrite * 1.25 + t.cacheRead * 0.1 + t.output * 5
    cellMap.set(key, c)
  }
  const roleCells = [...cellMap.values()].sort((a, b) => b.active - a.active)

  const deadGaps = orch.flatMap(r => r.deadGaps).sort((a, b) => b.ms - a.ms).slice(0, 10)

  // label each run with the window it spent most of its time in
  const homeWindow = (r) => {
    let best = null, bestMs = 0
    for (const w of windows) {
      const c = clipTotal(r.activeIntervals, w)
      if (c > bestMs) { bestMs = c; best = w.label }
    }
    return best
  }

  const builds = phases.filter(p => p.command === 'build' && p.ledger.length)
  const attributed = builds.flatMap(b => b.ledger.filter(x => x.slice !== 'unattributed'))
  const overallFpg = attributed.length
    ? attributed.filter(x => x.executor <= 1).length / attributed.length
    : null

  return {
    branch,
    runStart, runEnd,
    runElapsedMs: runEnd - runStart,
    agentActiveMs: agents.reduce((t, r) => t + r.activeMs, 0),
    orchActiveMs: orch.reduce((t, r) => t + r.activeMs, 0),
    totalActiveMs: total.active,
    agentStalledMs: agents.reduce((t, r) => t + r.stalledMs, 0),
    totalStalledMs: total.stalled,
    aliveMs: alive,
    deadMs: Math.max(0, (runEnd - runStart) - alive),
    dutyCycle: (runEnd - runStart) > 0 ? alive / (runEnd - runStart) : 0,
    parallelism: alive > 0 ? total.active / alive : 0,
    sessions: sessions.length,
    agentCount: agents.length,
    roles, phases, total,
    tokens: tk, tokenTotal: tokTotal, weightedTokens: Math.round(weighted),
    linesAdded: total.added, linesRemoved: total.removed,
    builds, firstPassGreen: overallFpg,
    commands, commandsByRole, roleCells, deadGaps,
    models: [...new Set(runs.map(r => r.model))].filter(m => m !== 'unknown'),
    efforts: [...new Set(runs.map(r => r.effort))].filter(e => e !== 'unknown'),
    topRuns: [...agents].sort((a, b) => b.activeMs - a.activeMs).slice(0, 12).map(r => ({
      role: shortRole(r.agentType), description: r.description, phase: homeWindow(r),
      activeMs: r.activeMs, toolMs: r.toolMs, reasonMs: r.reasonMs, stalledMs: r.stalledMs,
      toolCalls: r.toolCalls, model: r.model, effort: r.effort,
      tokens: r.tokens.input + r.tokens.cacheWrite + r.tokens.cacheRead + r.tokens.output,
      linesAdded: r.linesAdded, linesRemoved: r.linesRemoved,
    })),
    provenance: provenance(workDir, runEnd),
  }
}

/** Bucket a shell command by what it costs, not by its exact text. */
function classifyCommand(cmd) {
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

// ─────────────────────────────────────────────────────────── rendering

function table(headers, rows) {
  if (!rows.length) return '  (none)'
  const all = [headers, ...rows].map(r => r.map(x => String(x ?? '')))
  const w = headers.map((_, i) => Math.max(...all.map(r => r[i].length)))
  const line = (l, m, rgt) => l + w.map(n => '─'.repeat(n + 2)).join(m) + rgt
  const fmt = (r) => '│' + r.map((c, i) => ` ${c.padEnd(w[i])} `).join('│') + '│'
  return [line('┌', '┬', '┐'), fmt(all[0]), line('├', '┼', '┤'), ...all.slice(1).map(fmt), line('└', '┴', '┘')]
    .map(l => '  ' + l).join('\n')
}

function render(s) {
  const L = []
  const p = s.provenance
  L.push('')
  L.push(`  ${s.branch}`)
  L.push(`  ${'─'.repeat(Math.max(20, s.branch.length))}`)
  L.push(`  ${new Date(s.runStart).toISOString().slice(0, 16).replace('T', ' ')} → ${new Date(s.runEnd).toISOString().slice(0, 16).replace('T', ' ')}   ${s.sessions} session(s), ${s.agentCount} agents`)
  L.push(`  plugin ${p.pluginVersion ?? '?'} @ ${p.pluginSha ?? '?'}${p.pluginDirty ? ' (dirty)' : ''}   models: ${s.models.join(', ') || '?'}   effort: ${s.efforts.join(', ') || 'unknown'}`)
  L.push('')

  L.push('  WHERE THE CLOCK WENT')
  L.push(table(['measure', 'value', 'meaning'], [
    ['run elapsed', fmtDur(s.runElapsedMs), 'first command → last activity'],
    ['≥1 agent alive', `${fmtDur(s.aliveMs)}  (${pct(s.aliveMs, s.runElapsedMs)})`, 'the machine was doing something'],
    ['dead time', `${fmtDur(s.deadMs)}  (${pct(s.deadMs, s.runElapsedMs)})`, 'nothing running at all'],
    ['active (sum, all runs)', fmtDur(s.totalActiveMs), `parallel runs add up (${s.parallelism.toFixed(2)}×)`],
    ['  └ subagents', fmtDur(s.agentActiveMs), `${s.agentCount} agents`],
    ['  └ orchestrator', fmtDur(s.orchActiveMs), 'the main thread, incl. waiting on you'],
    ['stalled (sum)', fmtDur(s.totalStalledMs), 'backoff / parked session'],
  ]))
  L.push('')

  L.push('  BY PHASE   (each command invocation is its own window; tokens prorated by time)')
  L.push(table(['phase', 'window', 'alive', 'idle', 'active', 'tool', 'reason', 'subagents', 'tokens', '+/- lines'],
    s.phases.map(f => [f.phase, fmtDur(f.windowMs), fmtDur(f.wallMs),
      fmtDur(Math.max(0, f.windowMs - f.wallMs)), fmtDur(f.active),
      pct(f.tool, f.active), pct(f.reason, f.active), f.runs,
      fmtTok(f.tokens.input + f.tokens.cacheWrite + f.tokens.cacheRead + f.tokens.output),
      `+${f.added}/-${f.removed}`])))
  L.push('')

  L.push('  BY ROLE')
  L.push(table(['role', 'runs', 'elapsed', 'active', 'busy%', 'tool', 'reason', 'stalled', 'calls', 'tokens', '+/- lines', 'model', 'effort'],
    s.roles.map(r => [r.role, r.runs, fmtDur(r.elapsed), fmtDur(r.active), pct(r.active, r.elapsed),
      `${fmtMin(r.tool)} ${pct(r.tool, r.active)}`, `${fmtMin(r.reason)} ${pct(r.reason, r.active)}`,
      fmtDur(r.stalled), r.calls,
      fmtTok(r.tokens.input + r.tokens.cacheWrite + r.tokens.cacheRead + r.tokens.output),
      `+${r.added}/-${r.removed}`, r.models.join(',') || '?', r.efforts.join(',') || '?'])))
  L.push('')

  for (const b of s.builds) {
    L.push(`  RETRY LEDGER — ${b.phase}   (executor passes per slice; a failed gate costs a whole extra pass)`)
    L.push(table(['slice', 'executor', 'verifier', 'test', 'active', 'tokens', '+/- lines', 'rework?'],
      b.ledger.map(x => [x.slice, x.executor, x.verifier, x.test, fmtDur(x.activeMs), fmtTok(x.tokens),
        `+${x.added}/-${x.removed}`, x.rework ? 'yes' : ''])))
    const att = b.ledger.filter(x => x.slice !== 'unattributed')
    if (att.length) {
      const clean = att.filter(x => x.executor <= 1).length
      L.push(`  first-pass green: ${clean}/${att.length} slices (${pct(clean, att.length)})`)
    }
    L.push('')
  }

  L.push('  TOKENS')
  const tk = s.tokens
  L.push(table(['kind', 'tokens', 'share'], [
    ['fresh input', fmtTok(tk.input), pct(tk.input, s.tokenTotal)],
    ['cache write', fmtTok(tk.cacheWrite), pct(tk.cacheWrite, s.tokenTotal)],
    ['cache read', fmtTok(tk.cacheRead), pct(tk.cacheRead, s.tokenTotal)],
    ['output', fmtTok(tk.output), pct(tk.output, s.tokenTotal)],
    ['weighted', fmtTok(s.weightedTokens), 'input-equivalents (1 / 1.25 / 0.1 / 5)'],
  ]))
  if (s.linesAdded + s.linesRemoved > 0) {
    L.push(`  efficiency: ${fmtTok(Math.round(s.weightedTokens / Math.max(1, s.linesAdded)))} weighted tokens per line added   ·   +${s.linesAdded}/-${s.linesRemoved} lines`)
  }
  L.push('')

  if (s.commands.length) {
    L.push('  WHERE COMMAND TIME WENT   (summed per call — concurrent calls overlap, so this exceeds wall time)')
    L.push(table(['class', 'calls', 'total', 'slowest single'],
      s.commands.map(c => [c.cls, c.n, fmtDur(c.ms), fmtDur(c.slowest)])))
    L.push('')
  }

  if (s.topRuns.length) {
    L.push('  BIGGEST AGENT RUNS')
    L.push(table(['role', 'phase', 'what', 'active', 'tool', 'reason', 'calls', 'tokens', '+/-'],
      s.topRuns.map(r => [r.role, r.phase ?? '—', (r.description ?? '').slice(0, 34), fmtDur(r.activeMs),
        pct(r.toolMs, r.activeMs), pct(r.reasonMs, r.activeMs), r.toolCalls, fmtTok(r.tokens),
        `+${r.linesAdded}/-${r.linesRemoved}`])))
    L.push('')
  }

  if (s.deadGaps.length) {
    L.push(`  DEAD GAPS ≥ ${GAP_REPORT_MS / 60000}m   (one long pause vs many short ones is a different problem)`)
    L.push(table(['when', 'length'], s.deadGaps.map(g =>
      [new Date(g.from).toISOString().slice(0, 16).replace('T', ' '), fmtDur(g.ms)])))
    L.push('')
  }

  return L.join('\n')
}

// ─────────────────────────────────────────────────────────── emit / aggregate

function emit(summary) {
  mkdirSync(join(STORE, 'runs'), { recursive: true })
  const repo = summary.provenance.hostRepo ?? 'unknown'
  const safe = `${repo}__${summary.branch}`.replace(/[^A-Za-z0-9._-]/g, '_')
  const file = join(STORE, 'runs', `${safe}.json`)
  writeFileSync(file, JSON.stringify(summary, null, 2))

  const row = {
    branch: summary.branch, repo,
    runStart: new Date(summary.runStart).toISOString(),
    runEnd: new Date(summary.runEnd).toISOString(),
    runElapsedMin: +ms2min(summary.runElapsedMs).toFixed(1),
    aliveMin: +ms2min(summary.aliveMs).toFixed(1),
    deadMin: +ms2min(summary.deadMs).toFixed(1),
    dutyCycle: +summary.dutyCycle.toFixed(3),
    agentActiveMin: +ms2min(summary.agentActiveMs).toFixed(1),
    agents: summary.agentCount, sessions: summary.sessions,
    tokenTotal: summary.tokenTotal, weightedTokens: summary.weightedTokens,
    outputTokens: summary.tokens.output,
    linesAdded: summary.linesAdded, linesRemoved: summary.linesRemoved,
    models: summary.models, efforts: summary.efforts,
    pluginVersion: summary.provenance.pluginVersion, pluginSha: summary.provenance.pluginSha,
    hostSha: summary.provenance.hostSha,
    phases: summary.phases.map(p => ({
      phase: p.phase, windowMin: +ms2min(p.windowMs).toFixed(1),
      aliveMin: +ms2min(p.wallMs).toFixed(1), activeMin: +ms2min(p.active).toFixed(1),
    })),
    firstPassGreen: summary.firstPassGreen === null ? null : +summary.firstPassGreen.toFixed(3),
    capturedAt: summary.provenance.capturedAt,
  }
  // one row per (repo, branch): drop any earlier row for the same key so re-runs update
  let rows = []
  if (existsSync(INDEX)) {
    for (const line of readFileSync(INDEX, 'utf8').split('\n')) {
      if (!line.trim()) continue
      try { const r = JSON.parse(line); if (!(r.branch === row.branch && r.repo === row.repo)) rows.push(r) } catch { /* skip */ }
    }
  }
  rows.push(row)
  writeFileSync(INDEX, rows.map(r => JSON.stringify(r)).join('\n') + '\n')
  return { file, index: INDEX }
}

/** Command classes that are the repo answering back, rather than the model working. */
const CHECK_CLASSES = new Set(['build', 'test', 'typecheck', 'lint', 'generate', 'install'])

/**
 * Fleet-wide agent performance: how the agents themselves spend time, across
 * every recorded run. Reads the run documents (not the index) because the index
 * is deliberately one flat row per run and cannot carry a role breakdown.
 */
function agentsReport(sinceMs) {
  const dir = join(STORE, 'runs')
  if (!existsSync(dir)) { console.log('  no runs recorded yet — run with --emit first, or backfill.'); return }
  const docs = []
  for (const f of readdirSync(dir)) {
    if (!f.endsWith('.json')) continue
    try {
      const d = JSON.parse(readFileSync(join(dir, f), 'utf8'))
      if (sinceMs && d.runEnd < sinceMs) continue
      docs.push(d)
    } catch { /* skip an unreadable document rather than abort the report */ }
  }
  if (!docs.length) { console.log('  no runs in range.'); return }

  const cells = new Map()
  for (const d of docs) for (const c of (d.roleCells ?? [])) {
    const key = `${c.role}|${c.model}|${c.effort}`
    const a = cells.get(key) ?? { ...c, runs: 0, active: 0, tool: 0, reason: 0, stalled: 0, calls: 0, apiCalls: 0, added: 0, removed: 0, tokens: 0, output: 0, weighted: 0 }
    for (const k of ['runs', 'active', 'tool', 'reason', 'stalled', 'calls', 'apiCalls', 'added', 'removed', 'tokens', 'output', 'weighted']) a[k] += c[k] ?? 0
    cells.set(key, a)
  }
  const all = [...cells.values()]
  if (!all.length) { console.log('  runs found, but none carry a role breakdown — re-emit them to populate it.'); return }

  const fold = (list) => list.reduce((t, c) => {
    for (const k of ['runs', 'active', 'tool', 'reason', 'stalled', 'calls', 'apiCalls', 'added', 'removed', 'tokens', 'output', 'weighted']) t[k] = (t[k] ?? 0) + (c[k] ?? 0)
    return t
  }, {})
  const groupBy = (list, keyFn) => {
    const m = new Map()
    for (const c of list) {
      const k = keyFn(c)
      if (!m.has(k)) m.set(k, [])
      m.get(k).push(c)
    }
    return m
  }
  const tokPerLine = (g) => g.added > 0 ? fmtTok(Math.round(g.weighted / g.added)) : '—'

  console.log('')
  console.log(`  AGENT PERFORMANCE — ${docs.length} run(s)${sinceMs ? ` since ${new Date(sinceMs).toISOString().slice(0, 10)}` : ''}`)
  console.log('')

  const total = fold(all)
  console.log('  BY ROLE')
  const byRole = [...groupBy(all, c => c.role).entries()]
    .map(([role, list]) => ({ role, ...fold(list), models: [...new Set(list.map(c => c.model))], efforts: [...new Set(list.map(c => c.effort))] }))
    .sort((a, b) => b.active - a.active)
  console.log(table(['role', 'agents', 'active', 'share', 'tool', 'reason', 'stalled', 'calls', 'api', 'weighted tok', '+/- lines', 'tok/line'],
    byRole.map(g => [g.role, g.runs, fmtDur(g.active), pct(g.active, total.active),
      `${fmtDur(g.tool)} ${pct(g.tool, g.active)}`, `${fmtDur(g.reason)} ${pct(g.reason, g.active)}`,
      fmtDur(g.stalled), g.calls, g.apiCalls, fmtTok(Math.round(g.weighted)),
      `+${g.added}/-${g.removed}`, tokPerLine(g)])))
  console.log(`  total: ${fmtDur(total.active)} active — ${fmtDur(total.tool)} tool (${pct(total.tool, total.active)}) · ${fmtDur(total.reason)} reasoning (${pct(total.reason, total.active)})`)
  console.log('')

  console.log('  BY MODEL')
  const byModel = [...groupBy(all, c => c.model).entries()].map(([model, list]) => ({ model, ...fold(list) })).sort((a, b) => b.active - a.active)
  console.log(table(['model', 'agents', 'active', 'share', 'tool', 'reason', 'calls', 'weighted tok', '+/- lines', 'tok/line'],
    byModel.map(g => [g.model, g.runs, fmtDur(g.active), pct(g.active, total.active),
      pct(g.tool, g.active), pct(g.reason, g.active), g.calls, fmtTok(Math.round(g.weighted)),
      `+${g.added}/-${g.removed}`, tokPerLine(g)])))
  console.log('')

  console.log('  BY EFFORT')
  const byEffort = [...groupBy(all, c => c.effort).entries()].map(([effort, list]) => ({ effort, ...fold(list) })).sort((a, b) => b.active - a.active)
  console.log(table(['effort', 'agents', 'active', 'share', 'tool', 'reason', 'calls', 'weighted tok', '+/- lines', 'tok/line'],
    byEffort.map(g => [g.effort, g.runs, fmtDur(g.active), pct(g.active, total.active),
      pct(g.tool, g.active), pct(g.reason, g.active), g.calls, fmtTok(Math.round(g.weighted)),
      `+${g.added}/-${g.removed}`, tokPerLine(g)])))
  console.log('')

  console.log('  ROLE × MODEL × EFFORT   (the cell that answers "is the cheaper model good enough here?")')
  console.log(table(['role', 'model', 'effort', 'agents', 'active', 'tool', 'reason', 'calls', 'weighted tok', '+/- lines'],
    all.sort((a, b) => b.active - a.active).slice(0, 20).map(c => [c.role, c.model, c.effort, c.runs,
      fmtDur(c.active), pct(c.tool, c.active), pct(c.reason, c.active), c.calls,
      fmtTok(Math.round(c.weighted)), `+${c.added}/-${c.removed}`])))
  console.log('')

  // repo checks — the part of tool time that is the repo answering, not the model
  const cmdAgg = new Map()
  for (const d of docs) for (const c of (d.commands ?? [])) {
    const a = cmdAgg.get(c.cls) ?? { cls: c.cls, n: 0, ms: 0, slowest: 0 }
    a.n += c.n; a.ms += c.ms; a.slowest = Math.max(a.slowest, c.slowest ?? 0)
    cmdAgg.set(c.cls, a)
  }
  const cmds = [...cmdAgg.values()].sort((a, b) => b.ms - a.ms)
  const checkMs = cmds.filter(c => CHECK_CLASSES.has(c.cls)).reduce((t, c) => t + c.ms, 0)
  const cmdTotal = cmds.reduce((t, c) => t + c.ms, 0)

  console.log('  REPO CHECKS   (summed per call — concurrent calls overlap, so this exceeds wall time)')
  console.log(table(['class', 'check?', 'calls', 'total', 'share of shell', 'slowest single', 'avg'],
    cmds.map(c => [c.cls, CHECK_CLASSES.has(c.cls) ? 'yes' : '', c.n, fmtDur(c.ms),
      pct(c.ms, cmdTotal), fmtDur(c.slowest), fmtDur(c.ms / Math.max(1, c.n))])))
  console.log(`  repo checks: ${fmtDur(checkMs)} of ${fmtDur(cmdTotal)} shell time (${pct(checkMs, cmdTotal)}) — ${pct(checkMs, total.active)} of all agent active time`)
  // A class whose total is one blocked call is not a cost signal, it is an
  // incident. Reported explicitly: a real 7.02h `git` call once made `git` look
  // like 16% of all shell time, when the other 149 calls totalled 36 seconds.
  for (const c of cmds) {
    if (c.n > 1 && c.slowest > 0.5 * c.ms && c.slowest > 10 * 60_000) {
      console.log(`  ⚠ "${c.cls}" is dominated by ONE call of ${fmtDur(c.slowest)} (${pct(c.slowest, c.ms)} of the class; other ${c.n - 1} calls total ${fmtDur(c.ms - c.slowest)}).`)
      console.log('    A single call that long is a block — an interactive prompt, a pager, a waiting permission — not throughput to optimise.')
    }
  }
  console.log('')

  const roleCmd = new Map()
  for (const d of docs) for (const c of (d.commandsByRole ?? [])) {
    if (!CHECK_CLASSES.has(c.cls)) continue
    const a = roleCmd.get(c.role) ?? { role: c.role, n: 0, ms: 0 }
    a.n += c.n; a.ms += c.ms
    roleCmd.set(c.role, a)
  }
  if (roleCmd.size) {
    console.log('  WHO PAYS FOR THE CHECKS')
    const byRoleMap = new Map(byRole.map(g => [g.role, g]))
    console.log(table(['role', 'check calls', 'check time', 'of its tool time', 'of its active time'],
      [...roleCmd.values()].sort((a, b) => b.ms - a.ms).map(c => {
        const g = byRoleMap.get(c.role)
        return [c.role, c.n, fmtDur(c.ms), g ? pct(c.ms, g.tool) : '—', g ? pct(c.ms, g.active) : '—']
      })))
    console.log('')
  }
}

function aggregate(sinceMs) {
  if (!existsSync(INDEX)) { console.log('  no runs recorded yet — run with --emit first, or backfill.'); return }
  let rows = []
  for (const line of readFileSync(INDEX, 'utf8').split('\n')) {
    if (!line.trim()) continue
    try { rows.push(JSON.parse(line)) } catch { /* skip */ }
  }
  if (sinceMs) rows = rows.filter(r => Date.parse(r.runEnd) >= sinceMs)
  rows.sort((a, b) => Date.parse(a.runEnd) - Date.parse(b.runEnd))
  if (!rows.length) { console.log('  no runs in range.'); return }

  console.log('')
  console.log(`  ${rows.length} run(s)`)
  console.log(table(['branch', 'repo', 'ended', 'elapsed', 'alive', 'duty', 'agents', 'weighted tok', '+/- lines', 'plugin', 'effort'],
    rows.map(r => [r.branch.slice(0, 28), r.repo, r.runEnd.slice(0, 10), `${r.runElapsedMin}m`, `${r.aliveMin}m`,
      `${Math.round(r.dutyCycle * 100)}%`, r.agents, fmtTok(r.weightedTokens),
      `+${r.linesAdded}/-${r.linesRemoved}`, `${r.pluginVersion ?? '?'}@${r.pluginSha ?? '?'}`,
      (r.efforts ?? []).join(',') || '?'])))

  const byVer = new Map()
  for (const r of rows) {
    const k = `${r.pluginVersion ?? '?'}@${r.pluginSha ?? '?'}`
    const g = byVer.get(k) ?? { k, n: 0, alive: 0, elapsed: 0, weighted: 0, added: 0, fpg: [], agents: 0 }
    g.n++; g.alive += r.aliveMin; g.elapsed += r.runElapsedMin; g.weighted += r.weightedTokens
    g.added += r.linesAdded; g.agents += r.agents
    if (r.firstPassGreen !== null && r.firstPassGreen !== undefined) g.fpg.push(r.firstPassGreen)
    byVer.set(k, g)
  }
  console.log('')
  console.log('  BY PLUGIN VERSION   (the comparison the whole exercise is for)')
  console.log(table(['plugin', 'runs', 'avg alive', 'avg duty', 'avg weighted tok', 'tok/line', 'first-pass green'],
    [...byVer.values()].map(g => [g.k, g.n, `${(g.alive / g.n).toFixed(1)}m`,
      `${Math.round(100 * g.alive / Math.max(1, g.elapsed))}%`, fmtTok(Math.round(g.weighted / g.n)),
      g.added > 0 ? fmtTok(Math.round(g.weighted / g.added)) : '—',
      g.fpg.length ? `${Math.round(100 * g.fpg.reduce((a, b) => a + b, 0) / g.fpg.length)}%` : '—'])))
  console.log('')
}

// ─────────────────────────────────────────────────────────── cli

function parseArgs(argv) {
  const o = { branch: null, emit: false, json: false, list: false, aggregate: false, agents: false, since: null, quiet: false }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--emit') o.emit = true
    else if (a === '--json') o.json = true
    else if (a === '--list') o.list = true
    else if (a === '--aggregate') o.aggregate = true
    else if (a === '--agents') o.agents = true
    else if (a === '--quiet') o.quiet = true
    else if (a === '--since') o.since = argv[++i]
    else if (a === '--branch') o.branch = argv[++i]
    else if (a === '--help' || a === '-h') o.help = true
    else if (!a.startsWith('-') && !o.branch) o.branch = a
  }
  return o
}

const sinceToMs = (s) => {
  if (!s) return null
  const m = String(s).match(/^(\d+)([dwm])$/)
  if (m) {
    const n = +m[1], unit = { d: 864e5, w: 6048e5, m: 2592e6 }[m[2]]
    return Date.now() - n * unit
  }
  const t = Date.parse(s)
  return Number.isFinite(t) ? t : null
}

const HELP = `
run-metrics — where a unit of work's time and tokens actually went

  run-metrics [branch] [options]

  branch            branch to report on (default: current git branch)
  --list            list branches seen in the transcripts
  --aggregate       trend across all recorded runs (reads the index)
  --agents          fleet-wide AGENT performance: role x model x effort, and repo checks
  --emit            write the run to ~/.claude/bett3r-metrics/ and update the index
  --json            print the summary as JSON instead of tables
  --since <5d|2w|1m|ISO>   limit transcript scan / aggregation window
  --quiet           suppress the scan progress line
`

function main() {
  const o = parseArgs(process.argv.slice(2))
  if (o.help) { console.log(HELP); return }

  if (o.agents) { agentsReport(sinceToMs(o.since)); return }
  if (o.aggregate) { aggregate(sinceToMs(o.since)); return }

  if (o.list) {
    const rows = listBranches({ since: sinceToMs(o.since) })
    console.log('')
    console.log(table(['branch', 'last touched'], rows.slice(0, 40).map(([b, t]) =>
      [b, new Date(t).toISOString().slice(0, 16).replace('T', ' ')])))
    console.log('')
    return
  }

  const branch = o.branch ?? currentBranch()
  if (!branch) { console.error('No branch given and not inside a git repo. Pass one, or use --list.'); process.exit(2) }

  const files = findSessions(branch, { since: sinceToMs(o.since), quiet: o.quiet || o.json })
  if (!files.length) {
    console.error(`No transcripts found for branch "${branch}". Try --list to see what is on disk.`)
    process.exit(1)
  }

  const collected = collectRun(branch, files)
  const summary = summarize(branch, collected)
  if (!summary) { console.error('Transcripts found but nothing timestamped in them.'); process.exit(1) }

  if (o.json) console.log(JSON.stringify(summary, null, 2))
  else console.log(render(summary))

  if (o.emit) {
    const { file } = emit(summary)
    if (!o.json) console.log(`  recorded → ${file}\n`)
  }
}

main()
