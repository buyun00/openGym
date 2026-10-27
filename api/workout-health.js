// Fields shared by workout.completed mail and webhook payloads. No event dispatch here.
export function completedHealthFields(workout) {
  const raw = workout?.health;
  return raw && typeof raw === 'object' && !Array.isArray(raw)
    ? { health: healthPayload(raw) } : {};
}

// Explicit units and bounded scalars; never turn missing or denied readings into zero.
export function healthPayload(raw) {
  const value = (key, max) => typeof raw[key] === 'number' && Number.isFinite(raw[key]) && raw[key] >= 0 && raw[key] <= max ? raw[key] : null;
  return {
    source: 'apple_health',
    status: ['available', 'no_data', 'unavailable', 'query_failed'].includes(raw.status) ? raw.status : 'no_data',
    window_start: value('window_start', 1e14), window_end: value('window_end', 1e14),
    queried_at: value('queried_at', 1e14),
    workout_id: typeof raw.workout_id === 'string' ? raw.workout_id.slice(0, 200) : null,
    heart_rate_avg_bpm: value('heart_rate_avg_bpm', 400),
    heart_rate_max_bpm: value('heart_rate_max_bpm', 400),
    active_energy_kcal: value('active_energy_kcal', 100000),
  };
}
