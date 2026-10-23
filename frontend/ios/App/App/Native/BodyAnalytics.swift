import Foundation

enum BodyRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90, all = 0
    var id: Int { rawValue }
    var title: String { self == .all ? "全部" : "\(rawValue)天" }

    func contains(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), date < tomorrow else { return false }
        guard self != .all else { return true }
        let start = calendar.date(byAdding: .day, value: 1 - rawValue, to: today) ?? today
        return date >= start
    }
}

struct BodyTrainingSummary {
    var month: Int
    var week: Int
    var consecutiveWeeks: Int
}

struct BodyIntensity {
    struct Week: Identifiable {
        var date: Date
        var average: Double
        var id: Date { date }
    }
    var total: Int
    var rated: Int
    var average: Double?
    var hardShare: Double?
    var buckets: [Int]
    var weeks: [Week]
    var missing: Int { total - rated }
}

/// Calendar-based aggregates shared by native charts and tests. Session dates always
/// mean completion dates, matching the app's existing training-day semantics.
enum BodyAnalytics {
    static func workouts(_ sessions: [WorkoutSession], range: BodyRange, now: Date, calendar: Calendar = .current) -> [WorkoutSession] {
        sessions.filter { session in
            guard let date = session.finishedAt, date <= now else { return false }
            return range.contains(date, now: now, calendar: calendar)
        }.sorted { ($0.finishedAt ?? $0.startedAt) > ($1.finishedAt ?? $1.startedAt) }
    }

    static func weights(_ entries: [WeighIn], range: BodyRange, now: Date, calendar: Calendar = .current) -> [WeighIn] {
        entries.filter { range.contains($0.date, now: now, calendar: calendar) && $0.kilograms.isFinite && $0.kilograms > 0 }
            .sorted { $0.date < $1.date }
    }

    static func summary(_ sessions: [WorkoutSession], now: Date, calendar: Calendar = .current) -> BodyTrainingSummary {
        let dates = workouts(sessions, range: .all, now: now, calendar: calendar).compactMap(\.finishedAt)
        let monday = Weekday.monday(of: now, calendar: calendar)
        let weeks = Set(dates.map { Weekday.monday(of: $0, calendar: calendar) })
        // An unfinished current week does not break the streak until the week ends.
        var cursor = weeks.contains(monday) ? monday : (calendar.date(byAdding: .day, value: -7, to: monday) ?? monday)
        var streak = 0
        while weeks.contains(cursor) {
            streak += 1
            guard let prior = calendar.date(byAdding: .day, value: -7, to: cursor), prior < cursor else { break }
            cursor = prior
        }
        return BodyTrainingSummary(
            month: dates.filter { calendar.isDate($0, equalTo: now, toGranularity: .month) }.count,
            week: dates.filter { $0 >= monday }.count,
            consecutiveWeeks: streak
        )
    }

    static func muscleLoads(_ sessions: [WorkoutSession], muscles: [String: [String: Double]]) -> [MuscleLoad] {
        var totals: [String: Double] = [:]
        for session in sessions where session.finishedAt != nil {
            for exercise in session.exercises {
                let count = exercise.sets.filter(\.done).count
                guard count > 0 else { continue }
                for (id, contribution) in muscles[exercise.exerciseId] ?? [:] where contribution.isFinite && contribution > 0 {
                    totals[id, default: 0] += contribution * Double(count)
                }
            }
        }
        return totals.map { MuscleLoad(id: $0.key, value: $0.value) }.sorted {
            $0.value == $1.value ? $0.id < $1.id : $0.value > $1.value
        }
    }

    static func intensity(_ sessions: [WorkoutSession], calendar: Calendar = .current) -> BodyIntensity {
        var values: [Int] = []
        var weekly: [Date: [Int]] = [:]
        var total = 0
        for session in sessions {
            guard let date = session.finishedAt else { continue }
            for set in session.exercises.flatMap(\.sets) where set.done {
                total += 1
                guard let rir = set.rir, (0...10).contains(rir) else { continue }
                values.append(rir)
                weekly[Weekday.monday(of: date, calendar: calendar), default: []].append(rir)
            }
        }
        var buckets = Array(repeating: 0, count: 5)
        for value in values { buckets[min(value, 4)] += 1 }
        return BodyIntensity(
            total: total, rated: values.count,
            average: values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count),
            hardShare: values.isEmpty ? nil : Double(values.filter { $0 <= 3 }.count) / Double(values.count),
            buckets: buckets,
            weeks: weekly.map { BodyIntensity.Week(date: $0.key, average: Double($0.value.reduce(0, +)) / Double($0.value.count)) }
                .sorted { $0.date < $1.date }
        )
    }

    static func recordDays(workouts: [WorkoutSession], weights: [WeighIn], measurements: [BodyMeasurement], calendar: Calendar = .current) -> [Date] {
        let dates = workouts.compactMap(\.finishedAt) + weights.map(\.date) + measurements.map(\.date)
        return Set(dates.map { calendar.startOfDay(for: $0) }).sorted(by: >)
    }
}
