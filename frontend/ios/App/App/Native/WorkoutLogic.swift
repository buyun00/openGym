import Foundation

struct WorkoutPreferences: Codable, Equatable {
    var layout: WorkoutLayout = .cards
    var media: WorkoutMediaSize = .full
    var sound = true
    var haptics = true
    var flash = false
    var keepAwake = true
    var effort: WorkoutEffort = .rir
}

enum WorkoutMediaSize: String, Codable, CaseIterable {
    case full, mini, off
    var title: String { switch self { case .full: return "大图"; case .mini: return "缩略图"; case .off: return "隐藏" } }
}

enum WorkoutEffort: String, Codable, CaseIterable {
    case none, rir, rpe
    var title: String { self == .none ? "关闭" : rawValue.uppercased() }
}

enum WorkoutMetric: String, CaseIterable {
    case weight, reps, minutes, speed, incline, seconds
    var title: String {
        switch self {
        case .weight: return "重量 (kg)"
        case .reps: return "次数"
        case .minutes: return "时长 (分钟)"
        case .speed: return "速度 (km/h)"
        case .incline: return "坡度 (%)"
        case .seconds: return "时长 (秒)"
        }
    }
    var step: Double { switch self { case .weight: return 1.25; case .speed: return 0.1; case .incline: return 0.5; default: return 1 } }
    var maximum: Double { switch self { case .weight: return 500; case .reps: return 100; case .minutes: return 600; case .speed: return 100; case .incline: return 40; case .seconds: return 3600 } }

    func value(in set: WorkoutSet) -> Double? {
        switch self {
        case .weight: return set.weight
        case .reps: return Double(set.reps)
        case .minutes: return set.minutes
        case .speed: return set.speed
        case .incline: return set.incline
        case .seconds: return set.seconds
        }
    }

    func apply(_ value: Double?, to set: inout WorkoutSet) {
        guard value == nil || value!.isFinite else { return }
        let bounded = value.map { min(maximum, max(0, $0)) }
        switch self {
        case .weight: set.weight = bounded ?? 0
        case .reps: set.reps = Int((bounded ?? 0).rounded())
        case .minutes: set.minutes = bounded
        case .speed: set.speed = bounded.map { ($0 * 10).rounded() / 10 }
        case .incline: set.incline = bounded.map { ($0 * 2).rounded() / 2 }
        case .seconds: set.seconds = bounded.map { $0.rounded() }
        }
    }
}

enum WorkoutLogic {
    static func copy(_ set: WorkoutSet) -> WorkoutSet {
        var next = set
        next.id = UUID()
        next.done = false
        next.rir = nil
        next.completedAt = nil
        return next
    }

    static func seed(mode: WorkoutMode, reps: Int = 8, previous: WorkoutSet? = nil) -> WorkoutSet {
        if let previous { return copy(previous) }
        var set = WorkoutSet(id: UUID(), weight: 0, reps: mode == .reps ? reps : 0, done: false)
        if mode == .cardio { set.minutes = 20; set.speed = 8 }
        if mode == .time { set.seconds = 45 }
        return set
    }

    static func previous(_ id: String, mode: WorkoutMode, in history: [WorkoutSession], forProgression: Bool) -> (Date, WorkoutExercise)? {
        for session in history.sorted(by: { $0.startedAt > $1.startedAt }) where session.finishedAt != nil {
            if forProgression && session.noProgression == true { continue }
            if let exercise = session.exercises.last(where: {
                $0.exerciseId == id && ($0.mode ?? .reps) == mode && $0.sets.contains(where: \.done)
                    && (!forProgression || $0.noProgression != true)
            }) { return (session.startedAt, exercise) }
        }
        return nil
    }

    static func setExcluded(_ excluded: Bool, session: inout WorkoutSession) {
        session.noProgression = excluded
        for index in session.exercises.indices { session.exercises[index].noProgression = excluded }
    }

    static func insert(_ exercises: [WorkoutExercise], after id: UUID?, into session: inout WorkoutSession) {
        let index = id.flatMap { id in session.exercises.firstIndex(where: { $0.id == id }).map { $0 + 1 } } ?? session.exercises.count
        let incoming = exercises.map { exercise in
            var copy = exercise
            if session.noProgression == true { copy.noProgression = true }
            return copy
        }
        session.exercises.insert(contentsOf: incoming, at: index)
        if let first = incoming.first { session.selectedExerciseId = first.id }
    }

    static func remove(_ id: UUID, from session: inout WorkoutSession) {
        guard let index = session.exercises.firstIndex(where: { $0.id == id }) else { return }
        session.exercises.remove(at: index)
        if session.selectedExerciseId == id {
            session.selectedExerciseId = session.exercises.isEmpty ? nil : session.exercises[min(index, session.exercises.count - 1)].id
        }
        if session.restOwner == id { session.restEndsAt = nil; session.restOwner = nil; session.restSetOwner = nil }
    }

    static func finished(_ active: WorkoutSession, at date: Date, health: WorkoutHealth? = nil) -> WorkoutSession {
        var result = active
        // Only this finish action's explicit selection is retained. Skip always clears prior health.
        result.health = health
        result.finishedAt = date
        result.exercises.removeAll { !$0.sets.contains(where: \.done) }
        result.restEndsAt = nil
        result.restOwner = nil
        result.restSetOwner = nil
        result.selectedExerciseId = nil
        return result
    }

    static func summary(_ set: WorkoutSet, mode: WorkoutMode) -> String {
        switch mode {
        case .cardio:
            let base = "\(formatKg(set.minutes ?? 0)) min @ \(formatKg(set.speed ?? 0)) km/h"
            return base + (set.incline.map { " · 坡度 \(formatKg($0))%" } ?? "")
        case .time: return "\(formatKg(set.seconds ?? 0)) 秒" + (set.weight > 0 ? " · \(formatKg(set.weight)) kg" : "")
        case .reps: return "\(formatKg(set.weight)) kg × \(set.reps)"
        }
    }
}
