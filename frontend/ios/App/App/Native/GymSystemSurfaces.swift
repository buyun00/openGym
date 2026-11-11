import Foundation
import ActivityKit
import WidgetKit
import UIKit
import Observation

@MainActor
@Observable
final class GymRoutes {
    static let shared = GymRoutes()
    var pending: String?
    func receive(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["lingym", "opengym"].contains(scheme), let host = url.host?.lowercased(),
              ["workout", "water", "body", "sync-body"].contains(host) else { return false }
        pending = host
        return true
    }
}

@MainActor
enum GymWidgets {
    static func write(_ change: (inout GymWidgetData) -> Void) {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GymWidgetData.group) != nil,
              let defaults = UserDefaults(suiteName: GymWidgetData.group) else { return }
        var value = GymWidgetData.read()
        let old = value
        change(&value)
        guard value != old, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: GymWidgetData.key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func water(_ state: WellnessState) {
        write {
            $0.waterDay = GymWidgetData.day(Date())
            $0.waterML = state.waterTotal(on: Date())
            $0.waterGoal = state.settings.waterGoalML
        }
    }
}

extension GymStore {
    func refreshSystemSurfaces() {
        GymWidgets.write { value in
            value.weights = weighIns.sorted { $0.date < $1.date }.suffix(30).map {
                GymWidgetData.Weight(date: $0.date, kilograms: $0.kilograms)
            }
            value.plans = [:]
            for offset in 0..<8 {
                guard let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) else { continue }
                let key = WellnessDay.key(date)
                let chosen: [Routine]
                if let ids = dayPlan[key] {
                    chosen = ids.compactMap { id in routines.first { $0.id.uuidString == id } }
                } else { chosen = routines(on: Weekday.index(for: date)) }
                let done = workouts.contains { session in
                    session.finishedAt.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
                }
                value.plans[GymWidgetData.day(date)] = .init(
                    title: chosen.isEmpty ? "休息日" : chosen.map(\.name).joined(separator: "、"),
                    done: done, active: offset == 0 && active != nil)
            }
        }
        liveActivity.refresh(active)
    }
}

/// Serialized, coalesced local updates only; no per-second timer or APNs entitlement.
@MainActor
@Observable
final class TrainingLiveActivity {
    private var desired: WorkoutSession?
    private var revision = 0
    private var worker: Task<Void, Never>?
    private var lastUpdate = Date.distantPast
    private(set) var errorMessage: String?

    func refresh(_ session: WorkoutSession?) {
        desired = session
        revision += 1
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            repeat {
                let seen = self.revision
                await self.reconcile()
                if seen == self.revision { break }
            } while !Task.isCancelled
            self.worker = nil
        }
    }

    private func reconcile() async {
        let session = desired
        for activity in Activity<TrainingActivityAttributes>.activities where activity.attributes.sessionID != session?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let session, desired == session else { return }
        let countdown = countdown(for: session, now: .now)
        let exercise = session.exercises.first { $0.id == countdown?.exerciseID }
            ?? session.exercises.first { $0.id == session.selectedExerciseId }
            ?? session.exercises.first
        let state = TrainingActivityAttributes.ContentState(exercise: exercise?.name ?? "选择动作开始训练",
            completed: exercise?.sets.filter(\.done).count ?? 0, total: exercise?.sets.count ?? 0, countdown: countdown?.value)
        let content = ActivityContent(state: state, staleDate: state.countdown?.end)
        if let activity = Activity<TrainingActivityAttributes>.activities.first(where: { $0.attributes.sessionID == session.id }) {
            guard state != activity.content.state else { return }
            let delay = max(0, 1 - Date().timeIntervalSince(lastUpdate))
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            // A later event will be reconciled by the worker; do not send stale content.
            guard desired == session else { return }
            await activity.update(content)
        } else {
            guard UIApplication.shared.applicationState == .active,
                  ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            do {
                _ = try Activity.request(attributes: TrainingActivityAttributes(sessionID: session.id, name: session.name),
                                         content: content, pushType: nil)
                errorMessage = nil
            } catch { errorMessage = error.localizedDescription; return }
        }
        lastUpdate = Date()
    }

    private func countdown(for session: WorkoutSession, now: Date)
        -> (value: TrainingActivityAttributes.Countdown, exerciseID: UUID?)? {
        let cardio = WorkoutLogic.activeCardioTimer(in: session)
        if let end = session.restEndsAt, end > now, (cardio?.end ?? .distantPast) <= now {
            let owner = session.exercises.first { $0.id == session.restOwner }
            let start = owner?.sets.first { $0.id == session.restSetOwner }?.completedAt
                ?? max(session.startedAt, end.addingTimeInterval(-90))
            return (.init(kind: .rest, start: start, end: end), session.restOwner)
        }
        if let cardio {
            return (.init(kind: .cardio, start: cardio.start, end: cardio.end), cardio.exerciseID)
        }
        return nil
    }
}
