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

    // MARK: - 恒等操作（目标 == 原路径）是 no-op，不得触发 Never Overwrite

    func test_execute_identityOperations_areSkippedAsNoOp() throws {
        try makeFile("20260902_0001.ARW")
        try makeFile("DSC_0042.ARW")
        let plan = RenamePlan(operations: [
            RenameOperation(
                originalURL: workDir.appending(path: "20260902_0001.ARW"),
                newURL: workDir.appending(path: "20260902_0001.ARW")
            ),
            RenameOperation(
                originalURL: workDir.appending(path: "DSC_0042.ARW"),
                newURL: workDir.appending(path: "20260902_0042.ARW")
            ),
        ])

        let count = try transaction.execute(plan)

        XCTAssertEqual(count, 1, "恒等操作不应计入执行数")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "20260902_0001.ARW").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDir.appending(path: "DSC_0042.ARW").path))
        XCTAssertEqual(try journal.allRecords().count, 1, "恒等操作不写 Journal")
    }

    // MARK: - 活动标记（Crash Recovery：执行前写意图清单，成功后清除）

    private func makeTransaction(activeStore: ActiveTransactionStore) -> RenameTransaction {
        RenameTransaction(journal: journal, activeStore: activeStore)
    }

    func test_execute_success_clearsActiveMarker() throws {
        try makeFile("a.ARW")
        let store = ActiveTransactionStore(fileURL: workDir.appending(path: "active.json"))
        try makeTransaction(activeStore: store).execute(plan(originalNames: ["a.ARW"], newNames: ["x.ARW"]))
        XCTAssertNil(try store.load(), "执行成功后标记必须清除")
    }

    /// 模拟执行中断途崩溃：后续操作源文件缺失 → moveItem 抛错 →
    /// 标记留存，Journal 记录还在缓冲里未落盘（最坏情况），恢复只能靠标记调和
    func test_execute_failsMidway_markerRemainsAndReconciles() throws {
        try makeFile("a.ARW")
        // b.ARW 故意不创建
        let failingPlan = plan(originalNames: ["a.ARW", "b.ARW"], newNames: ["x.ARW", "y.ARW"])
        let store = ActiveTransactionStore(fileURL: workDir.appending(path: "active.json"))
        let crashing = makeTransaction(activeStore: store)

        XCTAssertThrowsError(try crashing.execute(failingPlan))

        let marker = try XCTUnwrap(try store.load(), "中断后标记必须留存")
        XCTAssertEqual(marker.operations.count, 2, "标记应包含完整意图清单")

        // 靠标记（而非 Journal）就能还原现场：a→x 已完成；b→y 因源文件缺失归入冲突，不自动处理
        let batch = try RecoveryEngine().reconcile(marker)
        XCTAssertEqual(batch.completed.map(\.newPath), [workDir.appending(path: "x.ARW").path])
        XCTAssertEqual(batch.pending.count, 0)
        XCTAssertEqual(batch.conflicts.count, 1)
    }

    /// 预检失败（目标已存在）发生在任何文件被触碰之前，不留标记
    func test_execute_preflightFails_leavesNoMarker() throws {
        try makeFile("a.ARW")
        try makeFile("x.ARW")
        let store = ActiveTransactionStore(fileURL: workDir.appending(path: "active.json"))
        XCTAssertThrowsError(try makeTransaction(activeStore: store).execute(plan(originalNames: ["a.ARW"], newNames: ["x.ARW"])))
        XCTAssertNil(try store.load())
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
