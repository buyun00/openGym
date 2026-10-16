// Gym equipment library helpers (views/Equipment.jsx; api/equipment.js stores the same shape).
import { EXDB, EXIDX } from './exercises.js'
import { exerciseNameFor } from './i18n-core.js'

export const EQUIP_GROUPS = [
  { key: 'chest', label: 'Chest' }, { key: 'back', label: 'Back' }, { key: 'legs', label: 'Legs' },
  { key: 'shoulders', label: 'Shoulders' }, { key: 'arms', label: 'Arms' }, { key: 'core', label: 'Core' },
]
export const equipItems = S => (Array.isArray(S?.gymEquipment) ? S.gymEquipment.filter(x => x && x.id) : [])
export const itemGroups = it => [...(it.primary || []), ...(it.secondary || [])]

// A free-text exercise name (what a bot sent) -> a catalogue id, by exact name in English or in
// the app's language, case- and space-insensitive. Unmatched names stay text on the item.
const norm = s => String(s || '').toLowerCase().replace(/[\s()（）_-]+/g, '')
let byName = null
export function exIdForName(name) {
  if (!byName) {
    byName = new Map()
    for (const e of EXDB) { byName.set(norm(e.n), e.id); const z = exerciseNameFor(e); if (z) byName.set(norm(z), e.id) }
  }
  return byName.get(norm(name)) || null
}
// Every exercise id the library supports: linked ids plus names that resolve to one.
export function equipExIds(S) {
  const out = new Set()
  for (const it of equipItems(S)) {
    for (const id of it.exIds || []) if (EXIDX[id] || (S.customEx || []).some(c => c.id === id)) out.add(id)
    for (const n of it.exNames || []) { const id = exIdForName(n); if (id) out.add(id) }
  }
  return out
}
// Stable: library exercises first, the rest keeps its order.
export const sortMineFirst = (list, mine) => (mine.size ? [...list].sort((a, b) => (mine.has(b.id) ? 1 : 0) - (mine.has(a.id) ? 1 : 0)) : list)

// Downscale a picked photo to a JPEG data URL (long side <= max px) before upload.
export function shrinkPhoto(file, max = 1280, q = 0.85) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      const k = Math.min(1, max / Math.max(img.width, img.height))
      const c = document.createElement('canvas')
      c.width = Math.round(img.width * k); c.height = Math.round(img.height * k)
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height)
      URL.revokeObjectURL(url)
      resolve(c.toDataURL('image/jpeg', q))
    }
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('image')) }
    img.src = url
  })
}