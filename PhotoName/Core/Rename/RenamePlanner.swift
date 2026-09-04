import Foundation

/// 把「资产组 + 元数据 + 模板」变成完整的改名前后对照表（PRD F-08/F-10 的 Plan 阶段）。
/// 同一资产的所有资源共享同一基础名，各自保留原扩展名。
struct RenamePlanner: Sendable {
    func makePlan(
        assets: [PhotoAsset],
        metadata: [UUID: PhotoMetadata],
        template: RenameTemplate,
        projectName: String? = nil,
        startingIndex: Int = 1
    ) throws -> RenamePlan {
        let renderer = TemplateRenderer()
        var operations: [RenameOperation] = []

        for (offset, asset) in assets.enumerated() {
            guard let first = asset.resources.first else { continue }
            let meta = metadata[asset.id]
            let context = TemplateContext(
                captureTime: meta?.captureTime,
                cameraModel: meta?.cameraModel,
                lensModel: meta?.lensModel,
                originalBaseName: first.url.deletingPathExtension().lastPathComponent,
                projectName: projectName
            )
            let baseName = try renderer.render(template, context: context, index: startingIndex + offset)

            for resource in asset.resources {
                let ext = resource.url.pathExtension
                let newName = ext.isEmpty ? baseName : "\(baseName).\(ext)"
                operations.append(
                    RenameOperation(
                        originalURL: resource.url,
                        newURL: resource.url.deletingLastPathComponent().appending(path: newName),
                        assetID: asset.id
                    )
                )
            }
        }

        return RenamePlan(operations: operations)
    }
}
