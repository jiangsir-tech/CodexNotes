import CodexNotesCore
import Foundation
import XCTest
@testable import CodexNotesProbe

@MainActor
final class ProbeViewModelRightPanelAvoidanceTests: XCTestCase {
    func testDetectorCanBeDisabledAndReenabledIndependently() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ProbeViewModel(noteStore: NoteStore(rootURL: root))

        XCTAssertFalse(model.isRightPanelAvoidanceEnabled)

        model.setRightPanelAvoidanceEnabled(true)
        XCTAssertTrue(model.isRightPanelAvoidanceEnabled)
        XCTAssertEqual(model.rightPanelObservation.state, .unknown)
        XCTAssertNotNil(model.rightPanelObservation.selectionStableKey)

        model.setRightPanelAvoidanceEnabled(false)
        XCTAssertFalse(model.isRightPanelAvoidanceEnabled)
        XCTAssertEqual(model.rightPanelObservation.state, .unknown)
        XCTAssertNotNil(model.rightPanelObservation.selectionStableKey)

        model.setRightPanelAvoidanceEnabled(true)
        XCTAssertTrue(model.isRightPanelAvoidanceEnabled)
        XCTAssertEqual(model.rightPanelObservation.state, .unknown)
        XCTAssertNotNil(model.rightPanelObservation.selectionStableKey)
    }
}
