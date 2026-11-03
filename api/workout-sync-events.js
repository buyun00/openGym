// Finished sessions that arrive through PUT /api/data, rather than POST /api/events.
//
// The web app watches its own store and fire-and-forgets workout.completed (frontend
// workout-events.js). Native iOS also posts live events; sync remains a fallback for older
// builds, imports and failed posts. A session is finished
// when it shows up in `workouts` with an `end` timestamp. In-progress work is not a signal —
// both clients keep `active` on the device, and PUT deletes it — so workout.started is not
// emitted from here. A start inferred at the moment the session is already over would be late,
// and a start inferred from a field the document does not store would fire again on every sync.
//
// One workout id is mailed once. The web client usually posts the event and then pushes the
// same id; both requests feed one durable completion hold before claiming delivery.
import fs from 'node:fs';
import path from 'node:path';
import { atomicWrite } from './durable.js';
import { libraryName } from './coach/core/library.js';
import { completedHealthFields } from './workout-health.js';

const MAX_KEYS = 2000;
const ID_MAX = 200;
const LB_IN_KG = 0.45359237;
const r1 = n => Math.round(n * 10) / 10;

export function eventsPath(dir, uid) {
  const safe = String(uid || '').replace(/[^a-zA-Z0-9_-]/g, '');
  return path.join(dir, `workout-events-${safe || 'unknown'}.json`);
}

// The key shared with POST /api/events. Null when the id cannot be claimed safely.
export function completedEventKey(id) {
  if (typeof id !== 'string' || !id || id.length > ID_MAX) return null;
  return 'workout.completed:' + id;
}

function readRecord(file) {
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    const object = v => v && typeof v === 'object' && !Array.isArray(v);
    if (!object(parsed) || !object(parsed.keys) || (parsed.pending != null && !object(parsed.pending))) {
      throw new Error('Invalid workout event record');
    }
    for (const [key, item] of Object.entries(parsed.pending || {})) {
      if (!object(item) || !object(item.data) || completedEventKey(item.data.workout_id) !== key ||
          !Number.isFinite(item.due) || item.due < 0) throw new Error('Invalid pending workout completion');
    }
    return { keys: parsed.keys, pending: parsed.pending || {} };
  } catch (e) {
    if (e.code === 'ENOENT') return { keys: {}, pending: {} };
    throw e; // An unreadable outbox must never become an empty deduplication record.
  }
}

// True the first time `key` is claimed for this profile. The file is the record, so a later
// rewrite — or the other request, after a restart — still sees it. Oldest keys fall off past
// MAX_KEYS; a workout already stored is not mailed again just because its key aged out.
export function claimEvent(dir, uid, key, now = Date.now(), max = MAX_KEYS) {
  if (!dir || !uid || !key) return false;
  const file = eventsPath(dir, uid);
  const record = readRecord(file), keys = record.keys;
  if (Object.prototype.hasOwnProperty.call(keys, key)) return false;
  keys[key] = now;
  const names = Object.keys(keys);
  if (names.length > max) {
    names.sort((a, b) => (Number(keys[a]) || 0) - (Number(keys[b]) || 0));
    for (const old of names.slice(0, names.length - max)) delete keys[old];
  }
  atomicWrite(file, JSON.stringify({ ...record, keys }), 0o600);
  return true;
}

// Both completion ingress paths share this durable hold. Resolve against the latest saved
// workout before the FIRST mail/webhook, rather than claiming an incomplete snapshot forever.
// A genuine workout without readable health still gets one completion after the bounded grace.
export function completionOutbox({ dir, readState, deliver, waitMs = 60_000, now = Date.now }) {
  function mergeHealth(previous, next) {
    if (!previous) return next;
    if (!next) return previous;
    const old = completedHealthFields({ health: previous }).health;
    const fresh = completedHealthFields({ health: next }).health;
    if (!old) return fresh;
    if (!fresh) return old;
    // A changed explicit selection must not borrow metrics from a different HKWorkout.
    const previousIsNewer = old.queried_at != null && fresh.queried_at != null && old.queried_at > fresh.queried_at;
    if (old.workout_id !== fresh.workout_id && (old.workout_id || fresh.workout_id)) return previousIsNewer ? old : fresh;
    const [earlier, later] = previousIsNewer ? [fresh, old] : [old, fresh];
    const merged = { ...earlier, ...Object.fromEntries(Object.entries(later).filter(([, v]) => v != null)) };
    if (merged.heart_rate_avg_bpm != null || merged.heart_rate_max_bpm != null || merged.active_energy_kcal != null) merged.status = 'available';
    return merged;
  }
  const ready = data => {
    const h = completedHealthFields(data).health;
    return h?.heart_rate_avg_bpm > 0 && h?.heart_rate_max_bpm > 0 && h?.active_energy_kcal != null;
  };
  function flush(user) {
    const file = eventsPath(dir, user.id), record = readRecord(file);
    if (!Object.keys(record.pending).length) return;
    const state = readState(user.id);
    if (!state || typeof state !== 'object') return; // Retry unreadable state; never lose health.
    let dirty = false;
    for (const [key, item] of Object.entries(record.pending)) {
      const workout = workoutsOf(state).find(w => completedId(w) === item.data.workout_id);
      const data = workout ? { ...item.data, ...completedPayload(workout, state) } : { ...item.data };
      // A POST may already have richer health than the document sync that raced it.
      if (item.data.health || data.health) {
        data.health = mergeHealth(item.data.health, data.health);
        data.health = completedHealthFields(data).health;
      }
      // Keep partial readings seen in a later PUT even if another partial snapshot follows it.
      if (JSON.stringify(data) !== JSON.stringify(item.data)) { item.data = data; dirty = true; }
      if (!ready(data) && now() < item.due) continue;
      delete record.pending[key];
      dirty = true;
      if (Object.hasOwn(record.keys, key)) continue;
      record.keys[key] = now();
      const names = Object.keys(record.keys).sort((a, b) => record.keys[a] - record.keys[b]);
      for (const old of names.slice(0, Math.max(0, names.length - MAX_KEYS))) delete record.keys[old];
      atomicWrite(file, JSON.stringify(record), 0o600);
      dirty = false;
      deliver(user, 'workout.completed', data);
    }
    if (dirty) atomicWrite(file, JSON.stringify(record), 0o600);
  }
  function enqueue(user, data) {
    const key = completedEventKey(data.workout_id);
    if (!key) return { invalid: true };
    const file = eventsPath(dir, user.id), record = readRecord(file);
    if (Object.hasOwn(record.keys, key)) return { duplicate: true };
    const old = record.pending[key];
    record.pending[key] = { due: old?.due ?? now() + waitMs,
      data: { ...old?.data, ...data, ...((old?.data.health || data.health) ?
        { health: mergeHealth(old?.data.health, data.health) } : {}) } };
    atomicWrite(file, JSON.stringify(record), 0o600);
    flush(user);
    return { pending: !!readRecord(file).pending[key] };
  }
  return { enqueue, flush };
}

// POST /api/events. Events we cannot key (no workout id, or not a completion) send as they
// always have. A completion whose id was already claimed — by a sync write, or an earlier post —
// does not send again.
export function claimClientEvent(dir, uid, type, data, now, eventId) {
  if (type !== 'workout.completed') {
    // Stable optional transport key; preserve legacy clients without a key.
    if (typeof eventId !== 'string' || !eventId || eventId.length > ID_MAX) return true;
    return claimEvent(dir, uid, `client:${type}:${eventId}`, now);
  }
  const key = completedEventKey(data && typeof data === 'object' ? data.workout_id : null);
  if (!key) return true;
  return claimEvent(dir, uid, key, now);
}

function workoutsOf(state) {
  return state && typeof state === 'object' && Array.isArray(state.workouts) ? state.workouts : [];
}

// A saved session. `end` is epoch milliseconds on both clients; anything else is not a finish.
function completedId(w) {
  if (!w || typeof w !== 'object' || Array.isArray(w)) return null;
  const key = completedEventKey(w.id);
  if (!key) return null;
  if (typeof w.end !== 'number' || !Number.isFinite(w.end) || w.end <= 0) return null;
  return w.id;
}

// Completed sessions in `next` whose id was not already completed in `prev`.
// A rewrite of the same id (edited sets, a new end) is not a new session.
export function newlyCompletedWorkouts(prev, next) {
  const before = new Set();
  for (const w of workoutsOf(prev)) {
    const id = completedId(w);
    if (id) before.add(id);
  }
  const seen = new Set();
  const out = [];
  for (const w of workoutsOf(next)) {
    const id = completedId(w);
    if (!id || before.has(id) || seen.has(id)) continue;
    seen.add(id);
    out.push(w);
  }
  return out;
}

function asKg(w, unit) {
  if (w == null) return null;
  const n = typeof w === 'number' ? w : Number(w);
  if (!Number.isFinite(n)) return null;
  return unit === 'lb' ? r1(n * LB_IN_KG) : n;
}

// Same fields workout-events.js posts, so one consumer can read either mail.
// Names are the catalogue's English title (or the person's own name); the API image does not
// carry the web app's translated name packs.
function exerciseNames(id, state) {
  const custom = (Array.isArray(state?.customEx) ? state.customEx : []).find(c => c && c.id === id && c.n);
  if (custom) return { name: String(custom.n), name_en: String(custom.n) };
  const en = libraryName(id);
  return { name: en || String(id), name_en: en || null };
}

function mapSet(s, i, unit) {
  const row = s && typeof s === 'object' ? s : {};
  return {
    n: i + 1,
    done: !!row.done,
    reps: row.r ?? null,
    weight_kg: asKg(row.w, unit),
    duration_sec: row.sec != null ? row.sec : row.min != null ? Math.round(row.min * 60) : null,
    distance_km: row.km ?? null,
    type: row.type || row.phase || null,
    done_at: row.at || null,
  };
}

function totals(exercises) {
  let sets = 0, reps = 0, vol = 0, cardioSec = 0;
  for (const e of exercises) for (const s of e.sets) {
    if (!s.done) continue;
    sets++;
    if (s.reps) reps += s.reps;
    if (s.reps && s.weight_kg) vol += s.reps * s.weight_kg;
    if (s.duration_sec && !s.reps) cardioSec += s.duration_sec;
  }
  return { sets, reps, volume_kg: r1(vol), cardio_min: r1(cardioSec / 60) };
}

export function completedPayload(w, state) {
  const unit = state?.unit;
  const entries = (Array.isArray(w.entries) ? w.entries : []).filter(e => e && typeof e === 'object');
  const exercises = entries.map((e, i) => {
    const names = exerciseNames(e.id, state);
    const sets = (Array.isArray(e.sets) ? e.sets : []).map((s, k) => mapSet(s, k, unit));
    return {
      index: i + 1,
      total: entries.length,
      exercise_id: e.id,
      name: names.name,
      name_en: names.name_en,
      rest_sec_planned: e.target?.restSec ?? state?.restSec ?? null,
      note: e.note || null,
      sets,
    };
  });
  const start = typeof w.start === 'number' && Number.isFinite(w.start) ? w.start : null;
  const end = w.end;
  return {
    workout_id: w.id,
    name: w.name ?? null,
    routine_ids: w.routineIds || (w.routineId ? [w.routineId] : []),
    started_at: start,
    ended_at: end,
    duration_min: start == null ? null : r1((end - start) / 60000),
    body_weight_kg: asKg(w.bw, unit) ?? null,
    totals: totals(exercises),
    exercises,
    ...completedHealthFields(w),
  };
}
