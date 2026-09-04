import XCTest
@testable import PhotoName

/// 核心工作流串联：scan → read metadata → group assets → make plan（PRD §8 前半段）
final class RenameWorkflowTests: XCTestCase {
    private var workDir: URL!
    private var workflow: RenameWorkflow!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "workflow-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        workflow = RenameWorkflow()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    private func makeFile(_ name: String) throws {
        try "data".write(to: workDir.appending(path: name), atomically: true, encoding: .utf8)
    }

    private func copyFixture(_ name: String, as targetName: String) throws {
        let source = try XCTUnwrap(
            Bundle(for: type(of: self)).url(forResource: name, withExtension: "jpg"),
            "需要 \(name).jpg 夹具"
        )
        try FileManager.default.copyItem(at: source, to: workDir.appending(path: targetName))
    }

    func test_makePlan_scansGroupsAndPlansInOnePass() throws {
        try makeFile("DSC_0001.ARW")
        try makeFile("DSC_0001.JPG")
        try makeFile("DSC_0001.XMP")
        try makeFile("IMG_4821.HEIC")
        try makeFile("notes.txt") // 非摄影文件应被忽略

        let plan = try workflow.makePlan(
            directory: workDir,
            template: RenameTemplate(pattern: "{index}")
        )

        // 一组 RAW+JPEG+XMP = index 0001；独立 HEIC = index 0002
        XCTAssertEqual(plan.operations.map { $0.newURL.lastPathComponent }, [
            "0001.ARW", "0001.JPG", "0001.XMP",
            "0002.HEIC",
        ])
    }

    func test_makePlan_readsEXIFForTemplate() throws {
        // 带真实 EXIF 的夹具：Model=ILCE-7RM5, DateTimeOriginal=2026:09:01 10:31:22
        try copyFixture("sony_sample", as: "DSC_0001.JPG")

        let plan = try workflow.makePlan(
            directory: workDir,
            template: RenameTemplate(pattern: "{camera}_{YYYY}{MM}{DD}_{index}")
        )

        XCTAssertEqual(plan.operations.first?.newURL.lastPathComponent, "ILCE-7RM5_20260901_0001.JPG")
    }

    func test_makePlan_emptyDirectory_returnsEmptyPlan() throws {
        let plan = try workflow.makePlan(
            directory: workDir,
            template: RenameTemplate(pattern: "{index}")
        )
        XCTAssertTrue(plan.operations.isEmpty)
    }

    /// F-05 fallback 链：无 EXIF 时间的文件改用文件日期，不再抛错
    func test_makePlan_noEXIFTime_usesFallbackFileDate() throws {
        try copyFixture("noexif_sample", as: "DSC_0002.JPG")

        let plan = try workflow.makePlan(
            directory: workDir,
            template: RenameTemplate(pattern: "{YYYY}{MM}{DD}_{index}")
        )

        XCTAssertEqual(plan.operations.count, 1)
        // 来源必须被标记为非 EXIF（文件创建日期），供预检警示
        let assets = try workflow.loadAssets(directory: workDir)
        let metadata = workflow.readMetadata(for: assets)
        XCTAssertEqual(metadata[assets[0].id]?.captureTimeSource, .fileCreationDate)
    }

    func test_loadAssets_returnsGroupedAssets() throws {
        try makeFile("DSC_0001.ARW")
        try makeFile("DSC_0001.JPG")
        try makeFile("IMG_4821.HEIC")

        let assets = try workflow.loadAssets(directory: workDir)

        XCTAssertEqual(assets.count, 2)
    }
}
