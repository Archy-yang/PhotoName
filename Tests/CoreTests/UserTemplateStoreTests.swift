import XCTest
@testable import PhotoName

/// 用户自定义模板的保存/删除与持久化（Pro 卖点：命名规则保存后重复使用）
@MainActor
final class UserTemplateStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "user-template-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    func test_default_isEmpty() {
        XCTAssertTrue(UserTemplateStore(defaults: defaults).presets.isEmpty)
    }

    func test_save_appendsNamedPreset_andPersistsAcrossInstances() {
        let store = UserTemplateStore(defaults: defaults)
        store.save(name: "婚礼", pattern: "{project}_{YYYY}{MM}{DD}_{index}")

        let reloaded = UserTemplateStore(defaults: defaults)

        XCTAssertEqual(reloaded.presets.count, 1)
        XCTAssertEqual(reloaded.presets[0].name, "婚礼")
        XCTAssertEqual(reloaded.presets[0].pattern, "{project}_{YYYY}{MM}{DD}_{index}")
    }

    /// 同名保存 = 更新 pattern（用户微调模板后用原名覆盖），不产生重名项
    func test_save_withExistingName_updatesPatternInPlace() {
        let store = UserTemplateStore(defaults: defaults)
        store.save(name: "婚礼", pattern: "{project}_{index}")
        store.save(name: "婚礼", pattern: "{project}_{YYYY}_{index}")

        let reloaded = UserTemplateStore(defaults: defaults)

        XCTAssertEqual(reloaded.presets.count, 1)
        XCTAssertEqual(reloaded.presets[0].pattern, "{project}_{YYYY}_{index}")
    }

    func test_save_keepsInsertionOrder() {
        let store = UserTemplateStore(defaults: defaults)
        store.save(name: "A", pattern: "{index}")
        store.save(name: "B", pattern: "{camera}_{index}")

        XCTAssertEqual(UserTemplateStore(defaults: defaults).presets.map(\.name), ["A", "B"])
    }

    func test_delete_removesPreset_andPersists() {
        let store = UserTemplateStore(defaults: defaults)
        store.save(name: "A", pattern: "{index}")
        store.save(name: "B", pattern: "{camera}_{index}")
        guard let id = store.presets.first(where: { $0.name == "A" })?.id else {
            return XCTFail("保存后应能取回 id")
        }

        store.delete(id)

        let reloaded = UserTemplateStore(defaults: defaults)
        XCTAssertEqual(reloaded.presets.map(\.name), ["B"])
    }
}
