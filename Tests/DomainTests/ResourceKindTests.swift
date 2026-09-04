import XCTest
@testable import PhotoName

final class ResourceKindTests: XCTestCase {
    func test_rawExtensions() {
        for ext in ["arw", "cr2", "cr3", "nef", "raf", "dng", "orf", "rw2"] {
            XCTAssertEqual(ResourceKind(fileExtension: ext), .raw, "扩展名 \(ext) 应识别为 RAW")
        }
    }

    func test_jpegExtensions() {
        XCTAssertEqual(ResourceKind(fileExtension: "jpg"), .jpeg)
        XCTAssertEqual(ResourceKind(fileExtension: "jpeg"), .jpeg)
    }

    func test_heicXmpVideoExtensions() {
        XCTAssertEqual(ResourceKind(fileExtension: "heic"), .heic)
        XCTAssertEqual(ResourceKind(fileExtension: "xmp"), .xmp)
        XCTAssertEqual(ResourceKind(fileExtension: "mov"), .video)
        XCTAssertEqual(ResourceKind(fileExtension: "mp4"), .video)
    }

    func test_extensionCaseInsensitive() {
        XCTAssertEqual(ResourceKind(fileExtension: "ARW"), .raw)
        XCTAssertEqual(ResourceKind(fileExtension: "Jpg"), .jpeg)
        XCTAssertEqual(ResourceKind(fileExtension: "XMP"), .xmp)
    }

    func test_unknownExtension() {
        XCTAssertEqual(ResourceKind(fileExtension: "txt"), .unknown)
        XCTAssertEqual(ResourceKind(fileExtension: ""), .unknown)
    }
}
