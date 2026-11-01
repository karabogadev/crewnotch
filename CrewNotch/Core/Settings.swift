//
//  Settings.swift
//  CrewNotch
//
//  App settings manager using UserDefaults
//

import Foundation

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

nonisolated enum AppSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let claudeDirectoryName = "claudeDirectoryName"
        static let approveFromNotch = "approveFromNotch"
        static let connectedAgents = "connectedAgents"
        static let keepAwakeEnabled = "keepAwakeEnabled"
        static let keepAwakeMaxHours = "keepAwakeMaxHours"
        static let keepAwakeMinBattery = "keepAwakeMinBattery"
        static let keepAwakeRequiresAdapter = "keepAwakeRequiresAdapter"
        static let showPlanUsage = "showPlanUsage"
        static let claudeUsageAllowed = "claudeUsageAllowed"
        static let attentionSound = "attentionSound"
        static let groupByProject = "groupByProject"
        static let openNotchOnRequest = "openNotchOnRequest"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    // MARK: - Notifications

    /// Sound when an agent needs you (approval or question).
    static var attentionSound: NotificationSound {
        get { defaults.string(forKey: Keys.attentionSound).flatMap(NotificationSound.init(rawValue:)) ?? .glass }
        set { defaults.set(newValue.rawValue, forKey: Keys.attentionSound) }
    }

    /// Open the notch automatically when an agent asks for approval.
    static var openNotchOnRequest: Bool {
        get { defaults.object(forKey: Keys.openNotchOnRequest) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.openNotchOnRequest) }
    }

    // MARK: - Appearance

    /// List sessions under their project.
    static var groupByProject: Bool {
        get { defaults.object(forKey: Keys.groupByProject) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.groupByProject) }
    }

    // MARK: - Onboarding

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    // MARK: - Plan Usage

    /// Show each provider's plan usage at the bottom of the notch.
    static var showPlanUsage: Bool {
        get { defaults.object(forKey: Keys.showPlanUsage) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showPlanUsage) }
    }

    /// The user agreed to let CrewNotch read Claude Code's sign-in from the
    /// keychain (macOS asks once) to fetch Claude plan usage.
    static var claudeUsageAllowed: Bool {
        get { defaults.bool(forKey: Keys.claudeUsageAllowed) }
        set { defaults.set(newValue, forKey: Keys.claudeUsageAllowed) }
    }

    // MARK: - Keep Awake

    /// Keep the Mac from sleeping (display may sleep) so agents keep running.
    static var keepAwakeEnabled: Bool {
        get { defaults.bool(forKey: Keys.keepAwakeEnabled) }
        set { defaults.set(newValue, forKey: Keys.keepAwakeEnabled) }
    }

    /// Keep Awake switches itself off after this many hours.
    static var keepAwakeMaxHours: Int {
        get { defaults.object(forKey: Keys.keepAwakeMaxHours) as? Int ?? 3 }
        set { defaults.set(newValue, forKey: Keys.keepAwakeMaxHours) }
    }

    /// On battery, let the Mac sleep below this charge level.
    static var keepAwakeMinBattery: Int {
        get { defaults.object(forKey: Keys.keepAwakeMinBattery) as? Int ?? 20 }
        set { defaults.set(newValue, forKey: Keys.keepAwakeMinBattery) }
    }

    /// Only keep awake while connected to a power adapter.
    static var keepAwakeRequiresAdapter: Bool {
        get { defaults.object(forKey: Keys.keepAwakeRequiresAdapter) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.keepAwakeRequiresAdapter) }
    }

    // MARK: - Agents

    /// Agents the user connected. Claude Code is connected out of the box,
    /// matching how hooks were installed automatically before multi-agent support.
    static var connectedAgents: Set<AgentKind> {
        get {
            guard let raw = defaults.array(forKey: Keys.connectedAgents) as? [String] else { return [.claude] }
            return Set(raw.compactMap(AgentKind.init(rawValue:)))
        }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: Keys.connectedAgents) }
    }

    // MARK: - Approvals

    /// Answer approval requests (Claude Code, Codex) from the notch.
    /// When off, the notch still shows that an agent needs you.
    static var approveFromNotch: Bool {
        get { defaults.object(forKey: Keys.approveFromNotch) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.approveFromNotch) }
    }

    // MARK: - Notification Sound

    /// The sound to play when an agent finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }

    // MARK: - Claude Directory

    /// The name of the Claude config directory under the user's home folder.
    /// Defaults to ".claude" (standard Claude Code installation).
    /// Change to ".claude-internal" (or similar) for enterprise/custom distributions.
    static var claudeDirectoryName: String {
        get {
            let value = defaults.string(forKey: Keys.claudeDirectoryName) ?? ""
            return value.isEmpty ? ".claude" : value
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Keys.claudeDirectoryName)
        }
    }
}
