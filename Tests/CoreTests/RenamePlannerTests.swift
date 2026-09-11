import XCTest
@testable import PhotoName

final class RenamePlannerTests: XCTestCase {
    private let planner = RenamePlanner()
    private let renderer = TemplateRenderer()

    private var sampleDate: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 2
        components.hour = 10; components.minute = 31; components.second = 22
        return Calendar.current.date(from: components)!
    }

    private func resource(_ name: String) -> PhotoResource {
        let url = URL(fileURLWithPath: "/shoot/\(name)")
        return PhotoResource(url: url, kind: ResourceKind(fileExtension: (name as NSString).pathExtension))
    }

    private func asset(_ names: [String]) -> PhotoAsset {
        PhotoAsset(resources: names.map(resource))
    }

    func test_plan_preservesExtensionPerResource() throws {
        let group = asset(["DSC_0001.ARW", "DSC_0001.JPG", "DSC_0001.XMP"])
        let plan = try planner.makePlan(
            assets: [group],
            metadata: [group.id: PhotoMetadata(captureTime: sampleDate)],
            template: RenameTemplate(pattern: "{YYYY}{MM}{DD}_{index}")
        )

        XCTAssertEqual(plan.operations.map { $0.newURL.lastPathComponent }, [
            "20260902_0001.ARW", "20260902_0001.JPG", "20260902_0001.XMP",
        ])
        XCTAssertEqual(plan.operations.map { $0.originalURL.lastPathComponent }, [
            "DSC_0001.ARW", "DSC_0001.JPG", "DSC_0001.XMP",
        ])
    }

    func test_plan_indexIncrementsPerAsset_notPerResource() throws {
        let first = asset(["DSC_0001.ARW", "DSC_0001.JPG"])
        let second = asset(["DSC_0002.ARW"])
        let plan = try planner.makePlan(
            assets: [first, second],
            metadata: [first.id: PhotoMetadata(captureTime: sampleDate), second.id: PhotoMetadata(captureTime: sampleDate)],
            template: RenameTemplate(pattern: "{index}")
        )

        let newNames = plan.operations.map { $0.newURL.lastPathComponent }
        XCTAssertEqual(newNames, ["0001.ARW", "0001.JPG", "0002.ARW"])
    }

    func test_plan_usesMetadataPerAsset() throws {
        let sony = asset(["DSC_0001.ARW"])
        let iphone = asset(["IMG_0002.HEIC"])
        let plan = try planner.makePlan(
            assets: [sony, iphone],
            metadata: [
                sony.id: PhotoMetadata(captureTime: sampleDate, cameraModel: "ILCE-7RM5"),
                iphone.id: PhotoMetadata(captureTime: sampleDate, cameraModel: "iPhone 17 Pro"),
            ],
            template: RenameTemplate(pattern: "{camera}_{index}")
        )

        let newNames = plan.operations.map { $0.newURL.lastPathComponent }
        XCTAssertEqual(newNames, ["ILCE-7RM5_0001.ARW", "iPhone 17 Pro_0002.HEIC"])
    }

    func test_plan_startingIndexDefaultsToOne_andIsConfigurable() throws {
        let only = asset(["DSC_0001.ARW"])
        let plan = try planner.makePlan(
            assets: [only],
            metadata: [only.id: PhotoMetadata()],
            template: RenameTemplate(pattern: "{index}"),
            startingIndex: 100
        )

        XCTAssertEqual(plan.operations.first?.newURL.lastPathComponent, "0100.ARW")
    }

    func test_plan_originalVariable_usesStemOfFirstResource() throws {
        let group = asset(["DSC_0001.ARW", "DSC_0001.JPG"])
        let plan = try planner.makePlan(
            assets: [group],
            metadata: [group.id: PhotoMetadata()],
            template: RenameTemplate(pattern: "kept-{original}")
        )

        XCTAssertEqual(plan.operations.map { $0.newURL.lastPathComponent }, [
            "kept-DSC_0001.ARW", "kept-DSC_0001.JPG",
        ])
    }

    func test_plan_missingCaptureTime_throws() {
        let only = asset(["DSC_0001.ARW"])
        XCTAssertThrowsError(
            try planner.makePlan(
                assets: [only],
                metadata: [only.id: PhotoMetadata()],
                template: RenameTemplate(pattern: "{YYYY}_{index}")
            )
        ) { error in
            XCTAssertEqual(error as? TemplateError, .missingCaptureTime)
        }
    }

    func test_plan_rendererIsConsistentWithPlannerOutput() throws {
        let group = asset(["DSC_0001.ARW"])
        let context = TemplateContext(captureTime: sampleDate, originalBaseName: "DSC_0001")
        let rendered = try renderer.render(RenameTemplate(pattern: "{YYYY}_{index}"), context: context, index: 1)
        let plan = try planner.makePlan(
            assets: [group],
            metadata: [group.id: PhotoMetadata(captureTime: sampleDate)],
            template: RenameTemplate(pattern: "{YYYY}_{index}")
        )
        XCTAssertEqual(plan.operations.first?.newURL.lastPathComponent, "\(rendered).ARW")
    }

    // MARK: - 恒等操作过滤（改名成自己的名字是 no-op，不是冲突）

    /// 已按模板命名过的目录再次预览：不应产生任何操作，也不应触发"目标已存在"阻塞
    func test_plan_identityRename_producesNoOperations() throws {
        let group = asset(["20260902_0001.ARW", "20260902_0001.JPG", "20260902_0001.XMP"])
        let plan = try planner.makePlan(
            assets: [group],
            metadata: [group.id: PhotoMetadata(captureTime: sampleDate)],
            template: RenameTemplate(pattern: "{YYYY}{MM}{DD}_{index}")
        )
        XCTAssertTrue(plan.operations.isEmpty, "恒等重命名应被过滤")
    }

    /// 混合目录：只有真正需要改名的文件进入方案
    func test_plan_mixedBatch_keepsOnlyRealRenames() throws {
        let alreadyNamed = asset(["20260902_0001.ARW"])
        let notNamed = asset(["DSC_0042.ARW"])
        let plan = try planner.makePlan(
            assets: [alreadyNamed, notNamed],
            metadata: [
                alreadyNamed.id: PhotoMetadata(captureTime: sampleDate),
                notNamed.id: PhotoMetadata(captureTime: sampleDate),
            ],
            template: RenameTemplate(pattern: "{YYYY}{MM}{DD}_{index}")
        )
        XCTAssertEqual(plan.operations.count, 1)
        XCTAssertEqual(plan.operations.first?.originalURL.lastPathComponent, "DSC_0042.ARW")
    }

    // MARK: - Duplicate Timestamp 的 Sequence 消解（PRD F-09）

    /// 连拍同秒 + 模板无 {index}：第二个同名资产自动追加 -2（第一个保持干净名）
    func test_plan_duplicateTimestamps_secondAssetGetsSequenceSuffix() throws {
        let first = asset(["DSC_0001.ARW"])
        let second = asset(["DSC_0002.ARW"])
        let plan = try planner.makePlan(
            assets: [first, second],
            metadata: [
                first.id: PhotoMetadata(captureTime: sampleDate),
                second.id: PhotoMetadata(captureTime: sampleDate),
            ],
            template: RenameTemplate(pattern: "{YYYY}{MM}{DD}_{HH}{mm}{ss}")
        )
        XCTAssertEqual(plan.operations.map { $0.newURL.lastPathComponent }, [
            "20260902_103122.ARW",
            "20260902_103122-2.ARW",
        ])
        XCTAssertEqual(plan.sequenceResolvedAssetIDs, [second.id])
    }

    /// 第三组继续递增 -3
    func test_plan_tripleDuplicates_incrementSequence() throws {
        let assets = (1...3).map { asset(["DSC_000\($0).ARW"]) }
        let plan = try planner.makePlan(
            assets: assets,
            metadata: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, PhotoMetadata(captureTime: sampleDate)) }),
            template: RenameTemplate(pattern: "{YYYY}{MM}{DD}_{HH}{mm}{ss}")
        )
        XCTAssertEqual(plan.operations.map { $0.newURL.lastPathComponent }, [
            "20260902_103122.ARW",
            "20260902_103122-2.ARW",
            "20260902_103122-3.ARW",
        ])
    }

    /// 序号后缀整组原子：同资产的 ARW/JPG 共用同一后缀（Asset Atomicity）
    func test_plan_sequenceSuffix_isGroupAtomic() throws {
        let first = asset(["DSC_0001.ARW"])
        let second = asset(["DSC_0002.ARW", "DSC_0002.JPG", "DSC_0002.XMP"])
        let plan = try planner.makePlan(
            assets: [first, second],
            metadata: [
                first.id: PhotoMetadata(captureTime: sampleDate),
                second.id: PhotoMetadata(captureTime: sampleDate),
            ],
            template: RenameTemplate(pattern: "{YYYY}{MM}{DD}_{HH}{mm}{ss}")
        )
        XCTAssertEqual(plan.operations.map { $0.newURL.lastPathComponent }, [
            "20260902_103122.ARW",
            "20260902_103122-2.ARW",
            "20260902_103122-2.JPG",
            "20260902_103122-2.XMP",
        ])
    }

    /// 拍摄时间不同：不触发序号，干净输出
    func test_plan_distinctTimestamps_noSequenceApplied() throws {
        let first = asset(["DSC_0001.ARW"])
        let second = asset(["DSC_0002.ARW"])
        var nextSecond = DateComponents()
        nextSecond.year = 2026; nextSecond.month = 9; nextSecond.day = 2
        nextSecond.hour = 10; nextSecond.minute = 31; nextSecond.second = 23
        let later = Calendar.current.date(from: nextSecond)!

        let plan = try planner.makePlan(
            assets: [first, second],
            metadata: [
                first.id: PhotoMetadata(captureTime: sampleDate),
                second.id: PhotoMetadata(captureTime: later),
            ],
            template: RenameTemplate(pattern: "{YYYY}{MM}{DD}_{HH}{mm}{ss}")
        )
        XCTAssertEqual(plan.operations.map { $0.newURL.lastPathComponent }, [
            "20260902_103122.ARW",
            "20260902_103123.ARW",
        ])
        XCTAssertTrue(plan.sequenceResolvedAssetIDs.isEmpty)
    }
}
