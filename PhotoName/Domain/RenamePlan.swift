import Foundation

/// 单个文件的重命名操作：改名前后对照表的一行（PRD F-08 Preview 的数据单元）
struct RenameOperation: Sendable, Equatable {
    let originalURL: URL
    let newURL: URL
    /// 所属资产组，用于资产级撤销（Asset Atomicity：整组回退，不做单文件级）
    var assetID: UUID?

    init(originalURL: URL, newURL: URL, assetID: UUID? = nil) {
        self.originalURL = originalURL
        self.newURL = newURL
        self.assetID = assetID
    }
}

/// 一个批量重命名方案：RenamePlanner 产出，Preview 展示、RenameTransaction 执行（PRD F-10）
struct RenamePlan: Sendable, Equatable {
    let operations: [RenameOperation]
    /// 因 Duplicate Timestamp 被 Sequence 消解（自动追加 -2/-3…）的资产组（PRD F-09，
    /// Preflight 据此发显式警告——自动改名的部分必须让用户看见，§12）
    var sequenceResolvedAssetIDs: Set<UUID> = []

    init(operations: [RenameOperation], sequenceResolvedAssetIDs: Set<UUID> = []) {
        self.operations = operations
        self.sequenceResolvedAssetIDs = sequenceResolvedAssetIDs
    }
}
