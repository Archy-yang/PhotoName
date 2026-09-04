import Foundation

/// 渲染模板所需的单资产上下文
struct TemplateContext: Sendable, Equatable {
    var captureTime: Date?
    var cameraModel: String?
    var lensModel: String?
    var originalBaseName: String
    var projectName: String?

    init(
        captureTime: Date? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        originalBaseName: String = "",
        projectName: String? = nil
    ) {
        self.captureTime = captureTime
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.originalBaseName = originalBaseName
        self.projectName = projectName
    }
}

enum TemplateError: Error, Equatable {
    /// 模板使用了日期变量，但该资产没有拍摄时间（应由 Preflight 呈现给用户，不能静默编造）
    case missingCaptureTime
    case missingProjectName
    case unknownVariable(String)
}

/// 将模板 + 上下文渲染成文件基础名（PRD F-06 / Phase 3 Template Engine 的 Phase 1 版本）。
struct TemplateRenderer: Sendable {
    private static let illegalFilenameCharacters: Set<Character> = ["/", ":", "\\"]

    func render(_ template: RenameTemplate, context: TemplateContext, index: Int) throws -> String {
        var result = ""
        var rest = Substring(template.pattern)

        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else {
                result += rest[open...]
                rest = ""
                break
            }
            let token = String(rest[rest.index(after: open)..<close])
            result += try render(token: token, context: context, index: index)
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }

    private func render(token: String, context: TemplateContext, index: Int) throws -> String {
        switch token {
        case "YYYY", "MM", "DD", "HH", "mm", "ss":
            guard let captureTime = context.captureTime else { throw TemplateError.missingCaptureTime }
            return dateComponent(of: captureTime, for: token)
        case "camera":
            return sanitize(context.cameraModel ?? "UnknownCamera")
        case "lens":
            return sanitize(context.lensModel ?? "UnknownLens")
        case "index":
            return String(index).leftPadded(to: 4)
        case "original":
            return context.originalBaseName
        case "project":
            guard let project = context.projectName, !project.isEmpty else {
                throw TemplateError.missingProjectName
            }
            return sanitize(project)
        default:
            throw TemplateError.unknownVariable(token)
        }
    }

    /// EXIF 时间按本机时区解释，与 MetadataReader 保持一致（已知限制，见路线图 Spike B 结论）
    private func dateComponent(of date: Date, for token: String) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        switch token {
        case "YYYY": return String(components.year ?? 0).leftPadded(to: 4)
        case "MM": return String(components.month ?? 0).leftPadded(to: 2)
        case "DD": return String(components.day ?? 0).leftPadded(to: 2)
        case "HH": return String(components.hour ?? 0).leftPadded(to: 2)
        case "mm": return String(components.minute ?? 0).leftPadded(to: 2)
        case "ss": return String(components.second ?? 0).leftPadded(to: 2)
        default: return ""
        }
    }

    /// 文件名中不允许出现的字符替换为 "-"
    private func sanitize(_ value: String) -> String {
        String(value.map { Self.illegalFilenameCharacters.contains($0) ? "-" : $0 })
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}
