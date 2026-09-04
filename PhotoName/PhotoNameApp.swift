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
    }
}

struct ContentView: View {
    @Environment(FeatureGate.self) private var featureGate

    var body: some View {
        AssetBrowserView()
    }
}
