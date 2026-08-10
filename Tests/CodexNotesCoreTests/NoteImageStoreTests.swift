import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CodexNotesCore

final class NoteImageStoreTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexNoteImageStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
    }

    func testPNGDataIsNormalizedStoredAndResolvedRelativeToTaskDocument() throws {
        let store = NoteImageStore(rootURL: temporaryRoot)
        let source = try imageData(type: .png, width: 3, height: 2, hasAlpha: true)

        let asset = try store.importImage(data: source)

        XCTAssertEqual(asset.pixelWidth, 3)
        XCTAssertEqual(asset.pixelHeight, 2)
        XCTAssertEqual(asset.fileURL.pathExtension, "png")
        XCTAssertEqual(asset.fileURL.deletingLastPathComponent(), store.assetRootURL)
        XCTAssertTrue(asset.markdownDestination.hasPrefix("../Assets/image-"))
        XCTAssertEqual(
            asset.markdown,
            "![\(L10n.text(.imageMarkdownAltText))](\(asset.markdownDestination))"
        )

        let stored = try Data(contentsOf: asset.fileURL)
        XCTAssertEqual(Array(stored.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(asset.fileURL.lastPathComponent, normalizedFilename(for: stored, ext: "png"))

        let taskDocument = temporaryRoot
            .appendingPathComponent("Tasks", isDirectory: true)
            .appendingPathComponent("thread-a.md")
        XCTAssertEqual(
            store.resolveManagedAsset(
                markdownDestination: asset.markdownDestination,
                relativeTo: taskDocument
            ),
            asset.fileURL.standardizedFileURL
        )
    }

    func testJPEGDataIsNormalizedToJPEGAndUsesContentMagicNotSuggestedExtension() throws {
        let store = NoteImageStore(rootURL: temporaryRoot)
        let source = try imageData(type: .jpeg, width: 4, height: 3, hasAlpha: false)
        let misleadingURL = temporaryRoot.appendingPathComponent("actually-jpeg.png")
        try source.write(to: misleadingURL, options: .atomic)

        let asset = try store.importImage(at: misleadingURL)

        XCTAssertEqual(asset.pixelWidth, 4)
        XCTAssertEqual(asset.pixelHeight, 3)
        XCTAssertEqual(asset.fileURL.pathExtension, "jpg")
        let stored = try Data(contentsOf: asset.fileURL)
        XCTAssertEqual(Array(stored.prefix(3)), [0xFF, 0xD8, 0xFF])
        XCTAssertEqual(asset.fileURL.lastPathComponent, normalizedFilename(for: stored, ext: "jpg"))
    }

    func testJPEGWithTrailingCompositePayloadStillImportsItsPrimaryImage() throws {
        var source = try imageData(type: .jpeg, width: 4, height: 3, hasAlpha: false)
        source.append(Data("trailing-motion-photo-payload".utf8))

        let asset = try NoteImageStore(rootURL: temporaryRoot).importImage(data: source)

        XCTAssertEqual(asset.pixelWidth, 4)
        XCTAssertEqual(asset.pixelHeight, 3)
        XCTAssertEqual(asset.fileURL.pathExtension, "jpg")
    }

    func testPNGMagicWinsOverMisleadingJPEGExtension() throws {
        let store = NoteImageStore(rootURL: temporaryRoot)
        let source = try imageData(type: .png, width: 2, height: 2, hasAlpha: true)
        let misleadingURL = temporaryRoot.appendingPathComponent("actually-png.jpg")
        try source.write(to: misleadingURL, options: .atomic)

        let asset = try store.importImage(at: misleadingURL)

        XCTAssertEqual(asset.fileURL.pathExtension, "png")
        XCTAssertEqual(Array(try Data(contentsOf: asset.fileURL).prefix(8)), [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        ])
    }

    func testHEICTIFFAndStaticWebPInputsAreNormalizedToManagedImages() throws {
        let store = NoteImageStore(rootURL: temporaryRoot)
        let heic = try imageData(type: .heic, width: 3, height: 2, hasAlpha: false)
        let tiff = try imageData(type: .tiff, width: 2, height: 3, hasAlpha: true)
        let webP = try XCTUnwrap(Data(base64Encoded:
            "UklGRkAAAABXRUJQVlA4TDQAAAAvAUAAAB+gpm0DNpWOuxiqpm0DNpWOuxiqpm0DNpWOuxg6//F/W5JsAzVtG7D4TToi+h8H"
        ))

        let assets = try [heic, tiff, webP].map(store.importImage)

        XCTAssertEqual(assets[0].fileURL.pathExtension, "jpg")
        XCTAssertEqual(assets[0].pixelWidth, 3)
        XCTAssertEqual(assets[0].pixelHeight, 2)
        XCTAssertEqual(assets[1].fileURL.pathExtension, "png")
        XCTAssertEqual(assets[1].pixelWidth, 2)
        XCTAssertEqual(assets[1].pixelHeight, 3)
        XCTAssertEqual(assets[2].pixelWidth, 2)
        XCTAssertEqual(assets[2].pixelHeight, 2)
        XCTAssertTrue(["png", "jpg"].contains(assets[2].fileURL.pathExtension))
        XCTAssertTrue(assets.allSatisfy {
            FileManager.default.fileExists(atPath: $0.fileURL.path)
        })
    }

    func testTransparentHEICIsNormalizedToPNGWithoutLosingAlpha() throws {
        let source = try imageData(type: .heic, width: 3, height: 2, hasAlpha: true)
        let sourceProperties = try imageProperties(source)
        XCTAssertEqual(Self.boolean(sourceProperties[kCGImagePropertyHasAlpha]), true)

        let asset = try NoteImageStore(rootURL: temporaryRoot).importImage(data: source)
        let storedProperties = try imageProperties(Data(contentsOf: asset.fileURL))

        XCTAssertEqual(asset.fileURL.pathExtension, "png")
        XCTAssertEqual(Self.boolean(storedProperties[kCGImagePropertyHasAlpha]), true)
    }

    func testTransparentWebPIsNormalizedToPNGWithoutLosingAlpha() throws {
        let source = try XCTUnwrap(Data(base64Encoded:
            "UklGRjQAAABXRUJQVlA4TCgAAAAvAUAAEB8gEEjaH3oNAUGR/6MJCAr+j04gQEjjP0o4Zl2IHyBE9D8C"
        ))
        let sourceProperties = try imageProperties(source)
        XCTAssertEqual(Self.boolean(sourceProperties[kCGImagePropertyHasAlpha]), true)

        let asset = try NoteImageStore(rootURL: temporaryRoot).importImage(data: source)
        let storedProperties = try imageProperties(Data(contentsOf: asset.fileURL))

        XCTAssertEqual(asset.fileURL.pathExtension, "png")
        XCTAssertEqual(Self.boolean(storedProperties[kCGImagePropertyHasAlpha]), true)
    }

    func testNormalizationAppliesOrientationAndStripsEXIFMetadata() throws {
        let metadata: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifUserComment: "secret-exif",
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFArtist: "secret-artist",
            ],
        ]
        let source = try imageData(
            type: .jpeg,
            width: 2,
            height: 3,
            hasAlpha: false,
            properties: metadata
        )
        let sourceProperties = try imageProperties(source)
        XCTAssertEqual(Self.integer(sourceProperties[kCGImagePropertyOrientation]), 6)
        XCTAssertNotNil(sourceProperties[kCGImagePropertyExifDictionary])
        XCTAssertNotNil(sourceProperties[kCGImagePropertyTIFFDictionary])

        let asset = try NoteImageStore(rootURL: temporaryRoot).importImage(data: source)
        let stored = try Data(contentsOf: asset.fileURL)
        let storedProperties = try imageProperties(stored)

        XCTAssertNotEqual(stored, source)
        XCTAssertEqual(asset.pixelWidth, 3)
        XCTAssertEqual(asset.pixelHeight, 2)
        XCTAssertNotEqual(Self.integer(storedProperties[kCGImagePropertyOrientation]), 6)
        let storedEXIF = storedProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(storedEXIF?[kCGImagePropertyExifUserComment])
        let storedTIFF = storedProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertNil(storedTIFF?[kCGImagePropertyTIFFArtist])
    }

    func testRepeatedImportDeduplicatesTheNormalizedAsset() throws {
        let store = NoteImageStore(rootURL: temporaryRoot)
        let source = try imageData(type: .png, width: 3, height: 3, hasAlpha: true)

        let first = try store.importImage(data: source)
        let second = try store.importImage(data: source)

        XCTAssertEqual(first, second)
        let files = try FileManager.default.contentsOfDirectory(
            at: store.assetRootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.filter { !$0.lastPathComponent.hasPrefix(".") }.count, 1)
    }

    func testAtomicWriteFailureIsReportedWithoutCreatingAnAsset() throws {
        let store = NoteImageStore(
            rootURL: temporaryRoot,
            atomicWrite: { _, _ in throw FixtureError.injectedFailure }
        )
        let source = try imageData(type: .png, width: 1, height: 1, hasAlpha: true)

        XCTAssertThrowsError(try store.importImage(data: source)) { error in
            guard let noteError = error as? NoteImageStoreError,
                  case let .cannotWrite(path) = noteError
            else { return XCTFail("Expected cannotWrite, got \(error)") }
            XCTAssertTrue(path.hasSuffix(".png"))
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: store.assetRootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(contents.isEmpty)
    }

    func testExistingDifferentBytesAtContentAddressedPathAreNeverOverwritten() throws {
        let store = NoteImageStore(rootURL: temporaryRoot)
        let prepared = try store.prepareImage(
            data: imageData(type: .png, width: 2, height: 1, hasAlpha: true)
        )
        let asset = try store.commit(prepared)
        let conflicting = Data("do-not-overwrite".utf8)
        try conflicting.write(to: asset.fileURL, options: .atomic)

        XCTAssertThrowsError(try store.commit(prepared)) { error in
            guard let noteError = error as? NoteImageStoreError,
                  case let .assetConflict(path) = noteError
            else { return XCTFail("Expected assetConflict, got \(error)") }
            XCTAssertEqual(path, asset.fileURL.path)
        }
        XCTAssertEqual(try Data(contentsOf: asset.fileURL), conflicting)
    }

    func testDefaultTwentyMegabyteEncodedLimitRejectsBeforeDecoding() {
        let store = NoteImageStore(rootURL: temporaryRoot)
        let oversized = Data(
            repeating: 0,
            count: NoteImageImportLimits().maximumEncodedBytes + 1
        )

        XCTAssertThrowsError(try store.prepareImage(data: oversized)) { error in
            guard let noteError = error as? NoteImageStoreError,
                  case let .encodedImageTooLarge(bytes) = noteError
            else { return XCTFail("Expected encodedImageTooLarge, got \(error)") }
            XCTAssertEqual(bytes, 20 * 1_024 * 1_024 + 1)
        }
    }

    func testPixelCountAndMaximumDimensionAreEnforcedBeforeStoring() throws {
        let source = try imageData(type: .png, width: 3, height: 2, hasAlpha: true)
        let pixelLimited = NoteImageStore(
            rootURL: temporaryRoot,
            limits: NoteImageImportLimits(
                maximumEncodedBytes: 1_000_000,
                maximumStoredBytes: 1_000_000,
                maximumPixelCount: 5,
                maximumDimension: 100
            )
        )

        XCTAssertThrowsError(try pixelLimited.prepareImage(data: source)) { error in
            guard let noteError = error as? NoteImageStoreError,
                  case let .pixelLimitExceeded(width, height) = noteError
            else { return XCTFail("Expected pixelLimitExceeded, got \(error)") }
            XCTAssertEqual(width, 3)
            XCTAssertEqual(height, 2)
        }

        let dimensionLimited = NoteImageStore(
            rootURL: temporaryRoot,
            limits: NoteImageImportLimits(
                maximumEncodedBytes: 1_000_000,
                maximumStoredBytes: 1_000_000,
                maximumPixelCount: 100,
                maximumDimension: 2
            )
        )
        XCTAssertThrowsError(try dimensionLimited.prepareImage(data: source)) { error in
            guard let noteError = error as? NoteImageStoreError,
                  case let .pixelLimitExceeded(width, height) = noteError
            else { return XCTFail("Expected pixelLimitExceeded, got \(error)") }
            XCTAssertEqual(width, 3)
            XCTAssertEqual(height, 2)
        }
    }

    func testNormalizedStoredSizeLimitIsEnforced() throws {
        let source = try imageData(type: .png, width: 2, height: 2, hasAlpha: true)
        let store = NoteImageStore(
            rootURL: temporaryRoot,
            limits: NoteImageImportLimits(
                maximumEncodedBytes: 1_000_000,
                maximumStoredBytes: 1,
                maximumPixelCount: 100,
                maximumDimension: 100
            )
        )

        XCTAssertThrowsError(try store.prepareImage(data: source)) { error in
            guard let noteError = error as? NoteImageStoreError,
                  case let .storedImageTooLarge(bytes) = noteError
            else { return XCTFail("Expected storedImageTooLarge, got \(error)") }
            XCTAssertGreaterThan(bytes, 1)
        }
    }

    func testCommitRevalidatesPreparedImageAgainstReceivingStoreLimits() throws {
        let source = try imageData(type: .png, width: 4, height: 3, hasAlpha: true)
        let prepared = try NoteImageStore(rootURL: temporaryRoot).prepareImage(data: source)
        let strictStore = NoteImageStore(
            rootURL: temporaryRoot,
            limits: NoteImageImportLimits(
                maximumEncodedBytes: 1,
                maximumStoredBytes: 1,
                maximumPixelCount: 1,
                maximumDimension: 1
            )
        )

        XCTAssertThrowsError(try strictStore.commit(prepared)) { error in
            guard let noteError = error as? NoteImageStoreError,
                  case .storedImageTooLarge = noteError
            else { return XCTFail("Expected receiving-store limit failure, got \(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: strictStore.assetRootURL.path))
    }

    func testEmptyImageDataIsRejectedAsInvalidSource() {
        let store = NoteImageStore(rootURL: temporaryRoot)

        XCTAssertThrowsError(try store.prepareImage(data: Data())) { error in
            guard let noteError = error as? NoteImageStoreError,
                  case .invalidSource = noteError
            else { return XCTFail("Expected invalidSource, got \(error)") }
        }
    }

    func testUnsupportedGIFIsRejectedByContentType() throws {
        let store = NoteImageStore(rootURL: temporaryRoot)

        let gif = try imageData(type: .gif, width: 1, height: 1, hasAlpha: false)
        XCTAssertThrowsError(try store.prepareImage(data: gif)) { error in
            guard let noteError = error as? NoteImageStoreError,
                  case .unsupportedFormat = noteError
            else { return XCTFail("Expected unsupportedFormat, got \(error)") }
        }
    }

    func testTruncatedPNGWithDeclaredImageDataIsRejectedAsDamaged() throws {
        let store = NoteImageStore(rootURL: temporaryRoot)

        let damagedPNG = try corruptPNGImagePayload(
            imageData(type: .png, width: 4, height: 4, hasAlpha: true)
        )
        XCTAssertThrowsError(try store.prepareImage(data: damagedPNG)) { error in
            guard let noteError = error as? NoteImageStoreError,
                  case .cannotDecode = noteError
            else { return XCTFail("Expected cannotDecode, got \(error)") }
        }
    }

    func testSourceSymlinkIsRejectedEvenWhenItTargetsAValidImage() throws {
        let target = temporaryRoot.appendingPathComponent("target.png")
        try imageData(type: .png, width: 1, height: 1, hasAlpha: true)
            .write(to: target, options: .atomic)
        let symlink = temporaryRoot.appendingPathComponent("source-link.png")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

        XCTAssertThrowsError(try NoteImageStore(rootURL: temporaryRoot).prepareImage(at: symlink)) {
            error in
            guard let noteError = error as? NoteImageStoreError,
                  case .sourceIsNotRegularFile = noteError
            else { return XCTFail("Expected sourceIsNotRegularFile, got \(error)") }
        }
    }

    func testAssetsDirectorySymlinkIsRejectedWithoutWritingOutsideTheStore() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexNoteImageStoreOutside-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let assetsLink = temporaryRoot.appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: assetsLink, withDestinationURL: outside)
        let source = try imageData(type: .png, width: 1, height: 1, hasAlpha: true)

        XCTAssertThrowsError(try NoteImageStore(rootURL: temporaryRoot).importImage(data: source)) {
            error in
            guard let noteError = error as? NoteImageStoreError,
                  case let .unsafeAssetDirectory(path) = noteError
            else { return XCTFail("Expected unsafeAssetDirectory, got \(error)") }
            XCTAssertEqual(path, assetsLink.path)
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testResolveRejectsTraversalAbsoluteWrongBaseAndMissingDestinations() throws {
        let store = NoteImageStore(rootURL: temporaryRoot)
        let asset = try store.importImage(
            data: imageData(type: .png, width: 1, height: 1, hasAlpha: true)
        )
        let filename = asset.fileURL.lastPathComponent
        let taskDocument = temporaryRoot
            .appendingPathComponent("Tasks", isDirectory: true)
            .appendingPathComponent("thread-a.md")

        XCTAssertNil(store.resolveManagedAsset(
            markdownDestination: "../Assets/../Assets/\(filename)",
            relativeTo: taskDocument
        ))
        XCTAssertNil(store.resolveManagedAsset(
            markdownDestination: asset.fileURL.path,
            relativeTo: taskDocument
        ))
        XCTAssertNil(store.resolveManagedAsset(
            markdownDestination: "../Assets/%69mage-\(String(repeating: "a", count: 64)).png",
            relativeTo: taskDocument
        ))
        XCTAssertNil(store.resolveManagedAsset(
            markdownDestination: asset.markdownDestination,
            relativeTo: temporaryRoot.appendingPathComponent("thread-a.md")
        ))

        try FileManager.default.removeItem(at: asset.fileURL)
        XCTAssertNil(store.resolveManagedAsset(
            markdownDestination: asset.markdownDestination,
            relativeTo: taskDocument
        ))
    }

    func testResolveRejectsManagedAssetFileSymlink() throws {
        let store = NoteImageStore(rootURL: temporaryRoot)
        let asset = try store.importImage(
            data: imageData(type: .png, width: 1, height: 1, hasAlpha: true)
        )
        let original = try Data(contentsOf: asset.fileURL)
        let outside = temporaryRoot.appendingPathComponent("outside.png")
        try original.write(to: outside, options: .atomic)
        try FileManager.default.removeItem(at: asset.fileURL)
        try FileManager.default.createSymbolicLink(at: asset.fileURL, withDestinationURL: outside)
        let taskDocument = temporaryRoot
            .appendingPathComponent("Tasks", isDirectory: true)
            .appendingPathComponent("thread-a.md")

        XCTAssertNil(store.resolveManagedAsset(
            markdownDestination: asset.markdownDestination,
            relativeTo: taskDocument
        ))
    }

    func testValidatedManagedAssetLoaderReturnsImportedBytes() throws {
        let store = NoteImageStore(rootURL: temporaryRoot)
        let asset = try store.importImage(
            data: imageData(type: .png, width: 3, height: 2, hasAlpha: true)
        )

        XCTAssertEqual(
            try store.loadValidatedManagedAssetData(at: asset.fileURL),
            try Data(contentsOf: asset.fileURL)
        )
    }

    func testValidatedManagedAssetLoaderRejectsContentChangedUnderHashName() throws {
        let store = NoteImageStore(rootURL: temporaryRoot)
        let asset = try store.importImage(
            data: imageData(type: .png, width: 3, height: 2, hasAlpha: true)
        )
        let replacement = try imageData(type: .png, width: 2, height: 3, hasAlpha: true)
        try replacement.write(to: asset.fileURL, options: .atomic)

        XCTAssertThrowsError(try store.loadValidatedManagedAssetData(at: asset.fileURL)) {
            error in
            guard let noteError = error as? NoteImageStoreError,
                  case .invalidManagedAsset = noteError
            else { return XCTFail("Expected invalidManagedAsset, got \(error)") }
        }
    }

    func testValidatedManagedAssetLoaderReappliesReceivingStorePixelLimits() throws {
        let regularStore = NoteImageStore(rootURL: temporaryRoot)
        let asset = try regularStore.importImage(
            data: imageData(type: .png, width: 3, height: 2, hasAlpha: true)
        )
        let strictStore = NoteImageStore(
            rootURL: temporaryRoot,
            limits: NoteImageImportLimits(
                maximumEncodedBytes: 1_000_000,
                maximumStoredBytes: 1_000_000,
                maximumPixelCount: 1,
                maximumDimension: 1
            )
        )

        XCTAssertThrowsError(try strictStore.loadValidatedManagedAssetData(at: asset.fileURL)) {
            error in
            guard let noteError = error as? NoteImageStoreError,
                  case .invalidManagedAsset = noteError
            else { return XCTFail("Expected invalidManagedAsset, got \(error)") }
        }
    }

    func testMarkdownImageReportsChineseEmojiUTF16Ranges() {
        let destination = managedDestination(character: "a", ext: "png")
        let token = "  ![中文 🚀](\(destination))"
        let markdown = "前缀😀\n\(token)\n后缀"

        let matches = MarkdownImage.matches(in: markdown)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].altText, "中文 🚀")
        XCTAssertEqual(matches[0].markdownDestination, destination)
        XCTAssertEqual(matches[0].tokenRange, (markdown as NSString).range(of: token))
        XCTAssertEqual(
            matches[0].lineRange,
            (markdown as NSString).lineRange(for: (markdown as NSString).range(of: token))
        )
    }

    func testMarkdownImageFindsMultipleImagesWithLFAndCRLFLineEndings() {
        let firstDestination = managedDestination(character: "a", ext: "png")
        let secondDestination = managedDestination(character: "b", ext: "jpg")
        let markdown = "![第一张](\(firstDestination))\r\n文字\r\n   ![第二张](\(secondDestination))\r\n"

        let matches = MarkdownImage.matches(in: markdown)

        XCTAssertEqual(matches.map(\.altText), ["第一张", "第二张"])
        XCTAssertEqual(matches.map(\.markdownDestination), [firstDestination, secondDestination])
    }

    func testMarkdownImageIgnoresFencedRemoteInlineAndMalformedImages() {
        let valid = managedDestination(character: "c", ext: "png")
        let malformedHash = "../Assets/image-not-a-hash.png"
        let uppercaseHash = "../Assets/image-\(String(repeating: "A", count: 64)).png"
        let markdown = """
        ```markdown
        ![fenced](\(valid))
        ```
        ~~~
        ![also fenced](\(valid))
        ~~~
        ![remote](https://example.com/image.png)
        text ![inline](\(valid))
            ![too indented](\(valid))
        ![bad hash](\(malformedHash))
        ![uppercase](\(uppercaseHash))
        ![query](\(valid)?download=1)
        ![backslash](..\\Assets\\image-\(String(repeating: "c", count: 64)).png)
        ![唯一有效](\(valid))
        """

        let matches = MarkdownImage.matches(in: markdown)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.altText, "唯一有效")
        XCTAssertEqual(matches.first?.markdownDestination, valid)
    }

    private func imageData(
        type: UTType,
        width: Int,
        height: Int,
        hasAlpha: Bool,
        properties: [CFString: Any] = [:]
    ) throws -> Data {
        let image = try makeImage(width: width, height: height, hasAlpha: hasAlpha)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw FixtureError.cannotCreateDestination
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.cannotFinalizeImage
        }
        return output as Data
    }

    private func makeImage(width: Int, height: Int, hasAlpha: Bool) throws -> CGImage {
        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * 4
                    bytes[offset] = UInt8((x * 67 + 31) % 255)
                    bytes[offset + 1] = UInt8((y * 83 + 47) % 255)
                    bytes[offset + 2] = UInt8(((x + y) * 59 + 19) % 255)
                    bytes[offset + 3] = hasAlpha ? UInt8(80 + (x + y) % 160) : 255
                }
            }
        }
        guard let provider = CGDataProvider(data: pixels as CFData) else {
            throw FixtureError.cannotCreateImage
        }
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw FixtureError.cannotCreateImage
        }
        return image
    }

    private func imageProperties(_ data: Data) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else {
            throw FixtureError.cannotReadProperties
        }
        return properties
    }

    private func corruptPNGImagePayload(_ source: Data) throws -> Data {
        let data = source
        var offset = 8
        while offset + 12 <= data.count {
            let length = Int(data[offset]) << 24
                | Int(data[offset + 1]) << 16
                | Int(data[offset + 2]) << 8
                | Int(data[offset + 3])
            guard length >= 0, offset + 12 + length <= data.count else {
                throw FixtureError.malformedPNGFixture
            }
            let typeData = data[(offset + 4)..<(offset + 8)]
            if String(data: typeData, encoding: .ascii) == "IDAT", length > 0 {
                // Preserve the PNG signature, IHDR, and the declared IDAT
                // header while truncating before its payload. ImageIO can still
                // identify the format and dimensions, but the source itself is
                // incomplete and must not be accepted as a valid image.
                return Data(data.prefix(offset + 8))
            }
            offset += length + 12
        }
        throw FixtureError.missingPNGImageData
    }

    private func normalizedFilename(for data: Data, ext: String) -> String {
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return "image-\(digest).\(ext)"
    }

    private func managedDestination(character: Character, ext: String) -> String {
        "../Assets/image-\(String(repeating: String(character), count: 64)).\(ext)"
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let number = value as? Int { return number }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        if let value = value as? Bool { return value }
        return nil
    }
}

private enum FixtureError: Error {
    case injectedFailure
    case cannotCreateDestination
    case cannotFinalizeImage
    case cannotCreateImage
    case cannotReadProperties
    case malformedPNGFixture
    case missingPNGImageData
}
