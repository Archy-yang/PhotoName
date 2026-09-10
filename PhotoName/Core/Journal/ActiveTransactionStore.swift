import Foundation

/// 活动事务标记的存储：单文件、原子写、整体删。
/// 存在标记 = 有批次被中断；Journal 记录可因缓冲丢失，标记里的意图清单是完整的。
struct ActiveTransactionStore: Sendable {
    let fileURL: URL

    func load() throws -> ActiveTransaction? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ActiveTransaction.self, from: data)
    }

    func save(_ transaction: ActiveTransaction) throws {
        let data = try JSONEncoder().encode(transaction)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
