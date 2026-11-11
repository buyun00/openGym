import Foundation
import ActivityKit

struct TrainingActivityAttributes: ActivityAttributes {
    struct Countdown: Codable, Hashable {
        enum Kind: String, Codable {
            case rest, cardio
        }

        var kind: Kind
        var start: Date
        var end: Date
        var interval: ClosedRange<Date> { min(start, end)...end }
    }

    struct ContentState: Codable, Hashable {
        var exercise: String
        var completed: Int
        var total: Int
        var countdown: Countdown? = nil
    }
    var sessionID: UUID
    var name: String
}

struct GymWidgetData: Codable, Equatable {
    struct Weight: Codable, Equatable, Identifiable {
        var date: Date
        var kilograms: Double
        var id: Date { date }
    }
    struct Plan: Codable, Equatable {
        var title: String
        var done: Bool
        var active: Bool
    }
    static let group = "group.org.lin0.lingym"
    static let key = "widget-snapshot-v1"
    var waterDay = ""
    var waterML = 0
    var waterGoal: Int?
    var plans: [String: Plan] = [:]
    var weights: [Weight] = []

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func read() -> Self {
        guard let defaults = UserDefaults(suiteName: group),
              let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
}
