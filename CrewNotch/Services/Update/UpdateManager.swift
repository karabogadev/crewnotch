//
//  UpdateManager.swift
//  CrewNotch
//
//  Checks GitHub Releases for a newer version. CrewNotch does not
//  self-update: "Download" opens the release page in the browser.
//

import AppKit
import Combine
import Foundation

/// Update state published to UI
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case found(version: String, releaseNotes: String?)
    case downloading(progress: Double)  // 0.0 to 1.0
    case extracting(progress: Double)
    case readyToInstall(version: String)
    case installing
    case error(message: String)

    var isActive: Bool {
        switch self {
        case .idle, .upToDate, .error:
            return false
        default:
            return true
        }
    }
}

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    static let repository = "karabogadev/crewnotch"
    static let releasesPage = URL(string: "https://github.com/\(repository)/releases/latest")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    @Published var state: UpdateState = .idle
    @Published var hasUnseenUpdate: Bool = false
    private var hasSeenUpdateThisSession = false
    private var releaseURL: URL = UpdateManager.releasesPage

    private init() {}

    // MARK: - Public API

    /// Queries the latest GitHub release. Pass `userInitiated: false` for background
    /// checks so that "up to date" and errors don't flash in the UI.
    func checkForUpdates(userInitiated: Bool = true) {
        if userInitiated { state = .checking }
        Task {
            do {
                let release = try await fetchLatestRelease()
                apply(release)
            } catch {
                state = userInitiated ? .error(message: "Couldn't reach GitHub") : .idle
            }
        }
    }

    func downloadAndInstall() {
        NSWorkspace.shared.open(releaseURL)
    }

    func installAndRelaunch() {
        NSWorkspace.shared.open(releaseURL)
    }

    func skipUpdate() {
        state = .idle
    }

    func dismissUpdate() {
        state = .idle
    }

    func cancelDownload() {
        state = .idle
    }

    func markUpdateSeen() {
        hasUnseenUpdate = false
        hasSeenUpdateThisSession = true
    }

    // MARK: - Private

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        let body: String?
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body, draft, prerelease
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: Self.latestReleaseAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private func apply(_ release: Release) {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        guard !release.draft, !release.prerelease,
              latest.compare(current, options: .numeric) == .orderedDescending else {
            state = .upToDate
            return
        }

        releaseURL = release.htmlURL
        state = .found(version: latest, releaseNotes: release.body)
        if !hasSeenUpdateThisSession {
            hasUnseenUpdate = true
        }
    }
}
