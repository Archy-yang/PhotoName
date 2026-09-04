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
}
