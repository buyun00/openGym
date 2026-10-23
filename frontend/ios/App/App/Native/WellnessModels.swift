import Foundation

// Local civil dates are captured at entry time so travelling never moves an old record.
enum WellnessDay {
    static func calendar(_ source: Calendar = .current) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = source.timeZone
        result.firstWeekday = 2
        return result
    }

    static func key(_ date: Date, calendar source: Calendar = .current) -> String {
        let c = calendar(source).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func weekKey(_ date: Date, calendar source: Calendar = .current) -> String {
        let c = calendar(source)
        let offset = (c.component(.weekday, from: date) + 5) % 7
        return key(c.date(byAdding: .day, value: -offset, to: c.startOfDay(for: date))!, calendar: c)
    }
}

struct WaterEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var day: String
    var milliliters: Int
}

struct ClockTime: Codable, Equatable, Hashable {
    var hour: Int
    var minute: Int

    var label: String { String(format: "%02d:%02d", hour, minute) }
    var minutes: Int { hour * 60 + minute }

    func date(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    init(date: Date, calendar: Calendar = .current) {
        hour = calendar.component(.hour, from: date)
        minute = calendar.component(.minute, from: date)
    }
}

enum Supplement: String, Codable, CaseIterable, Identifiable {
    case b, d
    var id: String { rawValue }
    var name: String { self == .b ? "维生素 B" : "维生素 D" }
}

struct DoseInstance: Identifiable, Equatable {
    var supplement: Supplement
    var period: String
    var slot: Int
    var time: ClockTime?
    var id: String { "\(supplement.rawValue).\(period).\(slot)" }
}

struct DoseRecord: Codable, Identifiable, Equatable {
    var id: String
    var supplement: Supplement
    var period: String
    var slot: Int
    var takenAt: Date
    var takenDay: String
}

struct WellnessSettings: Codable, Equatable {
    // No assumed goal or completed records from the approved illustration.
    var waterGoalML: Int?
    var cupML = 250
    var bTimes = [ClockTime(hour: 8), ClockTime(hour: 13), ClockTime(hour: 19)]
    var bTimesConfirmed = false
    var dWeekday: Int? // ISO weekday: Monday = 1. Nil until the user chooses.
    var dTime = ClockTime(hour: 9)
    var waterReminders = false
    var supplementReminders = false
    var waterTimes = [ClockTime(hour: 9), ClockTime(hour: 12), ClockTime(hour: 15), ClockTime(hour: 18)]

    var isValid: Bool {
        (waterGoalML == nil || (250...10000).contains(waterGoalML!)) &&
        (50...2000).contains(cupML) && bTimes.count == 3 &&
        Set(bTimes).count == 3 && (dWeekday == nil || (1...7).contains(dWeekday!)) &&
        !waterTimes.isEmpty && waterTimes.count <= 4 && Set(waterTimes).count == waterTimes.count &&
        (bTimes + [dTime] + waterTimes).allSatisfy { (0...23).contains($0.hour) && (0...59).contains($0.minute) }
    }
}

struct WellnessState: Codable, Equatable {
    var version = 1
    var settings = WellnessSettings()
    var water: [WaterEntry] = []
    var doses: [DoseRecord] = []

    func waterTotal(on date: Date, calendar: Calendar = .current) -> Int {
        let day = WellnessDay.key(date, calendar: calendar)
        return water.filter { $0.day == day }.reduce(0) { $0 + $1.milliliters }
    }

    func progress(on date: Date, calendar: Calendar = .current) -> Double {
        guard let goal = settings.waterGoalML, goal > 0 else { return 0 }
        return Double(waterTotal(on: date, calendar: calendar)) / Double(goal)
    }

    func instances(for supplement: Supplement, on date: Date, calendar: Calendar = .current) -> [DoseInstance] {
        if supplement == .b {
            return (0..<3).map { slot in
                DoseInstance(supplement: .b, period: WellnessDay.key(date, calendar: calendar), slot: slot,
                             time: settings.bTimesConfirmed ? settings.bTimes[slot] : nil)
            }
        }
        let weekday = (calendar.component(.weekday, from: date) + 5) % 7 + 1
        guard settings.dWeekday == weekday else { return [] }
        return [DoseInstance(supplement: .d, period: WellnessDay.weekKey(date, calendar: calendar), slot: 0, time: settings.dTime)]
    }

    func record(for instance: DoseInstance) -> DoseRecord? { doses.first { $0.id == instance.id } }

    mutating func addWater(_ milliliters: Int, at date: Date, id: UUID = UUID(), calendar: Calendar = .current) -> UUID? {
        guard (1...5000).contains(milliliters), !water.contains(where: { $0.id == id }) else { return nil }
        water.append(WaterEntry(id: id, date: date, day: WellnessDay.key(date, calendar: calendar), milliliters: milliliters))
        return id
    }

    mutating func recordDose(_ instance: DoseInstance, at date: Date, calendar: Calendar = .current) -> Bool {
        // A sheet left open across midnight must not mark yesterday's instance as today's.
        guard instances(for: instance.supplement, on: date, calendar: calendar).contains(where: { $0.id == instance.id }),
              record(for: instance) == nil else { return false }
        doses.append(DoseRecord(id: instance.id, supplement: instance.supplement, period: instance.period,
                                slot: instance.slot, takenAt: date, takenDay: WellnessDay.key(date, calendar: calendar)))
        return true
    }
}

struct WellnessReminder: Identifiable, Equatable {
    var id: String
    var date: Date
    var title: String
    var body: String
}

enum WellnessReminderPlan {
    static let prefix = "opengym.wellness."

    // One-shot instances let recording a dose remove exactly that reminder, not a whole recurring plan.
    // Seven days stays below iOS's pending-notification limit (at most 50 requests).
    static func make(state: WellnessState, now: Date, calendar: Calendar = .current) -> [WellnessReminder] {
        var result: [WellnessReminder] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            if state.settings.waterReminders && state.progress(on: day, calendar: calendar) < 1 {
                for (index, time) in state.settings.waterTimes.enumerated() {
                    let date = time.date(on: day, calendar: calendar)
                    if date > now {
                        result.append(WellnessReminder(id: "\(prefix)water.\(WellnessDay.key(day, calendar: calendar)).\(index)",
                                                       date: date, title: "喝点水吧", body: "喝完后，打开 openGym 记录实际饮水量。"))
                    }
                }
            }
            if state.settings.supplementReminders {
                for supplement in Supplement.allCases {
                    for instance in state.instances(for: supplement, on: day, calendar: calendar) {
                        guard let time = instance.time, state.record(for: instance) == nil else { continue }
                        let date = time.date(on: day, calendar: calendar)
                        if date > now {
                            result.append(WellnessReminder(id: prefix + instance.id, date: date, title: instance.supplement.name,
                                                           body: "到了你设置的服用时间。实际服用后再记录。"))
                        }
                    }
                }
            }
        }
        return result.sorted { $0.date < $1.date }
    }
}
