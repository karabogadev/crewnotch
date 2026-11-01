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

    /// 1M-token sessions say so in the model id ("…[1m]"); a prompt larger
    /// than 200K proves a 1M window too.
    static func claudeWindow(model: String?, used: Int) -> Int {
        let id = model?.lowercased() ?? ""
        if id.contains("[1m]") || id.contains("-1m") || used > 200_000 { return 1_000_000 }
        return 200_000
    }
}
