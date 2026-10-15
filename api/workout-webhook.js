// Outbound workout webhooks (local addition). POST /api/events from a signed-in app is wrapped
// in an envelope (event id, user, +08:00 timestamps) and forwarded to WORKOUT_WEBHOOK_URL in the
// background: 5 s timeout, 3 attempts. Empty URL = disabled. Results go to the container log.
import crypto from 'node:crypto';

export const EVENT_TYPES = new Set(['workout.started', 'exercise.completed', 'workout.completed', 'test']);
const OFFSET_MIN = 8 * 60;
export function iso8(ms) {
  const d = new Date(Number(ms) + OFFSET_MIN * 60000);
  return d.toISOString().replace('Z', '+08:00');
}
// Every `*_at` number (epoch ms) becomes an ISO string at +08:00.
export function isoAll(v, k = '') {
  if (Array.isArray(v)) return v.map(x => isoAll(x));
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([kk, x]) => [kk, isoAll(x, kk)]));
  if (k.endsWith('_at') && typeof v === 'number' && v > 1e11) return iso8(v);
  return v;
}
export function config() {
  let extra = {};
  try { extra = JSON.parse(process.env.WORKOUT_WEBHOOK_HEADERS || '{}') || {}; } catch { console.warn('[webhook] WORKOUT_WEBHOOK_HEADERS is not JSON, ignored'); }
  return { url: (process.env.WORKOUT_WEBHOOK_URL || '').trim(), secret: process.env.WORKOUT_WEBHOOK_SECRET || '', extra };
}
export function envelope(type, user, data, now = Date.now()) {
  return {
    id: 'evt_' + crypto.randomBytes(12).toString('hex'),
    type, occurred_at: iso8(now),
    user: { id: user.id, name: user.name || null },
    data: isoAll(data || {}),
  };
}
const sleep = ms => new Promise(r => setTimeout(r, ms));
export async function deliver(ev) {
  const { url, secret, extra } = config();
  if (!url) return { skipped: true };
  const body = JSON.stringify(ev);
  const headers = { ...extra, 'Content-Type': 'application/json', 'User-Agent': 'openGym-webhook/1', 'X-OpenGym-Event': ev.type, 'X-OpenGym-Event-Id': ev.id };
  if (secret) {
    headers.Authorization = 'Bearer ' + secret;
    headers['X-OpenGym-Signature'] = 'sha256=' + crypto.createHmac('sha256', secret).update(body).digest('hex');
  }
  let last = '';
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const r = await fetch(url, { method: 'POST', headers, body, signal: AbortSignal.timeout(5000) });
      if (r.ok) { console.log(`[webhook] ${ev.type} ${ev.id} -> ${r.status} (attempt ${attempt})`); return { ok: true, status: r.status, attempt }; }
      last = 'HTTP ' + r.status;
      if (r.status >= 400 && r.status < 500 && r.status !== 408 && r.status !== 429) break;
    } catch (e) { last = e?.name === 'TimeoutError' ? 'timeout' : (e?.cause?.code || e?.message || String(e)); }
    if (attempt < 3) await sleep(attempt * 2000);
  }
  console.warn(`[webhook] ${ev.type} ${ev.id} FAILED: ${last}`);
  return { ok: false, error: last };
}
