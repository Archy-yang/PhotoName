import Foundation

/// 批量事务执行器（PRD F-10 的 Phase 1 版本）：
/// 执行前全量预检（批内重复 + Never Overwrite），任一冲突则整体不动；
/// 执行中逐条写入 Journal，已完成的操作随时可撤销，失败即停。
struct RenameTransaction: Sendable {
    let journal: RenameJournal

    /// 返回成功的操作数。progress(done, total) 逐操作回调（后台线程，UI 侧自行调度）。
    /// Journal 按 64 条缓冲批量落盘：兼顾大目录性能与崩溃时最多丢失一小段记录（Crash Recovery 在 Phase 5 正式设计）。
    @discardableResult
    func execute(_ plan: RenamePlan, progress: (@Sendable (Int, Int) -> Void)? = nil) throws -> Int {
        // 恒等操作（目标 == 原路径）是 no-op：跳过预检与执行，不写 Journal（防御性过滤，
        // 正常情况下 RenamePlanner 已过滤）
        let operations = plan.operations.filter { $0.originalURL.standardizedFileURL != $0.newURL.standardizedFileURL }

        // 批内重复目标（例如模板漏了 {index} 导致整批同名）
        let targets = operations.map { $0.newURL.path }
        if Set(targets).count != targets.count {
            throw RenameError.duplicateDestinationInBatch
        }

        // Never Overwrite（PRD §12）：预检全部目标，任一已存在则整体不执行
        for operation in operations where FileManager.default.fileExists(atPath: operation.newURL.path) {
            throw RenameError.destinationExists
        }

        var completed = 0
        let total = operations.count
        let transactionID = UUID()
        var journalBuffer: [RenameRecord] = []

        for operation in operations {
            try FileManager.default.moveItem(at: operation.originalURL, to: operation.newURL)
            journalBuffer.append(
                RenameRecord(
                    assetID: operation.assetID,
                    transactionID: transactionID,
                    originalPath: operation.originalURL.path,
                    newPath: operation.newURL.path
                )
            )
            completed += 1
            if journalBuffer.count >= Self.journalFlushSize {
                try journal.append(contentsOf: journalBuffer)
                journalBuffer.removeAll(keepingCapacity: true)
            }
            progress?(completed, total)
        }
        try journal.append(contentsOf: journalBuffer)
        return completed
    }

    private static let journalFlushSize = 64
}
