import Foundation
import Security
import os

/// Reads and writes cc-hdrm's own OAuth credentials from/to the macOS Keychain.
/// Uses a distinct service name ("cc-hdrm-oauth") separate from Claude Code's item.
/// NEVER logs token values. NEVER persists credentials to disk outside Keychain.
final class OAuthKeychainService: KeychainServiceProtocol, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "oauth-keychain"
    )

    private static let serviceName = "cc-hdrm-oauth"
    private static let accountName = "anthropic-oauth"

    /// Reuse result types from KeychainService for consistency.
    typealias KeychainResult = KeychainService.KeychainResult
    typealias KeychainWriteResult = KeychainService.KeychainWriteResult

    /// Abstraction for Keychain data retrieval — enables test injection.
    private let dataProvider: @Sendable () -> KeychainResult

    /// Abstraction for Keychain data writing — enables test injection.
    private let writeProvider: @Sendable (Data) -> KeychainWriteResult

    /// Production initializer — reads from and writes to real Keychain.
    init() {
        self.dataProvider = {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: OAuthKeychainService.serviceName,
                kSecAttrAccount as String: OAuthKeychainService.accountName,
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
            let baseQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: OAuthKeychainService.serviceName,
                kSecAttrAccount as String: OAuthKeychainService.accountName
            ]

            // Try update first
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

            if updateStatus == errSecSuccess {
                return .success
            }

            if updateStatus == errSecItemNotFound {
                // Item doesn't exist — add with proper ACL
                var addQuery = baseQuery
                addQuery[kSecValueData as String] = data
                addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
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
            Self.logger.info("No OAuth credentials found in Keychain")
            throw AppError.keychainNotFound
        case .accessDenied:
            Self.logger.error("Keychain access denied — check entitlements and permissions")
            throw AppError.keychainAccessDenied
        case .error(let status):
            Self.logger.error("Keychain query failed with OSStatus: \(status)")
            throw AppError.keychainAccessDenied
        }

        // Parse JSON directly — our own item stores flat credential JSON
        do {
            let credentials = try JSONDecoder().decode(KeychainCredentials.self, from: data)
            Self.logger.info("Successfully read OAuth credentials from Keychain (subscription: \(credentials.subscriptionType ?? "unknown", privacy: .public))")
            return credentials
        } catch {
            Self.logger.error("Failed to decode OAuth credentials: \(error.localizedDescription)")
            throw AppError.keychainInvalidFormat
        }
    }

    func writeCredentials(_ credentials: KeychainCredentials) async throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(credentials)
        } catch {
            Self.logger.error("Failed to encode credentials for Keychain write: \(error.localizedDescription)")
            throw AppError.keychainInvalidFormat
        }

        let writeResult = writeProvider(data)
        switch writeResult {
        case .success:
            Self.logger.info("Successfully wrote OAuth credentials to Keychain")
        case .error(let status):
            Self.logger.error("Keychain write failed with OSStatus: \(status)")
            throw AppError.keychainAccessDenied
        }
    }

    /// Deletes the OAuth credentials from the Keychain.
    func deleteCredentials() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: Self.accountName
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Self.logger.error("Keychain delete failed with OSStatus: \(status)")
            throw AppError.keychainAccessDenied
        }
        Self.logger.info("OAuth credentials deleted from Keychain")
    }
}
