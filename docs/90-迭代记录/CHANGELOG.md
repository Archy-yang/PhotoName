# Changelog

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循语义化版本。

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
- 拍摄时间 fallback 链（F-05）未实现，缺 EXIF + 日期模板直接报错
- Scanner 全量加载，大目录（3000+ 文件）性能未验证
- iOS target 可构建未适配，iPadOS 未适配
- Commerce 仍为 stub（买断制方向已定，Phase C0 待启动）
