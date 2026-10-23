import Foundation
import UIKit
import UserNotifications
import AudioToolbox

extension Notification.Name {
    static let workoutRestFinished = Notification.Name("openGym.workoutRestFinished")
}

@MainActor
final class WorkoutRestAlerts {
    private var sleeper: Task<Void, Never>?
    private var scheduling: Task<Void, Never>?
    private let identifier = "opengym.workout.rest"

    func update(end: Date?, preferences: WorkoutPreferences, completed: @escaping @MainActor () -> Void) {
        sleeper?.cancel()
        let previous = scheduling
        previous?.cancel()
        scheduling = Task {
            // A superseded add must finish before its replacement removes the old request.
            await previous?.value
            guard !Task.isCancelled else { return }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            guard let end, end.timeIntervalSinceNow > 0 else { return }
            let status = await center.notificationSettings().authorizationStatus
            guard !Task.isCancelled, status == .authorized || status == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "休息结束"
            content.body = "准备好后开始下一组。"
            if preferences.sound { content.sound = .default }
            do {
                try await center.add(UNNotificationRequest(identifier: identifier, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)))
            } catch {
                // Foreground timer remains available even when the system rejects a notification.
            }
        }
        guard let end else { return }
        sleeper = Task {
            do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) } catch { return }
            guard !Task.isCancelled else { return }
            // In the background the scheduled system notification owns delivery. Removing it
            // from a waking in-process timer could race and suppress the lock-screen alert.
            guard UIApplication.shared.applicationState == .active else { return }
            if Date().timeIntervalSince(end) < 5 {
                if preferences.sound { AudioServicesPlaySystemSound(1005) }
                if preferences.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                NotificationCenter.default.post(name: .workoutRestFinished, object: nil)
            }
            completed()
        }
    }
}
