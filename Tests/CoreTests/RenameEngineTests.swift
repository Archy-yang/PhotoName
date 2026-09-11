import XCTest
@testable import PhotoName

final class RenameEngineTests: XCTestCase {
    private var workDir: URL!
    private var journalFile: URL!
    private var engine: RenameEngine!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appending(path: "rename-engine-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        journalFile = workDir.appending(path: "journal.json")
        engine = RenameEngine(journal: RenameJournal(fileURL: journalFile))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    // MARK: - rename

    func test_rename_movesFileToNewName() throws {
        let original = try makeFile(named: "DSC_0001.ARW", content: "raw-data")

        let newURL = try engine.rename(original, to: "20260902_0001.ARW")

        XCTAssertEqual(newURL.lastPathComponent, "20260902_0001.ARW")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(try String(contentsOf: newURL, encoding: .utf8), "raw-data")
    }

    func test_rename_recordsJournalEntry() throws {
        let original = try makeFile(named: "DSC_0001.ARW", content: "")

        _ = try engine.rename(original, to: "20260902_0001.ARW")

        let records = try engine.journal.allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].originalPath, original.path)
        XCTAssertEqual(records[0].newPath, workDir.appending(path: "20260902_0001.ARW").path)
    }

    /// Never Overwrite：目标已存在时必须拒绝，且不能留下任何变更。
    func test_rename_toExistingName_throwsAndDoesNotTouchFiles() throws {
        let original = try makeFile(named: "DSC_0001.ARW", content: "original")
        try makeFile(named: "taken.ARW", content: "taken")

        XCTAssertThrowsError(try engine.rename(original, to: "taken.ARW")) { error in
            XCTAssertEqual(error as? RenameError, .destinationExists)
        }

        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: workDir.appending(path: "taken.ARW"), encoding: .utf8), "taken")
        XCTAssertTrue(try engine.journal.allRecords().isEmpty)
    }

    // MARK: - undo

    func test_undoLast_restoresOriginalName() throws {
        let original = try makeFile(named: "DSC_0001.ARW", content: "data")
        let newURL = try engine.rename(original, to: "20260902_0001.ARW")

        let restored = try engine.undoLast()

        XCTAssertEqual(restored, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(try engine.journal.allRecords().isEmpty)
    }

    func test_undoLast_onEmptyJournal_returnsNil() throws {
        XCTAssertNil(try engine.undoLast())
    }

    // MARK: - helpers

    private func makeFile(named name: String, content: String) throws -> URL {
        let url = workDir.appending(path: name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - 撤销容错：外部丢失的文件不使整批失败

    /// 批内一个文件被外部删除：撤销时跳过它，其余照常恢复，Journal 正常清空
    func test_undoLastBatch_skipsExternallyMissingFiles() throws {
        let a = try makeFile(named: "a.ARW", content: "a")
        let b = try makeFile(named: "b.ARW", content: "b")
        let newA = workDir.appending(path: "x.ARW")
        let newB = workDir.appending(path: "y.ARW")
        try RenameTransaction(journal: engine.journal).execute(RenamePlan(operations: [
            RenameOperation(originalURL: a, newURL: newA),
            RenameOperation(originalURL: b, newURL: newB),
        ]))
        try FileManager.default.removeItem(at: newB)  // 模拟外部删除

        let restored = try engine.undoLastBatch()

        XCTAssertEqual(restored, [workDir.appending(path: "a.ARW")], "只恢复存活的 a，丢失的 b 被跳过")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.appending(path: "a.ARW").path))
        XCTAssertTrue(try engine.journal.allRecords().isEmpty, "整批记录照常清除")
    }

    // MARK: - 孤儿记录清理（原路径与新路径都消失的记录无法撤销）

    func test_cleanupOrphanRecords_removesDeadEntries() throws {
        let a = try makeFile(named: "a.ARW", content: "a")
        _ = try engine.rename(a, to: "x.ARW")
        // 两条死记录：两路径都不存在
        let dead1 = RenameRecord(originalPath: "/gone/1.ARW", newPath: "/gone/2.ARW")
        let dead2 = RenameRecord(originalPath: workDir.appending(path: "gone.ARW").path, newPath: workDir.appending(path: "gone2.ARW").path)
        try engine.journal.append(contentsOf: [dead1, dead2])
        XCTAssertEqual(try engine.journal.allRecords().count, 3)

        let removed = try engine.cleanupOrphanRecords()

        XCTAssertEqual(removed, 2)
        XCTAssertEqual(try engine.journal.allRecords().count, 1, "活记录保留")
    }

    func test_cleanupOrphanRecords_emptyJournal_returnsZero() throws {
        XCTAssertEqual(try engine.cleanupOrphanRecords(), 0)
    }
}
