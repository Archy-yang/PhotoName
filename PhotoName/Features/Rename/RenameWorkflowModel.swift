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
    /// 检测到的中断批次（Crash Recovery）：非 nil 时 UI 显示恢复提示条
    private(set) var interruptedBatch: InterruptedBatch?

    /// 当前选中的资产（Inspector 展示用）
    var selection: PhotoAsset.ID?

    var selectedAsset: PhotoAsset? {
        assets.first { $0.id == selection }
    }

    /// 某资产在当前方案中的改名操作（Inspector 预览用）
    func operations(for asset: PhotoAsset) -> [RenameOperation] {
        plan?.operations.filter { $0.assetID == asset.id } ?? []
    }

    var templatePattern: String = RenameTemplate.builtinPresets[0].pattern {
        didSet { scheduleLivePreview() }
    }
    var projectName: String = "" {
        didSet { scheduleLivePreview() }
    }

    /// 实时示例名：用第一个资产渲染模板（配合资产列表/Inspector 的完整预览）
    var templateSample: TemplateSamplePreview.Outcome? {
        TemplateSamplePreview().make(
            assets: assets,
            metadata: assetMetadata,
            template: RenameTemplate(pattern: templatePattern),
            projectName: projectName.isEmpty ? nil : projectName
        )
    }

    private let workflow = RenameWorkflow()
    private var transaction: RenameTransaction?
    private var engine: RenameEngine?
    private var activeStore: ActiveTransactionStore?
    private var isAccessingScope = false
    /// 元数据缓存：模板每次改动都会重新生成预览，避免反复重读几千个文件的 EXIF
    private var metadataCache: (assetIDs: [UUID], metadata: [UUID: PhotoMetadata])?
    private var previewDebounceTask: Task<Void, Never>?
    private var previewRunID = 0

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
        #if os(macOS)
        let resolveOptions: URL.BookmarkResolutionOptions = .withSecurityScope
        #else
        let resolveOptions: URL.BookmarkResolutionOptions = []
        #endif
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: resolveOptions,
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
        guard folderURL != nil, !assets.isEmpty, !templatePattern.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        previewRunID += 1
        let runID = previewRunID
        do {
            let currentAssets = assets
            let ids = currentAssets.map(\.id)

            // 元数据只在资产集合变化时重读；模板改动直接复用缓存（实时预览的关键）
            let metadata: [UUID: PhotoMetadata]
            if let cache = metadataCache, cache.assetIDs == ids {
                metadata = cache.metadata
            } else {
                statusText = "⏳ 正在读取元数据…"
                metadata = await Task.detached(priority: .userInitiated) { [workflow] in
                    workflow.readMetadata(for: currentAssets) { done, total in
                        Task { @MainActor in
                            self.statusText = "⏳ 正在读取元数据… \(done)/\(total)"
                        }
                    }
                }.value
                metadataCache = (ids, metadata)
            }

            let pattern = templatePattern
            let project = projectName.isEmpty ? nil : projectName
            statusText = "⏳ 正在预检…"
            let (newPlan, report) = try await Task.detached(priority: .userInitiated) { [workflow] in
                let plan = try workflow.makePlan(
                    assets: currentAssets,
                    metadata: metadata,
                    template: RenameTemplate(pattern: pattern),
                    projectName: project
                )
                let report = PreflightEngine().run(plan: plan, assets: currentAssets, metadata: metadata)
                return (plan, report)
            }.value

            // 防抖期间用户又改了模板：丢弃过期结果
            guard runID == previewRunID else { return }

            assetMetadata = metadata
            plan = newPlan
            preflightReport = report
            if report.canExecute {
                statusText = newPlan.operations.isEmpty
                    ? "✅ 所有文件已符合当前模板，无需重命名"
                    : "📋 预检通过：\(newPlan.operations.count) 个文件将被重命名"
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

    /// 模板输入的防抖实时预览：400ms 内的连续击键只触发一次完整预检
    private func scheduleLivePreview() {
        previewDebounceTask?.cancel()
        guard !assets.isEmpty else { return }
        previewDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.makePreviewPlan()
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
        let store = ActiveTransactionStore(
            fileURL: journalURL.deletingLastPathComponent().appending(path: "rename-journal-active.json")
        )
        activeStore = store
        transaction = RenameTransaction(journal: journal, activeStore: store)
        engine = RenameEngine(journal: journal)
        refreshCanUndo()
        Task { await checkInterruptedBatch() }
    }

    // MARK: - 崩溃恢复（PRD F-12）

    /// 获得文件夹访问权后检查：是否存在被中断的批次（活动标记 + 磁盘调和）
    private func checkInterruptedBatch() async {
        guard let activeStore else { return }
        guard let marker = try? activeStore.load() else { return }
        let reconciled = await Task.detached(priority: .userInitiated) {
            try? RecoveryEngine().reconcile(marker)
        }.value

        guard let batch = reconciled else { return }
        if batch.completed.isEmpty && batch.conflicts.isEmpty {
            // 一次都没动文件（执行刚开始就中断）：直接清标记，不打扰用户
            try? activeStore.clear()
            return
        }
        interruptedBatch = batch
    }

    /// 回退中断批次：已完成部分逆序恢复，清理 Journal 记录与标记
    func rollbackInterruptedBatch() async {
        guard let batch = interruptedBatch, let activeStore else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let journal = engine?.journal ?? RenameJournal(fileURL: journalURL)
            let restored = try await Task.detached(priority: .userInitiated) {
                try RecoveryEngine().rollback(batch, journal: journal, activeStore: activeStore)
            }.value
            interruptedBatch = nil
            await reloadAssets()
            var message = "↩️ 已恢复中断批次，回退 \(restored) 个文件"
            if batch.conflicts.isEmpty == false {
                message += "；\(batch.conflicts.count) 个状态异常的文件未动，请手动检查"
            }
            statusText = message
        } catch {
            statusText = "❌ 恢复失败：\(error.localizedDescription)"
        }
        refreshCanUndo()
    }

    /// 忽略中断批次：保持文件现状，仅清除标记（不再提示）
    func dismissInterruptedBatch() {
        try? activeStore?.clear()
        interruptedBatch = nil
        statusText = "已忽略中断批次，文件保持现状"
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
        metadataCache = nil
        plan = nil
        preflightReport = nil
        if let selection, !assets.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
        statusText = "✅ \(url.lastPathComponent)：\(loaded.count) 组资产"
        // 扫描完成后自动生成一次预览（模板已在输入框中）
        scheduleLivePreview()
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
