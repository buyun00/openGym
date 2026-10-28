// Native training metadata uses the same catalogue IDs, translations and incline rule as web.
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { EXDB, EXALIAS } from '../../frontend/src/lib/exercises-data.js'
import { inclineFits } from '../../frontend/src/lib/incline.js'
import './sync-exercise-aliases.mjs'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const zh = JSON.parse(fs.readFileSync(path.join(root, 'catalogue/i18n/zh.json'), 'utf8'))
const records = {}
for (const ex of EXDB) {
  const sourcePath = path.join(root, 'catalogue/exercises', `${ex.id}.json`)
  const source = fs.existsSync(sourcePath) ? JSON.parse(fs.readFileSync(sourcePath, 'utf8')) : {}
  records[ex.id] = {
    name: zh[ex.id]?.name || ex.n, englishName: ex.n,
    mode: ex.bp === 'cardio' ? 'cardio' : 'reps',
    equipment: ex.eq, bodyPart: ex.bp,
    instructions: zh[ex.id]?.instructions || source.instructions || [],
    target: ex.tg === 'cardiovascular system' ? '心血管系统' : '',
    incline: inclineFits(ex),
    ...(fs.existsSync(path.join(root, 'catalogue/media/clip', ex.gif)) ? { clip: ex.gif } : {}),
    ...(fs.existsSync(path.join(root, 'catalogue/media/still', ex.img)) ? { still: ex.img } : {}),
  }
}
for (const [alias, canonical] of Object.entries(EXALIAS)) if (records[canonical]) records[alias] = records[canonical]
const output = path.join(root, 'frontend/ios/App/App/Native/workout-catalogue.json')
fs.writeFileSync(output, JSON.stringify(records) + '\n')
console.log(`Native workout metadata: ${Object.keys(records).length} IDs, including aliases`)
