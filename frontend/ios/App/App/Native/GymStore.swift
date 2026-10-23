import Foundation
import Observation

@MainActor
@Observable
final class GymStore {
    let wellness = WellnessStore()
    var routines: [Routine] = []
    var week: [DayPlan] = (1...7).map { DayPlan(day: $0, routineIds: []) }
    var workouts: [WorkoutSession] = []
    var active: WorkoutSession?
    var weighIns: [WeighIn] = []
    var bodyMeasurements: [BodyMeasurement] = []
    var saveError: String?
    var targetKg: Double?
    var restSeconds: Int = 90
    var ownedEquipment: [String] = []
    var tab: AppTab = .today
    var restEndsAt: Date?

    private struct Snapshot: Codable {
        var routines: [Routine] = []
        var week: [DayPlan] = []
        var workouts: [WorkoutSession] = []
        var active: WorkoutSession?
        var weighIns: [WeighIn] = []
        var bodyMeasurements: [BodyMeasurement]?
        var targetKg: Double?
        var restSeconds: Int = 90
        var ownedEquipment: [String] = []
    }

    init() { load() }

    var todayIndex: Int { Weekday.index(for: Date()) }
    var todayRoutines: [Routine] { routines(on: todayIndex) }
    var didTrainToday: Bool { !finished(on: Date()).isEmpty }

    var todayTitle: String {
        if let active { return "\(active.name)（进行中）" }
        if didTrainToday { return "今天已经练过" }
        let names = todayRoutines.map(\.name)
        if names.isEmpty { return "休息日" }
        return names.joined(separator: "、")
    }

    var todayDetail: String? {
        if active != nil { return "点这里继续" }
        if didTrainToday, !todayRoutines.isEmpty { return "还可以再开一次" }
        if todayRoutines.isEmpty { return nextPlanLabel() }
        let count = todayRoutines.reduce(0) { $0 + $1.exercises.count }
        return "\(count) 个动作"
    }

    var todayAction: String {
        if active != nil { return "继续" }
        if todayRoutines.isEmpty { return "去安排" }
        return "开始"
    }

    var latestWeighIn: WeighIn? { weighIns.max(by: { $0.date < $1.date }) }

    var deltaSincePrevious: Double? {
        let ordered = weighIns.sorted { $0.date < $1.date }
        guard ordered.count >= 2 else { return nil }
        return ordered[ordered.count - 1].kilograms - ordered[ordered.count - 2].kilograms
    }

    var goalProgress: Double? {
        guard let target = targetKg, let latest = latestWeighIn else { return nil }
        let ordered = weighIns.sorted { $0.date < $1.date }
        guard let first = ordered.first else { return nil }
        let span = abs(first.kilograms - target)
        if span < 0.05 { return abs(latest.kilograms - target) < 0.05 ? 1 : 0 }
        let remaining = abs(latest.kilograms - target)
        return min(1, max(0, 1 - remaining / span))
    }

    var goalCaption: String {
        guard let target = targetKg, let latest = latestWeighIn else { return "设一个目标体重" }
        let gap = target - latest.kilograms
        if abs(gap) < 0.05 { return "已达到目标" }
        if gap > 0 { return "还要增加 \(formatKg(gap)) kg" }
        return "还要减少 \(formatKg(abs(gap))) kg"
    }

    var finishedWorkouts: [WorkoutSession] {
        workouts.filter { $0.finishedAt != nil }.sorted { $0.startedAt > $1.startedAt }
    }

    var activeDoneCount: Int {
        active?.exercises.reduce(0) { $0 + $1.sets.filter(\.done).count } ?? 0
    }

    var activeSetCount: Int {
        active?.exercises.reduce(0) { $0 + $1.sets.count } ?? 0
    }

    func routines(on day: Int) -> [Routine] {
        let ids = week.first(where: { $0.day == day })?.routineIds ?? []
        return ids.compactMap { key in routines.first { $0.id.uuidString == key } }
    }

    func routine(_ id: UUID) -> Routine? { routines.first { $0.id == id } }

    func weekMarks(now: Date = Date(), calendar: Calendar = .current) -> [WeekMark] {
        let monday = Weekday.monday(of: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            let day = offset + 1
            return WeekMark(
                date: date,
                day: day,
                isToday: calendar.isDate(date, inSameDayAs: today),
                planned: !routines(on: day).isEmpty,
                done: !finished(on: date, calendar: calendar).isEmpty
            )
        }
    }

    func openToday() {
        if active != nil {
            tab = .workout
            return
        }
        if todayRoutines.isEmpty {
            tab = .plan
            return
        }
        start(todayRoutines)
    }

    func startToday() {
        if active != nil {
            tab = .workout
            return
        }
        start(todayRoutines)
    }

    func start(_ chosen: [Routine]) {
        if active != nil {
            tab = .workout
            return
        }
        let blocks = chosen.filter { !$0.exercises.isEmpty }
        guard !blocks.isEmpty else {
            tab = .plan
            return
        }
        var exercises: [WorkoutExercise] = []
        for routine in blocks {
            for slot in routine.exercises {
                let last = lastPerformed(slot.exerciseId)
                let count = max(1, slot.setCount)
                let reps = max(1, last?.reps ?? slot.reps)
                let weight = last?.weight ?? 0
                let sets = (0..<count).map { _ in
                    WorkoutSet(id: UUID(), weight: weight, reps: reps, done: false)
                }
                exercises.append(WorkoutExercise(id: UUID(), exerciseId: slot.exerciseId, name: slot.name, sets: sets))
            }
        }
        let name = blocks.count == 1 ? blocks[0].name : blocks.map(\.name).joined(separator: "、")
        active = WorkoutSession(id: UUID(), name: name, startedAt: Date(), finishedAt: nil, exercises: exercises)
        tab = .workout
        save()
    }

    func toggleSet(exercise exerciseId: UUID, set setId: UUID) {
        guard var session = active,
              let ei = session.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = session.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        let turningOn = !session.exercises[ei].sets[si].done
        session.exercises[ei].sets[si].done = turningOn
        if turningOn {
            let current = session.exercises[ei].sets[si]
            if let next = session.exercises[ei].sets.indices.first(where: { $0 > si && !session.exercises[ei].sets[$0].done }),
               session.exercises[ei].sets[next].weight == 0 {
                session.exercises[ei].sets[next].weight = current.weight
                session.exercises[ei].sets[next].reps = current.reps
            }
            restEndsAt = Date().addingTimeInterval(TimeInterval(max(15, restSeconds)))
        }
        active = session
        save()
    }

    func addSet(exercise exerciseId: UUID) {
        guard var session = active, let ei = session.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let last = session.exercises[ei].sets.last
        session.exercises[ei].sets.append(WorkoutSet(id: UUID(), weight: last?.weight ?? 0, reps: last?.reps ?? 8, done: false))
        active = session
        save()
    }

    func deleteSet(exercise exerciseId: UUID, set setId: UUID) {
        guard var session = active, let ei = session.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        session.exercises[ei].sets.removeAll { $0.id == setId }
        active = session
        save()
    }

    func setWeight(exercise exerciseId: UUID, set setId: UUID, weight: Double) {
        updateSet(exercise: exerciseId, set: setId) { $0.weight = min(500, max(0, weight)) }
    }

    func setReps(exercise exerciseId: UUID, set setId: UUID, reps: Int) {
        updateSet(exercise: exerciseId, set: setId) { $0.reps = min(100, max(0, reps)) }
    }

    func finishActive() {
        guard var session = active else { return }
        session.finishedAt = Date()
        workouts.append(session)
        active = nil
        restEndsAt = nil
        tab = .today
        save()
    }

    func discardActive() {
        active = nil
        restEndsAt = nil
        save()
    }

    func clearRest() { restEndsAt = nil }

    func deleteWorkout(_ id: UUID) {
        let previous = workouts
        workouts.removeAll { $0.id == id }
        if !save() { workouts = previous }
    }

    @discardableResult
    func addRoutine(name: String) -> UUID {
        let routine = Routine(id: UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), exercises: [])
        routines.append(routine)
        save()
        return routine.id
    }

    func deleteRoutine(_ id: UUID) {
        let key = id.uuidString
        routines.removeAll { $0.id == id }
        for index in week.indices {
            week[index].routineIds.removeAll { $0 == key }
        }
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index].name = name
        save()
    }

    func updateSlot(_ routineId: UUID, _ slotId: UUID, setCount: Int? = nil, reps: Int? = nil) {
        guard let ri = routines.firstIndex(where: { $0.id == routineId }),
              let si = routines[ri].exercises.firstIndex(where: { $0.id == slotId }) else { return }
        if let setCount { routines[ri].exercises[si].setCount = min(20, max(1, setCount)) }
        if let reps { routines[ri].exercises[si].reps = min(100, max(1, reps)) }
        save()
    }

    func addExercise(_ info: ExerciseInfo, to routineId: UUID) {
        guard let index = routines.firstIndex(where: { $0.id == routineId }) else { return }
        routines[index].exercises.append(RoutineExercise(id: UUID(), exerciseId: info.id, name: info.name, setCount: 3, reps: 8))
        save()
    }

    func removeExercise(_ slotId: UUID, from routineId: UUID) {
        guard let index = routines.firstIndex(where: { $0.id == routineId }) else { return }
        routines[index].exercises.removeAll { $0.id == slotId }
        save()
    }

    func setIncluded(_ routine: Routine, on day: Int, included: Bool) {
        guard let index = week.firstIndex(where: { $0.day == day }) else { return }
        let key = routine.id.uuidString
        if included {
            if !week[index].routineIds.contains(key) { week[index].routineIds.append(key) }
        } else {
            week[index].routineIds.removeAll { $0 == key }
        }
        save()
    }

    @discardableResult
    func addWeighIn(kilograms: Double, date: Date, bodyFatPercent: Double? = nil, keepExistingBodyFat: Bool = true) -> Bool {
        guard kilograms.isFinite, kilograms > 0, kilograms < 500 else { return false }
        let previous = weighIns
        let day = Calendar.current.startOfDay(for: date)
        let existing = weighIns.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
        weighIns.removeAll { Calendar.current.isDate($0.date, inSameDayAs: day) }
        let fat = bodyFatPercent.flatMap { $0.isFinite && $0 > 0 && $0 < 100 ? $0 : nil }
        weighIns.append(WeighIn(id: existing?.id ?? UUID(), date: day, kilograms: kilograms,
                               bodyFatPercent: fat ?? (keepExistingBodyFat ? existing?.bodyFatPercent : nil)))
        weighIns.sort { $0.date < $1.date }
        guard save() else { weighIns = previous; return false }
        return true
    }

    func deleteWeighIn(_ id: UUID) {
        let previous = weighIns
        weighIns.removeAll { $0.id == id }
        if !save() { weighIns = previous }
    }

    @discardableResult
    func addMeasurement(date: Date, centimeters: [String: Double]) -> Bool {
        let valid = centimeters.filter { BodyMeasurement.fields.contains($0.key) && $0.value.isFinite && $0.value > 0 && $0.value < 300 }
        guard !valid.isEmpty else { return false }
        let previous = bodyMeasurements
        let day = Calendar.current.startOfDay(for: date)
        if let index = bodyMeasurements.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            bodyMeasurements[index].centimeters = valid
        } else {
            bodyMeasurements.append(BodyMeasurement(id: UUID(), date: day, centimeters: valid))
        }
        guard save() else { bodyMeasurements = previous; return false }
        return true
    }

    func deleteMeasurement(_ id: UUID) {
        let previous = bodyMeasurements
        bodyMeasurements.removeAll { $0.id == id }
        if !save() { bodyMeasurements = previous }
    }

    func setRIR(workout workoutId: UUID? = nil, exercise exerciseId: UUID, set setId: UUID, value: Int?) {
        let valid = value.flatMap { (0...10).contains($0) ? $0 : nil }
        if let workoutId {
            guard let wi = workouts.firstIndex(where: { $0.id == workoutId && $0.finishedAt != nil }),
                  let ei = workouts[wi].exercises.firstIndex(where: { $0.id == exerciseId }),
                  let si = workouts[wi].exercises[ei].sets.firstIndex(where: { $0.id == setId && $0.done }) else { return }
            let previous = workouts[wi].exercises[ei].sets[si].rir
            workouts[wi].exercises[ei].sets[si].rir = valid
            if !save() { workouts[wi].exercises[ei].sets[si].rir = previous }
        } else {
            let previous = active
            updateSet(exercise: exerciseId, set: setId) { $0.rir = valid }
            if saveError != nil { active = previous }
        }
    }

    func setTarget(_ kilograms: Double?) {
        let previous = targetKg
        targetKg = kilograms
        if !save() { targetKg = previous }
    }

    func setRest(_ seconds: Int) {
        restSeconds = min(300, max(15, seconds))
        save()
    }

    func setOwned(_ id: String, _ owned: Bool) {
        if owned {
            if !ownedEquipment.contains(id) { ownedEquipment.append(id) }
        } else {
            ownedEquipment.removeAll { $0 == id }
        }
        save()
    }

    func muscleLoad(days: Int, now: Date = Date()) -> [MuscleLoad] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: calendar.startOfDay(for: now)) ?? now
        var totals: [String: Double] = [:]
        for workout in workouts {
            guard let finished = workout.finishedAt, finished >= start else { continue }
            for exercise in workout.exercises {
                let done = exercise.sets.filter(\.done).count
                guard done > 0, let info = Catalogue.byId[exercise.exerciseId] else { continue }
                for (muscle, weight) in info.muscles {
                    totals[muscle, default: 0] += weight * Double(done)
                }
            }
        }
        return totals.map { MuscleLoad(id: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }

    func monthCounts(now: Date = Date(), calendar: Calendar = .current) -> [MonthCount] {
        let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return (0..<12).map { offset in
            let monthsAgo = 11 - offset
            let month = calendar.date(byAdding: .month, value: -monthsAgo, to: startOfThisMonth) ?? startOfThisMonth
            let count = workouts.filter { session in
                guard let finished = session.finishedAt else { return false }
                return calendar.isDate(finished, equalTo: month, toGranularity: .month)
            }.count
            return MonthCount(month: month, count: count)
        }
    }

    func historyExercises() -> [HistoryExercise] {
        var seen: [String: String] = [:]
        for session in workouts.sorted(by: { $0.startedAt > $1.startedAt }) where session.finishedAt != nil {
            for exercise in session.exercises where seen[exercise.exerciseId] == nil {
                seen[exercise.exerciseId] = exercise.name
            }
        }
        return seen.map { HistoryExercise(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func series(for exerciseId: String) -> ExerciseSeries {
        var weighted: [SetPoint] = []
        var reps: [SetPoint] = []
        for session in workouts.sorted(by: { $0.startedAt < $1.startedAt }) where session.finishedAt != nil {
            let sets = session.exercises.filter { $0.exerciseId == exerciseId }.flatMap(\.sets).filter(\.done)
            guard !sets.isEmpty else { continue }
            let bestWeight = sets.map(\.weight).max() ?? 0
            let bestReps = sets.map(\.reps).max() ?? 0
            if bestWeight > 0 { weighted.append(SetPoint(date: session.startedAt, value: bestWeight)) }
            if bestReps > 0 { reps.append(SetPoint(date: session.startedAt, value: Double(bestReps))) }
        }
        if !weighted.isEmpty { return ExerciseSeries(usesReps: false, points: weighted) }
        return ExerciseSeries(usesReps: true, points: reps)
    }

    func weighIns(within days: Int?) -> [WeighIn] {
        let ordered = weighIns.sorted { $0.date < $1.date }
        guard let days, days > 0, let last = ordered.last else { return ordered }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: last.date) ?? last.date
        return ordered.filter { $0.date >= cutoff }
    }

    private func finished(on date: Date, calendar: Calendar = .current) -> [WorkoutSession] {
        workouts.filter { session in
            guard let finished = session.finishedAt else { return false }
            return calendar.isDate(finished, inSameDayAs: date)
        }
    }

    private func nextPlanLabel() -> String? {
        for offset in 1...6 {
            let day = ((todayIndex - 1 + offset) % 7) + 1
            let list = routines(on: day)
            if !list.isEmpty {
                return "下次：\(Weekday.name(day)) · \(list.map(\.name).joined(separator: "、"))"
            }
        }
        return "还没有安排计划"
    }

    private func lastPerformed(_ exerciseId: String) -> WorkoutSet? {
        for session in workouts.sorted(by: { $0.startedAt > $1.startedAt }) where session.finishedAt != nil {
            for exercise in session.exercises where exercise.exerciseId == exerciseId {
                if let done = exercise.sets.last(where: \.done) { return done }
            }
        }
        return nil
    }

    private func updateSet(exercise exerciseId: UUID, set setId: UUID, _ change: (inout WorkoutSet) -> Void) {
        guard var session = active,
              let ei = session.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = session.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        change(&session.exercises[ei].sets[si])
        active = session
        save()
    }

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("openGym", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("gym-state.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            normalizeWeek()
            return
        }
        routines = snapshot.routines
        week = snapshot.week
        workouts = snapshot.workouts
        active = snapshot.active
        weighIns = snapshot.weighIns
        bodyMeasurements = snapshot.bodyMeasurements ?? []
        targetKg = snapshot.targetKg
        restSeconds = min(300, max(15, snapshot.restSeconds))
        ownedEquipment = snapshot.ownedEquipment
        normalizeWeek()
    }

    @discardableResult
    private func save() -> Bool {
        normalizeWeek()
        let snapshot = Snapshot(
            routines: routines,
            week: week,
            workouts: workouts,
            active: active,
            weighIns: weighIns,
            bodyMeasurements: bodyMeasurements,
            targetKg: targetKg,
            restSeconds: restSeconds,
            ownedEquipment: ownedEquipment
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            saveError = nil
            return true
        } catch {
            saveError = "无法保存到此设备：\(error.localizedDescription)"
            return false
        }
    }

    private func normalizeWeek() {
        var next: [DayPlan] = []
        let known = Set(routines.map(\.id.uuidString))
        for day in 1...7 {
            let ids = week.first(where: { $0.day == day })?.routineIds ?? []
            next.append(DayPlan(day: day, routineIds: ids.filter { known.contains($0) }))
        }
        week = next
    }
}
