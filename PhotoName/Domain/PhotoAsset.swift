import Foundation

/// 核心领域模型：一个摄影资产组（RAW + JPEG + XMP）
struct PhotoAsset: Identifiable, Sendable {
    let id: UUID
    let captureTime: Date?
    let cameraMake: String?
    let cameraModel: String?
    let lensModel: String?
    let resources: [PhotoResource]

    var originalFilename: String {
        resources.first?.originalFilename ?? "Unknown"
    }

    init(
        id: UUID = UUID(),
        captureTime: Date? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        resources: [PhotoResource] = []
    ) {
        self.id = id
        self.captureTime = captureTime
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.resources = resources
    }
}
