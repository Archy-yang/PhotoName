import Foundation

/// 一条重命名操作记录（PRD F-11 Operation Journal 的最小单元）。
/// assetID / transactionID 用于资产级与批次级撤销；为 nil 时视为独立记录（兼容旧格式）。
struct RenameRecord: Codable, Sendable, Identifiable {
    let id: UUID
    var assetID: UUID?
    var transactionID: UUID?
    let timestamp: Date
    let originalPath: String
    let newPath: String

    init(
        id: UUID = UUID(),
        assetID: UUID? = nil,
        transactionID: UUID? = nil,
        timestamp: Date = Date(),
        originalPath: String,
        newPath: String
    ) {
        self.id = id
        self.assetID = assetID
        self.transactionID = transactionID
        self.timestamp = timestamp
        self.originalPath = originalPath
        self.newPath = newPath
    }
}
