import XCTest
@testable import PhotoName

/// 模板与偏好的持久化：重启后恢复上次使用的模板、项目名、排序方式
@MainActor
final class RenameWorkflowModelPersistenceTests: XCTestCase {
    func test_templateAndProject_persistAcrossInstances() {
        let defaults = UserDefaults(suiteName: "wf-persist-\(UUID().uuidString)")!
        let first = RenameWorkflowModel(defaults: defaults)
        first.templatePattern = "{YYYY}_{camera}_{index}"
        first.projectName = "婚礼跟拍"

        let second = RenameWorkflowModel(defaults: defaults)

        XCTAssertEqual(second.templatePattern, "{YYYY}_{camera}_{index}")
        XCTAssertEqual(second.projectName, "婚礼跟拍")
    }

    func test_sortPreference_persistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: "wf-persist-\(UUID().uuidString)")!
        let first = RenameWorkflowModel(defaults: defaults)
        first.assetSort = .fileName

        let second = RenameWorkflowModel(defaults: defaults)

        XCTAssertEqual(second.assetSort, .fileName)
    }

    func test_defaultTemplate_isFirstBuiltinPreset() {
        let defaults = UserDefaults(suiteName: "wf-persist-\(UUID().uuidString)")!
        let model = RenameWorkflowModel(defaults: defaults)
        XCTAssertEqual(model.templatePattern, RenameTemplate.builtinPresets[0].pattern)
    }
}
