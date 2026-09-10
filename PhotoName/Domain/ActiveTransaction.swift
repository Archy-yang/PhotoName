import Foundation

/// 活动事务标记里的单条操作（意图清单；崩溃恢复时对照磁盘调和实际状态）
struct ActiveTransactionOperation: Codable, Sendable, Equatable {
    let originalPath: String
    let newPath: String
    var assetID: UUID? = nil
}

/// 一次批量执行的活动标记（PRD F-10/F-12 Crash Recovery 的数据基础）：
/// 执行开始前原子写入，全部成功后删除；存在即说明批次被中断。
struct ActiveTransaction: Codable, Sendable, Equatable {
    let id: UUID
    let startedAt: Date
    let operations: [ActiveTransactionOperation]
}
