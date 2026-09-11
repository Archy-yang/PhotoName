# Changelog

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循语义化版本。

## [Unreleased]

### Added

- **Commerce C2–C4 商业闭环**（2026-09-11）：C2 FeatureGate 分层（Free 批量 ≤100 / 自定义模板 Pro，安全功能永不收费）；C3 Paywall（真实商品价格、买断语义文案、购买/恢复、§33 红线内）；C4 Settings 接入（权益状态/升级/恢复/关于，Core 零侵入）。无开发者账号，全程基于本地 .storekit 模拟环境开发自测；C5 上架验证 blocked 待账号
- **暗色摄影工具风 UI**（2026-09-11，界面原型定稿落地）：资产网格化——`ThumbnailProvider`（CGImageSource 后台解码）+ NSCache 缩略图缓存（上限 900 张，卡片自持状态只重绘自己）；卡片 = 缩略图 + RAW/HEIC 角标 + 旧名→绿色新名 + 扩展名 chips（**可点击切换各资源缩略图**）；「已改名」绿✓（恒等方案）右上角；全局暗色 token（`UITheme` 常量对应原型）；空态引导；工作流条自适应（宽单行/窄两行，预设紧凑菜单——分段控件上报宽度小于实际渲染宽度会裁切，踩坑）

- **暗色摄影工具风 UI**（2026-09-11，界面原型定稿落地）：资产网格化——`ThumbnailProvider`（CGImageSource 后台解码）+ NSCache 缩略图缓存（上限 900 张，卡片自持状态只重绘自己）；卡片 = 缩略图 + RAW/HEIC 角标 + 旧名→绿色新名 + 扩展名 chips（**可点击切换各资源缩略图**）；「已改名」绿✓（恒等方案）右上角；全局暗色 token（`UITheme` 常量对应原型）；空态引导；工作流条自适应（宽单行/窄两行，预设紧凑菜单——分段控件上报宽度小于实际渲染宽度会裁切，踩坑）

- **F-05 拍摄时间 fallback 链**（2026-09-04）：`CaptureTimeResolver` 按 EXIF → 媒体创建日期（Spotlight）→ 文件创建日期 → 文件修改日期取时间；实际来源记入 `captureTimeSource`，预检对非 EXIF 来源发橙色警告
- **模板 Preset 选择器 + 实时预览**（2026-09-08）：内置预设带显示名（日期_序号等 4 个）；模板/项目名改动 400ms 防抖后自动重新预览，「生成预览」按钮移除；示例名即时渲染（复用 `RenamePlanner` 保证与执行输出一致），模板错误（缺拍摄时间/缺项目名/未知变量）当场提示
- **元数据缓存**：EXIF 读取仅在资产集合变化时执行，模板实时预览不再重读大目录
- **预览融入资产列表**：每行「原名 → 新名（绿色）」，独立的改名预览 Section 移除
- **Crash Recovery**（2026-09-10，Phase 5 收尾）：批量执行前把完整意图清单原子写入活动标记文件，成功后清除；中断后启动时对照磁盘调和现场（已完成/未执行/冲突三类，冲突绝不自动处理），UI 橙色横幅引导「回退已改名文件 / 忽略」。Journal 64 条缓冲的崩溃丢记录窗口由标记兜底——丢的只是账本，意图清单永远完整
- **Commerce C0 StoreKit Spike**（2026-09-10）：`PurchaseManager`（StoreKit 唯一入口：加载/购买/恢复）+ `EntitlementManager` 买断制重构（NonConsumable `com.photoname.pro`，`Transaction.currentEntitlements` 为 Source of Truth，本地缓存快速启动，退款自动失效）；`.storekit` 配置规范化并挂载到 scheme；SKTestSession 全链路测试（购买/退款/恢复/失败注入/缓存跨实例）
- **iOS target 构建恢复**：Spotlight MDItem 与 bookmark security-scope 的平台守卫（`#if os(macOS)`），iOS scheme 构建通过

### Fixed

- **资产级撤销跨扫描失效**（2026-09-11）：`undoAsset` 原按 assetID 匹配 Journal，而每次扫描生成新 UUID——执行后刷新列表/跨会话必然失配。改为按**路径**匹配（回归测试锁死"撤一组不波及其他组"），旧格式记录保留 assetID 兜底
- **网格渲染死循环卡死**（2026-09-11）：缩略图缓存在视图 body 内写入 @Observable 状态 → 重渲染 → 再写 → 主线程饿死。改为 body 只读 + `.task` 渲染期外解码 + 卡片自持图像状态；侧栏开合掉帧同步解决（缓存去观察化 + 操作索引 O(1) + 网格禁用逐卡隐式动画）
- 单测宿主下跳过文件夹自动恢复（此前测试宿主启动时扫 3000 文件导致进程挂起不退出）
- **恒等重命名被误判为冲突**（2026-09-08）：执行后重新预览时新名 == 原名，Never Overwrite 误报"目标已存在"整批阻塞。`RenamePlanner` 过滤恒等操作（已命名目录 → "无需重命名"），`RenameTransaction` 防御性再过滤；踩坑记录 #3
- 资产列表最后一行被底部工作流条遮挡（VStack 布局替代 overlay）

### Performance

- 大目录（3000 文件）验证通过：扫描/EXIF/预检/执行全程异步 + 进度反馈；Journal 按 64 条缓冲批量落盘（消除 O(n²) 整文件重写；崩溃丢记录窗口由 Crash Recovery 收口，进行中）

## [v0.1.0] - 2026-09-04

首个内部里程碑：PRD §8 核心工作流端到端打通（骨架级实现，macOS）。

### Added

- **核心工作流**（PRD §8）：选目录 → 扫描 → EXIF 读取 → 资产配对 → 模板命名 → 预览 → 预检 → 批量重命名 → 撤销
- `PhotoScanner`：递归扫描目录，识别 raw/jpeg/heic/xmp，跳过隐藏文件
- `MetadataReader`：ImageIO 读取 EXIF（拍摄时间/机身/镜头），JPEG/HEIC 已验证，RAW 待真实样本
- `AssetGrouper`：按「同目录 + 基础名（大小写不敏感）」配对成 PhotoAsset
- `RenameTemplate` + `TemplateRenderer`：11 个模板变量、4 个内置预设、非法字符净化、缺数据显式报错
- `RenamePlanner` + `RenameTransaction`：改名前后对照表；全量预检（Never Overwrite / 批内重复）后批量执行，逐条落 Journal
- `PreflightEngine`：阻塞级（目标已存在/批内重复/非法文件名/目录不可写）+ 警告级（缺拍摄时间/缺 XMP）两级预检
- **两级撤销**：批次级（整批回退）+ 资产级（整组回退），跨批次只能逆序、不可跳批
- **三栏 UI 雏形**（PRD §11）：Sources / Assets / Inspector + 底部工作流条
- 沙盒与 security-scoped bookmark 验证通过（Spike A），folder bookmark 跨启动恢复
- XcodeGen 工程：macOS 15 + iOS 18 双 target、测试 scheme、docs 文件夹引用
- 项目文档体系：PRD、商业化基线、分期路线图、踩坑记录
- 单元测试 74 个（Domain / Core / Commerce）

### Known Issues

- RAW 格式（ARW/CR3/NEF/RAF）EXIF 读取未用真实样本验证
- EXIF 时间无时区语义，按本机时区解释；跨时区场景待设计
- StoreKit 购买路径的 5 个测试临时 skip：本地模拟服务器 ASPctaneS 被失败注入污染（踩坑 #4），`killall ASOctaneS` 后恢复并删除 skip；全链路曾在健康环境 3 轮全绿
- FeatureGate 仍为 stub：Free/Pro 分层、批量限制、Paywall 未接入（C2/C3 待启动）
- 大列表渲染（3000 行 List）未做虚拟化优化
- iOS target 可构建未适配，iPadOS 未适配
- Commerce 仍为 stub（买断制方向已定，Phase C0 待启动）
