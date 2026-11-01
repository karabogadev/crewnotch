//
//  TaskProgress.swift
//  CrewNotch
//
//  An agent's own to-do list for the current task, read from the tool
//  calls it makes to keep it: Claude Code's TodoWrite, Codex's update_plan
//  and Gemini CLI's write_todos.
//

import Foundation

nonisolated struct TaskProgress: Equatable, Sendable {
    nonisolated enum Status: String, Sendable {
        case pending, inProgress, completed, cancelled
    }

    nonisolated struct Item: Equatable, Sendable {
        /// Task id for Claude Code's task tools; nil for whole-list tools.
        var id: String? = nil
        let title: String
        /// What the agent says while doing it ("Writing tests"), when given.
        let activeTitle: String?
        let status: Status
    }

    let items: [Item]

    var total: Int { items.filter { $0.status != .cancelled }.count }
    var completed: Int { items.filter { $0.status == .completed }.count }
    var isFinished: Bool { total > 0 && completed == total }
    var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }

    /// The step in progress, else the next one to do.
    var currentTitle: String? {
        if let active = items.first(where: { $0.status == .inProgress }) { return active.activeTitle ?? active.title }
        return items.first(where: { $0.status == .pending })?.title
    }

    /// Tools that rewrite the whole list on every call.
    static let toolNames: Set<String> = ["TodoWrite", "update_plan", "write_todos"]

    /// Claude Code's task tools change one task per call.
    static let taskToolNames: Set<String> = ["TaskCreate", "TaskUpdate"]

    /// Applies a TaskCreate (after it ran, with the new id from its response)
    /// or TaskUpdate call to `progress`. Items are keyed by task id.
    static func applying(toolName: String?, input: [String: Any]?, response: [String: Any]?, to progress: TaskProgress?) -> TaskProgress? {
        guard let toolName, taskToolNames.contains(toolName), let input else { return progress }
        var items = progress?.items ?? []
        if toolName == "TaskCreate" {
            let task = response?["task"] as? [String: Any]
            guard let id = Self.string(task?["id"]),
                  let subject = (task?["subject"] ?? input["subject"]) as? String, !subject.isEmpty else { return progress }
            items.removeAll { $0.id == id }
            items.append(Item(id: id, title: subject, activeTitle: (input["activeForm"] ?? input["active_form"]) as? String, status: .pending))
        } else {
            guard let id = Self.string(input["taskId"] ?? input["task_id"] ?? input["id"]),
                  let index = items.firstIndex(where: { $0.id == id }) else { return progress }
            let old = items[index]
            if (input["status"] as? String) == "deleted" {
                items.remove(at: index)
            } else {
                items[index] = Item(
                    id: id,
                    title: (input["subject"] as? String) ?? old.title,
                    activeTitle: ((input["activeForm"] ?? input["active_form"]) as? String) ?? old.activeTitle,
                    status: (input["status"] as? String).map(status) ?? old.status
                )
            }
        }
        return items.isEmpty ? nil : TaskProgress(items: items)
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        if let number = value as? Int { return String(number) }
        return nil
    }

    /// The list carried by a to-do tool call, or nil for other tools.
    init?(toolName: String?, input: [String: Any]?) {
        guard let toolName, Self.toolNames.contains(toolName), let input else { return nil }
        let rawItems = (input["todos"] ?? input["plan"]) as? [[String: Any]] ?? []
        let items = rawItems.compactMap { raw -> Item? in
            guard let title = (raw["content"] ?? raw["step"] ?? raw["description"] ?? raw["title"]) as? String,
                  !title.isEmpty else { return nil }
            return Item(
                title: title,
                activeTitle: raw["activeForm"] as? String,
                status: Self.status(raw["status"] as? String)
            )
        }
        guard !items.isEmpty else { return nil }
        self.items = items
    }

    init(items: [Item]) {
        self.items = items
    }

    private static func status(_ raw: String?) -> Status {
        switch raw?.lowercased() {
        case "in_progress", "inprogress", "in-progress", "active", "running": return .inProgress
        case "completed", "complete", "done": return .completed
        case "cancelled", "canceled", "skipped": return .cancelled
        default: return .pending
        }
    }
}

/// How much of the model's context window the conversation fills.
nonisolated struct ContextUsage: Equatable, Sendable {
    let usedTokens: Int
    let windowTokens: Int

    var fraction: Double {
        windowTokens > 0 ? min(1, Double(usedTokens) / Double(windowTokens)) : 0
    }

    /// Claude Code: the prompt of the latest main-thread request (fresh,
    /// cached and cache-written input) against the model's window.
    static func claude(usage: UsageInfo) -> ContextUsage? {
        guard usage.contextTokens > 0 else { return nil }
        return ContextUsage(usedTokens: usage.contextTokens, windowTokens: claudeWindow(model: usage.model, used: usage.contextTokens))
    }

    /// Opus 4.7+, Sonnet 5+, Haiku 5.5+ and Fable have a 1M window; older
    /// models have 200K unless the id says "[1m]". A prompt over 200K proves 1M.
    static func claudeWindow(model: String?, used: Int) -> Int {
        let id = model?.lowercased() ?? ""
        if id.contains("[1m]") || id.contains("-1m") || used > 200_000 { return 1_000_000 }
        // Old naming ("claude-3-5-sonnet-…") is all 200K
        if id.range(of: #"claude-\d"#, options: .regularExpression) != nil { return 200_000 }
        // "opus-4-7", "haiku-4-5-20251001", "opus-4-20250514": the minor version has at most two digits
        guard let regex = try? NSRegularExpression(pattern: #"(opus|sonnet|haiku|fable)-(\d+)(?:-(\d{1,2})(?!\d))?"#),
              let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) else {
            return id.isEmpty ? 200_000 : 1_000_000  // an unknown, newer model
        }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: id).map { String(id[$0]) }
        }
        let family = group(1) ?? ""
        let major = group(2).flatMap(Int.init) ?? 0
        let minor = group(3).flatMap(Int.init) ?? 0
        switch family {
        case "fable": return 1_000_000
        case "opus": return (major, minor) >= (4, 7) ? 1_000_000 : 200_000
        case "sonnet": return major >= 5 ? 1_000_000 : 200_000
        case "haiku": return (major, minor) >= (5, 5) ? 1_000_000 : 200_000
        default: return 200_000
        }
    }
}
