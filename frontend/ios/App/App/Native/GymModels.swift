import Foundation

enum AppTab: String, Hashable {
    case today, plan, workout, body, water
}

struct RoutineExercise: Codable, Identifiable, Hashable {
    var id: UUID
    var exerciseId: String
    var name: String
    var setCount: Int
    var reps: Int
}

struct Routine: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var exercises: [RoutineExercise]
}

struct WorkoutSet: Codable, Identifiable, Hashable {
    var id: UUID
    var weight: Double
    var reps: Int
    var done: Bool
}

struct WorkoutExercise: Codable, Identifiable, Hashable {
    var id: UUID
    var exerciseId: String
    var name: String
    var sets: [WorkoutSet]
}

struct WorkoutSession: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var startedAt: Date
    var finishedAt: Date?
    var exercises: [WorkoutExercise]
}

struct WeighIn: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var kilograms: Double
}

struct DayPlan: Codable, Hashable {
    var day: Int
    var routineIds: [String]
}

struct WeekMark: Identifiable {
    var date: Date
    var day: Int
    var isToday: Bool
    var planned: Bool
    var done: Bool
    var id: Date { date }
}

struct MuscleLoad: Identifiable {
    var id: String
    var value: Double
}

struct MonthCount: Identifiable {
    var month: Date
    var count: Int
    var id: Date { month }
}

struct HistoryExercise: Identifiable, Hashable {
    var id: String
    var name: String
}

struct SetPoint: Identifiable {
    var date: Date
    var value: Double
    var id: Date { date }
}

struct ExerciseSeries {
    var usesReps: Bool
    var points: [SetPoint]
}

enum Weekday {
    static let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    static let shorts = ["一", "二", "三", "四", "五", "六", "日"]

    static func name(_ day: Int) -> String { names[slot(day)] }
    static func short(_ day: Int) -> String { shorts[slot(day)] }

    static func index(for date: Date, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    static func monday(of date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let offset = index(for: start, calendar: calendar) - 1
        return calendar.date(byAdding: .day, value: -offset, to: start) ?? start
    }

    private static func slot(_ day: Int) -> Int { min(6, max(0, day - 1)) }
}

func formatKg(_ value: Double) -> String {
    let rounded = (value * 100).rounded() / 100
    if abs(rounded - rounded.rounded()) < 0.001 { return String(format: "%.0f", rounded) }
    if abs(rounded * 10 - (rounded * 10).rounded()) < 0.001 { return String(format: "%.1f", rounded) }
    return String(format: "%.2f", rounded)
}

func parseKg(_ text: String) -> Double? {
    let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
    guard let value = Double(cleaned), value > 0, value < 500 else { return nil }
    return value
}

func signedKg(_ value: Double) -> String {
    let prefix = value > 0 ? "+" : ""
    return prefix + formatKg(value)
}
