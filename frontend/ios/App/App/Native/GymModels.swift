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
    var mode: WorkoutMode? = nil
    var minutes: Double? = nil
    var speed: Double? = nil
    var incline: Double? = nil
    var seconds: Double? = nil
    var note: String? = nil
    var weight: Double? = nil
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
    // Nil means unrecorded, never zero effort. Optional for older gym-state.json files.
    var rir: Int? = nil
    var minutes: Double? = nil
    var speed: Double? = nil
    var incline: Double? = nil
    var seconds: Double? = nil
    var completedAt: Date? = nil
}

struct WorkoutExercise: Codable, Identifiable, Hashable {
    var id: UUID
    var exerciseId: String
    var name: String
    var sets: [WorkoutSet]
    var mode: WorkoutMode? = nil
    var note: String? = nil
    var notePinned: Bool? = nil
    var noProgression: Bool? = nil
    var restSeconds: Int? = nil
    var routineId: UUID? = nil
}

struct WorkoutSession: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var startedAt: Date
    var finishedAt: Date?
    var exercises: [WorkoutExercise]
    var note: String? = nil
    var layout: WorkoutLayout? = nil
    var selectedExerciseId: UUID? = nil
    var noProgression: Bool? = nil
    var restEndsAt: Date? = nil
    var restOwner: UUID? = nil
    var restSetOwner: UUID? = nil
    var cardioTimer: WorkoutCardioTimer? = nil
    var health: WorkoutHealth? = nil
}

struct WorkoutCardioTimer: Codable, Hashable {
    var exerciseID: UUID
    var setID: UUID
    var start: Date
    var end: Date
}

struct WorkoutHealth: Codable, Hashable {
    var source = "apple_health"
    var status: String
    var window_start: Double
    var window_end: Double
    var queried_at: Double
    var workout_id: String? = nil
    var heart_rate_avg_bpm: Double? = nil
    var heart_rate_max_bpm: Double? = nil
    var active_energy_kcal: Double? = nil
}

enum WorkoutMode: String, Codable, CaseIterable {
    case reps, time, cardio
    var title: String { switch self { case .reps: return "力量"; case .time: return "计时"; case .cardio: return "有氧" } }
}

enum WorkoutLayout: String, Codable, CaseIterable {
    case cards, list, compact
    var title: String { switch self { case .cards: return "卡片"; case .list: return "列表"; case .compact: return "紧凑" } }
}

struct WeighIn: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var kilograms: Double
    var bodyFatPercent: Double? = nil

    var leanKilograms: Double? {
        guard let fat = bodyFatPercent, fat > 0, fat < 100 else { return nil }
        return kilograms * (1 - fat / 100)
    }
}

struct BodyMeasurement: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var centimeters: [String: Double]
    var bodyFatPercent: Double? = nil

    static let fields = ["颈围", "肩围", "胸围", "腰围", "臀围", "腹围", "左上臂围", "右上臂围",
                         "左前臂围", "右前臂围", "左腕围", "右腕围", "左大腿围", "右大腿围",
                         "左小腿围", "右小腿围", "左踝围", "右踝围", "上臂围", "大腿围", "小腿围"]
}

struct GymEquipmentRecord: Codable, Identifiable {
    var id: String
    var name: String
    var note: String
    var location: String
    var exerciseNames: [String]
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
