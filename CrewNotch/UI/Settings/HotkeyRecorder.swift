//
//  HotkeyRecorder.swift
//  CrewNotch
//
//  Click, press the new shortcut. ⎋ cancels, ⌫ clears it.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotkeyRecorder: View {
    @State private var hotkey: Hotkey? = Hotkey.saved
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(label)
                    .font(.system(.body, design: isRecording || hotkey == nil ? .default : .rounded).weight(.medium))
                    .foregroundStyle(isRecording ? Color.accentColor : (hotkey == nil ? .secondary : .primary))
                    .frame(minWidth: 110)
            }
            .help(isRecording ? "Press a key with ⌘, ⌃ or ⌥. ⎋ cancels, ⌫ removes the shortcut." : "Click to record a new shortcut")

            if hotkey != nil && !isRecording {
                Button {
                    save(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove the shortcut")
            }
        }
        .onDisappear { stopRecording() }
    }

    private var label: String {
        if isRecording { return rejected ? String(localized: "Add ⌘, ⌃ or ⌥") : String(localized: "Type shortcut…") }
        return hotkey?.displayString ?? String(localized: "Record Shortcut")
    }

    private func startRecording() {
        isRecording = true
        rejected = false
        // The current shortcut would fire while you press it again
        GlobalHotkey.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Escape:
                stopRecording()
            case kVK_Delete, kVK_ForwardDelete:
                save(nil)
                stopRecording()
            default:
                if let recorded = Hotkey(event: event) {
                    save(recorded)
                    stopRecording()
                } else {
                    rejected = true
                }
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            GlobalHotkey.shared.registerSaved()
        }
    }

    private func save(_ value: Hotkey?) {
        Hotkey.saved = value
        hotkey = value
        GlobalHotkey.shared.registerSaved()
    }
}
