import Foundation
import ImageIO

enum MetadataError: Error {
    /// 文件不是可读的图像源（损坏、非图片格式）
    case unreadableSource
}

/// 基于 ImageIO（CGImageSource）的元数据读取器（PRD F-03 的 Spike 实现）。
struct MetadataReader: Sendable {
    private static let exifFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    func readMetadata(at url: URL) throws -> PhotoMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            throw MetadataError.unreadableSource
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        return PhotoMetadata(
            captureTime: (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
                .flatMap(Self.exifFormatter.date(from:)),
            cameraMake: tiff?[kCGImagePropertyTIFFMake] as? String,
            cameraModel: tiff?[kCGImagePropertyTIFFModel] as? String,
            lensModel: exif?[kCGImagePropertyExifLensModel] as? String
        )
    }
}
