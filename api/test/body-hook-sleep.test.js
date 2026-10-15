import test from 'node:test';
import assert from 'node:assert/strict';
import { parseSleep, parseHealth } from '../body-hook.js';

const cases = [
  ['7.2', 7.2], [7.2, 7.2], ['7,2', 7.2], ['7.2 h', 7.2], ['7 hr 12 min', 7.2], ['7 hours 12 minutes', 7.2],
  ['7h12m', 7.2], ['1 hr 23 min\n2 hr', 3.4], ['1 hr 23 min, 2 hr', 3.4], ['1 hr, 23 min', 1.4],
  ['7\u5c0f\u65f612\u5206\u949f', 7.2], ['7 \u5c0f\u65f6 12 \u5206', 7.2], ['1\u5c0f\u65f623\u5206\u949f\n2\u5c0f\u65f6', 3.4],
  ['1\u5c0f\u65f623\u5206\u949f\uff0c2\u5c0f\u65f6', 3.4], ['1\u5c0f\u65f623\u5206\u949f\u30012\u5c0f\u65f6', 3.4],
  ['1:23:00\n2:00:00', 3.4], ['7:12', 7.2], ['432 min', 7.2], ['432', 7.2], ['25920', 7.2], ['27,000', 7.5],
  ['3600\n7200\n14400', 7], [[3600, 7200, 14400], 7], [['1 hr 23 min', '2 hr'], 3.4], ['["1 hr 23 min","2 hr"]', 3.4],
  ['25920 s', 7.2], ['45 min', 0.8], ['\u0034\u0035\u5206\u949f', 0.8], [{ value: '7 hr' }, 7],
];
test('parseSleep accepts Shortcuts duration formats', () => {
  for (const [v, want] of cases) assert.equal(parseSleep(v), want, JSON.stringify(v));
});
test('parseSleep: empty is missing, not 0', () => {
  for (const v of ['', ' ', null, undefined, [], '\n']) assert.equal(parseSleep(v), null, JSON.stringify(v));
});
test('parseHealth other fields', () => {
  assert.deepEqual(parseHealth({ resting_hr: '58 bpm', hrv_ms: '42,5 ms', steps: '8,123' }), { resting_hr: 58, hrv_ms: 42.5, steps: 8123 });
  assert.deepEqual(parseHealth({ steps: '', resting_hr: null }), {});
});
