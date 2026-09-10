import Foundation
import CoreServices

/// 拍摄时间解析：按 PRD F-05 回退链取时间，并标记实际来源（fallback 必须显式展示）。
/// provider 可注入，便于验证深层回退顺序（真实文件系统上文件几乎总有创建日期，造不出来）。
struct CaptureTimeResolver: Sendable {
    struct Providers: Sendable {
        var mediaCreation: @Sendable (URL) -> Date?
        var fileCreation: @Sendable (URL) -> Date?
        var fileModification: @Sendable (URL) -> Date?

        /// 标准实现：Spotlight Media Creation Date → 文件创建日期 → 文件修改日期
        static let standard = Providers(
            mediaCreation: { url in
                #if os(macOS)
                // Spotlight 未索引的卷（部分外接盘/SD 卡）返回 nil，自然落到下一级
                guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
                return MDItemCopyAttribute(item, kMDItemContentCreationDate) as? Date
                #else
                // iOS 无 MDItem 文件元数据 API，直接落下一级（文件日期）
                return nil
                #endif
            },
            fileCreation: { url in
                try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
            },
            fileModification: { url in
                try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            }
        )
    }

    private let providers: Providers

    init(providers: Providers = .standard) {
        self.providers = providers
    }

    func resolve(url: URL, exifTime: Date?) -> (date: Date?, source: CaptureTimeSource) {
        if let exifTime {
            return (exifTime, .exif)
        }
        let fallbacks: [(Date?, CaptureTimeSource)] = [
            (providers.mediaCreation(url), .mediaCreationDate),
            (providers.fileCreation(url), .fileCreationDate),
            (providers.fileModification(url), .fileModificationDate),
        ]
        for (date, source) in fallbacks where date != nil {
            return (date, source)
        }
        return (nil, .unavailable)
    }
}
