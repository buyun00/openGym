// Body-measurement webhook (local addition): lets one trusted client, e.g. an iPhone Shortcut,
// push a day's weight, lean body mass and body-fat % into one profile. Pure helpers here; the
// route in server.js does the locked read/stamp/write like PUT /api/data does.
export const LEAN_ID = 'hook-lean-mass-kg';
export const LEAN_NAME = '\u53bb\u8102\u4f53\u91cd (kg)';
const DEFAULT_KEYS = ['neck', 'shoulders', 'chest', 'waist', 'hips', 'upperArmLeft', 'upperArmRight',
  'forearmLeft', 'forearmRight', 'thighLeft', 'thighRight', 'calfLeft', 'calfRight'];
const ALL_KEYS = [...DEFAULT_KEYS, 'abdomen', 'wristLeft', 'wristRight', 'ankleLeft', 'ankleRight', 'bodyFat'];

// "87,4 kg" / "87.4" / 87.4 / "192 lb" -> { n, lb }
export function parseNum(v) {
  if (v == null || v === '') return null;
  if (typeof v === 'number') return Number.isFinite(v) ? { n: v, lb: false } : null;
  const s = String(v).trim();
  const m = /-?\d+(?:[.,]\d+)?/.exec(s.replace(/\s/g, ''));
  if (!m) return null;
  const n = parseFloat(m[0].replace(',', '.'));
  return Number.isFinite(n) ? { n, lb: /\b(lb|lbs|pound)|磅/i.test(s) } : null;
}
const r1 = n => Math.round(n * 10) / 10;
export function parseKg(v) {
  const p = parseNum(v); if (!p || p.n <= 0) return null;
  const kg = p.lb ? p.n * 0.45359237 : p.n;
  return kg > 0 && kg < 500 ? r1(kg) : null;
}
export function parsePct(v) {
  const p = parseNum(v); if (!p || p.n <= 0) return null;
  const pct = p.n <= 1 ? p.n * 100 : p.n;
  return pct > 0 && pct < 100 ? r1(pct) : null;
}
export function dayIn(ms, tz) {
  try {
    const f = new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' });
    return f.format(new Date(ms));
  } catch { return new Date(ms).toISOString().slice(0, 10); }
}
// 'YYYY-MM-DD', ISO datetime (zone-converted), '2026年10月15日 09:30', 'Oct 15, 2026 at 9:30'
export function parseDate(v, tz, now = Date.now()) {
  if (v == null || String(v).trim() === '') return dayIn(now, tz);
  const s = String(v).trim();
  let m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (m) return s;
  if (/^\d{4}-\d{2}-\d{2}T/.test(s) && /(Z|[+-]\d{2}:?\d{2})$/.test(s)) {
    const t = Date.parse(s); if (Number.isFinite(t)) return dayIn(t, tz);
  }
  m = /(\d{4})\D{1,3}(\d{1,2})\D{1,3}(\d{1,2})/.exec(s);
  if (m) return `${m[1]}-${m[2].padStart(2, '0')}-${m[3].padStart(2, '0')}`;
  const t = Date.parse(s.replace(/\bat\b/, ''));
  return Number.isFinite(t) ? dayIn(t, tz) : null;
}
const validDate = d => /^\d{4}-\d{2}-\d{2}$/.test(d) && !Number.isNaN(Date.parse(d + 'T12:00:00Z'));

// Apply to a CLONE of the state. Returns a summary. `del` removes that day's hook values.
// The entry time `t` is both the chart's x (weigh-in time) and the per-day sync stamp (later wins).
// It is the given day at 09:00 Asia/Shanghai; a re-post of a day that already has a stamp at or past
// that moves 1 ms past it, so the update still wins a merge without leaving its day.
export const dayStamp = (date, prevT) => {
  const base = Date.parse(date + 'T09:00:00+08:00');
  return Number(prevT) >= base ? Number(prevT) + 1 : base;
};

export function applyBody(S, { date, weight, lean, fat, del }, now = Date.now()) {
  if (!validDate(date)) throw Object.assign(new Error('invalid date'), { status: 400 });
  S.bodyweight = Array.isArray(S.bodyweight) ? S.bodyweight : [];
  S.measurements = Array.isArray(S.measurements) ? S.measurements : [];
  S.customMeasurements = Array.isArray(S.customMeasurements) ? S.customMeasurements : [];
  if (del) {
    const b = S.bodyweight.length, m = S.measurements.length;
    S.bodyweight = S.bodyweight.filter(e => e?.d !== date);
    S.measurements = S.measurements.filter(e => e?.d !== date);
    const [, mo, da] = date.split('-');
    return { date, deleted: { bodyweight: b - S.bodyweight.length, measurements: m - S.measurements.length }, message: `${+mo}月${+da}日 已删除` };
  }
  if (weight == null && lean == null && fat == null) throw Object.assign(new Error('no metric'), { status: 400 });
  const out = { date };
  // The previous record before this date, for the change shown in the message.
  const before = (arr, get) => [...arr].filter(e => e && String(e.d) < date && get(e) != null)
    .sort((a, b) => String(a.d).localeCompare(String(b.d))).map(get).at(-1) ?? null;
  const prevW = before(S.bodyweight, e => (Number(e.w) > 0 ? (S.unit === 'lb' ? r1(e.w * 0.45359237) : +e.w) : null));
  const prevF = before(S.measurements, e => (Number(e.bodyFat) > 0 ? +e.bodyFat : null));
  const prevL = before(S.measurements, e => { const v = (e.other || []).find(o => o?.id === LEAN_ID)?.value; return Number(v) > 0 ? +v : null; });
  if (weight != null) {
    const w = S.unit === 'lb' ? r1(weight / 0.45359237) : weight;
    const old = S.bodyweight.find(e => e?.d === date);
    const rest = S.bodyweight.filter(e => e?.d !== date);
    rest.push({ d: date, w, t: dayStamp(date, old?.t) });
    rest.sort((a, b) => String(a.d).localeCompare(String(b.d)));
    S.bodyweight = rest; out.weight_kg = weight;
  }
  if (lean != null || fat != null) {
    for (const c of S.customMeasurements) if (c?.id === LEAN_ID) c.name = LEAN_NAME;
    for (const e of S.measurements) for (const o of (e?.other || [])) if (o?.id === LEAN_ID) o.name = LEAN_NAME;
    if (lean != null && !S.customMeasurements.some(c => c?.id === LEAN_ID)) {
      S.customMeasurements.push({ id: LEAN_ID, name: LEAN_NAME, enabled: true });
    }
    if (fat != null) {
      const en = Array.isArray(S.measurementEnabled) ? S.measurementEnabled : DEFAULT_KEYS;
      if (!en.includes('bodyFat')) S.measurementEnabled = [...en, 'bodyFat'];
    }
    let e = S.measurements.find(x => x?.d === date);
    if (!e) {
      e = { d: date, t: dayStamp(date) }; for (const k of ALL_KEYS) e[k] = null;
      e.other = S.customMeasurements.map(c => ({ id: c.id, name: c.name, value: null }));
      S.measurements.push(e);
      S.measurements.sort((a, b) => String(a.d).localeCompare(String(b.d)));
    }
    else e.t = dayStamp(date, e.t);
    if (fat != null) { e.bodyFat = fat; out.body_fat_pct = fat; }
    if (lean != null) {
      e.other = Array.isArray(e.other) ? e.other : [];
      const o = e.other.find(x => x?.id === LEAN_ID);
      if (o) o.value = lean; else e.other.push({ id: LEAN_ID, name: LEAN_NAME, value: lean });
      out.lean_mass_kg = lean;
    }
  }
  const fx = n => r1(n).toFixed(1);
  const chg = (v, p) => (p == null ? '' : '（较上次 ' + (r1(v - p) > 0 ? '+' : r1(v - p) < 0 ? '-' : '±') + fx(Math.abs(v - p)) + '）');
  const [, mo, da] = date.split('-');
  const lines = [`${+mo}月${+da}日 已记录`];
  if (out.weight_kg != null) lines.push(`体重 ${fx(out.weight_kg)} kg${chg(out.weight_kg, prevW)}`);
  if (out.lean_mass_kg != null) lines.push(`去脂体重 ${fx(out.lean_mass_kg)} kg${chg(out.lean_mass_kg, prevL)}`);
  if (out.body_fat_pct != null) lines.push(`体脂率 ${fx(out.body_fat_pct)}%${chg(out.body_fat_pct, prevF)}`);
  for (const k of ['weight_kg', 'lean_mass_kg', 'body_fat_pct']) if (out[k] != null) out[k] = r1(out[k]);
  out.message = lines.join('\n');
  return out;
}

// ---- Daily health fields (sleep, resting HR, HRV, steps): kept in a sidecar file per user,
// health-<uid>.json = { "<date>": { sleep_hours, resting_hr, hrv_ms, steps, t } }.
const blank = v => v == null || (typeof v === 'string' && v.trim() === '') || (Array.isArray(v) && !v.length);
const numIn = s => { const m = /-?\d+(?:\.\d+)?/.exec(s); return m ? parseFloat(m[0]) : null; };
const decComma = s => String(s).trim().replace(/(\d),(\d{1,2})(?!\d)/g, '$1.$2');
// One sleep item -> { h } (unit known) or { raw } (unitless number).
function sleepItem(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? { raw: v } : null;
  const s = decComma(v).toLowerCase();
  if (!s) return null;
  let m = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(s);
  if (m) return { h: +m[1] + +m[2] / 60 + (+m[3] || 0) / 3600 };
  // "7 h 30 min", "7??30??", "450 min", "27000 s"
  let h = 0, hit = false;
  for (const [re, f] of [[/(\d+(?:\.\d+)?)\s*(h|hr|hrs|hour|hours|\u5c0f\u65f6|\u6642\u9593)/, 1], [/(\d+(?:\.\d+)?)\s*(m|min|mins|minute|minutes|\u5206\u949f|\u5206)(?![a-z])/, 1 / 60], [/(\d+(?:\.\d+)?)\s*(s|sec|secs|second|seconds|\u79d2)(?![a-z])/, 1 / 3600]]) {
    const x = re.exec(s); if (x) { h += parseFloat(x[1]) * f; hit = true; }
  }
  if (hit) return { h };
  const n = numIn(s);
  return n == null ? null : { raw: n };
}
const normHours = n => (n >= 1440 ? n / 3600 : n > 24 ? n / 60 : n);
export function parseSleep(v) {
  if (blank(v)) return null;
  const items = Array.isArray(v) ? v : typeof v === 'string' && /[\n;]/.test(v) ? v.split(/[\n;]+/) : [v];
  let h = 0, raw = 0, any = false, anyRaw = false;
  for (const it of items) {
    if (blank(it)) continue;
    const p = sleepItem(it); if (!p) continue;
    any = true;
    if (p.h != null) h += p.h; else { raw += p.raw; anyRaw = true; }
  }
  if (!any) return null;
  const total = h + (anyRaw ? normHours(raw) : 0);
  return total > 0 && total <= 24 ? r1(total) : null;
}
function intOf(v, lo, hi, thousands) {
  if (blank(v)) return null;
  let s = typeof v === 'number' ? String(v) : String(v).trim();
  s = thousands ? s.replace(/(\d)[,\s\u00a0'](?=\d{3}\b)/g, '$1') : decComma(s);
  const n = numIn(s);
  return n != null && n >= lo && n <= hi ? n : null;
}
export function parseHealth(b) {
  const out = {};
  const sl = parseSleep(b.sleep_hours ?? b.sleep); if (sl != null) out.sleep_hours = sl;
  const hr = intOf(b.resting_hr, 20, 250); if (hr != null) out.resting_hr = Math.round(hr);
  const hv = intOf(b.hrv_ms ?? b.hrv, 1, 1000); if (hv != null) out.hrv_ms = r1(hv);
  const st = intOf(b.steps, 0, 300000, true); if (st != null) out.steps = Math.round(st);
  return out;
}
export function healthLines(h) {
  const lines = [];
  if (h.sleep_hours != null) lines.push(`\u7761\u7720 ${r1(h.sleep_hours).toFixed(1)} h`);
  if (h.resting_hr != null) lines.push(`\u9759\u606f\u5fc3\u7387 ${h.resting_hr}`);
  if (h.hrv_ms != null) lines.push(`HRV ${Math.round(h.hrv_ms)} ms`);
  if (h.steps != null) lines.push(`\u6b65\u6570 ${h.steps.toLocaleString('en-US')}`);
  return lines;
}
export const dateLine = (date, verb = '\u5df2\u8bb0\u5f55') => { const [, mo, da] = date.split('-'); return `${+mo}\u6708${+da}\u65e5 ${verb}`; };
