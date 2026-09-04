import Foundation

/// 命名模板（PRD F-06）。pattern 只生成基础名，扩展名由 RenamePlan 按资源保留
/// （对 PRD 变量表的有意偏离：不需要 {ext}，因为一个资产的 RAW/JPEG/XMP 扩展名各不相同）。
struct RenameTemplate: Sendable, Equatable {
    /// 变量语法：`{YYYY}` 月份用 `{MM}`、分钟用 `{mm}`（大小写区分）
    var pattern: String

    init(pattern: String) {
        self.pattern = pattern
    }
}

extension RenameTemplate {
    /// 内置预设（PRD F-07）
    static let builtinPresets: [RenameTemplate] = [
        RenameTemplate(pattern: "{YYYY}{MM}{DD}_{index}"),
        RenameTemplate(pattern: "{YYYY}{MM}{DD}_{camera}_{index}"),
        RenameTemplate(pattern: "{project}_{YYYY}{MM}{DD}_{index}"),
        RenameTemplate(pattern: "{project}_{YYYY}{MM}{DD}_{camera}_{index}"),
    ]
}
