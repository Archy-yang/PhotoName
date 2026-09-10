import Foundation

/// 一次被中断批次的调和结果：按磁盘真实状态把意图清单分成三类
struct InterruptedBatch: Sendable {
    let transaction: ActiveTransaction
    /// 已完成（目标存在、源已消失）——可安全回退
    let completed: [ActiveTransactionOperation]
    /// 未执行（源仍在）——无需处理
    let pending: [ActiveTransactionOperation]
    /// 冲突（源与目标同时存在/同时消失）——拿不准的绝不动（Safe First）
    let conflicts: [ActiveTransactionOperation]

    var id: UUID { transaction.id }
}

/// 崩溃恢复（PRD F-12）：启动时用活动标记对照磁盘调和出中断现场，
/// 并支持把已完成部分逆序回退、清理标记与该批次的 Journal 记录。
struct RecoveryEngine: Sendable {
    func reconcile(_ transaction: ActiveTransaction) throws -> InterruptedBatch {
        var completed: [ActiveTransactionOperation] = []
        var pending: [ActiveTransactionOperation] = []
        var conflicts: [ActiveTransactionOperation] = []

        for operation in transaction.operations {
            let sourceExists = FileManager.default.fileExists(atPath: operation.originalPath)
            let targetExists = FileManager.default.fileExists(atPath: operation.newPath)
            switch (sourceExists, targetExists) {
            case (false, true):
                completed.append(operation)
            case (true, false):
                pending.append(operation)
            default:
                // (true, true)：外部同名文件？回退会覆盖；(false, false)：文件被移动/删除？无从恢复
                conflicts.append(operation)
            }
        }

        return InterruptedBatch(
            transaction: transaction,
            completed: completed,
            pending: pending,
            conflicts: conflicts
        )
    }

    /// 逆序回退已完成部分（改名是其自身的逆操作），清空该批次 Journal 记录并删除标记。
    /// 返回实际恢复的文件数。
    @discardableResult
    func rollback(
        _ batch: InterruptedBatch,
        journal: RenameJournal,
        activeStore: ActiveTransactionStore
    ) throws -> Int {
        let transactionID = batch.transaction.id
        var restored = 0

        for operation in batch.completed.reversed() {
            // Never Overwrite：回退目标意外存在时跳过该条（不覆盖任何文件）
            guard !FileManager.default.fileExists(atPath: operation.originalPath) else { continue }
            try FileManager.default.moveItem(atPath: operation.newPath, toPath: operation.originalPath)
            restored += 1
        }

        try journal.removeRecords { $0.transactionID == transactionID }
        try activeStore.clear()
        return restored
    }
}
