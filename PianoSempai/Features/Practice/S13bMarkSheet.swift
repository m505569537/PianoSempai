import SheetMusicCore
import SheetMusicLoader
import SheetMusicUI
import SwiftData
import SwiftUI

// MARK: - S13b 标记疑似谱面错误（Sheet）
// 真值：docs/design-reference/screens/S13b-score-error-mark/code.html（2d65df0c…）。
// 红线：只说「标记后不会扣分」——真值 §d 没有「不影响过关」字样，不得自行加字。
// M1（2026-11-03）：谱条升级为真实谱面渲染——练习室已加载的 Score 裁出「疑点小节 ±1」
// 片段（复用 SightReadSession.clippedScore 的裁剪+调号/拍号/谱号回填），红圈标到疑点
// 小节上。score 为 nil（无谱/加载失败/自由弹奏）→ 回退红虚线诚实占位，两种形态都
// 不画假符头/假「疑点和弦」callout。

struct S13bMarkSheet: View {
    let scoreName: String
    let measure: Int
    /// 真实 take 时间文案（如「今天 20:31 的 take」）。没有真实值就不渲染，不编造时间。
    let takeTime: String?
    /// M1：练习室已解析的完整谱（nil = 无谱/自由弹奏 → 红虚线占位回退）
    let score: Score?
    /// 提交回调（视图层负责落库）；第三参 = 「同时在下次问 Neko 时带上这个标记」的勾选态
    let onSubmit: (_ type: String, _ note: String, _ includeWithNeko: Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    init(scoreName: String, measure: Int, takeTime: String? = nil, score: Score? = nil, onSubmit: @escaping (_ type: String, _ note: String, _ includeWithNeko: Bool) -> Void) {
        self.scoreName = scoreName
        self.measure = measure
        self.takeTime = takeTime
        self.score = score
        self.onSubmit = onSubmit
    }

    /// M1：谱条裁剪区间 = 疑点小节 ±1（1-based 闭区间）；clippedScore 内部会按总小节数 clamp。
    /// 非 private：区间/定位是纯逻辑，单测锁定（PracticeCoreTests M1 组）。
    var stripMeasureRange: ClosedRange<Int> {
        let m = max(1, measure)
        return (m - 1)...(m + 1)
    }

    /// M1：疑点小节在裁剪片段内的位置（1-based，红圈定位用）
    var suspectIndexInStrip: Int {
        measure - stripMeasureRange.lowerBound + 1
    }

    enum MarkType: String, CaseIterable {
        case note = "note"
        case rhythm = "rhythm"
        case fingering = "fingering"
        var label: String {
            switch self {
            case .note: "音符/和弦不对"
            case .rhythm: "节奏不对"
            case .fingering: "指法标记可疑"
            }
        }
    }

    @State private var selected: MarkType = .note
    @State private var noteText = ""
    /// S13b 勾选框（真值 §g）：勾上后本次标记随下次问 Neko 一起带上
    @State private var includeWithNeko = false
    @FocusState private var noteFocused: Bool
    @Query private var existingMarks: [ScoreErrorMark]
    @Environment(\.s13bRowPressed) private var rowPressed

    /// 同小节历史标记次数（真实 @Query 数据；0 时不显示，不编计数）
    private var existingCount: Int {
        existingMarks.filter { $0.scoreName == scoreName && $0.measure == measure }
            .map(\.occurrenceCount).max() ?? 0
    }

    var body: some View {
        NocturneBottomDrawer {
            DrawerGrabHandle()

            // §2 标题区：无 ✕（真值没有；关闭走 scrim / 取消）
            header
                .padding(.horizontal, 20)
                .padding(.top, 2)

            contextLine
                .padding(.horizontal, 20)
                .padding(.top, 4)

            // §3 纸质谱条（诚实占位：M1 才上真实谱面渲染）
            paperStrip
                .padding(.horizontal, 20)
                .padding(.top, 12)

            // §4 说明框（逐字真值文案）
            explanationBox
                .padding(.horizontal, 20)
                .padding(.top, 14)

            // §5 问题类型（单选）
            typeChips
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            // §6 备注（标签在输入框上方）
            noteField
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            // §7 勾选行（整行热区，真实 @State 落库）
            checkboxRow
                .padding(.horizontal, 20)
                .padding(.top, 14)

            if existingCount > 0 {
                Text("这一小节你已标记 \(existingCount) 次。")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            // §8 操作钮（取消:提交 = 1:2）
            actionRow
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
        }
    }

    // MARK: §2 标题区

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("标记疑似谱面错误")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .tracking(-0.5) // 真值 tracking-tight（-0.025em @20px）
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            // 「反馈给 Neko」只是呈现态说明，不是独立按钮（真值同）
            Text("反馈给 Neko")
                .font(.labelMd)
                .foregroundStyle(Color.amber.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.amber.opacity(0.1), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.amber.opacity(0.2), lineWidth: 1))
                .fixedSize()
        }
    }

    /// 次行：只用真实数据拼（scoreName / measure；takeTime 有真值才追加，没有就不编）
    private var contextLine: some View {
        Text(contextText)
            .font(.bodySm)
            .foregroundStyle(Color.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contextText: String {
        var parts = ["\(scoreName) · 第 \(measure) 小节"]
        if let takeTime, !takeTime.isEmpty { parts.append(takeTime) }
        return parts.joined(separator: " · ")
    }

    // MARK: §3 纸质谱条（诚实占位）

    private var paperStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text("m. \(measure) (第 \(measure) 小节)")
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .foregroundStyle(Color.s13bPaperInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.danger)
                        .frame(width: 6, height: 6)
                    Text("异常音符位置")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.s13bPaperLegend)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize()
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                // 纸条表头分隔线 1pt #E6E0D2
                Rectangle()
                    .fill(Color.s13bPaperHairline)
                    .frame(height: 1)
            }

            // M1：真实谱条（有谱且部件非空）；无谱 → 红虚线诚实占位回退
            if let score, !score.parts.isEmpty {
                realScoreStrip(score: score)
            } else {
                placeholderStrip
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Color.s13bPaper
                PaperDotTexture()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.s13bPaperBorder, lineWidth: 1))
    }

    // MARK: M1 真实谱条（疑点小节 ±1 裁剪片段 + 红圈标疑点小节）

    @State private var stripScore: Score?
    @State private var stripBuildFailed = false

    private func buildStripScore(from score: Score) -> Score {
        SightReadSession.clippedScore(of: score, measures: stripMeasureRange)
    }

    /// 真实谱条：裁剪片段经 ScoreView 渲染在纸纹底上，疑点小节叠红圈（半透明描边，
    /// 不遮挡符头）。谱面只读展示，无选择/无光标/无点击。
    private func realScoreStrip(score: Score) -> some View {
        let clipped = buildStripScore(from: score)
        return VStack(alignment: .leading, spacing: 0) {
            ScoreView(
                score: clipped,
                options: Self.stripOptions,
                availableWidth: UIScreen.main.bounds.width - 80,
            )
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
            .overlay {
                // 疑点小节红圈：按裁剪片段内小节数等宽近似定位（单行 system 场景足够诚实——
                // 圈的是「这一小节区域」，不是逐符头精确定位；多行换行时圈仍落在片段视觉带内）。
                GeometryReader { proxy in
                    let stripMeasures = max(1, stripMeasureRange.count)
                    let slot = proxy.size.width / CGFloat(stripMeasures)
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.danger, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .background(Color.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .frame(
                            width: slot,
                            height: proxy.size.height * 0.82
                        )
                        .offset(x: slot * CGFloat(suspectIndexInStrip - 1) + slot * 0.08)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .allowsHitTesting(false)
            }
            Text("红色圈出第 \(measure) 小节（前后各附 1 小节帮助对照）")
                .font(.system(size: 10))
                .foregroundStyle(Color.s13bPaperLegend)
                .padding(.top, 4)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Color.s13bPaper
                PaperDotTexture()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.s13bPaperBorder, lineWidth: 1))
    }

    /// 无谱回退：红虚线诚实占位（原 M1 前形态，逐字保留）
    private var placeholderStrip: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.danger.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.danger, style: StrokeStyle(lineWidth: 1.5, dash: [3.5, 2.5]))
            )
            .overlay {
                Text("第 \(measure) 小节 · 疑点位置")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.s13bSuspectInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 132, height: 56)
            .frame(maxWidth: .infinity)
            .frame(height: 88)
    }

    /// M1 谱条渲染参数：小字号谱（staffSize 20，比练习室 28 小一号，抽屉里紧凑），
    /// 关换行徽章（同练习室口径：换行是显示偏好不是原稿标记）。
    private static let stripOptions: ScoreViewOptions = {
        var options = ScoreViewOptions(staffSize: 20, wrapToViewWidth: true, breakPolicy: .honor)
        options.breakIndicatorVisibility = .none
        options.includeTitleFrame = false
        return options
    }()

    // MARK: §4 说明框

    private var explanationBox: some View {
        Text("这里可能和你弹的不一致：可能是弹错，也可能是谱子本身印错了。标记后不会扣分，Neko 会把它和原始 MIDI 一起留着，之后可以换谱源再试。")
            .font(.bodySm)
            .leading(19.5, fontSize: 12) // 真值 leading-relaxed（1.625 @12px）
            .foregroundStyle(Color.s13bExplanationText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.s13bExplanationBg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.border.opacity(0.7), lineWidth: 1)
            )
    }

    // MARK: §5 问题类型（单选）

    private var typeChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("问题类型（可选）")
            HStack(spacing: 8) {
                ForEach(MarkType.allCases, id: \.rawValue) { tag in
                    ProblemTypeChip(title: tag.label, isSelected: selected == tag) {
                        selected = tag
                    }
                }
            }
        }
    }

    // MARK: §6 备注

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("备注（可选）")
            TextField("", text: $noteText)
                .font(.bodySm)
                .foregroundStyle(Color.textPrimary)
                .focused($noteFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.canvas, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(noteFocused ? Color.amber.opacity(0.8) : Color.border, lineWidth: 1)
                )
                .overlay(alignment: .leading) {
                    // TextField 的 placeholder 用覆盖层自绘，才能上真值的 #69625A
                    if noteText.isEmpty {
                        Text("例如：教材上是 do-mi-sol，但听起来像错的")
                            .font(.bodySm)
                            .foregroundStyle(Color.s13bPlaceholder)
                            .padding(.leading, 14)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    /// 字段标签（真值 §e/§f）：11px medium tracking-wider muted
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(1.1)
            .foregroundStyle(Color.textMuted)
    }

    // MARK: §7 勾选行（整行热区）

    private var checkboxRow: some View {
        Button {
            includeWithNeko.toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.canvas)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(rowPressed ? Color.amber.opacity(0.6) : Color.border, lineWidth: 1)
                        )
                    if includeWithNeko {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.amber)
                    }
                }
                .frame(width: 16, height: 16)

                Text("同时在下次问 Neko 时带上这个标记")
                    .font(.bodySm)
                    .foregroundStyle(rowPressed ? Color.textPrimary : Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CheckboxRowButtonStyle())
    }

    // MARK: §8 操作钮（取消:提交 = 1:2）

    private var actionRow: some View {
        // 1:2 用几何算宽（HStack 的 .infinity 只会等分，不按权重分）
        GeometryReader { proxy in
            let unit = max(0, (proxy.size.width - 10) / 3) // 间距 10，共 3 份
            HStack(spacing: 10) {
                Button("取消") { dismiss() }
                    .buttonStyle(CancelButtonStyle())
                    .frame(width: unit)
                Button {
                    onSubmit(selected.rawValue, noteText, includeWithNeko)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                        Text("提交标记")
                    }
                }
                .buttonStyle(SubmitButtonStyle())
                .frame(width: unit * 2)
            }
        }
        .frame(height: 44)
    }
}

// MARK: - 部件

/// 问题类型 chip（真值 §e）：选中 = 琥珀 20% 底 + 1pt 实心琥珀边 + 6pt 琥珀圆点；
/// 未选 = #1F1C1A 底 + #9C948B 字 + 1pt #332D29 边。
private struct ProblemTypeChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Circle()
                        .fill(Color.amber)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(isSelected ? .labelMd : .bodySm)
                    .foregroundStyle(isSelected ? Color.amber : Color.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.amber.opacity(0.2) : Color.s13bChipBg, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.amber : Color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// 勾选行按钮样式：整行热区，pressed 态注入 label（供勾选框边框/文案按真值 hover 变色）
private struct CheckboxRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.s13bRowPressed, configuration.isPressed)
    }
}

/// 「取消」钮（真值 §h）：透明底 + 1pt #332D29 边 + 12px medium muted；pressed 字转主色、底 #2C2724
private struct CancelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.labelMd)
            .foregroundStyle(configuration.isPressed ? Color.textPrimary : Color.textMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? Color.s13bCancelPressed : Color.clear)
            )
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// 「提交标记」钮（真值 §h）：琥珀底 + #1A1715 bold 字 + check 图标 + 琥珀投影；pressed 亮到 #e0ad57
private struct SubmitButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.s13bSubmitInk)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? Color.s13bSubmitPressed : Color.amber)
            )
            .shadow(color: Color.amber.opacity(0.15), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// 纸面点阵纹理（真值：径向 1pt 圆点 #E8E3D5，16pt 网格平铺，极低对比）
private struct PaperDotTexture: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 16
            let radius: CGFloat = 0.5
            var y = step / 2
            while y <= size.height {
                var x = step / 2
                while x <= size.width {
                    let dot = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: dot), with: .color(Color.s13bPaperDot))
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 按下态环境值（真值 §g hover 的 iOS 等价物）

private struct S13bRowPressedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private extension EnvironmentValues {
    var s13bRowPressed: Bool {
        get { self[S13bRowPressedKey.self] }
        set { self[S13bRowPressedKey.self] = newValue }
    }
}

// MARK: - S13b 真值字面量色（DesignSystem token 未覆盖到的真值 hex，仅本文件使用）

fileprivate extension Color {
    /// hex → sRGB（S13b 真值局部色专用）
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// 纸谱条底 #F9F7F1（真值 §c；`Color.scorePaper` 是 #F5F0E6，不同，故用字面量）
    static let s13bPaper = Color(hex: 0xF9F7F1)
    /// 纸面点阵 #E8E3D5
    static let s13bPaperDot = Color(hex: 0xE8E3D5)
    /// 纸谱条 1pt 边框 #E0DACB
    static let s13bPaperBorder = Color(hex: 0xE0DACB)
    /// 纸内表头分隔线 #E6E0D2
    static let s13bPaperHairline = Color(hex: 0xE6E0D2)
    /// 纸表头「m. N」粗体 #423C36
    static let s13bPaperInk = Color(hex: 0x423C36)
    /// 纸表头图例字 #8C8276
    static let s13bPaperLegend = Color(hex: 0x8C8276)
    /// 疑点区文字 #B34032（真值疑点红；纸上可读）
    static let s13bSuspectInk = Color(hex: 0xB34032)
    /// 说明框底 #201D1B
    static let s13bExplanationBg = Color(hex: 0x201D1B)
    /// 说明框正文 #D6D0C7
    static let s13bExplanationText = Color(hex: 0xD6D0C7)
    /// 未选中 chip 底 #1F1C1A
    static let s13bChipBg = Color(hex: 0x1F1C1A)
    /// 备注输入框 placeholder #69625A
    static let s13bPlaceholder = Color(hex: 0x69625A)
    /// 「取消」pressed 底 #2C2724
    static let s13bCancelPressed = Color(hex: 0x2C2724)
    /// 「提交标记」pressed 底 #e0ad57
    static let s13bSubmitPressed = Color(hex: 0xe0ad57)
    /// 「提交标记」文字 #1A1715
    static let s13bSubmitInk = Color(hex: 0x1A1715)
}
