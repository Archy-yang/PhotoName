import Foundation
import StoreKit

/// StoreKit 唯一入口（商业化文档 §21-25）：商品加载、购买、恢复。
/// 权益判断不在这里——`EntitlementManager` 持有 isPro；本类只推动交易并触发其 refresh。
@MainActor @Observable
final class PurchaseManager {
    private(set) var proProduct: Product?
    private(set) var lastErrorMessage: String?

    private let entitlements: EntitlementManager

    init(entitlements: EntitlementManager = .shared) {
        self.entitlements = entitlements
    }

    /// 加载 Pro 买断商品（App 启动 / Paywall 展示前调用）
    func loadProducts() async {
        do {
            proProduct = try await Product.products(for: [EntitlementManager.proProductID]).first
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 购买 Pro（NonConsumable）。返回是否成功（取消/失败/pending 均为 false）。
    @discardableResult
    func purchasePro() async throws -> Bool {
        if proProduct == nil { await loadProducts() }
        guard let product = proProduct else {
            lastErrorMessage = "商品尚未加载（StoreKit 不可用？）"
            return false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastErrorMessage = "交易校验未通过"
                    return false
                }
                await transaction.finish()
                // 手里已是 verified Transaction，直接激活（不等 currentEntitlements 异步传播）
                entitlements.activate(productID: transaction.productID)
                return true
            case .userCancelled:
                return false
            case .pending:
                // 家庭共享审批等场景：暂不计入权益
                return false
            @unknown default:
                return false
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    /// 恢复购买（换机 / 重装 / 第二台设备）
    func restorePurchases() async {
        do {
            try? await AppStore.sync()
        }
        await entitlements.refresh()
    }
}
