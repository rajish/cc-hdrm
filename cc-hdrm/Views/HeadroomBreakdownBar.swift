import SwiftUI

/// Typed stub for the headroom breakdown bar component.
///
/// Accepts real data types and interface that Stories 14.3-14.5 will implement
/// as a three-band visualization. Currently renders summary info about reset events.
struct HeadroomBreakdownBar: View {
    let resetEvents: [ResetEvent]
    let creditLimits: CreditLimits?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)

            content
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .accessibilityLabel("Headroom breakdown")
    }

    @ViewBuilder
    private var content: some View {
        if creditLimits == nil {
            Text("Headroom breakdown unavailable -- unknown subscription tier")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if resetEvents.isEmpty {
            Text("No reset events in this period")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Headroom breakdown: \(resetEvents.count) reset \(resetEvents.count == 1 ? "event" : "events") in period")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        HeadroomBreakdownBar(resetEvents: [], creditLimits: CreditLimits(fiveHourCredits: 100, sevenDayCredits: 909))
        HeadroomBreakdownBar(resetEvents: [], creditLimits: nil)
    }
    .padding()
    .frame(width: 600)
}
#endif
