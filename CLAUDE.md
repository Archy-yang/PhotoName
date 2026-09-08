# PhotoName — 项目约定

摄影素材安全批量重命名工具（macOS 优先 + iPadOS），Local First / Safe First / 买断制。
完整文档在 `docs/`：产品规格（`20-产品PRD/`）、分期路线图（`30-架构设计/01-分期路线图.md`）、踩坑记录（`40-踩坑记录/`）。

## 测试文件约定

**所有测试夹具统一放在 `/Users/yangqi/workspace/self_project/photo_name/test/`**（仓库外的同级 test 目录），不要写到桌面（~/Desktop）或其他位置：

- 生成脚本放该目录，输出目录也指向该目录（脚本内用 `$(dirname "$0")` 相对定位）
- 现有夹具：`generate_fixtures.swift`（EXIF 样本）、`generate_perf_fixtures.sh`（3000 文件性能夹具）、`PhotoName-SpikeTest/`、`PhotoName-PerfTest/`
- 需要用户在 App 里手动选择的验证文件夹也放这里，并告知完整路径

## 工程与开发流程

- 工程由 **XcodeGen** 生成：改 `project.yml` 或**增删/移动源文件后必须先 `xcodegen generate`** 再构建（XcodeGen 不会自动发现新文件）
- 常用命令：
  - 构建：`xcodegen generate && xcodebuild -project PhotoName.xcodeproj -scheme PhotoName_macOS -destination 'platform=macOS' build`
  - 测试：同上，把 `build` 换成 `test`
- **TDD**：先写测试（红）再实现（绿），生产代码在 `PhotoName/`，测试在 `Tests/`
- Swift 6 严格并发：全局单例/可变状态类需显式隔离域（UI 侧状态类用 `@MainActor`）
- 产品原则（写代码前对照）：Never Overwrite / Preview Before Mutation / 资产原子性（RAW+JPEG+XMP 整组操作）/ Local First（照片数据不出本机）

## 版本管理

- 主分支 `main`，功能分支 `feat/xxx`；每个功能完成后提交，里程碑打 annotated tag（如 `v0.1.0`）
- 版本记录写 `docs/90-迭代记录/CHANGELOG.md`
