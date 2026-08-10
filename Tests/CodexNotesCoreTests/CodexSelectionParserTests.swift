import XCTest
@testable import CodexNotesCore

final class CodexSelectionParserTests: XCTestCase {
    func testParsesLocalTask() {
        let selection = CodexSelectionParser.parse(line: localLine)

        XCTAssertEqual(selection?.kind, .local)
        XCTAssertEqual(selection?.threadID, "11111111-2222-7333-8444-555555555555")
        XCTAssertNil(selection?.hostID)
        XCTAssertEqual(selection?.stableKey, "local:11111111-2222-7333-8444-555555555555")
    }

    func testParsesRemoteTaskAndDecodesHost() {
        let line = localLine.replacingOccurrences(
            of: "ownerRoutePath=/local/11111111-2222-7333-8444-555555555555",
            with: "ownerRoutePath=/local/11111111-2222-7333-8444-555555555555?hostId=remote-control%3Aenv_example"
        )
        let selection = CodexSelectionParser.parse(line: line)

        XCTAssertEqual(selection?.threadID, "11111111-2222-7333-8444-555555555555")
        XCTAssertEqual(selection?.hostID, "remote-control:env_example")
        XCTAssertEqual(selection?.stableKey, "remote-control:env_example:11111111-2222-7333-8444-555555555555")
    }

    func testParsesWorkConversation() {
        let line = localLine.replacingOccurrences(
            of: "ownerRoutePath=/local/11111111-2222-7333-8444-555555555555",
            with: "ownerRoutePath=/work/conversation/local-chatgpt%3Aabc-123"
        )
        let selection = CodexSelectionParser.parse(line: line)

        XCTAssertEqual(selection?.kind, .work)
        XCTAssertEqual(selection?.threadID, "local-chatgpt:abc-123")
        XCTAssertEqual(selection?.stableKey, "work:local-chatgpt:abc-123")
    }

    func testParsesBlankNewTaskWithoutReusingOldID() {
        let line = localLine.replacingOccurrences(
            of: "ownerRoutePath=/local/11111111-2222-7333-8444-555555555555",
            with: "ownerRoutePath=/"
        )
        let selection = CodexSelectionParser.parse(line: line)

        XCTAssertEqual(selection?.kind, .newTask)
        XCTAssertNil(selection?.threadID)
        XCTAssertEqual(selection?.stableKey, "new:1:client-new-thread:fixture-001")
    }

    func testRejectsBackgroundThreadMessages() {
        let line = "2030-01-02T03:04:05.678Z info [electron-message-handler] Reasoning summary item completed threadId=11111111-2222-7333-8444-555555555555"
        XCTAssertNil(CodexSelectionParser.parse(line: line))
    }

    private let localLine = "2030-01-02T03:04:05.678Z info [electron-message-handler] IAB_LIFECYCLE received browser sidebar owner sync browserTabId=null conversationId=client-new-thread:fixture-001 originWebContentsId=1 ownerRoutePath=/local/11111111-2222-7333-8444-555555555555 windowId=1"
}
