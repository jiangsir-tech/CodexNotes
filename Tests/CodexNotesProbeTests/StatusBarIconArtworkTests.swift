import AppKit
import CodexNotesCore
import XCTest
@testable import CodexNotesProbe

final class StatusBarIconArtworkTests: XCTestCase {
    func testEverySupportedIconLoadsAsATwentyPointTemplateImage() throws {
        for icon in StatusBarIconID.allCases {
            let image = try XCTUnwrap(StatusBarIconArtwork.image(for: icon))

            XCTAssertEqual(image.size, NSSize(width: 20, height: 20))
            XCTAssertTrue(image.isTemplate)
            XCTAssertFalse(image.representations.isEmpty)
        }
    }

    func testTwoChoicesLoadDifferentArtwork() throws {
        let codex = try XCTUnwrap(StatusBarIconArtwork.image(for: .codexPencil))
        let chatGPT = try XCTUnwrap(StatusBarIconArtwork.image(for: .chatGPTPencil))

        XCTAssertNotEqual(codex.tiffRepresentation, chatGPT.tiffRepresentation)
    }

    func testDefaultArtworkIsAvailable() {
        XCTAssertNotNil(
            StatusBarIconArtwork.image(for: StatusBarIconPreference.defaultValue)
        )
    }

    func testEveryArtworkHasTransparentCornersAndVisibleInk() throws {
        for icon in StatusBarIconID.allCases {
            let image = try XCTUnwrap(StatusBarIconArtwork.image(for: icon))
            let cgImage = try XCTUnwrap(
                image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            )
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            let corners = [
                (0, 0),
                (bitmap.pixelsWide - 1, 0),
                (0, bitmap.pixelsHigh - 1),
                (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)
            ]

            for (x, y) in corners {
                XCTAssertEqual(bitmap.colorAt(x: x, y: y)?.alphaComponent, 0)
            }

            var visiblePixelCount = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide
                where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                    visiblePixelCount += 1
                }
            }
            XCTAssertGreaterThan(visiblePixelCount, 0)
        }
    }
}
