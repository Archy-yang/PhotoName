import Foundation

/// 用户保存的自定义模板（Pro 卖点：命名规则存起来重复使用，不必每次手敲）
struct UserTemplatePreset: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var pattern: String
}
