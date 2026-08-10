import AppKit
import XCTest
@testable import CodexNotesProbe

@MainActor
final class MainWindowFramePersistenceTests: XCTestCase {
    func testFirstLaunchUsesInitialPlacement() {
        XCTAssertEqual(
            MainWindowFramePersistence.plan(
                stableFrameRestored: false,
                currentLegacyFrameAvailable: false
            ),
            .placeInitially
        )
    }

    func testStableFrameAlwaysWinsOverLegacyFrame() {
        XCTAssertEqual(
            MainWindowFramePersistence.plan(
                stableFrameRestored: true,
                currentLegacyFrameAvailable: true
            ),
            .restoreStableFrame
        )
    }

    func testLegacyFrameIsMigratedWhenStableFrameIsMissing() {
        XCTAssertEqual(
            MainWindowFramePersistence.plan(
                stableFrameRestored: false,
                currentLegacyFrameAvailable: true
            ),
            .migrateLegacyFrame
        )
    }

    func testCurrentSwiftUIAutosaveNameMustHaveANonemptyFrame() {
        withDefaults { defaults in
            defaults.set(
                "   ",
                forKey: "NSWindow Frame CurrentSwiftUIFrame"
            )

            XCTAssertFalse(
                MainWindowFramePersistence.currentLegacyFrameIsAvailable(
                    autosaveName: "CurrentSwiftUIFrame",
                    defaults: defaults
                )
            )
        }
    }

    func testOnlyCurrentSwiftUIAutosaveNameIsAccepted() {
        withDefaults { defaults in
            defaults.set(
                "300 400 549 697 0 0 2560 1409 ",
                forKey: "NSWindow Frame OtherSwiftUIFrame"
            )

            XCTAssertEqual(
                MainWindowFramePersistence.legacyFrame(
                    autosaveName: "CurrentSwiftUIFrame",
                    defaults: defaults
                ),
                nil
            )
        }
    }

    func testCurrentSwiftUIAutosaveFrameIsAccepted() {
        withDefaults { defaults in
            defaults.set(
                "300 400 549 697 0 0 2560 1409 ",
                forKey: "NSWindow Frame CurrentSwiftUIFrame"
            )

            XCTAssertTrue(
                MainWindowFramePersistence.currentLegacyFrameIsAvailable(
                    autosaveName: "CurrentSwiftUIFrame",
                    defaults: defaults
                )
            )
        }
    }

    func testStableAutosaveNameIsNeverTreatedAsLegacy() {
        withDefaults { defaults in
            defaults.set(
                "300 400 549 697 0 0 2560 1409 ",
                forKey: MainWindowFramePersistence.autosaveDefaultsKey
            )

            XCTAssertFalse(
                MainWindowFramePersistence.currentLegacyFrameIsAvailable(
                    autosaveName: MainWindowFramePersistence.autosaveName,
                    defaults: defaults
                )
            )
        }
    }

    func testEmptyAutosaveNameFallsBackToKnownMainWindowLegacyFrame() {
        withDefaults { defaults in
            defaults.set(
                "300 400 549 697 0 0 2560 1409 ",
                forKey: legacyFrameKey(modifiedContent: true)
            )

            XCTAssertTrue(
                MainWindowFramePersistence.currentLegacyFrameIsAvailable(
                    autosaveName: "",
                    defaults: defaults
                )
            )
        }
    }

    func testSettingsFrameIsNotMistakenForMainWindowFrame() {
        withDefaults { defaults in
            defaults.set(
                "100 200 560 688 0 0 2560 1409 ",
                forKey: "NSWindow Frame com_apple_SwiftUI_Settings_window"
            )

            XCTAssertFalse(
                MainWindowFramePersistence.currentLegacyFrameIsAvailable(
                    autosaveName: "",
                    defaults: defaults
                )
            )
        }
    }

    func testCurrentModifiedContentFrameIsPreferredDuringMigration() {
        withDefaults { defaults in
            let oldFrame = "100 200 400 660 0 0 2560 1409 "
            let currentFrame = "300 400 549 697 0 0 2560 1409 "
            defaults.set(
                oldFrame,
                forKey: legacyFrameKey(modifiedContent: false)
            )
            defaults.set(
                currentFrame,
                forKey: legacyFrameKey(modifiedContent: true)
            )

            XCTAssertEqual(
                MainWindowFramePersistence.preferredLegacyFrame(in: defaults),
                currentFrame
            )
        }
    }

    func testMissingCurrentAutosaveFrameFallsBackToKnownLegacyFrame() {
        withDefaults { defaults in
            let legacyFrame = frameString(x: 310, y: 280, width: 520, height: 680)
            defaults.set(
                legacyFrame,
                forKey: legacyFrameKey(modifiedContent: true)
            )

            XCTAssertEqual(
                MainWindowFramePersistence.legacyFrame(
                    autosaveName: "MissingCurrentSwiftUIFrame",
                    defaults: defaults
                ),
                legacyFrame
            )
        }
    }

    func testMalformedLegacyFrameIsRejected() {
        withDefaults { defaults in
            defaults.set(
                "300 400 invalid 697 0 0 2560 1409 ",
                forKey: legacyFrameKey(modifiedContent: true)
            )

            XCTAssertNil(
                MainWindowFramePersistence.legacyFrame(
                    autosaveName: "",
                    defaults: defaults
                )
            )
        }
    }

    func testConfigureRestoresFallbackLegacyFrameAndMigratesIt() {
        withStandardFrameDefaults { defaults in
            let legacyFrame = frameString(x: 240, y: 220, width: 520, height: 680)
            defaults.set(
                legacyFrame,
                forKey: legacyFrameKey(modifiedContent: true)
            )
            let window = makeWindow(
                frame: NSRect(x: 40, y: 60, width: 400, height: 660)
            )
            var placementCount = 0
            defer { _ = window.setFrameAutosaveName("") }

            MainWindowFramePersistence.configure(window: window) {
                placementCount += 1
            }

            XCTAssertEqual(placementCount, 0)
            assertFrame(
                window.frame,
                equals: NSRect(x: 240, y: 220, width: 520, height: 680)
            )
            XCTAssertNotNil(
                defaults.string(forKey: MainWindowFramePersistence.autosaveDefaultsKey)
            )
        }
    }

    func testConfigureUsesInitialPlacementOnlyOnceAndThenRestoresStableFrame() {
        withStandardFrameDefaults { _ in
            let initialFrame = NSRect(x: 260, y: 230, width: 510, height: 670)
            let window = makeWindow(
                frame: NSRect(x: 40, y: 60, width: 400, height: 660)
            )
            var placementCount = 0
            defer { _ = window.setFrameAutosaveName("") }

            MainWindowFramePersistence.configure(window: window) {
                placementCount += 1
                window.setFrame(initialFrame, display: false)
            }
            window.setFrame(
                NSRect(x: 70, y: 80, width: 430, height: 640),
                display: false
            )
            MainWindowFramePersistence.persist(window: window)

            MainWindowFramePersistence.configure(window: window) {
                placementCount += 1
            }

            XCTAssertEqual(placementCount, 1)
            assertFrame(
                window.frame,
                equals: NSRect(x: 70, y: 80, width: 430, height: 640)
            )
        }
    }

    func testConfiguredWindowContinuesAutosavingMoveAndResize() {
        withStandardFrameDefaults { _ in
            let window = makeWindow(
                frame: NSRect(x: 80, y: 90, width: 420, height: 620)
            )
            let changedFrame = NSRect(x: 280, y: 250, width: 530, height: 690)
            defer { _ = window.setFrameAutosaveName("") }

            MainWindowFramePersistence.configure(window: window) {}
            window.setFrame(changedFrame, display: false)
            MainWindowFramePersistence.persist(window: window)

            let restoredWindow = makeWindow(
                frame: NSRect(x: 20, y: 30, width: 400, height: 660)
            )
            MainWindowFramePersistence.configure(window: restoredWindow) {
                XCTFail("Stable frame should avoid initial placement")
            }
            assertFrame(restoredWindow.frame, equals: changedFrame)
            _ = restoredWindow.setFrameAutosaveName("")
        }
    }

    func testConfigureClearsSwiftUIFrameAutosaveName() {
        withDefaults { defaults in
            let autosaveName = "MainWindowFramePersistenceTests.\(UUID().uuidString)"
            let autosaveDefaultsKey = "NSWindow Frame \(autosaveName)"
            let legacyFrame = testFrame(xOffset: 40, yOffset: 50)
            defaults.set(
                descriptor(for: legacyFrame),
                forKey: autosaveDefaultsKey
            )
            let window = makeWindow(
                frame: testFrame(xOffset: 160, yOffset: 110)
            )
            defer {
                window.orderOut(nil)
                _ = window.setFrameAutosaveName("")
                UserDefaults.standard.removeObject(forKey: autosaveDefaultsKey)
            }
            XCTAssertTrue(window.setFrameAutosaveName(autosaveName))

            MainWindowFramePersistence.configure(
                window: window,
                defaults: defaults
            ) {
                XCTFail("The current SwiftUI frame should be migrated")
            }

            XCTAssertEqual(window.frameAutosaveName, "")
            assertFrame(window.frame, equals: legacyFrame)
        }
    }

    func testHiddenProgrammaticMoveDoesNotOverwriteStableFrameAndShowRestoresIt() {
        withDefaults { defaults in
            let stableFrame = testFrame(xOffset: 50, yOffset: 60)
            let systemCenteredFrame = testFrame(xOffset: 190, yOffset: 120)
            let window = makeWindow(
                frame: testFrame(xOffset: 20, yOffset: 20)
            )
            defer { window.orderOut(nil) }
            seedStableFrame(stableFrame, defaults: defaults)

            MainWindowFramePersistence.configure(
                window: window,
                defaults: defaults
            ) {
                XCTFail("The stable frame should be restored")
            }
            XCTAssertEqual(window.frameAutosaveName, "")
            assertFrame(window.frame, equals: stableFrame)
            let stableDescriptor = defaults.string(
                forKey: MainWindowFramePersistence.autosaveDefaultsKey
            )

            window.orderOut(nil)
            window.setFrame(systemCenteredFrame, display: false)
            MainWindowFramePersistence.persistIfVisible(
                window: window,
                defaults: defaults
            )

            XCTAssertFalse(window.isVisible)
            XCTAssertEqual(
                defaults.string(
                    forKey: MainWindowFramePersistence.autosaveDefaultsKey
                ),
                stableDescriptor
            )

            MainWindowFramePersistence.showPreservingFrame(
                window: window,
                defaults: defaults
            )

            XCTAssertTrue(window.isVisible)
            assertFrame(window.frame, equals: stableFrame)
            XCTAssertEqual(
                defaults.string(
                    forKey: MainWindowFramePersistence.autosaveDefaultsKey
                ),
                stableDescriptor
            )
        }
    }

    func testHiddenTerminationDoesNotOverwriteStableFrameForNextLaunch() {
        withDefaults { defaults in
            let stableFrame = testFrame(xOffset: 60, yOffset: 70)
            let hiddenSystemFrame = testFrame(xOffset: 200, yOffset: 130)
            let window = makeWindow(
                frame: testFrame(xOffset: 20, yOffset: 20)
            )
            defer { window.orderOut(nil) }
            seedStableFrame(stableFrame, defaults: defaults)
            MainWindowFramePersistence.configure(
                window: window,
                defaults: defaults
            ) {
                XCTFail("The stable frame should be restored")
            }

            window.orderOut(nil)
            window.setFrame(hiddenSystemFrame, display: false)
            MainWindowFramePersistence.persistIfVisible(
                window: window,
                defaults: defaults
            )

            let relaunchedWindow = makeWindow(
                frame: testFrame(xOffset: 5, yOffset: 5)
            )
            defer { relaunchedWindow.orderOut(nil) }
            MainWindowFramePersistence.configure(
                window: relaunchedWindow,
                defaults: defaults
            ) {
                XCTFail("The hidden system frame must not replace the stable frame")
            }

            assertFrame(relaunchedWindow.frame, equals: stableFrame)
        }
    }

    func testCoordinatorTerminationObserverPreservesHiddenStableFrame() {
        withStandardFrameDefaults { defaults in
            let stableFrame = testFrame(xOffset: 65, yOffset: 75)
            let hiddenSystemFrame = testFrame(xOffset: 205, yOffset: 135)
            let window = makeWindow(
                frame: testFrame(xOffset: 20, yOffset: 20)
            )
            window.identifier = CodexNotesWindowIdentifier.main
            let coordinator = WindowConfigurator.Coordinator()
            defer {
                coordinator.invalidate()
                window.orderOut(nil)
            }
            seedStableFrame(stableFrame, defaults: defaults)
            MainWindowFramePersistence.configure(window: window) {
                XCTFail("The stable frame should be restored")
            }
            coordinator.attach(to: window, languageRevision: "test")

            window.orderOut(nil)
            window.setFrame(hiddenSystemFrame, display: false)
            NotificationCenter.default.post(
                name: NSApplication.willTerminateNotification,
                object: NSApp
            )

            let relaunchedWindow = makeWindow(
                frame: testFrame(xOffset: 5, yOffset: 5)
            )
            defer { relaunchedWindow.orderOut(nil) }
            MainWindowFramePersistence.configure(window: relaunchedWindow) {
                XCTFail("Termination must retain the last visible frame")
            }

            assertFrame(relaunchedWindow.frame, equals: stableFrame)
        }
    }

    func testTwoConsecutiveHideAndShowCyclesKeepTheStableFrame() {
        withDefaults { defaults in
            let stableFrame = testFrame(xOffset: 55, yOffset: 65)
            let programmaticFrames = [
                testFrame(xOffset: 175, yOffset: 105),
                testFrame(xOffset: 215, yOffset: 135),
            ]
            let window = makeWindow(
                frame: testFrame(xOffset: 15, yOffset: 15)
            )
            defer { window.orderOut(nil) }
            seedStableFrame(stableFrame, defaults: defaults)
            MainWindowFramePersistence.configure(
                window: window,
                defaults: defaults
            ) {
                XCTFail("The stable frame should be restored")
            }
            let stableDescriptor = defaults.string(
                forKey: MainWindowFramePersistence.autosaveDefaultsKey
            )

            for programmaticFrame in programmaticFrames {
                window.orderOut(nil)
                window.setFrame(programmaticFrame, display: false)
                MainWindowFramePersistence.persistIfVisible(
                    window: window,
                    defaults: defaults
                )

                MainWindowFramePersistence.showPreservingFrame(
                    window: window,
                    defaults: defaults
                )

                XCTAssertTrue(window.isVisible)
                assertFrame(window.frame, equals: stableFrame)
                XCTAssertEqual(
                    defaults.string(
                        forKey: MainWindowFramePersistence.autosaveDefaultsKey
                    ),
                    stableDescriptor
                )
            }
        }
    }

    func testVisibleMovePersistsAndIsRestoredByTheNextWindow() {
        withDefaults { defaults in
            let stableFrame = testFrame(xOffset: 45, yOffset: 55)
            let userFrame = testFrame(
                xOffset: 145,
                yOffset: 95,
                width: 460,
                height: 560
            )
            let window = makeWindow(
                frame: testFrame(xOffset: 10, yOffset: 10)
            )
            defer { window.orderOut(nil) }
            seedStableFrame(stableFrame, defaults: defaults)
            MainWindowFramePersistence.configure(
                window: window,
                defaults: defaults
            ) {
                XCTFail("The stable frame should be restored")
            }
            MainWindowFramePersistence.showPreservingFrame(
                window: window,
                defaults: defaults
            )
            XCTAssertTrue(window.isVisible)

            window.setFrame(userFrame, display: false)
            MainWindowFramePersistence.persistIfVisible(
                window: window,
                defaults: defaults
            )

            let restoredWindow = makeWindow(
                frame: testFrame(xOffset: 5, yOffset: 5)
            )
            defer { restoredWindow.orderOut(nil) }
            MainWindowFramePersistence.configure(
                window: restoredWindow,
                defaults: defaults
            ) {
                XCTFail("The user's visible move should have been persisted")
            }

            assertFrame(restoredWindow.frame, equals: userFrame)
            XCTAssertEqual(restoredWindow.frameAutosaveName, "")
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "MainWindowFramePersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }

    private func withStandardFrameDefaults(_ body: (UserDefaults) -> Void) {
        let defaults = UserDefaults.standard
        let keys = [
            MainWindowFramePersistence.autosaveDefaultsKey,
            legacyFrameKey(modifiedContent: false),
            legacyFrameKey(modifiedContent: true),
            "NSWindow Frame MissingCurrentSwiftUIFrame",
        ]
        let originalValues = Dictionary(
            uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) }
        )
        keys.forEach(defaults.removeObject(forKey:))
        defer {
            for key in keys {
                if let value = originalValues[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        body(defaults)
    }

    private func makeWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        return window
    }

    private func seedStableFrame(
        _ frame: NSRect,
        defaults: UserDefaults
    ) {
        let window = makeWindow(frame: frame)
        defer { window.orderOut(nil) }
        window.setFrame(frame, display: false)
        MainWindowFramePersistence.persist(
            window: window,
            defaults: defaults
        )
    }

    private func descriptor(for frame: NSRect) -> String {
        let window = makeWindow(frame: frame)
        defer { window.orderOut(nil) }
        window.setFrame(frame, display: false)
        return window.frameDescriptor
    }

    private func testFrame(
        xOffset: CGFloat,
        yOffset: CGFloat,
        width: CGFloat = 420,
        height: CGFloat = 520
    ) -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let fittedWidth = min(width, visibleFrame.width - 40)
        let fittedHeight = min(height, visibleFrame.height - 40)
        let maximumXOffset = max(20, visibleFrame.width - fittedWidth - 20)
        let maximumYOffset = max(20, visibleFrame.height - fittedHeight - 20)
        return NSRect(
            x: visibleFrame.minX + min(xOffset, maximumXOffset),
            y: visibleFrame.minY + min(yOffset, maximumYOffset),
            width: fittedWidth,
            height: fittedHeight
        )
    }

    private func frameString(
        x: Int,
        y: Int,
        width: Int,
        height: Int
    ) -> String {
        "\(x) \(y) \(width) \(height) 0 0 2560 1409 "
    }

    private func assertFrame(
        _ actual: NSRect,
        equals expected: NSRect,
        accuracy: CGFloat = 1
    ) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: accuracy)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: accuracy)
        XCTAssertEqual(actual.size.width, expected.size.width, accuracy: accuracy)
        XCTAssertEqual(actual.size.height, expected.size.height, accuracy: accuracy)
    }

    private func legacyFrameKey(modifiedContent: Bool) -> String {
        if modifiedContent {
            return "NSWindow Frame SwiftUI.WindowGroup<SwiftUI.ModifiedContent<" +
                "CodexNotesProbe.ContentView, SwiftUI._AppearanceActionModifier>>" +
                "-1-AppWindow-1"
        }
        return "NSWindow Frame SwiftUI.WindowGroup<CodexNotesProbe.ContentView>" +
            "-1-AppWindow-1"
    }
}
