//
//  AwayNotificationsSection.swift
//  CrewNotch
//
//  Settings → Notifications: macOS notifications and phone pushes (ntfy)
//  for when you're not looking at the notch.
//

import SwiftUI
import UserNotifications

struct AwayNotificationsSection: View {
    @AppStorage(FeatureKeys.macNotifications) private var macDelivery: NotificationDelivery = .off
    @AppStorage(FeatureKeys.phoneNotifications) private var phoneDelivery: NotificationDelivery = .off
    @AppStorage(FeatureKeys.awayAfterMinutes) private var awayAfterMinutes = 5
    @AppStorage(FeatureKeys.notifyNeedsYou) private var notifyNeedsYou = true
    @AppStorage(FeatureKeys.notifyFinished) private var notifyFinished = true
    @AppStorage(FeatureKeys.notifyUsageAlerts) private var notifyUsageAlerts = true
    @AppStorage(FeatureKeys.ntfyServer) private var server = "https://ntfy.sh"
    @AppStorage(FeatureKeys.ntfyTopic) private var topic = ""
    @AppStorage(FeatureKeys.phoneIncludesDetails) private var includesDetails = false

    @State private var macDenied = false
    @State private var testState: TestState = .idle

    private enum TestState { case idle, sending, sent, failed }

    var body: some View {
        Section {
            Picker("Mac notifications", selection: $macDelivery) {
                ForEach(NotificationDelivery.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: macDelivery) { _, value in
                guard value != .off else { return }
                Task { macDenied = !(await SystemNotifier.shared.requestAuthorization()) }
            }
            if macDenied {
                HStack {
                    Text("Notifications are off for CrewNotch in System Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
            }
            Picker("Phone notifications", selection: $phoneDelivery) {
                ForEach(NotificationDelivery.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: phoneDelivery) { _, value in
                if value != .off && topic.isEmpty { topic = PhoneNotifier.randomTopic() }
            }
            Picker("I'm away after", selection: $awayAfterMinutes) {
                Text("2 minutes").tag(2)
                Text("5 minutes").tag(5)
                Text("10 minutes").tag(10)
                Text("15 minutes").tag(15)
                Text("30 minutes").tag(30)
            }
            .disabled(macDelivery != .whenAway && phoneDelivery != .whenAway)
        } header: {
            Text("Beyond the notch")
        } footer: {
            Text("“When I'm away” sends only after this long without using the Mac, or while the screen is locked.")
                .foregroundStyle(.secondary)
        }

        Section("Send notifications for") {
            Toggle("Approvals and questions", isOn: $notifyNeedsYou)
            Toggle("Finished turns and commands", isOn: $notifyFinished)
            Toggle("Plan limit alerts", isOn: $notifyUsageAlerts)
        }
        .disabled(macDelivery == .off && phoneDelivery == .off)

        if phoneDelivery != .off {
            phoneSection
        }
    }

    private var phoneSection: some View {
        Section {
            TextField("Server", text: $server, prompt: Text("https://ntfy.sh"))
            HStack {
                TextField("Topic", text: $topic)
                    .font(.system(.body, design: .monospaced))
                Button("New Topic") { topic = PhoneNotifier.randomTopic() }
            }
            if let url = PhoneNotifier.subscribeURL(server: server.isEmpty ? "https://ntfy.sh" : server, topic: topic),
               !topic.isEmpty, let qr = PhoneNotifier.qrCode(for: url.absoluteString) {
                HStack(alignment: .top, spacing: 16) {
                    Image(decorative: qr, scale: 2)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 112, height: 112)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Install the free ntfy app on your phone, then scan this code or subscribe to the topic.")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(url.absoluteString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack {
                            Button("Send Test") { sendTest() }
                                .disabled(testState == .sending)
                            switch testState {
                            case .sending: ProgressView().controlSize(.small)
                            case .sent: Label("Sent", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            case .failed: Label("Couldn't reach the server", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                            case .idle: EmptyView()
                            }
                        }
                        .font(.callout)
                    }
                }
                .padding(.vertical, 4)
            }
            Toggle(isOn: $includesDetails) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include project and request")
                    Text("Off: pushes only say which agent needs you. On: they include the project, command or message.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Phone (ntfy)")
        } footer: {
            Text("Pushes go through the ntfy server above. Anyone who knows the topic can read them, so keep it private, or use your own server.")
                .foregroundStyle(.secondary)
        }
    }

    private func sendTest() {
        testState = .sending
        Task {
            testState = await PhoneNotifier.sendTest() ? .sent : .failed
        }
    }
}

/// Settings → Usage: alerts when a plan limit runs low or resets.
struct UsageAlertsSection: View {
    @AppStorage(FeatureKeys.usageAlerts) private var enabled = true
    @AppStorage(FeatureKeys.usageWarnPercent) private var warnPercent = 80
    @AppStorage(FeatureKeys.usageCriticalPercent) private var criticalPercent = 95
    @AppStorage(FeatureKeys.usageResetAlerts) private var resetAlerts = true

    var body: some View {
        Section {
            Toggle("Alert when a limit runs low", isOn: $enabled)
            Picker("Warn at", selection: $warnPercent) {
                ForEach([60, 70, 80, 90], id: \.self) { Text("\($0)%").tag($0) }
            }
            .disabled(!enabled)
            Picker("Urgent at", selection: $criticalPercent) {
                ForEach([90, 95, 99], id: \.self) { Text("\($0)%").tag($0) }
            }
            .disabled(!enabled)
            Toggle("Tell me when a limit resets", isOn: $resetAlerts)
                .disabled(!enabled)
        } header: {
            Text("Alerts")
        } footer: {
            Text("The notch drops down once per crossing. To get these on your Mac or phone too, see Notifications.")
                .foregroundStyle(.secondary)
        }
    }
}
