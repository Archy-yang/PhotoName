# 30-踩坑记录

踩到就记一条，格式：**现象 → 原因 → 解决方案**。重点是解决方案可复现、可直接照做。

## 预期高频区域

- Swift 6 严格并发（Sendable、actor 隔离）与 SwiftUI `@Observable` 的组合
- StoreKit 2 测试（.storekit 配置文件、Transaction.currentEntitlements 的坑）
- XcodeGen（target 配置、entitlements、多平台条件编译）
- 摄影元数据读取（EXIF 时区问题、RAW 格式解析）

## 记录

### 1. XcodeGen 不会自动发现新文件（2026-09-03）

**现象**：新增 `.swift` 文件后直接 `xcodebuild` 构建或跑测试，报类型不存在 / 测试 bundle 无可执行文件。

**原因**：XcodeGen 只在执行 `xcodegen generate` 时扫描文件系统生成 `.pbxproj`，之后新增的文件对工程不可见。

**解决**：每次新增/删除/移动源文件后，先 `xcodegen generate` 再构建。只修改已有文件内容则不需要。
