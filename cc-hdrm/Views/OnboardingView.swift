import SwiftUI

/// First-run onboarding view displayed in an NSPanel on initial launch.
/// Explains what the app does and offers Sign In or Later.
struct OnboardingView: View {
    var onSignIn: @MainActor () -> Void
    var onLater: @MainActor () -> Void

    @AccessibilityFocusState private var isSignInFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("cc-hdrm")
                .font(.title2)
                .fontWeight(.bold)

            Text("Monitor your Claude subscription usage from the menu bar — always visible, zero tokens spent.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)

            Text("Sign in with your Anthropic account to get started. This is a one-time setup.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)

            Spacer()
                .frame(height: 16)

            Button("Sign In") {
                onSignIn()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .accessibilityFocused($isSignInFocused)

            Button("Later") {
                onLater()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.callout)
            .focusEffectDisabled()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .accessibilityElement(children: .contain)
        .onAppear {
            isSignInFocused = true
        }
    }
}
