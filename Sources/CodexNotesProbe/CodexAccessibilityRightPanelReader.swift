import AppKit
import ApplicationServices
import CodexNotesCore
import CoreFoundation
import Foundation

enum CodexAccessibilityPermissionState: Equatable, Sendable {
    case authorized
    case denied
}

struct CodexAccessibilityRightPanelSample: Equatable, Sendable {
    let state: CodexRightPanelState
    let permission: CodexAccessibilityPermissionState
}

struct CodexAccessibilityElementSnapshot: Equatable, Sendable {
    let role: String
    let subrole: String?
    let frame: CGRect?
    let classTokens: Set<String>
    let children: [CodexAccessibilityElementSnapshot]

    init(
        role: String,
        subrole: String? = nil,
        frame: CGRect? = nil,
        classTokens: Set<String> = [],
        children: [CodexAccessibilityElementSnapshot] = []
    ) {
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.classTokens = classTokens
        self.children = children
    }
}

enum CodexAccessibilityRightPanelClassifier {
    static let shellRowClassTokens: Set<String> = [
        "relative", "isolate", "flex", "min-h-0", "flex-1",
        "overflow-hidden",
    ]
    static let asideClassTokens: Set<String> = [
        "relative", "z-[41]", "h-full", "min-h-0", "min-w-0",
        "shrink-0", "overflow-visible",
    ]
    private static let mainSubrole = "AXLandmarkMain"
    private static let asideSubrole = "AXLandmarkComplementary"
    private static let minimumMainWidth: CGFloat = 600
    private static let minimumMainHeight: CGFloat = 400
    private static let minimumAsideWidth: CGFloat = 240
    private static let maximumAsideWidth: CGFloat = 1_200
    private static let frameTolerance: CGFloat = 3

    static func state(
        in roots: [CodexAccessibilityElementSnapshot]
    ) -> CodexRightPanelState {
        let mains = descendants(in: roots).filter { element in
            element.subrole == mainSubrole
                && element.frame.map {
                    $0.width >= minimumMainWidth
                        && $0.height >= minimumMainHeight
                } == true
        }
        guard let main = mains.max(by: {
            frameArea($0.frame) < frameArea($1.frame)
        }), let mainFrame = main.frame else {
            return .unknown
        }

        let shellRows = shellRows(in: main)
        guard shellRows.count == 1, let shellRow = shellRows.first else {
            return .unknown
        }

        let viewports = shellRow.children.filter {
            $0.classTokens.contains(where: {
                $0.hasPrefix("_MainContentViewport_")
            })
        }
        guard viewports.count == 1,
              let viewport = viewports.first,
              let viewportFrame = viewport.frame,
              isVerticallyAligned(viewportFrame, with: mainFrame)
        else {
            return .unknown
        }

        let asideCandidates = shellRow.children.filter {
            $0.subrole == asideSubrole
                || asideClassTokens.isSubset(of: $0.classTokens)
        }
        if asideCandidates.isEmpty {
            return framesApproximatelyEqual(viewportFrame, mainFrame)
                ? .closed
                : .unknown
        }

        guard asideCandidates.count == 1,
              let aside = asideCandidates.first,
              aside.subrole == asideSubrole,
              asideClassTokens.isSubset(of: aside.classTokens),
              let asideFrame = aside.frame,
              validOpenGeometry(
                  main: mainFrame,
                  viewport: viewportFrame,
                  aside: asideFrame
              ) else {
            return .unknown
        }
        return .open
    }

    static func shellRows(
        in main: CodexAccessibilityElementSnapshot
    ) -> [CodexAccessibilityElementSnapshot] {
        guard let mainFrame = main.frame else { return [] }
        return descendants(in: main.children).filter {
            shellRowClassTokens.isSubset(of: $0.classTokens)
                && framesApproximatelyEqual($0.frame, mainFrame)
        }
    }

    private static func descendants(
        in roots: [CodexAccessibilityElementSnapshot]
    ) -> [CodexAccessibilityElementSnapshot] {
        var result: [CodexAccessibilityElementSnapshot] = []
        var queue = roots
        while !queue.isEmpty {
            let element = queue.removeFirst()
            result.append(element)
            queue.append(contentsOf: element.children)
        }
        return result
    }

    private static func validOpenGeometry(
        main: CGRect,
        viewport: CGRect,
        aside: CGRect
    ) -> Bool {
        guard aside.width >= minimumAsideWidth,
              aside.width <= min(maximumAsideWidth, main.width * 0.75),
              viewport.width > 0,
              isVerticallyAligned(viewport, with: main),
              isVerticallyAligned(aside, with: main),
              approximatelyEqual(viewport.minX, main.minX),
              approximatelyEqual(viewport.maxX, aside.minX),
              approximatelyEqual(aside.maxX, main.maxX),
              approximatelyEqual(viewport.width + aside.width, main.width)
        else { return false }
        return true
    }

    private static func isVerticallyAligned(
        _ frame: CGRect,
        with container: CGRect
    ) -> Bool {
        approximatelyEqual(frame.minY, container.minY)
            && approximatelyEqual(frame.maxY, container.maxY)
    }

    private static func framesApproximatelyEqual(
        _ lhs: CGRect?,
        _ rhs: CGRect
    ) -> Bool {
        guard let lhs else { return false }
        return approximatelyEqual(lhs.minX, rhs.minX)
            && approximatelyEqual(lhs.minY, rhs.minY)
            && approximatelyEqual(lhs.maxX, rhs.maxX)
            && approximatelyEqual(lhs.maxY, rhs.maxY)
    }

    private static func approximatelyEqual(
        _ lhs: CGFloat,
        _ rhs: CGFloat
    ) -> Bool {
        abs(lhs - rhs) <= frameTolerance
    }

    private static func frameArea(_ frame: CGRect?) -> CGFloat {
        guard let frame else { return 0 }
        return frame.width * frame.height
    }
}

struct CodexRightPanelDebouncer: Equatable, Sendable {
    private let requiredConsecutive: Int
    private var candidate: CodexRightPanelState?
    private var consecutiveCount = 0
    private(set) var lastPublished: CodexRightPanelState?

    init(requiredConsecutive: Int = 2) {
        precondition(requiredConsecutive > 0)
        self.requiredConsecutive = requiredConsecutive
    }

    mutating func observe(
        _ state: CodexRightPanelState
    ) -> CodexRightPanelState? {
        guard state != .unknown else {
            candidate = nil
            consecutiveCount = 0
            return nil
        }
        guard state != lastPublished else {
            candidate = nil
            consecutiveCount = 0
            return nil
        }
        if candidate == state {
            consecutiveCount += 1
        } else {
            candidate = state
            consecutiveCount = 1
        }
        guard consecutiveCount >= requiredConsecutive else { return nil }
        lastPublished = state
        candidate = nil
        consecutiveCount = 0
        return state
    }

    mutating func reset() {
        candidate = nil
        consecutiveCount = 0
        lastPublished = nil
    }
}

protocol CodexAccessibilityReading: Sendable {
    func isTrusted() -> Bool
    func codexProcessIdentifier() -> pid_t?
    func rootSnapshots(
        for processIdentifier: pid_t,
        budget: CodexAccessibilityTraversalBudget
    ) -> [CodexAccessibilityElementSnapshot]?
}

struct CodexAccessibilityTraversalBudget: Sendable {
    let maximumNodes: Int
    let maximumDepth: Int
    let maximumDuration: Duration

    init(
        maximumNodes: Int = 80,
        maximumDepth: Int = 18,
        maximumDuration: Duration = .milliseconds(20)
    ) {
        precondition(maximumNodes > 0)
        precondition(maximumDepth >= 0)
        self.maximumNodes = maximumNodes
        self.maximumDepth = maximumDepth
        self.maximumDuration = maximumDuration
    }
}

enum CodexAccessibilityTargetedTraversal {
    static func uniqueMatch<Node>(
        among roots: [Node],
        startingDepth: Int,
        nodeCount: inout Int,
        budget: CodexAccessibilityTraversalBudget,
        isBeforeDeadline: () -> Bool,
        isMatch: (Node) -> Bool,
        children: (Node) -> [Node]?,
        shouldTraverse: (Node) -> Bool
    ) -> Node? {
        guard startingDepth <= budget.maximumDepth else { return nil }
        var queue = roots.map { (node: $0, depth: startingDepth) }
        var match: Node?

        while !queue.isEmpty {
            guard nodeCount < budget.maximumNodes,
                  isBeforeDeadline() else { return nil }
            let item = queue.removeFirst()
            nodeCount += 1

            if isMatch(item.node) {
                guard match == nil else { return nil }
                match = item.node
                continue
            }

            guard item.depth < budget.maximumDepth,
                  let descendants = children(item.node) else { continue }
            for descendant in descendants where shouldTraverse(descendant) {
                queue.append((descendant, item.depth + 1))
            }
        }

        guard isBeforeDeadline() else { return nil }
        return match
    }
}

actor CodexAccessibilityRightPanelReader {
    private let backend: any CodexAccessibilityReading
    private let budget: CodexAccessibilityTraversalBudget

    init() {
        backend = SystemCodexAccessibilityBackend()
        budget = CodexAccessibilityTraversalBudget()
    }

    init(
        backend: any CodexAccessibilityReading,
        budget: CodexAccessibilityTraversalBudget = .init()
    ) {
        self.backend = backend
        self.budget = budget
    }

    func sample() -> CodexAccessibilityRightPanelSample {
        guard backend.isTrusted() else {
            return CodexAccessibilityRightPanelSample(
                state: .unknown,
                permission: .denied
            )
        }
        guard let processIdentifier = backend.codexProcessIdentifier(),
              let roots = backend.rootSnapshots(
                  for: processIdentifier,
                  budget: budget
              ) else {
            return CodexAccessibilityRightPanelSample(
                state: .unknown,
                permission: .authorized
            )
        }
        return CodexAccessibilityRightPanelSample(
            state: CodexAccessibilityRightPanelClassifier.state(in: roots),
            permission: .authorized
        )
    }
}

private final class SystemCodexAccessibilityBackend:
    CodexAccessibilityReading,
    @unchecked Sendable
{
    private let clock = ContinuousClock()

    func isTrusted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false]
            as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func codexProcessIdentifier() -> pid_t? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.openai.codex"
        ).first(where: { !$0.isTerminated })?.processIdentifier
    }

    func rootSnapshots(
        for processIdentifier: pid_t,
        budget: CodexAccessibilityTraversalBudget
    ) -> [CodexAccessibilityElementSnapshot]? {
        let application = AXUIElementCreateApplication(processIdentifier)
        _ = AXUIElementSetMessagingTimeout(application, 0.05)
        guard let window = selectedStandardWindow(in: application),
              let windowFrame = frameValue(window) else {
            return nil
        }

        let deadline = clock.now.advanced(by: budget.maximumDuration)
        var nodeCount = 0
        guard let mainResult = findMainLandmark(
            from: window,
            inside: windowFrame,
            nodeCount: &nodeCount,
            deadline: deadline,
            budget: budget
        ), let mainFrame = frameValue(mainResult.element),
           let shellRow = findUniqueShellRow(
               below: mainResult.element,
               mainFrame: mainFrame,
               startingDepth: mainResult.depth,
               nodeCount: &nodeCount,
               deadline: deadline,
               budget: budget
           ),
           let shellChildren = elementArrayValue(
               shellRow,
               kAXChildrenAttribute
           )
        else { return nil }

        guard nodeCount + shellChildren.count <= budget.maximumNodes,
              clock.now < deadline else { return nil }
        nodeCount += shellChildren.count

        let childSnapshots = shellChildren.map { shallowSnapshot($0) }
        let shellSnapshot = shallowSnapshot(
            shellRow,
            children: childSnapshots
        )
        guard clock.now < deadline else { return nil }
        let mainSnapshot = shallowSnapshot(
            mainResult.element,
            children: [shellSnapshot]
        )
        return [mainSnapshot]
    }

    private func selectedStandardWindow(
        in application: AXUIElement
    ) -> AXUIElement? {
        let focused = elementValue(application, kAXFocusedWindowAttribute)
        if let focused, isStandardWindow(focused) {
            return focused
        }
        guard let windows = elementArrayValue(application, kAXWindowsAttribute)
        else { return nil }
        return windows.filter(isStandardWindow).max(by: {
            area(frameValue($0)) < area(frameValue($1))
        })
    }

    private func findMainLandmark(
        from root: AXUIElement,
        inside windowFrame: CGRect,
        nodeCount: inout Int,
        deadline: ContinuousClock.Instant,
        budget: CodexAccessibilityTraversalBudget
    ) -> (element: AXUIElement, depth: Int)? {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        while !queue.isEmpty {
            guard nodeCount < budget.maximumNodes,
                  clock.now < deadline else { return nil }
            let item = queue.removeFirst()
            nodeCount += 1

            let role = stringValue(item.element, kAXRoleAttribute)
            let subrole = stringValue(item.element, kAXSubroleAttribute)
            let frame = frameValue(item.element)
            if subrole == "AXLandmarkMain",
               let frame,
               frame.width >= windowFrame.width * 0.5,
               frame.height >= windowFrame.height * 0.5 {
                return item
            }

            guard item.depth < budget.maximumDepth,
                  role == kAXWindowRole
                    || role == kAXGroupRole
                    || role == "AXWebArea"
                    || role == kAXScrollAreaRole,
                  let children = elementArrayValue(
                      item.element,
                      kAXChildrenAttribute
                  ) else { continue }
            for child in children where shouldTraverse(
                child,
                inside: windowFrame
            ) {
                queue.append((child, item.depth + 1))
            }
        }
        return nil
    }

    private func findUniqueShellRow(
        below main: AXUIElement,
        mainFrame: CGRect,
        startingDepth: Int,
        nodeCount: inout Int,
        deadline: ContinuousClock.Instant,
        budget: CodexAccessibilityTraversalBudget
    ) -> AXUIElement? {
        guard startingDepth < budget.maximumDepth,
              let children = elementArrayValue(main, kAXChildrenAttribute)
        else { return nil }

        return CodexAccessibilityTargetedTraversal.uniqueMatch(
            among: children,
            startingDepth: startingDepth + 1,
            nodeCount: &nodeCount,
            budget: budget,
            isBeforeDeadline: { self.clock.now < deadline },
            isMatch: { element in
                let classTokens = Set(
                    self.stringArrayValue(element, "AXDOMClassList") ?? []
                )
                return CodexAccessibilityRightPanelClassifier
                    .shellRowClassTokens.isSubset(of: classTokens)
                    && self.approximatelyEqual(
                        self.frameValue(element),
                        mainFrame
                    )
            },
            children: {
                self.elementArrayValue($0, kAXChildrenAttribute)
            },
            shouldTraverse: {
                self.shouldTraverse($0, inside: mainFrame)
            }
        )
    }

    private func shouldTraverse(
        _ element: AXUIElement,
        inside windowFrame: CGRect
    ) -> Bool {
        guard let role = stringValue(element, kAXRoleAttribute),
              role == kAXGroupRole
                || role == "AXWebArea"
                || role == kAXScrollAreaRole else { return false }
        guard let frame = frameValue(element) else { return true }
        guard frame.intersects(windowFrame), frame.width > 0, frame.height > 0
        else { return false }
        if stringValue(element, kAXSubroleAttribute) == "AXLandmarkMain" {
            return true
        }
        return area(frame) >= area(windowFrame) * 0.08
    }

    private func shallowSnapshot(
        _ element: AXUIElement,
        children: [CodexAccessibilityElementSnapshot] = []
    ) -> CodexAccessibilityElementSnapshot {
        CodexAccessibilityElementSnapshot(
            role: stringValue(element, kAXRoleAttribute) ?? "",
            subrole: stringValue(element, kAXSubroleAttribute),
            frame: frameValue(element),
            classTokens: Set(
                stringArrayValue(element, "AXDOMClassList") ?? []
            ),
            children: children
        )
    }

    private func approximatelyEqual(
        _ lhs: CGRect?,
        _ rhs: CGRect,
        tolerance: CGFloat = 3
    ) -> Bool {
        guard let lhs else { return false }
        return abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.maxX - rhs.maxX) <= tolerance
            && abs(lhs.maxY - rhs.maxY) <= tolerance
    }

    private func isStandardWindow(_ element: AXUIElement) -> Bool {
        stringValue(element, kAXRoleAttribute) == kAXWindowRole
            && stringValue(element, kAXSubroleAttribute)
                == kAXStandardWindowSubrole
    }

    private func stringValue(
        _ element: AXUIElement,
        _ attribute: String
    ) -> String? {
        copyValue(element, attribute) as? String
    }

    private func stringArrayValue(
        _ element: AXUIElement,
        _ attribute: String
    ) -> [String]? {
        copyValue(element, attribute) as? [String]
    }

    private func elementValue(
        _ element: AXUIElement,
        _ attribute: String
    ) -> AXUIElement? {
        guard let value = copyValue(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func elementArrayValue(
        _ element: AXUIElement,
        _ attribute: String
    ) -> [AXUIElement]? {
        copyValue(element, attribute) as? [AXUIElement]
    }

    private func frameValue(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = copyValue(element, kAXPositionAttribute),
              let sizeValue = copyValue(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let positionAXValue = unsafeBitCast(
            positionValue,
            to: AXValue.self
        )
        let sizeAXValue = unsafeBitCast(sizeValue, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func copyValue(
        _ element: AXUIElement,
        _ attribute: String
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return nil }
        return value
    }

    private func area(_ frame: CGRect?) -> CGFloat {
        guard let frame else { return 0 }
        return frame.width * frame.height
    }
}
