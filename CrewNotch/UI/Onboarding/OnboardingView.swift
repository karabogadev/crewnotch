//
//  OnboardingView.swift
//  CrewNotch
//
//  First launch: what CrewNotch does, connect the agents found on this Mac,
//  and pick a few preferences. Nothing is installed without a click.
//

import ServiceManagement
import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable { case welcome, agents, preferences }
    @State private var step: Step = .welcome

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: WelcomeStep()
                case .agents: ConnectAgentsStep()
                case .preferences: PreferencesStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 36)

            HStack {
                if step != .welcome {
                    Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StepDots(count: Step.allCases.count, current: step.rawValue)
                Spacer()
                Button(step == .preferences ? "Done" : "Continue") {
                    if let next = Step(rawValue: step.rawValue + 1) {
                        step = next
                    } else {
                        AppSettings.hasCompletedOnboarding = true
                        onFinish()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
            .padding(24)
        }
        .frame(width: 640, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            VStack(spacing: 6) {
                Text("Welcome to CrewNotch")
                    .font(.system(size: 28, weight: .bold))
                Text("All your coding agents, live in the notch.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                Feature(icon: "rectangle.3.group", title: "One notch for every agent",
                        text: "Claude Code, Codex, Cursor, Gemini, Antigravity and more, side by side.")
                Feature(icon: "bell.badge", title: "Know when you're needed",
                        text: "A sound and a glance when a turn finishes or an agent asks for approval.")
                Feature(icon: "arrow.up.forward.app", title: "Back in one click",
                        text: "Double-click a session to jump to its terminal or app window.")
                Feature(icon: "lock.shield", title: "Stays on your Mac",
                        text: "No account and no analytics. Agent activity never leaves this computer.")
            }
            .padding(.top, 6)
        }
    }
}

private struct Feature: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ConnectAgentsStep: View {
    @ObservedObject private var registry = AgentRegistry.shared

    private var detected: [AgentKind] { AgentKind.allCases.filter { registry.status(for: $0).isDetected } }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Connect your agents")
                    .font(.system(size: 26, weight: .bold))
                Text("We found these on your Mac. Connecting adds a small hook so CrewNotch can see when they work, finish or need you. Your other settings stay untouched.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Form {
                if detected.isEmpty {
                    Text("No supported agents found yet. You can connect them later in Settings → Agents.")
                        .foregroundStyle(.secondary)
                }
                ForEach(detected) { agent in
                    AgentRow(agent: agent, status: registry.status(for: agent))
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if detected.contains(where: { !registry.status(for: $0).isConnected }) {
                Button("Connect all") {
                    Task {
                        for agent in detected where !registry.status(for: agent).isConnected {
                            await registry.connect(agent)
                        }
                    }
                }
            }
        }
        .task { await registry.refresh() }
    }
}

private struct PreferencesStep: View {
    @AppStorage("approveFromNotch") private var approveFromNotch = true
    @AppStorage("groupByProject") private var groupByProject = false
    @AppStorage("showPlanUsage") private var showPlanUsage = true
    @AppStorage("claudeUsageAllowed") private var claudeUsageAllowed = false
    @ObservedObject private var keepAwake = KeepAwakeController.shared
    @State private var sounds = AppSettings.notificationSound != .none
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Make it yours")
                    .font(.system(size: 26, weight: .bold))
                Text("You can change all of this later in Settings.")
                    .foregroundStyle(.secondary)
            }

            Form {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if enabled { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                    }
                Toggle("Notification sounds", isOn: $sounds)
                    .onChange(of: sounds) { _, on in
                        AppSettings.notificationSound = on ? .pop : .none
                        AppSettings.attentionSound = on ? .glass : .none
                    }
                Toggle("Approve from the notch (Claude Code, Codex)", isOn: $approveFromNotch)
                Toggle("Group sessions by project", isOn: $groupByProject)
                Toggle(isOn: Binding(get: { keepAwake.isEnabled }, set: { keepAwake.setEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep agents running when the display sleeps")
                        Text("On power adapter, up to 3 hours at a time.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Show plan usage", isOn: $showPlanUsage)
                Toggle(isOn: Binding(
                    get: { claudeUsageAllowed && UsageMonitor.shared.isEnabled(.claude) },
                    set: { UsageMonitor.shared.setClaudeAllowed($0); claudeUsageAllowed = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include Claude usage")
                        Text("macOS asks once to read Claude Code's sign-in: choose Always Allow.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!showPlanUsage)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}
