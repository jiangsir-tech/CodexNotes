import AppKit
import CoreGraphics

struct MainWindowDisplayGeometry: Equatable {
    let appKitFrame: NSRect
    let visibleFrame: NSRect
    let quartzFrame: CGRect
}

enum MainWindowInitialPlacementPolicy {
    // Keep the scene's pre-configuration size stable so existing users do not
    // briefly see a different frame before their saved window is restored.
    static let swiftUIBootstrapSize = NSSize(width: 440, height: 680)

    // The compact first-run frame leaves more room for Codex while remaining
    // comfortably above ContentView's 340 x 520 resizing floor.
    static let fallbackSize = NSSize(width: 420, height: 640)
    static let widthRatio: CGFloat = 0.27
    static let heightRatio: CGFloat = 0.66
    static let minimumWidth: CGFloat = 400
    static let maximumWidth: CGFloat = 480
    static let minimumHeight: CGFloat = 600
    static let maximumHeight: CGFloat = 680
    static let companionGap: CGFloat = 8

    static func preferredSize(forVisibleFrameSize visibleSize: CGSize?) -> NSSize {
        guard let visibleSize,
              visibleSize.width.isFinite,
              visibleSize.height.isFinite,
              visibleSize.width > 0,
              visibleSize.height > 0 else {
            return fallbackSize
        }

        let proportionalWidth = (visibleSize.width * widthRatio).rounded()
        let proportionalHeight = (visibleSize.height * heightRatio).rounded()
        let preferredWidth = min(
            max(proportionalWidth, minimumWidth),
            maximumWidth
        )
        let preferredHeight = min(
            max(proportionalHeight, minimumHeight),
            maximumHeight
        )

        // Real macOS displays are larger than the preferred minima, but cap to
        // the available area so unusual scaled or virtual displays never place
        // the first window partly off screen.
        return NSSize(
            width: min(preferredWidth, visibleSize.width),
            height: min(preferredHeight, visibleSize.height)
        )
    }

    static func initialFrame(
        in visibleFrame: NSRect,
        codexFrame: NSRect?
    ) -> NSRect {
        let size = preferredSize(forVisibleFrameSize: visibleFrame.size)
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)

        guard let codexFrame else {
            return NSRect(
                x: ((visibleFrame.midX - size.width / 2).rounded())
                    .clamped(to: visibleFrame.minX...maximumX),
                y: ((visibleFrame.midY - size.height / 2).rounded())
                    .clamped(to: visibleFrame.minY...maximumY),
                width: size.width,
                height: size.height
            )
        }

        let rightX = codexFrame.maxX + companionGap
        let leftX = codexFrame.minX - size.width - companionGap
        let x: CGFloat
        if rightX >= visibleFrame.minX,
           rightX + size.width <= visibleFrame.maxX {
            x = rightX
        } else if leftX >= visibleFrame.minX,
                  leftX + size.width <= visibleFrame.maxX {
            x = leftX
        } else {
            x = (codexFrame.maxX - size.width - companionGap)
                .clamped(to: visibleFrame.minX...maximumX)
        }
        let y = (codexFrame.maxY - size.height)
            .clamped(to: visibleFrame.minY...maximumY)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    static func frameByRestoringDefaultSize(
        from currentFrame: NSRect,
        in visibleFrame: NSRect
    ) -> NSRect {
        let size = preferredSize(forVisibleFrameSize: visibleFrame.size)
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        let x = currentFrame.minX.clamped(
            to: visibleFrame.minX...maximumX
        )
        let y = (currentFrame.maxY - size.height).clamped(
            to: visibleFrame.minY...maximumY
        )
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    static func visibleFrame(
        containingMostOf frame: NSRect,
        among visibleFrames: [NSRect]
    ) -> NSRect? {
        visibleFrames
            .compactMap { visibleFrame -> (frame: NSRect, area: CGFloat)? in
                let intersection = visibleFrame.intersection(frame)
                guard !intersection.isNull, !intersection.isEmpty else {
                    return nil
                }
                return (
                    visibleFrame,
                    intersection.width * intersection.height
                )
            }
            .max { lhs, rhs in lhs.area < rhs.area }?
            .frame
    }

    static func display(
        containingQuartzBounds bounds: CGRect,
        among displays: [MainWindowDisplayGeometry]
    ) -> MainWindowDisplayGeometry? {
        displays
            .compactMap { display -> (MainWindowDisplayGeometry, CGFloat)? in
                let intersection = display.quartzFrame.intersection(bounds)
                guard !intersection.isNull, !intersection.isEmpty else {
                    return nil
                }
                return (display, intersection.width * intersection.height)
            }
            .max { lhs, rhs in lhs.1 < rhs.1 }?
            .0
    }

    static func appKitFrame(
        forQuartzBounds bounds: CGRect,
        on display: MainWindowDisplayGeometry
    ) -> NSRect {
        let localX = bounds.minX - display.quartzFrame.minX
        let localTop = bounds.minY - display.quartzFrame.minY
        return NSRect(
            x: display.appKitFrame.minX + localX,
            y: display.appKitFrame.maxY - localTop - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
