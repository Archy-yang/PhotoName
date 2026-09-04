import Foundation

/// 预检报告中的问题类型（PRD F-09）
enum PreflightIssueKind: Equatable, Sendable {
    /// 目标文件已存在（Never Overwrite）
    case destinationExists
    /// 批内产生重复目标名
    case duplicateDestination
    /// 目标名含文件系统非法字符
    case invalidTargetName
    /// 目标目录无写权限
    case folderNotWritable
    /// 资产缺少拍摄时间（EXIF）
    case missingCaptureTime
    /// 拍摄时间来自文件日期 fallback（非 EXIF），可能不准确（PRD F-05 要求显式展示）
    case fallbackCaptureTime
    /// RAW/JPEG 资产缺少 XMP sidecar
    case missingSidecar
}

extension PreflightIssueKind {
    /// 阻塞级问题禁止执行；警告级提示后允许继续（PRD F-09 策略：Missing Sidecar 等不强制阻止）
    var isBlocking: Bool {
        switch self {
        case .destinationExists, .duplicateDestination, .invalidTargetName, .folderNotWritable:
            return true
        case .missingCaptureTime, .fallbackCaptureTime, .missingSidecar:
            return false
        }
    }
}

/// 一条预检结果
struct PreflightIssue: Equatable, Sendable {
    let kind: PreflightIssueKind
    let message: String

    var isBlocking: Bool { kind.isBlocking }
}

/// 预检报告：Preview 生成后、执行前运行（PRD F-09）
struct PreflightReport: Equatable, Sendable {
    let issues: [PreflightIssue]

    var blockingIssues: [PreflightIssue] { issues.filter(\.isBlocking) }
    var warnings: [PreflightIssue] { issues.filter { !$0.isBlocking } }
    var canExecute: Bool { blockingIssues.isEmpty }
}

/// Rename 前的全部风险检查（PRD F-09 / §12 Explicit Warning）。
/// 阻塞级：目标已存在、批内重名、非法文件名、目录不可写；警告级：缺拍摄时间、缺 XMP sidecar。
struct PreflightEngine: Sendable {
    private static let illegalCharacters: Set<Character> = ["/", ":", "\\"]

    func run(
        plan: RenamePlan,
        assets: [PhotoAsset] = [],
        metadata: [UUID: PhotoMetadata] = [:],
        destinationDirectory: URL
    ) -> PreflightReport {
        var issues: [PreflightIssue] = []
        let operations = plan.operations

        // 1. 批内重复目标
        let targets = operations.map { $0.newURL.lastPathComponent }
        let duplicates = Dictionary(grouping: targets, by: { $0 }).filter { $0.value.count > 1 }
        if !duplicates.isEmpty {
            issues.append(PreflightIssue(
                kind: .duplicateDestination,
                message: "批内重复目标：\(duplicates.keys.sorted().joined(separator: "、"))（检查模板是否缺少 {index}）"
            ))
        }

        // 2. 目标已存在（Never Overwrite）
        let existing = operations.filter { FileManager.default.fileExists(atPath: $0.newURL.path) }
        if !existing.isEmpty {
            issues.append(PreflightIssue(
                kind: .destinationExists,
                message: "目标文件已存在：\(existing.prefix(3).map { $0.newURL.lastPathComponent }.joined(separator: "、"))\(existing.count > 3 ? " 等 \(existing.count) 个" : "")"
            ))
        }

        // 3. 非法目标名：名字本身非法，或目标不在目标目录的直接子项位置（防子目录逃逸）
        let destinationPath = destinationDirectory.standardizedFileURL.path
        let invalid = operations.filter { op in
            let name = op.newURL.lastPathComponent
            let escaped = op.newURL.deletingLastPathComponent().standardizedFileURL.path != destinationPath
            return name.isEmpty || name.hasPrefix(".")
                || name.contains(where: { Self.illegalCharacters.contains($0) })
                || escaped
        }
        if !invalid.isEmpty {
            issues.append(PreflightIssue(
                kind: .invalidTargetName,
                message: "非法文件名：\(invalid.prefix(3).map { $0.newURL.lastPathComponent }.joined(separator: "、"))"
            ))
        }

        // 4. 目录写权限
        if !FileManager.default.isWritableFile(atPath: destinationDirectory.path) {
            issues.append(PreflightIssue(
                kind: .folderNotWritable,
                message: "文件夹没有写权限：\(destinationDirectory.lastPathComponent)"
            ))
        }

        // 5a. 拍摄时间用了文件日期 fallback（PRD F-05：必须显式展示）
        let withFallbackTime = assets.filter {
            let source = metadata[$0.id]?.captureTimeSource
            return metadata[$0.id]?.captureTime != nil && source != .exif
        }
        if !withFallbackTime.isEmpty {
            let sources = Dictionary(grouping: withFallbackTime) {
                metadata[$0.id]?.captureTimeSource ?? .unavailable
            }
            let description = sources
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.value.count) 个（\($0.key.displayName)）" }
                .joined(separator: "、")
            issues.append(PreflightIssue(
                kind: .fallbackCaptureTime,
                message: "\(withFallbackTime.count) 个资产的拍摄时间来自文件日期而非 EXIF：\(description)，可能不准确"
            ))
        }

        // 5b. 完全缺拍摄时间（警告）
        let withoutTime = assets.filter { metadata[$0.id]?.captureTime == nil }
        if !withoutTime.isEmpty {
            issues.append(PreflightIssue(
                kind: .missingCaptureTime,
                message: "\(withoutTime.count) 个资产缺少拍摄时间：\(withoutTime.prefix(3).map { assetName($0) }.joined(separator: "、"))\(withoutTime.count > 3 ? " 等" : "")"
            ))
        }

        // 6. 缺 XMP sidecar（警告）
        for asset in assets where !asset.resources.contains(where: { $0.kind == .xmp }) {
            let hasImage = asset.resources.contains { $0.kind == .raw || $0.kind == .jpeg }
            if hasImage {
                issues.append(PreflightIssue(
                    kind: .missingSidecar,
                    message: "\(assetName(asset))：缺少 XMP sidecar"
                ))
            }
        }

        return PreflightReport(issues: issues)
    }

    private func assetName(_ asset: PhotoAsset) -> String {
        asset.resources.first.map { $0.url.deletingPathExtension().lastPathComponent } ?? "未知资产"
    }
}
