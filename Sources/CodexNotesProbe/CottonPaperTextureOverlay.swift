import SwiftUI

/// A deterministic, low-contrast fiber layer for the ivory cotton-paper theme.
/// The pattern is vector-drawn so it stays crisp without adding a bitmap asset.
struct CottonPaperTextureOverlay: View {
    private let cellSize: CGFloat = 128
    private let seed: UInt64 = 0x49564F5259434F54

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
                    drawCell(
                        row: row,
                        column: column,
                        in: &context
                    )
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

        for index in 0..<4 {
            let value = mix(cellHash, UInt64(index + 1))
            let start = CGPoint(
                x: origin.x + unit(value) * cellSize,
                y: origin.y + unit(value >> 16) * cellSize
            )
            let longFiber = index < 2
            let lengthRange: ClosedRange<CGFloat> = longFiber ? 26...54 : 8...18
            let length = interpolate(lengthRange, unit(value >> 32))
            let nearHorizontal = unit(value >> 48) < 0.60
            let angleDegrees = nearHorizontal
                ? interpolate(-15...15, unit(mix(value, 5)))
                : interpolate(20...160, unit(mix(value, 7)))
            let angle = angleDegrees * .pi / 180
            let end = CGPoint(
                x: start.x + cos(angle) * length,
                y: start.y + sin(angle) * length
            )
            let bend = interpolate(-2.2...2.2, unit(mix(value, 11)))
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
                    Color(red: 0.435, green: 0.357, blue: 0.263)
                        .opacity(Double(interpolate(0.014...0.022, unit(mix(value, 13)))))
                ),
                lineWidth: interpolate(
                    longFiber ? 0.28...0.42 : 0.25...0.35,
                    unit(mix(value, 17))
                )
            )
        }

        for index in 0..<3 {
            let value = mix(cellHash, UInt64(index + 101))
            let center = CGPoint(
                x: origin.x + unit(value) * cellSize,
                y: origin.y + unit(value >> 16) * cellSize
            )
            let diameter = interpolate(0.5...1.1, unit(value >> 32))
            let rect = CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(
                    Color(red: 0.502, green: 0.420, blue: 0.322)
                        .opacity(Double(interpolate(0.010...0.016, unit(value >> 48))))
                )
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
