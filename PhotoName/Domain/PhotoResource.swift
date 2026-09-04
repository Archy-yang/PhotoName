import Foundation

enum ResourceKind: String, Sendable {
    case raw, jpeg, heic, xmp, video, unknown

    /// 按文件扩展名分类（大小写不敏感）。RAW 覆盖 PRD F-02 第一阶段的清单。
    init(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "arw", "cr2", "cr3", "nef", "raf", "dng", "orf", "rw2":
            self = .raw
        case "jpg", "jpeg":
            self = .jpeg
        case "heic":
            self = .heic
        case "xmp":
            self = .xmp
        case "mov", "mp4":
            self = .video
        default:
            self = .unknown
        }
    }
}

struct PhotoResource: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let kind: ResourceKind
    let originalFilename: String
    let fileSize: Int64

    init(
        id: UUID = UUID(),
        url: URL,
        kind: ResourceKind = .unknown,
        originalFilename: String? = nil,
        fileSize: Int64 = 0
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.originalFilename = originalFilename ?? url.lastPathComponent
        self.fileSize = fileSize
    }
}
