import XCTest
@testable import PhotoName

final class RenameTransactionTests: XCTestCase {
    private var workDir: URL!
    private var journalFile: URL!
    private var journal: RenameJournal!
    private var transaction: RenameTransaction!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "rename-transaction-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        journalFile = workDir.appending(path: "journal.json")
        journal = RenameJournal(fileURL: journalFile)
        transaction = RenameTransaction(journal: journal)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = workDir.appending(path: name)
        try "data".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func plan(originalNames: [String], newNames: [String]) -> RenamePlan {
        let operations = zip(originalNames, newNames).map { original, new in
            RenameOperation(originalURL: workDir.appending(path: original), newURL: workDir.appending(path: new))
        }
        return RenamePlan(operations: operations)
    }

    // MARK: - 执行

    func test_execute_renamesAllFilesAndJournalsEachOperation() throws {
        try makeFile("DSC_0001.ARW")
        try makeFile("DSC_0001.JPG")
        let plan = plan(originalNames: ["DSC_0001.ARW", "DSC_0001.JPG"], newNames: ["20260902_0001.ARW", "20260902_0001.JPG"])

        let count = try transaction.execute(plan)

        XCTAssertEqual(count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDir.appending(path: "DSC_0001.ARW").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "20260902_0001.ARW").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "20260902_0001.JPG").path))
        XCTAssertEqual(try journal.allRecords().count, 2)
    }

    // MARK: - Never Overwrite（全量预检，任一冲突则整体不动）

    func test_execute_destinationExists_throwsBeforeTouchingAnyFile() throws {
        try makeFile("DSC_0001.ARW")
        try makeFile("DSC_0002.ARW")
        try makeFile("20260902_0002.ARW") // 第二个操作的目标已存在
        let plan = plan(originalNames: ["DSC_0001.ARW", "DSC_0002.ARW"], newNames: ["20260902_0001.ARW", "20260902_0002.ARW"])

        XCTAssertThrowsError(try transaction.execute(plan)) { error in
            XCTAssertEqual(error as? RenameError, .destinationExists)
        }

        // 所有文件保持原样，Journal 为空
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "DSC_0001.ARW").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "DSC_0002.ARW").path))
        XCTAssertTrue(try journal.allRecords().isEmpty)
    }

    // MARK: - 批内目标重复检测

    func test_execute_duplicateTargetsInBatch_throwsBeforeTouchingAnyFile() throws {
        try makeFile("DSC_0001.ARW")
        try makeFile("DSC_0002.ARW")
        // 模板不含 index：两个操作的目标相同
        let plan = plan(originalNames: ["DSC_0001.ARW", "DSC_0002.ARW"], newNames: ["same.ARW", "same.ARW"])

        XCTAssertThrowsError(try transaction.execute(plan)) { error in
            XCTAssertEqual(error as? RenameError, .duplicateDestinationInBatch)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "DSC_0001.ARW").path))
        XCTAssertTrue(try journal.allRecords().isEmpty)
    }

    // MARK: - 执行进度

    /// @Sendable 回调的线程安全收集器
    private final class ProgressCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var reports: [(done: Int, total: Int)] = []
        func append(_ done: Int, _ total: Int) {
            lock.lock(); reports.append((done, total)); lock.unlock()
        }
        var value: [(done: Int, total: Int)] {
            lock.lock(); defer { lock.unlock() }; return reports
        }
    }

    func test_execute_reportsMonotonicProgress() throws {
        try makeFile("a.ARW")
        try makeFile("b.ARW")
        try makeFile("c.ARW")
        let plan = plan(originalNames: ["a.ARW", "b.ARW", "c.ARW"], newNames: ["x.ARW", "y.ARW", "z.ARW"])

        let collector = ProgressCollector()
        try transaction.execute(plan) { done, total in
            collector.append(done, total)
        }

        let reports = collector.value
        XCTAssertEqual(reports.last?.total, 3, "总数应为操作数")
        XCTAssertEqual(reports.last?.done, 3, "最后应报告完成全部")
        for (prev, next) in zip(reports, reports.dropFirst()) {
            XCTAssertLessThan(prev.done, next.done, "进度必须单调递增")
        }
    }

    // MARK: - 撤销联动

    func test_execute_thenUndoLast_restoresOneOperation() throws {
        try makeFile("DSC_0001.ARW")
        try makeFile("DSC_0002.ARW")
        let plan = plan(originalNames: ["DSC_0001.ARW", "DSC_0002.ARW"], newNames: ["20260902_0001.ARW", "20260902_0002.ARW"])
        try transaction.execute(plan)

        let engine = RenameEngine(journal: journal)
        let restored = try engine.undoLast()

        XCTAssertEqual(restored, workDir.appending(path: "DSC_0002.ARW"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDir.appending(path: "20260902_0002.ARW").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "DSC_0002.ARW").path))
        XCTAssertEqual(try journal.allRecords().count, 1)
    }

    func test_execute_emptyPlan_succeedsWithZeroCount() throws {
        XCTAssertEqual(try transaction.execute(RenamePlan(operations: [])), 0)
        XCTAssertTrue(try journal.allRecords().isEmpty)
    }

    // MARK: - 批次级撤销（一次操作整体回退）

    func test_execute_thenUndoLastBatch_restoresAllFilesAndClearsBatch() throws {
        try makeFile("DSC_0001.ARW")
        try makeFile("DSC_0001.JPG")
        try makeFile("DSC_0002.ARW")
        let plan = plan(
            originalNames: ["DSC_0001.ARW", "DSC_0001.JPG", "DSC_0002.ARW"],
            newNames: ["20260902_0001.ARW", "20260902_0001.JPG", "20260902_0002.ARW"]
        )
        try transaction.execute(plan)

        let engine = RenameEngine(journal: journal)
        let restored = try engine.undoLastBatch()

        XCTAssertEqual(restored.count, 3)
        for original in ["DSC_0001.ARW", "DSC_0001.JPG", "DSC_0002.ARW"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: original).path), "\(original) 应恢复")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDir.appending(path: "20260902_0001.ARW").path))
        XCTAssertTrue(try journal.allRecords().isEmpty)
    }

    /// 跨批次只能逆序撤：撤销"上一批"只能回退最后一批，更早的批次不动
    func test_undoLastBatch_withTwoBatches_restoresOnlyNewestBatch() throws {
        try makeFile("a.ARW")
        try makeFile("b.ARW")
        try transaction.execute(plan(originalNames: ["a.ARW"], newNames: ["x.ARW"]))
        try transaction.execute(plan(originalNames: ["b.ARW"], newNames: ["y.ARW"]))

        let engine = RenameEngine(journal: journal)
        let restored = try engine.undoLastBatch()

        XCTAssertEqual(restored, [workDir.appending(path: "b.ARW")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "x.ARW").path), "更早批次的结果不应被动")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "b.ARW").path))
    }

    // MARK: - 资产级撤销（Asset Atomicity：整组回退，不做单文件级）

    private let assetOne = PhotoAsset(resources: [])
    private let assetTwo = PhotoAsset(resources: [])

    func test_execute_thenUndoAsset_restoresWholeAssetGroup() throws {
        try makeFile("DSC_0001.ARW")
        try makeFile("DSC_0001.JPG")
        try makeFile("DSC_0002.ARW")
        let plan = RenamePlan(operations: [
            RenameOperation(originalURL: workDir.appending(path: "DSC_0001.ARW"), newURL: workDir.appending(path: "20260902_0001.ARW"), assetID: assetOne.id),
            RenameOperation(originalURL: workDir.appending(path: "DSC_0001.JPG"), newURL: workDir.appending(path: "20260902_0001.JPG"), assetID: assetOne.id),
            RenameOperation(originalURL: workDir.appending(path: "DSC_0002.ARW"), newURL: workDir.appending(path: "20260902_0002.ARW"), assetID: assetTwo.id),
        ])
        try transaction.execute(plan)

        let engine = RenameEngine(journal: journal)
        let restored = try engine.undoAsset(assetOne.id)

        XCTAssertEqual(Set(restored.map(\.lastPathComponent)), ["DSC_0001.ARW", "DSC_0001.JPG"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "20260902_0002.ARW").path), "其他资产不应被动")
        XCTAssertEqual(try journal.allRecords().count, 1, "只移除该资产的记录")
    }
}
