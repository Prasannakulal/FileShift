import SwiftUI

// MARK: - State

/// Observable state for the radial menu, supporting continuous hover and drag hit-testing.
class RadialMenuState: ObservableObject {
    @Published var hoveredIndex: Int? = nil

    let totalSegments: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    init(totalSegments: Int, innerRadius: CGFloat = 46, outerRadius: CGFloat = 110) {
        self.totalSegments = totalSegments
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
    }

    /// Update hover using a vector (dx, dy) in standard cartesian coordinates (dy > 0 is UP, dx > 0 is RIGHT)
    func updateWithDelta(dx: CGFloat, dy: CGFloat) {
        let distance = sqrt(dx * dx + dy * dy)

        // Highlight if inside the donut ring (with comfortable tolerance)
        guard distance >= (innerRadius - 6) && distance <= (outerRadius + 22) else {
            clearHover()
            return
        }

        // Standard screen cartesian: dy > 0 is UP, dx > 0 is RIGHT
        // Clockwise angle from 12 o'clock:
        // 12 o'clock = 0°, 3 o'clock = 90°, 6 o'clock = 180°, 9 o'clock = 270°
        var clockwiseAngle = 90.0 - (atan2(dy, dx) * 180.0 / .pi)
        if clockwiseAngle < 0 {
            clockwiseAngle += 360.0
        }

        let segmentAngle = 360.0 / Double(totalSegments)
        // Shift by half segmentAngle so segment 0 is centered directly at 12 o'clock (top)
        var shiftedAngle = clockwiseAngle + (segmentAngle / 2.0)
        if shiftedAngle >= 360.0 {
            shiftedAngle -= 360.0
        }

        let idx = Int(shiftedAngle / segmentAngle)
        if idx >= 0 && idx < totalSegments {
            if hoveredIndex != idx {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                    hoveredIndex = idx
                }
            }
        } else {
            clearHover()
        }
    }

    /// Update hover from SwiftUI local view coordinates (where localDy > 0 is DOWN)
    func updateHoverLocal(at point: CGPoint, in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let localDx = point.x - center.x
        let localDy = point.y - center.y
        // Invert Y because in SwiftUI Y increases downwards, but standard cartesian Y increases upwards
        updateWithDelta(dx: localDx, dy: -localDy)
    }

    /// Update hover from macOS screen coordinates (where Y increases UPWARDS)
    func updateHoverScreen(mouseScreenPoint: NSPoint, screenCenter: NSPoint) {
        let dx = mouseScreenPoint.x - screenCenter.x
        let dy = mouseScreenPoint.y - screenCenter.y
        updateWithDelta(dx: dx, dy: dy)
    }

    func clearHover() {
        if hoveredIndex != nil {
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredIndex = nil
            }
        }
    }
}

// MARK: - Radial Menu View

/// The radial pie menu view — compact, elegant transparent HUD matching the reference dial.
struct RadialMenuView: View {

    let config: RadialMenuConfig
    @ObservedObject var state: RadialMenuState
    var fileSizeString: String = "1.1 MB"
    let onSegmentSelected: (MenuSegment) -> Void
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0.0

    // Compact geometry constants matching the reference dial
    private let outerRadius: CGFloat = 110
    private let innerRadius: CGFloat = 46
    private let cornerRadius: CGFloat = 11

    private var gapAngle: Double {
        18.0 / Double(max(1, config.segmentCount))
    }

    private var haloRadius: CGFloat {
        outerRadius + 14
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1. Outer Translucent Frosted Glass Halo (transparent theme matching reference)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "F59543").opacity(0.55),
                                Color(hex: "E67425").opacity(0.35),
                                Color(white: 1.0, opacity: 0.28)
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: haloRadius
                        )
                    )
                    .frame(width: haloRadius * 2, height: haloRadius * 2)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.65),
                                        Color.white.opacity(0.30)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 5)

                // 2. Petal Segments
                ForEach(Array(config.segments.enumerated()), id: \.element.id) { index, segment in
                    SegmentView(
                        segment: segment,
                        index: index,
                        totalSegments: config.segmentCount,
                        outerRadius: outerRadius,
                        innerRadius: innerRadius,
                        cornerRadius: cornerRadius,
                        gapAngle: gapAngle,
                        isHovered: state.hoveredIndex == index
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            onSegmentSelected(segment)
                        }
                    }
                }

                // 3. Center Hub with File Size / Hovered Format Capsule
                CenterCircleView(
                    hoveredLabel: state.hoveredIndex != nil && state.hoveredIndex! < config.segments.count ? config.segments[state.hoveredIndex!].label : nil,
                    fileSizeLabel: fileSizeString,
                    radius: innerRadius - 3
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Circle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    state.updateHoverLocal(at: location, in: geo.size)
                case .ended:
                    state.clearHover()
                }
            }
        }
        .frame(width: haloRadius * 2 + 40, height: haloRadius * 2 + 40)
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.74, blendDuration: 0)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }

    /// Dismiss with animation
    func dismissAnimated(completion: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.16)) {
            scale = 0.6
            opacity = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            completion()
        }
    }
}

// MARK: - Segment View

/// A single rounded quadrant petal in the radial dial
struct SegmentView: View {

    let segment: MenuSegment
    let index: Int
    let totalSegments: Int
    let outerRadius: CGFloat
    let innerRadius: CGFloat
    let cornerRadius: CGFloat
    let gapAngle: Double
    let isHovered: Bool

    private var segmentAngle: Double {
        360.0 / Double(totalSegments)
    }

    // Segment 0 is centered directly at 12 o'clock (-90° in standard SwiftUI)
    private var centerAngle: Double {
        -90.0 + Double(index) * segmentAngle
    }

    private var startAngle: Double {
        centerAngle - (segmentAngle / 2.0) + (gapAngle / 2.0)
    }

    private var endAngle: Double {
        centerAngle + (segmentAngle / 2.0) - (gapAngle / 2.0)
    }

    // Position for the label text in the middle of the petal
    private var labelPosition: CGPoint {
        let labelRadius = (outerRadius + innerRadius) / 2.0
        let angleRad = centerAngle * .pi / 180.0
        return CGPoint(
            x: cos(angleRad) * labelRadius,
            y: sin(angleRad) * labelRadius
        )
    }

    var body: some View {
        ZStack {
            // Petal Shape
            RoundedAnnularWedge(
                startAngle: .degrees(startAngle),
                endAngle: .degrees(endAngle),
                innerRadius: innerRadius,
                outerRadius: outerRadius,
                cornerRadius: cornerRadius
            )
            .fill(segmentFill)
            .overlay(
                RoundedAnnularWedge(
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(endAngle),
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    cornerRadius: cornerRadius
                )
                .strokeBorder(
                    segmentStroke,
                    lineWidth: isHovered ? 1.2 : 0.8
                )
            )
            .shadow(
                color: isHovered ? Color(hex: "E64A19").opacity(0.65) : Color.black.opacity(0.06),
                radius: isHovered ? 9 : 3,
                x: 0,
                y: isHovered ? 0 : 1.5
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)

            // Centered format label (11pt bold)
            Text(segment.label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isHovered ? Color.white : Color(hex: "2E1D13"))
                .offset(x: labelPosition.x, y: labelPosition.y)
                .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .contentShape(
            RoundedAnnularWedge(
                startAngle: .degrees(startAngle),
                endAngle: .degrees(endAngle),
                innerRadius: innerRadius,
                outerRadius: outerRadius + 5,
                cornerRadius: cornerRadius
            )
        )
        .animation(.spring(response: 0.20, dampingFraction: 0.80), value: isHovered)
    }

    private var segmentFill: some ShapeStyle {
        if isHovered {
            // Vibrant glowing fiery orange matching the reference hover state
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "F55F20"),
                        Color(hex: "E84B12")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else {
            // Soft warm cream/ivory translucent fill
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "FFF8EF").opacity(0.92),
                        Color(hex: "FDE8D4").opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var segmentStroke: some ShapeStyle {
        if isHovered {
            return AnyShapeStyle(Color.white.opacity(0.95))
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.80),
                        Color(hex: "EBD6C1").opacity(0.50)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - Center Hub

/// The center hub of the radial dial, featuring a warm glowing amber well
/// with a centered capsule displaying file size or the hovered target format.
struct CenterCircleView: View {
    let hoveredLabel: String?
    let fileSizeLabel: String
    let radius: CGFloat

    private var displayText: String {
        if let hovered = hoveredLabel, !hovered.isEmpty {
            return hovered
        }
        return fileSizeLabel
    }

    var body: some View {
        ZStack {
            // Amber well circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "F28935").opacity(0.90),
                            Color(hex: "D9641A").opacity(0.90)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: radius
                    )
                )
                .frame(width: radius * 2, height: radius * 2)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                )
                .shadow(color: Color(hex: "6A2500").opacity(0.25), radius: 4, x: 0, y: 1.5)

            // Centered peach/apricot capsule pill (smaller, borderless/soft matching Image 2)
            ZStack {
                Capsule()
                    .fill(Color(hex: "FDB974").opacity(0.88))

                Text(displayText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "341E0F"))
                    .id(displayText)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            .frame(width: 58, height: 24)
        }
        .animation(.easeInOut(duration: 0.15), value: displayText)
    }
}

// MARK: - Rounded Annular Wedge Shape

/// Mathematically exact annular sector shape with smoothly rounded corners.
struct RoundedAnnularWedge: InsettableShape {

    var startAngle: Angle
    var endAngle: Angle
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> RoundedAnnularWedge {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    private func normArc(from: Double, to: Double, clockwise: Bool) -> (Angle, Angle) {
        let a = from
        var b = to
        if !clockwise {
            while b < a { b += 2 * .pi }
            while b - a > 2 * .pi { b -= 2 * .pi }
        } else {
            while b > a { b -= 2 * .pi }
            while a - b > 2 * .pi { b += 2 * .pi }
        }
        return (Angle(radians: a), Angle(radians: b))
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rIn = innerRadius + insetAmount
        let rOut = outerRadius - insetAmount

        guard rOut > rIn else { return Path() }

        let a1 = startAngle.radians
        var a2 = endAngle.radians
        if a2 <= a1 {
            a2 += 2 * .pi
        }

        let span = a2 - a1
        guard span > 0.05 else { return Path() }

        // Limit corner radius to avoid geometric inversion
        var r = cornerRadius
        r = min(r, (rOut - rIn) / 2.0 - 0.5)
        r = min(r, (rIn * span) / 4.0)
        r = max(r, 0)

        if r < 1.0 {
            var path = Path()
            path.addArc(
                center: center,
                radius: rOut,
                startAngle: Angle(radians: a1),
                endAngle: Angle(radians: a2),
                clockwise: false
            )
            path.addArc(
                center: center,
                radius: rIn,
                startAngle: Angle(radians: a2),
                endAngle: Angle(radians: a1),
                clockwise: true
            )
            path.closeSubpath()
            return path
        }

        let dout = sqrt(max(0, pow(rOut - r, 2) - pow(r, 2)))
        let din = sqrt(max(0, pow(rIn + r, 2) - pow(r, 2)))

        let u1 = CGPoint(x: cos(a1), y: sin(a1))
        let n1 = CGPoint(x: -sin(a1), y: cos(a1))

        let u2 = CGPoint(x: cos(a2), y: sin(a2))
        let n2 = CGPoint(x: -sin(a2), y: cos(a2))

        let cout1 = CGPoint(
            x: center.x + dout * u1.x + r * n1.x,
            y: center.y + dout * u1.y + r * n1.y
        )
        let cin1 = CGPoint(
            x: center.x + din * u1.x + r * n1.x,
            y: center.y + din * u1.y + r * n1.y
        )

        let cout2 = CGPoint(
            x: center.x + dout * u2.x - r * n2.x,
            y: center.y + dout * u2.y - r * n2.y
        )
        let cin2 = CGPoint(
            x: center.x + din * u2.x - r * n2.x,
            y: center.y + din * u2.y - r * n2.y
        )

        let gammaOut1 = atan2(cout1.y - center.y, cout1.x - center.x)
        let gammaOut2 = atan2(cout2.y - center.y, cout2.x - center.x)
        let gammaIn1 = atan2(cin1.y - center.y, cin1.x - center.x)
        let gammaIn2 = atan2(cin2.y - center.y, cin2.x - center.x)

        var path = Path()

        // Start at tangent on ray 1 (inner corner)
        path.move(to: CGPoint(x: center.x + din * u1.x, y: center.y + din * u1.y))

        // 1. Ray 1 straight line to outer corner tangent
        path.addLine(to: CGPoint(x: center.x + dout * u1.x, y: center.y + dout * u1.y))

        // 2. Corner 1 arc at (outer, a1)
        let (c1Start, c1End) = normArc(from: a1 - .pi / 2, to: gammaOut1, clockwise: false)
        path.addArc(
            center: cout1,
            radius: r,
            startAngle: c1Start,
            endAngle: c1End,
            clockwise: false
        )

        // 3. Outer circular arc
        let (outArcStart, outArcEnd) = normArc(from: gammaOut1, to: gammaOut2, clockwise: false)
        path.addArc(
            center: center,
            radius: rOut,
            startAngle: outArcStart,
            endAngle: outArcEnd,
            clockwise: false
        )

        // 4. Corner 2 arc at (outer, a2)
        let (c2Start, c2End) = normArc(from: gammaOut2, to: a2 + .pi / 2, clockwise: false)
        path.addArc(
            center: cout2,
            radius: r,
            startAngle: c2Start,
            endAngle: c2End,
            clockwise: false
        )

        // 5. Ray 2 straight line to inner corner tangent
        path.addLine(to: CGPoint(x: center.x + din * u2.x, y: center.y + din * u2.y))

        // 6. Corner 3 arc at (inner, a2)
        let (c3Start, c3End) = normArc(from: a2 + .pi / 2, to: gammaIn2 + .pi, clockwise: false)
        path.addArc(
            center: cin2,
            radius: r,
            startAngle: c3Start,
            endAngle: c3End,
            clockwise: false
        )

        // 7. Inner circular arc (in reverse)
        let (inArcStart, inArcEnd) = normArc(from: gammaIn2, to: gammaIn1, clockwise: true)
        path.addArc(
            center: center,
            radius: rIn,
            startAngle: inArcStart,
            endAngle: inArcEnd,
            clockwise: true
        )

        // 8. Corner 4 arc at (inner, a1)
        let (c4Start, c4End) = normArc(from: gammaIn1 + .pi, to: a1 - .pi / 2, clockwise: false)
        path.addArc(
            center: cin1,
            radius: r,
            startAngle: c4Start,
            endAngle: c4End,
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
