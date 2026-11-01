//
//  CodexUsageReader.swift
//  CrewNotch
//
//  Codex writes its rate-limit windows into every session rollout
//  (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl, "token_count" events),
//  so usage can be read locally with no network call or credentials.
//

import Foundation

nonisolated enum CodexUsageReader {
    private static var sessionsDir: URL {
        let home = Foundation.ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return home.appendingPathComponent("sessions")
    }

    static func read() -> ProviderUsage? {
        guard let file = newestRollout(),
              let event = lastRateLimitEvent(in: file) else { return nil }
        return usage(from: event.rateLimits, at: event.timestamp)
    }

    // MARK: - Parsing

    static func usage(from rateLimits: [String: Any], at timestamp: Date) -> ProviderUsage {
        let now = Date()
        var limits: [UsageLimit] = []
        for key in ["primary", "secondary"] {
            guard let window = rateLimits[key] as? [String: Any],
                  let used = (window["used_percent"] as? NSNumber)?.doubleValue else { continue }
            let minutes = (window["window_minutes"] as? NSNumber)?.intValue
            let resetsAt = (window["resets_at"] as? NSNumber).map { UsageFormat.date(fromEpoch: $0.doubleValue) }
            // A window that already reset has nothing used in it yet.
            let current = (resetsAt.map { $0 <= now } ?? false) ? 0 : used
            limits.append(UsageLimit(label: label(forWindowMinutes: minutes, fallback: key), usedPercent: current, resetsAt: resetsAt))
        }
        let plan = (rateLimits["plan_type"] as? String).map(planName)
        return ProviderUsage(agent: .codex, plan: plan, limits: limits, updatedAt: timestamp)
    }

    private static func label(forWindowMinutes minutes: Int?, fallback: String) -> String {
        switch minutes {
        case 300: return "Session"
        case 10080: return "Weekly"
        case let minutes?: return minutes >= 1440 ? "\(minutes / 1440)-day" : "\(minutes / 60)-hour"
        case nil: return fallback == "primary" ? "Session" : "Weekly"
        }
    }

    private static func planName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "pro": return "Pro"
        case "prolite": return "Pro 100"
        case "promax": return "Pro 500"
        default: return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    // MARK: - Files

    /// Walks year/month/day folders newest-first instead of scanning every session.
    private static func newestRollout() -> URL? {
        let fm = FileManager.default
        func sortedChildren(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        for year in sortedChildren(sessionsDir) {
            for month in sortedChildren(year) {
                for day in sortedChildren(month) {
                    let rollouts = sortedChildren(day).filter { $0.pathExtension == "jsonl" }
                    let newest = rollouts.max { modificationDate($0) < modificationDate($1) }
                    if let newest { return newest }
                }
            }
        }
        return nil
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Reads the tail of the rollout and returns the latest event that carries rate limits.
    private static func lastRateLimitEvent(in file: URL) -> (rateLimits: [String: Any], timestamp: Date)? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let tailLength: UInt64 = 512 * 1024
        try? handle.seek(toOffset: size > tailLength ? size - tailLength : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let rateLimits = payload["rate_limits"] as? [String: Any] else { continue }
            let timestamp = (json["timestamp"] as? String).flatMap(UsageFormat.date(fromISO:)) ?? modificationDate(file)
            return (rateLimits, timestamp)
        }
        return nil
    }
}
