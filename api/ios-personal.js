// Private iOS builds use a data-and-workout-events credential, never an anonymous default user.
// It is signed by the existing server secret and revoked by the existing user's sv counter.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const allowed = new Set(['GET /api/me', 'GET /api/data', 'GET /api/data/rev', 'PUT /api/data', 'POST /api/events']);

export function personalSession(req, payload, users, bearer) {
  if (!bearer || !allowed.has(`${req.method} ${new URL(req.url, 'http://localhost').pathname}`)) return null;
  const match = /^ios:([^:]+):(\d+):([a-f0-9]{64})$/.exec(payload);
  if (!match) return null;
  const user = users.find(u => u.id === match[1]);
  if (!user || user.disabled || Number(match[2]) !== (user.sv || 0)) return null;
  return { user, exp: Infinity, bearer: true, personal: true };
}

export function createPersonalConfig(users, secret, base) {
  if (users.length !== 1 || users[0].disabled) throw new Error('Personal provisioning requires exactly one enabled user.');
  const url = new URL(base);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) throw new Error('Use the HTTPS web base URL.');
  const user = users[0];
  const payload = `ios:${user.id}:${user.sv || 0}:${crypto.randomBytes(32).toString('hex')}`;
  const mac = crypto.createHmac('sha256', secret).update(payload).digest('base64url');
  return { base: url.href.replace(/\/+$/, ''), token: `${payload}.${mac}`, userID: user.id, name: user.name || '个人数据' };
}

// Run only on the server, through SSH. The credential is written privately, never logged.
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [command, directory, base, output] = process.argv.slice(2);
    if (command !== '--provision' || !directory || !base || !output) throw new Error('Usage: node ios-personal.js --provision DATA_DIR HTTPS_BASE OUTPUT_JSON');
    const { users } = JSON.parse(fs.readFileSync(path.join(directory, 'db.json'), 'utf8'));
    const config = createPersonalConfig(users, fs.readFileSync(path.join(directory, 'secret'), 'utf8').trim(), base);
    fs.writeFileSync(output, JSON.stringify(config) + '\n', { flag: 'wx', mode: 0o600 });
    console.log('Private iOS connection configuration created.');
  } catch (error) {
    console.error(error.code === 'EEXIST' ? 'Output already exists; keep the existing private configuration or choose a new output path.' : 'Provisioning failed; check the arguments, single-user database and private file permissions.');
    process.exitCode = 1;
  }
}
