// Finished sessions that arrive through PUT /api/data, rather than POST /api/events.
//
// The web app watches its own store and fire-and-forgets workout.completed (frontend
// workout-events.js). The personal iOS build never does: it only syncs the saved document
// (GET/PUT /api/data), and its credential is not allowed to post events. A session is finished
// when it shows up in `workouts` with an `end` timestamp. In-progress work is not a signal —
// both clients keep `active` on the device, and PUT deletes it — so workout.started is not
// emitted from here. A start inferred at the moment the session is already over would be late,
// and a start inferred from a field the document does not store would fire again on every sync.
//
// One workout id is mailed once. The web client usually posts the event and then pushes the
// same id; whichever request claims the key first sends, and the other does not.
import fs from 'node:fs';
import path from 'node:path';
import { atomicWrite } from './durable.js';
import { libraryName } from './coach/core/library.js';

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

function readKeys(file) {
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    const raw = parsed && parsed.keys;
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
    return raw;
  } catch { return {}; }
}

// True the first time `key` is claimed for this profile. The file is the record, so a later
// rewrite — or the other request, after a restart — still sees it. Oldest keys fall off past
// MAX_KEYS; a workout already stored is not mailed again just because its key aged out.
export function claimEvent(dir, uid, key, now = Date.now(), max = MAX_KEYS) {
  if (!dir || !uid || !key) return false;
  const file = eventsPath(dir, uid);
  const keys = readKeys(file);
  if (Object.prototype.hasOwnProperty.call(keys, key)) return false;
  keys[key] = now;
  const names = Object.keys(keys);
  if (names.length > max) {
    names.sort((a, b) => (Number(keys[a]) || 0) - (Number(keys[b]) || 0));
    for (const old of names.slice(0, names.length - max)) delete keys[old];
  }
  atomicWrite(file, JSON.stringify({ keys }), 0o600);
  return true;
}

// POST /api/events. Events we cannot key (no workout id, or not a completion) send as they
// always have. A completion whose id was already claimed — by a sync write, or an earlier post —
// does not send again.
export function claimClientEvent(dir, uid, type, data, now) {
  if (type !== 'workout.completed') return true;
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
  };
}
