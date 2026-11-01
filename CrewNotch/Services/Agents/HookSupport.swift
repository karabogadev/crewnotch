//
//  HookSupport.swift
//  CrewNotch
//
//  Shared plumbing for agent integrations: the hook script on disk, the
//  command each agent runs, and safe edits to the agents' JSON config files.
//

import AppKit
import Foundation

// MARK: - Hook script

nonisolated enum HookScript {
    /// Substring that identifies CrewNotch's entries in any agent config.
    static let marker = "crewnotch-hook.py"

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".crewnotch/bin")
    }

    static var url: URL {
        directory.appendingPathComponent(marker)
    }

    /// Copies the bundled script into ~/.crewnotch/bin when it is missing or outdated.
    static func install() throws {
        guard let bundled = Bundle.main.url(forResource: "crewnotch-hook", withExtension: "py") else {
            throw IntegrationError.missingBundledScript
        }
        let fm = FileManager.default
        let source = try Data(contentsOf: bundled)
        if (try? Data(contentsOf: url)) == source { return }

        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try source.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Shell command an agent runs for one hook event.
    static func command(agent: AgentKind, event: String? = nil) -> String {
        var parts = ["/usr/bin/python3", shellQuote(url.path), "--agent", agent.rawValue]
        if let event {
            parts += ["--event", event]
        }
        return parts.joined(separator: " ")
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - Errors

nonisolated enum IntegrationError: LocalizedError {
    case missingBundledScript
    case unreadableConfig(URL)

    var errorDescription: String? {
        switch self {
        case .missingBundledScript:
            return "The CrewNotch hook script is missing from the app bundle."
        case .unreadableConfig(let url):
            return "\(url.path) isn't valid JSON, so CrewNotch left it untouched."
        }
    }
}

// MARK: - JSON config files

nonisolated enum JSONConfigFile {
    /// Reads a JSON object. A missing file is an empty object; a file that
    /// exists but can't be parsed throws, so we never overwrite user config.
    static func load(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntegrationError.unreadableConfig(url)
        }
        return object
    }

    /// Writes a JSON object, skipping the write when nothing changed.
    static func save(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        if (try? Data(contentsOf: url)) == data { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func remove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func contains(_ url: URL, _ needle: String) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains(needle)
    }
}

// MARK: - Hook entry editing

/// Edits the `hooks` object used by Claude Code and agents that copied its
/// format: `{ "<Event>": [ { "matcher"?: "...", "hooks": [ handler ] } ] }`.
nonisolated enum GroupedHooks {
    struct Registration {
        let event: String
        var matcher: String?
        var timeout: Int?
        var extra: [String: Any] = [:]
    }

    /// Removes CrewNotch handlers, dropping groups and events left empty.
    static func removingOurs(from hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                result[event] = value
                continue
            }
            let cleaned: [[String: Any]] = groups.compactMap { group in
                guard var handlers = group["hooks"] as? [[String: Any]] else { return group }
                handlers.removeAll(where: isOurs)
                guard !handlers.isEmpty else { return nil }
                var updated = group
                updated["hooks"] = handlers
                return updated
            }
            if !cleaned.isEmpty {
                result[event] = cleaned
            }
        }
        return result
    }

    /// Replaces CrewNotch's handlers in `hooks` with fresh ones for `registrations`.
    static func installing(_ registrations: [Registration], agent: AgentKind, into hooks: [String: Any]) -> [String: Any] {
        var result = removingOurs(from: hooks)
        for registration in registrations {
            var handler: [String: Any] = ["type": "command", "command": HookScript.command(agent: agent, event: registration.event)]
            if let timeout = registration.timeout {
                handler["timeout"] = timeout
            }
            handler.merge(registration.extra) { _, new in new }

            var group: [String: Any] = ["hooks": [handler]]
            if let matcher = registration.matcher {
                group["matcher"] = matcher
            }
            let existing = result[registration.event] as? [[String: Any]] ?? []
            result[registration.event] = existing + [group]
        }
        return result
    }

    static func containsOurs(_ hooks: [String: Any]?) -> Bool {
        guard let hooks else { return false }
        return hooks.values.contains { value in
            let groups = value as? [[String: Any]] ?? []
            return groups.contains { ($0["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs) }
        }
    }

    static func isOurs(_ handler: [String: Any]) -> Bool {
        let command = (handler["command"] as? String) ?? (handler["bash"] as? String) ?? ""
        return command.contains(HookScript.marker)
    }
}

// MARK: - Detection helpers

nonisolated enum AgentDetection {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    static func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: home.appendingPathComponent(relativePath).path)
    }

    static func appInstalled(_ bundleIdentifiers: [String]) -> Bool {
        bundleIdentifiers.contains { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
        }
    }

    /// Looks for an executable in the usual install locations.
    static func binaryExists(_ name: String) -> Bool {
        let candidates = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            home.appendingPathComponent(".\(name)/bin").path,
        ]
        return candidates.contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(name)") }
    }
}
