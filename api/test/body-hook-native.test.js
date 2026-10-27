import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { parseHealth, LEAN_ID } from '../body-hook.js';

test('native stage minutes validate independently and preserve missing values', () => {
  assert.deepEqual(parseHealth({ deep_min: 45.25, rem_min: 0, core_min: null, awake_min: -1, asleep_min: 1441 }), { deep_min: 45.3, rem_min: 0 });
});

test('one authenticated POST persists body and daily health; partial and legacy retries merge', async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'gym-body-daily-'));
  fs.writeFileSync(path.join(dir, 'db.json'), JSON.stringify({ users: [{ id: 'native_test', name: 'Test' }], creds: [], subs: [], invites: [] }));
  const child = spawn(process.execPath, ['server.js'], {
    cwd: new URL('../', import.meta.url), stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, DATA_DIR: dir, PORT: '0', ORIGIN: 'http://localhost', RP_ID: 'localhost',
      WEIGHT_HOOK_TOKEN: 'test-only-token', WEIGHT_HOOK_UID: 'native_test', WORKOUT_WEBHOOK_URL: '', WORKOUT_EMAIL_TO: '' }
  });
  t.after(async () => { const stopped = once(child, 'exit'); child.kill(); await stopped; fs.rmSync(dir, { recursive: true, force: true }); });
  let log = '';
  const port = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(log)), 20000);
    child.stdout.on('data', d => { log += d; const m = /gym-api on :(\d+)/.exec(log); if (m) { clearTimeout(timer); resolve(m[1]); } });
    child.stderr.on('data', d => { log += d; });
    child.once('exit', code => { clearTimeout(timer); reject(new Error(`exit ${code}: ${log}`)); });
  });
  const post = async body => {
    const response = await fetch(`http://127.0.0.1:${port}/api/hook/body`, { method: 'POST', headers: { Authorization: 'Bearer test-only-token', 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    assert.equal(response.status, 200); return response.json();
  };
  const health = { sleep_hours: 7.5, deep_min: 60, core_min: 300, rem_min: 80, asleep_min: 10, awake_min: 15, resting_hr: 58, hrv_ms: 42.5, steps: 8123 };
  const body = { date: '2026-10-27', weight_kg: 72.4, body_fat_pct: 18.5, lean_mass_kg: 59 };
  const result = await post({ ...body, ...health });
  assert.equal(result.ok, true);
  for (const [key, value] of Object.entries(health)) assert.equal(result[key], value);
  const state = JSON.parse(fs.readFileSync(path.join(dir, 'state-native_test.json')));
  assert.equal(state.bodyweight[0].w, 72.4);
  assert.equal(state.measurements[0].bodyFat, 18.5);
  assert.equal(state.measurements[0].other.find(x => x.id === LEAN_ID).value, 59);
  await post({ date: body.date, steps: 9000 });
  await post({ ...body, weight_kg: 73 });
  const stored = JSON.parse(fs.readFileSync(path.join(dir, 'health-native_test.json')))[body.date];
  const { t: stamp, ...daily } = stored;
  assert.ok(stamp > 0); assert.deepEqual(daily, { ...health, steps: 9000 });
});
