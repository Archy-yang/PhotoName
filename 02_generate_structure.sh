#!/bin/bash
set -e

BASE="PhotoName"

echo "📁 Creating directory structure and skeleton files..."

# === Directories ===
dirs=(
  "$BASE/Domain"
  "$BASE/Core/Scanner"
  "$BASE/Core/Metadata"
  "$BASE/Core/AssetGrouping"
  "$BASE/Core/Sorting"
  "$BASE/Core/Template"
  "$BASE/Core/Preflight"
  "$BASE/Core/Rename"
  "$BASE/Core/Journal"
  "$BASE/Features/SourcePicker"
  "$BASE/Features/AssetBrowser"
  "$BASE/Features/TemplateEditor"
  "$BASE/Features/Preview"
  "$BASE/Features/Preflight"
  "$BASE/Features/Rename"
  "$BASE/Features/History"
  "$BASE/Commerce/Store"
  "$BASE/Commerce/Entitlement"
  "$BASE/Commerce/FeatureGate"
  "$BASE/Commerce/Paywall"
  "$BASE/Commerce/StoreKit"
  "$BASE/Platform/macOS"
  "$BASE/Platform/iPadOS"
  "Tests/DomainTests"
  "Tests/CoreTests"
  "Tests/CommerceTests"
)

for dir in "${dirs[@]}"; do
  mkdir -p "$dir"
done

# === Skeleton Files ===

# Domain/PhotoAsset.swift
cat > "$BASE/Domain/PhotoAsset.swift" << 'EOF'
import Foundation

/// 核心领域模型：一个摄影资产组（RAW + JPEG + XMP）
struct PhotoAsset: Identifiable, Sendable {
    let id: UUID
    let captureTime: Date?
    let cameraMake: String?
    let cameraModel: String?
    let lensModel: String?
    let resources: [PhotoResource]

    var originalFilename: String {
        resources.first?.originalFilename ?? "Unknown"
    }

    init(
        id: UUID = UUID(),
        captureTime: Date? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        resources: [PhotoResource] = []
    ) {
        self.id = id
        self.captureTime = captureTime
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.resources = resources
    }
}
EOF

# Domain/PhotoResource.swift
cat > "$BASE/Domain/PhotoResource.swift" << 'EOF'
import Foundation

enum ResourceKind: String, Sendable {
    case raw, jpeg, heic, xmp, video, unknown
}

struct PhotoResource: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let kind: ResourceKind
    let originalFilename: String
    let fileSize: Int64

    init(
        id: UUID = UUID(),
        url: URL,
        kind: ResourceKind = .unknown,
        originalFilename: String? = nil,
        fileSize: Int64 = 0
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.originalFilename = originalFilename ?? url.lastPathComponent
        self.fileSize = fileSize
    }
}
EOF

# Commerce/Entitlement/EntitlementManager.swift
cat > "$BASE/Commerce/Entitlement/EntitlementManager.swift" << 'EOF'
import Foundation
import StoreKit

@Observable
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
EOF

# Commerce/FeatureGate/FeatureGate.swift
cat > "$BASE/Commerce/FeatureGate/FeatureGate.swift" << 'EOF'
import Foundation

enum Feature: String, CaseIterable {
    case batchRename
    case customTemplate
    case multiCameraTimeline
    case cameraTimeOffset
    case ingestWorkflow
}

@Observable
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
EOF

# Entitlements file
cat > "$BASE/PhotoName.entitlements" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
EOF

# StoreKit Configuration
cat > "$BASE/Commerce/StoreKit/PhotoName.storekit" << 'EOF'
{
  "identifier" : "8A3B9C2D-1E4F-4A5B-8C6D-7E8F9A0B1C2D",
  "type" : "Configuration",
  "version" : 3,
  "products" : [
    {
      "id" : "com.photoname.pro",
      "type" : "NonConsumable",
      "displayName" : "PhotoName Pro",
      "description" : "Lifetime license for unlimited assets, custom templates, and professional workflows.",
      "price" : 9.99,
      "internalID" : "PRO_LIFETIME_001"
    }
  ],
  "settings" : {
    "_applicationInternalID" : "",
    "_developerTeamID" : ""
  }
}
EOF

# App Entry Point
cat > "$BASE/PhotoNameApp.swift" << 'EOF'
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
        NavigationSplitView {
            Text("Sources")
                .navigationTitle("PhotoName")
        } detail: {
            Text("Select a folder to begin")
                .foregroundStyle(.secondary)
        }
    }
}
EOF

echo "✅ All skeleton files created."
echo ""
echo "Next steps:"
echo "  1. Run: bash 01_create_project.sh"
echo "  2. Open PhotoName.xcodeproj in Xcode"
echo "  3. Select your Team in Signing & Capabilities"
echo "  4. Build & Run (⌘R)"
