import CoreGraphics
import Foundation

/// 缩略图缓存：NSCache 存储（线程安全、内存紧张自动驱逐、离屏卡片自动丢弃）。
///
/// 架构约束：刻意**不是** @Observable。若所有卡片观察同一份缓存，任何一张图
/// 解码完成都会让整个网格重绘（千级资产 = 渲染风暴，侧栏开合/滚动都卡顿）。
/// 正确分工：缓存只做跨重建的存取（非观察），卡片各自持 @State 图像，
/// 只因自己的加载完成而重绘一次。
final class ThumbnailStore: @unchecked Sendable {
    private let cache = NSCache<NSUUID, ImageBox>()
    private let provider = ThumbnailProvider()

    init(countLimit: Int = 900) {
        cache.countLimit = countLimit
    }

    /// 未命中则在后台解码并写入缓存（调用方在视图 `.task` 中 await）
    func image(for resource: PhotoResource) async -> CGImage? {
        if let hit = cache.object(forKey: resource.id as NSUUID) { return hit.image }
        guard resource.kind != .xmp else { return nil }
        let url = resource.url
        let image = await Task.detached(priority: .utility) {
            self.provider.thumbnail(for: url, maxPixelSize: Self.maxPixelSize)
        }.value
        if let image {
            cache.setObject(ImageBox(image), forKey: resource.id as NSUUID)
        }
        return image
    }

    func invalidateAll() {
        cache.removeAllObjects()
    }

    nonisolated static let maxPixelSize = 480
}

/// NSCache 只存对象类型，包一层
private final class ImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
