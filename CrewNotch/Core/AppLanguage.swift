//
//  AppLanguage.swift
//  CrewNotch
//
//  The languages CrewNotch ships in, and switching the app's language
//  independently of the system (applied after a relaunch).
//

import AppKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case chinese = "zh-Hans"
    case hindi = "hi"
    case spanish = "es"
    case french = "fr"
    case arabic = "ar"
    case portuguese = "pt-BR"
    case russian = "ru"
    case japanese = "ja"
    case turkish = "tr"

    var id: String { rawValue }

    /// Each language named in itself, so it's recognizable whatever the current language
    var nativeName: String {
        switch self {
        case .system: return String(localized: "System default")
        case .english: return "English"
        case .chinese: return "简体中文"
        case .hindi: return "हिन्दी"
        case .spanish: return "Español"
        case .french: return "Français"
        case .arabic: return "العربية"
        case .portuguese: return "Português (Brasil)"
        case .russian: return "Русский"
        case .japanese: return "日本語"
        case .turkish: return "Türkçe"
        }
    }

    private static let key = "AppleLanguages"

    /// The language chosen in CrewNotch, or `.system` when following macOS.
    static var current: AppLanguage {
        guard let codes = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key] as? [String],
              let first = codes.first else { return .system }
        return AppLanguage(rawValue: first) ?? .system
    }

    static func select(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: key)
        }
    }

    /// Starts a fresh copy of the app and quits this one.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; open -n \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
