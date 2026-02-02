import SwiftUI

extension HeadroomState {
    /// The SwiftUI `Color` for this headroom state, using semantic color tokens from the asset catalog.
    var swiftUIColor: Color {
        switch self {
        case .normal: .headroomNormal
        case .caution: .headroomCaution
        case .warning: .headroomWarning
        case .critical: .headroomCritical
        case .exhausted: .headroomExhausted
        case .disconnected: .disconnected
        }
    }
}
