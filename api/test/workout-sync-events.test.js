/* A finished session that shows up in PUT /api/data is mailed and webhooked once,
   through the same helpers as POST /api/events from native or web clients.
   A later rewrite of that id, or the web client's own post of it, does not send again.
   workout.started is still only what the client posts: the synced document has no in-progress
   session to see one in. */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  claimClientEvent, claimEvent, completionOutbox, completedEventKey, completedPayload, eventsPath, newlyCompletedWorkouts,
} from '../workout-sync-events.js';
import { boundPort } from './helpers.mjs';

const API = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const sleep = ms => new Promise(r => setTimeout(r, ms));

function workout(id, extra = {}) {
  const start = Object.prototype.hasOwnProperty.call(extra, 'start') ? extra.start : 1_700_000_000_000;
  const end = Object.prototype.hasOwnProperty.call(extra, 'end') ? extra.end : start + 40 * 60_000;
  return {
    id, d: '2026-10-26', name: 'Push', start, end, routineId: 'plan', routineIds: ['plan'], bw: 70,
    entries: [{
      id: '0001', note: 'easy', target: { restSec: 90 },
      sets: [{ w: 20, r: 10, done: true, at: end - 1000 }, { w: 20, r: 8, done: false }],
    }],
    ...extra, id, start, end,
  };
}

test('a completed workout is new only the first time its id is stored with an end', () => {
  const old = workout('already');
  const prev = { workouts: [old, { id: 'open', start: 5 }, null, 'nope'] };
  const next = {
    active: { id: 'live', start: 9 },
    workouts: [
      workout('already', { name: 'renamed', end: old.end + 5000 }),
      { id: 'open', start: 5, end: 1_700_000_100_000 },
      workout('fresh'),
      workout('fresh', { name: 'dup' }),
      { id: '', end: 10 },
      { id: 'text-end', end: '1700000000000' },
      { id: 'no-end', start: 1 },
    ],
  };
  assert.deepEqual(newlyCompletedWorkouts(prev, next).map(w => w.id), ['open', 'fresh']);
  assert.deepEqual(newlyCompletedWorkouts(null, { workouts: [workout('only')] }).map(w => w.id), ['only']);
  assert.deepEqual(newlyCompletedWorkouts({ workouts: [] }, { workouts: [] }), []);
  assert.equal(completedEventKey(''), null);
  assert.equal(completedEventKey('x'.repeat(201)), null);
});

test('the sync payload matches the fields the web client posts', () => {
  const end = 1_700_000_000_000 + 40 * 60_000;
  const w = workout('w', {
    start: 1_700_000_000_000, end, bw: 154, routineIds: undefined, routineId: 'plan',
    entries: [
      { id: '0001', sets: [{ w: 100, r: 10, done: true, at: end }] },
      { id: 'mine', note: '', target: {}, sets: [{ min: 30, done: true }, { sec: 45, r: 5, done: true, w: 10 }] },
      null,
    ],
  });
  const payload = completedPayload(w, {
    unit: 'lb', restSec: 75,
    customEx: [{ id: 'mine', n: '我的动作' }],
  });
  assert.equal(payload.workout_id, 'w');
  assert.deepEqual(payload.routine_ids, ['plan']);
  assert.equal(payload.duration_min, 40);
  assert.equal(payload.body_weight_kg, 69.9);
  assert.equal(payload.exercises.length, 2);
  assert.equal(payload.exercises[0].name, '3/4 sit-up');
  assert.equal(payload.exercises[0].name_en, '3/4 sit-up');
  assert.equal(payload.exercises[0].sets[0].weight_kg, 45.4);
  assert.equal(payload.exercises[0].sets[0].reps, 10);
  assert.equal(payload.exercises[1].name, '我的动作');
  assert.equal(payload.exercises[1].rest_sec_planned, 75);
  assert.equal(payload.exercises[1].note, null);
  assert.equal(payload.exercises[1].sets[0].duration_sec, 1800);
  assert.deepEqual(payload.totals, { sets: 3, reps: 15, volume_kg: 476.5, cardio_min: 30 });
  const unknown = completedPayload({ id: 'u', end: 5, entries: [{ id: 'nope', sets: [] }] }, { unit: 'kg' });
  assert.equal(unknown.exercises[0].name, 'nope');
  assert.equal(unknown.exercises[0].name_en, null);
  assert.equal(unknown.duration_min, null);
});

test('claim is once per workout id, per profile, and survives a rewrite of the file', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'gym-events-'));
  try {
    assert.equal(claimClientEvent(dir, 'u', 'workout.started', { workout_id: 'a' }), true);
    assert.equal(claimClientEvent(dir, 'u', 'workout.started', { workout_id: 'a' }), true);
    assert.equal(claimClientEvent(dir, 'u', 'workout.completed', {}), true);
    assert.equal(claimEvent(dir, 'u', completedEventKey('a')), true);
    assert.equal(claimClientEvent(dir, 'u', 'workout.completed', { workout_id: 'a' }), false);
    assert.equal(claimEvent(dir, 'other', completedEventKey('a')), true);
    // Windows ACLs do not expose Unix permission bits; keep checking 0600 on deployment hosts.
    if (process.platform !== 'win32') assert.equal(fs.statSync(eventsPath(dir, 'u')).mode & 0o777, 0o600);
    const kept = JSON.parse(fs.readFileSync(eventsPath(dir, 'u'), 'utf8'));
    assert.deepEqual(Object.keys(kept.keys), ['workout.completed:a']);
    fs.writeFileSync(eventsPath(dir, 'u'), 'not json');
    assert.throws(() => claimEvent(dir, 'u', completedEventKey('b')));
    fs.writeFileSync(eventsPath(dir, 'u'), JSON.stringify({ keys: {} }));
    assert.equal(claimEvent(dir, 'u', completedEventKey('b'), 2, 2), true);
    assert.equal(claimEvent(dir, 'u', completedEventKey('c'), 3, 2), true);
    assert.equal(claimEvent(dir, 'u', completedEventKey('d'), 4, 2), true);
    const pruned = JSON.parse(fs.readFileSync(eventsPath(dir, 'u'), 'utf8')).keys;
    assert.deepEqual(Object.keys(pruned).sort(), ['workout.completed:c', 'workout.completed:d']);
    assert.equal(claimEvent(dir, 'u', completedEventKey('b'), 5, 2), true);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve(server.address().port));
  });
}

function smtpCatcher() {
  const messages = [];
  const server = net.createServer(sock => {
    let buf = '', mode = 'cmd';
    sock.write('220 localhost ESMTP\r\n');
    sock.on('data', chunk => {
      buf += chunk.toString('utf8');
      for (;;) {
        if (mode === 'data') {
          const end = buf.indexOf('\r\n.\r\n');
          if (end < 0) return;
          messages.push(buf.slice(0, end));
          buf = buf.slice(end + 5);
          mode = 'cmd';
          sock.write('250 OK\r\n');
          continue;
        }
        const nl = buf.indexOf('\r\n');
        if (nl < 0) return;
        const line = buf.slice(0, nl);
        buf = buf.slice(nl + 2);
        const cmd = line.split(' ')[0].toUpperCase();
        if (cmd === 'DATA') { mode = 'data'; sock.write('354 Go\r\n'); }
        else if (cmd === 'QUIT') { sock.write('221 bye\r\n'); sock.end(); }
        else sock.write('250 OK\r\n');
      }
    });
    sock.on('error', () => {});
  });
  return { server, messages };
}

test('PUT /api/data mails a newly completed workout once, including when the web client also posts it', async t => {
  const hits = [];
  const smtp = smtpCatcher();
  const hook = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', d => chunks.push(d));
    req.on('end', () => {
      try { hits.push(JSON.parse(Buffer.concat(chunks).toString('utf8'))); } catch { hits.push(null); }
      res.writeHead(204); res.end();
    });
  });
  const smtpPort = await listen(smtp.server);
  const hookPort = await listen(hook);
  const caught = smtp.messages;

  const root = fs.realpathSync(os.tmpdir());
  const dir = fs.mkdtempSync(path.join(root, 'gym-sync-events-'));
  const user = { id: 'only-owner', name: 'Owner', created: new Date().toISOString() };
  const secret = crypto.randomBytes(32).toString('hex');
  const seeded = workout('already-there', { name: 'Old', start: 1_700_000_000_000, end: 1_700_000_000_000 + 30 * 60_000, entries: [] });
  fs.writeFileSync(path.join(dir, 'secret'), secret);
  fs.writeFileSync(path.join(dir, 'db.json'), JSON.stringify({ users: [user], creds: [], subs: [], invites: [] }));
  fs.writeFileSync(path.join(dir, `state-${user.id}.json`), JSON.stringify({
    unit: 'kg', restSec: 60, routines: [{ id: 'plan', name: 'Push', ex: [] }], customEx: [],
    workouts: [seeded], _rev: 3, _wid: 'seedwid',
  }));
  const child = spawn(process.execPath, ['server.js'], {
    cwd: API, stdio: ['ignore', 'pipe', 'pipe'],
    env: {
      ...process.env, PORT: '0', DATA_DIR: dir, ORIGIN: 'http://localhost:8080', RP_ID: 'localhost',
      COACH_DISABLED: '1', MEDIA_UPLOADS: '0',
      WORKOUT_EMAIL_TO: 'lumi@example.com', WORKOUT_EMAIL_FROM: 'opengym@localhost',
      SMTP_HOST: '127.0.0.1', SMTP_PORT: String(smtpPort),
      WORKOUT_WEBHOOK_URL: `http://127.0.0.1:${hookPort}/hook`,
      WORKOUT_COMPLETION_HEALTH_WAIT_MS: '800',
    },
  });
  let log = '';
  child.stdout.on('data', d => log += d);
  child.stderr.on('data', d => log += d);
  t.after(() => {
    child.kill('SIGKILL');
    smtp.server.close();
    hook.close();
    fs.rmSync(dir, { recursive: true, force: true });
  });
  const base = `http://127.0.0.1:${await boundPort(child, () => log)}`;
  const webPayload = `${user.id}:${Date.now() + 86400000}:0`;
  const token = `${webPayload}.${crypto.createHmac('sha256', secret).update(webPayload).digest('base64url')}`;
  const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  const webHeaders = {
    Cookie: `gymsid=${webPayload}.${crypto.createHmac('sha256', secret).update(webPayload).digest('base64url')}`,
    'Content-Type': 'application/json',
  };

  const mailed = id => caught.filter(m => m.includes(`"workout_id": "${id}"`) && m.includes('workout.completed'));
  const hooked = id => hits.filter(h => h && h.type === 'workout.completed' && h.data && h.data.workout_id === id);
  async function arrived(id) {
    for (let i = 0; i < 100; i++) {
      if (mailed(id).length && hooked(id).length) return;
      await sleep(20);
    }
    assert.fail(`no workout.completed for ${id}\nmail ${caught.length} hook ${hits.length}\n${log}`);
  }
  async function settled(id, n) {
    await sleep(400);
    assert.equal(mailed(id).length, n, log);
    assert.equal(hooked(id).length, n);
  }
  async function read() {
    const r = await fetch(base + '/api/data', { headers });
    const body = await r.json();
    assert.equal(r.status, 200, JSON.stringify(body));
    return body;
  }
  async function put(mutate) {
    const cur = await read();
    const state = JSON.parse(JSON.stringify(cur.state));
    mutate(state);
    const r = await fetch(base + '/api/data', {
      method: 'PUT', headers,
      body: JSON.stringify({ state, baseRev: cur.rev, baseWid: cur.state._wid }),
    });
    const body = await r.json();
    assert.equal(r.status, 200, JSON.stringify(body));
    return body;
  }
  async function post(type, data, useHeaders = headers, event_id) {
    const r = await fetch(base + '/api/events', { method: 'POST', headers: useHeaders, body: JSON.stringify({ type, data, event_id }) });
    return { status: r.status, body: await r.json() };
  }

  const start = Date.now() - 40 * 60_000;
  const end = start + 39 * 60_000;
  await put(s => { s.restSec = 90; });
  await settled('already-there', 0);
  assert.equal(log.includes('[events] workout.completed'), false);

  // Reproduce the incident: POST wins the race with no HR; PUT arrives with health later.
  const lateHealth = { status: 'available', heart_rate_avg_bpm: 109, heart_rate_max_bpm: 134, active_energy_kcal: 202 };
  const held = await post('workout.completed', { workout_id: 'late-health', name: '力量 A' });
  assert.equal(held.body.pending, true);
  await settled('late-health', 0); // Neither channel may send the early incomplete snapshot.
  await put(s => { s.workouts.push(workout('late-health', { start, end, health: lateHealth })); });
  await arrived('late-health');
  assert.equal(hooked('late-health')[0].data.health.heart_rate_avg_bpm, 109);
  assert.equal(hooked('late-health')[0].data.health.heart_rate_max_bpm, 134);
  assert.equal(hooked('late-health')[0].data.health.active_energy_kcal, 202);
  assert.match(mailed('late-health')[0], /"heart_rate_max_bpm": 134/);
  assert.equal((await post('workout.completed', { workout_id: 'late-health' })).body.duplicate, true);
  await settled('late-health', 1);

  // Reverse order: PUT has partial metrics; the later batch upgrades the held completion.
  await put(s => { s.workouts.push(workout('put-late', { start, end, health: { status: 'available', active_energy_kcal: 202 } })); });
  await settled('put-late', 0);
  await put(s => { s.workouts.find(w => w.id === 'put-late').health = lateHealth; });
  await arrived('put-late');
  assert.equal(hooked('put-late')[0].data.health.heart_rate_avg_bpm, 109);
  assert.match(mailed('put-late')[0], /"active_energy_kcal": 202/);

  await put(s => { s.workouts.push(workout('ios-1', { name: '腿', start, end, bw: 70,
    health: { source: 'apple_health', status: 'available', window_start: start, window_end: end,
      queried_at: end + 1000, heart_rate_avg_bpm: 123.5, heart_rate_max_bpm: 168, active_energy_kcal: 245 }
  })); });
  await arrived('ios-1');
  assert.match(log, /\[events\] workout\.completed ios-1 via sync/);
  const hookBody = hooked('ios-1')[0];
  assert.equal(hookBody.user.id, user.id);
  assert.equal(hookBody.data.name, '腿');
  assert.equal(hookBody.data.exercises[0].exercise_id, '0001');
  assert.equal(hookBody.data.exercises[0].name, '3/4 sit-up');
  assert.equal(hookBody.data.exercises[0].sets[0].reps, 10);
  assert.equal(hookBody.data.exercises[0].sets[0].weight_kg, 20);
  assert.equal(hookBody.data.totals.sets, 1);
  assert.equal(hookBody.data.duration_min, 39);
  assert.equal(hookBody.data.health.heart_rate_avg_bpm, 123.5);
  assert.equal(hookBody.data.health.heart_rate_max_bpm, 168);
  assert.equal(hookBody.data.health.active_energy_kcal, 245);
  assert.match(mailed('ios-1')[0], /"heart_rate_avg_bpm": 123.5/);
  assert.match(mailed('ios-1')[0], /"active_energy_kcal": 245/);
  assert.match(mailed('ios-1')[0], /Subject: openGym workout\.completed/);
  assert.match(mailed('ios-1')[0], /To: lumi@example.com/);
  const saved = JSON.parse(fs.readFileSync(path.join(dir, `state-${user.id}.json`), 'utf8'));
  assert.ok(saved.workouts.some(w => w.id === 'ios-1' && w.end === end));

  await put(s => {
    const w = s.workouts.find(x => x.id === 'ios-1');
    w.entries[0].sets[0].r = 12;
    w.name = '腿（改）';
    w.health.active_energy_kcal = 250; // Late HealthKit data updates records, not a second completion.
  });
  await settled('ios-1', 1);

  const again = await post('workout.completed', { workout_id: 'ios-1', name: 'from web' }, webHeaders);
  assert.equal(again.status, 202);
  assert.equal(again.body.duplicate, true);
  await settled('ios-1', 1);

  const denied = await post('workout.completed', { workout_id: 'nope' }, { Authorization: 'Bearer invalid', 'Content-Type': 'application/json' });
  assert.equal(denied.status, 401);
  await settled('nope', 0);

  const posted = await post('workout.completed', { workout_id: 'web-1', name: 'from web' });
  assert.equal(posted.status, 202);
  assert.equal(posted.body.duplicate, undefined);
  await arrived('web-1');
  await put(s => { s.workouts.push(workout('web-1', { name: 'from phone later', start, end })); });
  await settled('web-1', 1);

  await put(s => { s.workouts.push({ id: 'still-open', name: 'Open', start, entries: [] }); });
  await settled('still-open', 0);
  await put(s => { s.workouts.find(w => w.id === 'still-open').end = end; });
  await arrived('still-open');

  await put(s => {
    s.workouts.push(workout('batch-a', { start, end }));
    s.workouts.push(workout('batch-b', { start, end }));
  });
  await arrived('batch-a');
  await arrived('batch-b');

  const importedHealth = { source: 'apple_health', status: 'available', window_start: start, window_end: end,
    queried_at: end + 1000, workout_id: 'B7F450E5-7462-451D-BF86-4BA5F8E7B223',
    heart_rate_avg_bpm: 130, heart_rate_max_bpm: 165, active_energy_kcal: 320 };
  await put(s => { s.workouts.push(workout(importedHealth.workout_id, { name: '骑行 · 健康导入', start, end,
    entries: [], routineId: null, routineIds: [], health: importedHealth })); });
  await arrived(importedHealth.workout_id);
  const imported = hooked(importedHealth.workout_id)[0].data;
  assert.deepEqual(imported.exercises, []);
  assert.deepEqual(imported.routine_ids, []);
  assert.equal(imported.health.active_energy_kcal, 320);
  assert.match(mailed(importedHealth.workout_id)[0], /"heart_rate_avg_bpm": 130/);
  await put(s => { s.workouts.find(w => w.id === importedHealth.workout_id).health.active_energy_kcal = 325; });
  await settled(importedHealth.workout_id, 1);

  const firstStart = await post('workout.started', { workout_id: 'start-same', marker: 'first-start' });
  const secondStart = await post('workout.started', { workout_id: 'start-same', marker: 'second-start' });
  assert.equal(firstStart.status, 202);
  assert.equal(secondStart.status, 202);
  for (let i = 0; i < 100 && (!caught.some(m => m.includes('first-start')) || !caught.some(m => m.includes('second-start'))); i++) await sleep(20);
  assert.ok(caught.some(m => m.includes('first-start') && m.includes('workout.started')));
  assert.ok(caught.some(m => m.includes('second-start') && m.includes('workout.started')));
  assert.equal(hits.filter(h => h && h.type === 'workout.started').length, 2);
  for (const type of ['workout.started', 'exercise.completed']) {
    const first = await post(type, {workout_id:'retry-live'}, headers, 'stable-live');
    const retry = await post(type, {workout_id:'retry-live'}, headers, 'stable-live');
    assert.equal(first.status,202);
    assert.equal(first.body.duplicate,undefined);
    assert.equal(retry.body.duplicate,true);
  }
});

test('stable transport keys deduplicate live events per profile and type', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'event-retry-'));
  try {
    for (const type of ['workout.started', 'exercise.completed']) {
      assert.equal(claimClientEvent(dir,'one',type,{},1,'stable'),true);
      assert.equal(claimClientEvent(dir,'one',type,{},2,'stable'),false);
      assert.equal(claimClientEvent(dir,'two',type,{},3,'stable'),true);
    }
  } finally { fs.rmSync(dir,{recursive:true,force:true}); }
});

test('completion hold survives restart, merges partial health, and keeps the original deadline', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'completion-hold-'));
  try {
    let time = 1000, state = { workouts: [] };
    const deliveries = [], user = { id: 'u' };
    const options = { dir, now: () => time, waitMs: 60_000, readState: () => state,
      deliver: (...args) => deliveries.push(args) };
    const first = completionOutbox(options);
    assert.deepEqual(first.enqueue(user, { workout_id: 'w' }), { pending: true });
    time += 30_000;
    // A started/exercise claim must preserve the pending completion in the shared file.
    claimClientEvent(dir, user.id, 'exercise.completed', {}, time, 'ex');
    const restarted = completionOutbox(options);
    restarted.enqueue(user, { workout_id: 'w', health: { heart_rate_avg_bpm: 109, heart_rate_max_bpm: 134 } });
    assert.equal(deliveries.length, 0);
    state.workouts.push(workout('w', { health: { active_energy_kcal: 202 } }));
    restarted.flush(user);
    assert.equal(deliveries.length, 1);
    assert.equal(deliveries[0][2].health.heart_rate_avg_bpm, 109);
    assert.equal(deliveries[0][2].health.active_energy_kcal, 202);
    assert.deepEqual(restarted.enqueue(user, { workout_id: 'w' }), { duplicate: true });

    restarted.enqueue(user, { workout_id: 'no-health' });
    time += 59_999;
    restarted.enqueue(user, { workout_id: 'no-health' });
    assert.equal(deliveries.length, 1);
    time++;
    completionOutbox(options).flush(user);
    assert.equal(deliveries.length, 2); // Genuine absent readings never become invented zeros.
    assert.equal(deliveries[1][2].health, undefined);
    completionOutbox(options).flush(user);
    assert.equal(deliveries.length, 2);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('completion hold persists partial sync readings and never combines different manual selections', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'completion-partial-'));
  try {
    let state = { workouts: [] };
    const deliveries = [], user = { id: 'u' };
    const options = { dir, now: () => 1000, readState: () => state,
      deliver: (_, __, data) => deliveries.push(data) };
    completionOutbox(options).enqueue(user, { workout_id: 'partial' });
    state.workouts = [workout('partial', { health: { workout_id: 'hk-a', active_energy_kcal: 202 } })];
    completionOutbox(options).flush(user);
    assert.equal(deliveries.length, 0);
    // The server restarts and the next document has only HR. Previously seen kcal survive.
    state.workouts[0].health = { workout_id: 'hk-a', heart_rate_avg_bpm: 109, heart_rate_max_bpm: 134 };
    completionOutbox(options).flush(user);
    assert.deepEqual([deliveries[0].health.heart_rate_avg_bpm, deliveries[0].health.heart_rate_max_bpm,
      deliveries[0].health.active_energy_kcal], [109, 134, 202]);

    state.workouts = [workout('changed', { health: { workout_id: 'hk-a', queried_at: 100, active_energy_kcal: 202 } })];
    const outbox = completionOutbox(options);
    outbox.enqueue(user, { workout_id: 'changed', health: state.workouts[0].health });
    outbox.enqueue(user, { workout_id: 'changed', health: { workout_id: 'hk-b', queried_at: 200,
      heart_rate_avg_bpm: 120, heart_rate_max_bpm: 140 } });
    assert.equal(deliveries.length, 1); // An older saved selection cannot overwrite the newer POST.
    assert.equal(JSON.parse(fs.readFileSync(eventsPath(dir, 'u'))).pending['workout.completed:changed'].data.health.workout_id, 'hk-b');
    state.workouts[0].health = { workout_id: 'hk-b', queried_at: 300, active_energy_kcal: 250 };
    outbox.flush(user);
    assert.equal(deliveries.length, 2);
    assert.deepEqual([deliveries[1].health.workout_id, deliveries[1].health.heart_rate_avg_bpm,
      deliveries[1].health.active_energy_kcal], ['hk-b', 120, 250]);

    state.workouts = [];
    outbox.enqueue(user, { workout_id: 'unreadable' });
    state = Symbol('unreadable');
    completionOutbox({ ...options, now: () => 100_000 }).flush(user);
    assert.equal(deliveries.length, 2);
    state = { workouts: [] };
    completionOutbox({ ...options, now: () => 100_000 }).flush(user);
    assert.equal(deliveries.length, 3);
    assert.equal(deliveries[2].health, undefined);

    fs.writeFileSync(eventsPath(dir, 'u'), JSON.stringify({ keys: {}, pending: {
      'workout.completed:corrupt': { data: { workout_id: 'corrupt' } },
    } }));
    assert.throws(() => outbox.flush(user), /Invalid pending/);
    assert.equal(deliveries.length, 3);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
