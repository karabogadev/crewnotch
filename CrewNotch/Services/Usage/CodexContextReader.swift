//
//  CodexContextReader.swift
//  CrewNotch
//
//  How full a Codex session's context window is. Codex logs a
//  "token_count" event after every turn in the session's rollout
//  (~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<session id>.jsonl) with
//  the last request's tokens and the model's context window.
//

import Foundation

nonisolated enum CodexContextReader {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var rolloutPaths: [String: URL] = [:]
    nonisolated(unsafe) private static var lastMiss: [String: Date] = [:]

    private static var sessionsDir: URL {
        let home = Foundation.ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return home.appendingPathComponent("sessions")
    }

    /// `sessionId` is Codex's own id (without CrewNotch's "codex:" prefix).
    static func context(sessionId: String) -> ContextUsage? {
        guard let file = rollout(for: sessionId) else { return nil }
        return lastContext(in: file)
    }

    static func lastContext(in file: URL) -> ContextUsage? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let tailLength: UInt64 = 512 * 1024
        try? handle.seek(toOffset: size > tailLength ? size - tailLength : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        let text = String(decoding: data, as: UTF8.self)

        for line in text.split(separator: "\n").reversed() where line.contains("\"token_count\"") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let window = info["model_context_window"] as? Int, window > 0,
                  let last = info["last_token_usage"] as? [String: Any] else { continue }
            // Codex counts the context as the last request's tokens minus hidden reasoning
            let total = last["total_tokens"] as? Int ?? 0
            let reasoning = last["reasoning_output_tokens"] as? Int ?? 0
            return ContextUsage(usedTokens: max(0, total - reasoning), windowTokens: window)
        }
        return nil
    }

    /// Finds the rollout once per session, newest days first.
    private static func rollout(for sessionId: String) -> URL? {
        lock.lock()
        if let known = rolloutPaths[sessionId] {
            lock.unlock()
            return known
        }
        if let miss = lastMiss[sessionId], Date().timeIntervalSince(miss) < 60 {
            lock.unlock()
            return nil
        }
        lock.unlock()

        let suffix = "-\(sessionId).jsonl"
        let fm = FileManager.default
        func children(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        var found: URL?
        search: for year in children(sessionsDir) {
            for month in children(year) {
                for day in children(month) {
                    if let match = children(day).first(where: { $0.lastPathComponent.hasSuffix(suffix) }) {
                        found = match
                        break search
                    }
                }
            }
        }

        lock.lock()
        if let found { rolloutPaths[sessionId] = found } else { lastMiss[sessionId] = Date() }
        lock.unlock()
        return found
    }
}
