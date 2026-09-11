import Foundation

enum RenameError: Error, Equatable {
    /// Never Overwrite（PRD §12）：目标文件已存在时拒绝重命名
    case destinationExists
    /// 同一批次内产生了重复的目标文件名（PRD F-09 Duplicate Name）
    case duplicateDestinationInBatch
}

/// 执行单个文件重命名并记录 Journal；支持按 Journal 撤销（PRD F-10/F-11/F-12 的 Spike 版本）。
struct RenameEngine: Sendable {
    let journal: RenameJournal

    /// 将文件重命名为 newName（同目录）。目标已存在时抛出 `RenameError.destinationExists`。
    @discardableResult
    func rename(_ url: URL, to newName: String) throws -> URL {
        let newURL = url.deletingLastPathComponent().appending(path: newName)

        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw RenameError.destinationExists
        }

        try FileManager.default.moveItem(at: url, to: newURL)
        try journal.append(
            RenameRecord(originalPath: url.path, newPath: newURL.path)
        )
        return newURL
    }

    /// 撤销最近一次重命名（单条记录）。没有可撤销的记录时返回 nil。
    @discardableResult
    func undoLast() throws -> URL? {
        guard let record = try journal.removeLast() else { return nil }
        let current = URL(fileURLWithPath: record.newPath)
        let restored = URL(fileURLWithPath: record.originalPath)
        try FileManager.default.moveItem(at: current, to: restored)
        return restored
    }

    /// 批次级撤销：整体回退最后一个事务（PRD F-12）。撤销只能按批次逆序进行，
    /// 不能跳过中间批次——跨批次撤销会把文件拖到从未存在过的状态。
    @discardableResult
    func undoLastBatch() throws -> [URL] {
        guard let records = try journal.removeLastTransaction() else { return [] }
        return try records.reversed().map { record in
            try FileManager.default.moveItem(
                at: URL(fileURLWithPath: record.newPath),
                to: URL(fileURLWithPath: record.originalPath)
            )
            return URL(fileURLWithPath: record.originalPath)
        }
    }

    /// 资产级撤销：在最近一个包含该资产的事务中，把该资产组的所有文件整体回退（PRD §12 Asset Atomicity）。
    /// 单个文件级撤销会导致组内半改状态（RAW 回了旧名、JPG 还是新名），因此不提供。
    ///
    /// 关联键用**路径**而非 assetID：每次扫描都会生成新的资产 UUID，按 ID 匹配在
    /// "执行后刷新列表"和"跨会话"两个场景必然失配（右键撤销静默失效）。
    /// 资产当前资源路径等于该批次记录的 newPath 时命中；旧格式记录（无路径可配）按 assetID 兜底。
    @discardableResult
    func undoAsset(matching asset: PhotoAsset) throws -> [URL] {
        let currentPaths = Set(asset.resources.map { $0.url.standardizedFileURL.path })

        func pathsHit(_ record: RenameRecord) -> Bool {
            currentPaths.contains(URL(fileURLWithPath: record.newPath).standardizedFileURL.path)
                || currentPaths.contains(URL(fileURLWithPath: record.originalPath).standardizedFileURL.path)
        }

        let transactions = try journal.transactions()
        guard let transaction = transactions.last(where: { group in
            group.contains { pathsHit($0) }
        }) else { return [] }

        // 命中事务里，产出"当前路径"的那部分记录才是该资产组（同批次内其他资产不动）
        var assetRecords = transaction.filter { pathsHit($0) }
        if assetRecords.isEmpty {
            // 路径全不匹配（文件被外部改名等）：旧格式记录按 assetID 兜底
            assetRecords = transaction.filter { $0.assetID == asset.id }
        }
        guard !assetRecords.isEmpty else { return [] }

        try journal.removeRecords { record in
            assetRecords.contains(where: { $0.id == record.id })
        }

        return try assetRecords.reversed().map { record in
            try FileManager.default.moveItem(
                at: URL(fileURLWithPath: record.newPath),
                to: URL(fileURLWithPath: record.originalPath)
            )
            return URL(fileURLWithPath: record.originalPath)
        }
    }
}
