import Foundation

enum Feature: String, CaseIterable {
    case batchRename
    case customTemplate
    case multiCameraTimeline
    case cameraTimeOffset
    case ingestWorkflow
}

@MainActor @Observable
final class FeatureGate {
    private let entitlements: EntitlementManager

    init(entitlements: EntitlementManager = .shared) {
        self.entitlements = entitlements
    }

    func isAvailable(_ feature: Feature) -> Bool {
        guard entitlements.isPro else { return false }
        // Phase C2: Map features to entitlements
        return true
    }

    func canProcess(assetCount: Int) -> Bool {
        if entitlements.isPro { return true }
        return assetCount <= 100  // Free tier limit
    }
}
