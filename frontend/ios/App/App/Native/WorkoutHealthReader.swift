import Foundation
import HealthKit

/// Reads only explicitly selected workouts. Never writes samples or starts a live session.
@MainActor
final class WorkoutHealthReader {
    private let store = HKHealthStore()
    private let heart = HKQuantityType(.heartRate)
    private let energy = HKQuantityType(.activeEnergyBurned)

    /// Listing/previewing never attaches data. Only an explicit choice can be saved.
    func recent(around date: Date) async throws -> [HKWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "OpenGym.HealthKit", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "此设备无法读取健康数据"])
        }
        try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType(), heart, energy])
        let end = min(Date(), date.addingTimeInterval(86400))
        return try await workouts(start: date.addingTimeInterval(-7 * 86400), end: end)
    }

    /// Read exactly the user's selected workout; never search for a replacement workout.
    func readForCompletion(_ workout: HKWorkout) async throws -> WorkoutHealth {
        // HKWorkout can sync before its samples. Retry only the user's exact selection.
        let deadline = Date().addingTimeInterval(20)
        var result = try await read(workout, deadline: deadline)
        while result.heart_rate_avg_bpm == nil || result.heart_rate_max_bpm == nil || result.active_energy_kcal == nil {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            try await Task.sleep(for: .seconds(min(2, remaining)))
            try Task.checkCancellation()
            guard Date() < deadline else { break }
            let latest: WorkoutHealth
            do { latest = try await read(workout, deadline: deadline) }
            catch {
                let failure = error as NSError
                // A timed-out retry must not discard readings already obtained for this choice.
                if failure.domain == "OpenGym.HealthKit" && failure.code == 1 { break }
                throw error
            }
            result.heart_rate_avg_bpm = latest.heart_rate_avg_bpm ?? result.heart_rate_avg_bpm
            result.heart_rate_max_bpm = latest.heart_rate_max_bpm ?? result.heart_rate_max_bpm
            result.active_energy_kcal = latest.active_energy_kcal ?? result.active_energy_kcal
            result.queried_at = latest.queried_at
        }
        if result.heart_rate_avg_bpm != nil || result.active_energy_kcal != nil { result.status = "available" }
        try Task.checkCancellation()
        return result
    }

    func read(_ workout: HKWorkout, deadline: Date? = nil) async throws -> WorkoutHealth {
        let start = workout.startDate, end = workout.endDate
        let window = HKQuery.predicateForSamples(withStart: start, end: end,
                                                 options: [.strictStartDate, .strictEndDate])
        let associated = NSCompoundPredicate(andPredicateWithSubpredicates: [window,
            HKQuery.predicateForObjects(from: workout)])
        var hr = try await statistics(heart, predicate: associated, options: [.discreteAverage, .discreteMax], deadline: deadline)
        if hr?.averageQuantity() == nil {
            let source = NSCompoundPredicate(andPredicateWithSubpredicates: [window,
                HKQuery.predicateForObjects(from: workout.sourceRevision.source)])
            hr = try await statistics(heart, predicate: source, options: [.discreteAverage, .discreteMax], deadline: deadline)
        }
        let calories = try await statistics(energy, predicate: associated, options: .cumulativeSum, deadline: deadline)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var result = WorkoutHealth(status: "available", window_start: start.timeIntervalSince1970 * 1000,
                                   window_end: end.timeIntervalSince1970 * 1000,
                                   queried_at: Date().timeIntervalSince1970 * 1000)
        result.workout_id = workout.uuid.uuidString
        result.heart_rate_avg_bpm = hr?.averageQuantity()?.doubleValue(for: bpm)
        result.heart_rate_max_bpm = hr?.maximumQuantity()?.doubleValue(for: bpm)
        result.active_energy_kcal = calories?.sumQuantity()?.doubleValue(for: .kilocalorie())
            ?? workout.statistics(for: energy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        if result.heart_rate_avg_bpm == nil && result.active_energy_kcal == nil { result.status = "no_data" }
        return result
    }

    private func workouts(start: Date, end: Date) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let gate = HealthQueryGate(continuation)
            let query = HKSampleQuery(sampleType: .workoutType(),
                                      predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                      limit: 30, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { gate.resolve(.failure(error)) }
                else { gate.resolve(.success(samples as? [HKWorkout] ?? [])) }
            }
            store.execute(query)
            timeout(query, gate: gate)
        }
    }

    private func statistics(_ type: HKQuantityType, predicate: NSPredicate,
                            options: HKStatisticsOptions, deadline: Date? = nil) async throws -> HKStatistics? {
        try Task.checkCancellation()
        if let deadline, deadline <= Date() { throw queryTimeoutError }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = HealthQueryGate(continuation)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, stats, error in
                if let error = error as? HKError, error.code == .errorNoData { gate.resolve(.success(nil)) }
                else if let error { gate.resolve(.failure(error)) }
                else { gate.resolve(.success(stats)) }
            }
            store.execute(query)
            timeout(query, gate: gate, deadline: deadline)
        }
    }

    private var queryTimeoutError: NSError {
        NSError(domain: "OpenGym.HealthKit", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "健康数据读取超时"])
    }

    private func timeout<T>(_ query: HKQuery, gate: HealthQueryGate<T>, deadline: Date? = nil) {
        // Authorization has no timer: the user decides. Data queries must not block saving forever.
        // All completion queries share the same budget, including an in-flight final retry.
        let seconds = min(10, max(0, deadline?.timeIntervalSinceNow ?? 10))
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if gate.resolve(.failure(self.queryTimeoutError)) {
                self.store.stop(query)
            }
        }
    }
}

/// HealthKit callbacks and timeout race; resume the awaiting operation exactly once.
private final class HealthQueryGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }
    @discardableResult func resolve(_ result: Result<T, Error>) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
        return pending != nil
    }
}
