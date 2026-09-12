import Foundation

/// 用户自定义模板的持久化（UserDefaults JSON）。同名保存 = 覆盖更新，
/// 保证列表里不出现重名项；顺序按保存先后稳定。
@MainActor @Observable
final class UserTemplateStore {
    private static let storageKey = "templates.userPresets"

    private(set) var presets: [UserTemplatePreset] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([UserTemplatePreset].self, from: data) {
            presets = saved
        }
    }

    /// 保存（或按名字覆盖更新）一个自定义模板
    func save(name: String, pattern: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        if let index = presets.firstIndex(where: { $0.name == trimmedName }) {
            presets[index].pattern = pattern
        } else {
            presets.append(UserTemplatePreset(id: UUID(), name: trimmedName, pattern: pattern))
        }
        persist()
    }

    func delete(_ id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(presets), forKey: Self.storageKey)
    }
}
