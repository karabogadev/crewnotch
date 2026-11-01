//
//  RecentSessionsSection.swift
//  CrewNotch
//
//  "Recently ended" at the bottom of the session list: reopen a finished
//  conversation in a terminal, or copy the command that does.
//

import SwiftUI

struct RecentSessionsSection: View {
    @ObservedObject var recents: RecentSessions
    let onResumed: () -> Void

    @AppStorage("recentSessionsExpanded") private var expanded = false
    @AppStorage(FeatureKeys.resumeTerminal) private var resumeTerminal: ResumeTerminal = .automatic
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text("Recently ended")
                    Text("\(recents.items.count)")
                        .foregroundColor(.ink.opacity(0.3))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8 * textScale.factor, weight: .bold))
                    Spacer()
                }
                .font(.system(size: 11 * textScale.factor, weight: .semibold))
                .foregroundColor(.ink.opacity(0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)
            .padding(.top, 6)

            if expanded {
                ForEach(recents.items) { item in
                    RecentSessionRow(item: item, resumeTerminal: resumeTerminal, onResumed: onResumed) {
                        recents.forget(item)
                    }
                }
            }
        }
    }
}

private struct RecentSessionRow: View {
    let item: RecentSession
    let resumeTerminal: ResumeTerminal
    let onResumed: () -> Void
    let onForget: () -> Void

    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    @State private var isHovered = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            AgentIcon(agent: item.agent, size: 15)
                .frame(width: 30)
                .opacity(0.8)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12 * textScale.factor, weight: .medium))
                    .foregroundColor(.ink.opacity(0.75))
                    .lineLimit(1)
                Text("\(item.projectName) · \(RelativeTime.short(since: item.endedAt))")
                    .font(.system(size: 10.5 * textScale.factor))
                    .foregroundColor(.ink.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let command = item.resumeCommand {
                if isHovered {
                    IconButton(icon: copied ? "checkmark" : "doc.on.doc") { copy(command) }
                        .help("Copy the resume command")
                    IconButton(icon: "xmark") { onForget() }
                        .help("Remove from the list")
                }
                SoftPill(title: "Resume", prominent: false) { resume(command) }
                    .help(command)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.ink.opacity(isHovered ? 0.05 : 0.025)))
        .onHover { isHovered = $0 }
    }

    private func resume(_ command: String) {
        Task {
            if await TerminalLauncher.run(command, preferred: resumeTerminal, sessionTerminal: item.terminalBundleId) {
                onResumed()
            } else {
                copy(command)
            }
        }
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
