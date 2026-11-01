//
//  DeepSeekSessionWatcher.swift
//  CrewNotch
//
//  DeepSeek Harness has no hooks for approvals, but it appends every
//  session event to ~/.dsh/sessions/<project>/session-<id>/session.v4.jsonl.zstd
//  (independent zstd frames, flushed every ~200 ms). This watcher tails those
//  logs and turns the events into the same normalized events hooks produce.
//

import AppKit
import Foundation
import os.log

/// Drives the watcher from the main actor (app lookup, timer).
@MainActor
enum DeepSeekMonitor {
    private static var timer: Timer?

    static func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        tick()
    }

    private static func tick() {
        guard AppSettings.connectedAgents.contains(.deepseek),
              let app = AgentKind.deepseek.appBundleIdentifiers()
                .lazy.compactMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }).first
        else { return }
        let pid = Int(app.processIdentifier)
        Task.detached { await DeepSeekSessionWatcher.shared.scan(appPid: pid) }
    }
}

actor DeepSeekSessionWatcher {
    static let shared = DeepSeekSessionWatcher()

    private static let logger = Logger(subsystem: "com.karabogadev.crewnotch", category: "DeepSeek")
    /// Sessions untouched for longer than this aren't picked up at launch.
    private static let recentWindow: TimeInterval = 15 * 60

    private struct Session {
        let decoder: ZstdStreamDecoder
        var offset: UInt64 = 0
        var partialLine = Data()
        var id: String?
        var cwd = ""
        var isSubagent = false
        var caughtUp = false
        var snapshot = Snapshot()
    }

    /// What a session looks like after replaying its log, used to publish
    /// one current state at launch instead of replaying old history.
    private struct Snapshot {
        var title: String?
        var lastPrompt: String?
        var lastReply: String?
        var inTurn = false
        var pendingApproval: (tool: String, reason: String?)?
    }

    private var sessions: [String: Session] = [:]
    private var isScanning = false

    private var root: URL {
        let base = Foundation.ProcessInfo.processInfo.environment["DSH_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh")
        return base.appendingPathComponent("sessions")
    }

    func scan(appPid: Int) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        for file in sessionLogs() {
            let path = file.url.path
            if sessions[path] == nil {
                guard Date().timeIntervalSince(file.modified) < Self.recentWindow,
                      let decoder = ZstdStreamDecoder() else { continue }
                sessions[path] = Session(decoder: decoder)
            }
            await read(path: path, appPid: appPid)
        }
    }

    // MARK: - Files

    private func sessionLogs() -> [(url: URL, modified: Date)] {
        let fm = FileManager.default
        var result: [(URL, Date)] = []
        for project in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for session in (try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: nil)) ?? []
            where session.lastPathComponent.hasPrefix("session-") {
                let log = session.appendingPathComponent("session.v4.jsonl.zstd")
                if let modified = try? log.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    result.append((log, modified))
                }
            }
        }
        return result
    }

    private func read(path: String, appPid: Int) async {
        guard var session = sessions[path],
              let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        guard size > session.offset else {
            if !session.caughtUp {
                session.caughtUp = true
                await publishSnapshot(of: session, appPid: appPid)
                sessions[path] = session
            }
            return
        }
        try? handle.seek(toOffset: session.offset)
        let chunk = (try? handle.read(upToCount: Int(size - session.offset))) ?? Data()
        session.offset += UInt64(chunk.count)

        guard let decoded = session.decoder.decode(chunk) else {
            Self.logger.warning("Corrupt DeepSeek log, skipping: \(path, privacy: .public)")
            return
        }

        var buffer = session.partialLine + decoded
        var events: [[String: Any]] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = buffer[(newline + 1)...]
            if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                events.append(json)
            }
        }
        session.partialLine = Data(buffer)

        for event in events {
            if let normalized = apply(event, to: &session, appPid: appPid), session.caughtUp, !session.isSubagent {
                await SessionStore.shared.process(.hookReceived(normalized))
            }
        }

        if !session.caughtUp {
            session.caughtUp = true
            await publishSnapshot(of: session, appPid: appPid)
        }
        sessions[path] = session
    }

    // MARK: - Events

    /// Updates the session's snapshot and returns the normalized event, if any.
    private func apply(_ json: [String: Any], to session: inout Session, appPid: Int) -> HookEvent? {
        let type = json["type"] as? String ?? ""
        let data = json["data"] as? [String: Any] ?? [:]

        func event(_ name: String, _ status: String, tool: String? = nil, input: [String: Any]? = nil,
                   toolUseId: String? = nil, message: String? = nil, prompt: String? = nil,
                   reply: String? = nil, title: String? = nil) -> HookEvent? {
            guard let id = session.id else { return nil }
            return HookEvent(
                sessionId: "deepseek:\(id)", cwd: session.cwd, event: name, status: status, pid: appPid,
                tool: tool, toolInput: input.map { $0.mapValues(AnyCodable.init) }, toolUseId: toolUseId,
                message: message, agent: .deepseek, prompt: prompt, assistantMessage: reply, title: title
            )
        }

        switch type {
        case "session":
            session.id = json["id"] as? String
            session.cwd = json["cwd"] as? String ?? ""
            session.isSubagent = ((json["delegationDepth"] as? NSNumber)?.intValue ?? 0) > 0
            return nil

        case "session/title":
            session.snapshot.title = data["title"] as? String
            return event("TitleChanged", "metadata", title: session.snapshot.title)

        case "user/message":
            guard (data["source"] as? [String: Any])?["kind"] as? String == "user",
                  let text = Self.text(of: data["content"]) else { return nil }
            session.snapshot.lastPrompt = text
            session.snapshot.inTurn = true
            return event("UserPromptSubmit", "processing", prompt: text)

        case "turn/start":
            session.snapshot.inTurn = true
            return event("PostToolUse", "processing")

        case "tool/call":
            let name = data["name"] as? String ?? "tool"
            let arguments = (data["arguments"] as? String).flatMap {
                try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
            }
            return event("PreToolUse", "running_tool", tool: name, input: arguments, toolUseId: data["callId"] as? String)

        case "tool/result":
            let callId = (data["message"] as? [String: Any])?["toolCallId"] as? String
            return event("PostToolUse", "processing", toolUseId: callId)

        case "approval/asked":
            let tool = data["toolName"] as? String ?? "Approval"
            let reason = data["reason"] as? String
            session.snapshot.pendingApproval = (tool, reason)
            return event("PermissionRequest", "waiting_for_approval", tool: tool,
                         input: reason.map { ["reason": $0] }, toolUseId: data["callId"] as? String)

        case "approval/decided":
            session.snapshot.pendingApproval = nil
            return event("PostToolUse", "processing")

        case "assistant/message":
            let content = (data["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            guard !content.contains(where: { $0["type"] as? String == "tool-call" }),
                  let text = Self.text(of: content) else { return nil }
            session.snapshot.lastReply = text
            return event("AssistantResponse", "processing", reply: text)

        case "turn/end":
            session.snapshot.inTurn = false
            session.snapshot.pendingApproval = nil
            let reason = (data["reason"] as? [String: Any])?["kind"] as? String
            return event("Stop", "waiting_for_input", message: reason == "completed" ? nil : reason)

        default:
            return nil
        }
    }

    /// Publishes a session's current state once, after reading its history.
    private func publishSnapshot(of session: Session, appPid: Int) async {
        guard let id = session.id, !session.isSubagent else { return }
        let snapshot = session.snapshot
        func send(_ name: String, _ status: String, prompt: String? = nil, reply: String? = nil,
                  tool: String? = nil, input: [String: Any]? = nil) async {
            await SessionStore.shared.process(.hookReceived(HookEvent(
                sessionId: "deepseek:\(id)", cwd: session.cwd, event: name, status: status, pid: appPid,
                tool: tool, toolInput: input.map { $0.mapValues(AnyCodable.init) },
                agent: .deepseek, prompt: prompt, assistantMessage: reply, title: snapshot.title
            )))
        }

        await send("SessionStart", "waiting_for_input")
        if snapshot.inTurn {
            await send("UserPromptSubmit", "processing", prompt: snapshot.lastPrompt)
            if let approval = snapshot.pendingApproval {
                await send("PermissionRequest", "waiting_for_approval", tool: approval.tool,
                           input: approval.reason.map { ["reason": $0] })
            }
        } else if let reply = snapshot.lastReply {
            await send("TitleChanged", "metadata", reply: reply)
        }
    }

    private static func text(of content: Any?) -> String? {
        let parts = (content as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
        let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(4000))
    }
}
