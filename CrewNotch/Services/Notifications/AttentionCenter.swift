//
//  AttentionCenter.swift
//  CrewNotch
//
//  Sends what needs you beyond the notch: macOS notifications and pushes
//  to your phone through ntfy, each either always or only while you're
//  away from the Mac. The notch's own sounds and banners are separate.
//

import AppKit
import Combine
import CoreGraphics

/// Something worth telling the user about.
nonisolated struct AttentionAlert: Sendable {
    nonisolated enum Kind: Sendable {
        case approval, question, finished, usage

        var isNeedsYou: Bool { self == .approval || self == .question }
    }

    let kind: Kind
    let title: String
    /// Project, request or message: shown on the Mac, sent to the phone only when allowed.
    let detail: String?
    var sessionId: String? = nil
    /// The approval or question this is about, so its notification can be withdrawn once answered.
    var requestId: String? = nil

    init(kind: Kind, title: String, detail: String?, sessionId: String? = nil, requestId: String? = nil) {
        self.kind = kind
        self.title = title
        // Pushes have a size limit, and a notification is no place for a whole reply
        self.detail = detail.map { $0.count > 200 ? String($0.prefix(199)) + "…" : $0 }
        self.sessionId = sessionId
        self.requestId = requestId
    }
}

@MainActor
final class AttentionCenter {
    static let shared = AttentionCenter()

    private var previousPhases: [String: SessionPhase] = [:]
    private var hasBaseline = false
    private var cancellable: AnyCancellable?

    private init() {}

    func start() {
        guard cancellable == nil else { return }
        cancellable = SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.sessionsChanged($0) }
    }

    // MARK: - Session changes

    private func sessionsChanged(_ sessions: [SessionState]) {
        defer {
            previousPhases = Dictionary(sessions.map { ($0.sessionId, $0.phase) }, uniquingKeysWith: { _, new in new })
            hasBaseline = true
        }
        // Sessions already running at launch aren't news
        guard hasBaseline else { return }

        for session in sessions {
            let old = previousPhases[session.sessionId]
            // Answered (anywhere): its notification is no longer news
            if let answered = old?.activePermissionId, answered != session.activePermission?.toolUseId {
                SystemNotifier.shared.withdraw(requestId: answered)
            }
            if let permission = session.activePermission, old?.activePermissionId != permission.toolUseId {
                let isQuestion = permission.toolName == "AskUserQuestion"
                post(AttentionAlert(
                    kind: isQuestion ? .question : .approval,
                    title: isQuestion
                        ? String(localized: "\(session.agent.displayName) has a question")
                        : String(localized: "\(session.agent.displayName) needs your approval"),
                    detail: [session.projectName, isQuestion ? nil : session.pendingToolInput]
                        .compactMap { $0 }.joined(separator: " · "),
                    sessionId: session.sessionId,
                    requestId: permission.toolUseId
                ), session: session)
            } else if session.phase == .waitingForInput, old?.isActive == true {
                let title = session.agent == .command
                    ? String(localized: "Command finished")
                    : String(localized: "\(session.agent.displayName) finished")
                post(AttentionAlert(
                    kind: .finished,
                    title: title,
                    detail: [session.displayTitle, session.lastMessageRole == "assistant" ? session.lastMessage : nil]
                        .compactMap { $0 }.joined(separator: " · "),
                    sessionId: session.sessionId
                ), session: session)
            }
        }
    }

    // MARK: - Delivery

    /// Sends an alert through every channel the user turned on for its kind.
    func post(_ alert: AttentionAlert, session: SessionState? = nil) {
        guard isWanted(alert.kind) else { return }
        let away = AwayDetector.isAway(afterMinutes: AppSettings.awayAfterMinutes)
        let toMac = Self.allows(AppSettings.macNotifications, away: away)
        let toPhone = Self.allows(AppSettings.phoneNotifications, away: away) && !AppSettings.ntfyTopic.isEmpty
        guard toMac || toPhone else { return }

        Task {
            // A finished turn you're already looking at needs no notification
            if alert.kind == .finished, !away, let session, await SessionFocuser.isFocused(session) { return }
            if toMac { SystemNotifier.shared.send(alert) }
            if toPhone { await PhoneNotifier.send(alert) }
        }
    }

    private func isWanted(_ kind: AttentionAlert.Kind) -> Bool {
        switch kind {
        case .approval, .question: return AppSettings.notifyNeedsYou
        case .finished: return AppSettings.notifyFinished
        case .usage: return AppSettings.notifyUsageAlerts
        }
    }

    private static func allows(_ delivery: NotificationDelivery, away: Bool) -> Bool {
        switch delivery {
        case .off: return false
        case .whenAway: return away
        case .always: return true
        }
    }
}

private extension SessionPhase {
    var activePermissionId: String? {
        if case .waitingForApproval(let context) = self { return context.toolUseId }
        return nil
    }
}

/// Whether the user has stepped away: no input for a while, or the screen is locked.
nonisolated enum AwayDetector {
    static func isAway(afterMinutes minutes: Int) -> Bool {
        if isScreenLocked { return true }
        return idleSeconds >= Double(max(1, minutes)) * 60
    }

    static var idleSeconds: Double {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    static var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
