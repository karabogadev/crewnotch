//
//  Settings.swift
//  CrewNotch
//
//  App settings manager using UserDefaults
//

import AppKit
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

/// How plan usage is laid out at the bottom of the notch.
nonisolated enum UsageStyle: String, CaseIterable {
    case line, bars, compact

    var title: String {
        switch self {
        case .line: return "Line"
        case .bars: return "Bars"
        case .compact: return "Compact"
        }
    }
}

/// Which number a usage percentage shows.
nonisolated enum UsagePercentMode: String, CaseIterable {
    case used, left

    var title: String { self == .used ? "Used" : "Left" }
}

/// Which limit represents a provider when only one is shown.
nonisolated enum UsageLimitChoice: String, CaseIterable {
    case mostUsed, session, weekly

    var title: String {
        switch self {
        case .mostUsed: return "Closest to the limit"
        case .session: return "Session"
        case .weekly: return "Weekly"
        }
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
        static let playSounds = "playSounds"
        static let questionSound = "questionSound"
        static let showFinishedBanner = "showFinishedBanner"
        static let usageProviderOrder = "usageProviderOrder"
        static let hiddenUsageMetrics = "hiddenUsageMetrics"
    }

    // MARK: - Sounds and banners

    /// Master switch for every CrewNotch sound.
    static var playSounds: Bool {
        get { defaults.object(forKey: Keys.playSounds) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.playSounds) }
    }

    /// Sound when an agent asks you a question.
    static var questionSound: NotificationSound {
        get { defaults.string(forKey: Keys.questionSound).flatMap(NotificationSound.init(rawValue:)) ?? .tink }
        set { defaults.set(newValue.rawValue, forKey: Keys.questionSound) }
    }

    /// Briefly open the notch with a "Finished" banner when an agent finishes.
    static var showFinishedBanner: Bool {
        get { defaults.object(forKey: Keys.showFinishedBanner) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showFinishedBanner) }
    }

    /// Plays a sound if sounds are on and the user picked one.
    /// Plays a sound if sounds are on, skipping repeats of the same sound
    /// within a moment (several sessions finishing together sound once).
    @MainActor static func play(_ sound: NotificationSound) {
        guard playSounds, let name = sound.soundName else { return }
        let now = Date()
        if let last = lastPlayed[name], now.timeIntervalSince(last) < 1.5 { return }
        lastPlayed[name] = now
        NSSound(named: name)?.play()
    }

    @MainActor private static var lastPlayed: [String: Date] = [:]

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
