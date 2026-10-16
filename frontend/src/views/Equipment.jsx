import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { t } from '../lib/i18n.js'
import { uid } from '../lib/format.js'
import { api, appBase } from '../lib/api.js'
import { EXIDX, searchExercises } from '../lib/exercises.js'
import { exerciseNameFor } from '../lib/i18n-core.js'
import { EQUIP_GROUPS, equipItems, itemGroups, exIdForName, shrinkPhoto } from '../lib/gym-equipment.js'
import { confirmSheet } from '../sheets.jsx'
import Icon from '../components/Icon.jsx'
import { Button, TextField, TextArea } from '../components/ui.jsx'
import { tappable } from '../lib/use-sheet-keyboard.js'

// Gym equipment library (器材库): what your gym has, by muscle group, each with the exercises it
// supports, a photo and your settings. Stored in S.gymEquipment and synced like gym cards; the
// exercise picker puts these exercises first ("In my gym").
const update = fn => useStore.getState().update(fn)
const toast = m => useUI.getState().toast(m)
const groupLabel = k => t(EQUIP_GROUPS.find(g => g.key === k)?.label || k)
export const photoUrl = f => appBase().replace(/\/$/, '') + '/api/equipment/photo?f=' + encodeURIComponent(f)

function exLabel(id) { const e = EXIDX[id]; return e ? exerciseNameFor(e) : id }

function EquipEdit({ item, close }) {
  const [name, setName] = useState(item?.name || '')
  const [primary, setPrimary] = useState(item?.primary || [])
  const [secondary, setSecondary] = useState(item?.secondary || [])
  const [exIds, setExIds] = useState(() => {
    const ids = [...(item?.exIds || [])]
    for (const n of item?.exNames || []) { const id = exIdForName(n); if (id && !ids.includes(id)) ids.push(id) }
    return ids
  })
  const [exNames, setExNames] = useState(() => (item?.exNames || []).filter(n => !exIdForName(n)))
  const [note, setNote] = useState(item?.note || '')
  const [location, setLocation] = useState(item?.location || '')
  const [photo, setPhoto] = useState(item?.photo || null)
  const [busy, setBusy] = useState(false)
  const [q, setQ] = useState('')
  const hits = useMemo(() => (q.trim() ? searchExercises(Object.values(EXIDX), q).slice(0, 8) : []), [q])
  const cycle = k => {
    // tap: none -> primary -> secondary -> none
    if (primary.includes(k)) { setPrimary(primary.filter(x => x !== k)); setSecondary([...secondary, k]) }
    else if (secondary.includes(k)) setSecondary(secondary.filter(x => x !== k))
    else setPrimary([...primary, k])
  }
  const pick = async e => {
    const file = e.target.files?.[0]; if (!file) return
    setBusy(true)
    try {
      const data = await shrinkPhoto(file)
      const r = await api('/api/equipment/photo', { method: 'POST', body: JSON.stringify({ data }) })
      setPhoto(r.photo)
    } catch { toast(t('Photo upload failed')) } finally { setBusy(false); e.target.value = '' }
  }
  const save = () => {
    if (!name.trim()) { toast(t('Enter a name')); return }
    if (!primary.length && !secondary.length) { toast(t('Choose at least one muscle group')); return }
    update(s => {
      if (!Array.isArray(s.gymEquipment)) s.gymEquipment = []
      const now = Date.now()
      const next = { ...(item || {}), id: item?.id || 'eq' + uid(), name: name.trim(), primary, secondary, exIds, exNames, note: note.trim(), location: location.trim(), photo, _ts: now, created: item?.created || now }
      const i = s.gymEquipment.findIndex(x => x.id === next.id)
      if (i >= 0) s.gymEquipment[i] = next; else s.gymEquipment.push(next)
    })
    close()
  }
  const del = () => confirmSheet({
    title: t('Delete equipment?'), message: item.name, confirmText: t('Delete'), danger: true,
    onConfirm: () => { update(s => { s.gymEquipment = (s.gymEquipment || []).filter(x => x.id !== item.id) }); close() },
  })
  return <div>
    <h3 style={{ marginBottom: 12 }}>{item ? t('Edit equipment') : t('Add equipment')}</h3>
    <div className="small dim" style={{ marginBottom: 4 }}>{t('Name')}</div>
    <TextField value={name} onChange={e => setName(e.target.value)} placeholder={t('e.g. Cable crossover')} />
    <div className="small dim" style={{ margin: '12px 0 4px' }}>{t('Muscle groups (tap: primary, again: secondary)')}</div>
    <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
      {EQUIP_GROUPS.map(g => <Button key={g.key} size="sm" variant={primary.includes(g.key) ? 'primary' : secondary.includes(g.key) ? 'tinted' : 'plain'} onClick={() => cycle(g.key)}>
        {t(g.label)}{primary.includes(g.key) ? ' \u2605' : secondary.includes(g.key) ? ' \u00b7' : ''}</Button>)}
    </div>
    <div className="small dim" style={{ margin: '12px 0 4px' }}>{t('Exercises')}</div>
    <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
      {exIds.map(id => <span key={id} className="tag acc" {...tappable(() => setExIds(exIds.filter(x => x !== id)))}>{exLabel(id)}{' \u00d7'}</span>)}
      {exNames.map(n => <span key={n} className="tag" {...tappable(() => setExNames(exNames.filter(x => x !== n)))}>{n}{' \u00d7'}</span>)}
    </div>
    <TextField value={q} onChange={e => setQ(e.target.value)} placeholder={t('Search exercises to link')} style={{ marginTop: 6 }} />
    {hits.length > 0 && <div className="list" style={{ marginTop: 4 }}>{hits.map(e => <div key={e.id} className="item" {...tappable(() => { if (!exIds.includes(e.id)) setExIds([...exIds, e.id]); setQ('') })}>
      <div className="grow"><div className="tt">{exerciseNameFor(e)}</div><div className="ss">{t(e.eq)}</div></div><Icon name="plus" /></div>)}</div>}
    <div className="small dim" style={{ margin: '12px 0 4px' }}>{t('Photo')}</div>
    <div className="row" style={{ gap: 10, alignItems: 'center' }}>
      {photo && <img src={photoUrl(photo)} alt="" style={{ width: 96, height: 96, objectFit: 'cover', borderRadius: 12 }} />}
      <label className="btn sm tinted" style={{ cursor: 'pointer' }}>{busy ? t('Uploading\u2026') : photo ? t('Change photo') : t('Add photo')}
        <input type="file" accept="image/*" onChange={pick} style={{ display: 'none' }} /></label>
      {photo && <Button size="sm" variant="ghost" onClick={() => setPhoto(null)}>{t('Remove')}</Button>}
    </div>
    <div className="small dim" style={{ margin: '12px 0 4px' }}>{t('Notes (seat, pin, settings)')}</div>
    <TextArea value={note} onChange={e => setNote(e.target.value)} rows={3} />
    <div className="small dim" style={{ margin: '12px 0 4px' }}>{t('Location in the gym')}</div>
    <TextField value={location} onChange={e => setLocation(e.target.value)} />
    <div className="row" style={{ gap: 8, marginTop: 16 }}>
      {item && <Button variant="ghost" className="danger" onClick={del}>{t('Delete')}</Button>}
      <div className="grow" />
      <Button onClick={close}>{t('Cancel')}</Button>
      <Button variant="primary" onClick={save} disabled={busy}>{t('Save')}</Button>
    </div>
  </div>
}
export const equipEditSheet = item => useUI.getState().openSheet(close => <EquipEdit item={item} close={close} />)

export default function Equipment() {
  const nav = useNavigate()
  const S = useStore(s => s.S)
  const [group, setGroup] = useState('')
  const items = equipItems(S)
  const shown = group ? items.filter(it => itemGroups(it).includes(group)) : items
  const byGroup = group ? [[group, shown]] : EQUIP_GROUPS.map(g => [g.key, items.filter(it => (it.primary || [])[0] === g.key || (!(it.primary || []).length && (it.secondary || [])[0] === g.key))]).filter(([, l]) => l.length)
  return <div className="narrow">
    <div className="hdr">
      <button className="iconbtn" onClick={() => nav('/library')} aria-label={t('Exercises')}><Icon name="chevronLeft" /></button>
      <div style={{ flex: 1, marginLeft: 10 }}><h1>{t('Equipment')}</h1><div className="sub">{t('{0} items in your gym', items.length)}</div></div>
      <button className="iconbtn" onClick={() => equipEditSheet(null)} aria-label={t('Add equipment')}><Icon name="plus" /></button>
    </div>
    <div className="row" style={{ gap: 6, flexWrap: 'wrap', marginBottom: 12 }}>
      <Button size="sm" variant={!group ? 'primary' : 'plain'} onClick={() => setGroup('')}>{t('All')}</Button>
      {EQUIP_GROUPS.map(g => <Button key={g.key} size="sm" variant={group === g.key ? 'primary' : 'plain'} onClick={() => setGroup(g.key)}>
        {t(g.label)} {items.filter(it => itemGroups(it).includes(g.key)).length || ''}</Button>)}
    </div>
    {!items.length && <div className="card muted small">{t('No equipment yet. Add what your gym has, and the exercise picker will show those exercises first.')}</div>}
    {byGroup.map(([g, list]) => <div key={g}>
      {!group && <h3 style={{ margin: '14px 4px 6px' }}>{groupLabel(g)}</h3>}
      {list.map(it => <div key={it.id} className="card tappable" style={{ cursor: 'pointer', display: 'flex', gap: 12 }} {...tappable(() => equipEditSheet(it))}>
        {it.photo ? <img src={photoUrl(it.photo)} alt="" style={{ width: 64, height: 64, objectFit: 'cover', borderRadius: 10, flex: 'none' }} />
          : <div style={{ width: 64, height: 64, borderRadius: 10, background: 'var(--fill, rgba(127,127,127,.12))', display: 'grid', placeItems: 'center', flex: 'none' }}><Icon name="dumbbell" /></div>}
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ fontWeight: 600 }}>{it.name}</div>
          <div className="small muted">{(it.primary || []).map(groupLabel).join(' / ')}{(it.secondary || []).length ? ' \u00b7 ' + (it.secondary || []).map(groupLabel).join(' / ') : ''}{it.location ? ' \u00b7 ' + it.location : ''}</div>
          <div className="small dim" style={{ marginTop: 2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {[...(it.exIds || []).map(exLabel), ...(it.exNames || [])].join('\u3001')}</div>
          {it.note && <div className="small" style={{ marginTop: 2 }}>{it.note}</div>}
        </div>
      </div>)}
    </div>)}
  </div>
}