import XCTest
@testable import PhotoName

final class CaptureTimeResolverTests: XCTestCase {
    private var workDir: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "time-resolver-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    private func makeFile(named name: String, created: Date? = nil, modified: Date? = nil) throws -> URL {
        let url = workDir.appending(path: name)
        try "data".write(to: url, atomically: true, encoding: .utf8)
        var attributes: [FileAttributeKey: Any] = [:]
        if let created { attributes[.creationDate] = created }
        if let modified { attributes[.modificationDate] = modified }
        if !attributes.isEmpty {
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        }
        return url
    }

    private var oldDate: Date { Date(timeIntervalSince1970: 1_000_000_000) } // 2001-09-09
    private var newerDate: Date { Date(timeIntervalSince1970: 1_600_000_000) } // 2020-09-13

    // MARK: - 回退顺序（PRD F-05：EXIF → Media Creation → File Creation → File Modification）

    func test_exifTimePresent_winsOverEverything() throws {
        let url = try makeFile(named: "a.ARW", created: oldDate, modified: newerDate)
        let resolver = CaptureTimeResolver()

        let resolved = resolver.resolve(url: url, exifTime: oldDate)

        XCTAssertEqual(resolved.source, .exif)
        XCTAssertEqual(resolved.date, oldDate)
    }

    func test_exifMissing_fileCreationDate_isUsed() throws {
        let url = try makeFile(named: "a.ARW", created: oldDate, modified: newerDate)
        let resolver = CaptureTimeResolver()

        let resolved = resolver.resolve(url: url, exifTime: nil)

        XCTAssertEqual(resolved.source, .fileCreationDate)
        XCTAssertEqual(resolved.date, oldDate)
    }

    /// 用注入的 provider 验证更深层回退（macOS 文件总有创建日期，真实文件系统造不出来）
    func test_fileCreationUnavailable_fallsToModificationDate() {
        let url = workDir.appending(path: "fake.ARW")
        let newer = newerDate
        let resolver = CaptureTimeResolver(providers: .init(
            mediaCreation: { _ in nil },
            fileCreation: { _ in nil },
            fileModification: { _ in newer }
        ))

        let resolved = resolver.resolve(url: url, exifTime: nil)

        XCTAssertEqual(resolved.source, .fileModificationDate)
        XCTAssertEqual(resolved.date, newer)
    }

    func test_mediaCreationDate_precedesFileCreation() {
        let url = workDir.appending(path: "fake.ARW")
        let older = oldDate
        let newer = newerDate
        let resolver = CaptureTimeResolver(providers: .init(
            mediaCreation: { _ in older },
            fileCreation: { _ in newer },
            fileModification: { _ in newer }
        ))

        let resolved = resolver.resolve(url: url, exifTime: nil)

        XCTAssertEqual(resolved.source, .mediaCreationDate)
        XCTAssertEqual(resolved.date, older)
    }

    func test_allSourcesUnavailable_isUnavailable() {
        let url = workDir.appending(path: "fake.ARW")
        let resolver = CaptureTimeResolver(providers: .init(
            mediaCreation: { _ in nil },
            fileCreation: { _ in nil },
            fileModification: { _ in nil }
        ))

        let resolved = resolver.resolve(url: url, exifTime: nil)

        XCTAssertEqual(resolved.source, .unavailable)
        XCTAssertNil(resolved.date)
    }
}
