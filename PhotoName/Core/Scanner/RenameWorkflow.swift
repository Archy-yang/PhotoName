import Foundation

/// 核心工作流串联（PRD §8 前半段）：扫描 → 读元数据 → 配对成资产 → 生成改名方案。
/// 纯 Core 层，无 UI 依赖；UI 层（RenameWorkflowModel）负责状态与安全作用域。
struct RenameWorkflow: Sendable {
    private let scanner = PhotoScanner()
    private let metadataReader = MetadataReader()
    private let grouper = AssetGrouper()
    private let planner = RenamePlanner()

    /// 扫描目录并按 PRD F-04 配对成 PhotoAsset 列表
    func loadAssets(directory: URL) throws -> [PhotoAsset] {
        let resources = try scanner.scan(directory: directory)
        return grouper.group(resources)
    }

    /// 一步生成完整改名方案。资产元数据取每组第一个资源（同组文件元数据一致）。
    func makePlan(
        directory: URL,
        template: RenameTemplate,
        projectName: String? = nil,
        startingIndex: Int = 1
    ) throws -> RenamePlan {
        let assets = try loadAssets(directory: directory)
        let metadata = readMetadata(for: assets)
        return try makePlan(assets: assets, metadata: metadata, template: template, projectName: projectName, startingIndex: startingIndex)
    }

    func makePlan(
        assets: [PhotoAsset],
        metadata: [UUID: PhotoMetadata],
        template: RenameTemplate,
        projectName: String? = nil,
        startingIndex: Int = 1
    ) throws -> RenamePlan {
        try planner.makePlan(
            assets: assets,
            metadata: metadata,
            template: template,
            projectName: projectName,
            startingIndex: startingIndex
        )
    }

    /// 批量读取资产元数据（每组取第一个资源），供 Preflight 与 Planner 共用
    func readMetadata(for assets: [PhotoAsset]) -> [UUID: PhotoMetadata] {
        var metadata: [UUID: PhotoMetadata] = [:]
        for asset in assets {
            guard let first = asset.resources.first else { continue }
            metadata[asset.id] = try? metadataReader.readMetadata(at: first.url)
        }
        return metadata
    }
}
