import SwiftUI

/// A deterministic, near-invisible fiber layer for the cool silver tracing-paper theme.
/// Sparse vector strokes suggest paper grain without adding noise around text.
struct SilverTracingPaperTextureOverlay: View {
    private let cellSize: CGFloat = 144
    private let seed: UInt64 = 0x53494C5645525452

    var body: some View {
        Canvas(
            opaque: false,
            colorMode: .nonLinear,
            rendersAsynchronously: false
        ) { context, size in
            let columnCount = max(1, Int(ceil(size.width / cellSize)))
            let rowCount = max(1, Int(ceil(size.height / cellSize)))

            for row in 0..<rowCount {
                for column in 0..<columnCount {
                    drawCell(row: row, column: column, in: &context)
                }
            }
        }
        .blendMode(.multiply)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawCell(
        row: Int,
        column: Int,
        in context: inout GraphicsContext
    ) {
        let origin = CGPoint(
            x: CGFloat(column) * cellSize,
            y: CGFloat(row) * cellSize
        )
        let cellHash = hash(row: row, column: column, element: 0)

        for index in 0..<3 {
            let value = mix(cellHash, UInt64(index + 1))
            let start = CGPoint(
                x: origin.x + unit(value) * cellSize,
                y: origin.y + unit(value >> 16) * cellSize
            )
            let longFiber = index < 2
            let lengthRange: ClosedRange<CGFloat> = longFiber ? 28...62 : 9...20
            let length = interpolate(lengthRange, unit(value >> 32))
            let nearHorizontal = unit(value >> 48) < 0.70
            let angleDegrees = nearHorizontal
                ? interpolate(-10...10, unit(mix(value, 5)))
                : interpolate(25...155, unit(mix(value, 7)))
            let angle = angleDegrees * .pi / 180
            let end = CGPoint(
                x: start.x + cos(angle) * length,
                y: start.y + sin(angle) * length
            )
            let bend = interpolate(-1.4...1.4, unit(mix(value, 11)))
            let control = CGPoint(
                x: (start.x + end.x) / 2,
                y: (start.y + end.y) / 2 + bend
            )

            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
            context.stroke(
                path,
                with: .color(
                    Color(red: 0.400, green: 0.467, blue: 0.518)
                        .opacity(Double(interpolate(0.008...0.014, unit(mix(value, 13)))))
                ),
                lineWidth: interpolate(0.22...0.36, unit(mix(value, 17)))
            )
        }
    }

    private func hash(row: Int, column: Int, element: Int) -> UInt64 {
        var value = seed
        value ^= UInt64(row) &* 0x9E3779B185EBCA87
        value ^= UInt64(column) &* 0xC2B2AE3D27D4EB4F
        value ^= UInt64(element) &* 0x165667B19E3779F9
        return avalanche(value)
    }

    private func mix(_ value: UInt64, _ salt: UInt64) -> UInt64 {
        avalanche(value ^ (salt &* 0x9E3779B185EBCA87))
    }

    private func avalanche(_ input: UInt64) -> UInt64 {
        var value = input
        value ^= value >> 30
        value = value &* 0xBF58476D1CE4E5B9
        value ^= value >> 27
        value = value &* 0x94D049BB133111EB
        value ^= value >> 31
        return value
    }

    private func unit(_ value: UInt64) -> CGFloat {
        CGFloat(value & 0xFFFF) / CGFloat(UInt16.max)
    }

    private func interpolate(
        _ range: ClosedRange<CGFloat>,
        _ amount: CGFloat
    ) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * amount
    }
}
