import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class WellnessNotifications {
    private(set) var authorization: UNAuthorizationStatus?
    private(set) var message = "正在读取通知权限"
    private(set) var scheduledCount = 0
    private(set) var scheduledThrough: Date?
    @ObservationIgnored private var scheduling: Task<Void, Never>?
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    var allowed: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }

    var authorizationLabel: String {
        guard let authorization else { return "读取中" }
        switch authorization {
        case .notDetermined: return "尚未请求"
        case .denied: return "未授权"
        case .authorized: return "已授权"
        case .provisional: return "已静默授权"
        case .ephemeral: return "已临时授权"
        @unknown default: return "未知状态"
        }
    }

    func requestPermission() async -> Bool {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        if authorization == .notDetermined {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
            catch { message = "通知权限请求失败：\(error.localizedDescription)"; return false }
            authorization = await center.notificationSettings().authorizationStatus
        }
        if !allowed { message = "通知未获授权，可在系统设置中开启" }
        return allowed
    }

    func reconcile(state: WellnessState, now: Date) {
        let previous = scheduling
        previous?.cancel()
        scheduling = Task {
            // Serialize replacement: an old add() that is already in flight must finish before removal.
            await previous?.value
            guard !Task.isCancelled else { return }
            let settings = await center.notificationSettings()
            guard !Task.isCancelled else { return }
            authorization = settings.authorizationStatus
            let pending = await center.pendingNotificationRequests()
            guard !Task.isCancelled else { return }
            let owned = pending.filter { $0.identifier.hasPrefix(WellnessReminderPlan.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: owned.map(\.identifier))
            scheduledCount = 0
            scheduledThrough = nil
            guard allowed else {
                message = authorization == .denied ? "通知未获授权，可在系统设置中开启" : "提醒尚未授权"
                return
            }
            let plan = WellnessReminderPlan.make(state: state, now: now)
            // Leave room for unrelated notifications, including the existing workout timer.
            let available = max(0, 64 - (pending.count - owned.count))
            do {
                for reminder in plan.prefix(available) {
                    guard !Task.isCancelled else { return }
                    let content = UNMutableNotificationContent()
                    content.title = reminder.title
                    content.body = reminder.body
                    content.sound = .default
                    content.threadIdentifier = "opengym.wellness"
                    var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
                    components.timeZone = .current
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
                    guard !Task.isCancelled else { return }
                    scheduledCount += 1
                    scheduledThrough = reminder.date
                }
                if plan.count > available {
                    message = "系统提醒名额不足，已安排最近 \(scheduledCount) 条"
                } else if scheduledCount > 0 {
                    message = "已安排 \(scheduledCount) 条提醒"
                } else {
                    message = "没有待发送的提醒"
                }
            } catch {
                message = "部分提醒未能安排：\(error.localizedDescription)"
            }
        }
    }
}
