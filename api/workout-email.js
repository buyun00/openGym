// Email delivery of workout events (local addition). Minimal SMTP client, no dependency:
// direct to the recipient domain's MX on port 25 (STARTTLS when offered), or through a relay when
// SMTP_HOST is set (SMTP_PORT, SMTP_SECURE=1 for implicit TLS, SMTP_USER/SMTP_PASS -> AUTH LOGIN).
import net from 'node:net';
import tls from 'node:tls';
import dns from 'node:dns/promises';
import os from 'node:os';

export function emailConfig() {
  const e = process.env;
  return {
    to: (e.WORKOUT_EMAIL_TO || '').trim(),
    from: (e.WORKOUT_EMAIL_FROM || e.SMTP_FROM || 'opengym@localhost').trim(),
    host: (e.SMTP_HOST || '').trim(), port: +(e.SMTP_PORT || 0) || null,
    secure: /^(1|true|yes|on)$/i.test(e.SMTP_SECURE || ''),
    user: e.SMTP_USER || '', pass: e.SMTP_PASS || '',
    helo: (e.SMTP_HELO || '').trim() || (String(e.WORKOUT_EMAIL_FROM || '').split('@')[1] || os.hostname()),
  };
}

function session(sock) {
  let buf = '', waiters = [];
  const onData = d => {
    buf += d.toString('utf8');
    for (;;) {
      // A full reply ends with a line "NNN text" (space, not dash).
      const m = /(^|\r\n)(\d{3}) [^\r\n]*\r\n/.exec(buf);
      if (!m) break;
      const end = m.index + m[0].length, text = buf.slice(0, end).trim();
      buf = buf.slice(end);
      const w = waiters.shift(); if (w) w.resolve({ code: +m[2], text });
    }
  };
  const onErr = e => { while (waiters.length) waiters.shift().reject(e); };
  sock.on('data', onData); sock.on('error', onErr); sock.on('close', () => onErr(new Error('connection closed')));
  return {
    read: () => new Promise((resolve, reject) => waiters.push({ resolve, reject })),
    detach: () => { sock.off('data', onData); sock.removeAllListeners('error'); sock.removeAllListeners('close'); },
  };
}
const dotStuff = s => s.replace(/\r?\n/g, '\r\n').replace(/^\./gm, '..');

export async function sendMail({ to, subject, text, headers = {} }) {
  const c = emailConfig();
  let host = c.host, port = c.port || (c.host ? (c.secure ? 465 : 587) : 25);
  if (!host) {
    const domain = to.split('@')[1];
    const mx = (await dns.resolveMx(domain)).sort((a, b) => a.priority - b.priority);
    host = mx[0]?.exchange || domain;
  }
  const msgId = `<${Date.now().toString(36)}.${Math.random().toString(36).slice(2)}@${c.helo}>`;
  let sock = await new Promise((res, rej) => {
    const s = c.secure ? tls.connect({ host, port, servername: host }, () => res(s)) : net.connect({ host, port }, () => res(s));
    s.setTimeout(20000, () => s.destroy(new Error('smtp timeout')));
    s.once('error', rej);
  });
  let S = session(sock);
  const cmd = async (line, ok) => {
    if (line != null) sock.write(line + '\r\n');
    const r = await S.read();
    if (!ok.includes(Math.floor(r.code / 100) * 100) && !ok.includes(r.code)) throw new Error(`SMTP ${line ? line.split(' ')[0] : 'greeting'}: ${r.text}`);
    return r;
  };
  try {
    await cmd(null, [220]);
    let ehlo = await cmd('EHLO ' + c.helo, [250]);
    if (!c.secure && /STARTTLS/i.test(ehlo.text)) {
      await cmd('STARTTLS', [220]);
      S.detach();
      sock = await new Promise((res, rej) => { const s = tls.connect({ socket: sock, servername: host, rejectUnauthorized: !!c.host }, () => res(s)); s.once('error', rej); });
      sock.setTimeout(20000, () => sock.destroy(new Error('smtp timeout')));
      S = session(sock);
      ehlo = await cmd('EHLO ' + c.helo, [250]);
    }
    if (c.user) {
      await cmd('AUTH LOGIN', [334]);
      await cmd(Buffer.from(c.user).toString('base64'), [334]);
      await cmd(Buffer.from(c.pass).toString('base64'), [235]);
    }
    await cmd(`MAIL FROM:<${c.from}>`, [250]);
    await cmd(`RCPT TO:<${to}>`, [250]);
    await cmd('DATA', [354]);
    const hdr = {
      From: `openGym <${c.from}>`, To: to, Subject: subject, Date: new Date().toUTCString().replace('GMT', '+0000'),
      'Message-ID': msgId, 'MIME-Version': '1.0', 'Content-Type': 'text/plain; charset=utf-8', 'Content-Transfer-Encoding': '8bit', ...headers,
    };
    const head = Object.entries(hdr).map(([k, v]) => `${k}: ${String(v).replace(/[\r\n]+/g, ' ')}`).join('\r\n');
    const r = await cmd(head + '\r\n\r\n' + dotStuff(text) + '\r\n.', [250]);
    try { sock.write('QUIT\r\n'); } catch { /* closing anyway */ }
    return { ok: true, host, port, messageId: msgId, response: r.text };
  } finally { setTimeout(() => sock.destroy(), 1000).unref?.(); }
}

export async function emailEvent(ev) {
  const c = emailConfig();
  if (!c.to) return { skipped: true };
  try {
    const r = await sendMail({
      to: c.to, subject: 'openGym ' + ev.type,
      text: JSON.stringify(ev, null, 2) + '\n',
      headers: { 'X-OpenGym-Event': ev.type, 'X-OpenGym-Event-Id': ev.id },
    });
    console.log(`[email] ${ev.type} ${ev.id} -> ${r.host}:${r.port} ${r.messageId} ${r.response}`);
    return r;
  } catch (e) {
    console.warn(`[email] ${ev.type} ${ev.id} FAILED: ${e.message}`);
    return { ok: false, error: e.message };
  }
}
