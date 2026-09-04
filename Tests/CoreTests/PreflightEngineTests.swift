import XCTest
@testable import PhotoName

final class PreflightEngineTests: XCTestCase {
    private var workDir: URL!
    private let engine = PreflightEngine()

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "preflight-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        try? FileManager.default.removeItem(at: workDir.appending(path: ".."))
        super.tearDown()
    }

    private func makeFile(_ name: String) throws {
        try "data".write(to: workDir.appending(path: name), atomically: true, encoding: .utf8)
    }

    private func operation(_ original: String, _ new: String) -> RenameOperation {
        RenameOperation(originalURL: workDir.appending(path: original), newURL: workDir.appending(path: new))
    }

    // MARK: - 阻塞级

    func test_destinationExists_isBlocking() throws {
        try makeFile("taken.ARW")
        let report = engine.run(plan: RenamePlan(operations: [operation("a.ARW", "taken.ARW")]), destinationDirectory: workDir)

        XCTAssertEqual(report.blockingIssues.count, 1)
        XCTAssertFalse(report.canExecute)
    }

    func test_duplicateTargetsInBatch_isBlocking() {
        let report = engine.run(
            plan: RenamePlan(operations: [operation("a.ARW", "same.ARW"), operation("b.ARW", "same.ARW")]),
            destinationDirectory: workDir
        )

        XCTAssertEqual(report.blockingIssues.count, 1)
        XCTAssertFalse(report.canExecute)
    }

    func test_illegalTargetName_isBlocking() {
        let report = engine.run(
            plan: RenamePlan(operations: [operation("a.ARW", "bad/name.ARW")]),
            destinationDirectory: workDir
        )

        XCTAssertTrue(report.blockingIssues.contains { $0.kind == .invalidTargetName })
    }

    func test_nonWritableDirectory_isBlocking() throws {
        let readOnlyDir = workDir.appending(path: "readonly")
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnlyDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyDir.path)
        }

        let report = engine.run(
            plan: RenamePlan(operations: [operation("a.ARW", "x.ARW")]),
            destinationDirectory: readOnlyDir
        )

        XCTAssertTrue(report.blockingIssues.contains { $0.kind == .folderNotWritable })
        XCTAssertFalse(report.canExecute)
    }

    // MARK: - 警告级

    func test_missingCaptureTime_isWarning_notBlocking() {
        let asset = PhotoAsset(resources: [PhotoResource(url: workDir.appending(path: "a.ARW"), kind: .raw)])
        let report = engine.run(
            plan: RenamePlan(operations: [operation("a.ARW", "0001.ARW")]),
            assets: [asset],
            metadata: [asset.id: PhotoMetadata(captureTime: nil)],
            destinationDirectory: workDir
        )

        XCTAssertTrue(report.warnings.contains { $0.kind == .missingCaptureTime })
        XCTAssertTrue(report.canExecute, "警告不应阻塞执行")
    }

    /// PRD F-05：用了文件日期 fallback 必须显式警示
    func test_fallbackCaptureTime_isWarning_withSourceLabel() {
        let asset = PhotoAsset(resources: [PhotoResource(url: workDir.appending(path: "a.ARW"), kind: .raw)])
        let report = engine.run(
            plan: RenamePlan(operations: [operation("a.ARW", "0001.ARW")]),
            assets: [asset],
            metadata: [asset.id: PhotoMetadata(captureTime: Date(), captureTimeSource: .fileCreationDate)],
            destinationDirectory: workDir
        )

        let fallbackWarnings = report.warnings.filter { $0.kind == .fallbackCaptureTime }
        XCTAssertEqual(fallbackWarnings.count, 1)
        XCTAssertTrue(fallbackWarnings[0].message.contains("文件创建日期"), "警告应标明具体 fallback 来源")
        XCTAssertTrue(report.canExecute)
    }

    func test_exifCaptureTime_producesNoFallbackWarning() {
        let asset = PhotoAsset(resources: [PhotoResource(url: workDir.appending(path: "a.ARW"), kind: .raw)])
        let report = engine.run(
            plan: RenamePlan(operations: []),
            assets: [asset],
            metadata: [asset.id: PhotoMetadata(captureTime: Date(), captureTimeSource: .exif)],
            destinationDirectory: workDir
        )

        XCTAssertFalse(report.warnings.contains { $0.kind == .fallbackCaptureTime })
        XCTAssertFalse(report.warnings.contains { $0.kind == .missingCaptureTime })
    }

    func test_rawOrJpegWithoutXMP_isWarning() {
        let withXMP = PhotoAsset(resources: [
            PhotoResource(url: workDir.appending(path: "a.ARW"), kind: .raw),
            PhotoResource(url: workDir.appending(path: "a.XMP"), kind: .xmp),
        ])
        let withoutXMP = PhotoAsset(resources: [PhotoResource(url: workDir.appending(path: "b.ARW"), kind: .raw)])
        let report = engine.run(
            plan: RenamePlan(operations: []),
            assets: [withXMP, withoutXMP],
            metadata: [:],
            destinationDirectory: workDir
        )

        XCTAssertEqual(report.warnings.filter { $0.kind == .missingSidecar }.count, 1)
        XCTAssertTrue(report.canExecute)
    }

    // MARK: - 正常路径

    func test_cleanPlan_hasNoIssues_andCanExecute() throws {
        try makeFile("a.ARW")
        let report = engine.run(
            plan: RenamePlan(operations: [operation("a.ARW", "x.ARW")]),
            destinationDirectory: workDir
        )

        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertTrue(report.canExecute)
    }
}
