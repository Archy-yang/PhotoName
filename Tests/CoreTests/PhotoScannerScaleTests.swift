import XCTest
@testable import PhotoName

/// 大目录规模验证（PRD Phase 7：3000+ 文件）——只验证正确性与可完成性，不做时间断言
final class PhotoScannerScaleTests: XCTestCase {
    func test_scan3000Files_groupsCorrectly() throws {
        let workDir = FileManager.default.temporaryDirectory
            .appending(path: "scale-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // 1000 组 × (RAW + JPEG + XMP) = 3000 个文件，分 10 个子目录
        for group in 0..<1000 {
            let subDir = workDir.appending(path: "sub\(group / 100)")
            try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
            for ext in ["ARW", "JPG", "XMP"] {
                let name = String(format: "DSC_%04d.%@", group, ext)
                try Data(repeating: 0x61, count: 16).write(to: subDir.appending(path: name))
            }
        }

        let scanner = PhotoScanner()
        let resources = try scanner.scan(directory: workDir)
        XCTAssertEqual(resources.count, 3000)

        let grouper = AssetGrouper()
        let assets = grouper.group(resources)
        XCTAssertEqual(assets.count, 1000)
        XCTAssertTrue(assets.allSatisfy { $0.resources.count == 3 })
    }
}
