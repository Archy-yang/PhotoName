import Foundation

/// 可分层的功能（商业化文档 §27）。核心安全功能永不收费（§8），其余 Pro 买断解锁。
enum Feature: String, CaseIterable {
    case batchRename
    case customTemplate
    case multiCameraTimeline
    case cameraTimeOffset
    case ingestWorkflow
}

/// Free/Pro 分层判断（C2）。只做判断，不关心交易——交易在 PurchaseManager，
/// 权益状态在 EntitlementManager；本类是两者对业务层的唯一读数。
@MainActor @Observable
final class FeatureGate {
    /// Free 单批资产组上限（商业化文档 §27：Batch ≤ 100）
    static let freeBatchLimit = 100
    /// 核心安全功能，任何层级永久可用（§8）
    static let freeFeatures: Set<Feature> = [.batchRename]

    private let entitlements: EntitlementManager

    init(entitlements: EntitlementManager = .shared) {
        self.entitlements = entitlements
    }

    var isPro: Bool { entitlements.isPro }

    func isAvailable(_ feature: Feature) -> Bool {
        FeatureGate.freeFeatures.contains(feature) || entitlements.isPro
    }

    /// 本批资产组数是否允许处理
    func canProcess(assetCount: Int) -> Bool {
        isPro || assetCount <= Self.freeBatchLimit
    }

    /// 模板是否可用：内置预设免费，自定义（含改过的内置）Pro 专属（F-07/§27）
    func canUseTemplate(_ pattern: String) -> Bool {
        isPro || RenameTemplate.builtinPresets.contains { $0.pattern == pattern }
    }

    /// 超限提示文案（§33：说明利害引导购买，无倒计时/无强制弹窗/无虚假折扣）
    func batchLimitMessage(assetCount: Int) -> String? {
        guard !canProcess(assetCount: assetCount) else { return nil }
        return "本批 \(assetCount) 组资产超出 Free 上限（\(Self.freeBatchLimit) 组）——升级 Pro 一次买断，终身使用无限批量"
    }

    func customTemplateMessage() -> String? {
        guard !isPro else { return nil }
        return "自定义模板是 Pro 功能——内置 4 个预设永久免费，升级 Pro 一次买断解锁全部模板"
    }
}
