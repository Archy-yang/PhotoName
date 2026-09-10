import Foundation
import StoreKit

/// Pro 权益状态（商业化文档 §28）：
/// Source of Truth 是 StoreKit Transaction（`Transaction.currentEntitlements`），
/// 本地缓存仅用于快速启动——冷启动先读缓存，`refresh()` 后以 StoreKit 为准。
/// 买断制 NonConsumable（`com.photoname.pro`），无订阅、无账号（§40-41）。
@MainActor @Observable
final class EntitlementManager {
    static let proProductID = "com.photoname.pro"
    static let shared = EntitlementManager()

    private(set) var isPro: Bool

    private let defaults: UserDefaults
    private static let cacheKey = "entitlement.isPro"

    /// `defaults` 可注入（测试用独立 suite）；生产用 `.standard`
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 冷启动：先读缓存，后续 refresh() 以 StoreKit 为准
        self.isPro = defaults.bool(forKey: Self.cacheKey)
    }

    /// 遍历当前有效权益，匹配 Pro 产品（已退款/撤销的交易不会出现在 currentEntitlements）
    func refresh() async {
        var pro = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.productID == Self.proProductID,
               transaction.revocationDate == nil {
                pro = true
                break
            }
        }
        setPro(pro)
    }

    /// 购买成功后由 PurchaseManager 调用：调用方手里持有 verified Transaction（即 StoreKit 真相），
    /// 直接激活并写缓存。不等 `Transaction.currentEntitlements` 的异步传播——
    /// 该列表更新有延迟，购买后立刻 refresh 会读到旧状态把 isPro 覆盖回 false。
    func activate(productID: String) {
        guard productID == Self.proProductID else { return }
        setPro(true)
    }

    private func setPro(_ value: Bool) {
        isPro = value
        defaults.set(value, forKey: Self.cacheKey)
    }

    /// 测试辅助：读取被测实例使用的 defaults suite（验证跨实例缓存）
    var defaultsForTesting: UserDefaults { defaults }
}
