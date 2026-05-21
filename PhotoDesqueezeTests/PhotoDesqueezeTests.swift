import CoreImage
import ImageIO
import XCTest
@testable import PhotoDesqueeze

final class PhotoDesqueezeTests: XCTestCase {
    func testFactorLabelIsFilesystemFriendly() {
        XCTAssertEqual(OutputPlanner.factorLabel(1.33), "1_33x")
        XCTAssertEqual(OutputPlanner.factorLabel(2.0), "2_00x")
    }

    func testOutputPlannerPreservesRelativeSubfolder() throws {
        let root = try makeTemporaryDirectory()
        let input = root.appendingPathComponent("Input", isDirectory: true)
        let output = root.appendingPathComponent("Output", isDirectory: true)
        let nested = input.appendingPathComponent("Day 01", isDirectory: true)
        let source = nested.appendingPathComponent("shot001.DNG")

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: source.path, contents: Data())

        let url = try OutputPlanner.outputURL(
            for: source,
            inputFolder: input,
            outputFolder: output,
            options: ProcessingOptions(
                factor: 1.33,
                axis: .automatic,
                colorSpace: .displayP3,
                outputFormat: .tiff16,
                collisionMode: .autoRename,
                recursive: true,
                preserveSubfolders: true
            )
        )

        XCTAssertEqual(
            url.path,
            output.appendingPathComponent("Day 01/shot001_desqueezed_1_33x.tiff").path
        )
    }

    func testOutputPlannerAvoidsOverwriteWhenRequested() throws {
        let root = try makeTemporaryDirectory()
        let input = root.appendingPathComponent("Input", isDirectory: true)
        let output = root.appendingPathComponent("Output", isDirectory: true)
        let source = input.appendingPathComponent("shot001.tiff")

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: source.path, contents: Data())

        let existing = output.appendingPathComponent("shot001_desqueezed_1_55x.tiff")
        FileManager.default.createFile(atPath: existing.path, contents: Data())

        let url = try OutputPlanner.outputURL(
            for: source,
            inputFolder: input,
            outputFolder: output,
            options: ProcessingOptions(
                factor: 1.55,
                axis: .automatic,
                colorSpace: .displayP3,
                outputFormat: .tiff16,
                collisionMode: .autoRename,
                recursive: false,
                preserveSubfolders: false
            )
        )

        XCTAssertEqual(url.lastPathComponent, "shot001_desqueezed_1_55x-2.tiff")
    }

    func testOutputPlannerSkipsExistingWhenRequested() throws {
        let root = try makeTemporaryDirectory()
        let input = root.appendingPathComponent("Input", isDirectory: true)
        let output = root.appendingPathComponent("Output", isDirectory: true)
        let source = input.appendingPathComponent("shot001.tiff")

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: source.path, contents: Data())

        let existing = output.appendingPathComponent("shot001_desqueezed_1_33x.tiff")
        FileManager.default.createFile(atPath: existing.path, contents: Data())

        let plan = try OutputPlanner.outputPlan(
            for: source,
            inputFolder: input,
            outputFolder: output,
            options: ProcessingOptions(
                factor: 1.33,
                axis: .automatic,
                colorSpace: .displayP3,
                outputFormat: .tiff16,
                collisionMode: .skipExisting,
                recursive: false,
                preserveSubfolders: false
            )
        )

        XCTAssertEqual(plan, .skip(existing))
    }

    func testScannerFindsRawAndRenderedImageExtensions() throws {
        let root = try makeTemporaryDirectory()
        let input = root.appendingPathComponent("Input", isDirectory: true)
        let nested = input.appendingPathComponent("Nested", isDirectory: true)

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: input.appendingPathComponent("a.DNG").path, contents: Data())
        FileManager.default.createFile(atPath: input.appendingPathComponent("b.tif").path, contents: Data())
        FileManager.default.createFile(atPath: nested.appendingPathComponent("c.ARW").path, contents: Data())
        FileManager.default.createFile(atPath: input.appendingPathComponent("notes.txt").path, contents: Data())

        let recursive = try ImageFileScanner.imageFiles(in: input, recursive: true)
        XCTAssertEqual(recursive.map(\.lastPathComponent), ["a.DNG", "b.tif", "c.ARW"])

        let shallow = try ImageFileScanner.imageFiles(in: input, recursive: false)
        XCTAssertEqual(shallow.map(\.lastPathComponent), ["a.DNG", "b.tif"])
    }

    func testAutomaticAxisUsesOrientationAndDimensions() {
        let landscape = CGRect(x: 0, y: 0, width: 10, height: 4)
        let portrait = CGRect(x: 0, y: 0, width: 4, height: 10)

        XCTAssertEqual(
            DesqueezeAxis.automatic.resolved(orientation: .right, imageExtent: landscape),
            .vertical
        )
        XCTAssertEqual(
            DesqueezeAxis.automatic.resolved(orientation: .up, imageExtent: landscape),
            .horizontal
        )
        XCTAssertEqual(
            DesqueezeAxis.automatic.resolved(orientation: nil, imageExtent: portrait),
            .vertical
        )
    }

    func testProcessorWritesDesqueezedSixteenBitTIFF() async throws {
        let root = try makeTemporaryDirectory()
        let input = root.appendingPathComponent("Input", isDirectory: true)
        let output = root.appendingPathComponent("Output", isDirectory: true)
        let source = input.appendingPathComponent("fixture.tiff")

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 10, height: 4))
        try CIContext().writeTIFFRepresentation(
            of: image,
            to: source,
            format: .RGBA16,
            colorSpace: colorSpace
        )

        let processor = ImageBatchProcessor()
        let results = await processor.processBatch(
            inputFolder: input,
            outputFolder: output,
            options: ProcessingOptions(
                factor: 1.33,
                axis: .horizontal,
                colorSpace: .sRGB,
                outputFormat: .tiff16,
                collisionMode: .autoRename,
                recursive: false,
                preserveSubfolders: false
            ),
            progress: { _ in }
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.status, .succeeded)

        let outputURL = try XCTUnwrap(results.first?.outputURL)
        let sourceRef = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(sourceRef, 0, nil) as? [CFString: Any])

        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 13)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 4)
        XCTAssertEqual((properties[kCGImagePropertyDepth] as? NSNumber)?.intValue, 16)

        let manifestURL = output.appendingPathComponent(OutputManifestWriter.manifestFileName)
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        XCTAssertTrue(manifest.contains("fixture_desqueezed_1_33x.tiff"))
        XCTAssertTrue(manifest.contains("Horizontal"))
    }

    func testProcessorCanDesqueezeVertically() async throws {
        let root = try makeTemporaryDirectory()
        let input = root.appendingPathComponent("Input", isDirectory: true)
        let output = root.appendingPathComponent("Output", isDirectory: true)
        let source = input.appendingPathComponent("fixture.tiff")

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image = CIImage(color: CIColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 10))
        try CIContext().writeTIFFRepresentation(
            of: image,
            to: source,
            format: .RGBA16,
            colorSpace: colorSpace
        )

        let processor = ImageBatchProcessor()
        let results = await processor.processBatch(
            inputFolder: input,
            outputFolder: output,
            options: ProcessingOptions(
                factor: 1.33,
                axis: .automatic,
                colorSpace: .sRGB,
                outputFormat: .tiff16,
                collisionMode: .autoRename,
                recursive: false,
                preserveSubfolders: false
            ),
            progress: { _ in }
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.status, .succeeded)
        XCTAssertTrue(results.first?.message.contains("vertical") == true)

        let outputURL = try XCTUnwrap(results.first?.outputURL)
        let sourceRef = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(sourceRef, 0, nil) as? [CFString: Any])

        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 4)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 13)
        XCTAssertEqual((properties[kCGImagePropertyDepth] as? NSNumber)?.intValue, 16)
    }

    func testProcessorSkipsExistingOutput() async throws {
        let root = try makeTemporaryDirectory()
        let input = root.appendingPathComponent("Input", isDirectory: true)
        let output = root.appendingPathComponent("Output", isDirectory: true)
        let source = input.appendingPathComponent("fixture.tiff")

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 10, height: 4))
        try CIContext().writeTIFFRepresentation(
            of: image,
            to: source,
            format: .RGBA16,
            colorSpace: colorSpace
        )

        let existing = output.appendingPathComponent("fixture_desqueezed_1_33x.tiff")
        FileManager.default.createFile(atPath: existing.path, contents: Data("existing".utf8))

        let processor = ImageBatchProcessor()
        let results = await processor.processBatch(
            inputFolder: input,
            outputFolder: output,
            options: ProcessingOptions(
                factor: 1.33,
                axis: .horizontal,
                colorSpace: .sRGB,
                outputFormat: .tiff16,
                collisionMode: .skipExisting,
                recursive: false,
                preserveSubfolders: false
            ),
            progress: { _ in }
        )

        XCTAssertEqual(results.first?.status, .skipped)
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoDesqueezeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
