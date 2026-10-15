import test from 'node:test';
import assert from 'node:assert/strict';
import { parseSleep, parseHealth, parseSleepStages, stageOf } from '../body-hook.js';

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
test('parseSleep: iOS m:ss / h:mm:ss list (Shortcuts Duration of sleep samples)', () => {
  assert.equal(parseSleep('28:01\n2:24:36\n30\n4:00'), 3);
  assert.equal(parseSleep('3:00\n2:30\n5:30\n1:00\n28:01\n15:00\n10:00\n18:00\n22:00\n6:30\n6:00\n9:00\n28:31\n29:01\n39:01\n13:30\n3:30\n37:01\n47:01\n42:01\n45:31\n21:30\n3:30\n20:30\n22:00\n3:00\n12:00\n2:24:36\n9:00\n4:00\n24:31\n52:02\n2:00\n30\n4:00\n1:00\n1:00\n22:00\n36:01\n7:30\n2:00\n8:00\n2:30\n4:00'), 13.6);
  assert.equal(parseSleep('7:12'), 7.2);
});
test('parseSleep: empty is missing, not 0', () => {
  for (const v of ['', ' ', null, undefined, [], '\n']) assert.equal(parseSleep(v), null, JSON.stringify(v));
});
test('parseHealth other fields', () => {
  assert.deepEqual(parseHealth({ resting_hr: '58 bpm', hrv_ms: '42,5 ms', steps: '8,123' }), { resting_hr: 58, hrv_ms: 42.5, steps: 8123 });
  assert.deepEqual(parseHealth({ steps: '', resting_hr: null }), {});
});

test('stageOf names', () => {
  const m = { '\u6838\u5fc3\u7761\u7720': 'core', Core: 'core', '\u6df1\u5ea6\u7761\u7720': 'deep', Deep: 'deep', '\u5feb\u901f\u52a8\u773c\u7761\u7720': 'rem', REM: 'rem',
    '\u6e05\u9192': 'awake', '\u6e05\u9192\u65f6\u95f4': 'awake', Awake: 'awake', '\u5367\u5e8a': 'inbed', '\u5728\u5e8a\u4e0a': 'inbed', 'In Bed': 'inbed',
    '\u7761\u7720\u4e2d': 'asleep', Asleep: 'asleep', Unspecified: 'asleep' };
  for (const [k, v] of Object.entries(m)) assert.equal(stageOf(k), v, k);
});
test('sleep stages paired by index', () => {
  const r = parseHealth({ sleep_hours: '30:00\n1:00:00\n2:00:00\n10:00\n8:00:00', sleep_stages: '\u6df1\u5ea6\u7761\u7720\nREM\n\u6838\u5fc3\u7761\u7720\n\u6e05\u9192\n\u5728\u5e8a\u4e0a' });
  assert.deepEqual({ ...r }, { sleep_hours: 3.5, deep_min: 30, rem_min: 60, core_min: 120, awake_min: 10 });
  const a = parseHealth({ sleep_hours: ['1 hr', '30 min'], sleep_stages: ['Core', 'Deep'] });
  assert.equal(a.sleep_hours, 1.5); assert.equal(a.deep_min, 30);
});
test('sleep stages length mismatch keeps total', () => {
  const r = parseHealth({ sleep_hours: '28:01\n2:24:36\n30\n4:00', sleep_stages: 'Core\nDeep' });
  assert.equal(r.sleep_hours, 3); assert.equal(r.deep_min, undefined);
  assert.equal(parseSleepStages('1:00\n2:00', 'Core').ok, false);
});
