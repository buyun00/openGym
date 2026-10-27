import { test } from 'node:test';
import assert from 'node:assert/strict';
import { completedHealthFields } from '../workout-health.js';
import { envelope } from '../workout-webhook.js';

test('old workouts keep the original completion contract', () => {
  assert.deepEqual(completedHealthFields({ id: 'old', end: 42 }), {});
});
test('missing, denied and invalid readings remain null, not zero', () => {
  const { health } = completedHealthFields({ id: 'w', end: 42, health: {
    status: 'no_data', heart_rate_avg_bpm: '123', heart_rate_max_bpm: Infinity,
    active_energy_kcal: -1, secret: 'not forwarded',
  } });
  assert.equal(health.status, 'no_data');
  assert.equal(health.heart_rate_avg_bpm, null);
  assert.equal(health.heart_rate_max_bpm, null);
  assert.equal(health.active_energy_kcal, null);
  assert.equal('secret' in health, false);
});

test('completion envelope retains heart rate, energy and the workout time window', () => {
  const start = 1_700_000_000_000, end = start + 40 * 60000;
  const fields = completedHealthFields({ health: { source: 'apple_health', status: 'available',
    window_start: start, window_end: end, queried_at: end + 1000, workout_id: 'hk-workout',
    heart_rate_avg_bpm: 123.5, heart_rate_max_bpm: 168, active_energy_kcal: 245 } });
  const event = envelope('workout.completed', { id: 'u' }, { workout_id: 'gym-workout', ...fields }, end);
  const delivered = JSON.parse(JSON.stringify(event)); // Same JSON delivered to mail/webhook.
  assert.equal(delivered.data.health.heart_rate_avg_bpm, 123.5);
  assert.equal(delivered.data.health.heart_rate_max_bpm, 168);
  assert.equal(delivered.data.health.active_energy_kcal, 245);
  assert.equal(delivered.data.health.window_start, start);
  assert.equal(delivered.data.health.window_end, end);
  assert.equal(typeof delivered.data.health.queried_at, 'string');
  assert.equal(delivered.data.health.workout_id, 'hk-workout');
});

test('malformed health containers are omitted and optional metrics stay null', () => {
  for (const health of [null, [], '123', 0]) assert.deepEqual(completedHealthFields({ health }), {});
  const { health } = completedHealthFields({ health: { status: 'no_data' } });
  assert.equal(health.heart_rate_avg_bpm, null);
  assert.equal(health.active_energy_kcal, null);
});
