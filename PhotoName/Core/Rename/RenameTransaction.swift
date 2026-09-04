import Foundation

/// 批量事务执行器（PRD F-10 的 Phase 1 版本）：
/// 执行前全量预检（批内重复 + Never Overwrite），任一冲突则整体不动；
/// 执行中逐条写入 Journal，已完成的操作随时可撤销，失败即停。
struct RenameTransaction: Sendable {
    let journal: RenameJournal

    /// 返回成功的操作数
    @discardableResult
    func execute(_ plan: RenamePlan) throws -> Int {
        // 批内重复目标（例如模板漏了 {index} 导致整批同名）
        let targets = plan.operations.map { $0.newURL.path }
        if Set(targets).count != targets.count {
            throw RenameError.duplicateDestinationInBatch
        }

        // Never Overwrite（PRD §12）：预检全部目标，任一已存在则整体不执行
        for operation in plan.operations where FileManager.default.fileExists(atPath: operation.newURL.path) {
            throw RenameError.destinationExists
        }

        var completed = 0
        let transactionID = UUID()
        for operation in plan.operations {
            try FileManager.default.moveItem(at: operation.originalURL, to: operation.newURL)
            try journal.append(
                RenameRecord(
                    assetID: operation.assetID,
                    transactionID: transactionID,
                    originalPath: operation.originalURL.path,
                    newPath: operation.newURL.path
                )
            )
            completed += 1
        }
        return completed
    }
}
