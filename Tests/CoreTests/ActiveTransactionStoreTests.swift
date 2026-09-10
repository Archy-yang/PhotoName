import XCTest
@testable import PhotoName

/// 活动事务标记：执行前写入完整操作清单，成功后删除。
/// 崩溃恢复的依据——Journal 记录可以因缓冲丢失，标记里的意图清单是完整的。
final class ActiveTransactionStoreTests: XCTestCase {
    private var workDir: URL!
    private var markerFile: URL!
    private var store: ActiveTransactionStore!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "active-txn-store-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        markerFile = workDir.appending(path: "active-transaction.json")
        store = ActiveTransactionStore(fileURL: markerFile)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    private func sampleTransaction() -> ActiveTransaction {
        ActiveTransaction(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_789_000_000),
            operations: [
                ActiveTransactionOperation(originalPath: "/shoot/a.ARW", newPath: "/shoot/20260908_0001.ARW", assetID: UUID()),
                ActiveTransactionOperation(originalPath: "/shoot/b.ARW", newPath: "/shoot/20260908_0002.ARW", assetID: nil),
            ]
        )
    }

    func test_save_thenLoad_roundTripsEqually() throws {
        let txn = sampleTransaction()
        try store.save(txn)
        XCTAssertEqual(try store.load(), txn)
    }

    func test_load_withoutMarkerFile_returnsNil() throws {
        XCTAssertNil(try store.load())
    }

    func test_clear_removesMarker() throws {
        try store.save(sampleTransaction())
        try store.clear()
        XCTAssertNil(try store.load())
    }

    func test_clear_withoutMarkerFile_doesNotThrow() throws {
        XCTAssertNoThrow(try store.clear())
    }

    func test_save_twice_latestWins() throws {
        let first = sampleTransaction()
        let second = sampleTransaction()
        try store.save(first)
        try store.save(second)
        XCTAssertEqual(try store.load(), second, "同时只应有一个活动标记，后写覆盖前写")
    }
}
