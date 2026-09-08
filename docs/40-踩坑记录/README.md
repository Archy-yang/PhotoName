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

### 2. Preflight 路径校验的不变量写错：应对比"源与目标同目录"，而非"目标是根目录直接子项"（2026-09-04）

**现象**：对含子目录的大目录（如 `PerfTest/DCIM/1000/DSC_0001.ARW`）生成预览，所有文件被误判为"非法文件名（子目录逃逸）"，整批永久阻塞。

**原因**：防路径逃逸的校验写成「目标必须是 `destinationDirectory` 的直接子项」。递归扫描下合法操作的目标本来就散布在各层子目录，与单一根目录比较必然全部误判。

**解决**：正确的不变量是**目标与原文件同目录**（重命名不跨目录），逐操作比较 `newURL.deletingLastPathComponent() == originalURL.deletingLastPathComponent()`。写权限检查同理：按操作目标目录的去重集合逐个检查，而不是只查一个传入的根目录。

**教训**：为安全检查写"不变量"时，先想清楚它在递归/嵌套场景下的语义；并用真实结构（含子目录）写回归测试。
