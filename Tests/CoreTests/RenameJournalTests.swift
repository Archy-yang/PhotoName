import XCTest
@testable import PhotoName

final class RenameJournalTests: XCTestCase {
    private var journalFile: URL!

    override func setUp() {
        super.setUp()
        journalFile = FileManager.default.temporaryDirectory
            .appending(path: "journal-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: journalFile)
        super.tearDown()
    }

    func test_emptyJournal_returnsNoRecords() throws {
        let journal = RenameJournal(fileURL: journalFile)
        XCTAssertTrue(try journal.allRecords().isEmpty)
    }

    func test_append_thenReload_returnsAppendedRecord() throws {
        let journal = RenameJournal(fileURL: journalFile)
        let record = RenameRecord(
            timestamp: Date(timeIntervalSince1970: 0),
            originalPath: "/tmp/a/DSC_0001.ARW",
            newPath: "/tmp/a/20260902_0001.ARW"
        )

        try journal.append(record)

        let reloaded = RenameJournal(fileURL: journalFile)
        let records = try reloaded.allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.originalPath, "/tmp/a/DSC_0001.ARW")
        XCTAssertEqual(records.first?.newPath, "/tmp/a/20260902_0001.ARW")
    }

    func test_appendMultipleRecords_preservesOrder() throws {
        let journal = RenameJournal(fileURL: journalFile)
        try journal.append(RenameRecord(timestamp: Date(), originalPath: "/a/1.ARW", newPath: "/a/x.ARW"))
        try journal.append(RenameRecord(timestamp: Date(), originalPath: "/a/2.ARW", newPath: "/a/y.ARW"))

        let records = try journal.allRecords()
        XCTAssertEqual(records.map(\.originalPath), ["/a/1.ARW", "/a/2.ARW"])
    }

    func test_removeLast_returnsLastRecordAndRemovesIt() throws {
        let journal = RenameJournal(fileURL: journalFile)
        try journal.append(RenameRecord(timestamp: Date(), originalPath: "/a/1.ARW", newPath: "/a/x.ARW"))
        try journal.append(RenameRecord(timestamp: Date(), originalPath: "/a/2.ARW", newPath: "/a/y.ARW"))

        let removed = try journal.removeLast()
        XCTAssertEqual(removed?.originalPath, "/a/2.ARW")
        XCTAssertEqual(try journal.allRecords().map(\.originalPath), ["/a/1.ARW"])
    }

    func test_removeLast_onEmptyJournal_returnsNil() throws {
        let journal = RenameJournal(fileURL: journalFile)
        XCTAssertNil(try journal.removeLast())
    }

    // MARK: - 事务分组（批次级撤销的数据基础）

    private let batchID = UUID()
    private let otherBatchID = UUID()

    func test_transactions_groupRecordsByTransactionID() throws {
        let journal = RenameJournal(fileURL: journalFile)
        try journal.append(RenameRecord(transactionID: batchID, originalPath: "/a/1", newPath: "/a/x"))
        try journal.append(RenameRecord(transactionID: batchID, originalPath: "/a/2", newPath: "/a/y"))
        try journal.append(RenameRecord(transactionID: otherBatchID, originalPath: "/a/3", newPath: "/a/z"))

        let transactions = try journal.transactions()

        XCTAssertEqual(transactions.count, 2)
        XCTAssertEqual(transactions[0].map(\.originalPath), ["/a/1", "/a/2"])
        XCTAssertEqual(transactions[1].map(\.originalPath), ["/a/3"])
    }

    /// 旧格式记录（无 transactionID）每条自成一组，不能丢失
    func test_transactions_legacyRecords_withoutTransactionID_groupIndividually() throws {
        let journal = RenameJournal(fileURL: journalFile)
        try journal.append(RenameRecord(originalPath: "/a/1", newPath: "/a/x"))
        try journal.append(RenameRecord(originalPath: "/a/2", newPath: "/a/y"))

        XCTAssertEqual(try journal.transactions().count, 2)
    }

    func test_removeLastTransaction_removesAllRecordsOfThatBatch() throws {
        let journal = RenameJournal(fileURL: journalFile)
        try journal.append(RenameRecord(transactionID: batchID, originalPath: "/a/1", newPath: "/a/x"))
        try journal.append(RenameRecord(transactionID: batchID, originalPath: "/a/2", newPath: "/a/y"))
        try journal.append(RenameRecord(transactionID: otherBatchID, originalPath: "/a/3", newPath: "/a/z"))

        let removed = try journal.removeLastTransaction()

        XCTAssertEqual(removed?.map(\.originalPath), ["/a/3"])
        XCTAssertEqual(try journal.allRecords().map(\.originalPath), ["/a/1", "/a/2"])
    }

    /// 批量追加只写一次文件（大目录执行的 O(n²) I/O 修复）
    func test_appendBatch_writesAllRecordsOnce() throws {
        let journal = RenameJournal(fileURL: journalFile)
        let records = (1...500).map {
            RenameRecord(transactionID: batchID, originalPath: "/a/\($0)", newPath: "/a/x\($0)")
        }

        try journal.append(contentsOf: records)

        XCTAssertEqual(try journal.allRecords().count, 500)
        XCTAssertEqual(try journal.allRecords().last?.originalPath, "/a/500")
    }

    func test_appendBatch_empty_doesNothing() throws {
        let journal = RenameJournal(fileURL: journalFile)
        try journal.append(contentsOf: [])
        XCTAssertTrue(try journal.allRecords().isEmpty)
    }
}
