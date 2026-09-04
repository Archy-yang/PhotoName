import Foundation

/// 重命名操作日志：追加写入 JSON 文件，支撑 Undo 与 Crash Recovery（PRD F-11）。
/// 无内存状态，每次读写都以文件为准，多实例可见同一份记录。
final class RenameJournal: Sendable {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func allRecords() throws -> [RenameRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([RenameRecord].self, from: data)
    }

    func append(_ record: RenameRecord) throws {
        var records = try allRecords()
        records.append(record)
        try write(records)
    }

    /// 弹出最后一条记录（单条 Undo 时调用）。空日志返回 nil。
    func removeLast() throws -> RenameRecord? {
        var records = try allRecords()
        guard let last = records.popLast() else { return nil }
        try write(records)
        return last
    }

    // MARK: - 事务视图（批次级撤销的数据基础）

    /// 按 transactionID 分组的事务列表（按写入顺序）；无 transactionID 的旧记录每条自成一组
    func transactions() throws -> [[RenameRecord]] {
        let records = try allRecords()
        var order: [UUID] = []
        var groups: [UUID: [RenameRecord]] = [:]
        for record in records {
            let key = record.transactionID ?? record.id
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(record)
        }
        return order.compactMap { groups[$0] }
    }

    /// 弹出最后一个事务的全部记录（整批撤销）。空日志返回 nil。
    func removeLastTransaction() throws -> [RenameRecord]? {
        guard let lastTransaction = try transactions().last else { return nil }
        let removedIDs = Set(lastTransaction.map(\.id))
        try removeRecords { removedIDs.contains($0.id) }
        return lastTransaction
    }

    /// 移除满足条件的记录（资产级撤销时使用）
    func removeRecords(where matches: (RenameRecord) -> Bool) throws {
        var records = try allRecords()
        records.removeAll(where: matches)
        try write(records)
    }

    private func write(_ records: [RenameRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
