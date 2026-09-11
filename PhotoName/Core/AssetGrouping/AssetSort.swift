import Foundation

/// 资产网格排序（PRD F-05：拍摄时间是排序基石）。
/// EXIF 元数据优先于资产自带时间（扫描期 fallback 时间不如 EXIF 可信）；无时间的排最后。
enum AssetSort: String, CaseIterable, Sendable {
    case captureTime
    case fileName

    var displayName: String {
        switch self {
        case .captureTime: return "拍摄时间"
        case .fileName: return "文件名"
        }
    }

    func sort(_ assets: [PhotoAsset], metadata: [UUID: PhotoMetadata]) -> [PhotoAsset] {
        assets.sorted { a, b in
            switch self {
            case .captureTime:
                let ta = metadata[a.id]?.captureTime ?? a.captureTime
                let tb = metadata[b.id]?.captureTime ?? b.captureTime
                switch (ta, tb) {
                case let (l?, r?):
                    if l != r { return l < r }
                case (.some, nil):
                    return true   // 有时间在前
                case (nil, .some):
                    return false  // 无时间排后
                case (nil, nil):
                    break
                }
                return a.originalFilename.localizedStandardCompare(b.originalFilename) == .orderedAscending
            case .fileName:
                return a.originalFilename.localizedStandardCompare(b.originalFilename) == .orderedAscending
            }
        }
    }
}
