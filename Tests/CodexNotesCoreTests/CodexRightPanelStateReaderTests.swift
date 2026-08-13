import Foundation
import XCTest
@testable import CodexNotesCore

final class CodexRightPanelStateReaderTests: XCTestCase {
    func testReadsGenericRightPanelState() throws {
        let openData = try fixtureData([
            "thread-tab-routes-v1:target-thread": genericState(open: true)
        ])
        let closedData = try fixtureData([
            "thread-tab-routes-v1:target-thread": genericState(open: false)
        ])

        XCTAssertEqual(
            CodexRightPanelStateParser.state(
                for: "target-thread",
                in: openData
            ),
            .open
        )
        XCTAssertEqual(
            CodexRightPanelStateParser.state(
                for: "target-thread",
                in: closedData
            ),
            .closed
        )
    }

    func testGenericStateWinsWhenBrowserStateConflicts() throws {
        let genericOpenData = try fixtureData([
            "thread-tab-routes-v1:target-thread": genericState(open: true),
            "thread-browser-tabs-v1:target-thread": [
                "rightPanelOpen": false
            ]
        ])
        let genericClosedData = try fixtureData([
            "thread-tab-routes-v1:target-thread": genericState(open: false),
            "thread-browser-tabs-v1:target-thread": [
                "rightPanelOpen": true
            ]
        ])

        XCTAssertEqual(
            CodexRightPanelStateParser.state(
                for: "target-thread",
                in: genericOpenData
            ),
            .open
        )
        XCTAssertEqual(
            CodexRightPanelStateParser.state(
                for: "target-thread",
                in: genericClosedData
            ),
            .closed
        )
    }

    func testMalformedGenericStateFallsBackToBrowserState() throws {
        let malformedGenericStates: [Any] = [
            NSNull(),
            [:],
            ["topology": NSNull()],
            ["topology": [:]],
            ["topology": ["right": NSNull()]],
            ["topology": ["right": [:]]],
            ["topology": ["right": ["open": NSNull()]]],
            ["topology": ["right": ["open": 1]]],
            ["topology": ["right": ["open": "true"]]]
        ]

        for genericState in malformedGenericStates {
            let data = try fixtureData([
                "thread-tab-routes-v1:target-thread": genericState,
                "thread-browser-tabs-v1:target-thread": [
                    "rightPanelOpen": true
                ]
            ])
            XCTAssertEqual(
                CodexRightPanelStateParser.state(
                    for: "target-thread",
                    in: data
                ),
                .open,
                "Did not fall back for malformed generic state: \(genericState)"
            )
        }
    }

    func testGenericStateDoesNotBorrowAnotherThreadsValue() throws {
        let data = try fixtureData([
            "thread-tab-routes-v1:old-thread": genericState(open: true),
            "thread-tab-routes-v1:target-thread": genericState(open: false),
            "thread-browser-tabs-v1:old-thread": ["rightPanelOpen": true]
        ])

        XCTAssertEqual(
            CodexRightPanelStateParser.state(for: "target-thread", in: data),
            .closed
        )
        XCTAssertEqual(
            CodexRightPanelStateParser.state(for: "missing-thread", in: data),
            .closed
        )
    }

    func testValidAtomStateWithBothExactKeysAbsentIsClosed() throws {
        let emptyAtomData = try fixtureData([:])
        let otherThreadData = try fixtureData([
            "thread-tab-routes-v1:other-thread": genericState(open: true),
            "thread-browser-tabs-v1:other-thread": [
                "rightPanelOpen": true
            ]
        ])

        XCTAssertEqual(
            CodexRightPanelStateParser.state(
                for: "target-thread",
                in: emptyAtomData
            ),
            .closed
        )
        XCTAssertEqual(
            CodexRightPanelStateParser.state(
                for: "target-thread",
                in: otherThreadData
            ),
            .closed
        )
    }

    func testPresentInvalidExactKeyWithoutValidFallbackIsUnknown() throws {
        let fixtures = try [
            fixtureData([
                "thread-tab-routes-v1:target-thread": NSNull()
            ]),
            fixtureData([
                "thread-browser-tabs-v1:target-thread": NSNull()
            ]),
            fixtureData([
                "thread-tab-routes-v1:target-thread": [
                    "topology": ["right": ["open": 1]]
                ],
                "thread-browser-tabs-v1:target-thread": [
                    "rightPanelOpen": "false"
                ]
            ])
        ]

        for data in fixtures {
            XCTAssertEqual(
                CodexRightPanelStateParser.state(
                    for: "target-thread",
                    in: data
                ),
                .unknown
            )
        }
    }

    func testReadsTrueForExactThreadAsOpen() throws {
        let data = try fixtureData([
            "thread-browser-tabs-v1:target-thread": ["rightPanelOpen": true]
        ])

        XCTAssertEqual(
            CodexRightPanelStateParser.state(for: "target-thread", in: data),
            .open
        )
    }

    func testReadsFalseForExactThreadAsClosed() throws {
        let data = try fixtureData([
            "thread-browser-tabs-v1:target-thread": ["rightPanelOpen": false]
        ])

        XCTAssertEqual(
            CodexRightPanelStateParser.state(for: "target-thread", in: data),
            .closed
        )
    }

    func testDoesNotBorrowOpenStateFromAnotherThread() throws {
        let data = try fixtureData([
            "thread-browser-tabs-v1:old-thread": ["rightPanelOpen": true],
            "thread-browser-tabs-v1:target-thread": ["rightPanelOpen": false]
        ])

        XCTAssertEqual(
            CodexRightPanelStateParser.state(for: "target-thread", in: data),
            .closed
        )
        XCTAssertEqual(
            CodexRightPanelStateParser.state(for: "missing-thread", in: data),
            .closed
        )
    }

    func testMissingStructuresAreUnknown() throws {
        let fixtures: [Any] = [
            [:],
            ["electron-persisted-atom-state": NSNull()],
            ["electron-persisted-atom-state": []],
            [
                "electron-persisted-atom-state": [
                    "thread-browser-tabs-v1:target-thread": NSNull()
                ]
            ],
            [
                "electron-persisted-atom-state": [
                    "thread-browser-tabs-v1:target-thread": [:]
                ]
            ],
            [
                "electron-persisted-atom-state": [
                    "thread-browser-tabs-v1:target-thread": [
                        "rightPanelOpen": NSNull()
                    ]
                ]
            ]
        ]

        for fixture in fixtures {
            let data = try JSONSerialization.data(withJSONObject: fixture)
            XCTAssertEqual(
                CodexRightPanelStateParser.state(
                    for: "target-thread",
                    in: data
                ),
                .unknown
            )
        }
    }

    func testMalformedJSONIsUnknown() {
        XCTAssertEqual(
            CodexRightPanelStateParser.state(
                for: "target-thread",
                in: Data("{not-json".utf8)
            ),
            .unknown
        )
    }

    func testTypeDriftIsUnknownInsteadOfTruthy() throws {
        let driftedValues: [Any] = [
            1,
            0,
            "true",
            ["value": true],
            [true]
        ]

        for value in driftedValues {
            let data = try fixtureData([
                "thread-browser-tabs-v1:target-thread": [
                    "rightPanelOpen": value
                ]
            ])
            XCTAssertEqual(
                CodexRightPanelStateParser.state(
                    for: "target-thread",
                    in: data
                ),
                .unknown,
                "Unexpectedly accepted \(value) as a Boolean"
            )
        }
    }

    func testEmptyThreadIDIsUnknown() throws {
        let data = try fixtureData([
            "thread-browser-tabs-v1:": ["rightPanelOpen": true]
        ])

        XCTAssertEqual(
            CodexRightPanelStateParser.state(for: "", in: data),
            .unknown
        )
    }

    func testThreadIDUsesJavaScriptEncodeURIComponentRules() throws {
        let threadID = "thread/有 空格?x=1&y!'()*~.-_"
        let encodedThreadID = "thread%2F%E6%9C%89%20"
            + "%E7%A9%BA%E6%A0%BC%3Fx%3D1%26y!'()*~.-_"
        let expectedGenericKey = "thread-tab-routes-v1:" + encodedThreadID
        let expectedBrowserKey = "thread-browser-tabs-v1:" + encodedThreadID
        XCTAssertEqual(
            CodexRightPanelStateParser.genericPersistedKey(for: threadID),
            expectedGenericKey
        )
        XCTAssertEqual(
            CodexRightPanelStateParser.browserPersistedKey(for: threadID),
            expectedBrowserKey
        )
        XCTAssertEqual(
            CodexRightPanelStateParser.persistedKey(for: threadID),
            expectedBrowserKey
        )

        let data = try fixtureData([
            expectedGenericKey: genericState(open: true),
            expectedBrowserKey: ["rightPanelOpen": false],
            "thread-browser-tabs-v1:\(threadID)": ["rightPanelOpen": false]
        ])
        XCTAssertEqual(
            CodexRightPanelStateParser.state(for: threadID, in: data),
            .open
        )
    }

    func testFileReaderReadsFreshSnapshots() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let stateURL = directory.appendingPathComponent("state.json")
        try fixtureData([
            "thread-browser-tabs-v1:target-thread": ["rightPanelOpen": true]
        ]).write(to: stateURL, options: .atomic)
        let reader = CodexRightPanelStateReader(globalStateURL: stateURL)

        let openState = await reader.state(for: "target-thread")
        XCTAssertEqual(openState, .open)

        try fixtureData([
            "thread-browser-tabs-v1:target-thread": ["rightPanelOpen": false]
        ]).write(to: stateURL, options: .atomic)
        let closedState = await reader.state(for: "target-thread")
        XCTAssertEqual(closedState, .closed)
    }

    func testFileReaderReturnsUnknownForMissingFile() async {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing-state.json")
        let reader = CodexRightPanelStateReader(globalStateURL: stateURL)

        let state = await reader.state(for: "target-thread")
        XCTAssertEqual(state, .unknown)
    }

    private func fixtureData(_ atomState: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "electron-persisted-atom-state": atomState
        ])
    }

    private func genericState(open: Bool) -> [String: Any] {
        [
            "topology": [
                "right": [
                    "open": open
                ]
            ]
        ]
    }
}
