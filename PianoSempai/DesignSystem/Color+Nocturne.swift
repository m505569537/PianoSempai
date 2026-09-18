import SwiftUI

// Nocturne Minimal 色板（docs/design-reference/foundation/visual-system.md §1）。
// token 值定义在 Resources/Assets.xcassets；UI 恒为深色，故均为 universal 单值。
// 命名用语义名，与 brief §1 清单一致。

extension Color {
    /// 根背景（暖炭 #1C1917）
    static let canvas = Color("canvas")
    /// 更深一档背景（#161311），用于浮层底下压暗区
    static let surface = Color("surface")
    /// 一级卡片、分组容器（#262220）
    static let card = Color("card")
    /// 激活卡、pressed、弹层、浮起 dock（#2D2724）
    static let cardElevated = Color("cardElevated")
    /// 最高层级表面，modal 头部（#383432）
    static let sheetTop = Color("sheetTop")
    /// 卡片 1px 发丝边（#332D29）
    static let border = Color("border")
    /// 输入框、滑块轨道未填充（#3D3531）
    static let borderInput = Color("borderInput")
    /// 主琥珀（#D4A24E）：主按钮、当前态、光标、关键数值
    static let amber = Color("amber")
    /// hover/微交互高亮、badge、focus ring（#E8C882）
    static let amberBright = Color("amberBright")
    /// 次级琥珀、未激活轨道（#8C6A38）
    static let amberDim = Color("amberDim")
    /// 标题、主文本（#F5F2ED）
    static let textPrimary = Color("textPrimary")
    /// 正文次级（#C2BCB4）
    static let textBody = Color("textBody")
    /// 时间、索引、label、副文案（#9C948B）
    static let textMuted = Color("textMuted")
    /// 已连接、通过、达标、ON 开关（#7FA97C）
    static let success = Color("success")
    /// 断连、强开警示、错误、删除（#C97064）
    static let danger = Color("danger")
    /// 双 take 对比 B（旧次）专用蓝灰（#8FA3B8），全局仅此一处使用
    static let compareB = Color("compareB")
    /// 五线谱纸白（#F5F0E6）
    static let scorePaper = Color("scorePaper")
    /// 五线谱墨黑符头（#1C1917）
    static let scoreInk = Color("scoreInk")
    /// modal/drawer 遮罩 rgba(12,10,9,0.6)
    static let scrim = Color("scrim")
}
