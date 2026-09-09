import XCTest
@testable import PhotoName

/// 内置 Preset 选择器（PRD F-07）的数据基础：每个预设要有用户可读的名字
final class RenameTemplatePresetTests: XCTestCase {
    func test_builtinPresets_carryDisplayNames() {
        XCTAssertEqual(RenameTemplate.builtinPresets.map(\.name), [
            "日期_序号",
            "日期_机身_序号",
            "项目_日期_序号",
            "项目_日期_机身_序号",
        ])
    }

    func test_builtinPresets_patternsUnchanged() {
        // F-07 固化的 4 个 pattern 不应被改名动作破坏
        XCTAssertEqual(RenameTemplate.builtinPresets.map(\.pattern), [
            "{YYYY}{MM}{DD}_{index}",
            "{YYYY}{MM}{DD}_{camera}_{index}",
            "{project}_{YYYY}{MM}{DD}_{index}",
            "{project}_{YYYY}{MM}{DD}_{camera}_{index}",
        ])
    }
}
