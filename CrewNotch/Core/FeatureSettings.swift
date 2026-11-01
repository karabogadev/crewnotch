//
//  FeatureSettings.swift
//  CrewNotch
//
//  Keys and defaults for the optional features: approvals, keyboard,
//  privacy, session list extras, notifications away from the notch and
//  usage alerts. Views bind with @AppStorage(FeatureKeys.x); other code
//  reads through AppSettings.
//

import Foundation

nonisolated enum FeatureKeys {
    // Approvals
    static let showApprovalDetails = "showApprovalDetails"
    static let warnRiskyCommands = "warnRiskyCommands"
    static let offerAlwaysAllow = "offerAlwaysAllow"
    static let answerQuestionsInNotch = "answerQuestionsInNotch"

    // Keyboard
    static let hotkey = "notchHotkey"
    static let panelShortcuts = "panelShortcuts"
    static let shortcutsExpanded = "shortcutsExpanded"

    // App
    static let showInDock = "showInDock"

    // Privacy
    static let hideFromScreenSharing = "hideFromScreenSharing"

    // Session list
    static let showGitBranch = "showGitBranch"
    static let showTaskProgress = "showTaskProgress"
    static let contextFill = "contextFillDisplay"
    static let stalledAfterMinutes = "stalledAfterMinutes"
    static let showRecentSessions = "showRecentSessions"
    static let resumeTerminal = "resumeTerminal"

    // Commands run through `crewnotch run`
    static let showCommandSessions = "showCommandSessions"

    // Notifications away from the notch
    static let macNotifications = "macNotifications"
    static let phoneNotifications = "phoneNotifications"
    static let ntfyServer = "ntfyServer"
    static let ntfyTopic = "ntfyTopic"
    static let phoneIncludesDetails = "phoneIncludesDetails"
    static let awayAfterMinutes = "awayAfterMinutes"
    static let notifyNeedsYou = "notifyNeedsYou"
    static let notifyFinished = "notifyFinished"
    static let notifyUsageAlerts = "notifyUsageAlerts"

    // Usage alerts
    static let usageAlerts = "usageAlertsEnabled"
    static let usageWarnPercent = "usageWarnPercent"
    static let usageCriticalPercent = "usageCriticalPercent"
    static let usageResetAlerts = "usageResetAlerts"
}

/// When a notification goes out through a channel outside the notch.
nonisolated enum NotificationDelivery: String, CaseIterable, Identifiable {
    case off, whenAway, always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return String(localized: "Off")
        case .whenAway: return String(localized: "When I'm away")
        case .always: return String(localized: "Always")
        }
    }
}

/// When a session row shows how full the agent's context window is.
nonisolated enum ContextFillDisplay: String, CaseIterable, Identifiable {
    case always, aboveHalf, aboveMost, never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: return String(localized: "Always")
        case .aboveHalf: return String(localized: "Above 50%")
        case .aboveMost: return String(localized: "Above 80%")
        case .never: return String(localized: "Never")
        }
    }

    /// Lowest fill (0...1) that is shown, or nil when never shown.
    var threshold: Double? {
        switch self {
        case .always: return 0
        case .aboveHalf: return 0.5
        case .aboveMost: return 0.8
        case .never: return nil
        }
    }
}

/// Terminal that opens when resuming an ended session.
nonisolated enum ResumeTerminal: String, CaseIterable, Identifiable {
    case automatic, terminal, iTerm, ghostty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return String(localized: "Automatic")
        case .terminal: return "Terminal"
        case .iTerm: return "iTerm2"
        case .ghostty: return "Ghostty"
        }
    }
}

extension AppSettings {
    private static var store: UserDefaults { .standard }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        store.object(forKey: key) as? Bool ?? value
    }

    private static func int(_ key: String, default value: Int) -> Int {
        store.object(forKey: key) as? Int ?? value
    }

    // MARK: Approvals

    static var showApprovalDetails: Bool { bool(FeatureKeys.showApprovalDetails, default: true) }
    static var warnRiskyCommands: Bool { bool(FeatureKeys.warnRiskyCommands, default: true) }
    static var offerAlwaysAllow: Bool { bool(FeatureKeys.offerAlwaysAllow, default: true) }
    static var answerQuestionsInNotch: Bool { bool(FeatureKeys.answerQuestionsInNotch, default: true) }

    // MARK: Keyboard

    static var panelShortcuts: Bool { bool(FeatureKeys.panelShortcuts, default: true) }
    static var showInDock: Bool { bool(FeatureKeys.showInDock, default: true) }

    // MARK: Privacy

    static var hideFromScreenSharing: Bool { bool(FeatureKeys.hideFromScreenSharing, default: false) }

    // MARK: Session list

    static var stalledAfterMinutes: Int { int(FeatureKeys.stalledAfterMinutes, default: 10) }
    static var showRecentSessions: Bool { bool(FeatureKeys.showRecentSessions, default: true) }

    static var resumeTerminal: ResumeTerminal {
        store.string(forKey: FeatureKeys.resumeTerminal).flatMap(ResumeTerminal.init(rawValue:)) ?? .automatic
    }

    // MARK: Commands

    static var showCommandSessions: Bool { bool(FeatureKeys.showCommandSessions, default: true) }

    // MARK: Notifications away from the notch

    static var macNotifications: NotificationDelivery {
        store.string(forKey: FeatureKeys.macNotifications).flatMap(NotificationDelivery.init(rawValue:)) ?? .off
    }

    static var phoneNotifications: NotificationDelivery {
        store.string(forKey: FeatureKeys.phoneNotifications).flatMap(NotificationDelivery.init(rawValue:)) ?? .off
    }

    static var ntfyServer: String {
        let value = store.string(forKey: FeatureKeys.ntfyServer)?.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? "https://ntfy.sh" : value
    }

    static var ntfyTopic: String {
        store.string(forKey: FeatureKeys.ntfyTopic)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    static var phoneIncludesDetails: Bool { bool(FeatureKeys.phoneIncludesDetails, default: false) }
    static var awayAfterMinutes: Int { int(FeatureKeys.awayAfterMinutes, default: 5) }
    static var notifyNeedsYou: Bool { bool(FeatureKeys.notifyNeedsYou, default: true) }
    static var notifyFinished: Bool { bool(FeatureKeys.notifyFinished, default: true) }
    static var notifyUsageAlerts: Bool { bool(FeatureKeys.notifyUsageAlerts, default: true) }

    // MARK: Usage alerts

    static var usageAlerts: Bool { bool(FeatureKeys.usageAlerts, default: true) }
    static var usageWarnPercent: Int { int(FeatureKeys.usageWarnPercent, default: 80) }
    static var usageCriticalPercent: Int { int(FeatureKeys.usageCriticalPercent, default: 95) }
    static var usageResetAlerts: Bool { bool(FeatureKeys.usageResetAlerts, default: true) }
}
