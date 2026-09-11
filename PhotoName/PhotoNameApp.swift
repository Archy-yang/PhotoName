import SwiftUI

@main
struct PhotoNameApp: App {
    @State private var entitlements = EntitlementManager.shared
    @State private var featureGate = FeatureGate()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(featureGate)
        }
        .defaultSize(width: 1360, height: 840)

        Settings {
            CommerceSettingsView()
        }
    }
}

struct ContentView: View {
    @Environment(FeatureGate.self) private var featureGate

    var body: some View {
        AssetBrowserView()
    }
}
