import SwiftUI
import UniformTypeIdentifiers

/// 三栏主界面（PRD §11）：Sources / Assets / Inspector + 底部工作流条。
/// 暗色摄影工具风（界面原型定稿 2026-09-10）：缩略图网格 + 改名预览叠卡片。
struct AssetBrowserView: View {
    @State private var model = RenameWorkflowModel()
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sourcesSidebar
                    .navigationTitle("PhotoName")
                    .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            } content: {
                assetGrid
                    .navigationSplitViewColumnWidth(min: 380, ideal: 680)
            } detail: {
                inspector
                    .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
            }
            // 恢复提示条与工作流条都在 VStack 中占独立空间，网格内容不会被遮挡
            if let batch = model.interruptedBatch {
                interruptedBatchBanner(batch)
            }
            workflowBar
        }
        .preferredColorScheme(.dark)
        .background(UITheme.ground)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.pickFolder(at: url)
            }
        }
        .onAppear { model.restoreLastFolder() }
    }

    // MARK: - Sources 侧栏

    private var sourcesSidebar: some View {
        List {
            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("选择文件夹…", systemImage: "plus.circle")
                        .foregroundStyle(UITheme.textPrimary)
                }
                if let url = model.folderURL {
                    Label(url.lastPathComponent, systemImage: "folder.fill")
                        .foregroundStyle(UITheme.amber)
                }
            } header: {
                Text("资源库")
            }
            if let url = model.folderURL {
                Section("当前来源") {
                    statRow("资产组", model.assets.count)
                    statRow("文件", model.assets.reduce(0) { $0 + $1.resources.count })
                    if let plan = model.plan {
                        statRow("改名预览", plan.operations.count, valueColor: UITheme.green)
                    }
                }
                Section {
                    Text(url.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(UITheme.textFaint)
                        .lineLimit(3)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(UITheme.panel)
        .listStyle(.sidebar)
    }

    private func statRow(_ label: String, _ value: Int, valueColor: Color = UITheme.textPrimary) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(UITheme.textDim)
            Spacer()
            Text(value.formatted())
                .font(.callout.monospacedDigit())
                .foregroundStyle(valueColor)
        }
    }

    // MARK: - Assets 网格

    private var assetGrid: some View {
        Group {
            if model.folderURL == nil {
                emptyState
            } else if model.assets.isEmpty {
                ContentUnavailableView(
                    "还没有资产",
                    systemImage: "photo.stack",
                    description: Text(model.statusText.isEmpty ? "这个文件夹里没有识别到照片文件" : model.statusText)
                )
                .foregroundStyle(UITheme.textDim)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 210), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(model.assets) { asset in
                            AssetCardView(
                                asset: asset,
                                thumbnailStore: model.thumbnails,
                                newBaseName: newBaseName(of: asset),
                                isAlreadyNamed: isAlreadyNamed(asset),
                                isSelected: model.selection == asset.id,
                                onSelect: { model.selection = asset.id },
                                onUndo: { Task { await model.undoAsset(asset) } }
                            )
                        }
                    }
                    .padding(16)
                    // 侧栏开合时禁止隐式动画逐卡动画（数百次 frame 动画 = 掉帧）；
                    // 列宽变化直接就位，只有 NavigationSplitView 自己做侧栏动画
                    .transaction { $0.animation = nil }
                }
                .background(UITheme.ground)
            }
        }
        .background(UITheme.ground)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(UITheme.textFaint)
            Text("选择一个照片文件夹开始")
                .font(.title3.weight(.medium))
                .foregroundStyle(UITheme.textPrimary)
            Text("本机、外接 SSD 或 SD 卡中的 RAW / JPEG / HEIC / XMP 都可以")
                .font(.callout)
                .foregroundStyle(UITheme.textDim)
            Button("选择文件夹…") { showImporter = true }
                .buttonStyle(.borderedProminent)
                .tint(UITheme.amber)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UITheme.ground)
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        Group {
            if let asset = model.selectedAsset {
                assetInspector(asset)
            } else {
                summaryInspector
            }
        }
        .background(UITheme.panel)
    }

    private var summaryInspector: some View {
        VStack(spacing: 12) {
            Text(model.statusText.isEmpty ? "选择一个资产查看详情" : model.statusText)
                .font(.headline)
                .foregroundStyle(UITheme.textPrimary)
                .multilineTextAlignment(.center)
            if let report = model.preflightReport {
                preflightSummary(report)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private func assetInspector(_ asset: PhotoAsset) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(baseName(of: asset))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(UITheme.textPrimary)

                let meta = model.assetMetadata[asset.id]
                inspectorRow("拍摄时间", meta?.captureTime.map { Self.timeFormatter.string(from: $0) } ?? "—")
                inspectorRow("机身", meta?.cameraModel ?? "—")
                inspectorRow("镜头", meta?.lensModel ?? "—")
                if let source = meta?.captureTimeSource, source != .exif {
                    // F-05：用了 fallback 必须显式展示
                    inspectorRow("时间来源", source.displayName, badge: "FALLBACK", badgeColor: UITheme.orange)
                }

                Divider()
                    .overlay(UITheme.line)

                Text("资源")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(UITheme.textFaint)
                    .textCase(.uppercase)
                let planned = model.operations(for: asset)
                ForEach(Array(asset.resources.enumerated()), id: \.offset) { index, resource in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(resource.originalFilename)
                            .font(.caption.monospaced())
                            .foregroundStyle(UITheme.textDim)
                        if index < planned.count {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                Text(planned[index].newURL.lastPathComponent)
                                    .font(.caption.monospaced())
                            }
                            .foregroundStyle(UITheme.green)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(UITheme.well, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inspectorRow(_ label: String, _ value: String, badge: String? = nil, badgeColor: Color = UITheme.amber) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.callout)
                .foregroundStyle(UITheme.textFaint)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundStyle(UITheme.textPrimary)
                .textSelection(.enabled)
            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(badgeColor.opacity(0.5), lineWidth: 1)
                    )
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 底部工作流条（Template → Preview → Preflight → Rename）

    private var workflowBar: some View {
        VStack(spacing: 0) {
            if let report = model.preflightReport, !report.issues.isEmpty {
                preflightSummary(report)
            }
            if let sample = model.templateSample {
                templateSampleLine(sample)
            }
            ViewThatFits(in: .horizontal) {
                // 宽：单行。预设用紧凑菜单——分段控件的最小渲染宽度大于其上报的
                // 理想宽度，在 ViewThatFits 里会"量着能放下、画出来超宽被裁"（实测踩坑）
                HStack(spacing: 10) {
                    menuPresets
                    templateField.frame(maxWidth: 280)
                    insertVariableMenu
                    projectField.frame(maxWidth: 200)
                    Spacer(minLength: 8)
                    statusText
                    undoButton
                    executeButton
                }
                // 窄：两行（编辑一行、动作一行），收掉状态文字
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        menuPresets
                        templateField
                        insertVariableMenu
                    }
                    HStack(spacing: 10) {
                        projectField
                        Spacer(minLength: 8)
                        undoButton
                        executeButton
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .background(UITheme.panel)
    }

    /// 紧凑预设入口：显示当前预设名，点开选择（自定义模板时显示"预设"）
    private var menuPresets: some View {
        Menu {
            ForEach(RenameTemplate.builtinPresets, id: \.pattern) { preset in
                Button(preset.name) { model.templatePattern = preset.pattern }
            }
        } label: {
            Label(currentPresetName, systemImage: "list.bullet")
        }
        .fixedSize()
    }

    private var currentPresetName: String {
        RenameTemplate.builtinPresets.first { $0.pattern == model.templatePattern }?.name ?? "预设"
    }

    private var templateField: some View {
        HStack(spacing: 6) {
            Text("模板")
                .font(.callout)
                .foregroundStyle(UITheme.textFaint)
            TextField("{YYYY}{MM}{DD}_{index}", text: $model.templatePattern)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5).monospaced())
                .foregroundStyle(UITheme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(UITheme.well, in: RoundedRectangle(cornerRadius: 7))
    }

    private var projectField: some View {
        HStack(spacing: 6) {
            Text("项目")
                .font(.callout)
                .foregroundStyle(UITheme.textFaint)
            TextField("可选，配合 {project}", text: $model.projectName)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(UITheme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(UITheme.well, in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private var statusText: some View {
        if !model.statusText.isEmpty {
            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(UITheme.textDim)
                .lineLimit(1)
        }
    }

    private var undoButton: some View {
        Button("撤销上一批") { Task { await model.undoLastBatch() } }
            .disabled(!model.canUndo || model.isBusy)
    }

    private var executeButton: some View {
        Button("执行重命名") { Task { await model.executePlan() } }
            .fontWeight(.semibold)
            .foregroundStyle(.black.opacity(0.85))
            .tint(UITheme.amber)
            .buttonStyle(.borderedProminent)
            .disabled(model.plan == nil || model.plan?.operations.isEmpty == true || model.preflightReport?.canExecute == false || model.isBusy)
    }

    /// 变量以菜单分组插入（追加到模板末尾，用户可再编辑微调）
    private var insertVariableMenu: some View {
        Menu {
            Menu("时间") {
                ForEach(["{YYYY}", "{MM}", "{DD}", "{HH}", "{mm}", "{ss}"], id: \.self) {
                    insertVariableButton($0)
                }
            }
            Menu("拍摄信息") {
                ForEach(["{camera}", "{lens}"], id: \.self) {
                    insertVariableButton($0)
                }
            }
            Menu("其他") {
                ForEach(["{index}", "{original}", "{project}"], id: \.self) {
                    insertVariableButton($0)
                }
            }
        } label: {
            Image(systemName: "curlybraces.square")
                .font(.system(size: 14))
                .foregroundStyle(UITheme.textDim)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("插入模板变量")
    }

    private func insertVariableButton(_ variable: String) -> some View {
        Button(variable) { model.templatePattern += variable }
    }

    @ViewBuilder
    private func templateSampleLine(_ sample: TemplateSamplePreview.Outcome) -> some View {
        HStack(spacing: 6) {
            switch sample {
            case .rendered(let name):
                Label {
                    Text("示例：\(name)")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                }
                .foregroundStyle(UITheme.textDim)
            case .failed(let error):
                Label(sampleErrorMessage(for: error), systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(UITheme.orange)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private func sampleErrorMessage(for error: TemplateError) -> String {
        switch error {
        case .missingCaptureTime:
            return "该资产缺少拍摄时间，日期变量无法预览"
        case .missingProjectName:
            return "模板使用了 {project}，请填写项目名"
        case .unknownVariable(let name):
            return "未知变量 {\(name)}，请检查模板"
        }
    }

    private func preflightSummary(_ report: PreflightReport) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                Label(issue.message, systemImage: issue.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(issue.isBlocking ? UITheme.red : UITheme.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(report.canExecute ? UITheme.orange.opacity(0.08) : UITheme.red.opacity(0.08))
    }

    private func interruptedBatchBanner(_ batch: InterruptedBatch) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundStyle(UITheme.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("检测到上次执行中断：\(batch.completed.count) 个文件已改名，\(batch.pending.count) 个未执行")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(UITheme.textPrimary)
                if !batch.conflicts.isEmpty {
                    Text("\(batch.conflicts.count) 个文件状态异常（源与目标同时存在/缺失），已跳过，请手动检查")
                        .font(.caption)
                        .foregroundStyle(UITheme.orange)
                }
            }
            Spacer()
            Button("忽略") { model.dismissInterruptedBatch() }
                .disabled(model.isBusy)
            Button("回退已改名文件") { Task { await model.rollbackInterruptedBatch() } }
                .buttonStyle(.borderedProminent)
                .tint(UITheme.orange)
                .disabled(model.isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(UITheme.orange.opacity(0.12))
    }

    // MARK: - 工具

    private func baseName(of asset: PhotoAsset) -> String {
        asset.resources.first.map { $0.url.deletingPathExtension().lastPathComponent } ?? "未知"
    }

    /// 该资产在当前方案中的新基础名（无预览方案或无操作时为 nil）
    private func newBaseName(of asset: PhotoAsset) -> String? {
        model.operations(for: asset).first.map { $0.newURL.deletingPathExtension().lastPathComponent }
    }

    /// 方案存在但该资产无操作 = 文件已符合模板（显示"已改名"）
    private func isAlreadyNamed(_ asset: PhotoAsset) -> Bool {
        model.plan != nil && model.operations(for: asset).isEmpty
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
