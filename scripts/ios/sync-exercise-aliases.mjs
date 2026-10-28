// Keep native muscle lookups for drawing aliases in sync with the web catalogue.
import fs from 'node:fs'
import { EXALIAS } from '../../frontend/src/lib/exercises-data.js'

const file = new URL('../../frontend/ios/App/App/Native/exercises.json', import.meta.url)
const exercises = JSON.parse(fs.readFileSync(file, 'utf8'))
const byId = new Map(exercises.map(exercise => [exercise.id, exercise]))
for (const [alias, canonical] of Object.entries(EXALIAS)) {
  const source = byId.get(canonical)
  const target = byId.get(alias)
  if (!source || !target) throw new Error(`Missing native exercise for alias ${alias} -> ${canonical}`)
  if (process.argv.includes('--check') && JSON.stringify(target.muscles) !== JSON.stringify(source.muscles)) {
    throw new Error(`Native exercise alias ${alias} -> ${canonical} is out of date`)
  }
  target.muscles = source.muscles
}
if (!process.argv.includes('--check')) {
  fs.writeFileSync(file, JSON.stringify(exercises) + '\n')
}
