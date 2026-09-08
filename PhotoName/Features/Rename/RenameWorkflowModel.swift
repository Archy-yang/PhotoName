import Foundation

/// 完整工作流的状态层（PRD §8）：选目录 → 资产列表 → 模板 → 预览 → 执行 → 撤销。
/// 负责安全作用域（security scope / bookmark）与 UI 状态；核心逻辑都在 Core 层。
@MainActor @Observable
final class RenameWorkflowModel {
    private(set) var folderURL: URL?
    private(set) var assets: [PhotoAsset] = []
    private(set) var assetMetadata: [UUID: PhotoMetadata] = [:]
    private(set) var plan: RenamePlan?
    private(set) var preflightReport: PreflightReport?
    private(set) var statusText = ""
    private(set) var canUndo = false
    /// 重 I/O（扫描/读 EXIF/批量改名）进行中，UI 据此禁用操作
    private(set) var isBusy = false

    /// 当前选中的资产（Inspector 展示用）
    var selection: PhotoAsset.ID?

    var selectedAsset: PhotoAsset? {
        assets.first { $0.id == selection }
    }

    /// 某资产在当前方案中的改名操作（Inspector 预览用）
    func operations(for asset: PhotoAsset) -> [RenameOperation] {
        plan?.operations.filter { $0.assetID == asset.id } ?? []
    }

    var templatePattern: String = RenameTemplate.builtinPresets[0].pattern
    var projectName: String = ""

    private let workflow = RenameWorkflow()
    private var transaction: RenameTransaction?
    private var engine: RenameEngine?
    private var isAccessingScope = false

    private var journalURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appending(path: "rename-journal.json")
    }

    // MARK: - 选择文件夹

    func pickFolder(at url: URL) {
        stopAccessing()
        guard url.startAccessingSecurityScopedResource() else {
            statusText = "❌ 无法获得文件夹访问权限（security scope）"
            return
        }
        isAccessingScope = true
        folderURL = url
        saveBookmark(for: url)
        activateJournal()
        Task { await reloadAssets() }
    }

    /// App 启动时用持久化的 bookmark 恢复上次选择的文件夹
    func restoreLastFolder() {
        guard folderURL == nil,
              let data = UserDefaults.standard.data(forKey: "spikeA.folderBookmark")
        else { return }

        var bookmarkIsStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &bookmarkIsStale
        ) else {
            statusText = "⚠️ bookmark 已失效，请重新选择文件夹"
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            statusText = "⚠️ 已恢复文件夹路径但无法获得访问权限"
            return
        }
        isAccessingScope = true
        folderURL = url
        activateJournal()
        Task { await reloadAssets() }
    }

    // MARK: - 预览与执行（重 I/O 均在后台线程，UI 保持响应）

    func makePreviewPlan() async {
        guard let folderURL else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let currentAssets = assets
            let pattern = templatePattern
            let project = projectName.isEmpty ? nil : projectName

            let (metadata, newPlan, report) = try await Task.detached(priority: .userInitiated) { [workflow] in
                let metadata = workflow.readMetadata(for: currentAssets) { done, total in
                    Task { @MainActor in
                        // 进度更新走主线程，但不阻塞读取
                        self.statusText = "⏳ 正在读取元数据… \(done)/\(total)"
                    }
                }
                let plan = try workflow.makePlan(
                    assets: currentAssets,
                    metadata: metadata,
                    template: RenameTemplate(pattern: pattern),
                    projectName: project
                )
                Task { @MainActor in self.statusText = "⏳ 正在预检…" }
                let report = PreflightEngine().run(plan: plan, assets: currentAssets, metadata: metadata)
                return (metadata, plan, report)
            }.value

            assetMetadata = metadata
            plan = newPlan
            preflightReport = report
            if report.canExecute {
                statusText = "📋 预检通过：\(newPlan.operations.count) 个文件将被重命名"
            } else {
                statusText = "⛔ 预检发现阻塞问题，不能执行"
            }
        } catch TemplateError.missingCaptureTime {
            statusText = "❌ 部分照片缺少拍摄时间（EXIF），无法使用含日期的模板"
            plan = nil
            preflightReport = nil
        } catch {
            statusText = "❌ 生成预览失败：\(error.localizedDescription)"
            plan = nil
            preflightReport = nil
        }
    }

    func executePlan() async {
        guard let transaction, let plan, preflightReport?.canExecute != false else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let executingPlan = plan
            let total = executingPlan.operations.count
            let count = try await Task.detached(priority: .userInitiated) {
                try transaction.execute(executingPlan) { done, _ in
                    Task { @MainActor in
                        self.statusText = "⏳ 正在执行重命名… \(done)/\(total)"
                    }
                }
            }.value
            self.plan = nil
            preflightReport = nil
            await reloadAssets()
            statusText = "✅ 已重命名 \(count) 个文件"
        } catch RenameError.destinationExists {
            statusText = "❌ 目标文件名已存在，整批未执行（Never Overwrite）"
        } catch RenameError.duplicateDestinationInBatch {
            statusText = "❌ 批次内产生了重复的目标文件名（检查模板是否缺少 {index}）"
        } catch {
            statusText = "❌ 执行失败：\(error.localizedDescription)"
        }
        refreshCanUndo()
    }

    /// 批次级撤销：整体回退最近一次批量执行
    func undoLastBatch() async {
        guard let engine else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let restored = try await Task.detached(priority: .userInitiated) {
                try engine.undoLastBatch()
            }.value
            if restored.isEmpty {
                statusText = "没有可撤销的批次"
            } else {
                await reloadAssets()
                statusText = "↩️ 已撤销整批，恢复 \(restored.count) 个文件"
            }
        } catch {
            statusText = "❌ 撤销失败：\(error.localizedDescription)"
        }
        refreshCanUndo()
    }

    /// 资产级撤销：整组回退某个资产的最近一次变更（Asset Atomicity）
    func undoAsset(_ asset: PhotoAsset) async {
        guard let engine else { return }
        do {
            let restored = try await Task.detached(priority: .userInitiated) {
                try engine.undoAsset(asset.id)
            }.value
            if restored.isEmpty {
                statusText = "该资产没有可撤销的变更"
            } else {
                await reloadAssets()
                statusText = "↩️ 已撤销资产（\(restored.count) 个文件）"
            }
        } catch {
            statusText = "❌ 撤销失败：\(error.localizedDescription)"
        }
        refreshCanUndo()
    }

    // MARK: - 私有

    private func activateJournal() {
        let journal = RenameJournal(fileURL: journalURL)
        transaction = RenameTransaction(journal: journal)
        engine = RenameEngine(journal: journal)
        refreshCanUndo()
    }

    private func reloadAssets() async {
        guard let folderURL else { return }
        isBusy = true
        defer { isBusy = false }
        let url = folderURL
        statusText = "⏳ 正在扫描…"
        let loaded = await Task.detached(priority: .userInitiated) { [workflow] in
            try? workflow.loadAssets(directory: url)
        }.value ?? []

        assets = loaded
        assetMetadata = [:]
        plan = nil
        preflightReport = nil
        if let selection, !assets.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
        statusText = "✅ \(url.lastPathComponent)：\(loaded.count) 组资产"
    }

    private func refreshCanUndo() {
        canUndo = !((try? engine?.journal.allRecords())?.isEmpty ?? true)
    }

    private func saveBookmark(for url: URL) {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = .withSecurityScope
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        if let data = try? url.bookmarkData(options: options) {
            UserDefaults.standard.set(data, forKey: "spikeA.folderBookmark")
        }
    }

    private func stopAccessing() {
        if isAccessingScope, let folderURL {
            folderURL.stopAccessingSecurityScopedResource()
            isAccessingScope = false
        }
    }
}
