import XCTest

final class SettingsEditorPresentationTests: XCTestCase {
    func testResizeHintUsesAnAdaptiveAccessibleFooter() throws {
        let source = try repositorySource(
            at: "Sources/CodexNotesProbe/SettingsView.swift"
        )

        XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(source.contains(".lineLimit(1)"))
        XCTAssertTrue(source.contains(
            ".fixedSize(horizontal: true, vertical: false)"
        ))
        XCTAssertTrue(source.contains("VStack(alignment: .leading, spacing: 8)"))
        XCTAssertTrue(source.contains(".settingsEditorWindowResizeHint"))
        XCTAssertTrue(source.contains(
            "Image(systemName: \"arrow.up.left.and.arrow.down.right\")"
        ))
        XCTAssertTrue(source.contains(".accessibilityElement(children: .combine)"))

        let hintRange = try XCTUnwrap(source.range(of: "editorWindowResizeHint"))
        let restoreRange = try XCTUnwrap(source.range(of: "editorRestoreDefaultsButton"))
        XCTAssertLessThan(hintRange.lowerBound, restoreRange.lowerBound)
    }

    private func repositorySource(at relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
