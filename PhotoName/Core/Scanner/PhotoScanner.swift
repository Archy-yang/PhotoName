import Foundation

/// 递归扫描目录，产出摄影相关文件的 PhotoResource（PRD F-01/F-02 的 Phase 2 版本）。
/// 只收 raw/jpeg/heic/xmp（video 按计划在后续阶段加入）；跳过隐藏文件（.DS_Store、AppleDouble 资源叉等）。
struct PhotoScanner: Sendable {
    func scan(directory: URL) throws -> [PhotoResource] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: directory.path])
        }

        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )
        guard let enumerator else { return [] }

        var resources: [PhotoResource] = []
        for case let url as URL in enumerator {
            guard !url.lastPathComponent.hasPrefix(".") else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }

            let ext = url.pathExtension
            let kind = ResourceKind(fileExtension: ext)
            switch kind {
            case .raw, .jpeg, .heic, .xmp:
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                resources.append(
                    PhotoResource(url: url, kind: kind, fileSize: Int64(size))
                )
            case .video, .unknown:
                continue
            }
        }
        return resources.sorted { $0.url.path < $1.url.path }
    }
}
