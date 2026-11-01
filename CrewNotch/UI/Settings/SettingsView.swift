//
//  SettingsView.swift
//  CrewNotch
//
//  The Settings window: General, Notifications, Appearance, Agents, About.
//

import AppKit
import Combine
import ServiceManagement
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, notifications, appearance, usage, agents, about

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .notifications: return "bell.badge.fill"
        case .appearance: return "paintbrush.fill"
        case .usage: return "gauge.with.dots.needle.67percent"
        case .agents: return "terminal.fill"
        case .about: return "info.circle.fill"
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var pane: SettingsPane = .general
}

struct SettingsView: View {
    @ObservedObject private var navigation = SettingsNavigation.shared

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(
                get: { navigation.pane },
                set: { if let pane = $0 { navigation.pane = pane } }
            )) { pane in
                Label(pane.title, systemImage: pane.icon)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch navigation.pane {
                case .general: GeneralPane()
                case .notifications: NotificationsPane()
                case .appearance: AppearancePane()
                case .usage: UsagePane()
                case .agents: AgentsPane()
                case .about: AboutPane()
                }
            }
            .navigationTitle(navigation.pane.title)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject private var screens = ScreenSelector.shared
    @ObservedObject private var keepAwake = KeepAwakeController.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("keepAwakeMaxHours") private var maxHours = 3
    @AppStorage("keepAwakeMinBattery") private var minBattery = 20
    @AppStorage("keepAwakeRequiresAdapter") private var requiresAdapter = true

    private var keepAwakeStatus: String {
        switch keepAwake.state {
        case .active(let until): return "On until \(until.formatted(date: .omitted, time: .shortened))"
        case .paused(let reason): return "Paused: \(reason)"
        case .off: return "Off"
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Show notch on") {
                Picker("Display", selection: Binding(
                    get: { screens.selectionMode == .automatic ? nil : screens.selectedScreen.map(ScreenIdentifier.init(screen:)) },
                    set: { identifier in
                        if let identifier, let screen = screens.availableScreens.first(where: identifier.matches) {
                            screens.selectScreen(screen)
                        } else {
                            screens.selectAutomatic()
                        }
                        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                    }
                )) {
                    Text("Automatic (built-in display first)").tag(ScreenIdentifier?.none)
                    ForEach(screens.availableScreens, id: \.self) { screen in
                        Text(screen.localizedName).tag(Optional(ScreenIdentifier(screen: screen)))
                    }
                }
            }

            Section {
                Toggle(isOn: Binding(get: { keepAwake.isEnabled }, set: { keepAwake.setEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep agents running")
                        Text(keepAwakeStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Stepper("Turn off after \(maxHours) hour\(maxHours == 1 ? "" : "s")", value: $maxHours, in: 1...12)
                Toggle("Only on power adapter", isOn: $requiresAdapter)
                Picker("On battery, stop below", selection: $minBattery) {
                    ForEach([10, 20, 30, 50], id: \.self) { Text("\($0)%").tag($0) }
                }
                .disabled(requiresAdapter)
            } header: {
                Text("Keep Awake")
            } footer: {
                Text("Your Mac stays awake while the display sleeps or the screen is locked. Closing the lid still puts it to sleep.")
                    .foregroundStyle(.secondary)
            }
            .onChange(of: maxHours) { keepAwake.setEnabled(keepAwake.isEnabled) }
            .onChange(of: requiresAdapter) { keepAwake.setEnabled(keepAwake.isEnabled) }
            .onChange(of: minBattery) { keepAwake.setEnabled(keepAwake.isEnabled) }

            Section {
                Button("Quit CrewNotch", role: .destructive) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .onAppear { screens.refreshScreens() }
    }
}

// MARK: - Appearance

private struct AppearancePane: View {
    @AppStorage("groupByProject") private var groupByProject = true

    var body: some View {
        Form {
            Section("Session list") {
                Toggle("Group by project", isOn: $groupByProject)
            }

            AnimationSettingsSection()
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutPane: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("CrewNotch")
                .font(.system(size: 26, weight: .bold))
            Text("Every AI coding agent, live in your MacBook notch.")
                .foregroundStyle(.secondary)
            Text(version)
                .font(.callout)
                .foregroundStyle(.tertiary)
            Link("github.com/karabogadev/crewnotch", destination: URL(string: "https://github.com/karabogadev/crewnotch")!)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Animations

private struct AnimationSettingsSection: View {
    @AppStorage("animationSpeed") private var speed: NotchEffectSpeed = .normal

    var body: some View {
        Section {
            ForEach(NotchMoment.allCases) { moment in
                AnimationMomentRow(moment: moment)
            }
            Picker("Speed", selection: $speed) {
                ForEach(NotchEffectSpeed.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Animations")
        } footer: {
            Text("Press play to preview an animation in the notch.").foregroundStyle(.secondary)
        }
    }
}

private struct AnimationMomentRow: View {
    let moment: NotchMoment
    @AppStorage private var style: NotchEffectStyle

    init(moment: NotchMoment) {
        self.moment = moment
        _style = AppStorage(wrappedValue: moment.defaultStyle, moment.settingsKey)
    }

    var body: some View {
        HStack {
            Picker(moment.title, selection: $style) {
                ForEach(NotchEffectStyle.allCases) { Text($0.title).tag($0) }
            }
            Button {
                NotchEffects.shared.play(style, tint: moment.tint)
            } label: {
                Image(systemName: "play.circle.fill").font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(style == .none)
            .help("Preview")
        }
    }
}
