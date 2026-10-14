import { useLayoutEffect, useRef, useState } from 'react'
import { fmtNum, fmtDate, MONTHS } from '../lib/format.js'
import { t } from '../lib/i18n.js'

// Home weight card: body weight, lean mass (kg, left axis) and body fat (%, right axis) in one
// chart. series: [{ key, label, unit, color, axis: 'l' | 'r', points: [{ d, y }] }]. Scrubbing
// shows every series' value for the nearest date that has any reading.
const W = 340
const day = d => new Date(d + 'T12:00:00').getTime()
function scale(vals, extra) {
  const v = [...vals, ...(extra != null && isFinite(extra) ? [extra] : [])]
  let lo = Math.min(...v), hi = Math.max(...v)
  if (lo === hi) { lo -= 1; hi += 1 }
  const pad = (hi - lo) * 0.12
  return [lo - pad, hi + pad]
}
function ticksOf(lo, hi) {
  const raw = (hi - lo) / 3, pow = Math.pow(10, Math.floor(Math.log10(raw)))
  let step = 10 * pow
  for (const m of [1, 2, 2.5, 5, 10]) if (raw <= m * pow) { step = m * pow; break }
  const out = []
  for (let v0 = Math.ceil(lo / step) * step; v0 <= hi + 1e-9; v0 += step) out.push(Math.round(v0 / step) * step || 0)
  return out
}

export default function BodyChart({ series, h = 150, goal = null }) {
  const svgRef = useRef(null), wrapRef = useRef(null), tipRef = useRef(null)
  const [hover, setHover] = useState(null)
  useLayoutEffect(() => { setHover(null) }, [series])
  useLayoutEffect(() => {
    const tip = tipRef.current, wrap = wrapRef.current
    if (!hover || !tip || !wrap) return
    const cw = wrap.clientWidth, tw = tip.offsetWidth, cx = hover.x / W * cw
    tip.style.left = Math.max(4, Math.min(cw - tw - 4, cx - tw / 2)) + 'px'
    tip.style.top = '4px'
  })
  const live = series.filter(s => s.points.length)
  if (!live.length) return <div className="empty small">{t('No data yet')}</div>
  const H = h
  const hasR = live.some(s => s.axis === 'r'), hasL = live.some(s => s.axis !== 'r')
  const P = { l: hasL ? 34 : 8, r: hasR ? 30 : 12, t: 10, b: 22 }
  const all = live.flatMap(s => s.points.map(p => day(p.d)))
  const t0 = Math.min(...all), t1 = Math.max(...all)
  const X = tm => (t1 === t0 ? (P.l + W - P.r) / 2 : P.l + (tm - t0) / (t1 - t0) * (W - P.l - P.r))
  const [l0, l1] = hasL ? scale(live.filter(s => s.axis !== 'r').flatMap(s => s.points.map(p => p.y)), goal) : [0, 1]
  const [r0, r1] = hasR ? scale(live.filter(s => s.axis === 'r').flatMap(s => s.points.map(p => p.y))) : [0, 1]
  const Y = (y, axis) => {
    const [lo, hi] = axis === 'r' ? [r0, r1] : [l0, l1]
    return P.t + (1 - (y - lo) / (hi - lo)) * (H - P.t - P.b)
  }
  const grid = []
  if (hasL) ticksOf(l0, l1).forEach(v => grid.push(<g key={'l' + v}>
    <line x1={P.l} y1={Y(v, 'l')} x2={W - P.r} y2={Y(v, 'l')} stroke="var(--sep-op)" strokeWidth="1" strokeDasharray="2 4" />
    <text x={P.l - 5} y={Y(v, 'l') + 3.5} textAnchor="end" fontSize="9.5" fill="var(--label-2)">{fmtNum(v)}</text></g>))
  const rs = live.find(s => s.axis === 'r')
  if (hasR) ticksOf(r0, r1).forEach(v => grid.push(
    <text key={'r' + v} x={W - P.r + 4} y={Y(v, 'r') + 3.5} textAnchor="start" fontSize="9.5" fill={rs.color}>{fmtNum(v)}%</text>))
  const ticks = []
  const d0 = new Date(t0), d1 = new Date(t1)
  let m = new Date(d0.getFullYear(), d0.getMonth() + 1, 1)
  while (m <= d1) { ticks.push({ t: +m, txt: t(MONTHS[m.getMonth()]) }); m = new Date(m.getFullYear(), m.getMonth() + 1, 1) }
  if (!ticks.length && t1 > t0) for (let i = 0; i <= 2; i++) {
    const dd = new Date(t0 + (t1 - t0) * i / 2)
    ticks.push({ t: +dd, txt: dd.getDate() + ' ' + t(MONTHS[dd.getMonth()]), anchor: i === 0 ? 'start' : i === 2 ? 'end' : 'middle' })
  }
  ticks.forEach((tk, i) => grid.push(<g key={'x' + i}>
    <line x1={X(tk.t)} y1={P.t} x2={X(tk.t)} y2={H - P.b} stroke="var(--sep-op)" strokeWidth="1" strokeDasharray="2 4" />
    <text x={X(tk.t)} y={H - 7} textAnchor={tk.anchor || 'middle'} fontSize="9.5" fill="var(--label-2)">{tk.txt}</text></g>))
  const dates = [...new Set(live.flatMap(s => s.points.map(p => p.d)))].sort()
  const onMove = e => {
    const c = e.touches ? e.touches[0] : e
    if (!c || c.clientX === undefined) return
    const r = svgRef.current.getBoundingClientRect()
    const vx = (c.clientX - r.left) / (r.width || W) * W
    let best = dates[0]
    for (const d of dates) if (Math.abs(X(day(d)) - vx) < Math.abs(X(day(best)) - vx)) best = d
    setHover({ d: best, x: X(day(best)) })
  }
  return (
    <div className="chart-i" ref={wrapRef} onMouseMove={onMove} onMouseDown={onMove} onMouseLeave={() => setHover(null)}
      onTouchStart={onMove} onTouchMove={onMove}>
      <svg ref={svgRef} viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" style={{ aspectRatio: `${W}/${H}` }}>
        {grid}
        {goal != null && isFinite(goal) && hasL && <line x1={P.l} y1={Y(goal, 'l')} x2={W - P.r} y2={Y(goal, 'l')} stroke="var(--yellow)" strokeWidth="1.4" strokeDasharray="7 4" />}
        {live.map(s => <g key={s.key}>
          {s.points.length > 1 && <polyline points={s.points.map(p => X(day(p.d)).toFixed(1) + ',' + Y(p.y, s.axis).toFixed(1)).join(' ')}
            fill="none" stroke={s.color} strokeWidth="2.2" strokeLinejoin="round" strokeLinecap="round" />}
          {(() => { const p = s.points.at(-1); return <circle cx={X(day(p.d))} cy={Y(p.y, s.axis)} r="3.5" fill={s.color} /> })()}
        </g>)}
        {hover && <g>
          <line x1={hover.x} y1={P.t} x2={hover.x} y2={H - P.b} stroke="var(--label-3)" strokeWidth="1" strokeDasharray="3 3" />
          {live.map(s => s.points.filter(p => p.d === hover.d).map(p =>
            <circle key={s.key} cx={hover.x} cy={Y(p.y, s.axis)} r="4.5" fill={s.color} stroke="var(--bg)" strokeWidth="2" />))}
        </g>}
      </svg>
      {hover && <div className="ctip" ref={tipRef}>
        <div>{fmtDate(hover.d, true)}</div>
        {live.map(s => { const p = s.points.find(q => q.d === hover.d); return p ? <div key={s.key} style={{ color: s.color }}>{s.label} {fmtNum(p.y)}{s.unit === '%' ? '%' : ' ' + s.unit}</div> : null })}
      </div>}
    </div>
  )
}
