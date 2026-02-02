import Foundation
import Security
import os

/// Reads and writes Claude Code OAuth credentials from/to the macOS Keychain.
/// NEVER logs token values. NEVER persists credentials to disk.
final class KeychainService: KeychainServiceProtocol, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "keychain"
    )

    private static let serviceName = "Claude Code-credentials"

    /// Result type for Keychain data retrieval — preserves OSStatus for error differentiation.
    enum KeychainResult: Sendable {
        case success(Data)
        case notFound
        case accessDenied
        case error(OSStatus)
    }

    /// Result type for Keychain write operations.
    enum KeychainWriteResult: Sendable {
        case success
        case error(OSStatus)
    }

    /// Abstraction for Keychain data retrieval — enables test injection.
    private let dataProvider: @Sendable () -> KeychainResult

    /// Abstraction for Keychain data writing — enables test injection.
    private let writeProvider: @Sendable (Data) -> KeychainWriteResult

    /// Production initializer — reads from and writes to real Keychain.
    init() {
        self.dataProvider = {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: KeychainService.serviceName,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            switch status {
            case errSecSuccess:
                guard let data = result as? Data else {
                    return .error(status)
                }
                return .success(data)
            case errSecItemNotFound:
                return .notFound
            case errSecAuthFailed, errSecInteractionNotAllowed:
                return .accessDenied
            default:
                return .error(status)
            }
        }

        self.writeProvider = { data in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: KeychainService.serviceName
            ]

            // Try update first
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

            if updateStatus == errSecSuccess {
                return .success
            }

            if updateStatus == errSecItemNotFound {
                // Item doesn't exist — add it
                var addQuery = query
                addQuery[kSecValueData as String] = data
                let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
                if addStatus == errSecSuccess {
                    return .success
                }
                return .error(addStatus)
            }

            return .error(updateStatus)
        }
    }

    /// Test initializer — injects data provider and write provider.
    init(
        dataProvider: @escaping @Sendable () -> KeychainResult,
        writeProvider: @escaping @Sendable (Data) -> KeychainWriteResult = { _ in .success }
    ) {
        self.dataProvider = dataProvider
        self.writeProvider = writeProvider
    }

    func readCredentials() async throws -> KeychainCredentials {
        let result = dataProvider()
        let data: Data
        switch result {
        case .success(let d):
            data = d
        case .notFound:
            Self.logger.info("No Claude Code credentials found in Keychain")
            throw AppError.keychainNotFound
        case .accessDenied:
            Self.logger.error("Keychain access denied — check entitlements and permissions")
            throw AppError.keychainAccessDenied
        case .error(let status):
            Self.logger.error("Keychain query failed with OSStatus: \(status)")
            throw AppError.keychainAccessDenied
        }

        // Parse outer JSON to extract claudeAiOauth object
        let outerObject: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Self.logger.error("Keychain data is not a JSON object")
                throw AppError.keychainInvalidFormat
            }
            outerObject = parsed
        } catch let error as AppError {
            throw error
        } catch {
            Self.logger.error("Failed to parse Keychain JSON: \(error.localizedDescription)")
            throw AppError.keychainInvalidFormat
        }

        guard let oauthObject = outerObject["claudeAiOauth"] else {
            Self.logger.error("Keychain JSON missing 'claudeAiOauth' key")
            throw AppError.keychainInvalidFormat
        }

        // Re-serialize the inner object and decode to KeychainCredentials
        let oauthData: Data
        do {
            oauthData = try JSONSerialization.data(withJSONObject: oauthObject)
        } catch {
            Self.logger.error("Failed to serialize claudeAiOauth object: \(error.localizedDescription)")
            throw AppError.keychainInvalidFormat
        }

        do {
            let credentials = try JSONDecoder().decode(KeychainCredentials.self, from: oauthData)
            Self.logger.info("Successfully read credentials from Keychain (subscription: \(credentials.subscriptionType ?? "unknown", privacy: .public))")
            return credentials
        } catch {
            Self.logger.error("Failed to decode claudeAiOauth: \(error.localizedDescription)")
            throw AppError.keychainInvalidFormat
        }
    }

    func writeCredentials(_ credentials: KeychainCredentials) async throws {
        // Read existing Keychain data to preserve outer JSON structure
        var outerObject: [String: Any]

        let readResult = dataProvider()
        switch readResult {
        case .success(let existingData):
            if let parsed = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                outerObject = parsed
            } else {
                outerObject = [:]
            }
        case .notFound:
            outerObject = [:]
        case .accessDenied:
            Self.logger.error("Keychain access denied during write — check entitlements")
            throw AppError.keychainAccessDenied
        case .error(let status):
            Self.logger.error("Keychain read failed during write with OSStatus: \(status)")
            throw AppError.keychainAccessDenied
        }

        // Encode credentials to JSON and merge into claudeAiOauth
        let credentialData = try JSONEncoder().encode(credentials)
        guard let credentialDict = try JSONSerialization.jsonObject(with: credentialData) as? [String: Any] else {
            Self.logger.error("Failed to serialize credentials for Keychain write")
            throw AppError.keychainInvalidFormat
        }

        // Preserve existing claudeAiOauth fields not in the new credentials
        var existingOauth = outerObject["claudeAiOauth"] as? [String: Any] ?? [:]
        for (key, value) in credentialDict {
            existingOauth[key] = value
        }
        outerObject["claudeAiOauth"] = existingOauth

        let updatedJSON = try JSONSerialization.data(withJSONObject: outerObject)

        let writeResult = writeProvider(updatedJSON)
        switch writeResult {
        case .success:
            Self.logger.info("Successfully wrote credentials to Keychain")
        case .error(let status):
            Self.logger.error("Keychain write failed with OSStatus: \(status)")
            throw AppError.keychainAccessDenied
        }
    }
}
