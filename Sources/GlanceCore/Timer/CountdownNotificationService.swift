import Foundation
import UserNotifications

@MainActor
final class CountdownNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter?
    private var requestIdentifier: String?
    private var scheduling: Task<Void, Never>?
    var onResponse: ((Bool) -> Void)?
    var onUnavailable: ((Bool) -> Void)?
    private static let identifier = "glance.countdown"

    override init() {
        // UserNotifications requires an application bundle; SwiftPM test executables are not apps.
        center = Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
        super.init()
        center?.delegate = self
    }

    func schedule(deadline: Date?, title: String, body: String, done: String) {
        scheduling?.cancel()
        guard let center else { onUnavailable?(true); return }
        if let requestIdentifier {
            center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
            center.removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
        }
        requestIdentifier = nil
        guard let deadline else { return }
        let identifier = Self.identifier + "." + UUID().uuidString
        requestIdentifier = identifier
        scheduling = Task { [weak self] in
            guard let self else { return }
            do {
                // Remove timers left by a previous process before installing this process's request.
                let pending: [String] = await withCheckedContinuation { continuation in
                    center.getPendingNotificationRequests { @Sendable requests in
                        continuation.resume(returning: requests.map(\.identifier))
                    }
                }
                let delivered: [String] = await withCheckedContinuation { continuation in
                    center.getDeliveredNotifications { @Sendable notifications in
                        continuation.resume(returning: notifications.map { $0.request.identifier })
                    }
                }
                guard !Task.isCancelled else { return }
                center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix(Self.identifier) })
                center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.hasPrefix(Self.identifier) })
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard !Task.isCancelled else { return }
                let alertsEnabled: Bool = await withCheckedContinuation { continuation in
                    center.getNotificationSettings { @Sendable settings in
                        continuation.resume(returning: settings.alertSetting == .enabled)
                    }
                }
                guard !Task.isCancelled else { return }
                onUnavailable?(!granted || !alertsEnabled)
                guard granted else { return }
                let action = UNNotificationAction(identifier: "timer.done", title: done, options: [])
                center.setNotificationCategories([UNNotificationCategory(identifier: "timer", actions: [action], intentIdentifiers: [], options: [])])
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.categoryIdentifier = "timer"
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                try await center.add(request)
                if Task.isCancelled { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
            } catch {
                guard !Task.isCancelled else { return }
                onUnavailable?(true)
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        let isDone = response.actionIdentifier == "timer.done"
        Task { @MainActor [weak self] in self?.onResponse?(isDone) }
        completionHandler()
    }
}
