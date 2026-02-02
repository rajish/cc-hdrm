import Foundation
import os

/// Checks GitHub Releases for newer app versions. All failures are silent (.debug log only).
final class UpdateCheckService: UpdateCheckServiceProtocol, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "update"
    )

    private static let owner = "rajish"
    private static let repo = "cc-hdrm"

    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let dataLoader: DataLoader
    private let appState: AppState
    private let preferencesManager: any PreferencesManagerProtocol
    private let currentVersion: String

    /// Production initializer — uses URLSession.shared.
    @MainActor
    init(appState: AppState, preferencesManager: any PreferencesManagerProtocol) {
        self.dataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
        self.appState = appState
        self.preferencesManager = preferencesManager
        self.currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Test initializer — injects network layer and version.
    @MainActor
    init(
        dataLoader: @escaping DataLoader,
        appState: AppState,
        preferencesManager: any PreferencesManagerProtocol,
        currentVersion: String
    ) {
        self.dataLoader = dataLoader
        self.appState = appState
        self.preferencesManager = preferencesManager
        self.currentVersion = currentVersion
    }

    func checkForUpdate() async {
        Self.logger.debug("Checking for updates (current: \(self.currentVersion))")

        let url = URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("cc-hdrm/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 5

        do {
            let (data, response) = try await dataLoader(request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                Self.logger.debug("GitHub API returned non-200 status")
                return
            }

            let decoder = JSONDecoder()
            let release = try decoder.decode(GitHubRelease.self, from: data)

            let remoteVersion = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName

            guard Self.isNewer(remoteVersion, than: currentVersion) else {
                Self.logger.debug("No update available (remote: \(remoteVersion))")
                return
            }

            if remoteVersion == preferencesManager.dismissedVersion {
                Self.logger.debug("Version \(remoteVersion) was dismissed by user, skipping update notification")
                return
            }

            // Find DMG asset first, then ZIP, fall back to release page URL
            let downloadURL: URL
            if let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
               let assetURL = URL(string: dmgAsset.browserDownloadUrl) {
                downloadURL = assetURL
            } else if let zipAsset = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
                      let assetURL = URL(string: zipAsset.browserDownloadUrl) {
                downloadURL = assetURL
            } else if let fallbackURL = URL(string: release.htmlUrl) {
                downloadURL = fallbackURL
            } else {
                Self.logger.debug("No valid download URL found in release")
                return
            }

            let update = AvailableUpdate(version: remoteVersion, downloadURL: downloadURL)
            Self.logger.debug("Update available: \(remoteVersion)")

            await MainActor.run {
                appState.updateAvailableUpdate(update)
            }
        } catch {
            Self.logger.debug("Update check failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Semver Comparison

    /// Returns true if `remote` version is strictly newer than `local` using numeric comparison.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        guard r.count == 3, l.count == 3 else { return false }
        return (r[0], r[1], r[2]) > (l[0], l[1], l[2])
    }

    // MARK: - GitHub API Response Model

    private struct GitHubRelease: Codable {
        let tagName: String
        let htmlUrl: String
        let assets: [Asset]

        struct Asset: Codable {
            let name: String
            let browserDownloadUrl: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case assets
        }
    }
}
