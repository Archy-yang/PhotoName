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
        reloadAssets()
        statusText = "✅ 已选择：\(url.lastPathComponent)，共 \(assets.count) 个资产"
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
        reloadAssets()
        statusText = "✅ 已恢复上次文件夹：\(url.lastPathComponent)，共 \(assets.count) 个资产"
    }

    // MARK: - 预览与执行

    func makePreviewPlan() {
        guard let folderURL else { return }
        do {
            let metadata = workflow.readMetadata(for: assets)
            assetMetadata = metadata
            plan = try workflow.makePlan(
                assets: assets,
                metadata: metadata,
                template: RenameTemplate(pattern: templatePattern),
                projectName: projectName.isEmpty ? nil : projectName
            )
            preflightReport = PreflightEngine().run(
                plan: plan!,
                assets: assets,
                metadata: metadata,
                destinationDirectory: folderURL
            )
            if preflightReport?.canExecute == true {
                statusText = "📋 预检通过：\(plan?.operations.count ?? 0) 个文件将被重命名"
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

    func executePlan() {
        guard let transaction, let plan, preflightReport?.canExecute != false else { return }
        do {
            let count = try transaction.execute(plan)
            self.plan = nil
            reloadAssets()
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
    func undoLastBatch() {
        guard let engine else { return }
        do {
            let restored = try engine.undoLastBatch()
            if restored.isEmpty {
                statusText = "没有可撤销的批次"
            } else {
                reloadAssets()
                statusText = "↩️ 已撤销整批，恢复 \(restored.count) 个文件"
            }
        } catch {
            statusText = "❌ 撤销失败：\(error.localizedDescription)"
        }
        refreshCanUndo()
    }

    /// 资产级撤销：整组回退某个资产的最近一次变更（Asset Atomicity）
    func undoAsset(_ asset: PhotoAsset) {
        guard let engine else { return }
        do {
            let restored = try engine.undoAsset(asset.id)
            if restored.isEmpty {
                statusText = "该资产没有可撤销的变更"
            } else {
                reloadAssets()
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

    private func reloadAssets() {
        guard let folderURL else { return }
        assets = (try? workflow.loadAssets(directory: folderURL)) ?? []
        assetMetadata = [:]
        plan = nil
        preflightReport = nil
        if let selection, !assets.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
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
