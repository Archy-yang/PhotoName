import Foundation

/// 把零散文件按「同一目录 + 同一文件名基础名」配对成 PhotoAsset（PRD F-04）。
/// 配对规则：基础名大小写不敏感；不同目录的同名文件不配对；独立文件自成一组。
struct AssetGrouper: Sendable {
    func group(_ resources: [PhotoResource]) -> [PhotoAsset] {
        let grouped = Dictionary(grouping: resources) { resource in
            groupKey(for: resource.url)
        }

        return grouped
            .sorted { $0.key < $1.key }
            .map { _, resources in
                PhotoAsset(resources: resources.sorted { $0.originalFilename < $1.originalFilename })
            }
    }

    private func groupKey(for url: URL) -> String {
        let directory = url.deletingLastPathComponent().path
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        return "\(directory)/\(stem)"
    }
}
