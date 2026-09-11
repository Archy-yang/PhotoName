import XCTest
@testable import PhotoName

/// 资产网格排序（PRD F-05：拍摄时间是排序基石）
final class AssetSortTests: XCTestCase {
    private func asset(named name: String, capturedAt time: Date? = nil) -> PhotoAsset {
        let url = URL(filePath: "/shoot/\(name)")
        return PhotoAsset(captureTime: time, resources: [PhotoResource(url: url, kind: .raw)])
    }

    private let t1 = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 10))!
    private let t2 = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 11))!

    func test_captureTime_sortsChronologically() {
        let assets = [asset(named: "DSC_0002.ARW", capturedAt: t2),
                      asset(named: "DSC_0001.ARW", capturedAt: t1)]

        let sorted = AssetSort.captureTime.sort(assets, metadata: [:])

        XCTAssertEqual(sorted.map(\.originalFilename), ["DSC_0001.ARW", "DSC_0002.ARW"])
    }

    /// EXIF 元数据优先于资产自带时间（fallback 时间不如 EXIF 可信）
    func test_captureTime_prefersMetadataOverAssetField() {
        let early = asset(named: "DSC_EARLY.ARW", capturedAt: t2)
        let late = asset(named: "DSC_LATE.ARW", capturedAt: t1)
        let metadata = [
            early.id: PhotoMetadata(captureTime: t1, captureTimeSource: .exif),
            late.id: PhotoMetadata(captureTime: t2, captureTimeSource: .exif),
        ]

        let sorted = AssetSort.captureTime.sort([early, late], metadata: metadata)

        XCTAssertEqual(sorted.map(\.originalFilename), ["DSC_EARLY.ARW", "DSC_LATE.ARW"])
    }

    /// 无时间的资产排到最后，彼此按文件名
    func test_captureTime_assetsWithoutTime_goLast() {
        let noTime1 = asset(named: "DSC_B.ARW")
        let noTime2 = asset(named: "DSC_A.ARW")
        let timed = asset(named: "DSC_C.ARW", capturedAt: t1)

        let sorted = AssetSort.captureTime.sort([noTime1, noTime2, timed], metadata: [:])

        XCTAssertEqual(sorted.map(\.originalFilename), ["DSC_C.ARW", "DSC_A.ARW", "DSC_B.ARW"])
    }

    func test_fileName_sortsNaturally() {
        let assets = [asset(named: "DSC_10.ARW"), asset(named: "DSC_2.ARW"), asset(named: "DSC_1.ARW")]

        let sorted = AssetSort.fileName.sort(assets, metadata: [:])

        XCTAssertEqual(sorted.map(\.originalFilename), ["DSC_1.ARW", "DSC_2.ARW", "DSC_10.ARW"])
    }
}
