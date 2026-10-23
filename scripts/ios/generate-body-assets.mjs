// Reuse the project's licensed anatomy geometry as Xcode vector template images.
// No rasterization, hand-drawn controls or runtime SVG/WebView dependency.
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { resolve, dirname } from 'node:path'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const source = readFileSync(resolve(root, 'frontend/src/lib/body-paths.js'), 'utf8')
const paths = JSON.parse(source.slice(source.indexOf('export default ') + 15).trim().replace(/;$/, ''))
const muscles = ['trapezius', 'deltoids', 'chest', 'upper-back', 'serratus', 'biceps', 'triceps', 'forearm',
  'abs', 'obliques', 'lower-back', 'gluteal', 'quadriceps', 'hamstring', 'adductors', 'hip-flexors', 'calves', 'tibialis']
const assets = resolve(root, 'frontend/ios/App/App/Assets.xcassets/BodyMap')
mkdirSync(assets, { recursive: true })
writeFileSync(resolve(assets, 'Contents.json'), JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2) + '\n')
let count = 0
for (const side of ['front', 'back']) {
  const view = paths.male[side]
  const [, , width, height] = view.vb.split(' ').map(Number)
  const silhouette = Object.entries(view.p).filter(([key]) => !muscles.includes(key)).flatMap(([, values]) => values)
  for (const name of ['silhouette', ...muscles]) {
    const geometry = name === 'silhouette' ? silhouette : view.p[name] || []
    const assetName = `BodyMap-${side}-${name}`
    const folder = resolve(assets, assetName + '.imageset')
    mkdirSync(folder, { recursive: true })
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="${view.vb}">\n` +
      geometry.map(d => `  <path d="${d}" fill="#000000"/>`).join('\n') + '\n</svg>\n'
    writeFileSync(resolve(folder, assetName + '.svg'), svg)
    writeFileSync(resolve(folder, 'Contents.json'), JSON.stringify({
      images: [{ filename: assetName + '.svg', idiom: 'universal' }],
      info: { author: 'xcode', version: 1 },
      properties: { 'preserves-vector-representation': true, 'template-rendering-intent': 'template' }
    }, null, 2) + '\n')
    count++
  }
}
const notice = readFileSync(resolve(root, 'NOTICE.md'), 'utf8').split('## Body diagram geometry')[1].split('## Exercise media')[0]
writeFileSync(resolve(root, 'frontend/ios/App/App/Native/BodyMapNotices.txt'),
  'Body diagram geometry\n\n' + notice.trim() + '\n\nThe iOS app splits the same paths into per-muscle SVG template images in Assets.xcassets.\n')
console.log(`Generated ${count} native vector template assets and bundled attribution.`)
