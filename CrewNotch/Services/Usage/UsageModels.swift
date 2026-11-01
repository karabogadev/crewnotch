//
//  UsageModels.swift
//  CrewNotch
//
//  Plan usage of one provider: its rate-limit windows and plan name.
//

import Foundation

nonisolated struct UsageLimit: Identifiable, Equatable, Sendable {
    /// "Session", "Weekly", "Sonnet", "Extra usage"...
    let label: String
    /// 0...100
    let usedPercent: Double
    let resetsAt: Date?

    var id: String { label }

    /// The label in the user's language ("Session", "Weekly"... are also used as ids).
    var displayLabel: String { Self.displayName(label) }

    static func displayName(_ label: String) -> String {
        switch label {
        case "Session": return String(localized: "Session")
        case "Weekly": return String(localized: "Weekly")
        case "Extra usage": return String(localized: "Extra usage")
        case "Monthly": return String(localized: "Monthly")
        case "Total usage": return String(localized: "Total usage")
        case "Auto usage": return String(localized: "Auto usage")
        case "API usage": return String(localized: "API usage")
        case "Premium requests": return String(localized: "Premium requests")
        case "Chat": return String(localized: "Chat")
        case "Completions": return String(localized: "Completions")
        case "Credits": return String(localized: "Credits")
        default: return label  // model names like Sonnet, Fable or Gemini Pro
        }
    }
}

nonisolated struct ProviderUsage: Identifiable, Equatable, Sendable {
    let agent: AgentKind
    var plan: String?
    var limits: [UsageLimit]
    /// When the numbers were produced (for local sources, the agent's last turn)
    var updatedAt: Date
    var error: String?

    var id: AgentKind { agent }

    /// The limit closest to running out
    var headline: UsageLimit? {
        limits.max { $0.usedPercent < $1.usedPercent }
    }

    /// The limit picked in Settings, falling back to the one closest to running out.
    func limit(for choice: UsageLimitChoice) -> UsageLimit? {
        switch choice {
        case .mostUsed: return headline
        case .session: return limits.first { $0.label == "Session" } ?? headline
        case .weekly: return limits.first { $0.label == "Weekly" } ?? headline
        }
    }
}

nonisolated enum UsageFormat {
    /// "4d 9h", "2h 15m", "12m"
    static func timeUntil(_ date: Date, from now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Unix timestamps arrive in seconds or milliseconds.
    static func date(fromEpoch value: Double) -> Date {
        Date(timeIntervalSince1970: value < 1e10 ? value : value / 1000)
    }

    static func date(fromISO value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
