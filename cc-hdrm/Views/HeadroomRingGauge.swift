import SwiftUI

/// A circular ring gauge that visualizes headroom percentage.
/// Depletes clockwise from 12 o'clock as headroom decreases.
/// Reusable for both 5-hour (96px/7px) and 7-day (56px/4px) gauges.
struct HeadroomRingGauge: View {
    /// Headroom percentage (0–100). `nil` means disconnected.
    let headroomPercentage: Double?
    /// Label shown above the gauge (e.g. "5h", "7d").
    let windowLabel: String
    /// Diameter of the ring.
    let ringSize: CGFloat
    /// Stroke width of the ring.
    let strokeWidth: CGFloat
    /// Optional slope level to display below percentage. Defaults to `nil` for backward compatibility.
    let slopeLevel: SlopeLevel?

    /// Initializer with default nil slope for backward compatibility.
    init(
        headroomPercentage: Double?,
        windowLabel: String,
        ringSize: CGFloat,
        strokeWidth: CGFloat,
        slopeLevel: SlopeLevel? = nil
    ) {
        self.headroomPercentage = headroomPercentage
        self.windowLabel = windowLabel
        self.ringSize = ringSize
        self.strokeWidth = strokeWidth
        self.slopeLevel = slopeLevel
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Headroom state derived from percentage — never stored separately.
    private var headroomState: HeadroomState {
        guard let headroomPercentage else { return .disconnected }
        // HeadroomState init expects utilization (100 - headroom)
        return HeadroomState(from: 100.0 - headroomPercentage)
    }

    /// Fill amount for the ring arc (0.0–1.0).
    private var fillAmount: CGFloat {
        max(0, (headroomPercentage ?? 0)) / 100.0
    }

    /// Color for the ring fill and center text.
    private var fillColor: Color {
        headroomState.swiftUIColor
    }

    /// Center text: percentage, "0%", or em dash for disconnected.
    private var centerText: String {
        guard let headroomPercentage else { return "\u{2014}" } // em dash
        return "\(Int(max(0, headroomPercentage)))%"
    }

    /// Accessibility description of the current state.
    private var accessibilityDescription: String {
        guard let headroomPercentage else {
            return "\(windowLabel) headroom: unavailable"
        }
        return "\(windowLabel) headroom: \(Int(max(0, headroomPercentage))) percent"
    }

    var body: some View {
        ZStack {
            // Track (full ring, tertiary color)
            Circle()
                .stroke(
                    Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )

            // Fill (partial ring, headroom color)
            Circle()
                .trim(from: 0, to: fillAmount)
                .stroke(
                    fillColor,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90)) // Start from 12 o'clock
                .animation(
                    reduceMotion ? .none : .easeInOut(duration: 0.5),
                    value: fillAmount
                )

            // Center content: percentage + optional slope
            VStack(spacing: 0) {
                Text(centerText)
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(fillColor)

                // Slope indicator: shown only when slope provided AND connected
                if let slope = slopeLevel, headroomPercentage != nil {
                    SlopeIndicator(slopeLevel: slope, headroomState: headroomState)
                }
            }
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(
            headroomPercentage.map { "\(Int(max(0, $0))) percent" } ?? ""
        )
    }
}
