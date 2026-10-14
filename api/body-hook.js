// Body-measurement webhook (local addition): lets one trusted client, e.g. an iPhone Shortcut,
// push a day's weight, lean body mass and body-fat % into one profile. Pure helpers here; the
// route in server.js does the locked read/stamp/write like PUT /api/data does.
export const LEAN_ID = 'hook-lean-mass-kg';
export const LEAN_NAME = '瘦体重 (kg)';
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
export function applyBody(S, { date, weight, lean, fat, del }, now = Date.now()) {
  if (!validDate(date)) throw Object.assign(new Error('invalid date'), { status: 400 });
  S.bodyweight = Array.isArray(S.bodyweight) ? S.bodyweight : [];
  S.measurements = Array.isArray(S.measurements) ? S.measurements : [];
  S.customMeasurements = Array.isArray(S.customMeasurements) ? S.customMeasurements : [];
  if (del) {
    const b = S.bodyweight.length, m = S.measurements.length;
    S.bodyweight = S.bodyweight.filter(e => e?.d !== date);
    S.measurements = S.measurements.filter(e => e?.d !== date);
    return { date, deleted: { bodyweight: b - S.bodyweight.length, measurements: m - S.measurements.length } };
  }
  if (weight == null && lean == null && fat == null) throw Object.assign(new Error('no metric'), { status: 400 });
  const out = { date };
  if (weight != null) {
    const w = S.unit === 'lb' ? r1(weight / 0.45359237) : weight;
    const rest = S.bodyweight.filter(e => e?.d !== date);
    rest.push({ d: date, w, t: now });
    rest.sort((a, b) => String(a.d).localeCompare(String(b.d)));
    S.bodyweight = rest; out.weight_kg = weight;
  }
  if (lean != null || fat != null) {
    if (lean != null && !S.customMeasurements.some(c => c?.id === LEAN_ID)) {
      S.customMeasurements.push({ id: LEAN_ID, name: LEAN_NAME, enabled: true });
    }
    if (fat != null) {
      const en = Array.isArray(S.measurementEnabled) ? S.measurementEnabled : DEFAULT_KEYS;
      if (!en.includes('bodyFat')) S.measurementEnabled = [...en, 'bodyFat'];
    }
    let e = S.measurements.find(x => x?.d === date);
    if (!e) {
      e = { d: date, t: now }; for (const k of ALL_KEYS) e[k] = null;
      e.other = S.customMeasurements.map(c => ({ id: c.id, name: c.name, value: null }));
      S.measurements.push(e);
      S.measurements.sort((a, b) => String(a.d).localeCompare(String(b.d)));
    }
    e.t = now;
    if (fat != null) { e.bodyFat = fat; out.body_fat_pct = fat; }
    if (lean != null) {
      e.other = Array.isArray(e.other) ? e.other : [];
      const o = e.other.find(x => x?.id === LEAN_ID);
      if (o) o.value = lean; else e.other.push({ id: LEAN_ID, name: LEAN_NAME, value: lean });
      out.lean_mass_kg = lean;
    }
  }
  return out;
}
