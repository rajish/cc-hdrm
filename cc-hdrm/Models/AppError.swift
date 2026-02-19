import Foundation

/// All application error cases as defined in the Architecture specification.
enum AppError: Error, Sendable, Equatable {
    case keychainNotFound
    case keychainAccessDenied
    case keychainInvalidFormat
    case tokenExpired
    case tokenRefreshFailed(underlying: any Error & Sendable)
    case networkUnreachable
    case apiError(statusCode: Int, body: String?)
    case parseError(underlying: any Error & Sendable)
    case databaseOpenFailed(path: String)
    case databaseSchemaFailed(underlying: any Error & Sendable)
    case databaseQueryFailed(underlying: any Error & Sendable)
    case oauthAuthorizationFailed(String)
    case oauthTokenExchangeFailed(underlying: any Error & Sendable)
    case oauthCallbackTimeout

    static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.keychainNotFound, .keychainNotFound),
             (.keychainAccessDenied, .keychainAccessDenied),
             (.keychainInvalidFormat, .keychainInvalidFormat),
             (.tokenExpired, .tokenExpired),
             (.networkUnreachable, .networkUnreachable),
             (.oauthCallbackTimeout, .oauthCallbackTimeout):
            return true
        case (.tokenRefreshFailed, .tokenRefreshFailed):
            return true
        case let (.apiError(lCode, lBody), .apiError(rCode, rBody)):
            return lCode == rCode && lBody == rBody
        case (.parseError, .parseError):
            return true
        case let (.databaseOpenFailed(lPath), .databaseOpenFailed(rPath)):
            return lPath == rPath
        case (.databaseSchemaFailed, .databaseSchemaFailed):
            return true
        case (.databaseQueryFailed, .databaseQueryFailed):
            return true
        case let (.oauthAuthorizationFailed(lMsg), .oauthAuthorizationFailed(rMsg)):
            return lMsg == rMsg
        case (.oauthTokenExchangeFailed, .oauthTokenExchangeFailed):
            return true
        default:
            return false
        }
    }
}
