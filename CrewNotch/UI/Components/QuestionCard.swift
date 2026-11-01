//
//  QuestionCard.swift
//  CrewNotch
//
//  Answers an agent's multiple-choice question (Claude Code's
//  AskUserQuestion) right in the notch: pick an option, tick several,
//  or type your own answer.
//

import SwiftUI

/// One question from an AskUserQuestion call.
nonisolated struct AgentQuestion: Identifiable, Equatable, Sendable {
    nonisolated struct Option: Equatable, Sendable {
        let label: String
        let description: String?
    }

    let id: Int
    let text: String
    let header: String?
    let options: [Option]
    let multiSelect: Bool

    static func parse(_ input: [String: Any]) -> [AgentQuestion] {
        guard let raw = input["questions"] as? [[String: Any]] else { return [] }
        return raw.enumerated().compactMap { index, item in
            guard let text = item["question"] as? String, !text.isEmpty else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> Option? in
                guard let label = option["label"] as? String, !label.isEmpty else { return nil }
                return Option(label: label, description: option["description"] as? String)
            }
            return AgentQuestion(
                id: index,
                text: text,
                header: item["header"] as? String,
                options: options,
                multiSelect: item["multiSelect"] as? Bool ?? false
            )
        }
    }

    /// A lone single-choice question is answered with one click.
    static func isOneClick(_ questions: [AgentQuestion]) -> Bool {
        questions.count == 1 && !questions[0].multiSelect && !questions[0].options.isEmpty
    }
}

struct QuestionCard: View {
    let questions: [AgentQuestion]
    var showsShortcuts = false
    let onSubmit: ([String: String]) -> Void
    var onOpenAgent: (() -> Void)? = nil

    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    @AppStorage(AppearanceKeys.accentMode) private var accent: AccentMode = .full
    @State private var selections: [Int: Set<Int>] = [:]
    @State private var typed: [Int: String] = [:]
    @State private var submitted = false

    private var scale: CGFloat { textScale.factor }
    private var oneClick: Bool { AgentQuestion.isOneClick(questions) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(questions) { question in
                questionView(question)
            }
            HStack(spacing: 8) {
                if let onOpenAgent {
                    Button(action: onOpenAgent) {
                        Text("Answer in the agent")
                            .font(.system(size: 10.5 * scale))
                            .foregroundColor(.ink.opacity(0.45))
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 8)
                if !oneClick || hasTypedAnswer {
                    SoftPill(title: "Send", prominent: true, hint: showsShortcuts ? "⌘↩" : nil) { submit() }
                        .disabled(!isComplete || submitted)
                        .opacity(isComplete ? 1 : 0.45)
                }
            }
        }
        .disabled(submitted)
    }

    private func questionView(_ question: AgentQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let header = question.header, !header.isEmpty {
                    Text(header)
                        .font(.system(size: 9.5 * scale, weight: .semibold))
                        .foregroundColor(accent.attentionColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accent.attentionColor.opacity(0.14)))
                }
                Text(question.text)
                    .font(.system(size: 12 * scale, weight: .medium))
                    .foregroundColor(.ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    optionButton(question: question, index: index, option: option)
                }
            }

            TextField(question.options.isEmpty ? "Your answer" : "Other answer", text: Binding(
                get: { typed[question.id] ?? "" },
                set: { typed[question.id] = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 11 * scale))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.ink.opacity(0.06)))
            .onSubmit { if isComplete { submit() } }
        }
    }

    private func optionButton(question: AgentQuestion, index: Int, option: AgentQuestion.Option) -> some View {
        let selected = selections[question.id]?.contains(index) == true
        return Button {
            toggle(question: question, index: index)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if question.multiSelect {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 11 * scale))
                        .foregroundColor(selected ? .ink.opacity(0.9) : .ink.opacity(0.4))
                } else if oneClick && showsShortcuts && index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                        .foregroundColor(.ink.opacity(0.45))
                        .frame(width: 14)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: 11.5 * scale, weight: .medium))
                        .foregroundColor(.ink.opacity(0.9))
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 10.5 * scale))
                            .foregroundColor(.ink.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.ink.opacity(0.14) : Color.ink.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Answering

    private func toggle(question: AgentQuestion, index: Int) {
        if question.multiSelect {
            var set = selections[question.id] ?? []
            if set.contains(index) { set.remove(index) } else { set.insert(index) }
            selections[question.id] = set
        } else {
            selections[question.id] = [index]
            if oneClick { submit() }
        }
    }

    private var hasTypedAnswer: Bool {
        typed.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var isComplete: Bool {
        questions.allSatisfy { answer(for: $0) != nil }
    }

    /// The chosen labels joined with ", ", plus any typed text.
    private func answer(for question: AgentQuestion) -> String? {
        let labels = (selections[question.id] ?? []).sorted().compactMap { index in
            question.options.indices.contains(index) ? question.options[index].label : nil
        }
        let text = (typed[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = question.multiSelect ? labels + (text.isEmpty ? [] : [text]) : (text.isEmpty ? labels : [text])
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func submit() {
        guard !submitted, isComplete else { return }
        var answers: [String: String] = [:]
        for question in questions {
            answers[question.text] = answer(for: question)
        }
        submitted = true
        onSubmit(answers)
    }
}
