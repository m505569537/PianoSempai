import SwiftUI

// 字体语义层（visual-system §2）。
// P1 不内置版权字体：标题用系统衬线（New York，中文回退宋体系），
// 正文/标签用系统无衬线（中文回退 PingFang SC），数据用 monospaced。
// 日后换 Noto Serif SC / Noto Sans SC 时只改本文件。

extension Font {
    // MARK: Serif 展示级（display / headline）

    /// display-lg：32/40，400 serif
    static let displayLg = Font.system(size: 32, weight: .regular, design: .serif)
    /// headline-lg：24/32，400 serif
    static let headlineLg = Font.system(size: 24, weight: .regular, design: .serif)
    /// headline-sm：20/28，500 serif
    static let headlineSm = Font.system(size: 20, weight: .medium, design: .serif)

    // MARK: Sans 正文级（title / body / label）

    /// title-md：16/24，500 sans
    static let titleMd = Font.system(size: 16, weight: .medium)
    /// body-lg：16/26，400 sans
    static let bodyLg = Font.system(size: 16)
    /// body-md：14/22，400 sans
    static let bodyMd = Font.system(size: 14)
    /// body-sm：12/18，400 sans
    static let bodySm = Font.system(size: 12)
    /// label-md：12/16，500 sans（中文标签勿再压字距）
    static let labelMd = Font.system(size: 12, weight: .medium)
    /// label-sm：11/14，500 sans
    static let labelSm = Font.system(size: 11, weight: .medium)

    // MARK: Mono 数据级（DisplaySerif/BodySans/LabelMono 三语义的 mono 腿）

    /// 等宽数据文字（BPM / ms / 时间戳）。数字一律配 `.monospacedDigit()` 使用。
    static func labelMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// 行高语义：SwiftUI 无直接 line-height，用 lineSpacing 补齐（字号 + lineSpacing ≈ 行高）。
extension Text {
    /// 按视觉 token 行高补 lineSpacing。例：bodyMd 14/22 → lineSpacing 8。
    func leading(_ lineHeight: CGFloat, fontSize: CGFloat) -> some View {
        lineSpacing(lineHeight - fontSize)
    }
}
