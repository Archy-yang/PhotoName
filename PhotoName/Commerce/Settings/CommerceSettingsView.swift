import SwiftUI

/// 设置（C4 业务接入）：权益状态、升级/恢复入口、付费模式说明。
/// 只读 FeatureGate/EntitlementManager——商业逻辑不在此处（§26：UI 是展示层）。
struct CommerceSettingsView: View {
    @State private var gate = FeatureGate()
    @State private var purchases = PurchaseManager()
    @State private var showPaywall = false
    @State private var restoreMessage: String?

    var body: some View {
        Form {
            Section("权益") {
                if gate.isPro {
                    LabeledContent("当前版本") {
                        Label("Pro（已买断，终身有效）", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(UITheme.amber)
                    }
                } else {
                    LabeledContent("当前版本") { Text("Free") }
                    Button("升级 Pro…") { showPaywall = true }
                    Button("恢复购买") {
                        Task {
                            let restored = await purchases.restorePurchases()
                            restoreMessage = restored ? nil : "没有找到可恢复的购买"
                        }
                    }
                    .disabled(purchases.isRestoring)
                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.caption)
                            .foregroundStyle(UITheme.textDim)
                    }
                }
            }
            Section("关于") {
                LabeledContent("版本") { Text(Self.versionString) }
                LabeledContent("付费模式") { Text("一次买断 · 终身使用 · 无订阅") }
            }
        }
        .formStyle(.grouped)
        .preferredColorScheme(.dark)
        .frame(width: 420, height: 300)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private static let versionString: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }()
}
