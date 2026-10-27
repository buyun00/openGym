import Foundation
import HealthKit

/// One-shot reads only. Never writes health samples or starts a live workout session.
@MainActor
final class WorkoutHealthReader {
    private let store = HKHealthStore()
    private let heart = HKQuantityType(.heartRate)
    private let energy = HKQuantityType(.activeEnergyBurned)

    func read(start: Date, end: Date, requestPermission: Bool) async -> WorkoutHealth {
        var result = WorkoutHealth(status: "no_data", window_start: start.timeIntervalSince1970 * 1000,
                                   window_end: end.timeIntervalSince1970 * 1000,
                                   queried_at: Date().timeIntervalSince1970 * 1000)
        guard end > start, HKHealthStore.isHealthDataAvailable() else {
            result.status = "unavailable"; return result
        }
        do {
            if requestPermission {
                try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType(), heart, energy])
            }
            let window = HKQuery.predicateForSamples(withStart: start, end: end,
                                                     options: [.strictStartDate, .strictEndDate])
            // A nearby workout must cover >=80% of BOTH intervals; adjacent sessions must not match.
            let candidates = try await workouts(start: start, end: end)
            let duration = end.timeIntervalSince(start)
            let matched = candidates.filter {
                let overlap = min(end, $0.endDate).timeIntervalSince(max(start, $0.startDate))
                return overlap / duration >= 0.8 && overlap / max(1, $0.endDate.timeIntervalSince($0.startDate)) >= 0.8
            }.max { a, b in
                min(end, a.endDate).timeIntervalSince(max(start, a.startDate)) <
                min(end, b.endDate).timeIntervalSince(max(start, b.startDate))
            }
            result.workout_id = matched?.uuid.uuidString
            // Heart samples can exist without a saved Apple Watch workout.
            var heartPredicate = window
            if let matched {
                heartPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [window,
                    HKQuery.predicateForObjects(from: matched.sourceRevision.source)])
            }
            let bpm = HKUnit.count().unitDivided(by: .minute())
            var hr = try await statistics(heart, predicate: heartPredicate, options: [.discreteAverage, .discreteMax])
            // Imported workouts can have a different source from the watch/chest sensor.
            if matched != nil && hr?.averageQuantity() == nil {
                hr = try await statistics(heart, predicate: window, options: [.discreteAverage, .discreteMax])
            }
            result.heart_rate_avg_bpm = hr?.averageQuantity()?.doubleValue(for: bpm)
            result.heart_rate_max_bpm = hr?.maximumQuantity()?.doubleValue(for: bpm)
            if let matched {
                let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [window,
                    HKQuery.predicateForObjects(from: matched)])
                let calories = try await statistics(energy, predicate: predicate, options: .cumulativeSum)
                result.active_energy_kcal = calories?.sumQuantity()?.doubleValue(for: .kilocalorie())
            }
            result.status = result.heart_rate_avg_bpm != nil || result.active_energy_kcal != nil || matched != nil ? "available" : "no_data"
        } catch {
            // Read denial is deliberately indistinguishable from no samples in HealthKit.
            // Preserve partial values if a later query fails; never substitute zero.
            result.status = "query_failed"
        }
        return result
    }

    private func workouts(start: Date, end: Date) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let gate = HealthQueryGate(continuation)
            let query = HKSampleQuery(sampleType: .workoutType(),
                                      predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { gate.resolve(.failure(error)) }
                else { gate.resolve(.success(samples as? [HKWorkout] ?? [])) }
            }
            store.execute(query)
            timeout(query, gate: gate)
        }
    }

    private func statistics(_ type: HKQuantityType, predicate: NSPredicate,
                            options: HKStatisticsOptions) async throws -> HKStatistics? {
        try await withCheckedThrowingContinuation { continuation in
            let gate = HealthQueryGate(continuation)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, stats, error in
                if let error = error as? HKError, error.code == .errorNoData { gate.resolve(.success(nil)) }
                else if let error { gate.resolve(.failure(error)) }
                else { gate.resolve(.success(stats)) }
            }
            store.execute(query)
            timeout(query, gate: gate)
        }
    }

    private func timeout<T>(_ query: HKQuery, gate: HealthQueryGate<T>) {
        // Authorization has no timer: the user decides. Data queries must not block saving forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if gate.resolve(.failure(NSError(domain: "OpenGym.HealthKit", code: 1,
                                             userInfo: [NSLocalizedDescriptionKey: "健康数据读取超时"]))) {
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
