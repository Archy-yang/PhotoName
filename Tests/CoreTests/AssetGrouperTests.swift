import XCTest
@testable import PhotoName

final class AssetGrouperTests: XCTestCase {
    private let grouper = AssetGrouper()

    private func resource(_ name: String, dir: String = "/shoot") -> PhotoResource {
        let url = URL(fileURLWithPath: "\(dir)/\(name)")
        return PhotoResource(
            url: url,
            kind: ResourceKind(fileExtension: (name as NSString).pathExtension)
        )
    }

    /// PRD F-04：DSC_0001.ARW + .JPG + .XMP 属于同一张照片
    func test_rawJpegXmpWithSameStem_pairIntoOneAsset() {
        let assets = grouper.group([
            resource("DSC_0001.ARW"), resource("DSC_0001.JPG"), resource("DSC_0001.XMP"),
        ])

        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets[0].resources.count, 3)
        XCTAssertEqual(assets[0].resources.map(\.kind).sorted { $0.rawValue < $1.rawValue }, [.jpeg, .raw, .xmp])
    }

    func test_differentStems_formSeparateAssets() {
        let assets = grouper.group([
            resource("DSC_0001.ARW"), resource("DSC_0002.ARW"), resource("DSC_0003.ARW"),
        ])

        XCTAssertEqual(assets.count, 3)
    }

    /// 配对不区分大小写：相机可能生成 dsc_0001.jpg 这类名字
    func test_stemMatchingIsCaseInsensitive() {
        let assets = grouper.group([
            resource("DSC_0001.ARW"), resource("dsc_0001.JPG"), resource("Dsc_0001.XMP"),
        ])

        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets[0].resources.count, 3)
    }

    /// 不同目录下的同名文件不属于同一资产
    func test_sameStemInDifferentFolders_notGrouped() {
        let assets = grouper.group([
            resource("DSC_0001.ARW", dir: "/card-a"),
            resource("DSC_0001.JPG", dir: "/card-b"),
        ])

        XCTAssertEqual(assets.count, 2)
    }

    /// 独立文件（如手机 HEIC）自成一组，不能被丢弃
    func test_standaloneFile_formsOwnAsset() {
        let assets = grouper.group([resource("IMG_4821.HEIC")])

        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets[0].resources.first?.kind, .heic)
    }

    /// 混合场景：成组的 RAW+JPEG+XMP 与独立的 HEIC 共存
    func test_mixedScene_groupsAndStandaloneCoexist() {
        let assets = grouper.group([
            resource("DSC_0001.ARW"), resource("DSC_0001.JPG"), resource("DSC_0001.XMP"),
            resource("IMG_4821.HEIC"),
            resource("DJI_0381.DNG"),
        ])

        XCTAssertEqual(assets.count, 3)
        XCTAssertEqual(assets.compactMap { $0.resources.first?.originalFilename }.sorted(),
                       ["DJI_0381.DNG", "DSC_0001.ARW", "IMG_4821.HEIC"].sorted())
    }

    /// 输出按基础名稳定排序（后续 Phase 2 会换成 Capture Time 排序）
    func test_assetsSortedByStem() {
        let assets = grouper.group([
            resource("IMG_0002.HEIC"), resource("DSC_0001.ARW"), resource("AAA_0000.XMP"),
        ])

        XCTAssertEqual(
            assets.map { $0.resources[0].originalFilename },
            ["AAA_0000.XMP", "DSC_0001.ARW", "IMG_0002.HEIC"]
        )
    }
}
