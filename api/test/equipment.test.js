import test from 'node:test';
import assert from 'node:assert/strict';
import { groupOf, upsert, remove, normalizeItem, decodePhoto } from '../equipment.js';

test('groupOf maps Chinese and English names', () => {
  for (const [k, v] of [['胸', 'chest'], ['背', 'back'], ['腿', 'legs'], ['肩', 'shoulders'], ['手臂', 'arms'], ['核心', 'core'],
    ['Chest', 'chest'], ['triceps', 'arms'], ['front delts', 'shoulders'], ['三头肌', 'arms'], ['glutes', 'legs'], ['xyz', null]]) assert.equal(groupOf(k), v, k);
});
test('upsert creates, updates by name, keeps omitted fields', () => {
  const S = {};
  const a = upsert(S, { name: '坐姿推胸机', primary: '胸', secondary: ['肩', '手臂'], exercise_ids: ['0576'], note: '座椅 4' }, 1);
  assert.equal(a.created, true);
  assert.deepEqual(a.item.secondary, ['shoulders', 'arms']);
  const b = upsert(S, { name: '坐姿推胸机', location: '二楼' }, 2);
  assert.equal(b.created, false);
  assert.equal(S.gymEquipment.length, 1);
  assert.equal(b.item.note, '座椅 4');
  assert.equal(b.item.location, '二楼');
  assert.deepEqual(b.item.exIds, ['0576']);
  assert.equal(remove(S, { name: '坐姿推胸机' }), 1);
  assert.equal(S.gymEquipment.length, 0);
});
test('upsert validates', () => {
  assert.throws(() => upsert({}, { name: '', primary: '胸' }));
  assert.throws(() => upsert({}, { name: 'x' }));
});
test('photo name must be a hash', () => {
  assert.equal(normalizeItem({ name: 'x', primary: 'chest', photo: '../../etc/passwd' }).photo, null);
  assert.throws(() => decodePhoto('aGVsbG8='));
});