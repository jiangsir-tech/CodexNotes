import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct NoteImageImportLimits: Equatable, Sendable {
    public let maximumEncodedBytes: Int
    public let maximumStoredBytes: Int
    public let maximumPixelCount: Int
    public let maximumDimension: Int

    public init(
        maximumEncodedBytes: Int = 20 * 1_024 * 1_024,
        maximumStoredBytes: Int = 60 * 1_024 * 1_024,
        maximumPixelCount: Int = 40_000_000,
        maximumDimension: Int = 12_000
    ) {
        self.maximumEncodedBytes = maximumEncodedBytes
        self.maximumStoredBytes = maximumStoredBytes
        self.maximumPixelCount = maximumPixelCount
        self.maximumDimension = maximumDimension
    }
}

public struct PreparedNoteImage: Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public var byteCount: Int { data.count }

    fileprivate let data: Data
    fileprivate let filename: String

    fileprivate init(data: Data, filename: String, pixelWidth: Int, pixelHeight: Int) {
        self.data = data
        self.filename = filename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct NoteImageAsset: Equatable, Sendable {
    public let fileURL: URL
    public let markdownDestination: String
    public let pixelWidth: Int
    public let pixelHeight: Int

    public var markdown: String {
        "![\(L10n.text(.imageMarkdownAltText))](\(markdownDestination))"
    }
}

public enum NoteImageStoreError: LocalizedError, Sendable {
    case invalidSource
    case sourceIsNotRegularFile
    case unsupportedFormat
    case animatedImageUnsupported
    case encodedImageTooLarge(Int)
    case storedImageTooLarge(Int)
    case invalidDimensions
    case pixelLimitExceeded(width: Int, height: Int)
    case cannotDecode
    case cannotEncode
    case cannotCreateAssetDirectory(String)
    case unsafeAssetDirectory(String)
    case invalidManagedAsset(String)
    case assetConflict(String)
    case cannotWrite(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSource:
            return L10n.text(.imageStoreErrorInvalidSource)
        case .sourceIsNotRegularFile:
            return L10n.text(.imageStoreErrorNotRegularFile)
        case .unsupportedFormat:
            return L10n.text(.imageStoreErrorUnsupportedFormat)
        case .animatedImageUnsupported:
            return L10n.text(.imageStoreErrorAnimatedUnsupported)
        case let .encodedImageTooLarge(bytes):
            return L10n.text(
                .imageStoreErrorEncodedTooLarge,
                replacements: ["sizeMB": Self.megabytes(bytes)]
            )
        case let .storedImageTooLarge(bytes):
            return L10n.text(
                .imageStoreErrorConvertedTooLarge,
                replacements: ["sizeMB": Self.megabytes(bytes)]
            )
        case .invalidDimensions:
            return L10n.text(.imageStoreErrorInvalidDimensions)
        case let .pixelLimitExceeded(width, height):
            return L10n.text(
                .imageStoreErrorDimensionsTooLarge,
                replacements: [
                    "width": String(width),
                    "height": String(height)
                ]
            )
        case .cannotDecode:
            return L10n.text(.imageStoreErrorCannotDecode)
        case .cannotEncode:
            return L10n.text(.imageStoreErrorCannotEncode)
        case let .cannotCreateAssetDirectory(path):
            return L10n.text(
                .imageStoreErrorCannotCreateDirectory,
                replacements: ["path": path]
            )
        case let .unsafeAssetDirectory(path):
            return L10n.text(
                .imageStoreErrorUnsafeDirectory,
                replacements: ["path": path]
            )
        case let .invalidManagedAsset(path):
            return L10n.text(
                .imageStoreErrorInvalidAsset,
                replacements: ["path": path]
            )
        case let .assetConflict(path):
            return L10n.text(
                .imageStoreErrorAssetConflict,
                replacements: ["path": path]
            )
        case let .cannotWrite(path):
            return L10n.text(
                .imageStoreErrorCannotSave,
                replacements: ["path": path]
            )
        }
    }

    private static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f", Double(bytes) / 1_048_576)
    }
}

public final class NoteImageStore: @unchecked Sendable {
    private enum SourceFormat: Equatable {
        case png
        case jpeg
        case heic
        case webP
        case tiff
    }

    public let rootURL: URL
    public let assetRootURL: URL
    public let limits: NoteImageImportLimits

    private let atomicWrite: @Sendable (Data, URL) throws -> Void
    private let readData: @Sendable (URL) throws -> Data

    public init(
        rootURL: URL,
        limits: NoteImageImportLimits = NoteImageImportLimits()
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.assetRootURL = rootURL.standardizedFileURL
            .appendingPathComponent("Assets", isDirectory: true)
        self.limits = limits
        self.atomicWrite = { data, url in
            try data.write(to: url, options: .atomic)
        }
        self.readData = { url in
            try Data(contentsOf: url, options: .mappedIfSafe)
        }
    }

    init(
        rootURL: URL,
        limits: NoteImageImportLimits = NoteImageImportLimits(),
        atomicWrite: @escaping @Sendable (Data, URL) throws -> Void,
        readData: @escaping @Sendable (URL) throws -> Data = {
            try Data(contentsOf: $0, options: .mappedIfSafe)
        }
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.assetRootURL = rootURL.standardizedFileURL
            .appendingPathComponent("Assets", isDirectory: true)
        self.limits = limits
        self.atomicWrite = atomicWrite
        self.readData = readData
    }

    public func prepareImage(at fileURL: URL) throws -> PreparedNoteImage {
        guard fileURL.isFileURL else {
            throw NoteImageStoreError.invalidSource
        }

        let values: URLResourceValues
        do {
            values = try fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ])
        } catch {
            throw NoteImageStoreError.invalidSource
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw NoteImageStoreError.sourceIsNotRegularFile
        }
        if let fileSize = values.fileSize, fileSize > limits.maximumEncodedBytes {
            throw NoteImageStoreError.encodedImageTooLarge(fileSize)
        }

        let data: Data
        do {
            data = try readData(fileURL)
        } catch {
            throw NoteImageStoreError.invalidSource
        }
        return try prepareImage(data: data)
    }

    public func prepareImage(data: Data) throws -> PreparedNoteImage {
        guard !data.isEmpty else {
            throw NoteImageStoreError.invalidSource
        }
        guard data.count <= limits.maximumEncodedBytes else {
            throw NoteImageStoreError.encodedImageTooLarge(data.count)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceTypeIdentifier = CGImageSourceGetType(source),
              let sourceType = UTType(sourceTypeIdentifier as String)
        else {
            throw NoteImageStoreError.unsupportedFormat
        }

        let sourceFormat: SourceFormat
        if sourceType.conforms(to: .png) {
            sourceFormat = .png
        } else if sourceType.conforms(to: .jpeg) {
            sourceFormat = .jpeg
        } else if sourceType.conforms(to: .heic) {
            sourceFormat = .heic
        } else if sourceType.conforms(to: .webP) {
            sourceFormat = .webP
        } else if sourceType.conforms(to: .tiff) {
            sourceFormat = .tiff
        } else {
            throw NoteImageStoreError.unsupportedFormat
        }
        guard Self.hasStructurallyCompleteContainer(data, format: sourceFormat) else {
            throw NoteImageStoreError.cannotDecode
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw NoteImageStoreError.cannotDecode
        }
        guard frameCount == 1 else {
            throw NoteImageStoreError.animatedImageUnsupported
        }
        guard CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
        else {
            // Reject containers that ImageIO itself reports as incomplete.
            // Some codecs deliberately recover damaged pixel streams; the
            // normalized output is still bounded and structurally valid.
            throw NoteImageStoreError.cannotDecode
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any],
              let width = Self.integerProperty(properties[kCGImagePropertyPixelWidth]),
              let height = Self.integerProperty(properties[kCGImagePropertyPixelHeight]),
              width > 0,
              height > 0
        else {
            throw NoteImageStoreError.invalidDimensions
        }

        let pixelCount = width.multipliedReportingOverflow(by: height)
        guard !pixelCount.overflow,
              width <= limits.maximumDimension,
              height <= limits.maximumDimension,
              pixelCount.partialValue <= limits.maximumPixelCount
        else {
            throw NoteImageStoreError.pixelLimitExceeded(width: width, height: height)
        }

        let decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            decodeOptions as CFDictionary
        ) else {
            throw NoteImageStoreError.cannotDecode
        }

        let normalizedPixelCount = image.width.multipliedReportingOverflow(by: image.height)
        guard image.width > 0,
              image.height > 0,
              !normalizedPixelCount.overflow,
              image.width <= limits.maximumDimension,
              image.height <= limits.maximumDimension,
              normalizedPixelCount.partialValue <= limits.maximumPixelCount
        else {
            throw NoteImageStoreError.pixelLimitExceeded(
                width: image.width,
                height: image.height
            )
        }

        // ImageIO may expose an opaque HEIC thumbnail through a premultiplied
        // alpha bitmap. Prefer the source metadata for HEIC/WebP so genuine
        // transparency is preserved without turning every photo into a PNG.
        let sourceHasAlpha = Self.booleanProperty(
            properties[kCGImagePropertyHasAlpha]
        ) == true
        let preservesSharpEdges = sourceFormat == .png
            || sourceFormat == .tiff
            || ((sourceFormat == .heic || sourceFormat == .webP) && sourceHasAlpha)
        let outputType: UTType = preservesSharpEdges ? .png : .jpeg
        let outputExtension = preservesSharpEdges ? "png" : "jpg"
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            outputType.identifier as CFString,
            1,
            nil
        ) else {
            throw NoteImageStoreError.cannotEncode
        }
        let outputProperties: [CFString: Any] = preservesSharpEdges
            ? [:]
            : [kCGImageDestinationLossyCompressionQuality: 0.9]
        CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw NoteImageStoreError.cannotEncode
        }

        let normalizedData = output as Data
        guard normalizedData.count <= limits.maximumStoredBytes else {
            throw NoteImageStoreError.storedImageTooLarge(normalizedData.count)
        }
        let digest = SHA256.hash(data: normalizedData)
            .map { String(format: "%02x", $0) }
            .joined()
        let filename = "image-\(digest).\(outputExtension)"
        return PreparedNoteImage(
            data: normalizedData,
            filename: filename,
            pixelWidth: image.width,
            pixelHeight: image.height
        )
    }

    public func commit(_ prepared: PreparedNoteImage) throws -> NoteImageAsset {
        guard prepared.byteCount <= limits.maximumStoredBytes else {
            throw NoteImageStoreError.storedImageTooLarge(prepared.byteCount)
        }
        let pixelCount = prepared.pixelWidth.multipliedReportingOverflow(
            by: prepared.pixelHeight
        )
        guard prepared.pixelWidth > 0,
              prepared.pixelHeight > 0,
              !pixelCount.overflow,
              prepared.pixelWidth <= limits.maximumDimension,
              prepared.pixelHeight <= limits.maximumDimension,
              pixelCount.partialValue <= limits.maximumPixelCount
        else {
            throw NoteImageStoreError.pixelLimitExceeded(
                width: prepared.pixelWidth,
                height: prepared.pixelHeight
            )
        }
        try ensureSafeAssetDirectory()
        let fileURL = assetRootURL.appendingPathComponent(
            prepared.filename,
            isDirectory: false
        )

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
                throw NoteImageStoreError.unsafeAssetDirectory(fileURL.path)
            }
            let existing: Data
            do {
                existing = try readData(fileURL)
            } catch {
                throw NoteImageStoreError.cannotWrite(fileURL.path)
            }
            guard existing == prepared.data else {
                throw NoteImageStoreError.assetConflict(fileURL.path)
            }
        } else {
            do {
                try atomicWrite(prepared.data, fileURL)
            } catch {
                throw NoteImageStoreError.cannotWrite(fileURL.path)
            }
        }

        return NoteImageAsset(
            fileURL: fileURL,
            markdownDestination: "../Assets/\(prepared.filename)",
            pixelWidth: prepared.pixelWidth,
            pixelHeight: prepared.pixelHeight
        )
    }

    public func importImage(data: Data) throws -> NoteImageAsset {
        try commit(prepareImage(data: data))
    }

    public func importImage(at fileURL: URL) throws -> NoteImageAsset {
        try commit(prepareImage(at: fileURL))
    }

    public func resolveManagedAsset(
        markdownDestination: String,
        relativeTo documentFileURL: URL
    ) -> URL? {
        guard let filename = Self.managedFilename(from: markdownDestination) else {
            return nil
        }
        let expectedURL = assetRootURL
            .appendingPathComponent(filename, isDirectory: false)
            .standardizedFileURL
        let relativeURL = URL(
            fileURLWithPath: markdownDestination,
            relativeTo: documentFileURL.deletingLastPathComponent()
        ).standardizedFileURL
        guard relativeURL == expectedURL,
              FileManager.default.fileExists(atPath: expectedURL.path)
        else {
            return nil
        }

        let assetDirectoryValues = try? assetRootURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        let fileValues = try? expectedURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ])
        guard assetDirectoryValues?.isDirectory == true,
              assetDirectoryValues?.isSymbolicLink != true,
              fileValues?.isRegularFile == true,
              fileValues?.isSymbolicLink != true,
              let fileSize = fileValues?.fileSize,
              fileSize > 0,
              fileSize <= limits.maximumStoredBytes
        else {
            return nil
        }

        let canonicalRoot = assetRootURL.resolvingSymlinksInPath().standardizedFileURL
        let canonicalFile = expectedURL.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalFile.deletingLastPathComponent() == canonicalRoot else {
            return nil
        }
        return canonicalFile
    }

    public func loadValidatedManagedAssetData(at fileURL: URL) throws -> Data {
        let standardizedURL = fileURL.standardizedFileURL
        guard standardizedURL.deletingLastPathComponent() == assetRootURL,
              Self.managedFilename(
                from: "../Assets/\(standardizedURL.lastPathComponent)"
              ) != nil
        else {
            throw NoteImageStoreError.invalidManagedAsset(fileURL.path)
        }

        let assetDirectoryValues = try? assetRootURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        let fileValues = try? standardizedURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ])
        guard assetDirectoryValues?.isDirectory == true,
              assetDirectoryValues?.isSymbolicLink != true,
              fileValues?.isRegularFile == true,
              fileValues?.isSymbolicLink != true,
              let fileSize = fileValues?.fileSize,
              fileSize > 0,
              fileSize <= limits.maximumStoredBytes
        else {
            throw NoteImageStoreError.invalidManagedAsset(fileURL.path)
        }

        let canonicalRoot = assetRootURL.resolvingSymlinksInPath().standardizedFileURL
        let canonicalFile = standardizedURL.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalFile.deletingLastPathComponent() == canonicalRoot else {
            throw NoteImageStoreError.invalidManagedAsset(fileURL.path)
        }

        let data: Data
        do {
            data = try readData(canonicalFile)
        } catch {
            throw NoteImageStoreError.invalidManagedAsset(fileURL.path)
        }
        guard data.count == fileSize else {
            throw NoteImageStoreError.invalidManagedAsset(fileURL.path)
        }

        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        let expectedPrefix = "image-\(digest)."
        guard standardizedURL.lastPathComponent.hasPrefix(expectedPrefix),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let typeIdentifier = CGImageSourceGetType(source),
              let type = UTType(typeIdentifier as String),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = Self.integerProperty(properties[kCGImagePropertyPixelWidth]),
              let height = Self.integerProperty(properties[kCGImagePropertyPixelHeight]),
              width > 0,
              height > 0
        else {
            throw NoteImageStoreError.invalidManagedAsset(fileURL.path)
        }

        let expectedExtension: String
        let format: SourceFormat
        if type.conforms(to: .png) {
            expectedExtension = "png"
            format = .png
        } else if type.conforms(to: .jpeg) {
            expectedExtension = "jpg"
            format = .jpeg
        } else {
            throw NoteImageStoreError.invalidManagedAsset(fileURL.path)
        }
        let pixelCount = width.multipliedReportingOverflow(by: height)
        guard standardizedURL.pathExtension == expectedExtension,
              !pixelCount.overflow,
              width <= limits.maximumDimension,
              height <= limits.maximumDimension,
              pixelCount.partialValue <= limits.maximumPixelCount,
              Self.hasStructurallyCompleteContainer(data, format: format)
        else {
            throw NoteImageStoreError.invalidManagedAsset(fileURL.path)
        }
        return data
    }

    private func ensureSafeAssetDirectory() throws {
        if FileManager.default.fileExists(atPath: assetRootURL.path) {
            let values = try? assetRootURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey
            ])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else {
                throw NoteImageStoreError.unsafeAssetDirectory(assetRootURL.path)
            }
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: assetRootURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw NoteImageStoreError.cannotCreateAssetDirectory(assetRootURL.path)
        }
        let values = try? assetRootURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            throw NoteImageStoreError.unsafeAssetDirectory(assetRootURL.path)
        }
    }

    private static func managedFilename(from destination: String) -> String? {
        let prefix = "../Assets/"
        guard destination.hasPrefix(prefix),
              destination.count > prefix.count,
              !destination.contains("\\"),
              !destination.contains("%"),
              !destination.contains("\0")
        else { return nil }
        let filename = String(destination.dropFirst(prefix.count))
        guard !filename.contains("/"),
              filename.range(
                of: #"^image-[0-9a-f]{64}\.(png|jpg)$"#,
                options: .regularExpression
              ) != nil
        else { return nil }
        return filename
    }

    private static func integerProperty(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let number = value as? Int {
            return number
        }
        return nil
    }

    private static func booleanProperty(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let value = value as? Bool {
            return value
        }
        return nil
    }

    private static func hasStructurallyCompleteContainer(
        _ data: Data,
        format: SourceFormat
    ) -> Bool {
        switch format {
        case .png:
            return hasCompletePNGFraming(data)
        case .jpeg:
            return hasCompleteJPEGFraming(data)
        case .webP:
            return hasCompleteWebPFraming(data)
        case .heic:
            return hasCompleteISOBaseMediaFileFraming(data)
        case .tiff:
            // TIFF has no terminal marker. ImageIO's status plus a successful
            // full decode remains the authoritative completeness check.
            return data.count >= 8
        }
    }

    private static func hasCompletePNGFraming(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count >= 8, Array(bytes[0..<8]) == signature else { return false }

        var offset = 8
        var chunkIndex = 0
        var sawImageData = false
        while offset <= bytes.count - 12 {
            guard let length = bigEndianUInt32(bytes, at: offset).map(Int.init),
                  length <= bytes.count - offset - 12
            else { return false }
            let typeStart = offset + 4
            let dataStart = typeStart + 4
            let crcOffset = dataStart + length
            let nextOffset = crcOffset + 4
            let type = Array(bytes[typeStart..<(typeStart + 4)])

            if chunkIndex == 0, type != Array("IHDR".utf8) {
                return false
            }
            if type == Array("IHDR".utf8), length != 13 {
                return false
            }
            if type == Array("IDAT".utf8), length > 0 {
                sawImageData = true
            }
            if type == Array("IEND".utf8) {
                return length == 0 && sawImageData && nextOffset == bytes.count
            }
            offset = nextOffset
            chunkIndex += 1
        }
        return false
    }

    private static func hasCompleteJPEGFraming(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8
        else { return false }

        // A valid still JPEG needs at least one complete Start Of Scan
        // segment. ImageIO performs the deeper entropy validation afterward.
        var offset = 2
        var sawScan = false
        while offset + 1 < bytes.count {
            guard bytes[offset] == 0xFF else {
                offset += 1
                continue
            }
            while offset < bytes.count, bytes[offset] == 0xFF {
                offset += 1
            }
            guard offset < bytes.count else { return false }
            let marker = bytes[offset]
            offset += 1
            if marker == 0x00 || (0xD0...0xD7).contains(marker) {
                continue
            }
            if marker == 0xD9 {
                return sawScan
            }
            if marker == 0x01 || marker == 0xD8 {
                continue
            }
            guard offset + 1 < bytes.count,
                  let segmentLength = bigEndianUInt16(bytes, at: offset).map(Int.init),
                  segmentLength >= 2,
                  segmentLength <= bytes.count - offset
            else { return false }
            if marker == 0xDA {
                sawScan = true
            }
            offset += segmentLength
        }
        return false
    }

    private static func hasCompleteWebPFraming(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 20,
              Array(bytes[0..<4]) == Array("RIFF".utf8),
              Array(bytes[8..<12]) == Array("WEBP".utf8),
              let declaredSize = littleEndianUInt32(bytes, at: 4).map(Int.init),
              declaredSize == bytes.count - 8
        else { return false }

        var offset = 12
        var sawImageChunk = false
        while offset <= bytes.count - 8 {
            let type = Array(bytes[offset..<(offset + 4)])
            guard let length = littleEndianUInt32(bytes, at: offset + 4).map(Int.init),
                  length <= bytes.count - offset - 8
            else { return false }
            if type == Array("VP8 ".utf8)
                || type == Array("VP8L".utf8)
                || type == Array("VP8X".utf8)
            {
                sawImageChunk = true
            }
            let paddedLength = length + (length & 1)
            guard paddedLength <= bytes.count - offset - 8 else { return false }
            offset += 8 + paddedLength
        }
        return sawImageChunk && offset == bytes.count
    }

    private static func hasCompleteISOBaseMediaFileFraming(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 16 else { return false }
        var offset = 0
        var sawFileType = false
        while offset < bytes.count {
            guard offset <= bytes.count - 8,
                  let shortSize = bigEndianUInt32(bytes, at: offset)
            else { return false }
            let type = Array(bytes[(offset + 4)..<(offset + 8)])
            var headerSize = 8
            let boxSize: Int
            if shortSize == 0 {
                boxSize = bytes.count - offset
            } else if shortSize == 1 {
                guard offset <= bytes.count - 16,
                      let longSize = bigEndianUInt64(bytes, at: offset + 8),
                      longSize <= UInt64(Int.max)
                else { return false }
                headerSize = 16
                boxSize = Int(longSize)
            } else {
                boxSize = Int(shortSize)
            }
            guard boxSize >= headerSize, boxSize <= bytes.count - offset else {
                return false
            }
            if type == Array("ftyp".utf8) {
                sawFileType = true
            }
            offset += boxSize
        }
        return sawFileType && offset == bytes.count
    }

    private static func bigEndianUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16? {
        guard offset >= 0, offset <= bytes.count - 2 else { return nil }
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func bigEndianUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= bytes.count - 4 else { return nil }
        return (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= bytes.count - 4 else { return nil }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func bigEndianUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64? {
        guard offset >= 0, offset <= bytes.count - 8 else { return nil }
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(bytes[offset + index])
        }
        return value
    }

}

public struct MarkdownImageMatch: Equatable, Sendable {
    public let tokenRange: NSRange
    public let lineRange: NSRange
    public let altText: String
    public let markdownDestination: String

    public init(
        tokenRange: NSRange,
        lineRange: NSRange,
        altText: String,
        markdownDestination: String
    ) {
        self.tokenRange = tokenRange
        self.lineRange = lineRange
        self.altText = altText
        self.markdownDestination = markdownDestination
    }
}

public enum MarkdownImage {
    private static let managedImageExpression = try! NSRegularExpression(
        pattern: #"(?m)^[ ]{0,3}!\[([^\]\r\n]*)\]\((\.\./Assets/image-[0-9a-f]{64}\.(?:png|jpg))\)[ ]*$"#
    )

    public static func matches(in markdown: String) -> [MarkdownImageMatch] {
        let source = markdown as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let fencedRanges = fencedCodeRanges(in: source)
        return managedImageExpression.matches(in: markdown, range: fullRange).compactMap {
            result in
            guard result.numberOfRanges == 3,
                  result.range(at: 1).location != NSNotFound,
                  result.range(at: 2).location != NSNotFound,
                  !fencedRanges.contains(where: { NSLocationInRange(result.range.location, $0) })
            else { return nil }
            return MarkdownImageMatch(
                tokenRange: result.range,
                lineRange: source.lineRange(for: result.range),
                altText: source.substring(with: result.range(at: 1)),
                markdownDestination: source.substring(with: result.range(at: 2))
            )
        }
    }

    private static func fencedCodeRanges(in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = 0
        var openingLocation: Int?
        var openingMarker: Character?

        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let line = source.substring(with: lineRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let marker: Character?
            if line.hasPrefix("```") {
                marker = "`"
            } else if line.hasPrefix("~~~") {
                marker = "~"
            } else {
                marker = nil
            }

            if let marker {
                if openingLocation == nil {
                    openingLocation = lineRange.location
                    openingMarker = marker
                } else if openingMarker == marker, let start = openingLocation {
                    ranges.append(NSRange(location: start, length: NSMaxRange(lineRange) - start))
                    openingLocation = nil
                    openingMarker = nil
                }
            }
            location = NSMaxRange(lineRange)
        }

        if let openingLocation {
            ranges.append(NSRange(location: openingLocation, length: source.length - openingLocation))
        }
        return ranges
    }
}
