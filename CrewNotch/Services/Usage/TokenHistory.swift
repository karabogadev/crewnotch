//
//  TokenHistory.swift
//  CrewNotch
//
//  Token use per hour and agent over the last 30 days, read from the agents'
//  own logs on this Mac:
//    Claude Code      ~/.claude/projects/**/*.jsonl (assistant message usage)
//    Codex            ~/.codex/sessions/**/rollout-*.jsonl (token_count totals)
//    DeepSeek Harness ~/.dsh/sessions/**/session.v4.jsonl.zstd (assistant usage)
//
//  Files are parsed incrementally and the per-hour totals cached in
//  ~/.crewnotch/token-history.json, so only new log lines are read again.
//

import Foundation

// MARK: - Report

nonisolated struct TokenBucket: Codable, Sendable {
    var tokens: [String: Int] = [:]   // AgentKind.rawValue -> tokens
    /// Estimated cost at Claude API list prices (Claude Code only)
    var claudeValue: Double = 0
}

nonisolated struct TokenHistoryReport: Sendable {
    struct Bar: Identifiable, Sendable {
        let start: Date
        let tokens: [AgentKind: Int]
        var total: Int { tokens.values.reduce(0, +) }
        var id: Date { start }
    }

    let range: TokenHistoryRange
    let bars: [Bar]
    let totals: [AgentKind: Int]
    let claudeValue: Double
    let rangeStart: Date
    let rangeEnd: Date

    var total: Int { totals.values.reduce(0, +) }
    var activeBars: [Bar] { bars.filter { $0.total > 0 } }
    var busiest: Bar? { bars.max { $0.total < $1.total } }
    var perActiveBar: Int { activeBars.isEmpty ? 0 : total / activeBars.count }
}

nonisolated enum TokenHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case today, week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "7 days"
        case .month: return "30 days"
        }
    }

    var caption: String {
        switch self {
        case .today: return "TODAY"
        case .week: return "LAST 7 DAYS"
        case .month: return "LAST 30 DAYS"
        }
    }

    /// Today is shown per hour, longer ranges per day
    var isHourly: Bool { self == .today }
    var dayCount: Int {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        }
    }
}

// MARK: - Store

actor TokenHistoryStore {
    static let shared = TokenHistoryStore()

    private struct FileState: Codable {
        var size: UInt64
        var offset: UInt64
        var lastMessageId: String?
        var lastCodexTotal: Int?
        var hours: [String: TokenBucket]   // "yyyy-MM-dd'T'HH" -> bucket
    }

    private var files: [String: FileState] = [:]
    private var loadedCache = false

    private static let cacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".crewnotch/token-history.json")
    private static let window: TimeInterval = 31 * 86_400

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH"
        return formatter
    }()

    // MARK: Public

    func report(for range: TokenHistoryRange, now: Date = Date()) -> TokenHistoryReport {
        refresh()

        var hours: [String: TokenBucket] = [:]
        for state in files.values {
            for (hour, bucket) in state.hours {
                var merged = hours[hour, default: TokenBucket()]
                for (agent, count) in bucket.tokens { merged.tokens[agent, default: 0] += count }
                merged.claudeValue += bucket.claudeValue
                hours[hour] = merged
            }
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let rangeStart = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: today) ?? today
        let starts: [Date] = range.isHourly
            ? (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: today) }
            : (0..<range.dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: rangeStart) }

        var bars: [TokenHistoryReport.Bar] = []
        var totals: [AgentKind: Int] = [:]
        var value = 0.0
        for start in starts {
            var tokens: [AgentKind: Int] = [:]
            let hourCount = range.isHourly ? 1 : 24
            for offset in 0..<hourCount {
                guard let hourDate = calendar.date(byAdding: .hour, value: offset, to: start),
                      let bucket = hours[Self.hourFormatter.string(from: hourDate)] else { continue }
                for (raw, count) in bucket.tokens {
                    guard let agent = AgentKind(rawValue: raw) else { continue }
                    tokens[agent, default: 0] += count
                    totals[agent, default: 0] += count
                }
                value += bucket.claudeValue
            }
            bars.append(.init(start: start, tokens: tokens))
        }
        return TokenHistoryReport(range: range, bars: bars, totals: totals, claudeValue: value,
                                  rangeStart: rangeStart, rangeEnd: now)
    }

    // MARK: Refresh

    private func refresh() {
        if !loadedCache {
            loadedCache = true
            if let data = try? Data(contentsOf: Self.cacheURL),
               let cached = try? JSONDecoder().decode([String: FileState].self, from: data) {
                files = cached
            }
        }

        let cutoff = Date().addingTimeInterval(-Self.window)
        var seen = Set<String>()
        for (url, kind) in Self.logFiles(since: cutoff) {
            seen.insert(url.path)
            update(url, kind: kind)
        }
        // Forget files that fell out of the window or were deleted
        files = files.filter { seen.contains($0.key) }

        try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(files) {
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
    }

    private enum LogKind { case claude, codex, deepseek }

    private static func logFiles(since cutoff: Date) -> [(URL, LogKind)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots: [(URL, LogKind, (URL) -> Bool)] = [
            (ClaudePaths.projectsDir, .claude, { $0.pathExtension == "jsonl" }),
            (home.appendingPathComponent(".codex/sessions"), .codex, { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }),
            (home.appendingPathComponent(".dsh/sessions"), .deepseek, { $0.lastPathComponent == "session.v4.jsonl.zstd" }),
        ]
        var result: [(URL, LogKind)] = []
        for (root, kind, matches) in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
            ) else { continue }
            for case let url as URL in enumerator where matches(url) {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if modified >= cutoff { result.append((url, kind)) }
            }
        }
        return result
    }

    private func update(_ url: URL, kind: LogKind) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64 else { return }
        var state = files[url.path] ?? FileState(size: 0, offset: 0, hours: [:])
        if size < state.size { state = FileState(size: 0, offset: 0, hours: [:]) }  // rewritten
        guard size > state.size else { return }

        switch kind {
        case .claude, .codex:
            guard let handle = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? handle.close() }
            try? handle.seek(toOffset: state.offset)
            guard let data = try? handle.readToEnd() else { return }
            // Only consume complete lines; a partial last line is read next time
            guard let lastNewline = data.lastIndex(of: 0x0A) else { return }
            let complete = data[data.startIndex...lastNewline]
            for line in complete.split(separator: 0x0A) {
                if kind == .claude { parseClaude(Data(line), into: &state) } else { parseCodex(Data(line), into: &state) }
            }
            state.offset += UInt64(complete.count)
        case .deepseek:
            // zstd frames can't be resumed mid-file cheaply; logs are small, so re-read
            guard let data = try? Data(contentsOf: url), let decoder = ZstdStreamDecoder(),
                  let decoded = decoder.decode(data) else { return }
            state.hours = [:]
            for line in decoded.split(separator: 0x0A) { parseDeepSeek(Data(line), into: &state) }
            state.offset = size
        }
        state.size = size
        files[url.path] = state
    }

    // MARK: Parsers

    /// Claude writes one line per content block, repeating the message's usage;
    /// count each message id once.
    private func parseClaude(_ line: Data, into state: inout FileState) {
        guard line.contains(Self.usageKey), line.contains(Self.assistantType),
              let usage = Self.object(after: Self.usageKey, in: line) else { return }
        let id = Self.string(after: Self.messageIdKey, in: line)
        if let id, id == state.lastMessageId { return }
        state.lastMessageId = id

        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        guard let timestamp = Self.string(after: Self.timestampKey, in: line),
              let date = UsageFormat.date(fromISO: timestamp) else { return }

        let model = Self.string(after: Self.modelKey, in: line) ?? ""
        let price = ClaudePricing.price(for: model)
        let value = (Double(input) * price.input + Double(output) * price.output
            + Double(cacheWrite) * price.cacheWrite + Double(cacheRead) * price.cacheRead) / 1_000_000

        add(input + output + cacheWrite + cacheRead, agent: .claude, value: value, at: date, to: &state)
    }

    /// Codex reports running session totals; count the growth between events.
    private func parseCodex(_ line: Data, into state: inout FileState) {
        guard line.contains(Self.tokenCountType),
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let info = (json["payload"] as? [String: Any])?["info"] as? [String: Any],
              let total = (info["total_token_usage"] as? [String: Any])?["total_tokens"] as? Int,
              let date = (json["timestamp"] as? String).flatMap(UsageFormat.date(fromISO:)) else { return }
        let growth = total - (state.lastCodexTotal ?? 0)
        state.lastCodexTotal = total
        if growth > 0 { add(growth, agent: .codex, value: 0, at: date, to: &state) }
    }

    private func parseDeepSeek(_ line: Data, into state: inout FileState) {
        guard line.contains(Self.deepseekAssistant),
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let data = json["data"] as? [String: Any],
              let total = (data["usage"] as? [String: Any])?["totalTokens"] as? Int,
              let time = json["time"] as? Double else { return }
        add(total, agent: .deepseek, value: 0, at: UsageFormat.date(fromEpoch: time), to: &state)
    }

    private func add(_ tokens: Int, agent: AgentKind, value: Double, at date: Date, to state: inout FileState) {
        let key = Self.hourFormatter.string(from: date)
        var bucket = state.hours[key, default: TokenBucket()]
        bucket.tokens[agent.rawValue, default: 0] += tokens
        bucket.claudeValue += value
        state.hours[key] = bucket
    }

    // MARK: Byte helpers (avoid parsing whole multi-KB lines)

    private static let usageKey = Data("\"usage\":".utf8)
    private static let assistantType = Data("\"type\":\"assistant\"".utf8)
    private static let messageIdKey = Data("\"id\":\"msg_".utf8)
    private static let timestampKey = Data("\"timestamp\":\"".utf8)
    private static let modelKey = Data("\"model\":\"".utf8)
    private static let tokenCountType = Data("\"token_count\"".utf8)
    private static let deepseekAssistant = Data("\"assistant/message\"".utf8)

    private static func string(after key: Data, in line: Data) -> String? {
        guard let range = line.range(of: key),
              let end = line[range.upperBound...].firstIndex(of: 0x22) else { return nil }
        return String(decoding: line[range.upperBound..<end], as: UTF8.self)
    }

    /// Parses the flat JSON object that follows `key` (the usage object).
    private static func object(after key: Data, in line: Data) -> [String: Any]? {
        guard let range = line.range(of: key), let open = line[range.upperBound...].firstIndex(of: 0x7B) else { return nil }
        var depth = 0
        var index = open
        while index < line.endIndex {
            switch line[index] {
            case 0x7B: depth += 1
            case 0x7D:
                depth -= 1
                if depth == 0 {
                    return try? JSONSerialization.jsonObject(with: line[open...index]) as? [String: Any]
                }
            default: break
            }
            index = line.index(after: index)
        }
        return nil
    }
}

nonisolated private extension Data {
    func contains(_ other: Data) -> Bool { range(of: other) != nil }
}

// MARK: - Pricing

/// Claude API list prices per million tokens, used only to estimate what
/// Claude Code usage would cost at API rates. Cache writes are priced at
/// 1.25x input, cache reads at the listed rate or 0.1x input.
nonisolated enum ClaudePricing {
    struct Price {
        let input: Double
        let output: Double
        let cacheWrite: Double
        let cacheRead: Double

        init(_ input: Double, _ output: Double, cacheRead: Double? = nil) {
            self.input = input
            self.output = output
            self.cacheWrite = input * 1.25
            self.cacheRead = cacheRead ?? input * 0.1
        }
    }

    static func price(for model: String) -> Price {
        let id = model.lowercased()
        switch true {
        case id.contains("fable-5-1"), id.contains("mythos"): return Price(10, 50, cacheRead: 0.25)
        case id.contains("fable"): return Price(10, 50)
        case id.contains("opus-5-5"): return Price(4, 20, cacheRead: 0.20)
        case id.contains("opus-5"), id.contains("opus-4-8"), id.contains("opus-4-7"),
             id.contains("opus-4-6"), id.contains("opus-4-5"): return Price(5, 25)
        case id.contains("opus"): return Price(15, 75)
        case id.contains("sonnet-5-5"): return Price(2, 10, cacheRead: 0.20)
        case id.contains("sonnet-5"): return Price(2, 10)
        case id.contains("sonnet"): return Price(3, 15)
        case id.contains("haiku-5-5"): return Price(0.10, 0.50)
        case id.contains("haiku-4-5"): return Price(1, 5)
        case id.contains("haiku"): return Price(0.8, 4)
        default: return Price(4, 20, cacheRead: 0.20)  // unknown: current default model
        }
    }
}
