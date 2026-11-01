//
//  NotificationsPane.swift
//  CrewNotch
//
//  Settings → Notifications: a live preview of what the notch shows in each
//  state, what appears in the notch, and the sound for each kind of event.
//

import SwiftUI

struct NotificationsPane: View {
    @AppStorage("openNotchOnRequest") private var showRequests = true
    @AppStorage("approveFromNotch") private var approveFromNotch = true
    @AppStorage("showFinishedBanner") private var showFinishedBanner = true
    @AppStorage("playSounds") private var playSounds = true

    @State private var previewState: NotchPreview.State = .finished
    @State private var previewDevice: NotchPreview.Device = .macBook

    var body: some View {
        Form {
            Section {
                NotchPreview(state: previewState, device: previewDevice)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                Picker("State", selection: $previewState) {
                    ForEach(NotchPreview.State.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                HStack {
                    Text("Preview")
                    Spacer()
                    Picker("Device", selection: $previewDevice) {
                        ForEach(NotchPreview.Device.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            } footer: {
                Text(previewState.explanation).foregroundStyle(.secondary)
            }

            Section("In the notch") {
                Toggle(isOn: $showRequests) {
                    SettingLabel("Show requests", "Open the notch for questions and approvals from connected agents.")
                }
                Toggle(isOn: $approveFromNotch) {
                    SettingLabel("Reply from the notch", "Allow or deny tool calls for agents that support it (Claude Code, Codex).")
                }
                Toggle(isOn: $showFinishedBanner) {
                    SettingLabel("Finished banner", "Drop the notch down for a moment when an agent finishes.")
                }
                Button {
                    SettingsNavigation.shared.pane = .agents
                } label: {
                    HStack {
                        Text("Set up agents")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Play sounds", isOn: $playSounds)
                SoundRow(icon: "checkmark.circle", title: "Turn finished",
                         get: { AppSettings.notificationSound }, set: { AppSettings.notificationSound = $0 })
                SoundRow(icon: "questionmark.bubble", title: "Question",
                         get: { AppSettings.questionSound }, set: { AppSettings.questionSound = $0 })
                SoundRow(icon: "exclamationmark.circle", title: "Approval needed",
                         get: { AppSettings.attentionSound }, set: { AppSettings.attentionSound = $0 })
            } header: {
                Text("Sounds")
            } footer: {
                Text("Turning sounds off or choosing None keeps the visual notifications.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SettingLabel: View {
    let title: String
    let detail: String

    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SoundRow: View {
    let icon: String
    let title: String
    let get: () -> NotificationSound
    let set: (NotificationSound) -> Void

    @AppStorage("playSounds") private var playSounds = true
    @State private var sound: NotificationSound = .none

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
            Spacer()
            Button {
                if let name = sound.soundName { NSSound(named: name)?.play() }
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.secondary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .disabled(sound == .none)
            .help("Play")
            Picker(title, selection: $sound) {
                ForEach(NotificationSound.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 150)
        }
        .disabled(!playSounds)
        .onAppear { sound = get() }
        .onChange(of: sound) { _, newValue in set(newValue) }
    }
}

// MARK: - Preview

/// A miniature of the notch showing what each state looks like.
struct NotchPreview: View {
    enum State: String, CaseIterable, Identifiable {
        case working, finished, needsYou, openPanel

        var id: String { rawValue }

        var title: String {
            switch self {
            case .working: return "Working"
            case .finished: return "Finished"
            case .needsYou: return "Needs you"
            case .openPanel: return "Open panel"
            }
        }

        var explanation: String {
            switch self {
            case .working: return "While agents work, the notch shows the busiest agent's logo and the crew dots."
            case .finished: return "When a turn finishes, the notch drops down for a moment. Click it to go back to the session."
            case .needsYou: return "Questions and approvals open the notch. Agents that support it can be answered right there."
            case .openPanel: return "Hover or click the notch to see every session, grouped by project."
            }
        }
    }

    enum Device: String, CaseIterable, Identifiable {
        case macBook, monitor
        var id: String { rawValue }
        var title: String { self == .macBook ? "MacBook" : "Monitor" }
    }

    let state: State
    let device: Device

    private let sample = SessionState(sessionId: "preview", cwd: "/Users/you/storefront", agent: .claude)

    var body: some View {
        ZStack(alignment: .top) {
            // Menu bar and desktop behind the notch
            LinearGradient(colors: [Color(white: 0.32), Color(white: 0.2)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color(white: 0.42)).frame(height: 22)

            notch
                .padding(.top, device == .macBook ? 0 : 4)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: state)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: device)
    }

    @ViewBuilder
    private var notch: some View {
        VStack(spacing: 0) {
            closedRow.frame(height: 22)
            expandedContent
        }
        .padding(.horizontal, 10)
        .padding(.bottom, state == .working ? 0 : 8)
        .frame(width: width)
        .background(Color.black)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: device == .macBook ? 0 : 11,
            bottomLeadingRadius: state == .working ? 10 : 18,
            bottomTrailingRadius: state == .working ? 10 : 18,
            topTrailingRadius: device == .macBook ? 0 : 11,
            style: .continuous
        ))
    }

    private var width: CGFloat {
        switch state {
        case .working: return 230
        case .finished: return 300
        case .needsYou: return 330
        case .openPanel: return 340
        }
    }

    @ViewBuilder
    private var closedRow: some View {
        HStack {
            AgentIcon(agent: .claude, size: 13)
            Spacer()
            switch state {
            case .working: WorkingIndicator(size: 13)
            case .needsYou: AttentionPulse(size: 13)
            case .finished: NotchStatusGlyph(status: .finished, size: 12)
            case .openPanel: Image(systemName: "gearshape").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        switch state {
        case .working:
            EmptyView()
        case .finished:
            FinishedBanner(session: sample) {}
                .allowsHitTesting(false)
        case .needsYou:
            HStack(spacing: 8) {
                AgentIcon(agent: .claude, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Needs you").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    Text("Bash  npm test").font(.system(size: 10, design: .monospaced)).foregroundColor(TerminalColors.amber)
                }
                Spacer()
                pill("Deny", filled: false)
                pill("Allow", filled: true)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
        case .openPanel:
            VStack(alignment: .leading, spacing: 6) {
                previewRow(.claude, "Fix the checkout bug", status: .working, detail: "Working · main")
                previewRow(.codex, "Write release notes", status: .finished, detail: "Done · Notes saved")
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
        }
    }

    private func pill(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(filled ? .black : .white.opacity(0.7))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(filled ? Color.white.opacity(0.9) : Color.white.opacity(0.12)))
    }

    private func previewRow(_ agent: AgentKind, _ title: String, status: CrewActivity, detail: String) -> some View {
        HStack(spacing: 8) {
            NotchStatusGlyph(status: status, size: 11).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(.white)
                HStack(spacing: 4) {
                    AgentIcon(agent: agent, size: 9)
                    Text(detail).font(.system(size: 9)).foregroundColor(.white.opacity(0.45))
                }
            }
            Spacer()
        }
    }
}
