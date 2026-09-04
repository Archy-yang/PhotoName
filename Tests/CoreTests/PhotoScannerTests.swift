import XCTest
@testable import PhotoName

final class PhotoScannerTests: XCTestCase {
    private var workDir: URL!
    private let scanner = PhotoScanner()

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "scanner-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    private func makeFile(_ relativePath: String) throws -> URL {
        let url = workDir.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "data".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func test_scan_flatDirectory_returnsOnlyPhotoFiles() throws {
        try makeFile("DSC_0001.ARW")
        try makeFile("DSC_0001.JPG")
        try makeFile("DSC_0001.XMP")
        try makeFile("notes.txt")
        try makeFile("readme.md")

        let resources = try scanner.scan(directory: workDir)

        XCTAssertEqual(resources.count, 3)
        XCTAssertEqual(Set(resources.map(\.kind)), [.raw, .jpeg, .xmp])
    }

    func test_scan_skipsHiddenFiles() throws {
        try makeFile("DSC_0001.ARW")
        try makeFile(".DS_Store")
        try makeFile("._DSC_0001.ARW") // AppleDouble 资源叉

        let resources = try scanner.scan(directory: workDir)

        XCTAssertEqual(resources.count, 1)
        XCTAssertEqual(resources.first?.originalFilename, "DSC_0001.ARW")
    }

    func test_scan_isRecursive_includesSubdirectories() throws {
        try makeFile("DCIM/100MSDCF/DSC_0001.ARW")
        try makeFile("DCIM/100MSDCF/DSC_0002.ARW")
        try makeFile("XMP/DSC_0001.XMP")

        let resources = try scanner.scan(directory: workDir)

        XCTAssertEqual(resources.count, 3)
        XCTAssertEqual(Set(resources.map(\.kind)), [.raw, .xmp])
    }

    func test_scan_resourceURLsPointToRealFiles() throws {
        try makeFile("DSC_0001.ARW")

        let resources = try scanner.scan(directory: workDir)

        XCTAssertEqual(resources.first?.url, workDir.appending(path: "DSC_0001.ARW"))
        XCTAssertEqual(resources.first?.fileSize, 4) // "data".utf8.count
    }

    func test_scan_nonexistentDirectory_throws() {
        let missing = workDir.appending(path: "does-not-exist")
        XCTAssertThrowsError(try scanner.scan(directory: missing))
    }

    func test_scan_emptyDirectory_returnsEmpty() throws {
        let resources = try scanner.scan(directory: workDir)
        XCTAssertTrue(resources.isEmpty)
    }
}
