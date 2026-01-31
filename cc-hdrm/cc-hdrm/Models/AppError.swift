import Foundation

/// All application error cases as defined in the Architecture specification.
enum AppError: Error, Sendable {
    case keychainNotFound
    case keychainAccessDenied
    case keychainInvalidFormat
    case tokenExpired
    case tokenRefreshFailed(underlying: any Error & Sendable)
    case networkUnreachable
    case apiError(statusCode: Int, body: String?)
    case parseError(underlying: any Error & Sendable)
}
