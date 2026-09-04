import Foundation

/// 拍摄时间的来源（PRD F-05 回退链：EXIF → Media Creation → File Creation → File Modification）
enum CaptureTimeSource: String, Sendable {
    case exif
    case mediaCreationDate
    case fileCreationDate
    case fileModificationDate
    case unavailable

    var displayName: String {
        switch self {
        case .exif: return "EXIF"
        case .mediaCreationDate: return "媒体创建日期"
        case .fileCreationDate: return "文件创建日期"
        case .fileModificationDate: return "文件修改日期"
        case .unavailable: return "无"
        }
    }
}

/// 从单个照片文件读出的元数据（PRD F-03）
struct PhotoMetadata: Sendable, Equatable {
    /// 拍摄时间（EXIF 或 fallback；`captureTimeSource` 标记实际来源，用了 fallback 必须显式展示）
    var captureTime: Date?
    var captureTimeSource: CaptureTimeSource?
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
}
