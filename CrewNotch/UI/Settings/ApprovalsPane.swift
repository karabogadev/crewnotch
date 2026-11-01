//
//  ApprovalsPane.swift
//  CrewNotch
//
//  Settings → Approvals: answering agents from the notch, what a request
//  shows before you allow it, and the extra ways to answer.
//

import SwiftUI

struct ApprovalsPane: View {
    @AppStorage("approveFromNotch") private var approveFromNotch = true
    @AppStorage(FeatureKeys.showApprovalDetails) private var showDetails = true
    @AppStorage(FeatureKeys.warnRiskyCommands) private var warnRisky = true
    @AppStorage(FeatureKeys.offerAlwaysAllow) private var offerAlwaysAllow = true
    @AppStorage(FeatureKeys.answerQuestionsInNotch) private var answerQuestions = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $approveFromNotch) {
                    label("Answer from the notch",
                          "Claude Code, Codex and OpenCode wait for your answer in the notch. Their own prompt keeps working too; the first answer counts.")
                }
            }

            Section("Before you allow") {
                Toggle(isOn: $showDetails) {
                    label("Show the full request", "The whole command, the diff of an edit or the start of a new file.")
                }
                Toggle(isOn: $warnRisky) {
                    label("Warn about risky requests",
                          "Deleting files, force-pushing, sudo, running downloaded scripts, editing secrets or files outside the project.")
                }
            }

            Section {
                Toggle(isOn: $offerAlwaysAllow) {
                    label("Offer “Always”", "Saves the rule the agent suggests, such as Bash(npm test:*), so it stops asking.")
                }
                Toggle(isOn: $answerQuestions) {
                    label("Answer questions in the notch", "Pick an option or type an answer when Claude Code asks you something.")
                }
            } header: {
                Text("Answers")
            } footer: {
                Text("Keyboard shortcuts for answering are in General → Keyboard.")
                    .foregroundStyle(.secondary)
            }
            .disabled(!approveFromNotch)
        }
        .formStyle(.grouped)
    }

    private func label(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
