import SwiftUI

/// A deterministic, near-invisible pressed-cotton layer for the Bordeaux theme.
/// Short rose fibers and sparse dark pulp pores keep the deep surface tactile
/// without turning it into leather, velvet, a wine stain, or a noise filter.
struct BordeauxCottonPaperTextureOverlay: View {
    private let cellSize: CGFloat = 160
    private let seed: UInt64 = 0x424F524445415558

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

        for index in 0..<2 {
            let value = mix(cellHash, UInt64(index + 1))
            let start = CGPoint(
                x: origin.x + unit(value) * cellSize,
                y: origin.y + unit(value >> 16) * cellSize
            )
            let length = interpolate(7...18, unit(value >> 32))
            let angle = interpolate(0...(2 * CGFloat.pi), unit(value >> 48))
            let end = CGPoint(
                x: start.x + cos(angle) * length,
                y: start.y + sin(angle) * length
            )
            let control = CGPoint(
                x: (start.x + end.x) / 2
                    + interpolate(-1.8...1.8, unit(mix(value, 5))),
                y: (start.y + end.y) / 2
                    + interpolate(-1.8...1.8, unit(mix(value, 7)))
            )

            var fiber = Path()
            fiber.move(to: start)
            fiber.addQuadCurve(to: end, control: control)
            context.stroke(
                fiber,
                with: .color(
                    Color(red: 0.760, green: 0.560, blue: 0.610)
                        .opacity(Double(interpolate(0.006...0.014, unit(mix(value, 11)))))
                ),
                lineWidth: interpolate(0.20...0.34, unit(mix(value, 13)))
            )
        }

        if cellHash & 1 == 0 {
            let value = mix(cellHash, 101)
            let center = CGPoint(
                x: origin.x + unit(value) * cellSize,
                y: origin.y + unit(value >> 16) * cellSize
            )
            let diameter = interpolate(0.5...1.0, unit(value >> 32))
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: center.x - diameter / 2,
                        y: center.y - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                ),
                with: .color(
                    Color(red: 0.090, green: 0.040, blue: 0.055)
                        .opacity(Double(interpolate(0.004...0.009, unit(value >> 48))))
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
