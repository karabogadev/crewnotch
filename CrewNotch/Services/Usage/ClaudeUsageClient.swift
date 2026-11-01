//
//  ClaudeUsageClient.swift
//  CrewNotch
//
//  Claude plan usage from Anthropic's OAuth usage endpoint, using the
//  sign-in Claude Code already keeps in the keychain. Strictly read-only:
//  CrewNotch never refreshes or writes the token (that would race Claude
//  Code's own refresh and could sign the user out). An expired token just
//  waits until Claude Code refreshes it.
//
//  Endpoint and response shape as documented by OpenUsage (MIT,
//  github.com/robinebers/openusage).
//

import Foundation

nonisolated enum ClaudeUsageClient {
    enum Failure: LocalizedError {
        case notSignedIn
        case signInExpired
        case noUsageScope
        case rateLimited(until: Date)
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return String(localized: "Sign in to Claude Code")
            case .signInExpired: return String(localized: "Open Claude Code to renew sign-in")
            case .noUsageScope: return String(localized: "This sign-in can't read usage")
            case .rateLimited(let until): return String(localized: "Paused until \(until.formatted(date: .omitted, time: .shortened))")
            case .server(let code): return String(localized: "Usage unavailable (\(code))")
            }
        }
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let retryKey = "claudeUsageRetryAfter"

    static func fetch() async throws -> ProviderUsage {
        if let until = UserDefaults.standard.object(forKey: retryKey) as? Date, until > Date() {
            throw Failure.rateLimited(until: until)
        }

        let credentials = try readCredentials()

        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        request.setValue("CrewNotch/\(version)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            UserDefaults.standard.removeObject(forKey: retryKey)
        case 401, 403:
            throw Failure.signInExpired
        case 429:
            let until = Date().addingTimeInterval(retryDelay(from: response as? HTTPURLResponse))
            UserDefaults.standard.set(until, forKey: retryKey)
            throw Failure.rateLimited(until: until)
        default:
            throw Failure.server(status)
        }

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return ProviderUsage(agent: .claude, plan: credentials.plan, limits: limits(from: json), updatedAt: Date())
    }

    // MARK: - Response

    static func limits(from json: [String: Any]) -> [UsageLimit] {
        let hour: TimeInterval = 3600
        func window(_ key: String, _ label: String, _ length: TimeInterval) -> UsageLimit? {
            guard let value = json[key] as? [String: Any],
                  let used = (value["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return UsageLimit(label: label, usedPercent: used, resetsAt: resetDate(value["resets_at"]), window: length)
        }

        var result = [window("five_hour", "Session", 5 * hour), window("seven_day", "Weekly", 168 * hour), window("seven_day_sonnet", "Sonnet", 168 * hour)]
            .compactMap { $0 }

        // Per-model weekly limits (e.g. Fable) live in `limits[]`.
        for entry in json["limits"] as? [[String: Any]] ?? [] where entry["kind"] as? String == "weekly_scoped" {
            guard let percent = (entry["percent"] as? NSNumber)?.doubleValue,
                  let model = ((entry["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String,
                  !result.contains(where: { $0.label == model }) else { continue }
            result.append(UsageLimit(label: model, usedPercent: percent, resetsAt: resetDate(entry["resets_at"]), window: 168 * hour))
        }

        if let extra = json["extra_usage"] as? [String: Any], extra["is_enabled"] as? Bool == true,
           let limit = (extra["monthly_limit"] as? NSNumber)?.doubleValue, limit > 0 {
            let used = (extra["used_credits"] as? NSNumber)?.doubleValue ?? 0
            result.append(UsageLimit(label: "Extra usage", usedPercent: min(100, used / limit * 100), resetsAt: nil))
        }
        return result
    }

    private static func resetDate(_ value: Any?) -> Date? {
        if let string = value as? String { return UsageFormat.date(fromISO: string) }
        if let number = value as? NSNumber { return UsageFormat.date(fromEpoch: number.doubleValue) }
        return nil
    }

    /// Honors Retry-After (seconds or HTTP date); otherwise backs off 15 minutes.
    private static func retryDelay(from response: HTTPURLResponse?) -> TimeInterval {
        guard let header = response?.value(forHTTPHeaderField: "Retry-After") else { return 15 * 60 }
        if let seconds = TimeInterval(header) { return min(max(seconds, 60), 3600) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: header) { return min(max(date.timeIntervalSinceNow, 60), 3600) }
        return 15 * 60
    }

    // MARK: - Credentials

    private struct Credentials {
        let accessToken: String
        let plan: String?
    }

    /// Reads Claude Code's sign-in from the keychain in-process; macOS asks the
    /// user once to let CrewNotch (and only CrewNotch) read it.
    private static func readCredentials() throws -> Credentials {
        // Claude Code files its sign-in under the user's name. Running it with
        // sudo once leaves a second item for "root" that is never refreshed, and
        // a lookup by service alone may return that stale one.
        let service = "Claude Code-credentials"
        guard var raw = (LocalData.keychainPassword(service, account: NSUserName()) ?? LocalData.keychainPassword(service))?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { throw Failure.notSignedIn }
        if !raw.hasPrefix("{"), let decoded = hexDecoded(raw) { raw = decoded }

        guard let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { throw Failure.notSignedIn }

        if let scopes = oauth["scopes"] as? [String], !scopes.contains("user:profile") {
            throw Failure.noUsageScope
        }
        if let expiresAt = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
           UsageFormat.date(fromEpoch: expiresAt) < Date() {
            throw Failure.signInExpired
        }
        return Credentials(accessToken: token, plan: planName(oauth))
    }

    /// "max" + "default_claude_max_20x" -> "Max 20x"
    private static func planName(_ oauth: [String: Any]) -> String? {
        guard let type = oauth["subscriptionType"] as? String, !type.isEmpty else { return nil }
        var name = type.prefix(1).uppercased() + type.dropFirst()
        if let tier = oauth["rateLimitTier"] as? String,
           let range = tier.range(of: #"\d+x"#, options: .regularExpression) {
            name += " \(tier[range])"
        }
        return name
    }

    private static func hexDecoded(_ hex: String) -> String? {
        guard hex.count.isMultiple(of: 2), hex.allSatisfy(\.isHexDigit) else { return nil }
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}
