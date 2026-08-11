import Foundation
import XCTest
@testable import CodexNotesCore

final class CodexLogMonitorTests: XCTestCase {
    private static let fixturePID: pid_t = 42_424

    private final class PIDState: @unchecked Sendable {
        var value: pid_t?

        init(_ value: pid_t?) {
            self.value = value
        }
    }

    private var temporaryRoot: URL!
    private var logURL: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CodexLogMonitorTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
        logURL = temporaryRoot.appendingPathComponent(
            "codex-desktop-fixture-\(Self.fixturePID)-t0-i1-000001-0.log"
        )
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        logURL = nil
        temporaryRoot = nil
    }

    func testBootstrapFindsMarkerBehindMoreThanTwoMegabytesOfNoise() async throws {
        let threadID = "11111111-2222-7333-8444-555555555555"
        let marker = selectionLine(
            timestamp: "2030-01-02T03:04:05.678Z",
            threadID: threadID
        )
        let noiseLine = String(repeating: "n", count: 8_191) + "\n"
        let trailingNoise = String(repeating: noiseLine, count: 257)
        XCTAssertGreaterThan(trailingNoise.utf8.count, 2_000_000)
        try write(Data((marker + "\n" + trailingNoise).utf8))

        let selection = try await makeMonitor().bootstrap()

        XCTAssertEqual(selection?.threadID, threadID)
        XCTAssertEqual(selection?.timestamp, "2030-01-02T03:04:05.678Z")
    }

    func testBootstrapSearchesPastFortyRotatedFiles() async throws {
        let threadID = "10101010-2020-7333-8444-505050505050"
        for index in 0..<41 {
            let file = fixtureLogURL(index: index)
            let contents: String
            if index == 40 {
                contents = selectionLine(
                    timestamp: "2030-01-02T03:05:06.789Z",
                    threadID: threadID
                ) + "\n"
            } else {
                contents = "rotated noise \(index)\n"
            }
            try write(Data(contents.utf8), to: file)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: Double(100 - index))],
                ofItemAtPath: file.path
            )
        }

        let selection = try await makeMonitor().bootstrap()

        XCTAssertEqual(selection?.threadID, threadID)
    }

    func testBootstrapDoesNotFallBackToPreviousLaunchUUIDWithReusedPID() async throws {
        let oldLaunchURL = fixtureLogURL(family: "old-launch", index: 1)
        try write(
            Data(
                (selectionLine(
                    timestamp: "2030-01-02T03:06:07.890Z",
                    threadID: "stale-reused-pid-thread"
                ) + "\n").utf8
            ),
            to: oldLaunchURL
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: oldLaunchURL.path
        )

        let currentLaunchURL = fixtureLogURL(family: "current-launch", index: 1)
        try write(Data("current launch noise without a selection\n".utf8), to: currentLaunchURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: currentLaunchURL.path
        )

        let selection = try await makeMonitor().bootstrap()

        XCTAssertNil(selection)
    }

    func testBootstrapParsesMarkerSplitAcrossBackwardReadChunks() async throws {
        let chunkSize = 512
        let threadID = "22222222-3333-7444-8555-666666666666"
        let marker = Data(
            selectionLine(
                timestamp: "2030-02-03T04:05:06.789Z",
                threadID: threadID
            ).utf8
        )
        let suffixCount = chunkSize - marker.count / 2 - 1
        XCTAssertGreaterThan(suffixCount, 0)

        var contents = Data("older noise\n".utf8)
        contents.append(marker)
        contents.append(0x0A)
        contents.append(Data(repeating: 0x78, count: suffixCount))
        try write(contents)

        let selection = try await makeMonitor(
            bootstrapChunkSize: chunkSize
        ).bootstrap()

        XCTAssertEqual(selection?.threadID, threadID)
    }

    func testNoMarkerKeepsCursorAndPollFindsAppendedSelection() async throws {
        try write(Data("ordinary log line\nunfinished UTF-8: \u{732b}".utf8))
        let monitor = makeMonitor()

        let initial = try await monitor.bootstrap()
        XCTAssertNil(initial)

        let threadID = "33333333-4444-7555-8666-777777777777"
        try append(
            Data(
                ("\n" + selectionLine(
                    timestamp: "2030-03-04T05:06:07.890Z",
                    threadID: threadID
                ) + "\n").utf8
            )
        )

        let selection = try await monitor.poll()
        XCTAssertEqual(selection?.threadID, threadID)
    }

    func testUTF8SplitAcrossBootstrapAndPollPreservesSelectionLine() async throws {
        let threadID = "thread-\u{732b}"
        let line = Data(
            selectionLine(
                timestamp: "2030-03-04T05:07:08.901Z",
                threadID: threadID
            ).utf8
        )
        let characterBytes = Data("\u{732b}".utf8)
        let characterRange = try XCTUnwrap(line.range(of: characterBytes))
        let splitIndex = line.index(after: characterRange.lowerBound)
        try write(Data(line[..<splitIndex]))
        let monitor = makeMonitor()

        // An unterminated selection line must remain buffered, even though its
        // final UTF-8 scalar is currently incomplete.
        let initial = try await monitor.bootstrap()
        XCTAssertNil(initial)

        var remainder = Data(line[splitIndex..<line.endIndex])
        remainder.append(0x0A)
        try append(remainder)

        let selection = try await monitor.poll()
        XCTAssertEqual(selection?.threadID, threadID)
        XCTAssertEqual(selection?.stableKey, "local:\(threadID)")
    }

    func testBootstrapChoosesLaterMarkerWhenTimestampsTie() async throws {
        let olderThreadID = "44444444-5555-7666-8777-888888888888"
        let latestThreadID = "55555555-6666-7777-8888-999999999999"
        let tiedTimestamp = "2030-04-05T06:07:08.901Z"
        let contents = [
            selectionLine(
                timestamp: tiedTimestamp,
                threadID: olderThreadID
            ),
            "ordinary log line",
            selectionLine(
                timestamp: tiedTimestamp,
                threadID: latestThreadID
            ),
            ""
        ].joined(separator: "\n")
        try write(Data(contents.utf8))

        let selection = try await makeMonitor().bootstrap()

        XCTAssertEqual(selection?.threadID, latestThreadID)
        XCTAssertEqual(selection?.timestamp, tiedTimestamp)
    }

    func testPollReseedsFileReplacedAtSamePath() async throws {
        let oldThreadID = "66666666-7777-7888-8999-000000000000"
        let newThreadID = "77777777-8888-7999-8000-111111111111"
        let oldContents = selectionLine(
            timestamp: "2030-05-06T07:08:09.123Z",
            threadID: oldThreadID
        ) + "\n"
        try write(Data(oldContents.utf8))
        let monitor = makeMonitor()
        let initial = try await monitor.bootstrap()
        XCTAssertEqual(initial?.threadID, oldThreadID)

        try FileManager.default.removeItem(at: logURL)
        let newContents = selectionLine(
            timestamp: "2030-05-06T07:09:10.234Z",
            threadID: newThreadID
        ) + "\n" + String(repeating: "replacement noise\n", count: 32)
        XCTAssertGreaterThanOrEqual(newContents.utf8.count, oldContents.utf8.count)
        try write(Data(newContents.utf8))

        let selection = try await monitor.poll()
        XCTAssertEqual(selection?.threadID, newThreadID)
    }

    func testDeletedOldCursorDoesNotBlockPollingNewActiveFile() async throws {
        let oldThreadID = "80808080-7070-7666-8555-404040404040"
        let activeThreadID = "90909090-8080-7777-8666-303030303030"
        let tiedTimestamp = "2030-06-07T08:09:10.345Z"
        try write(
            Data(
                (selectionLine(
                    timestamp: tiedTimestamp,
                    threadID: oldThreadID
                ) + "\n").utf8
            )
        )
        let monitor = makeMonitor()
        let initial = try await monitor.bootstrap()
        XCTAssertEqual(initial?.threadID, oldThreadID)

        let activeURL = fixtureLogURL(index: 2)
        try write(
            Data(
                (selectionLine(
                    timestamp: tiedTimestamp,
                    threadID: activeThreadID
                ) + "\n").utf8
            ),
            to: activeURL
        )
        try FileManager.default.removeItem(at: logURL)

        var selection: CodexSelection?
        for _ in 0..<6 {
            selection = try await monitor.poll()
        }
        XCTAssertEqual(selection?.threadID, activeThreadID)
    }

    func testPollDrainsOldTailBeforeFollowingNewRotationOnRefresh() async throws {
        try write(Data("old active file without a selection\n".utf8))
        let monitor = makeMonitor()
        let initial = try await monitor.bootstrap()
        XCTAssertNil(initial)

        // Put the monitor immediately before its sixth-poll candidate refresh.
        for _ in 0..<5 {
            let selection = try await monitor.poll()
            XCTAssertNil(selection)
        }

        let threadID = "selection-at-old-rotation-tail"
        try append(
            Data(
                (selectionLine(
                    timestamp: "2030-06-07T08:10:11.456Z",
                    threadID: threadID
                ) + "\n").utf8
            )
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: logURL.path
        )

        let newActiveURL = fixtureLogURL(index: 2)
        try write(Data("new active file without a selection\n".utf8), to: newActiveURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newActiveURL.path
        )

        // The old cursor must reach its snapshot EOF before the refresh moves
        // incremental monitoring to the newer active file.
        let selection = try await monitor.poll()
        XCTAssertEqual(selection?.threadID, threadID)
    }

    func testPollRecoversUnreadTailWhenOldRotationIsRenamed() async throws {
        try write(Data("old active file without a selection\n".utf8))
        let monitor = makeMonitor()
        let initial = try await monitor.bootstrap()
        XCTAssertNil(initial)

        for _ in 0..<5 {
            _ = try await monitor.poll()
        }

        let threadID = "selection-in-renamed-old-rotation"
        try append(
            Data(
                (selectionLine(
                    timestamp: "2030-06-07T08:10:12.567Z",
                    threadID: threadID
                ) + "\n").utf8
            )
        )
        let rotatedURL = fixtureLogURL(index: 1)
        try FileManager.default.moveItem(at: logURL, to: rotatedURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: rotatedURL.path
        )

        let newActiveURL = fixtureLogURL(index: 2)
        try write(Data("new active file without a selection\n".utf8), to: newActiveURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newActiveURL.path
        )

        let selection = try await monitor.poll()
        XCTAssertEqual(selection?.threadID, threadID)
    }

    func testPollRejectsWhenAllCurrentPIDLogsDisappear() async throws {
        try write(
            Data(
                (selectionLine(
                    timestamp: "2030-06-07T08:11:12.567Z",
                    threadID: "live-before-log-removal"
                ) + "\n").utf8
            )
        )
        let monitor = makeMonitor()
        let initial = try await monitor.bootstrap()
        XCTAssertEqual(initial?.threadID, "live-before-log-removal")

        try FileManager.default.removeItem(at: logURL)
        do {
            _ = try await monitor.poll()
            XCTFail("当前 PID 的日志全部消失时必须停止绑定")
        } catch CodexProbeError.noCodexLog {
            // Expected.
        }
    }

    func testBootstrapRejectsHistoricalLogsWhenCodexIsNotRunning() async throws {
        try write(
            Data(
                (selectionLine(
                    timestamp: "2030-07-08T09:10:11.567Z",
                    threadID: "historical-thread"
                ) + "\n").utf8
            )
        )
        let monitor = CodexLogMonitor(
            logRoot: temporaryRoot,
            runningCodexPIDProvider: { nil },
            bootstrapChunkSize: 64 * 1_024
        )

        do {
            _ = try await monitor.bootstrap()
            XCTFail("Codex 未运行时不得绑定历史日志")
        } catch CodexProbeError.noCodexLog {
            // Expected: ProbeViewModel will keep the editor read-only.
        }
    }

    func testPollClearsLiveSelectionWhenCodexStops() async throws {
        let pidState = PIDState(Self.fixturePID)
        let threadID = "live-before-stop"
        try write(
            Data(
                (selectionLine(
                    timestamp: "2030-08-09T10:11:12.678Z",
                    threadID: threadID
                ) + "\n").utf8
            )
        )
        let monitor = CodexLogMonitor(
            logRoot: temporaryRoot,
            runningCodexPIDProvider: { pidState.value },
            bootstrapChunkSize: 64 * 1_024
        )
        let initial = try await monitor.bootstrap()
        XCTAssertEqual(initial?.threadID, threadID)

        pidState.value = nil
        do {
            _ = try await monitor.poll()
            XCTFail("Codex 退出后 poll 应报告主日志不可用")
        } catch CodexProbeError.noCodexLog {
            // Expected.
        }

        // A later process with the same fixture PID must not inherit the old
        // in-memory selection when its live log has no marker.
        try write(Data("new process noise\n".utf8))
        pidState.value = Self.fixturePID
        let afterRestart = try await monitor.poll()
        XCTAssertNil(afterRestart)
    }

    func testPollRejectsNewLivePIDWithoutCurrentLog() async throws {
        let pidState = PIDState(Self.fixturePID)
        try write(
            Data(
                (selectionLine(
                    timestamp: "2030-08-09T10:12:13.789Z",
                    threadID: "old-live-process"
                ) + "\n").utf8
            )
        )
        let monitor = CodexLogMonitor(
            logRoot: temporaryRoot,
            runningCodexPIDProvider: { pidState.value },
            bootstrapChunkSize: 64 * 1_024
        )
        let initial = try await monitor.bootstrap()
        XCTAssertEqual(initial?.threadID, "old-live-process")

        pidState.value = Self.fixturePID + 1
        do {
            _ = try await monitor.poll()
            XCTFail("新 Codex PID 没有当前日志时必须停止绑定")
        } catch CodexProbeError.noCodexLog {
            // Expected: historical files from the previous PID are ignored.
        }
    }

    func testPollDetectsCopyTruncateThatRegrowsPastOldOffset() async throws {
        let oldThreadID = "copytruncate-old"
        let newThreadID = "copytruncate-new"
        let oldContents = selectionLine(
            timestamp: "2030-09-10T11:12:13.789Z",
            threadID: oldThreadID
        ) + "\n" + String(repeating: "old noise\n", count: 16)
        try write(Data(oldContents.utf8))
        let originalFileNumber = fileNumber(at: logURL)
        let monitor = makeMonitor(bootstrapChunkSize: 128)
        let initial = try await monitor.bootstrap()
        XCTAssertEqual(initial?.threadID, oldThreadID)

        let newPrefix = selectionLine(
            timestamp: "2030-09-10T11:13:14.890Z",
            threadID: newThreadID
        ) + "\n"
        var newData = Data(newPrefix.utf8)
        XCTAssertLessThanOrEqual(newData.count, oldContents.utf8.count)
        newData.append(
            Data(
                repeating: 0x78,
                count: oldContents.utf8.count - newData.count
            )
        )
        XCTAssertEqual(newData.count, oldContents.utf8.count)
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: newData)
        try handle.close()
        XCTAssertEqual(fileNumber(at: logURL), originalFileNumber)

        let selection = try await monitor.poll()
        XCTAssertEqual(selection?.threadID, newThreadID)
    }

    func testPollProcessesLargeForwardDeltaInChunks() async throws {
        try write(Data("initial noise\n".utf8))
        let monitor = makeMonitor(bootstrapChunkSize: 128)
        let initial = try await monitor.bootstrap()
        XCTAssertNil(initial)

        let threadID = "large-forward-delta"
        let appended = String(repeating: "forward noise line\n", count: 256)
            + selectionLine(
                timestamp: "2030-10-11T12:13:14.901Z",
                threadID: threadID
            )
            + "\n"
        XCTAssertGreaterThan(appended.utf8.count, 128 * 10)
        try append(Data(appended.utf8))

        let selection = try await monitor.poll()
        XCTAssertEqual(selection?.threadID, threadID)
    }

    private func makeMonitor(
        bootstrapChunkSize: Int = 64 * 1_024
    ) -> CodexLogMonitor {
        CodexLogMonitor(
            logRoot: temporaryRoot,
            runningCodexPIDProvider: { Self.fixturePID },
            bootstrapChunkSize: bootstrapChunkSize
        )
    }

    private func write(_ data: Data) throws {
        try write(data, to: logURL)
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }

    private func append(_ data: Data) throws {
        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func selectionLine(timestamp: String, threadID: String) -> String {
        "\(timestamp) info [electron-message-handler] "
            + "IAB_LIFECYCLE received browser sidebar owner sync "
            + "browserTabId=null conversationId=client-new-thread:fixture "
            + "originWebContentsId=1 ownerRoutePath=/local/\(threadID) windowId=1"
    }

    private func fixtureLogURL(index: Int) -> URL {
        fixtureLogURL(family: "fixture", index: index)
    }

    private func fixtureLogURL(family: String, index: Int) -> URL {
        temporaryRoot.appendingPathComponent(
            "codex-desktop-\(family)-\(Self.fixturePID)-t0-i1-\(index).log"
        )
    }

    private func fileNumber(at url: URL) -> UInt64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
    }
}
