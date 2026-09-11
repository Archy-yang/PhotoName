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

    /// 创建真实文件并返回指向它的资产（Sequence 消解用例用）
    private func makeAssetWithFile(_ name: String) -> PhotoAsset {
        try? makeFile(name)
        let url = workDir.appending(path: name)
        return PhotoAsset(resources: [PhotoResource(url: url, kind: ResourceKind(fileExtension: (name as NSString).pathExtension))])
    }

    // MARK: - 阻塞级

    func test_destinationExists_isBlocking() throws {
        try makeFile("taken.ARW")
        let report = engine.run(plan: RenamePlan(operations: [operation("a.ARW", "taken.ARW")]))

        XCTAssertEqual(report.blockingIssues.count, 1)
        XCTAssertFalse(report.canExecute)
    }

    func test_duplicateTargetsInBatch_isBlocking() {
        let report = engine.run(
            plan: RenamePlan(operations: [operation("a.ARW", "same.ARW"), operation("b.ARW", "same.ARW")])
        )

        XCTAssertEqual(report.blockingIssues.count, 1)
        XCTAssertFalse(report.canExecute)
    }

    func test_illegalTargetName_isBlocking() {
        let report = engine.run(
            plan: RenamePlan(operations: [operation("a.ARW", "bad/name.ARW")])
        )

        XCTAssertTrue(report.blockingIssues.contains { $0.kind == .invalidTargetName })
    }

    // MARK: - Duplicate Timestamp 的 Sequence 消解（PRD F-09）：警告而非阻塞

    /// Planner 已用 -2/-3 消解同名 → 不再判批内重复阻塞，但必须显式告知用户（§12 Explicit Warning）
    func test_sequenceResolvedDuplicates_isWarningNotBlocking() throws {
        let first = makeAssetWithFile("DSC_0001.ARW")
        let second = makeAssetWithFile("DSC_0002.ARW")
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 10, minute: 31, second: 22))!
        let plan = try RenamePlanner().makePlan(
            assets: [first, second],
            metadata: [
                first.id: PhotoMetadata(captureTime: date),
                second.id: PhotoMetadata(captureTime: date),
            ],
            template: RenameTemplate(pattern: "{YYYY}{MM}{DD}_{HH}{mm}{ss}")
        )
        XCTAssertFalse(plan.sequenceResolvedAssetIDs.isEmpty, "前置：Planner 应已消解")

        let report = engine.run(plan: plan, assets: [first, second], metadata: [:])

        XCTAssertFalse(report.blockingIssues.contains { $0.kind == .duplicateDestination }, "已消解的同名不应阻塞")
        XCTAssertTrue(report.canExecute)
        XCTAssertEqual(report.warnings.filter { $0.kind == .duplicateTimestampResolved }.count, 1, "消解必须显式告知")
        // 消解后的文件真实存在于磁盘（makePlan 引用的目标不会已存在）
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.operations[1].newURL.path))
    }

    func test_nonWritableDirectory_isBlocking() throws {
        let readOnlyDir = workDir.appending(path: "readonly")
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnlyDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyDir.path)
        }

        // 原文件与目标都在只读目录中（重命名不跨目录，目标目录即只读目录）
        let op = RenameOperation(
            originalURL: readOnlyDir.appending(path: "a.ARW"),
            newURL: readOnlyDir.appending(path: "x.ARW")
        )

        let report = engine.run(plan: RenamePlan(operations: [op]))

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
        )

        XCTAssertEqual(report.warnings.filter { $0.kind == .missingSidecar }.count, 1)
        XCTAssertTrue(report.canExecute)
    }

    // MARK: - 正常路径

    func test_cleanPlan_hasNoIssues_andCanExecute() throws {
        try makeFile("a.ARW")
        let report = engine.run(
            plan: RenamePlan(operations: [operation("a.ARW", "x.ARW")])
        )

        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertTrue(report.canExecute)
    }

    /// 回归：子目录中的文件重命名（目标与源同目录）不应被误判为路径逃逸
    func test_subdirectoryRename_sameParent_notFlagged() throws {
        let subDir = workDir.appending(path: "DCIM/100SU")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "data".write(to: subDir.appending(path: "a.ARW"), atomically: true, encoding: .utf8)
        let op = RenameOperation(
            originalURL: subDir.appending(path: "a.ARW"),
            newURL: subDir.appending(path: "test_0001.ARW")
        )

        let report = engine.run(plan: RenamePlan(operations: [op]))

        XCTAssertTrue(report.canExecute, "同目录重命名不应被标记：\(report.issues)")
    }

    /// 目标跑到另一个目录才是非法（重命名不跨目录）
    func test_targetInDifferentDirectory_isInvalid() throws {
        let otherDir = workDir.appending(path: "elsewhere")
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        try makeFile("a.ARW")
        let op = RenameOperation(
            originalURL: workDir.appending(path: "a.ARW"),
            newURL: otherDir.appending(path: "x.ARW")
        )

        let report = engine.run(plan: RenamePlan(operations: [op]))

        XCTAssertTrue(report.blockingIssues.contains { $0.kind == .invalidTargetName })
    }
}
