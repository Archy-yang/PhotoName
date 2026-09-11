import SwiftUI
import StoreKit

/// Paywall（C3，商业化文档 §33 红线内）：
/// 只列已上线的权益、价格来自 StoreKit 商品、无倒计时/无强制弹窗/无虚假折扣，
/// 文案永远强调「一次买断 · 终身使用 · 无订阅」。
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var purchases = PurchaseManager()
    @State private var restoreMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    benefits
                    priceAndActions
                    if let error = purchases.lastErrorMessage {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(UITheme.red)
                    }
                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.caption)
                            .foregroundStyle(UITheme.textDim)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .background(UITheme.ground)
        .frame(minWidth: 440, minHeight: 520)
        .task { await purchases.loadProducts() }
        // 买断生效即关闭（权益全局生效，FeatureGate/界面自动解锁）
        .onChange(of: purchases.entitlementsIsPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("PhotoName Pro")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(UITheme.textPrimary)
            } icon: {
                Image(systemName: "seal.fill")
                    .foregroundStyle(UITheme.amber)
            }
            Text("一次买断 · 终身使用 · 无订阅")
                .font(.callout.weight(.medium))
                .foregroundStyle(UITheme.amber)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow("infinity", "无限批量处理", "Free 单批上限 \(FeatureGate.freeBatchLimit) 组资产，Pro 不限量")
            benefitRow("slider.horizontal.3", "自定义命名模板", "11 个变量自由组合；4 个内置预设永久免费")
            benefitRow("checkmark.shield", "完整安全流程不变", "预检 / Never Overwrite / 整组撤销，所有版本一致")
        }
        .padding(16)
        .background(UITheme.card, in: RoundedRectangle(cornerRadius: 10))
    }

    private func benefitRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(UITheme.amber)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(UITheme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(UITheme.textDim)
            }
        }
    }

    @ViewBuilder
    private var priceAndActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let product = purchases.proProduct {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(product.displayPrice)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(UITheme.textPrimary)
                    Text("一次付清，永久有效")
                        .font(.caption)
                        .foregroundStyle(UITheme.textDim)
                }
            } else {
                Text(purchases.lastErrorMessage == nil ? "正在获取商品…" : "商品暂不可用")
                    .font(.callout)
                    .foregroundStyle(UITheme.textDim)
            }

            Button {
                Task { _ = try? await purchases.purchasePro() }
            } label: {
                HStack {
                    if purchases.isPurchasing {
                        ProgressView().controlSize(.small)
                    }
                    Text(purchases.isPurchasing ? "购买中…" : "购买 Pro")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(UITheme.amber)
            .foregroundStyle(.black.opacity(0.85))
            .disabled(purchases.proProduct == nil || purchases.isPurchasing)

            Button {
                Task {
                    let restored = await purchases.restorePurchases()
                    restoreMessage = restored ? nil : "没有找到可恢复的购买（恢复仅针对本 Apple 账户已购项目）"
                }
            } label: {
                HStack {
                    if purchases.isRestoring {
                        ProgressView().controlSize(.small)
                    }
                    Text(purchases.isRestoring ? "恢复中…" : "恢复购买")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(purchases.isRestoring)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("买断即终身使用；价格上调不影响已购用户。")
            Text("权益与本机 Apple 账户绑定，换机或重装后可随时「恢复购买」。")
        }
        .font(.caption2)
        .foregroundStyle(UITheme.textFaint)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UITheme.panel)
    }
}
