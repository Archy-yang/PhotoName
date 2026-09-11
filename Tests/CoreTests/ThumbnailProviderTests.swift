import XCTest
import CoreGraphics
@testable import PhotoName

/// 资产网格缩略图：CGImageSource 生成受限尺寸的预览图。
/// 真实 RAW 的可解码性取决于系统 RAW 支持（运行时验证）；此处固化解码规则与占位行为。
final class ThumbnailProviderTests: XCTestCase {
    private let provider = ThumbnailProvider()

    private func fixture(_ name: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: name, withExtension: nil)
            ?? bundle.url(forResource: (name as NSString).deletingPathExtension,
                          withExtension: (name as NSString).pathExtension)
        return try XCTUnwrap(url, "夹具 \(name) 应存在于 Tests/Fixtures")
    }

    func test_jpegFixture_generatesThumbnailWithinMaxPixelSize() throws {
        let image = try XCTUnwrap(provider.thumbnail(for: fixture("sony_sample.jpg"), maxPixelSize: 320))
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertLessThanOrEqual(max(image.width, image.height), 320, "长边不得超过 maxPixelSize")
    }

    func test_heicFixture_generatesThumbnail() throws {
        let image = try XCTUnwrap(provider.thumbnail(for: fixture("iphone_sample.heic"), maxPixelSize: 320))
        XCTAssertGreaterThan(image.width, 0)
    }

    /// XMP 等非图像文件（或损坏文件）必须返回 nil，UI 展示占位图而非崩溃
    func test_nonImageFile_returnsNil() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "thumbnail-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fake = dir.appending(path: "fake.ARW")
        try "not an image".write(to: fake, atomically: true, encoding: .utf8)

        XCTAssertNil(provider.thumbnail(for: fake, maxPixelSize: 320))
    }

    func test_missingFile_returnsNil() throws {
        XCTAssertNil(provider.thumbnail(for: URL(filePath: "/nonexistent/photo.jpg"), maxPixelSize: 320))
    }
}
