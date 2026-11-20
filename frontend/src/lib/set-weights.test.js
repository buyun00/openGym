import { expect, it } from 'vitest'
import { buildCombinedEntries } from './session-merge.js'
import { editWorkoutSetPlan } from './routines.js'
import { convertStateUnit } from './units.js'
import { buildCompletedWorkout } from './finish-workout.js'
import { isWarmupRow, setSideField } from './workout-model.js'

const routine = { id: 'A', name: 'Bench', ex: [{ id: '0025', sets: 3, reps: 8, weight: 40, warmupSets: 1 }] }
const start = s => buildCombinedEntries(s, ['A']).entries
const weights = entry => entry.sets.filter(s => !isWarmupRow(s)).map(s => s.w)
function state(r = routine) {
  const s = { routines: [structuredClone(r)], workouts: [], exWeights: {}, unit: 'kg' }
  s.active = { id: 'work', start: 1, routineIds: ['A'], entries: start(s) }
  return s
}

it('retains edited work-set loads and count across a finish, progression and unit change', () => {
  const s = state(), slot = s.routines[0].ex[0]
  editWorkoutSetPlan(s, 0, e => { e.sets[0].w = 15 }) // warm-up
  expect(slot.setWeights).toBeUndefined()
  editWorkoutSetPlan(s, 0, e => { e.sets[2].w = 45 })
  editWorkoutSetPlan(s, 0, e => { e.sets[3].w = 50 })
  editWorkoutSetPlan(s, 0, e => { e.sets.push({ w: 0, r: 8, done: false }) })
  expect(slot).toMatchObject({ sets: 4, weight: 40, setWeights: [40, 45, 50, 0], warmupSets: 1 })
  s.active.entries[0].sets.forEach(row => { row.done = true })
  s.workouts.push(buildCompletedWorkout(s.active, { end: 100 }))
  expect(weights(start(s)[0])).toEqual([40, 45, 50, 0])
  expect(weights(start(convertStateUnit(s, 'lb'))[0])).toEqual([88, 99, 110, 0])
  editWorkoutSetPlan(s, 0, e => { e.sets.splice(2, 1) })
  expect(weights(start(s)[0])).toEqual([40, 50, 0])
})

it('follows a moved duplicate occurrence and leaves backfills and history edits alone', () => {
  const s = state({ ...routine, ex: [routine.ex[0], { ...routine.ex[0], weight: 20 }] })
  s.active.entries.reverse()
  const change = e => { e.sets.at(-1).w = 12.5 }
  editWorkoutSetPlan(s, 0, change)
  expect(s.routines[0].ex[0].setWeights).toBeUndefined()
  expect(s.routines[0].ex[1].setWeights).toEqual([20, 20, 12.5])
  for (const flag of ['backfill', 'editingWorkoutId']) {
    s.active[flag] = true
    editWorkoutSetPlan(s, 1, e => { e.sets.pop() })
    delete s.active[flag]
  }
  expect(s.routines[0].ex[0].sets).toBe(3)
  delete s.active.entries[1].sourceSlot
  editWorkoutSetPlan(s, 1, change)
  expect(s.routines[0].ex[0].setWeights).toBeUndefined()
})

it('keeps left and right loads together as one set for both reps and timed holds', () => {
  for (const mode of ['reps', 'time']) {
    const s = state({ ...routine, ex: [{ id: '0025', sets: 2, reps: 8, sec: 30, mode, side: true, weight: 5 }] })
    editWorkoutSetPlan(s, 0, e => {
      if (mode === 'time') e.sets[1].w = 7
      else e.sets[0] = setSideField(e.sets[0], 'R', 'w', 7)
    })
    expect(s.routines[0].ex[0]).toMatchObject({ sets: 2, setWeights: [[5, 7], 5] })
    const rows = start(s)[0].sets
    if (mode === 'time') expect(rows.map(row => row.w)).toEqual([5, 7, 5, 5])
    else expect(rows.map(row => [row.sides.L.w, row.sides.R.w])).toEqual([[5, 7], [5, 5]])
  }
})

it('a weight edit in an open session preserves other weights and extra sets just synced into the plan', () => {
  const s = state({ ...routine, ex: [{ ...routine.ex[0], warmupSets: 0, setWeights: [40, 45, 50] }] })
  const slot = s.routines[0].ex[0]
  Object.assign(slot, { sets: 4, setWeights: [40, 45, 55, 60] })
  editWorkoutSetPlan(s, 0, e => { e.sets[1].w = 47.5 })
  expect(weights(s.active.entries[0])).toEqual([40, 47.5, 50])
  expect(weights(start(s)[0])).toEqual([40, 47.5, 55, 60])
})
