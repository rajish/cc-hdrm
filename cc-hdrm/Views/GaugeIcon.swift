import AppKit
import Foundation

// MARK: - Gauge Icon Namespace

/// Namespace for menu bar gauge icon drawing functions.
///
/// Provides two icon types:
/// - `make(headroomPercentage:state:)` — Semicircular gauge for connected states
/// - `makeDisconnected()` — X icon for disconnected state
enum GaugeIcon {

    // MARK: - Constants

    /// Canvas size for menu bar icons (renders @2x on Retina as 36×36px)
    private static let canvasSize = NSSize(width: 18, height: 18)

    /// Geometry constants derived from HTML preview (gauge-icon-preview.html).
    /// Using flipped coordinates (origin top-left, Y down) to match menu bar display.
    private enum Geometry {
        /// Arc center X. Horizontally centered in 18pt canvas.
        static let centerX: CGFloat = 9.0
        /// Arc center Y. Positioned HIGH (in flipped coords) so arc bulges toward top of screen.
        static let centerY: CGFloat = 13.0
        /// Arc radius.
        static let arcRadius: CGFloat = 7.0
        /// Needle length. ~71% of arc radius for visual balance.
        static let needleLength: CGFloat = 5.0
        /// Track and fill arc stroke width.
        static let arcStrokeWidth: CGFloat = 2.0
        /// Needle stroke width.
        static let needleStrokeWidth: CGFloat = 1.5
        /// Center pivot dot radius.
        static let centerDotRadius: CGFloat = 1.5
        /// Padding for disconnected X icon.
        static let disconnectedPadding: CGFloat = 5.0
    }

    // MARK: - Public API

    /// Creates a semicircular gauge icon for the menu bar.
    ///
    /// The gauge shows:
    /// - Fill level corresponding to headroom percentage (0-100%)
    /// - Color matching the current `HeadroomState`
    /// - Needle pointing from left (0%) to right (100%)
    ///
    /// - Parameters:
    ///   - headroomPercentage: Headroom value 0-100. Values outside this range are clamped.
    ///   - state: The `HeadroomState` determining the gauge color.
    /// - Returns: An 18×18pt `NSImage` with `isTemplate = false`.
    static func make(headroomPercentage: Double, state: HeadroomState) -> NSImage {
        let image = NSImage(size: canvasSize, flipped: true) { _ in
            drawGauge(headroomPercentage: headroomPercentage, state: state)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Creates a distinct "X" icon for the disconnected state.
    ///
    /// The X icon is visually distinct from the gauge, clearly signaling
    /// that no data is available.
    ///
    /// - Returns: An 18×18pt `NSImage` with `isTemplate = false`.
    static func makeDisconnected() -> NSImage {
        let image = NSImage(size: canvasSize, flipped: true) { rect in
            drawDisconnectedX(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Calculates the needle angle for a given headroom percentage.
    ///
    /// Exposed for unit testing to verify geometry calculations.
    ///
    /// - Parameter headroomPercentage: Headroom value 0-100.
    /// - Returns: Angle in radians where 0 = right (100%), π = left (0%).
    static func angle(for headroomPercentage: Double) -> Double {
        let clampedHeadroom = max(0, min(100, headroomPercentage))
        let p = clampedHeadroom / 100.0
        return Double.pi * (1.0 - p)
    }

    // MARK: - Private Drawing

    /// Draws the gauge components: track arc, fill arc, needle, center dot.
    private static func drawGauge(headroomPercentage: Double, state: HeadroomState) {
        let cx = Geometry.centerX
        let cy = Geometry.centerY
        let radius = Geometry.arcRadius
        let needleLength = Geometry.needleLength

        // Clamp headroom to 0-100 range
        let clampedHeadroom = max(0, min(100, headroomPercentage))
        let p = clampedHeadroom / 100.0

        // Angle calculation: θ = π × (1 − p)
        // 100% (p=1) → θ=0 (right, 3 o'clock)
        // 0% (p=0) → θ=π (left, 9 o'clock)
        let theta = CGFloat.pi * (1.0 - p)

        // Get the color for this state
        let color = NSColor.headroomColor(for: state)

        // 1. Draw track arc (full semicircle, 25% opacity)
        drawTrackArc(cx: cx, cy: cy, radius: radius, color: color)

        // 2. Draw fill arc (partial semicircle from left to needle position)
        if p > 0 {
            drawFillArc(cx: cx, cy: cy, radius: radius, theta: theta, color: color)
        }

        // 3. Draw needle line (from center to needle end)
        drawNeedle(cx: cx, cy: cy, length: needleLength, theta: theta, color: color)

        // 4. Draw center dot
        drawCenterDot(cx: cx, cy: cy, color: color)
    }

    /// Draws the background track arc (full semicircle at 25% opacity).
    ///
    /// Flipped coords (origin top-left, Y down). With clockwise: false,
    /// arc from 180° to 360° (0°) goes through 270° (up on screen).
    private static func drawTrackArc(cx: CGFloat, cy: CGFloat, radius: CGFloat, color: NSColor) {
        let trackPath = NSBezierPath()
        trackPath.appendArc(
            withCenter: NSPoint(x: cx, y: cy),
            radius: radius,
            startAngle: 180,
            endAngle: 360,
            clockwise: false
        )
        trackPath.lineWidth = Geometry.arcStrokeWidth
        trackPath.lineCapStyle = .round

        color.withAlphaComponent(0.25).setStroke()
        trackPath.stroke()
    }

    /// Draws the fill arc from left (180°) to the angle corresponding to headroom.
    /// Fill sweeps counterclockwise from 180° through 270° (up) toward needle.
    private static func drawFillArc(cx: CGFloat, cy: CGFloat, radius: CGFloat, theta: CGFloat, color: NSColor) {
        let fillPath = NSBezierPath()
        // Convert theta to flipped coordinate angle: 360° - theta_degrees
        let thetaDegrees = theta * 180.0 / CGFloat.pi
        let endAngleDegrees = 360.0 - thetaDegrees
        fillPath.appendArc(
            withCenter: NSPoint(x: cx, y: cy),
            radius: radius,
            startAngle: 180,
            endAngle: endAngleDegrees,
            clockwise: false
        )
        fillPath.lineWidth = Geometry.arcStrokeWidth
        fillPath.lineCapStyle = .round

        color.setStroke()
        fillPath.stroke()
    }

    /// Draws the needle line from center to the angle position.
    /// Flipped coords: convert theta to flipped angle (360° - theta).
    private static func drawNeedle(cx: CGFloat, cy: CGFloat, length: CGFloat, theta: CGFloat, color: NSColor) {
        // Convert to flipped coordinate angle
        let flippedAngle = 2 * CGFloat.pi - theta
        let needleEndX = cx + length * cos(flippedAngle)
        let needleEndY = cy + length * sin(flippedAngle)

        let needlePath = NSBezierPath()
        needlePath.move(to: NSPoint(x: cx, y: cy))
        needlePath.line(to: NSPoint(x: needleEndX, y: needleEndY))
        needlePath.lineWidth = Geometry.needleStrokeWidth
        needlePath.lineCapStyle = .round

        color.setStroke()
        needlePath.stroke()
    }

    /// Draws the center pivot dot.
    private static func drawCenterDot(cx: CGFloat, cy: CGFloat, color: NSColor) {
        let r = Geometry.centerDotRadius
        let dotRect = NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        let dotPath = NSBezierPath(ovalIn: dotRect)

        color.setFill()
        dotPath.fill()
    }

    /// Draws the disconnected X icon.
    private static func drawDisconnectedX(in rect: NSRect) {
        let color = NSColor.headroomColor(for: .disconnected)
        let padding = Geometry.disconnectedPadding

        let xPath = NSBezierPath()

        // Top-left to bottom-right
        xPath.move(to: NSPoint(x: padding, y: rect.height - padding))
        xPath.line(to: NSPoint(x: rect.width - padding, y: padding))

        // Top-right to bottom-left
        xPath.move(to: NSPoint(x: rect.width - padding, y: rect.height - padding))
        xPath.line(to: NSPoint(x: padding, y: padding))

        xPath.lineWidth = Geometry.arcStrokeWidth
        xPath.lineCapStyle = .round

        color.setStroke()
        xPath.stroke()
    }
}

// MARK: - Legacy Function Wrappers (for backward compatibility)

/// Creates a semicircular gauge icon for the menu bar.
/// - Note: Prefer `GaugeIcon.make(headroomPercentage:state:)` for new code.
func makeGaugeIcon(headroomPercentage: Double, state: HeadroomState) -> NSImage {
    GaugeIcon.make(headroomPercentage: headroomPercentage, state: state)
}

/// Creates a distinct "X" icon for the disconnected state.
/// - Note: Prefer `GaugeIcon.makeDisconnected()` for new code.
func makeDisconnectedIcon() -> NSImage {
    GaugeIcon.makeDisconnected()
}

/// Calculates the needle angle for a given headroom percentage.
/// - Note: Prefer `GaugeIcon.angle(for:)` for new code.
func gaugeAngle(for headroomPercentage: Double) -> Double {
    GaugeIcon.angle(for: headroomPercentage)
}
