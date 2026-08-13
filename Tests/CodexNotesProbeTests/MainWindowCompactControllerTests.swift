import AppKit
import CodexNotesCore
import SwiftUI
import XCTest
@testable import CodexNotesProbe

@MainActor
final class MainWindowContentSizingPolicyTests: XCTestCase {
    func testIdealHeightStaysExpandedWhilePresentationBecomesCompact() {
        let expandedHost = makeSizingHost(
            isCollapsed: false,
            isCompactPresentationActive: false
        )
        let compactHost = makeSizingHost(
            isCollapsed: true,
            isCompactPresentationActive: true
        )

        XCTAssertEqual(MainWindowContentSizingPolicy.idealHeight, 660)
        XCTAssertEqual(
            expandedHost.fittingSize.height,
            MainWindowContentSizingPolicy.idealHeight,
            accuracy: 0.01
        )
        XCTAssertEqual(
            compactHost.fittingSize.height,
            MainWindowContentSizingPolicy.idealHeight,
            accuracy: 0.01
        )
    }

    func testCompactPresentationNeverRequestsFixedContentHeight() {
        XCTAssertNil(
            MainWindowContentSizingPolicy.fixedHeight(
                isCompactPresentationActive: false
            )
        )
        XCTAssertNil(
            MainWindowContentSizingPolicy.fixedHeight(
                isCompactPresentationActive: true
            )
        )
    }

    func testOnlyMinimumHeightRelaxesDuringCollapse() {
        XCTAssertEqual(
            MainWindowContentSizingPolicy.minimumHeight(isCollapsed: false),
            MainWindowCompactController.minimumExpandedContentSize.height
        )
        XCTAssertEqual(
            MainWindowContentSizingPolicy.minimumHeight(isCollapsed: true),
            MainWindowCompactController.compactContentHeight
        )
    }

    func testMinimumWidthTracksCompactPillAndExpandedWindow() {
        XCTAssertEqual(
            MainWindowContentSizingPolicy.minimumWidth(isCollapsed: false),
            MainWindowCompactController.minimumExpandedContentSize.width
        )
        XCTAssertEqual(
            MainWindowContentSizingPolicy.minimumWidth(isCollapsed: true),
            MainWindowCompactController.compactWindowWidth
        )
    }

    private func makeSizingHost(
        isCollapsed: Bool,
        isCompactPresentationActive: Bool
    ) -> NSHostingView<MainWindowContentSizingHarness> {
        let host = NSHostingView(
            rootView: MainWindowContentSizingHarness(
                isCollapsed: isCollapsed,
                isCompactPresentationActive: isCompactPresentationActive
            )
        )
        host.layoutSubtreeIfNeeded()
        return host
    }
}

private struct MainWindowContentSizingHarness: View {
    let isCollapsed: Bool
    let isCompactPresentationActive: Bool

    var body: some View {
        Color.clear
            .frame(
                minWidth: MainWindowContentSizingPolicy.minimumWidth(
                    isCollapsed: isCollapsed
                ),
                idealWidth: 400,
                minHeight: MainWindowContentSizingPolicy.minimumHeight(
                    isCollapsed: isCollapsed
                ),
                idealHeight: MainWindowContentSizingPolicy.idealHeight
            )
            .frame(
                height: MainWindowContentSizingPolicy.fixedHeight(
                    isCompactPresentationActive:
                        isCompactPresentationActive
                ),
                alignment: .top
            )
    }
}

final class MainWindowCompactGeometryTests: XCTestCase {
    func testCompactFrameUsesRequestedWidthAndPreservesTopRightEdges() {
        let expanded = NSRect(x: 120, y: 180, width: 440, height: 660)

        let compact = MainWindowCompactGeometry.compactFrame(
            from: expanded,
            compactWidth: 190,
            compactHeight: 31
        )

        XCTAssertEqual(compact.width, 190)
        XCTAssertEqual(compact.maxX, expanded.maxX)
        XCTAssertEqual(compact.maxY, expanded.maxY)
        XCTAssertEqual(compact.height, 31)
    }

    func testExpansionFollowsMovedCompactBarAndRestoresCachedSize() {
        let cached = NSRect(x: 120, y: 180, width: 440, height: 660)
        let movedCompact = NSRect(x: 720, y: 830, width: 190, height: 31)

        let expanded = MainWindowCompactGeometry.expandedFrame(
            from: movedCompact,
            cachedExpandedFrame: cached
        )

        XCTAssertEqual(expanded.maxX, movedCompact.maxX)
        XCTAssertEqual(expanded.maxY, movedCompact.maxY)
        XCTAssertEqual(expanded.size, cached.size)
    }

    func testExpansionIsKeptInsideVisibleFrameAfterCompactBarMovesLow() {
        let cached = NSRect(x: 120, y: 180, width: 440, height: 660)
        let movedCompact = NSRect(x: 950, y: 25, width: 190, height: 31)
        let visible = NSRect(x: 0, y: 24, width: 1_200, height: 776)

        let expanded = MainWindowCompactGeometry.expandedFrame(
            from: movedCompact,
            cachedExpandedFrame: cached,
            constrainedTo: visible
        )

        XCTAssertEqual(expanded.minY, visible.minY)
        XCTAssertTrue(visible.contains(expanded))
        XCTAssertEqual(expanded.size, cached.size)
    }
}

@MainActor
final class MainWindowCompactControllerTests: XCTestCase {
    func testCompactPillUsesDeliberatelySmallFixedWidth() {
        XCTAssertEqual(MainWindowCompactController.compactWindowWidth, 190)
        XCTAssertLessThan(
            MainWindowCompactController.compactWindowWidth,
            MainWindowCompactController.minimumExpandedContentSize.width
        )
    }

    func testCompactAppearanceUsesReadableTranslucencyLevels() {
        XCTAssertEqual(
            MainWindowCompactController.restingWindowOpacity,
            0.42,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MainWindowCompactController.activeWindowOpacity,
            0.68,
            accuracy: 0.001
        )
        XCTAssertLessThan(
            MainWindowCompactController.restingWindowOpacity,
            MainWindowCompactController.activeWindowOpacity
        )
        XCTAssertLessThan(
            MainWindowCompactController.activeWindowOpacity,
            1
        )
        XCTAssertEqual(
            MainWindowCompactController.compactWindowOpacity(
                isActive: false,
                reduceTransparency: false
            ),
            MainWindowCompactController.restingWindowOpacity
        )
        XCTAssertEqual(
            MainWindowCompactController.compactWindowOpacity(
                isActive: true,
                reduceTransparency: false
            ),
            MainWindowCompactController.activeWindowOpacity
        )
        XCTAssertEqual(
            MainWindowCompactController.compactWindowOpacity(
                isActive: false,
                reduceTransparency: true
            ),
            1
        )
    }

    func testCompactAppearanceClearsContentSliverAndRestoresWindowChrome() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            window.alphaValue = 0.75
            window.titlebarSeparatorStyle = .line
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }

            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            controller.toggleFromTitlebar()

            XCTAssertEqual(
                window.alphaValue,
                0.75 * MainWindowCompactController.restingWindowOpacity,
                accuracy: 0.001
            )
            XCTAssertEqual(window.backgroundColor.alphaComponent, 0, accuracy: 0.001)
            XCTAssertEqual(window.titlebarSeparatorStyle, .none)

            controller.updateConfiguration(
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: true
            )
            XCTAssertEqual(window.alphaValue, 0.75, accuracy: 0.001)
            XCTAssertEqual(window.backgroundColor.alphaComponent, 0, accuracy: 0.001)

            controller.toggleFromTitlebar()

            XCTAssertEqual(window.alphaValue, 0.75, accuracy: 0.001)
            XCTAssertEqual(window.backgroundColor.alphaComponent, 1, accuracy: 0.001)
            XCTAssertEqual(window.titlebarSeparatorStyle, .line)
        }
    }

    func testFullSizeContentWindowCollapseKeepsTopEdgeAfterAppKitLayout() async throws {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            throw XCTSkip("AppKit window integration requires a visible screen")
        }
        guard visibleFrame.width >= 380, visibleFrame.height >= 560 else {
            throw XCTSkip("Visible screen is too small for the expanded-window contract")
        }
        await preservingStableFrameDefaultsAsync {
            let windowSize = NSSize(
                width: min(420, visibleFrame.width - 40),
                height: min(590, visibleFrame.height - 40)
            )
            let window = NSWindow(
                contentRect: NSRect(
                    x: visibleFrame.midX - windowSize.width / 2,
                    y: visibleFrame.midY - windowSize.height / 2,
                    width: windowSize.width,
                    height: windowSize.height
                ),
                styleMask: [
                    .titled,
                    .closable,
                    .resizable,
                    .fullSizeContentView,
                ],
                backing: .buffered,
                defer: false
            )
            window.identifier = CodexNotesWindowIdentifier.main
            window.alphaValue = 0
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }

            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.contentView?.layoutSubtreeIfNeeded()
            let expandedFrame = window.frame
            let titlebarHeight = max(
                0,
                expandedFrame.height - window.contentLayoutRect.height
            )
            let expectedCompactHeight = ceil(
                titlebarHeight + MainWindowCompactController.compactContentHeight
            )
            XCTAssertGreaterThan(titlebarHeight, 0)
            XCTAssertGreaterThan(
                expectedCompactHeight,
                MainWindowCompactController.compactContentHeight
            )

            controller.toggleFromTitlebar()

            XCTAssertTrue(controller.isCollapsed)
            XCTAssertEqual(
                window.frame.width,
                MainWindowCompactController.compactWindowWidth,
                accuracy: 0.01
            )
            XCTAssertEqual(window.frame.maxX, expandedFrame.maxX, accuracy: 0.01)
            XCTAssertEqual(window.frame.height, expectedCompactHeight, accuracy: 0.01)
            XCTAssertEqual(window.frame.maxY, expandedFrame.maxY, accuracy: 0.01)

            for _ in 0..<3 {
                await Task.yield()
            }
            try? await Task.sleep(for: .milliseconds(100))

            XCTAssertEqual(
                window.frame.width,
                MainWindowCompactController.compactWindowWidth,
                accuracy: 0.01
            )
            XCTAssertEqual(window.frame.maxX, expandedFrame.maxX, accuracy: 0.01)
            XCTAssertEqual(window.frame.height, expectedCompactHeight, accuracy: 0.01)
            XCTAssertEqual(window.frame.maxY, expandedFrame.maxY, accuracy: 0.01)

            controller.toggleFromTitlebar()

            XCTAssertFalse(controller.isCollapsed)
            XCTAssertEqual(window.frame, expandedFrame)
            XCTAssertEqual(
                window.contentMinSize,
                MainWindowCompactController.minimumExpandedContentSize
            )
        }
    }

    func testTitlebarToggleCollapsesAndExpandsWithoutChangingStableFrame() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            let initialFrame = window.frame
            let originalAccessoryCount = window.titlebarAccessoryViewControllers.count
            defer {
                controller.detach()
                window.orderOut(nil)
            }

            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )

            XCTAssertEqual(
                window.titlebarAccessoryViewControllers.count,
                originalAccessoryCount + 1
            )

            controller.toggleFromTitlebar()

            XCTAssertTrue(controller.isCollapsed)
            XCTAssertEqual(window.frame.maxX, initialFrame.maxX, accuracy: 0.01)
            XCTAssertEqual(
                window.frame.width,
                MainWindowCompactController.compactWindowWidth,
                accuracy: 0.01
            )
            XCTAssertEqual(window.frame.maxY, initialFrame.maxY, accuracy: 0.01)
            XCTAssertLessThan(window.frame.height, 50)
            XCTAssertEqual(
                window.contentRect(forFrameRect: window.frame).height,
                MainWindowCompactController.compactContentHeight,
                accuracy: 0.01
            )
            XCTAssertLessThanOrEqual(
                window.contentMinSize.width,
                MainWindowCompactController.compactWindowWidth
            )
            XCTAssertFalse(window.styleMask.contains(.resizable))
            XCTAssertEqual(
                UserDefaults.standard.string(
                    forKey: MainWindowFramePersistence.autosaveDefaultsKey
                ),
                initialFrameDescriptor(for: initialFrame, using: window)
            )

            controller.toggleFromTitlebar()

            XCTAssertFalse(controller.isCollapsed)
            XCTAssertEqual(window.frame, initialFrame)
            XCTAssertTrue(window.styleMask.contains(.resizable))
            XCTAssertEqual(window.contentMinSize, NSSize(width: 340, height: 520))

            controller.detach()
            XCTAssertEqual(
                window.titlebarAccessoryViewControllers.count,
                originalAccessoryCount
            )
        }
    }

    func testCompactPillShowsOnlyTitleAndExpandAccessoryThenRestoresCloseButton() throws {
        try preservingStableFrameDefaultsThrowing {
            let window = makeWindow()
            window.title = "CodexNotes"
            window.titleVisibility = .visible
            MainWindowChromePolicy.apply(
                to: window,
                localization: AppLocalization(preference: .english)
            )
            let closeButton = try XCTUnwrap(
                window.standardWindowButton(.closeButton)
            )
            let miniaturizeButton = try XCTUnwrap(
                window.standardWindowButton(.miniaturizeButton)
            )
            let zoomButton = try XCTUnwrap(
                window.standardWindowButton(.zoomButton)
            )
            let originalAccessoryCount =
                window.titlebarAccessoryViewControllers.count
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }

            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            let compactAccessory = try XCTUnwrap(
                window.titlebarAccessoryViewControllers.last
            )
            let accessoryButtons = compactAccessory.view.subviews.compactMap {
                $0 as? NSButton
            }
            let accessoryButton = try XCTUnwrap(accessoryButtons.first)

            XCTAssertEqual(
                window.titlebarAccessoryViewControllers.count,
                originalAccessoryCount + 1
            )
            XCTAssertEqual(accessoryButtons.count, 1)
            XCTAssertFalse(closeButton.isHidden)
            XCTAssertTrue(miniaturizeButton.isHidden)
            XCTAssertTrue(zoomButton.isHidden)
            XCTAssertEqual(
                accessoryButton.accessibilityLabel(),
                L10n.text(.mainWindowCollapseAccessibilityLabel)
            )

            controller.toggleFromTitlebar()

            XCTAssertTrue(controller.isCollapsed)
            XCTAssertTrue(closeButton.isHidden)
            XCTAssertTrue(miniaturizeButton.isHidden)
            XCTAssertTrue(zoomButton.isHidden)
            XCTAssertEqual(window.title, "CodexNotes")
            XCTAssertEqual(window.titleVisibility, .visible)
            XCTAssertFalse(compactAccessory.view.isHidden)
            XCTAssertFalse(accessoryButton.isHidden)
            XCTAssertTrue(accessoryButton.isEnabled)
            XCTAssertNotNil(accessoryButton.image)
            XCTAssertEqual(
                accessoryButton.accessibilityLabel(),
                L10n.text(.mainWindowExpandAccessibilityLabel)
            )
            XCTAssertEqual(accessoryButtons.count, 1)

            controller.toggleFromTitlebar()

            XCTAssertFalse(controller.isCollapsed)
            XCTAssertFalse(closeButton.isHidden)
            XCTAssertTrue(closeButton.isEnabled)
            XCTAssertEqual(
                accessoryButton.accessibilityLabel(),
                L10n.text(.mainWindowCollapseAccessibilityLabel)
            )

            controller.toggleFromTitlebar()
            XCTAssertTrue(closeButton.isHidden)
            controller.detach()
            XCTAssertFalse(closeButton.isHidden)
        }
    }

    func testCollapseTransitionIsAtomicAndAppliesCompactAppearance() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            let backgroundColor = NSColor(
                calibratedRed: 0.18,
                green: 0.24,
                blue: 0.31,
                alpha: 1
            )
            defer {
                controller.detach()
                window.orderOut(nil)
            }

            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: backgroundColor,
                reduceMotion: false,
                reduceTransparency: false
            )
            window.orderFrontRegardless()

            assertOrdinaryTitlebarAppearance(window)
            controller.toggleFromTitlebar()

            assertCompactTitlebarAppearance(window)
            XCTAssertTrue(controller.isCompactContentPresentationActive)
            XCTAssertFalse(window.styleMask.contains(.resizable))
            XCTAssertLessThan(window.frame.height, 50)
        }
    }

    func testExpandTransitionIsAtomicAndRestoresOrdinaryAppearance() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }

            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            controller.toggleFromTitlebar()
            assertCompactTitlebarAppearance(window)
            XCTAssertTrue(controller.isCompactContentPresentationActive)

            controller.updateConfiguration(
                backgroundColor: .windowBackgroundColor,
                reduceMotion: false,
                reduceTransparency: false
            )
            controller.toggleFromTitlebar()

            assertOrdinaryTitlebarAppearance(window)
            XCTAssertFalse(controller.isCompactContentPresentationActive)
            XCTAssertTrue(window.styleMask.contains(.resizable))
            XCTAssertGreaterThan(window.frame.height, 500)
        }
    }

    func testCoordinatorDoesNotPersistTransientCompactResize() {
        preservingStableFrameDefaults {
            let availability = CompactTestCodexAvailabilityMonitor(
                isCodexAvailable: false
            )
            let coordinator = WindowConfigurator.Coordinator(
                codexAvailabilityMonitor: availability
            )
            let compactController = MainWindowCompactController()
            let editor = MarkdownEditorController()
            let window = makeWindow()
            defer {
                coordinator.detach()
                window.orderOut(nil)
            }

            coordinator.attach(
                to: window,
                languageRevision: "test",
                compactController: compactController,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            MainWindowFramePersistence.persist(window: window)
            let persistedExpandedDescriptor = window.frameDescriptor

            compactController.toggleFromTitlebar()
            NotificationCenter.default.post(
                name: NSWindow.didResizeNotification,
                object: window
            )
            NotificationCenter.default.post(
                name: NSApplication.willTerminateNotification,
                object: NSApp
            )

            XCTAssertTrue(compactController.isCollapsed)
            XCTAssertEqual(
                UserDefaults.standard.string(
                    forKey: MainWindowFramePersistence.autosaveDefaultsKey
                ),
                persistedExpandedDescriptor
            )
        }
    }

    func testCollapsedPresentationKeepsTransientFrame() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            controller.toggleFromTitlebar()
            let compactFrame = window.frame

            controller.presentPreservingTransientFrame { candidate in
                candidate.setFrame(
                    NSRect(x: 5, y: 5, width: 200, height: 200),
                    display: false
                )
            }

            XCTAssertEqual(window.frame, compactFrame)
            XCTAssertTrue(controller.isCollapsed)
        }
    }

    func testDetachRestoresExpandedGeometryAndRemovesAccessory() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            let initialFrame = window.frame
            let originalAccessoryCount = window.titlebarAccessoryViewControllers.count
            defer { window.orderOut(nil) }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            controller.toggleFromTitlebar()

            controller.detach()

            XCTAssertFalse(controller.isCollapsed)
            XCTAssertEqual(window.frame, initialFrame)
            XCTAssertTrue(window.styleMask.contains(.resizable))
            XCTAssertEqual(
                window.titlebarAccessoryViewControllers.count,
                originalAccessoryCount
            )
        }
    }

    func testContinuousOpenPanelStaysCollapsedAcrossTaskSwitch() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            controller.seedRightPanel(.closed)
            controller.observeRightPanel(.open)
            XCTAssertTrue(controller.isCollapsed)

            controller.selectionDidChange(seeding: .open)

            XCTAssertTrue(controller.isCollapsed)
        }
    }

    func testInitialOpenObservationCollapsesOnce() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()

            controller.observeRightPanel(.open)

            XCTAssertTrue(controller.isCollapsed)

            controller.toggleFromTitlebar()
            XCTAssertFalse(controller.isCollapsed)

            controller.observeRightPanel(.open)
            XCTAssertFalse(controller.isCollapsed)

            controller.observeRightPanel(.closed)
            controller.observeRightPanel(.open)
            XCTAssertTrue(controller.isCollapsed)
        }
    }

    func testDisablingAvoidanceRestoresAutomaticallyCollapsedWindow() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            let expandedFrame = window.frame
            controller.seedRightPanel(.closed)
            controller.observeRightPanel(.open)
            XCTAssertTrue(controller.isCollapsed)

            controller.setAutomaticAvoidanceEnabled(false)

            XCTAssertFalse(controller.isCollapsed)
            XCTAssertEqual(window.frame, expandedFrame)
            XCTAssertFalse(controller.isAutomaticAvoidanceEnabled)
        }
    }

    func testDisablingAvoidanceRestoresHiddenAutomaticCollapseWithoutShowingWindow() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            let expandedFrame = window.frame
            controller.seedRightPanel(.closed)
            controller.observeRightPanel(.open)
            XCTAssertTrue(controller.isCollapsed)
            window.orderOut(nil)

            controller.setAutomaticAvoidanceEnabled(false)

            XCTAssertFalse(controller.isCollapsed)
            XCTAssertEqual(window.frame, expandedFrame)
            XCTAssertFalse(window.isVisible)
        }
    }

    func testDisabledAvoidanceIgnoresPanelButKeepsManualToggleAvailable() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            controller.setAutomaticAvoidanceEnabled(false)

            controller.observeRightPanel(.open)
            XCTAssertFalse(controller.isCollapsed)

            controller.toggleFromTitlebar()
            XCTAssertTrue(controller.isCollapsed)
            controller.observeRightPanel(.closed)
            controller.observeRightPanel(.open)
            XCTAssertTrue(controller.isCollapsed)

            controller.toggleFromTitlebar()
            XCTAssertFalse(controller.isCollapsed)
        }
    }

    func testDisablingAvoidanceDoesNotUndoManualCollapse() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            controller.seedRightPanel(.closed)
            controller.observeRightPanel(.open)
            controller.toggleFromTitlebar()
            controller.toggleFromTitlebar()
            XCTAssertTrue(controller.isCollapsed)

            controller.setAutomaticAvoidanceEnabled(false)

            XCTAssertTrue(controller.isCollapsed)
        }
    }

    func testReenablingAvoidanceWaitsForAFreshOpenObservation() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            controller.setAutomaticAvoidanceEnabled(false)
            controller.observeRightPanel(.open)
            XCTAssertFalse(controller.isCollapsed)

            controller.setAutomaticAvoidanceEnabled(true)

            XCTAssertFalse(controller.isCollapsed)
            controller.observeRightPanel(.open)
            XCTAssertTrue(controller.isCollapsed)
        }
    }

    func testDisablingAvoidanceCancelsPendingAutomaticCollapse() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let scrollView = NSScrollView(
                frame: NSRect(x: 0, y: 0, width: 420, height: 590)
            )
            let textView = CheckboxTextView(frame: scrollView.contentView.bounds)
            scrollView.documentView = textView
            window.contentView = scrollView

            let controller = makeController()
            let editor = MarkdownEditorController()
            editor.attach(to: textView)
            textView.editorController = editor
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)
            textView.setMarkedText(
                "ni",
                selectedRange: NSRange(location: 2, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )

            controller.seedRightPanel(.closed)
            controller.observeRightPanel(.open)
            XCTAssertFalse(controller.isCollapsed)

            controller.setAutomaticAvoidanceEnabled(false)
            textView.unmarkText()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

            XCTAssertFalse(controller.isCollapsed)
        }
    }

    func testDisablingAvoidanceKeepsPendingManualCollapse() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let scrollView = NSScrollView(
                frame: NSRect(x: 0, y: 0, width: 420, height: 590)
            )
            let textView = CheckboxTextView(frame: scrollView.contentView.bounds)
            scrollView.documentView = textView
            window.contentView = scrollView

            let controller = makeController()
            let editor = MarkdownEditorController()
            editor.attach(to: textView)
            textView.editorController = editor
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)
            textView.setMarkedText(
                "ni",
                selectedRange: NSRange(location: 2, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )

            controller.toggleFromTitlebar()
            XCTAssertFalse(controller.isCollapsed)

            controller.setAutomaticAvoidanceEnabled(false)
            textView.unmarkText()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

            XCTAssertTrue(controller.isCollapsed)
        }
    }

    func testClosedPanelAfterTaskSwitchRestoresAutomaticCollapse() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            controller.seedRightPanel(.closed)
            controller.observeRightPanel(.open)
            XCTAssertTrue(controller.isCollapsed)

            controller.selectionDidChange(seeding: .closed)

            XCTAssertFalse(controller.isCollapsed)
            XCTAssertTrue(window.styleMask.contains(.resizable))
        }
    }

    func testUnknownPanelAfterTaskSwitchFailsOpen() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            controller.seedRightPanel(.closed)
            controller.observeRightPanel(.open)
            XCTAssertTrue(controller.isCollapsed)

            controller.selectionDidChange(seeding: .unknown)

            XCTAssertFalse(controller.isCollapsed)
        }
    }

    func testAutomaticCollapseWaitsForMarkedTextToEnd() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let scrollView = NSScrollView(
                frame: NSRect(x: 0, y: 0, width: 420, height: 590)
            )
            let textView = CheckboxTextView(
                frame: scrollView.contentView.bounds
            )
            scrollView.documentView = textView
            window.contentView = scrollView

            let controller = makeController()
            let editor = MarkdownEditorController()
            editor.attach(to: textView)
            textView.editorController = editor
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)
            textView.setMarkedText(
                "ni",
                selectedRange: NSRange(location: 2, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            XCTAssertTrue(textView.hasMarkedText())

            controller.seedRightPanel(.closed)
            controller.observeRightPanel(.open)

            XCTAssertFalse(controller.isCollapsed)
            window.makeFirstResponder(nil)
            NotificationCenter.default.post(
                name: NSWindow.didResignKeyNotification,
                object: window
            )
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            XCTAssertFalse(controller.isCollapsed)
            textView.unmarkText()
            XCTAssertTrue(controller.isCollapsed)
        }
    }

    func testPanelCloseAfterAtomicCollapseRestoresExpandedWindow() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: false,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            controller.seedRightPanel(.closed)

            controller.observeRightPanel(.open)
            controller.observeRightPanel(.closed)

            XCTAssertFalse(controller.isCollapsed)
            XCTAssertTrue(window.styleMask.contains(.resizable))
        }
    }

    func testPanelCloseRestoresExpandedPreOpenStateAfterManualRoundTrip() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            let expandedFrameBeforePanel = window.frame
            controller.seedRightPanel(.closed)

            controller.observeRightPanel(.open)
            XCTAssertTrue(controller.isCollapsed)
            controller.toggleFromTitlebar()
            XCTAssertFalse(controller.isCollapsed)
            controller.toggleFromTitlebar()
            XCTAssertTrue(controller.isCollapsed)

            controller.observeRightPanel(.closed)

            XCTAssertFalse(controller.isCollapsed)
            XCTAssertEqual(window.frame, expandedFrameBeforePanel)
        }
    }

    func testPanelCloseKeepsPreExistingCompactStateAfterManualRoundTrip() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            controller.seedRightPanel(.closed)
            controller.toggleFromTitlebar()
            XCTAssertTrue(controller.isCollapsed)

            controller.observeRightPanel(.open)
            controller.toggleFromTitlebar()
            XCTAssertFalse(controller.isCollapsed)
            controller.toggleFromTitlebar()
            XCTAssertTrue(controller.isCollapsed)

            controller.observeRightPanel(.closed)

            XCTAssertTrue(controller.isCollapsed)
        }
    }

    func testPanelCloseCancelsDelayedManualCollapseWhenPreOpenStateWasExpanded() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let scrollView = NSScrollView(
                frame: NSRect(x: 0, y: 0, width: 420, height: 590)
            )
            let textView = CheckboxTextView(frame: scrollView.contentView.bounds)
            scrollView.documentView = textView
            window.contentView = scrollView

            let controller = makeController()
            let editor = MarkdownEditorController()
            editor.attach(to: textView)
            textView.editorController = editor
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            controller.seedRightPanel(.closed)
            controller.observeRightPanel(.open)
            XCTAssertTrue(controller.isCollapsed)
            controller.toggleFromTitlebar()
            XCTAssertFalse(controller.isCollapsed)

            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)
            textView.setMarkedText(
                "ni",
                selectedRange: NSRange(location: 2, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            controller.toggleFromTitlebar()
            XCTAssertFalse(controller.isCollapsed)

            controller.observeRightPanel(.closed)
            textView.unmarkText()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

            XCTAssertFalse(controller.isCollapsed)
        }
    }

    func testPanelCloseRestoresHiddenAutomaticCollapseWithoutShowingWindow() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            let expandedFrameBeforePanel = window.frame
            controller.seedRightPanel(.closed)
            controller.observeRightPanel(.open)
            XCTAssertTrue(controller.isCollapsed)
            window.orderOut(nil)
            XCTAssertFalse(window.isVisible)

            controller.observeRightPanel(.closed)

            XCTAssertFalse(controller.isCollapsed)
            XCTAssertEqual(window.frame, expandedFrameBeforePanel)
            XCTAssertFalse(window.isVisible)
        }
    }

    func testAutomaticPanelCloseRestoresExactFrameAfterCompactBarDrifts() {
        let suiteName = "CodexNotesTests.AutomaticFrameRestore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let window = makeWindow()
        let controller = MainWindowCompactController(
            framePersistenceDefaults: defaults
        )
        controller.setAutomaticAvoidanceEnabled(true)
        let editor = MarkdownEditorController()
        defer {
            controller.detach()
            window.orderOut(nil)
        }

        controller.attach(
            to: window,
            editorController: editor,
            backgroundColor: .windowBackgroundColor,
            reduceMotion: true,
            reduceTransparency: false
        )
        window.orderFrontRegardless()
        let initialFrame = window.frame
        let initialDescriptor = initialFrameDescriptor(
            for: initialFrame,
            using: window
        )
        controller.seedRightPanel(.closed)
        controller.observeRightPanel(.open)
        XCTAssertTrue(controller.isCollapsed)
        XCTAssertEqual(
            defaults.string(
                forKey: MainWindowFramePersistence.autosaveDefaultsKey
            ),
            initialDescriptor
        )

        let compactFrame = window.frame
        window.setFrameOrigin(
            NSPoint(
                x: compactFrame.minX + 120,
                y: compactFrame.minY + 80
            )
        )
        XCTAssertNotEqual(window.frame.origin, compactFrame.origin)

        controller.observeRightPanel(.closed)

        XCTAssertFalse(controller.isCollapsed)
        XCTAssertEqual(window.frame, initialFrame)
        XCTAssertEqual(
            defaults.string(
                forKey: MainWindowFramePersistence.autosaveDefaultsKey
            ),
            initialDescriptor
        )
    }

    func testManualExpandStillFollowsMovedCompactBar() throws {
        let suiteName = "CodexNotesTests.ManualFrameRestore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let window = makeWindow()
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            throw XCTSkip("AppKit window integration requires a visible screen")
        }
        guard visibleFrame.width >= window.frame.width + 4,
              visibleFrame.height >= window.frame.height + 4
        else {
            throw XCTSkip("Visible screen cannot contain the expanded test window")
        }
        window.setFrame(
            NSRect(
                x: visibleFrame.midX - window.frame.width / 2,
                y: visibleFrame.midY - window.frame.height / 2,
                width: window.frame.width,
                height: window.frame.height
            ),
            display: false
        )
        let controller = MainWindowCompactController(
            framePersistenceDefaults: defaults
        )
        let editor = MarkdownEditorController()
        defer {
            controller.detach()
            window.orderOut(nil)
        }

        controller.attach(
            to: window,
            editorController: editor,
            backgroundColor: .windowBackgroundColor,
            reduceMotion: true,
            reduceTransparency: false
        )
        window.orderFrontRegardless()
        let initialFrame = window.frame
        controller.toggleFromTitlebar()
        XCTAssertTrue(controller.isCollapsed)

        let compactFrame = window.frame
        let dx = min(120, max(0, visibleFrame.maxX - compactFrame.maxX - 1))
        let dy = min(80, max(0, visibleFrame.maxY - compactFrame.maxY - 1))
        XCTAssertGreaterThan(dx, 0)
        XCTAssertGreaterThan(dy, 0)
        let movedCompactFrame = compactFrame.offsetBy(dx: dx, dy: dy)
        window.setFrame(movedCompactFrame, display: false)

        controller.toggleFromTitlebar()

        XCTAssertFalse(controller.isCollapsed)
        XCTAssertEqual(window.frame.maxX, movedCompactFrame.maxX, accuracy: 0.01)
        XCTAssertEqual(window.frame.maxY, movedCompactFrame.maxY, accuracy: 0.01)
        XCTAssertEqual(window.frame.size, initialFrame.size)
    }

    func testTaskSwitchFailOpenRestoresExactFrameAfterCompactBarDrifts() {
        let suiteName = "CodexNotesTests.TaskSwitchFrameRestore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let window = makeWindow()
        let controller = MainWindowCompactController(
            framePersistenceDefaults: defaults
        )
        controller.setAutomaticAvoidanceEnabled(true)
        let editor = MarkdownEditorController()
        defer {
            controller.detach()
            window.orderOut(nil)
        }

        controller.attach(
            to: window,
            editorController: editor,
            backgroundColor: .windowBackgroundColor,
            reduceMotion: true,
            reduceTransparency: false
        )
        window.orderFrontRegardless()
        let initialFrame = window.frame
        let initialDescriptor = initialFrameDescriptor(
            for: initialFrame,
            using: window
        )
        controller.seedRightPanel(.closed)
        controller.observeRightPanel(.open)
        XCTAssertTrue(controller.isCollapsed)

        let compactFrame = window.frame
        window.setFrame(
            compactFrame.offsetBy(dx: 120, dy: 80),
            display: false
        )
        controller.selectionDidChange(seeding: .closed)

        XCTAssertFalse(controller.isCollapsed)
        XCTAssertEqual(window.frame, initialFrame)
        XCTAssertEqual(
            defaults.string(
                forKey: MainWindowFramePersistence.autosaveDefaultsKey
            ),
            initialDescriptor
        )
    }

    func testPanelOpenAfterAtomicExpandEndsCollapsed() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: false,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            controller.seedRightPanel(.closed)
            controller.observeRightPanel(.open)
            XCTAssertTrue(controller.isCollapsed)

            controller.observeRightPanel(.closed)
            controller.observeRightPanel(.open)

            XCTAssertTrue(controller.isCollapsed)
            XCTAssertFalse(window.styleMask.contains(.resizable))
        }
    }

    func testDefaultSizeRestoreAfterAtomicCollapseKeepsStableFrame() {
        let suiteName = "CodexNotesTests.CompactRestore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        do {
            let window = makeWindow()
            let controller = MainWindowCompactController(
                framePersistenceDefaults: defaults
            )
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: false,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            MainWindowFramePersistence.persist(
                window: window,
                defaults: defaults
            )

            controller.toggleFromTitlebar()
            controller.prepareForDefaultSizeRestore()
            XCTAssertTrue(
                MainWindowFramePersistence.restoreDefaultSize(
                    window: window,
                    defaults: defaults
                )
            )
            let restoredFrame = window.frame
            let restoredDescriptor = window.frameDescriptor

            XCTAssertFalse(controller.isCollapsed)
            XCTAssertTrue(window.styleMask.contains(.resizable))
            XCTAssertEqual(window.frame, restoredFrame)
            XCTAssertGreaterThan(window.frame.height, 500)
            XCTAssertEqual(
                defaults.string(
                    forKey: MainWindowFramePersistence.autosaveDefaultsKey
                ),
                restoredDescriptor
            )
        }
    }

    func testDetachAfterAtomicCollapseRestoresExpandedFrame() {
        preservingStableFrameDefaults {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer { window.orderOut(nil) }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: false,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            let initialFrame = window.frame
            let initialDescriptor = initialFrameDescriptor(
                for: initialFrame,
                using: window
            )

            controller.toggleFromTitlebar()
            controller.detach()

            XCTAssertFalse(controller.isCollapsed)
            XCTAssertTrue(window.styleMask.contains(.resizable))
            XCTAssertEqual(window.frame, initialFrame)
            XCTAssertEqual(
                UserDefaults.standard.string(
                    forKey: MainWindowFramePersistence.autosaveDefaultsKey
                ),
                initialDescriptor
            )
        }
    }

    func testSustainedUnknownExpandsAutomaticallyCollapsedWindow() async {
        let suiteName = "CodexNotesTests.UnknownFrameRestore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let window = makeWindow()
        let controller = MainWindowCompactController(
            framePersistenceDefaults: defaults
        )
        controller.setAutomaticAvoidanceEnabled(true)
        let editor = MarkdownEditorController()
        defer {
            controller.detach()
            window.orderOut(nil)
        }
        controller.attach(
            to: window,
            editorController: editor,
            backgroundColor: .windowBackgroundColor,
            reduceMotion: true,
            reduceTransparency: false
        )
        window.orderFrontRegardless()
        let initialFrame = window.frame
        let initialDescriptor = initialFrameDescriptor(
            for: initialFrame,
            using: window
        )
        controller.seedRightPanel(.closed)
        controller.observeRightPanel(.open)
        XCTAssertTrue(controller.isCollapsed)

        let compactFrame = window.frame
        window.setFrame(
            compactFrame.offsetBy(dx: 120, dy: 80),
            display: false
        )

        controller.observeRightPanel(.unknown)
        try? await Task.sleep(for: .milliseconds(1_100))

        XCTAssertFalse(controller.isCollapsed)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.frame, initialFrame)
        XCTAssertEqual(
            defaults.string(
                forKey: MainWindowFramePersistence.autosaveDefaultsKey
            ),
            initialDescriptor
        )

        controller.observeRightPanel(.open)
        XCTAssertFalse(controller.isCollapsed)

        controller.observeRightPanel(.closed)
        controller.observeRightPanel(.open)
        XCTAssertTrue(controller.isCollapsed)
    }

    func testKnownOpenRecoveryCancelsUnknownFailOpen() async {
        await preservingStableFrameDefaultsAsync {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            controller.seedRightPanel(.closed)
            controller.observeRightPanel(.open)
            XCTAssertTrue(controller.isCollapsed)

            controller.observeRightPanel(.unknown)
            try? await Task.sleep(for: .milliseconds(100))
            controller.observeRightPanel(.open)
            try? await Task.sleep(for: .milliseconds(1_050))

            XCTAssertTrue(controller.isCollapsed)
            XCTAssertFalse(window.styleMask.contains(.resizable))
        }
    }

    func testSustainedUnknownDoesNotExpandManuallyCollapsedWindow() async {
        await preservingStableFrameDefaultsAsync {
            let window = makeWindow()
            let controller = makeController()
            let editor = MarkdownEditorController()
            defer {
                controller.detach()
                window.orderOut(nil)
            }
            controller.attach(
                to: window,
                editorController: editor,
                backgroundColor: .windowBackgroundColor,
                reduceMotion: true,
                reduceTransparency: false
            )
            window.orderFrontRegardless()
            controller.seedRightPanel(.open)
            controller.toggleFromTitlebar()
            XCTAssertTrue(controller.isCollapsed)

            controller.observeRightPanel(.unknown)
            try? await Task.sleep(for: .milliseconds(1_100))

            XCTAssertTrue(controller.isCollapsed)
            XCTAssertFalse(window.styleMask.contains(.resizable))
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 420, height: 590),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = CodexNotesWindowIdentifier.main
        window.alphaValue = 0
        return window
    }

    private func makeController() -> MainWindowCompactController {
        let controller = MainWindowCompactController()
        controller.setAutomaticAvoidanceEnabled(true)
        return controller
    }

    private func preservingStableFrameDefaults(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let key = MainWindowFramePersistence.autosaveDefaultsKey
        let originalValue = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        body()
    }

    private func preservingStableFrameDefaultsThrowing(
        _ body: () throws -> Void
    ) rethrows {
        let defaults = UserDefaults.standard
        let key = MainWindowFramePersistence.autosaveDefaultsKey
        let originalValue = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        try body()
    }

    private func preservingStableFrameDefaultsAsync(
        _ body: () async -> Void
    ) async {
        let defaults = UserDefaults.standard
        let key = MainWindowFramePersistence.autosaveDefaultsKey
        let originalValue = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        await body()
    }

    private func initialFrameDescriptor(
        for frame: NSRect,
        using window: NSWindow
    ) -> String {
        let currentFrame = window.frame
        window.setFrame(frame, display: false)
        let descriptor = window.frameDescriptor
        window.setFrame(currentFrame, display: false)
        return descriptor
    }

    private func assertOrdinaryTitlebarAppearance(
        _ window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(window.isOpaque, file: file, line: line)
        XCTAssertFalse(
            window.titlebarAppearsTransparent,
            file: file,
            line: line
        )
        XCTAssertEqual(
            window.backgroundColor.alphaComponent,
            1,
            accuracy: 0.001,
            file: file,
            line: line
        )
    }

    private func assertCompactTitlebarAppearance(
        _ window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(window.isOpaque, file: file, line: line)
        XCTAssertTrue(
            window.titlebarAppearsTransparent,
            file: file,
            line: line
        )
        XCTAssertEqual(
            window.backgroundColor.alphaComponent,
            0,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            window.titlebarSeparatorStyle,
            .none,
            file: file,
            line: line
        )
    }
}

@MainActor
private final class CompactTestCodexAvailabilityMonitor:
    CodexApplicationAvailabilityObserving
{
    let isCodexAvailable: Bool

    init(isCodexAvailable: Bool) {
        self.isCodexAvailable = isCodexAvailable
    }

    func start(onChange: @escaping (Bool) -> Void) {}

    func stop() {}
}
