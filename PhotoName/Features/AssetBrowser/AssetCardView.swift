import CoreGraphics
import SwiftUI

/// 资产卡片（原型定稿样式）：缩略图 + 格式角标 + 旧名→新名 + 扩展名 chips。
/// 状态：默认 / 选中（琥珀描边）/ 已改名（右上角绿✓，恒等方案）/ 预检冲突（红描边）。
/// 多资源资产（RAW+JPG+XMP）：点击扩展名 chip 切换缩略图显示对应文件。
struct AssetCardView: View {
    let asset: PhotoAsset
    let thumbnailStore: ThumbnailStore
    let newBaseName: String?
    /// 方案存在但该资产无操作（文件已符合模板）——显示绿✓而非误导性的"改名成自己"
    let isAlreadyNamed: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onUndo: () -> Void

    /// 当前展示的资源（默认第一个非 XMP 资源；XMP 无图像，仅在仅剩 sidecar 时兜底）
    @State private var displayedResourceID: UUID?
    /// 本卡的缩略图（按资源）。自持状态：图完成只重绘本卡，不惊动网格里的其他卡
    @State private var thumbnails: [UUID: CGImage] = [:]

    private func thumbnail(for resource: PhotoResource?) -> CGImage? {
        guard let resource else { return nil }
        return thumbnails[resource.id]
    }

    private var displayedResource: PhotoResource? {
        if let id = displayedResourceID, let match = asset.resources.first(where: { $0.id == id }) {
            return match
        }
        return asset.resources.first { $0.kind != .xmp } ?? asset.resources.first
    }

    var body: some View {
        VStack(spacing: 0) {
            thumbnailArea
            cardBody
        }
        .background(UITheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("撤销此资产的最近变更（整组）", action: onUndo)
        }
        // 解码在渲染期之外逐资源进行；结果写入本卡 @State（只重绘本卡）。
        // 重复进入可见区时命中 NSCache，秒回。
        .task(id: asset.id) {
            for resource in asset.resources {
                if let image = await thumbnailStore.image(for: resource) {
                    thumbnails[resource.id] = image
                }
            }
        }
    }

    private var borderColor: Color {
        isSelected ? UITheme.amber : UITheme.line.opacity(0.6)
    }

    private var thumbnailArea: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(UITheme.well)
            if let resource = displayedResource, let image = thumbnail(for: resource) {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(4 / 3, contentMode: .fill)
            } else {
                placeholder
            }
            if isAlreadyNamed {
                Label("已改名", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(UITheme.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            Text(kindBadge)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                .padding(7)
        }
        .aspectRatio(4 / 3, contentMode: .fit)
    }

    private var placeholder: some View {
        Image(systemName: displayedResource?.kind == .xmp ? "doc.text" : "photo")
            .font(.title2)
            .foregroundStyle(UITheme.textFaint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var kindBadge: String {
        switch displayedResource?.kind ?? .unknown {
        case .raw: return "RAW"
        case .heic: return "HEIC"
        case .jpeg: return "JPG"
        case .video: return "VIDEO"
        case .xmp: return "XMP"
        case .unknown: return "?"
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            namesRow
            HStack(spacing: 4) {
                ForEach(asset.resources) { resource in
                    extensionChip(resource)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 扩展名 chip = 缩略图切换器：点选后卡片显示该资源的缩略图
    private func extensionChip(_ resource: PhotoResource) -> some View {
        let isSelectedChip = displayedResource?.id == resource.id
        return Button {
            displayedResourceID = resource.id
        } label: {
            Text(resource.url.pathExtension.uppercased())
                .font(.system(size: 9.5).monospaced())
                .foregroundStyle(isSelectedChip ? UITheme.textPrimary : UITheme.textFaint)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    isSelectedChip ? UITheme.line : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelectedChip ? Color.clear : UITheme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var namesRow: some View {
        if let newBaseName {
            HStack(spacing: 5) {
                Text(asset.originalFilename.deletingExtension)
                    .font(.system(size: 12))
                    .foregroundStyle(UITheme.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundStyle(UITheme.textFaint)
                Text(newBaseName)
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(UITheme.green)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
        } else {
            Text(asset.originalFilename.deletingExtension)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isAlreadyNamed ? UITheme.textDim : UITheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private extension String {
    var deletingExtension: String {
        (self as NSString).deletingPathExtension.isEmpty ? self : (self as NSString).deletingPathExtension
    }
}
