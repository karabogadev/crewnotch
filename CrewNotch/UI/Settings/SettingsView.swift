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

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .notifications: return String(localized: "Notifications")
        case .appearance: return String(localized: "Appearance")
        case .usage: return String(localized: "Usage")
        case .agents: return String(localized: "Agents")
        case .about: return String(localized: "About")
        }
    }

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
        case .active(let until): return String(localized: "On until \(until.formatted(date: .omitted, time: .shortened))")
        case .paused(let reason): return String(localized: "Paused: \(reason)")
        case .off: return String(localized: "Off")
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
                Stepper("Turn off after \(maxHours) h", value: $maxHours, in: 1...12)
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
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    @AppStorage("groupByProject") private var groupByProject = false
    @AppStorage(AppearanceKeys.titleOrder) private var titleOrder: TitleOrder = .conversation
    @AppStorage(AppearanceKeys.material) private var material: PanelMaterial = .solid
    @AppStorage(AppearanceKeys.tint) private var tint: PanelTint = .black
    @AppStorage(AppearanceKeys.closedShowsWorking) private var closedShowsWorking = true
    @AppStorage(AppearanceKeys.closedShowsNotifications) private var closedShowsNotifications = true
    @AppStorage(AppearanceKeys.closedShowsUsage) private var closedShowsUsage = false
    @AppStorage(AppearanceKeys.idleNotch) private var idleNotch: IdleNotchBehavior = .hide
    @AppStorage(AppearanceKeys.idleAfterMinutes) private var idleAfterMinutes = 30
    @AppStorage(AppearanceKeys.hideIdleSessions) private var hideIdleSessions = false
    @AppStorage(AppearanceKeys.rowsAtOnce) private var rowsAtOnce = 5
    @AppStorage(AppearanceKeys.accentMode) private var accent: AccentMode = .full
    @AppStorage(AppearanceKeys.showSubagents) private var showSubagents = true

    var body: some View {
        Form {
            Section {
                Picker("Text size", selection: $textScale) {
                    ForEach(TextScale.allCases) { Text($0.title).tag($0) }
                }
                Picker("Material", selection: $material) {
                    ForEach(PanelMaterial.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Accent colors", selection: $accent) {
                    ForEach(AccentMode.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Color") {
                    HStack(spacing: 10) {
                        ForEach(PanelTint.allCases) { option in
                            Button {
                                tint = option
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                            .opacity(tint == option ? 1 : 0)
                                    )
                                    .padding(2)
                                    .overlay(Circle().stroke(tint == option ? Color.white : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .help(option.title)
                        }
                    }
                }
            } header: {
                Text("Panel")
            } footer: {
                Text("The closed notch always stays black so it blends with the camera housing.")
                    .foregroundStyle(.secondary)
            }

            Section("While closed") {
                Toggle("Working agents", isOn: $closedShowsWorking)
                Toggle("Notifications (finished, needs you)", isOn: $closedShowsNotifications)
                Toggle("Plan usage", isOn: $closedShowsUsage)
                Picker("When idle", selection: $idleNotch) {
                    ForEach(IdleNotchBehavior.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Session list") {
                Toggle("Group by project", isOn: $groupByProject)
                Toggle(isOn: $showSubagents) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show subagents")
                        Text("Delegating sessions get a badge; click it to see what each subagent is doing.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("First line", selection: $titleOrder) {
                    ForEach(TitleOrder.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Rows at once: \(rowsAtOnce)", value: $rowsAtOnce, in: 3...10)
                Picker("Mark a session idle after", selection: $idleAfterMinutes) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("4 hours").tag(240)
                    Text("Never").tag(0)
                }
                Picker("Idle sessions", selection: $hideIdleSessions) {
                    Text("Dim").tag(false)
                    Text("Hide").tag(true)
                }
                .pickerStyle(.segmented)
            }

            WorkingIndicatorSection()

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
        return String(localized: "Version \(short) (\(build))")
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

// MARK: - Working indicator

private struct WorkingIndicatorSection: View {
    @AppStorage("workingIndicatorStyle") private var style: WorkingIndicatorStyle = .crewDots
    @AppStorage("workingIndicatorColor") private var color: WorkingIndicatorColor = .crew

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        Section {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(WorkingIndicatorStyle.allCases) { option in
                    Button {
                        style = option
                    } label: {
                        VStack(spacing: 8) {
                            WorkingIndicatorView(style: option, color: color, size: 18)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black))
                            Text(option.title)
                                .font(.caption)
                                .foregroundStyle(style == option ? .primary : .secondary)
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(style == option ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            Picker("Colors", selection: $color) {
                ForEach(WorkingIndicatorColor.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Working indicator")
        } footer: {
            Text("Shown in the closed notch and next to sessions while an agent works.").foregroundStyle(.secondary)
        }
    }
}
