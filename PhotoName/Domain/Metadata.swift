import Foundation

/// 从单个照片文件读出的元数据（PRD F-03）
struct PhotoMetadata: Sendable, Equatable {
    /// EXIF DateTimeOriginal。注意：EXIF 时间不含时区，按本机时区解释（已知限制，Spike B 结论见路线图）
    var captureTime: Date?
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
}
