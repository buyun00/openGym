import Foundation
import UIKit
import UserNotifications
import AudioToolbox

extension Notification.Name {
    static let workoutRestFinished = Notification.Name("openGym.workoutRestFinished")
}

@MainActor
final class WorkoutRestAlerts {
    nonisolated static let identifier = "opengym.workout.rest"
    nonisolated static let deadlineKey = "restDeadline"
    static var foregroundSince = Date.distantPast

    private static let soundName = "WorkoutRestChime.wav"
    private static let chime: SystemSoundID? = {
        guard let url = Bundle.main.url(forResource: soundName, withExtension: nil) else { return nil }
        var id: SystemSoundID = 0
        return AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError ? id : nil
    }()

    private var sleeper: Task<Void, Never>?
    private var scheduling: Task<Bool, Never>?
    private var deadline: Date?
    private var sound = false
    private var haptics = false

    static func shouldPresentInForeground(at end: Date) -> Bool {
        let lateness = Date().timeIntervalSince(end)
        return UIApplication.shared.applicationState == .active
            && end >= foregroundSince && lateness >= 0 && lateness < 2
    }

    func update(end: Date?, preferences: WorkoutPreferences, reschedule: Bool,
                completed: @escaping @MainActor () -> Void) {
        haptics = preferences.haptics
        guard scheduling == nil || deadline != end || sound != preferences.sound || reschedule else { return }
        let expired = deadline.map { $0 <= Date() } ?? false
        deadline = end
        sound = preferences.sound
        sleeper?.cancel()

        // Clearing an elapsed timer must leave its one-shot system delivery intact.
        if end == nil && expired { return }
        let previous = scheduling
        previous?.cancel()
        let delivery = Task {
            // A superseded add must finish before its replacement removes the old request.
            _ = await previous?.value
            guard !Task.isCancelled else { return false }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            guard let end, end.timeIntervalSinceNow > 0 else { return false }
            let settings = await center.notificationSettings()
            let remaining = end.timeIntervalSinceNow
            guard !Task.isCancelled, remaining > 0,
                  settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return false }
            let usesSystemSound = preferences.sound && settings.authorizationStatus == .authorized && settings.soundSetting == .enabled
            let content = UNMutableNotificationContent()
            content.title = "休息结束"
            content.body = "准备好后开始下一组。"
            content.userInfo[Self.deadlineKey] = end.timeIntervalSince1970
            if usesSystemSound { content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: Self.soundName)) }
            do {
                try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)))
                return usesSystemSound
            } catch {
                return false
            }
        }
        scheduling = delivery
        guard let end, end.timeIntervalSinceNow > 0 else { return }
        sleeper = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) } catch { return }
            let usesSystemSound = await delivery.value
            guard !Task.isCancelled, let self, UIApplication.shared.applicationState == .active else { return }
            if Self.shouldPresentInForeground(at: end) {
                if preferences.sound && !usesSystemSound, let chime = Self.chime { AudioServicesPlaySystemSound(chime) }
                if self.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                NotificationCenter.default.post(name: .workoutRestFinished, object: nil)
            }
            completed()
        }
    }
}
