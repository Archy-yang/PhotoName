import Foundation
import StoreKit

@MainActor @Observable
final class EntitlementManager {
    static let shared = EntitlementManager()

    private(set) var isPro: Bool = false

    private init() {}

    func update(from entitlements: Set<Product.SubscriptionInfo.RenewalState>) async {
        // Phase C1: Implement StoreKit entitlement check
        // For now, default to free
        isPro = false
    }

    func refresh() async {
        // Phase C1: Call StoreKit Transaction.currentEntitlements
    }
}
