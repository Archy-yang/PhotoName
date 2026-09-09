import XCTest
@testable import PhotoName

/// 实时示例名预览：用户输入模板时，用第一个资产渲染出一个「示例新名字」，
/// 并把模板错误（缺拍摄时间 / 缺项目名 / 未知变量）即时反馈出来。
final class TemplateSamplePreviewTests: XCTestCase {
    private let samplePreview = TemplateSamplePreview()

    private func makeAsset(captureTime: Date? = nil, cameraModel: String? = nil) -> PhotoAsset {
        let url = URL(filePath: "/tmp/DCIM/DSC_0001.ARW")
        let asset = PhotoAsset(captureTime: captureTime, cameraModel: cameraModel, resources: [
            PhotoResource(url: url, kind: .raw),
        ])
        return asset
    }

    private let captureDate = Date(timeIntervalSince1970: 1_789_000_000) // 固定时刻

    // MARK: - 正常渲染

    func test_rendered_sampleNameMatchesPlannerOutput() throws {
        let asset = makeAsset(captureTime: captureDate, cameraModel: "ILCE-7RM5")
        let metadata = [asset.id: PhotoMetadata(captureTime: captureDate, captureTimeSource: .exif, cameraModel: "ILCE-7RM5")]

        let outcome = samplePreview.make(
            assets: [asset],
            metadata: metadata,
            template: RenameTemplate(pattern: "{YYYY}{MM}{DD}_{camera}_{index}"),
            projectName: nil
        )

        // 与 RenamePlanner 首资产（index 1）输出一致，且带扩展名
        guard case .rendered(let name) = outcome else {
            return XCTFail("应为 .rendered，实际 \(outcome.map(String.init(describing:)) ?? "nil")")
        }
        XCTAssertEqual(name, sampleDateString() + "_ILCE-7RM5_0001.ARW")
    }

    // MARK: - 模板错误即时反馈

    func test_templateUsesDateButAssetHasNoCaptureTime_reportsMissingCaptureTime() {
        let asset = makeAsset(captureTime: nil)
        let outcome = samplePreview.make(
            assets: [asset],
            metadata: [asset.id: PhotoMetadata()],
            template: RenameTemplate(pattern: "{YYYY}{MM}{DD}_{index}"),
            projectName: nil
        )
        XCTAssertEqual(outcome, .failed(.missingCaptureTime))
    }

    func test_templateUsesProjectWithoutProjectName_reportsMissingProjectName() {
        let asset = makeAsset(captureTime: captureDate)
        let outcome = samplePreview.make(
            assets: [asset],
            metadata: [asset.id: PhotoMetadata(captureTime: captureDate, captureTimeSource: .exif)],
            template: RenameTemplate(pattern: "{project}_{index}"),
            projectName: nil
        )
        XCTAssertEqual(outcome, .failed(.missingProjectName))
    }

    func test_unknownVariable_reportsUnknownVariable() {
        let asset = makeAsset(captureTime: captureDate)
        let outcome = samplePreview.make(
            assets: [asset],
            metadata: [asset.id: PhotoMetadata(captureTime: captureDate, captureTimeSource: .exif)],
            template: RenameTemplate(pattern: "{date}_{index}"),
            projectName: nil
        )
        XCTAssertEqual(outcome, .failed(.unknownVariable("date")))
    }

    // MARK: - 边界

    func test_noAssets_returnsNil() {
        let outcome = samplePreview.make(
            assets: [],
            metadata: [:],
            template: RenameTemplate(pattern: "{index}"),
            projectName: nil
        )
        XCTAssertNil(outcome)
    }

    private func sampleDateString() -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: captureDate)
        return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
