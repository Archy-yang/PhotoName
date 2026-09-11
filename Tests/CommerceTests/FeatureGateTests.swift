import XCTest
@testable import PhotoName

/// C2 Free/Pro 分层（商业化文档 §27）：核心安全功能永不收费（§8），
/// 买断制解锁 Pro（无订阅，§40-41）。
@MainActor
final class FeatureGateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var entitlements: EntitlementManager!
    private var gate: FeatureGate!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "feature-gate-tests-\(UUID().uuidString)")
        entitlements = EntitlementManager(defaults: defaults)
        gate = FeatureGate(entitlements: entitlements)
    }

    // MARK: - 核心安全功能永不收费（§8：Scan/预览/预检/改名/撤销全部免费）

    func test_coreSafetyFeatures_availableOnFree() {
        entitlements.activate(productID: "")  // 确保 Free
        for feature in Feature.allCases where FeatureGate.freeFeatures.contains(feature) {
            XCTAssertTrue(gate.isAvailable(feature), "\(feature) 属于核心安全功能，Free 必须可用")
        }
    }

    // MARK: - 批量上限（Free 100 / Pro 无限）

    func test_free_batchWithinLimit_allowed() {
        entitlements.activate(productID: "")
        XCTAssertTrue(gate.canProcess(assetCount: 100), "恰好 100 组应放行")
        XCTAssertTrue(gate.canProcess(assetCount: 50))
    }

    func test_free_batchOverLimit_blocked() {
        entitlements.activate(productID: "")
        XCTAssertFalse(gate.canProcess(assetCount: 101))
        XCTAssertFalse(gate.canProcess(assetCount: 3000))
    }

    func test_pro_batchUnlimited() {
        entitlements.activate(productID: EntitlementManager.proProductID)
        XCTAssertTrue(gate.canProcess(assetCount: 3000))
        XCTAssertTrue(gate.canProcess(assetCount: 100_000))
    }

    // MARK: - 自定义模板（Pro 专属；内置预设免费）

    func test_builtinPresets_freeOnFreeTier() {
        entitlements.activate(productID: "")
        for pattern in RenameTemplate.builtinPresets.map(\.pattern) {
            XCTAssertTrue(gate.canUseTemplate(pattern), "内置预设「\(presetName(pattern))」应免费")
        }
    }

    func test_customTemplate_requiresPro() {
        entitlements.activate(productID: "")
        XCTAssertFalse(gate.canUseTemplate("{YYYY}_{camera}_{lens}_{index}"), "自定义模板 Free 应被拦")
    }

    func test_customTemplate_allowedOnPro() {
        entitlements.activate(productID: EntitlementManager.proProductID)
        XCTAssertTrue(gate.canUseTemplate("{YYYY}_{camera}_{lens}_{index}"))
    }

    /// 改过的内置预设（比如末尾加了变量）也算自定义
    func test_editedBuiltinPattern_countsAsCustom() {
        entitlements.activate(productID: "")
        XCTAssertFalse(gate.canUseTemplate("{YYYY}{MM}{DD}_{index}_{original}"))
    }

    // MARK: - 提示文案（§33：引导购买，禁止倒计时/强制弹窗/虚假折扣）

    func test_batchLimitMessage_mentionsLifetimePurchase() {
        entitlements.activate(productID: "")
        let message = gate.batchLimitMessage(assetCount: 300)
        let text = try! XCTUnwrap(message)
        XCTAssertTrue(text.contains("买断"), "文案必须强调买断而非订阅：\(text)")
    }

    func test_batchLimitMessage_nilWithinLimit() {
        entitlements.activate(productID: "")
        XCTAssertNil(gate.batchLimitMessage(assetCount: 100))
    }

    private func presetName(_ pattern: String) -> String {
        RenameTemplate.builtinPresets.first { $0.pattern == pattern }?.name ?? pattern
    }
}
