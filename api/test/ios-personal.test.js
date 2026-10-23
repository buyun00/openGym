import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import { createPersonalConfig, personalSession } from '../ios-personal.js';
import { boundPort } from './helpers.mjs';

test('personal provisioning refuses ambiguous/disabled profiles and unsafe base URLs', () => {
  const user = {id: 'one', name: 'Personal'};
  for (const users of [[], [user, {...user, id: 'two'}], [{...user, disabled: true}]]) {
    assert.throws(() => createPersonalConfig(users, 'secret', 'https://example.com/gym'));
  }
  for (const base of ['http://example.com', 'https://me:secret@example.com', 'https://example.com/?q=1', 'https://example.com/#x']) {
    assert.throws(() => createPersonalConfig([user], 'secret', base));
  }
  const config = createPersonalConfig([user], 'secret', 'https://example.com/gym/');
  assert.equal(config.base, 'https://example.com/gym');
  assert.equal(config.userID, 'one');
});

test('personal capability checks scope, identity, disabled state and revocation version', () => {
  const user = {id: 'one', name: 'Personal', sv: 2};
  const config = createPersonalConfig([user], 'secret', 'https://example.com');
  const payload = config.token.slice(0, config.token.lastIndexOf('.'));
  const req = {method: 'GET', url: '/api/data?rev=1'};
  assert.equal(personalSession(req, payload, [user], true).user.id, 'one');
  assert.equal(personalSession(req, payload, [user], false), null);
  assert.equal(personalSession({...req, url: '/api/admin/users'}, payload, [user], true), null);
  assert.equal(personalSession({...req, method: 'DELETE'}, payload, [user], true), null);
  for (const users of [[], [{...user, id: 'two'}], [{...user, sv: 3}], [{...user, disabled: true}]]) {
    assert.equal(personalSession(req, payload, users, true), null);
  }
});

test('real API: private build reads the web profile without pairing; scope and revocation hold', async t => {
  const root = fs.realpathSync(os.tmpdir()), dir = fs.mkdtempSync(path.join(root, 'opengym-personal-'));
  const user = {id: 'only-owner', name: 'Owner', created: new Date().toISOString()};
  const secret = crypto.randomBytes(32).toString('hex');
  fs.writeFileSync(path.join(dir, 'secret'), secret);
  fs.writeFileSync(path.join(dir, 'db.json'), JSON.stringify({users: [user], creds: [], subs: [], invites: []}));
  const state = {routines: [{id: 'plan', name: 'Web plan', ex: []}], bodyweight: [{d: '2026-10-22', w: 70}], workouts: [], _rev: 1, _wid: 'first'};
  fs.writeFileSync(path.join(dir, `state-${user.id}.json`), JSON.stringify(state));
  const child = spawn(process.execPath, ['server.js'], {cwd: fileURLToPath(new URL('../', import.meta.url)), stdio: ['ignore', 'pipe', 'pipe'],
    env: {...process.env, PORT: '0', DATA_DIR: dir, ORIGIN: 'http://localhost:8080', RP_ID: 'localhost', COACH_DISABLED: '1', MEDIA_UPLOADS: '0'}});
  t.after(async () => {
    if (child.exitCode === null) {const stopped = once(child, 'exit'); child.kill(); await stopped;}
    assert.equal(path.dirname(fs.realpathSync(dir)), root);
    fs.rmSync(dir, {recursive: true, force: true});
  });
  let log = ''; child.stdout.on('data', d => log += d); child.stderr.on('data', d => log += d);
  const port = await boundPort(child, () => log), url = `http://127.0.0.1:${port}`;
  const config = createPersonalConfig([user], secret, 'https://example.com/gym');
  const headers = {Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json'};
  assert.equal((await fetch(url + '/api/data')).status, 401);
  assert.equal((await fetch(url + '/api/data', {headers: {...headers, Authorization: `Bearer ${config.token}x`}})).status, 401);
  assert.equal((await fetch(url + '/api/data', {headers: {Cookie: `gymsid=${config.token}`}})).status, 401);
  const me = await fetch(url + '/api/me', {headers}).then(r => r.json());
  assert.equal(me.user.id, user.id); assert.equal(me.user.admin, false); assert.equal(me.token, undefined);
  const first = await fetch(url + '/api/data', {headers}).then(r => r.json());
  assert.equal(first.state.routines[0].name, 'Web plan'); assert.equal(first.state.bodyweight[0].w, 70);
  const modified = {...first.state, restSec: 125};
  const put = await fetch(url + '/api/data', {method: 'PUT', headers, body: JSON.stringify({state: modified, baseRev: first.rev, baseWid: first.state._wid})});
  assert.equal(put.status, 200);
  assert.equal((await fetch(url + '/api/data/rev', {headers})).status, 200);
  // A scoped credential must never be exchanged for a general account session.
  for (const [method, route] of [['POST', '/api/pair/create'], ['POST', '/api/logout/all'], ['GET', '/api/admin/users']]) {
    assert.equal((await fetch(url + route, {method, headers, ...(method === 'POST' ? {body: '{}'} : {})})).status, 401);
  }
  const payload = `${user.id}:${Date.now() + 86400000}:0`;
  const cookie = payload + '.' + crypto.createHmac('sha256', secret).update(payload).digest('base64url');
  const webHeaders = {Cookie: `gymsid=${cookie}`, 'Content-Type': 'application/json'};
  const web = await fetch(url + '/api/data', {headers: webHeaders}).then(r => r.json());
  assert.equal(web.state.restSec, 125); assert.equal(web.state.bodyweight[0].w, 70);
  assert.equal((await fetch(url + '/api/logout/all', {method: 'POST', headers: webHeaders, body: '{}'})).status, 200);
  assert.equal((await fetch(url + '/api/data', {headers})).status, 401);
});
