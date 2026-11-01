//
//  AgentsPane.swift
//  CrewNotch
//
//  Every supported agent: whether it's on this Mac, and connecting or
//  disconnecting CrewNotch's hooks.
//

import AppKit
import SwiftUI

struct AgentsPane: View {
    @ObservedObject private var registry = AgentRegistry.shared
    @State private var claudeFolder = ClaudePaths.claudeDir.path

    private var detected: [AgentKind] { AgentKind.connectable.filter { registry.status(for: $0).isDetected } }
    private var missing: [AgentKind] { AgentKind.connectable.filter { !registry.status(for: $0).isDetected } }

    var body: some View {
        Form {
            Section("On this Mac") {
                if detected.isEmpty {
                    Text("Looking for agents…").foregroundStyle(.secondary)
                }
                ForEach(detected) { agent in
                    AgentRow(agent: agent, status: registry.status(for: agent))
                }
            }

            if !missing.isEmpty {
                Section("Not installed") {
                    ForEach(missing) { agent in
                        AgentRow(agent: agent, status: registry.status(for: agent))
                    }
                }
            }

            Section {
                LabeledContent("Folder") {
                    Text(claudeFolder)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Choose…", action: chooseClaudeFolder)
                    Button("Auto-detect") { setClaudeFolder("") }
                }
            } header: {
                Text("Claude Code folder")
            } footer: {
                Text("Only needed when Claude Code uses a custom config folder.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await registry.refresh() }
    }

    private func chooseClaudeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = ClaudePaths.claudeDir
        panel.message = "Select the folder Claude Code uses (usually ~/.claude)."
        if panel.runModal() == .OK, let url = panel.url {
            setClaudeFolder(url.path)
        }
    }

    private func setClaudeFolder(_ path: String) {
        AppSettings.claudeDirectoryName = path
        ClaudePaths.invalidateCache()
        claudeFolder = ClaudePaths.claudeDir.path
        if AppSettings.connectedAgents.contains(.claude) {
            Task { await registry.connect(.claude) }
        }
    }
}

struct AgentRow: View {
    let agent: AgentKind
    let status: AgentRegistry.Status
    @State private var isWorking = false

    private var subtitle: String {
        if !status.isDetected { return String(localized: "Not found on this Mac") }
        if status.isConnected {
            return agent.supportsApproval
                ? String(localized: "Connected · live status and approvals")
                : String(localized: "Connected · live status")
        }
        return String(localized: "Detected · not connected")
    }

    var body: some View {
        HStack(spacing: 12) {
            AgentIcon(agent: agent, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(status.isConnected ? Color.green : Color.secondary)
                if status.isConnected, let note = AgentIntegrations.all[agent]?.setupNote {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if let error = status.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            if status.isDetected {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Button(status.isConnected ? "Disconnect" : "Connect") {
                        isWorking = true
                        Task {
                            if status.isConnected {
                                await AgentRegistry.shared.disconnect(agent)
                            } else {
                                await AgentRegistry.shared.connect(agent)
                            }
                            isWorking = false
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(status.isDetected ? 1 : 0.55)
    }
}
