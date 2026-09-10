import XCTest
@testable import PhotoName

/// 崩溃恢复：拿活动标记里的意图清单对照磁盘真实状态（调和），
/// 并支持把"已完成但未记账"的部分逆序回退。
final class RecoveryEngineTests: XCTestCase {
    private var workDir: URL!
    private var journalFile: URL!
    private var journal: RenameJournal!
    private let engine = RecoveryEngine()

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "recovery-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        journalFile = workDir.appending(path: "journal.json")
        journal = RenameJournal(fileURL: journalFile)
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

    private func op(_ original: String, _ new: String) -> ActiveTransactionOperation {
        ActiveTransactionOperation(
            originalPath: workDir.appending(path: original).path,
            newPath: workDir.appending(path: new).path
        )
    }

    // MARK: - 调和（reconcile）

    func test_reconcile_classifiesDoneAndPendingByFilesystemState() throws {
        // a 已改名完成（x 存在，a 不存在）；b 未执行（b 存在）
        try makeFile("x.ARW")
        try makeFile("b.ARW")
        let txn = ActiveTransaction(id: UUID(), startedAt: Date(), operations: [
            op("a.ARW", "x.ARW"),
            op("b.ARW", "y.ARW"),
        ])

        let batch = try engine.reconcile(txn)

        XCTAssertEqual(batch.completed.map(\.newPath), [txn.operations[0].newPath], "目标已存在且源已消失 → 已完成")
        XCTAssertEqual(batch.pending.map(\.originalPath), [txn.operations[1].originalPath], "源仍在 → 未执行")
        XCTAssertTrue(batch.conflicts.isEmpty)
    }

    /// 源和目标同时存在是危险状态（可能是外部文件恰好同名），绝不自动回退
    func test_reconcile_sourceAndTargetBothExist_isConflict() throws {
        try makeFile("a.ARW")
        try makeFile("x.ARW")
        let txn = ActiveTransaction(id: UUID(), startedAt: Date(), operations: [op("a.ARW", "x.ARW")])

        let batch = try engine.reconcile(txn)

        XCTAssertEqual(batch.conflicts.count, 1)
        XCTAssertTrue(batch.completed.isEmpty)
        XCTAssertTrue(batch.pending.isEmpty)
    }

    func test_reconcile_sourceAndTargetBothMissing_isConflict() throws {
        let txn = ActiveTransaction(id: UUID(), startedAt: Date(), operations: [op("gone.ARW", "also-gone.ARW")])

        let batch = try engine.reconcile(txn)

        XCTAssertEqual(batch.conflicts.count, 1)
    }

    // MARK: - 回退（rollback）

    func test_rollback_restoresCompletedInReverse_andRemovesMarkerAndJournalRecords() throws {
        let store = ActiveTransactionStore(fileURL: workDir.appending(path: "active.json"))
        // 中断现场：a→x 已完成，b→y 未执行；Journal 记录因缓冲丢失（模拟最坏情况）
        try makeFile("x.ARW")
        try makeFile("y.ARW") // 第二个也完成了，验证逆序回退
        let txn = ActiveTransaction(id: UUID(), startedAt: Date(), operations: [
            op("a.ARW", "x.ARW"),
            op("b.ARW", "y.ARW"),
        ])
        try store.save(txn)
        // Journal 里有部分记录（缓冲恰好刷过一批）
        try journal.append(RenameRecord(transactionID: txn.id, originalPath: txn.operations[0].originalPath, newPath: txn.operations[0].newPath))

        let batch = try engine.reconcile(txn)
        let restored = try engine.rollback(batch, journal: journal, activeStore: store)

        XCTAssertEqual(restored, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "a.ARW").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "b.ARW").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDir.appending(path: "x.ARW").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDir.appending(path: "y.ARW").path))
        XCTAssertNil(try store.load(), "回退后标记必须清除，否则下次启动再次报中断")
        XCTAssertTrue(try journal.allRecords().isEmpty, "该批次的 Journal 记录应一并清理")
    }

    /// 冲突操作不回退，其余照常回退（Safe First：拿不准的绝不动）
    func test_rollback_skipsConflicts_andRestoresTheRest() throws {
        try makeFile("x.ARW")   // 已完成
        try makeFile("a.ARW")   // 冲突：源也回来了（用户手动恢复过）
        try makeFile("b.ARW")   // 未执行
        let txn = ActiveTransaction(id: UUID(), startedAt: Date(), operations: [
            op("a.ARW", "x.ARW"),
            op("b.ARW", "y.ARW"),
        ])

        let batch = try engine.reconcile(txn)
        let restored = try engine.rollback(batch, journal: journal, activeStore: ActiveTransactionStore(fileURL: workDir.appending(path: "active.json")))

        XCTAssertEqual(restored, 0, "唯一可回退的是冲突操作，跳过")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "x.ARW").path), "冲突操作不动")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "a.ARW").path), "冲突操作不动")
    }
}
