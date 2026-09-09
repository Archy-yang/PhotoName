import Foundation

/// 实时示例名预览：用户编辑模板时，用第一个资产渲染出一个「示例新名字」。
/// 复用 RenamePlanner（首资产 + index 1），保证示例与真实 plan 的输出规则完全一致；
/// 模板错误（缺拍摄时间 / 缺项目名 / 未知变量）即时返回，交由 UI 呈现。
struct TemplateSamplePreview: Sendable {
    enum Outcome: Equatable, Sendable {
        case rendered(String)
        case failed(TemplateError)
    }

    func make(
        assets: [PhotoAsset],
        metadata: [UUID: PhotoMetadata],
        template: RenameTemplate,
        projectName: String?
    ) -> Outcome? {
        guard let first = assets.first else { return nil }
        do {
            let plan = try RenamePlanner().makePlan(
                assets: [first],
                metadata: metadata,
                template: template,
                projectName: projectName
            )
            return .rendered(plan.operations.first.map { $0.newURL.lastPathComponent } ?? "")
        } catch let error as TemplateError {
            return .failed(error)
        } catch {
            return nil
        }
    }
}
