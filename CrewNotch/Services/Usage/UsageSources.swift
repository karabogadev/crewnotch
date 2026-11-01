//
//  UsageSources.swift
//  CrewNotch
//
//  One plan-usage source per agent. Each reads credentials the agent already
//  keeps on this Mac (read-only: never refreshed or written) and turns the
//  provider's usage into percentage limits. Endpoints and fields follow the
//  documentation in OpenUsage (MIT, github.com/robinebers/openusage).
//

import Foundation
import Security

nonisolated protocol UsageSource: Sendable {
    var agent: AgentKind { get }
    /// What CrewNotch reads to get usage, shown before the user turns it on
    var accessNote: String { get }
    /// Seconds between refreshes
    var refreshInterval: TimeInterval { get }
    /// Whether the agent's sign-in (or local data) exists on this Mac
    func isAvailable() -> Bool
    func fetch() async throws -> ProviderUsage
}

nonisolated enum UsageSources {
    static let all: [any UsageSource] = [
        ClaudeUsageSource(), CodexUsageSource(), AntigravityUsageSource(), CursorUsageSource(),
        CopilotUsageSource(), GrokUsageSource(), OpenCodeUsageSource(), KiroUsageSource(),
    ]

    static func source(for agent: AgentKind) -> (any UsageSource)? {
        all.first { $0.agent == agent }
    }
}

nonisolated enum UsageSourceError: LocalizedError {
    case notSignedIn(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn(let app): return String(localized: "Open \(app) to sign in")
        case .unavailable(let reason): return reason
        }
    }
}

// MARK: - Claude and Codex

nonisolated struct ClaudeUsageSource: UsageSource {
    let agent = AgentKind.claude
    let refreshInterval: TimeInterval = 300
    var accessNote: String { String(localized: "Reads Claude Code's sign-in from the keychain (macOS asks once).") }
    /// Claude Code is installed; the keychain is only touched once the user turns this on.
    func isAvailable() -> Bool { LocalData.exists(".claude") }
    func fetch() async throws -> ProviderUsage { try await ClaudeUsageClient.fetch() }
}

nonisolated struct CodexUsageSource: UsageSource {
    let agent = AgentKind.codex
    let refreshInterval: TimeInterval = 60
    var accessNote: String { String(localized: "Reads Codex's local session files. Nothing is sent anywhere.") }
    func isAvailable() -> Bool { LocalData.exists(".codex/sessions") }
    func fetch() async throws -> ProviderUsage {
        guard let usage = CodexUsageReader.read() else { throw UsageSourceError.unavailable(String(localized: "No Codex sessions yet")) }
        return usage
    }
}

// MARK: - Antigravity

/// Asks the running Antigravity app's local language server; no token needed.
nonisolated struct AntigravityUsageSource: UsageSource {
    let agent = AgentKind.antigravity
    let refreshInterval: TimeInterval = 120
    var accessNote: String { String(localized: "Asks the running Antigravity app on this Mac. Nothing leaves your Mac.") }

    func isAvailable() -> Bool {
        AgentIntegrations.all[.antigravity]?.isDetected() ?? false
    }

    func fetch() async throws -> ProviderUsage {
        guard let server = Self.findServer() else {
            throw UsageSourceError.unavailable(String(localized: "Open Antigravity to see usage"))
        }
        let body: [String: Any] = ["metadata": ["ideName": "antigravity", "extensionName": "antigravity", "ideVersion": "unknown", "locale": "en"]]
        for port in server.ports {
            for scheme in ["https", "http"] {
                let url = URL(string: "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus")!
                guard let json = try? await LocalData.postJSON(url, body: body, headers: [
                    "Connect-Protocol-Version": "1", "x-codeium-csrf-token": server.csrf,
                ], trustLocalhost: true), let status = json["userStatus"] as? [String: Any] else { continue }
                return usage(from: status)
            }
        }
        throw UsageSourceError.unavailable(String(localized: "Antigravity didn't answer"))
    }

    private func usage(from status: [String: Any]) -> ProviderUsage {
        let configs = ((status["cascadeModelConfigData"] as? [String: Any])?["clientModelConfigs"] as? [[String: Any]]) ?? []
        // One limit per model; effort variants ("Gemini 4 Argon (High)") share a quota
        var models: [(name: String, fraction: Double, reset: Date?)] = []
        for config in configs {
            let name = (config["label"] as? String ?? "").replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
            let id = ((config["modelOrAlias"] as? [String: Any])?["model"] as? String) ?? ""
            guard !name.isEmpty, !Self.hiddenModels.contains(id), !id.contains("GEMINI_2_5"),
                  let quota = config["quotaInfo"] as? [String: Any] else { continue }
            let fraction = min(max((quota["remainingFraction"] as? NSNumber)?.doubleValue ?? 0, 0), 1)
            let reset = (quota["resetTime"] as? String).flatMap(UsageFormat.date(fromISO:))
            if let index = models.firstIndex(where: { $0.name == name }) {
                if fraction < models[index].fraction { models[index] = (name, fraction, reset) }
            } else {
                models.append((name, fraction, reset))
            }
        }
        let limits = models.map { UsageLimit(label: $0.name, usedPercent: (1 - $0.fraction) * 100, resetsAt: $0.reset) }
        let plan = ((status["userTier"] as? [String: Any])?["name"] as? String)
            ?? (((status["planStatus"] as? [String: Any])?["planInfo"] as? [String: Any])?["planName"] as? String)
        return ProviderUsage(agent: agent, plan: plan, limits: limits, updatedAt: Date())
    }

    /// Internal entries that aren't real models
    private static let hiddenModels: Set<String> = ["MODEL_CHAT_20706", "MODEL_CHAT_23310", "MODEL_PLACEHOLDER_M9", "MODEL_PLACEHOLDER_M19"]

    /// The language server process with its CSRF token and listening ports.
    private static func findServer() -> (csrf: String, ports: [Int])? {
        guard let listing = LocalData.run("/bin/ps", ["-ax", "-o", "pid=,command="]) else { return nil }
        for line in listing.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count > 2, let pid = Int(parts[0]),
                  (parts[1] as NSString).lastPathComponent.hasPrefix("language_server"),
                  line.contains("antigravity"),
                  let csrf = argument("--csrf_token", in: parts) else { continue }
            let lsof = LocalData.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "\(pid)"]) ?? ""
            let ports = lsof.split(separator: "\n").compactMap { row -> Int? in
                guard row.contains("LISTEN"), let address = row.split(separator: " ").first(where: { $0.contains(":") && $0.last?.isNumber == true }) else { return nil }
                return Int(address.split(separator: ":").last ?? "")
            }
            if !ports.isEmpty { return (csrf, Array(Set(ports)).sorted()) }
        }
        return nil
    }

    private static func argument(_ name: String, in parts: [String]) -> String? {
        for (index, part) in parts.enumerated() {
            if part == name, index + 1 < parts.count { return parts[index + 1] }
            if part.hasPrefix(name + "=") { return String(part.dropFirst(name.count + 1)) }
        }
        return nil
    }
}

// MARK: - Cursor

nonisolated struct CursorUsageSource: UsageSource {
    let agent = AgentKind.cursor
    let refreshInterval: TimeInterval = 300
    var accessNote: String { String(localized: "Reads Cursor's sign-in from its local settings database.") }

    private static let database = "Library/Application Support/Cursor/User/globalStorage/state.vscdb"

    func isAvailable() -> Bool { LocalData.exists(Self.database) }

    func fetch() async throws -> ProviderUsage {
        guard let token = LocalData.sqliteValue(Self.database, key: "cursorAuth/accessToken")
                ?? LocalData.keychainPassword("cursor-access-token") else {
            throw UsageSourceError.notSignedIn("Cursor")
        }
        let headers = ["Authorization": "Bearer \(token)", "Connect-Protocol-Version": "1"]
        let base = "https://api2.cursor.sh/aiserver.v1.DashboardService/"
        let usage = try await LocalData.postJSON(URL(string: base + "GetCurrentPeriodUsage")!, body: [:], headers: headers)
        let planName = ((try? await LocalData.postJSON(URL(string: base + "GetPlanInfo")!, body: [:], headers: headers))?["planInfo"] as? [String: Any])?["planName"] as? String

        guard let plan = usage["planUsage"] as? [String: Any] else {
            throw UsageSourceError.unavailable(String(localized: "Usage isn't available for this Cursor plan"))
        }
        let reset = LocalData.number(usage["billingCycleEnd"]).map { UsageFormat.date(fromEpoch: $0) }
        var limits: [UsageLimit] = []
        if let total = LocalData.number(plan["totalPercentUsed"]) ?? LocalData.ratio(plan["totalSpend"], plan["limit"]) {
            limits.append(UsageLimit(label: "Total usage", usedPercent: total, resetsAt: reset))
        }
        if let auto = LocalData.number(plan["autoPercentUsed"]) {
            limits.append(UsageLimit(label: "Auto usage", usedPercent: auto, resetsAt: reset))
        }
        if let api = LocalData.number(plan["apiPercentUsed"]) {
            limits.append(UsageLimit(label: "API usage", usedPercent: api, resetsAt: reset))
        }
        return ProviderUsage(agent: agent, plan: planName, limits: limits, updatedAt: Date())
    }
}

// MARK: - Copilot

nonisolated struct CopilotUsageSource: UsageSource {
    let agent = AgentKind.copilot
    let refreshInterval: TimeInterval = 300
    var accessNote: String { String(localized: "Reads the GitHub CLI sign-in from the keychain (macOS asks once).") }

    /// The GitHub CLI is set up; the keychain is only touched once the user turns this on.
    func isAvailable() -> Bool { LocalData.exists(".config/gh/hosts.yml") }

    func fetch() async throws -> ProviderUsage {
        guard var token = LocalData.keychainPassword("gh:github.com") else { throw UsageSourceError.notSignedIn("GitHub CLI") }
        let prefix = "go-keyring-base64:"
        if token.hasPrefix(prefix), let data = Data(base64Encoded: String(token.dropFirst(prefix.count))) {
            token = String(decoding: data, as: UTF8.self)
        }
        let json = try await LocalData.getJSON(URL(string: "https://api.github.com/copilot_internal/user")!, headers: [
            "Authorization": "token \(token)",
            "Editor-Version": "vscode/1.96.2",
            "Editor-Plugin-Version": "copilot-chat/0.26.7",
            "User-Agent": "GitHubCopilotChat/0.26.7",
            "X-Github-Api-Version": "2025-04-01",
        ])
        let reset = ((json["quota_reset_date"] ?? json["limited_user_reset_date"]) as? String).flatMap(Self.date)
        let snapshots = json["quota_snapshots"] as? [String: Any] ?? [:]
        let names = [("premium_interactions", "Premium requests"), ("chat", "Chat"), ("completions", "Completions")]
        let limits: [UsageLimit] = names.compactMap { key, label in
            guard let snapshot = snapshots[key] as? [String: Any], snapshot["unlimited"] as? Bool != true else { return nil }
            if let remaining = LocalData.number(snapshot["percent_remaining"]) {
                return UsageLimit(label: label, usedPercent: 100 - remaining, resetsAt: reset)
            }
            guard let used = LocalData.ratio(snapshot["remaining"], snapshot["entitlement"]) else { return nil }
            return UsageLimit(label: label, usedPercent: 100 - used, resetsAt: reset)
        }
        let plan = (json["copilot_plan"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return ProviderUsage(agent: agent, plan: plan, limits: limits, updatedAt: Date())
    }

    private static func date(_ value: String) -> Date? {
        if let date = UsageFormat.date(fromISO: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

// MARK: - Grok

nonisolated struct GrokUsageSource: UsageSource {
    let agent = AgentKind.grok
    let refreshInterval: TimeInterval = 300
    var accessNote: String { String(localized: "Reads Grok's sign-in from ~/.grok/auth.json.") }

    func isAvailable() -> Bool { LocalData.exists(".grok/auth.json") }

    func fetch() async throws -> ProviderUsage {
        guard let auth = LocalData.jsonFile(".grok/auth.json"),
              let key = auth.values.compactMap({ ($0 as? [String: Any])?["key"] as? String }).first(where: { !$0.isEmpty }) else {
            throw UsageSourceError.notSignedIn("Grok")
        }
        let json = try await LocalData.getJSON(URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!, headers: [
            "Authorization": "Bearer \(key)", "X-XAI-Token-Auth": "xai-grok-cli",
        ])
        let config = json["config"] as? [String: Any] ?? [:]
        let reset = ((config["currentPeriod"] as? [String: Any])?["end"] as? String).flatMap(UsageFormat.date(fromISO:))
        let used = LocalData.number(config["creditUsagePercent"]) ?? 0
        return ProviderUsage(agent: agent, plan: nil, limits: [UsageLimit(label: "Weekly", usedPercent: used, resetsAt: reset)], updatedAt: Date())
    }
}

// MARK: - OpenCode Go

nonisolated struct OpenCodeUsageSource: UsageSource {
    let agent = AgentKind.opencode
    let refreshInterval: TimeInterval = 300
    var accessNote: String { String(localized: "Reads your OpenCode Go key from OpenCode's auth file.") }

    private static let authFile = ".local/share/opencode/auth.json"

    func isAvailable() -> Bool {
        (LocalData.jsonFile(Self.authFile)?["opencode-go"] as? [String: Any])?["key"] != nil
    }

    func fetch() async throws -> ProviderUsage {
        guard let key = (LocalData.jsonFile(Self.authFile)?["opencode-go"] as? [String: Any])?["key"] as? String else {
            throw UsageSourceError.notSignedIn("OpenCode Go")
        }
        let json = try await LocalData.getJSON(URL(string: "https://opencode.ai/zen/go/v1/usage")!, headers: ["Authorization": "Bearer \(key)"])
        let usage = json["usage"] as? [String: Any] ?? [:]
        let windows = [("rolling", "Session"), ("weekly", "Weekly"), ("monthly", "Monthly")]
        let limits: [UsageLimit] = windows.compactMap { key, label in
            guard let window = usage[key] as? [String: Any], let percent = LocalData.number(window["percent"]) else { return nil }
            return UsageLimit(label: label, usedPercent: percent, resetsAt: (window["resetsAt"] as? String).flatMap(UsageFormat.date(fromISO:)))
        }
        return ProviderUsage(agent: agent, plan: "Go", limits: limits, updatedAt: Date())
    }
}

// MARK: - Kiro

/// Reads the usage Kiro already caches in its settings database; offline.
nonisolated struct KiroUsageSource: UsageSource {
    let agent = AgentKind.kiro
    let refreshInterval: TimeInterval = 120
    var accessNote: String { String(localized: "Reads the usage Kiro keeps in its local settings. Nothing is sent anywhere.") }

    private static let database = "Library/Application Support/Kiro/User/globalStorage/state.vscdb"

    func isAvailable() -> Bool { LocalData.exists(Self.database) }

    func fetch() async throws -> ProviderUsage {
        guard let raw = LocalData.sqliteValue(Self.database, key: "kiro.kiroAgent"),
              let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let state = json["kiro.resourceNotifications.usageState"] as? [String: Any],
              let breakdowns = state["usageBreakdowns"] as? [[String: Any]] else {
            throw UsageSourceError.unavailable(String(localized: "Open Kiro to see usage"))
        }
        let credits = breakdowns.first { ($0["resourceType"] ?? $0["type"]) as? String == "CREDIT" } ?? breakdowns.first
        guard let credits,
              let used = LocalData.number(credits["currentUsageWithPrecision"] ?? credits["currentUsage"]),
              let limit = LocalData.number(credits["usageLimitWithPrecision"] ?? credits["usageLimit"]), limit > 0 else {
            throw UsageSourceError.unavailable(String(localized: "Open Kiro to see usage"))
        }
        let reset: Date? = {
            if let text = credits["nextDateReset"] as? String { return UsageFormat.date(fromISO: text) }
            return LocalData.number(credits["nextDateReset"]).map { UsageFormat.date(fromEpoch: $0) }
        }()
        return ProviderUsage(agent: agent, plan: nil, limits: [UsageLimit(label: "Credits", usedPercent: used / limit * 100, resetsAt: reset)], updatedAt: Date())
    }
}

// MARK: - Local data helpers

nonisolated enum LocalData {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    static func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: home.appendingPathComponent(relativePath).path)
    }

    static func jsonFile(_ relativePath: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(relativePath)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Runs a tool and returns its standard output, or nil on failure.
    static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads a keychain item in-process, so macOS asks on behalf of CrewNotch
    /// and an "Always Allow" applies to CrewNotch only, not to a shared tool
    /// like /usr/bin/security that any program could run.
    static func keychainPassword(_ service: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    /// A value from a VS Code-style `state.vscdb` (opened read-only).
    static func sqliteValue(_ relativePath: String, key: String) -> String? {
        let path = home.appendingPathComponent(relativePath).path
        let query = "SELECT value FROM ItemTable WHERE key = '\(key.replacingOccurrences(of: "'", with: "''"))';"
        return run("/usr/bin/sqlite3", ["-readonly", path, query]).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    static func ratio(_ part: Any?, _ whole: Any?) -> Double? {
        guard let part = number(part), let whole = number(whole), whole > 0 else { return nil }
        return part / whole * 100
    }

    static func getJSON(_ url: URL, headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return try await perform(request, trustLocalhost: false)
    }

    static func postJSON(_ url: URL, body: [String: Any], headers: [String: String], trustLocalhost: Bool = false) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request, trustLocalhost: trustLocalhost)
    }

    private static func perform(_ request: URLRequest, trustLocalhost: Bool) async throws -> [String: Any] {
        let session = trustLocalhost ? URLSession(configuration: .ephemeral, delegate: LocalhostTrust(), delegateQueue: nil) : .shared
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw UsageSourceError.unavailable(String(localized: "Sign-in expired")) }
        guard (200..<300).contains(status) else { throw UsageSourceError.unavailable(String(localized: "Usage unavailable (\(status))")) }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

/// Accepts the self-signed certificate of servers on 127.0.0.1 only.
private final class LocalhostTrust: NSObject, URLSessionDelegate, Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.host == "127.0.0.1",
              let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}
