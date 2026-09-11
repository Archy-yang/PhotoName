import Foundation
import ImageIO

/// 资产网格缩略图：CGImageSource 生成受限尺寸预览图（PRD §11 中央网格的图源）。
/// 纯函数、线程安全；失败（非图像/损坏/缺失）返回 nil，UI 展示占位图。
/// 真实 RAW 的可解码性取决于系统 RAW 支持，运行时验证（路线图已知项）。
struct ThumbnailProvider: Sendable {
    func thumbnail(for url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
