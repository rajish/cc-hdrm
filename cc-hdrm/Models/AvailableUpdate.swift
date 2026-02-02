import Foundation

/// Represents an available app update with version and download URL.
struct AvailableUpdate: Sendable, Equatable {
    let version: String
    let downloadURL: URL
}
