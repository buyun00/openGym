import { isSideSet, isWarmupRow, syncSideAggregate, WEIGHT_ORIGIN_MANUAL } from './workout-model.js'

// One item per work set, including an explicit zero. A unilateral set can have two loads.
const pair = (left, right) => left === right ? left : [left, right]
export const hasSetWeights = cfg => Array.isArray(cfg?.setWeights) && cfg.setWeights.length > 0
export const scalarWeight = value => Array.isArray(value) ? Math.max(...value) : value
export const mapSetWeights = (weights, convert) => weights.map(w => Array.isArray(w) ? w.map(convert) : w == null ? w : convert(w))

export function weightsFromRows(rows) {
  const work = rows.filter(row => !isWarmupRow(row))
  const weights = []
  for (let i = 0; i < work.length; i++) {
    const row = work[i]
    if (isSideSet(row)) weights.push(pair(row.sides.L.w ?? 0, row.sides.R.w ?? 0))
    else if (row.side === 'L' && work[i + 1]?.side === 'R') weights.push(pair(row.w ?? 0, work[++i].w ?? 0))
    else weights.push(row.w ?? 0)
  }
  return weights
}

export function applySetWeights(rows, weights, fallback) {
  const individual = weights.some(w => Array.isArray(w) || w !== weights[0])
  const withWeight = (row, weight) => Number.isFinite(weight) && weight >= 0
    ? { ...row, w: weight, ...(individual ? { weightOrigin: WEIGHT_ORIGIN_MANUAL } : {}) } : row
  let i = 0
  return rows.map(row => {
    const w = weights[i] ?? fallback
    if (row.side !== 'L') i++
    if (isSideSet(row)) return syncSideAggregate({ ...row, sides: {
      L: withWeight(row.sides.L, Array.isArray(w) ? w[0] : w),
      R: withWeight(row.sides.R, Array.isArray(w) ? w[1] : w),
    } })
    return withWeight(row, Array.isArray(w) ? w[row.side === 'R' ? 1 : 0] : w)
  })
}
