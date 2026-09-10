import Foundation

/// 批量事务执行器（PRD F-10 的 Phase 1 版本）：
/// 执行前全量预检（批内重复 + Never Overwrite），任一冲突则整体不动；
/// 执行中逐条写入 Journal，已完成的操作随时可撤销，失败即停。
struct RenameTransaction: Sendable {
    let journal: RenameJournal
    /// 活动标记存储（Crash Recovery）：nil 时不写标记（兼容旧调用）
    let activeStore: ActiveTransactionStore?

    init(journal: RenameJournal, activeStore: ActiveTransactionStore? = nil) {
        self.journal = journal
        self.activeStore = activeStore
    }

    /// 返回成功的操作数。progress(done, total) 逐操作回调（后台线程，UI 侧自行调度）。
    /// Journal 按 64 条缓冲批量落盘：兼顾大目录性能；崩溃丢记录的窗口由活动标记兜底——
    /// 执行前把完整意图清单原子写入标记，成功后清除，中断后靠标记对照磁盘调和现场。
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

        // 执行前写活动标记（完整意图清单）；预检失败不会走到这里，不产生假中断
        if let activeStore {
            try activeStore.save(
                ActiveTransaction(
                    id: transactionID,
                    startedAt: Date(),
                    operations: operations.map {
                        ActiveTransactionOperation(
                            originalPath: $0.originalURL.path,
                            newPath: $0.newURL.path,
                            assetID: $0.assetID
                        )
                    }
                )
            )
        }

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
        // 全部成功：清除标记。清除失败不使执行失败（最坏情况是下次启动多一次可忽略的恢复提示）
        try? activeStore?.clear()
        return completed
    }

    private static let journalFlushSize = 64
}
