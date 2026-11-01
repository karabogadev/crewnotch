//
//  SystemNotifier.swift
//  CrewNotch
//
//  macOS notifications for when the notch isn't enough. Clicking one
//  jumps to the session it is about.
//

import AppKit
import UserNotifications

@MainActor
final class SystemNotifier: NSObject {
    static let shared = SystemNotifier()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    /// Asks macOS for permission; returns whether notifications may be shown.
    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func send(_ alert: AttentionAlert) {
        Task {
            let status = await authorizationStatus()
            if status == .notDetermined {
                guard await requestAuthorization() else { return }
            } else if status != .authorized && status != .provisional {
                return
            }
            let content = UNMutableNotificationContent()
            content.title = alert.title
            if let detail = alert.detail, !detail.isEmpty { content.body = detail }
            if let sessionId = alert.sessionId {
                content.threadIdentifier = sessionId
                content.userInfo = ["sessionId": sessionId]
            }
            content.interruptionLevel = alert.kind.isNeedsYou ? .timeSensitive : .active
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}

extension SystemNotifier: UNUserNotificationCenterDelegate {
    /// Show banners even while CrewNotch is the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let sessionId = response.notification.request.content.userInfo["sessionId"] as? String,
              let session = await SessionStore.shared.session(for: sessionId) else { return }
        await MainActor.run {
            if SessionFocuser.canFocus(session) {
                Task { await SessionFocuser.focus(session) }
            } else {
                AppDelegate.shared?.windowController?.viewModel.notchOpen(reason: .click)
            }
        }
    }
}
