// Gym equipment library (local addition). Items live in the user's state as `gymEquipment`, a
// list synced like gymCards (sync-merge.js / sync-stamps.js), so the app and the API see the
// same thing. Photos are files in DATA/equipment-photos, named by content hash.
import crypto from 'node:crypto';

export const GROUPS = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
const ALIAS = [
  ['chest', /^(chest|pecs?|pectorals?|胸|胸部|胸肌|上胸|下胸)$/],
  ['back', /^(back|lats?|upper back|lower back|背|背部|背阔肌|上背|下背|斜方肌|traps?)$/],
  ['legs', /^(legs?|quads?|quadriceps|hamstrings?|glutes?|calves|calf|腿|腿部|臀|臀部|股四头肌|腘绳肌|小腿)$/],
  ['shoulders', /^(shoulders?|delts?|deltoids?|front delts?|rear delts?|side delts?|肩|肩部|三角肌|前束|后束|中束|前三角肌|后三角肌)$/],
  ['arms', /^(arms?|biceps?|triceps?|forearms?|手臂|臂|二头|二头肌|三头|三头肌|前臂)$/],
  ['core', /^(core|abs?|abdominals?|obliques?|waist|核心|腹|腹部|腹肌|腹斜肌)$/],
];
export function groupOf(v) {
  const s = String(v ?? '').trim().toLowerCase();
  if (!s) return null;
  if (GROUPS.includes(s)) return s;
  return ALIAS.find(([, re]) => re.test(s))?.[0] || null;
}
const str = (v, n) => (v == null ? '' : String(v).trim().slice(0, n));
const listOf = v => (Array.isArray(v) ? v : typeof v === 'string' ? v.split(/[\n,，、;；]+/) : []);
const uniq = a => [...new Set(a)];
export const newId = () => 'eq' + crypto.randomBytes(6).toString('hex');

// One item from loose input (the hook, the CRUD API). `prev` is the stored item being updated:
// a field the input leaves out keeps its stored value.
export function normalizeItem(raw = {}, prev = null, now = Date.now()) {
  const p = prev || {};
  const has = k => raw[k] !== undefined;
  const pick = (keys, fallback) => { for (const k of keys) if (has(k)) return raw[k]; return fallback; };
  const primary = uniq(listOf(pick(['primary', 'primary_muscles'], raw.muscles?.primary ?? p.primary)).map(groupOf).filter(Boolean));
  const secondary = uniq(listOf(pick(['secondary', 'secondary_muscles'], raw.muscles?.secondary ?? p.secondary)).map(groupOf).filter(Boolean)).filter(g => !primary.includes(g));
  const item = {
    id: p.id || str(raw.id, 40) || newId(),
    name: str(pick(['name'], p.name), 80),
    primary, secondary,
    exIds: uniq(listOf(pick(['exIds', 'exercise_ids'], p.exIds)).map(x => str(x, 40)).filter(Boolean)).slice(0, 60),
    exNames: uniq(listOf(pick(['exNames', 'exercises'], p.exNames)).map(x => str(x, 80)).filter(Boolean)).slice(0, 60),
    note: str(pick(['note', 'notes'], p.note), 1000),
    location: str(pick(['location'], p.location), 120),
    photo: pick(['photo'], p.photo ?? null) || null,
    _ts: now,
  };
  if (item.photo && !/^[0-9a-f]{64}\.(jpg|png|webp)$/.test(item.photo)) item.photo = p.photo || null;
  if (p.created) item.created = p.created; else item.created = now;
  return item;
}

// Upsert into S.gymEquipment by id, else by exact (case-insensitive) name. Returns the item.
export function upsert(S, raw, now = Date.now()) {
  S.gymEquipment = Array.isArray(S.gymEquipment) ? S.gymEquipment.filter(x => x && x.id) : [];
  const name = str(raw.name, 80).toLowerCase();
  const prev = (raw.id && S.gymEquipment.find(x => x.id === raw.id)) || (name && S.gymEquipment.find(x => String(x.name).toLowerCase() === name)) || null;
  const item = normalizeItem(raw, prev, now);
  if (!item.name) throw Object.assign(new Error('name required'), { status: 400 });
  if (!item.primary.length && !item.secondary.length) throw Object.assign(new Error('at least one muscle group (chest/back/legs/shoulders/arms/core or 胸/背/腿/肩/手臂/核心)'), { status: 400 });
  if (prev) S.gymEquipment = S.gymEquipment.map(x => (x.id === prev.id ? item : x));
  else S.gymEquipment.push(item);
  return { item, created: !prev };
}
export function remove(S, { id, name }) {
  const before = (S.gymEquipment || []).length;
  const n = str(name, 80).toLowerCase();
  S.gymEquipment = (S.gymEquipment || []).filter(x => !(x && ((id && x.id === id) || (!id && n && String(x.name).toLowerCase() === n))));
  return before - S.gymEquipment.length;
}

// Photo upload: base64 or data URL, jpeg/png/webp checked by magic bytes.
export function decodePhoto(data) {
  const m = /^data:image\/[a-z+]+;base64,(.*)$/s.exec(String(data || ''));
  const buf = Buffer.from(m ? m[1] : String(data || ''), 'base64');
  if (buf.length < 100) throw Object.assign(new Error('photo too small or not base64'), { status: 400 });
  const ext = buf[0] === 0xff && buf[1] === 0xd8 ? 'jpg' : buf.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) ? 'png'
    : buf.slice(0, 4).toString() === 'RIFF' && buf.slice(8, 12).toString() === 'WEBP' ? 'webp' : null;
  if (!ext) throw Object.assign(new Error('photo must be jpeg, png or webp'), { status: 400 });
  return { buf, name: crypto.createHash('sha256').update(buf).digest('hex') + '.' + ext, ext };
}
export const PHOTO_RE = /^[0-9a-f]{64}\.(jpg|png|webp)$/;