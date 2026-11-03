// Outbound workout events (local addition). Watches the store for a session starting, an
// exercise getting all its sets ticked, and a session being saved, and tells our own API
// (POST /api/events), which forwards to the configured webhook. Fire-and-forget: never awaited
// on a UI path, every failure swallowed; each event is sent at most once per device
// (localStorage), so a reload does not resend what already went out.
import { api } from './api.js'
import { EXIDX } from './exercises.js'
import { exerciseNameFor } from './i18n-core.js'

const KEY = 'og-workout-events-sent'
const r1 = n => Math.round(n * 10) / 10
let sent = null
function sentSet() {
  if (sent) return sent
  try { sent = new Set(JSON.parse(localStorage.getItem(KEY) || '[]')) } catch { sent = new Set() }
  return sent
}
function once(key) {
  const s = sentSet()
  if (s.has(key)) return false
  s.add(key)
  try { localStorage.setItem(KEY, JSON.stringify([...s].slice(-300))) } catch { /* private mode */ }
  return true
}
function send(type, data) {
  try {
    const p = api('/api/events', { method: 'POST', body: JSON.stringify({ type, data }), keepalive: true, timeout: 10000 })
    if (p && typeof p.catch === 'function') p.catch(() => {})
  } catch { /* never let an event break the app */ }
}

const kg = (w, S) => (w == null ? null : S.unit === 'lb' ? r1(w * 0.45359237) : w)
export function exercisePayload(e, i, n, S) {
  const ex = EXIDX[e.id] || (S.customEx || []).find(c => c.id === e.id)
  const sets = (e.sets || []).map((s, k) => ({
    n: k + 1, done: !!s.done,
    reps: s.r ?? null,
    weight_kg: kg(s.w, S),
    duration_sec: s.sec != null ? s.sec : s.min != null ? Math.round(s.min * 60) : null,
    distance_km: s.km ?? null,
    type: s.type || s.phase || null,
    done_at: s.at || null,
  }))
  return {
    index: i + 1, total: n,
    exercise_id: e.id,
    name: ex ? (exerciseNameFor(ex) || ex.n) : String(e.id),
    name_en: ex?.n || null,
    rest_sec_planned: e.target?.restSec ?? S.restSec ?? null,
    note: e.note || null,
    sets,
  }
}
function totals(exs) {
  let sets = 0, reps = 0, vol = 0, cardioSec = 0
  for (const e of exs) for (const s of e.sets) {
    if (!s.done) continue
    sets++
    if (s.reps) reps += s.reps
    if (s.reps && s.weight_kg) vol += s.reps * s.weight_kg
    if (s.duration_sec && !s.reps) cardioSec += s.duration_sec
  }
  return { sets, reps, volume_kg: r1(vol), cardio_min: r1(cardioSec / 60) }
}
const live = A => A && !A.backfill && !A.editingWorkoutId

function step(prev, A, S) {
  if (live(A) && once('start:' + A.id)) {
    send('workout.started', {
      workout_id: A.id, name: A.name, routine_ids: A.routineIds || [],
      started_at: A.start,
      exercises: (A.entries || []).map((e, i, all) => {
        const p = exercisePayload(e, i, all.length, S)
        return { index: p.index, exercise_id: p.exercise_id, name: p.name, planned_sets: p.sets.length, rest_sec_planned: p.rest_sec_planned }
      }),
    })
  }
  if (live(A)) {
    const n = (A.entries || []).length
    A.entries.forEach((e, i) => {
      if (!e.sets?.length || !e.sets.every(s => s.done)) return
      if (!once('ex:' + A.id + ':' + i + ':' + e.id)) return
      const at = Math.max(0, ...e.sets.map(s => s.at || 0)) || Date.now()
      send('exercise.completed', { workout_id: A.id, workout_name: A.name, completed_at: at, exercise: exercisePayload(e, i, n, S) })
    })
  }
  if (live(prev) && !A) {
    const w = (S.workouts || []).find(x => x && x.start === prev.start)
    if (!w || !once('done:' + prev.id)) return
    const exs = (w.entries || []).map((e, i, all) => exercisePayload(e, i, all.length, S))
    const end = w.end || Date.now()
    send('workout.completed', {
      workout_id: prev.id, name: w.name, routine_ids: w.routineIds || (w.routineId ? [w.routineId] : []),
      started_at: w.start, ended_at: end, duration_min: r1((end - w.start) / 60000),
      body_weight_kg: kg(w.bw, S) ?? null,
      totals: totals(exs), exercises: exs,
      ...(w.health ? { health: w.health } : {}),
    })
  }
}

export function startWorkoutEvents(store) {
  let prev = store.getState().S?.active || null
  store.subscribe(st => {
    const A = st.S?.active || null
    if (A === prev) return
    try { step(prev, A, st.S) } catch { /* never let an event break the app */ }
    prev = A
  })
}
