import XCTest
@testable import PhotoName

final class MetadataReaderTests: XCTestCase {
    private let reader = MetadataReader()

    /// 测试夹具来自 Tests/Fixtures（打进测试 bundle），由 test/generate_fixtures.swift 生成
    private func fixture(_ name: String, ext: String) throws -> URL {
        let bundle = Bundle(for: type(of: self))
        return try XCTUnwrap(bundle.url(forResource: name, withExtension: ext), "fixture \(name).\(ext) 不在测试 bundle 中")
    }

    func test_sonyJPEG_readsFullEXIF() throws {
        let metadata = try reader.readMetadata(at: fixture("sony_sample", ext: "jpg"))

        XCTAssertEqual(metadata.cameraMake, "SONY")
        XCTAssertEqual(metadata.cameraModel, "ILCE-7RM5")
        XCTAssertEqual(metadata.lensModel, "FE 24-70mm F2.8 GM II")

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: try XCTUnwrap(metadata.captureTime)
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 1)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 31)
        XCTAssertEqual(components.second, 22)
    }

    func test_iphoneHEIC_readsEXIF() throws {
        let metadata = try reader.readMetadata(at: fixture("iphone_sample", ext: "heic"))

        XCTAssertEqual(metadata.cameraMake, "Apple")
        XCTAssertEqual(metadata.cameraModel, "iPhone 17 Pro")
        XCTAssertNil(metadata.lensModel)
        XCTAssertNotNil(metadata.captureTime)
    }

    func test_noEXIFJPEG_returnsNilFields() throws {
        let metadata = try reader.readMetadata(at: fixture("noexif_sample", ext: "jpg"))

        XCTAssertNil(metadata.captureTime)
        XCTAssertNil(metadata.cameraMake)
        XCTAssertNil(metadata.cameraModel)
        XCTAssertNil(metadata.lensModel)
    }

    func test_nonImageFile_throws() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "not-an-image-\(UUID().uuidString).txt")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try reader.readMetadata(at: url))
    }
}
