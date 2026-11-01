//
//  ApprovalDetailView.swift
//  CrewNotch
//
//  What an approval request would actually do: the whole shell command,
//  the diff of an edit, the start of a new file, plus warnings for
//  commands worth a second look. Used by the session row and the chat bar.
//

import SwiftUI

extension PermissionContext {
    /// Tool input with plain Swift values.
    var rawInput: [String: Any] {
        toolInput?.mapValues(\.value) ?? [:]
    }

    func riskWarnings(cwd: String?) -> [String] {
        CommandRisk.warnings(toolName: toolName, input: rawInput, cwd: cwd)
    }

    /// What "Always allow" would save, e.g. "Bash(npm test:*)".
    var suggestionSummary: String? {
        guard let suggestions else { return nil }
        var parts: [String] = []
        for case let suggestion as [String: Any] in suggestions.map(\.value) {
            if let rules = suggestion["rules"] as? [[String: Any]] {
                for rule in rules {
                    guard let tool = rule["toolName"] as? String else { continue }
                    if let content = rule["ruleContent"] as? String, !content.isEmpty {
                        parts.append("\(tool)(\(content))")
                    } else {
                        parts.append(tool)
                    }
                }
            } else if suggestion["type"] as? String == "setMode", let mode = suggestion["mode"] as? String {
                parts.append(mode == "acceptEdits" ? String(localized: "Accept edits for this session") : mode)
            } else if let directories = suggestion["directories"] as? [String] {
                parts.append(contentsOf: directories)
            } else if let patterns = suggestion["patterns"] as? [String] {
                parts.append(contentsOf: patterns)  // OpenCode's "always" patterns
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

struct ApprovalDetailView: View {
    let context: PermissionContext
    let cwd: String
    var showsDetails = true
    var showsWarnings = true
    /// The rule "Always" would save, shown in the open rather than only in a tooltip
    var alwaysRule: String? = nil
    /// Inside the row's request plate: text sits on the plate instead of its own tile
    var inPlate = false

    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard

    private var input: [String: Any] { context.rawInput }
    private var warnings: [String] { showsWarnings ? context.riskWarnings(cwd: cwd) : [] }
    private var scale: CGFloat { textScale.factor }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5 * scale))
                    Text(warning)
                        .font(.system(size: 11 * scale, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(TerminalColors.red)
            }
            if showsDetails {
                detail
            }
            if let alwaysRule {
                Text("Always allows: \(alwaysRule)")
                    .font(.system(size: 10 * scale))
                    .foregroundColor(.ink.opacity(0.4))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detail: some View {
        if let command = CommandRisk.shellCommand(from: input) {
            if let description = string("description") {
                Text(description)
                    .font(.system(size: 11 * scale))
                    .foregroundColor(.ink.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            CodeBox(text: command, monospaced: true, tile: !inPlate)
        } else if let old = string("old_string", allowEmpty: true), let new = string("new_string", allowEmpty: true) {
            SimpleDiffView(oldString: old, newString: new, filename: displayPath)
        } else if let edits = input["edits"] as? [[String: Any]], let first = edits.first {
            SimpleDiffView(
                oldString: first["old_string"] as? String ?? "",
                newString: first["new_string"] as? String ?? "",
                filename: displayPath
            )
            if edits.count > 1 {
                Text("^[+\(edits.count - 1) more edit](inflect: true)")
                    .font(.system(size: 10.5 * scale))
                    .foregroundColor(.ink.opacity(0.45))
            }
        } else if let content = string("content", allowEmpty: true) {
            if let path = displayPath {
                pathLabel(path)
            }
            CodeBox(text: Self.firstLines(of: content, count: 8), monospaced: true, footer: Self.moreLinesNote(content, shown: 8), tile: !inPlate)
        } else if let plan = string("plan") {
            CodeBox(text: String(plan.prefix(1200)), monospaced: false, tile: !inPlate)
        } else {
            fieldList
        }
    }

    // MARK: - Pieces

    private func pathLabel(_ path: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc")
                .font(.system(size: 9.5 * scale))
            Text(path)
                .font(.system(size: 11 * scale, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundColor(.ink.opacity(0.6))
    }

    /// Other tools (MCP, web, search): a few of their arguments.
    private var fieldList: some View {
        let keys = input.keys.filter { $0 != "description" }.sorted()
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(keys.prefix(5)), id: \.self) { key in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(key)
                        .font(.system(size: 10.5 * scale, weight: .medium, design: .monospaced))
                        .foregroundColor(.ink.opacity(0.45))
                    Text(Self.describe(input[key]))
                        .font(.system(size: 10.5 * scale, design: .monospaced))
                        .foregroundColor(.ink.opacity(0.7))
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Helpers

    private func string(_ key: String, allowEmpty: Bool = false) -> String? {
        guard let value = input[key] as? String else { return nil }
        return allowEmpty || !value.isEmpty ? value : nil
    }

    /// The edited file, relative to the project when it is inside it.
    private var displayPath: String? {
        guard let path = string("file_path") ?? string("notebook_path") ?? string("path") else { return nil }
        let root = cwd.hasSuffix("/") ? cwd : cwd + "/"
        if !cwd.isEmpty, path.hasPrefix(root) { return String(path.dropFirst(root.count)) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func firstLines(of text: String, count: Int) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).prefix(count).joined(separator: "\n")
    }

    static func moreLinesNote(_ text: String, shown: Int) -> String? {
        let total = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return total > shown ? String(AttributedString(localized: "^[+\(total - shown) more line](inflect: true)").characters) : nil
    }

    static func describe(_ value: Any?) -> String {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        case let array as [Any]: return array.map { describe($0) }.joined(separator: ", ")
        case let dict as [String: Any]:
            guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else { return "…" }
            return text
        default: return ""
        }
    }
}

/// Monospaced text on a soft tile; long text scrolls instead of growing the card.
struct CodeBox: View {
    let text: String
    var monospaced = true
    var footer: String? = nil
    /// On its own soft tile; off when the surrounding plate already is one
    var tile = true

    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard

    private var isLong: Bool {
        text.count > 420 || text.split(separator: "\n", omittingEmptySubsequences: false).count > 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if isLong {
                    ScrollView(.vertical, showsIndicators: true) { content }
                        .frame(height: 112 * textScale.factor)
                } else {
                    content
                }
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.ink.opacity(tile ? 0.06 : 0)))

            if let footer {
                Text(footer)
                    .font(.system(size: 10 * textScale.factor))
                    .foregroundColor(.ink.opacity(0.4))
            }
        }
    }

    private var content: some View {
        Text(text)
            .font(.system(size: (tile ? 10.5 : 12) * textScale.factor, design: monospaced ? .monospaced : .default))
            .lineSpacing(tile ? 0 : 2)
            .foregroundColor(.ink.opacity(tile ? 0.8 : 0.92))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, tile ? 8 : 0)
            .padding(.vertical, tile ? 6 : 0)
    }
}
