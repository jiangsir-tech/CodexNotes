@testable import CodexNotesProbe
import XCTest

final class ScopeSelectorPresentationTests: XCTestCase {
    func testSelectionIndicatorUsesApprovedCompactDotGeometry() {
        XCTAssertEqual(ScopeSelectionIndicatorMetrics.diameter, 6)
        XCTAssertEqual(ScopeSelectionIndicatorMetrics.edgeInset, 8)
        XCTAssertEqual(
            ScopeSelectionIndicatorMetrics.diameter
                + ScopeSelectionIndicatorMetrics.edgeInset,
            14
        )
    }
}
