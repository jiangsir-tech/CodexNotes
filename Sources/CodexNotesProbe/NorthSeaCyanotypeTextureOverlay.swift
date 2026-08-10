import SwiftUI

/// A deterministic, low-contrast cold-pressed paper layer for the North Sea theme.
/// Tiny paper dimples and pigment edges add depth without resembling tracing fibers.
struct NorthSeaCyanotypeTextureOverlay: View {
    private let cellSize: CGFloat = 160
    private let seed: UInt64 = 0x4E4F525448534541

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

        for index in 0..<2 {
            let value = mix(cellHash, UInt64(index + 1))
            let center = CGPoint(
                x: origin.x + unit(value) * cellSize,
                y: origin.y + unit(value >> 16) * cellSize
            )
            let width = interpolate(7...18, unit(value >> 32))
            let height = interpolate(3...8, unit(value >> 48))
            let inset = interpolate(0.4...1.3, unit(mix(value, 5)))

            var dimple = Path(
                ellipseIn: CGRect(
                    x: center.x - width / 2,
                    y: center.y - height / 2,
                    width: width,
                    height: height
                )
            )
            dimple.addEllipse(
                in: CGRect(
                    x: center.x - width / 2 + inset,
                    y: center.y - height / 2 + inset / 2,
                    width: max(0.5, width - inset * 2),
                    height: max(0.5, height - inset)
                )
            )
            context.fill(
                dimple,
                with: .color(
                    Color(red: 0.310, green: 0.431, blue: 0.537)
                        .opacity(Double(interpolate(0.004...0.008, unit(mix(value, 7)))))
                ),
                style: FillStyle(eoFill: true)
            )
        }

        let edgeValue = mix(cellHash, 101)
        let start = CGPoint(
            x: origin.x + unit(edgeValue) * cellSize,
            y: origin.y + unit(edgeValue >> 16) * cellSize
        )
        let length = interpolate(32...72, unit(edgeValue >> 32))
        let end = CGPoint(
            x: start.x + length,
            y: start.y + interpolate(-4...4, unit(edgeValue >> 48))
        )
        let control = CGPoint(
            x: (start.x + end.x) / 2,
            y: (start.y + end.y) / 2 + interpolate(-7...7, unit(mix(edgeValue, 11)))
        )

        var pigmentEdge = Path()
        pigmentEdge.move(to: start)
        pigmentEdge.addQuadCurve(to: end, control: control)
        context.stroke(
            pigmentEdge,
            with: .color(
                Color(red: 0.275, green: 0.408, blue: 0.522)
                    .opacity(Double(interpolate(0.006...0.011, unit(mix(edgeValue, 13)))))
            ),
            lineWidth: interpolate(0.24...0.42, unit(mix(edgeValue, 17)))
        )
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
