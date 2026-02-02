import Foundation
import Testing
@testable import cc_hdrm

@Suite("UpdateCheckService Tests")
struct UpdateCheckServiceTests {

    // MARK: - Helpers

    private static let githubURL = URL(string: "https://api.github.com/repos/rajish/cc-hdrm/releases/latest")!

    private static func makeRelease(
        tagName: String = "v2.0.0",
        htmlUrl: String = "https://github.com/rajish/cc-hdrm/releases/tag/v2.0.0",
        assets: [[String: String]] = [
            ["name": "cc-hdrm-2.0.0.dmg", "browser_download_url": "https://github.com/rajish/cc-hdrm/releases/download/v2.0.0/cc-hdrm-2.0.0.dmg"],
            ["name": "cc-hdrm-v2.0.0-macos.zip", "browser_download_url": "https://github.com/rajish/cc-hdrm/releases/download/v2.0.0/cc-hdrm-v2.0.0-macos.zip"]
        ]
    ) -> String {
        let assetsJSON = assets.map { asset in
            """
            {"name": "\(asset["name"]!)", "browser_download_url": "\(asset["browser_download_url"]!)"}
            """
        }.joined(separator: ", ")
        return """
        {"tag_name": "\(tagName)", "html_url": "\(htmlUrl)", "assets": [\(assetsJSON)]}
        """
    }

    private static func makeSuccessResponse(json: String) -> (Data, URLResponse) {
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(url: githubURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }

    private static func makeErrorResponse(statusCode: Int) -> (Data, URLResponse) {
        let data = "error".data(using: .utf8)!
        let response = HTTPURLResponse(url: githubURL, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }

    @MainActor
    private static func makeSUT(
        json: String? = nil,
        statusCode: Int = 200,
        throwError: Error? = nil,
        currentVersion: String = "1.0.0",
        dismissedVersion: String? = nil
    ) -> (UpdateCheckService, AppState, MockPreferencesManager) {
        let appState = AppState()
        let prefs = MockPreferencesManager()
        prefs.dismissedVersion = dismissedVersion

        let dataLoader: UpdateCheckService.DataLoader
        if let error = throwError {
            dataLoader = { _ in throw error }
        } else if let json {
            dataLoader = { _ in makeSuccessResponse(json: json) }
        } else {
            dataLoader = { _ in makeErrorResponse(statusCode: statusCode) }
        }

        let service = UpdateCheckService(
            dataLoader: dataLoader,
            appState: appState,
            preferencesManager: prefs,
            currentVersion: currentVersion
        )

        return (service, appState, prefs)
    }

    // MARK: - Newer version available → sets availableUpdate

    @Test("newer version sets availableUpdate with DMG asset URL (preferred over ZIP)")
    @MainActor
    func newerVersionSetsUpdate() async {
        let json = Self.makeRelease(tagName: "v2.0.0")
        let (sut, appState, _) = Self.makeSUT(json: json, currentVersion: "1.0.0")

        await sut.checkForUpdate()

        #expect(appState.availableUpdate?.version == "2.0.0")
        #expect(appState.availableUpdate?.downloadURL.absoluteString == "https://github.com/rajish/cc-hdrm/releases/download/v2.0.0/cc-hdrm-2.0.0.dmg")
    }

    // MARK: - Same version → nil

    @Test("same version keeps availableUpdate nil")
    @MainActor
    func sameVersionNoUpdate() async {
        let json = Self.makeRelease(tagName: "v1.0.0")
        let (sut, appState, _) = Self.makeSUT(json: json, currentVersion: "1.0.0")

        await sut.checkForUpdate()

        #expect(appState.availableUpdate == nil)
    }

    // MARK: - Older version → nil

    @Test("older version keeps availableUpdate nil")
    @MainActor
    func olderVersionNoUpdate() async {
        let json = Self.makeRelease(tagName: "v0.9.0")
        let (sut, appState, _) = Self.makeSUT(json: json, currentVersion: "1.0.0")

        await sut.checkForUpdate()

        #expect(appState.availableUpdate == nil)
    }

    // MARK: - Network failure → silent

    @Test("network failure is silent, no error state")
    @MainActor
    func networkFailureSilent() async {
        let (sut, appState, _) = Self.makeSUT(throwError: URLError(.notConnectedToInternet), currentVersion: "1.0.0")

        await sut.checkForUpdate()

        #expect(appState.availableUpdate == nil)
        #expect(appState.connectionStatus == .disconnected) // unchanged default
    }

    // MARK: - Malformed JSON → silent

    @Test("malformed JSON is silent, no error state")
    @MainActor
    func malformedJSONSilent() async {
        let (sut, appState, _) = Self.makeSUT(json: "{invalid json!!!}", currentVersion: "1.0.0")

        await sut.checkForUpdate()

        #expect(appState.availableUpdate == nil)
    }

    // MARK: - Missing assets → falls back to htmlUrl

    @Test("missing DMG and ZIP assets falls back to htmlUrl")
    @MainActor
    func missingAssetsFallback() async {
        let json = Self.makeRelease(
            tagName: "v2.0.0",
            htmlUrl: "https://github.com/rajish/cc-hdrm/releases/tag/v2.0.0",
            assets: [["name": "something-else.tar.gz", "browser_download_url": "https://example.com/other.tar.gz"]]
        )
        let (sut, appState, _) = Self.makeSUT(json: json, currentVersion: "1.0.0")

        await sut.checkForUpdate()

        #expect(appState.availableUpdate?.version == "2.0.0")
        #expect(appState.availableUpdate?.downloadURL.absoluteString == "https://github.com/rajish/cc-hdrm/releases/tag/v2.0.0")
    }

    // MARK: - Empty assets → falls back to htmlUrl

    @Test("empty assets array falls back to htmlUrl")
    @MainActor
    func emptyAssetsFallback() async {
        let json = Self.makeRelease(
            tagName: "v2.0.0",
            htmlUrl: "https://github.com/rajish/cc-hdrm/releases/tag/v2.0.0",
            assets: []
        )
        let (sut, appState, _) = Self.makeSUT(json: json, currentVersion: "1.0.0")

        await sut.checkForUpdate()

        #expect(appState.availableUpdate?.version == "2.0.0")
        #expect(appState.availableUpdate?.downloadURL.absoluteString == "https://github.com/rajish/cc-hdrm/releases/tag/v2.0.0")
    }

    // MARK: - No DMG → falls back to ZIP

    @Test("missing DMG asset falls back to ZIP asset")
    @MainActor
    func missingDMGFallsBackToZip() async {
        let json = Self.makeRelease(
            tagName: "v2.0.0",
            assets: [["name": "cc-hdrm-v2.0.0-macos.zip", "browser_download_url": "https://github.com/rajish/cc-hdrm/releases/download/v2.0.0/cc-hdrm-v2.0.0-macos.zip"]]
        )
        let (sut, appState, _) = Self.makeSUT(json: json, currentVersion: "1.0.0")

        await sut.checkForUpdate()

        #expect(appState.availableUpdate?.version == "2.0.0")
        #expect(appState.availableUpdate?.downloadURL.absoluteString == "https://github.com/rajish/cc-hdrm/releases/download/v2.0.0/cc-hdrm-v2.0.0-macos.zip")
    }

    // MARK: - Dismissed version → nil

    @Test("dismissed version keeps availableUpdate nil")
    @MainActor
    func dismissedVersionNoUpdate() async {
        let json = Self.makeRelease(tagName: "v2.0.0")
        let (sut, appState, _) = Self.makeSUT(json: json, currentVersion: "1.0.0", dismissedVersion: "2.0.0")

        await sut.checkForUpdate()

        #expect(appState.availableUpdate == nil)
    }

    // MARK: - Semver comparison edge cases

    @Test("semver: 1.0.10 is newer than 1.0.9")
    func semverPatchEdge() {
        #expect(UpdateCheckService.isNewer("1.0.10", than: "1.0.9") == true)
    }

    @Test("semver: 2.0.0 is newer than 1.99.99")
    func semverMajorEdge() {
        #expect(UpdateCheckService.isNewer("2.0.0", than: "1.99.99") == true)
    }

    @Test("semver: 1.0.0 is not newer than 1.0.0")
    func semverEqual() {
        #expect(UpdateCheckService.isNewer("1.0.0", than: "1.0.0") == false)
    }

    @Test("semver: 1.0.0 is not newer than 2.0.0")
    func semverOlder() {
        #expect(UpdateCheckService.isNewer("1.0.0", than: "2.0.0") == false)
    }

    @Test("semver: malformed version returns false")
    func semverMalformed() {
        #expect(UpdateCheckService.isNewer("abc", than: "1.0.0") == false)
        #expect(UpdateCheckService.isNewer("1.0", than: "1.0.0") == false)
    }

    // MARK: - Non-200 response → silent

    @Test("non-200 response is silent")
    @MainActor
    func non200Silent() async {
        let (sut, appState, _) = Self.makeSUT(statusCode: 403, currentVersion: "1.0.0")

        await sut.checkForUpdate()

        #expect(appState.availableUpdate == nil)
    }

    // MARK: - Tag without v prefix

    @Test("tag without v prefix is handled correctly")
    @MainActor
    func tagWithoutVPrefix() async {
        let json = Self.makeRelease(tagName: "2.0.0")
        let (sut, appState, _) = Self.makeSUT(json: json, currentVersion: "1.0.0")

        await sut.checkForUpdate()

        #expect(appState.availableUpdate?.version == "2.0.0")
    }
}
