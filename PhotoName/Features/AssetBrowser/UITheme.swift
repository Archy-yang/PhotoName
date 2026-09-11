import SwiftUI

/// 暗色主题 Token（与界面原型一一对应；App 全局强制暗色——摄影工具的看片环境）
enum UITheme {
    static let ground = Color(hex: 0x1E1F22)      // 窗口底
    static let panel = Color(hex: 0x26272B)       // 侧栏/操作条面板
    static let card = Color(hex: 0x2B2C31)        // 资产卡片
    static let well = Color(hex: 0x17181A)        // 输入框/内嵌底
    static let line = Color(hex: 0x34353A)        // 分隔线/描边
    static let textPrimary = Color(hex: 0xE8E9EB)
    static let textDim = Color(hex: 0x9DA0A6)
    static let textFaint = Color(hex: 0x6E7076)

    /// 强调色：暗房琥珀——只做选中与主按钮
    static let amber = Color(hex: 0xD9A441)
    /// 语义色：绿色只给新名字与成功
    static let green = Color(hex: 0x4CC38A)
    /// 语义色：橙=警告可继续
    static let orange = Color(hex: 0xE08A3C)
    /// 语义色：红=阻塞禁行
    static let red = Color(hex: 0xE05B4E)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
