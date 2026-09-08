import SwiftUI
import UniformTypeIdentifiers

/// 三栏主界面（PRD §11）：Sources / Assets / Inspector + 底部工作流条
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
                assetList
                    .navigationSplitViewColumnWidth(min: 280, ideal: 360)
            } detail: {
                inspector
            }
            // 工作流条放在 VStack 中占独立空间，列表内容不会被遮挡
            workflowBar
        }
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
            Button {
                showImporter = true
            } label: {
                Label("选择文件夹…", systemImage: "folder.badge.plus")
            }
            if let url = model.folderURL {
                Section("当前来源") {
                    Label(url.lastPathComponent, systemImage: "folder.fill")
                    Label("\(model.assets.count) 组资产", systemImage: "photo.on.rectangle.angled")
                    Label("\(model.assets.reduce(0) { $0 + $1.resources.count }) 个文件", systemImage: "doc.text")
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Assets 列表

    private var assetList: some View {
        Group {
            if model.assets.isEmpty {
                ContentUnavailableView(
                    "还没有资产",
                    systemImage: "photo.stack",
                    description: Text(model.statusText.isEmpty ? "选择一个照片文件夹开始" : model.statusText)
                )
            } else {
                List(selection: $model.selection) {
                    if model.plan != nil {
                        Section("改名预览") {
                            ForEach(Array(model.plan!.operations.enumerated()), id: \.offset) { _, operation in
                                HStack(spacing: 8) {
                                    Text(operation.originalURL.lastPathComponent)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                    Text(operation.newURL.lastPathComponent)
                                        .font(.caption.monospaced())
                                }
                            }
                        }
                    }
                    Section("资产（\(model.assets.count) 组）") {
                        ForEach(model.assets) { asset in
                            VStack(alignment: .leading) {
                                Text(baseName(of: asset))
                                    .font(.callout.weight(.medium))
                                Text(asset.resources.map(\.originalFilename).joined(separator: "  ·  "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(asset.id)
                            .contextMenu {
                                Button("撤销此资产的最近变更（整组）") {
                                    Task { await model.undoAsset(asset) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        if let asset = model.selectedAsset {
            assetInspector(asset)
        } else {
            summaryInspector
        }
    }

    private var summaryInspector: some View {
        VStack(spacing: 12) {
            Text(model.statusText.isEmpty ? "选择一个资产查看详情" : model.statusText)
                .font(.headline)
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

                let meta = model.assetMetadata[asset.id]
                inspectorRow("拍摄时间", meta?.captureTime.map { Self.timeFormatter.string(from: $0) } ?? "—")
                inspectorRow("机身", meta?.cameraModel ?? "—")
                inspectorRow("镜头", meta?.lensModel ?? "—")

                Divider()

                Text("资源")
                    .font(.subheadline.weight(.semibold))
                let planned = model.operations(for: asset)
                ForEach(Array(asset.resources.enumerated()), id: \.offset) { index, resource in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(resource.originalFilename)
                            .font(.caption.monospaced())
                        if index < planned.count {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                Text(planned[index].newURL.lastPathComponent)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    // MARK: - 底部工作流条（Template → Preview → Preflight → Rename）

    private var workflowBar: some View {
        VStack(spacing: 8) {
            if let report = model.preflightReport, !report.issues.isEmpty {
                preflightSummary(report)
            }
            HStack(spacing: 12) {
                Text("模板")
                    .font(.callout)
                TextField("{YYYY}{MM}{DD}_{index}", text: $model.templatePattern)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                Text("项目")
                    .font(.callout)
                TextField("可选，配合 {project}", text: $model.projectName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                Spacer()
                if !model.statusText.isEmpty {
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button("撤销上一批") { Task { await model.undoLastBatch() } }
                    .disabled(!model.canUndo || model.isBusy)
                Button("生成预览") { Task { await model.makePreviewPlan() } }
                    .disabled(model.assets.isEmpty || model.templatePattern.isEmpty || model.isBusy)
                Button("执行重命名") { Task { await model.executePlan() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.plan == nil || model.preflightReport?.canExecute == false || model.isBusy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func preflightSummary(_ report: PreflightReport) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                Label(issue.message, systemImage: issue.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(issue.isBlocking ? .red : .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - 工具

    private func baseName(of asset: PhotoAsset) -> String {
        asset.resources.first.map { $0.url.deletingPathExtension().lastPathComponent } ?? "未知"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
