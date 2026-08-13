import CodexNotesCore
import XCTest
@testable import CodexNotesProbe

final class CodexAccessibilityRightPanelReaderTests: XCTestCase {
    func testClassifiesClosedExactLayout() {
        XCTAssertEqual(
            CodexAccessibilityRightPanelClassifier.state(in: [tree(open: false)]),
            .closed
        )
    }

    func testClassifiesOpenExactLayoutIncludingEmptyBrowserPage() {
        XCTAssertEqual(
            CodexAccessibilityRightPanelClassifier.state(in: [tree(open: true)]),
            .open
        )
    }

    func testFindsShellRowBelowSeveralWrappers() {
        let viewport = element(
            frame: mainFrame,
            classes: ["_MainContentViewport_1e9gb_72"]
        )
        let shell = element(
            frame: mainFrame,
            classes: CodexAccessibilityRightPanelClassifier.shellRowClassTokens,
            children: [viewport]
        )
        let main = element(
            subrole: "AXLandmarkMain",
            frame: mainFrame,
            children: [
                element(children: [element(children: [shell])]),
            ]
        )

        XCTAssertEqual(
            CodexAccessibilityRightPanelClassifier.shellRows(in: main),
            [shell]
        )
        XCTAssertEqual(
            CodexAccessibilityRightPanelClassifier.state(in: [main]),
            .closed
        )
    }

    func testInjectedReaderClassifiesNestedOpenTree() async {
        let reader = CodexAccessibilityRightPanelReader(
            backend: FakeAccessibilityBackend(
                roots: [tree(open: true)]
            )
        )

        let sample = await reader.sample()
        XCTAssertEqual(
            sample,
            CodexAccessibilityRightPanelSample(
                state: .open,
                permission: .authorized
            )
        )
    }

    func testInjectedReaderDeniedPermissionFailsUnknownWithoutRoots() async {
        let reader = CodexAccessibilityRightPanelReader(
            backend: FakeAccessibilityBackend(
                isTrusted: false,
                processIdentifier: nil,
                roots: nil
            )
        )

        let sample = await reader.sample()
        XCTAssertEqual(
            sample,
            CodexAccessibilityRightPanelSample(
                state: .unknown,
                permission: .denied
            )
        )
    }

    func testTargetedTraversalFindsUniqueShellBelowWrappers() {
        let shell = element(
            frame: mainFrame,
            classes: CodexAccessibilityRightPanelClassifier.shellRowClassTokens
        )
        let roots = [element(children: [element(children: [shell])])]
        var nodeCount = 0
        let budget = CodexAccessibilityTraversalBudget(
            maximumNodes: 8,
            maximumDepth: 4,
            maximumDuration: .milliseconds(20)
        )

        let match = CodexAccessibilityTargetedTraversal.uniqueMatch(
            among: roots,
            startingDepth: 1,
            nodeCount: &nodeCount,
            budget: budget,
            isBeforeDeadline: { true },
            isMatch: {
                CodexAccessibilityRightPanelClassifier.shellRowClassTokens
                    .isSubset(of: $0.classTokens)
            },
            children: { $0.children },
            shouldTraverse: { _ in true }
        )

        XCTAssertEqual(match, shell)
        XCTAssertEqual(nodeCount, 3)
    }

    func testTargetedTraversalFailsUnknownWhenBudgetExpires() {
        let shell = element(
            frame: mainFrame,
            classes: CodexAccessibilityRightPanelClassifier.shellRowClassTokens
        )
        let roots = [element(children: [element(children: [shell])])]
        var nodeCount = 0
        let budget = CodexAccessibilityTraversalBudget(
            maximumNodes: 2,
            maximumDepth: 4,
            maximumDuration: .milliseconds(20)
        )

        let match = CodexAccessibilityTargetedTraversal.uniqueMatch(
            among: roots,
            startingDepth: 1,
            nodeCount: &nodeCount,
            budget: budget,
            isBeforeDeadline: { true },
            isMatch: {
                CodexAccessibilityRightPanelClassifier.shellRowClassTokens
                    .isSubset(of: $0.classTokens)
            },
            children: { $0.children },
            shouldTraverse: { _ in true }
        )

        XCTAssertNil(match)
        XCTAssertEqual(nodeCount, 2)
    }

    func testMissingShellRowIsUnknown() {
        let main = element(
            subrole: "AXLandmarkMain",
            frame: mainFrame,
            children: []
        )
        XCTAssertEqual(
            CodexAccessibilityRightPanelClassifier.state(in: [main]),
            .unknown
        )
    }

    func testNarrowViewportWithoutAsideIsUnknownNotClosed() {
        XCTAssertEqual(
            CodexAccessibilityRightPanelClassifier.state(
                in: [tree(open: false, viewportFrame: openViewportFrame)]
            ),
            .unknown
        )
    }

    func testSummaryOverlayDoesNotCountAsRightPanel() {
        let summary = element(
            frame: CGRect(x: 2054, y: 124, width: 506, height: 1297),
            classes: [
                "pointer-events-none", "absolute", "right-0", "z-40",
            ]
        )
        XCTAssertEqual(
            CodexAccessibilityRightPanelClassifier.state(
                in: [tree(open: false, extraShellChildren: [summary])]
            ),
            .closed
        )
    }

    func testGenericAsideTokenOnViewportDoesNotCreateFalseCandidate() {
        let viewport = element(
            frame: mainFrame,
            classes: ["_MainContentViewport_1e9gb_72", "relative"]
        )
        let shell = element(
            frame: mainFrame,
            classes: CodexAccessibilityRightPanelClassifier.shellRowClassTokens,
            children: [viewport]
        )
        let main = element(
            subrole: "AXLandmarkMain",
            frame: mainFrame,
            children: [element(children: [shell])]
        )

        XCTAssertEqual(
            CodexAccessibilityRightPanelClassifier.state(in: [main]),
            .closed
        )
    }

    func testAsideWithWrongGeometryIsUnknown() {
        let wrongAside = aside(
            frame: CGRect(x: 1800, y: 31, width: 500, height: 1409)
        )
        XCTAssertEqual(
            CodexAccessibilityRightPanelClassifier.state(
                in: [tree(
                    open: false,
                    viewportFrame: openViewportFrame,
                    extraShellChildren: [wrongAside]
                )]
            ),
            .unknown
        )
    }

    func testPartialAsideClassDriftIsUnknown() {
        let drifted = element(
            subrole: "AXLandmarkComplementary",
            frame: openAsideFrame,
            classes: ["relative", "z-[41]", "h-full"]
        )
        XCTAssertEqual(
            CodexAccessibilityRightPanelClassifier.state(
                in: [tree(
                    open: false,
                    viewportFrame: openViewportFrame,
                    extraShellChildren: [drifted]
                )]
            ),
            .unknown
        )
    }

    func testLargestMainLandmarkWins() {
        let smallMain = element(
            subrole: "AXLandmarkMain",
            frame: CGRect(x: 0, y: 0, width: 700, height: 500)
        )
        XCTAssertEqual(
            CodexAccessibilityRightPanelClassifier.state(
                in: [smallMain, tree(open: true)]
            ),
            .open
        )
    }

    func testDebouncerRequiresTwoMatchingDefiniteSamples() {
        var debouncer = CodexRightPanelDebouncer()
        XCTAssertNil(debouncer.observe(.open))
        XCTAssertEqual(debouncer.observe(.open), .open)
        XCTAssertNil(debouncer.observe(.open))
    }

    func testDebouncerUnknownBreaksCandidateWithoutPublishingUnknown() {
        var debouncer = CodexRightPanelDebouncer()
        XCTAssertNil(debouncer.observe(.closed))
        XCTAssertNil(debouncer.observe(.unknown))
        XCTAssertNil(debouncer.observe(.closed))
        XCTAssertEqual(debouncer.observe(.closed), .closed)
    }

    func testDebouncerPublishesNewOppositeStateAfterConfirmation() {
        var debouncer = CodexRightPanelDebouncer()
        XCTAssertNil(debouncer.observe(.closed))
        XCTAssertEqual(debouncer.observe(.closed), .closed)
        XCTAssertNil(debouncer.observe(.open))
        XCTAssertEqual(debouncer.observe(.open), .open)
    }

    func testDebouncerResetAllowsRepublishingSameState() {
        var debouncer = CodexRightPanelDebouncer()
        _ = debouncer.observe(.open)
        XCTAssertEqual(debouncer.observe(.open), .open)
        debouncer.reset()
        XCTAssertNil(debouncer.observe(.open))
        XCTAssertEqual(debouncer.observe(.open), .open)
    }

    private let mainFrame = CGRect(x: 576, y: 31, width: 1984, height: 1409)
    private let openViewportFrame = CGRect(
        x: 576,
        y: 31,
        width: 972,
        height: 1409
    )
    private let openAsideFrame = CGRect(
        x: 1548,
        y: 31,
        width: 1012,
        height: 1409
    )

    private func tree(
        open: Bool,
        viewportFrame: CGRect? = nil,
        extraShellChildren: [CodexAccessibilityElementSnapshot] = []
    ) -> CodexAccessibilityElementSnapshot {
        let viewport = element(
            frame: viewportFrame ?? (open ? openViewportFrame : mainFrame),
            classes: ["_MainContentViewport_1e9gb_72"]
        )
        var shellChildren = [viewport]
        if open {
            shellChildren.append(aside(frame: openAsideFrame))
        }
        shellChildren.append(contentsOf: extraShellChildren)
        let shell = element(
            frame: mainFrame,
            classes: CodexAccessibilityRightPanelClassifier.shellRowClassTokens,
            children: shellChildren
        )
        return element(
            subrole: "AXLandmarkMain",
            frame: mainFrame,
            children: [element(children: [shell])]
        )
    }

    private func aside(
        frame: CGRect
    ) -> CodexAccessibilityElementSnapshot {
        element(
            subrole: "AXLandmarkComplementary",
            frame: frame,
            classes: CodexAccessibilityRightPanelClassifier.asideClassTokens
        )
    }

    private func element(
        role: String = "AXGroup",
        subrole: String? = nil,
        frame: CGRect? = nil,
        classes: Set<String> = [],
        children: [CodexAccessibilityElementSnapshot] = []
    ) -> CodexAccessibilityElementSnapshot {
        CodexAccessibilityElementSnapshot(
            role: role,
            subrole: subrole,
            frame: frame,
            classTokens: classes,
            children: children
        )
    }
}

private final class FakeAccessibilityBackend:
    CodexAccessibilityReading,
    @unchecked Sendable
{
    private let trusted: Bool
    private let processIdentifier: pid_t?
    private let roots: [CodexAccessibilityElementSnapshot]?

    init(
        isTrusted: Bool = true,
        processIdentifier: pid_t? = 123,
        roots: [CodexAccessibilityElementSnapshot]?
    ) {
        trusted = isTrusted
        self.processIdentifier = processIdentifier
        self.roots = roots
    }

    func isTrusted() -> Bool {
        trusted
    }

    func codexProcessIdentifier() -> pid_t? {
        processIdentifier
    }

    func rootSnapshots(
        for processIdentifier: pid_t,
        budget: CodexAccessibilityTraversalBudget
    ) -> [CodexAccessibilityElementSnapshot]? {
        roots
    }
}
