//
//  PhoneNotifier.swift
//  CrewNotch
//
//  Pushes to your phone through ntfy (ntfy.sh or your own server): install
//  the ntfy app, subscribe to your topic, done. No account. Only the agent
//  and what it wants are sent, unless you allow details.
//

import CoreImage
import Foundation

nonisolated enum PhoneNotifier {
    /// Publishes an alert; returns whether the server accepted it.
    @discardableResult
    static func send(_ alert: AttentionAlert) async -> Bool {
        let details = await MainActor.run { AppSettings.phoneIncludesDetails }
        let message: String
        if details, let detail = alert.detail, !detail.isEmpty {
            message = detail
        } else {
            message = alert.kind.isNeedsYou
                ? String(localized: "Open your Mac to answer.")
                : String(localized: "Open CrewNotch for details.")
        }
        return await publish(title: alert.title, message: message, tags: tags(for: alert.kind), priority: alert.kind.isNeedsYou ? 4 : 3)
    }

    static func sendTest() async -> Bool {
        await publish(
            title: String(localized: "CrewNotch is connected"),
            message: String(localized: "You'll get a push like this when an agent needs you."),
            tags: ["white_check_mark"],
            priority: 3
        )
    }

    private static func tags(for kind: AttentionAlert.Kind) -> [String] {
        switch kind {
        case .approval: return ["warning"]
        case .question: return ["question"]
        case .finished: return ["white_check_mark"]
        case .usage: return ["bar_chart"]
        }
    }

    /// JSON publishing keeps non-ASCII titles intact (headers can't carry them).
    private static func publish(title: String, message: String, tags: [String], priority: Int) async -> Bool {
        let (server, topic) = await MainActor.run { (AppSettings.ntfyServer, AppSettings.ntfyTopic) }
        guard !topic.isEmpty, let url = URL(string: server), url.scheme == "https" || url.scheme == "http" else { return false }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["topic": topic, "title": title, "message": message, "tags": tags, "priority": priority]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
    }

    /// A topic that is hard to guess: anyone who knows it can read your pushes.
    static func randomTopic() -> String {
        let alphabet = Array("abcdefghijkmnopqrstuvwxyz23456789")
        return "crewnotch-" + String((0..<14).map { _ in alphabet.randomElement()! })
    }

    /// Link that subscribes the ntfy app to the topic.
    static func subscribeURL(server: String, topic: String) -> URL? {
        let base = server.hasSuffix("/") ? String(server.dropLast()) : server
        return URL(string: "\(base)/\(topic)")
    }

    static func qrCode(for text: String) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
