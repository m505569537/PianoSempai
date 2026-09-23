import SwiftUI
import SwiftData

// MARK: - S05 定级结果 · 你的起点
// 真值：docs/design-reference/screens/S05-placement-result/code.html（id e7be272ba979488cabbe7d30e945768b）。
// Stitch 画布 2560 宽忽略；HTML 容器 max-w-[390px] → 按 390 逻辑宽实现（左右 20pt，卡片内容宽 318）。
//
// 诚实红线：
// - 只画真实算出的三个轴（音准 / 读谱 / 连续性）；节奏、速度、双手协同无数据 → 只画网格 +「P2」标，
//   不出顶点、不出数值、不朝无数据方向延伸多边形。
// - 音准与读谱同源于同一份视奏命中率，两轴恒等，绝不编出两个不同数字。
// - 无中心分（真值雷达没有）；副文由真实数据现算，不用真值的硬编码句。
// - 不画假 OS chrome：无状态栏（9:41/信号/wifi/电池）、无 home 指示条、无返回按钮。
// - 插入点由 CourseEngine 规则表产出，本页只渲染。

struct S05ResultView: View {
    // 真实数据接线：最新一条定级结果 + 力度校准（优先匹配本次结果的 calibrationId，取不到再取最新）
    @Query(sort: \PlacementResult.createdAt, order: .reverse) private var results: [PlacementResult]
    @Query private var calibrations: [VelocityCalibration]
    let onGeneratePlan: () -> Void
    let onRetake: () -> Void

    @State private var showRetakeConfirm = false

    private var result: PlacementResult? { results.first }
    private var calibration: VelocityCalibration? {
        calibrations
            .sorted { $0.createdAt > $1.createdAt }
            .first { $0.entityId == result?.velocityCalibrationId }
            ?? calibrations.sorted { $0.createdAt > $1.createdAt }.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // §1 顶部完成行（真值 mt12 mb20）
                completionRow
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                // §2 标题区（真值 mb20）
                titleBlock
                    .padding(.bottom, 20)

                radarCard      // §3 六维雷达卡（mb14）
                routeCard      // §4 路线插入点卡（mb14）
                infoCard       // §5 信息卡（mb14）
                calibrationCard // §6 力度校准卡（mb20）

                // §7 底部操作（真值底部容器 pt8）
                planButton
                    .padding(.top, 8)
                retakeButton
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.canvas)
        .confirmationDialog("重新评估将替换本次结果（可撤销一次的留痕在 P2 提供）", isPresented: $showRetakeConfirm, titleVisibility: .visible) {
            Button("重新评估", role: .destructive) { onRetake() }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: §1 顶部完成行

    /// 3 个 6pt 琥珀圆点 + 14×1pt 琥珀 60% 连接线（点/线间距 8pt）+ 右侧「评估完成」
    private var completionRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.amber)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color.amber.opacity(0.6))
                .frame(width: 14, height: 1)
            Circle()
                .fill(Color.amber)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color.amber.opacity(0.6))
                .frame(width: 14, height: 1)
            Circle()
                .fill(Color.amber)
                .frame(width: 6, height: 6)
            Spacer(minLength: 8)
            Text("评估完成")
                .font(.system(size: 12))
                .foregroundStyle(Color.textMuted)
                .kerning(0.6) // 真值 tracking-wider ≈ +0.05em
        }
    }

    // MARK: §2 标题区

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("你的起点")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .kerning(0.7) // 真值 tracking-wide ≈ +0.025em
                .foregroundStyle(Color.textPrimary)
            Text(summary)
                .font(.system(size: 13.5))
                .leading(22, fontSize: 13.5) // 真值 leading-relaxed 1.625
                .foregroundStyle(Color.textMuted)
        }
    }

    /// 副文：由真实数据现算（不用真值硬编码的「基础扎实，卡点在视奏速度与双手协同。」）
    private var summary: String {
        guard let result else { return "评估结果已就绪" }
        let percent = Int((averageHitRate * 100).rounded())
        let pauses = result.pauseCounts.reduce(0, +)
        return "视奏命中 \(percent)%，停顿 \(pauses) 次；节奏、速度与双手协同将在完整判分后提供。"
    }

    /// 视奏命中率均值（两段真实采集；无数据 = 0）
    private var averageHitRate: Double {
        guard let result, !result.sightreadHitRates.isEmpty else { return 0 }
        return result.sightreadHitRates.reduce(0, +) / Double(result.sightreadHitRates.count)
    }

    // MARK: §3 六维雷达卡

    private var radarCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            radar
            Text("音准与读谱同源于本次视奏命中率；节奏、速度、双手协同由 P2 完整判分提供。")
                .font(.system(size: 11))
                .leading(16, fontSize: 11)
                .foregroundStyle(Color.textMuted)
                .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
        .padding(.bottom, 14)
    }

    /// 六轴 5 分制取值。轴序（顺时针自顶部）：音准 / 节奏 / 连续性 / 速度 / 读谱 / 双手协同。
    /// nil = 本次无真实数据 → 不画顶点、不出数值，只留网格 + P2 标。
    /// 固定换算规则（写死；P2 对齐算法就绪后重算）：
    /// - 音准 = 读谱 = 视奏命中率均值 × 5 —— 同一来源，两轴恒等；
    /// - 连续性 = max(0, 100 − 停顿数×10) ÷ 100 × 5 —— 同 CourseEngine.continuityScore 规则。
    private var axisScores: [Double?] {
        guard let result else { return Array(repeating: nil, count: 6) }
        let accuracy5 = averageHitRate * 5
        let continuity100 = max(0, 100 - result.pauseCounts.reduce(0, +) * 10)
        let continuity5 = Double(continuity100) / 100 * 5
        return [accuracy5, nil, continuity5, nil, accuracy5, nil]
    }

    /// 真实轴顶点（仅三个：音准=顶部、连续性=右下、读谱=左下）
    private var dataPoints: [CGPoint] {
        var points: [CGPoint] = []
        for (index, score) in axisScores.enumerated() {
            if let score {
                points.append(S05RadarGeometry.vertex(index, radius: CGFloat(score) / 5 * S05RadarGeometry.outerRadius))
            }
        }
        return points
    }

    private var radar: some View {
        let points = dataPoints
        let available = axisScores.map { $0 != nil }
        return ZStack {
            // 网格：4 圈同心六边形（70/17.5 实线，52.5/35 虚线）+ 6 条轴线，全部 #332D29
            RadarRings(radii: S05RadarGeometry.solidRingRadii)
                .stroke(Color.border, lineWidth: 1)
            RadarRings(radii: S05RadarGeometry.dashedRingRadii)
                .stroke(Color.border, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            RadarSpokes()
                .stroke(Color.border, lineWidth: 1)

            // 数据多边形：只连真实顶点；不可用轴无半径 → 不朝节奏/速度/双手协同方向延伸
            RadarDataPolygon(points: points)
                .fill(LinearGradient(
                    colors: [Color.amber.opacity(0.32), Color.amber.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay {
                    RadarDataPolygon(points: points)
                        .stroke(Color.amber, style: StrokeStyle(lineWidth: 1.75, lineJoin: .round))
                }

            // 真实顶点：3.5pt 琥珀点 + 1.5pt 背景色描边
            ForEach(points.indices, id: \.self) { index in
                Circle()
                    .fill(Color.amber)
                    .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 1.5))
                    .frame(width: 7, height: 7)
                    .position(points[index])
            }

            // 轴标签用 Text 覆盖（不用 SVG text）
            ForEach(0..<S05RadarAxis.names.count, id: \.self) { index in
                axisLabel(index, isAvailable: available[index])
            }
        }
        .frame(width: S05RadarGeometry.canvas.width, height: S05RadarGeometry.canvas.height)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// 轴标签：真实轴 #F5F2ED；不可用轴 #9C948B + 10pt「P2」小标（无顶点圆点、无数值）
    private func axisLabel(_ index: Int, isAvailable: Bool) -> some View {
        let anchor = S05RadarAxis.anchors[index]
        let alignment = S05RadarAxis.alignments[index]
        let slot: CGFloat = 60
        let x: CGFloat
        switch alignment {
        case .leading: x = anchor.x + slot / 2
        case .trailing: x = anchor.x - slot / 2
        default: x = anchor.x
        }
        // 真值 SVG y 为基线；12pt 文本视觉中心约在基线上方 4pt。
        // 带 P2 小标时整条下移，让第一行仍落在真值标签位置上。
        let y = anchor.y - 4 + (isAvailable ? 0 : 7)

        return VStack(spacing: 1) {
            Text(S05RadarAxis.names[index])
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isAvailable ? Color.textPrimary : Color.textMuted)
            if !isAvailable {
                Text("P2")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
        }
        .frame(width: slot, alignment: alignment)
        .position(x: x, y: y)
    }

    // MARK: §4 路线插入点卡

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical") // 真值 Material auto_stories
                    .font(.system(size: 17))
                    .foregroundStyle(Color.amber)
                Text("路线插入点")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.bottom, 2) // 头行 mb14 = 行距 12 + 2

            if let result {
                // 拜厄：插入点琥珀
                routeRow(
                    icon: "book", iconColor: Color.textMuted,
                    name: "拜厄", nameColor: Color.textPrimary, nameWeight: .medium,
                    showsHairline: true
                ) {
                    Text("从第 \(result.entryBeyer) 条进入")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.amber)
                        .monospacedDigit()
                }

                // 哈农：插入点白色（真值不是琥珀）
                routeRow(
                    icon: "book", iconColor: Color.textMuted,
                    name: "哈农", nameColor: Color.textPrimary, nameWeight: .medium,
                    showsHairline: true
                ) {
                    Text("从第 \(result.entryHanon) 条开始")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .monospacedDigit()
                }

                // 车尔尼 599：整行 muted，右值 12.5pt + 全角括号
                routeRow(
                    icon: "book", iconColor: Color.textMuted.opacity(0.6),
                    name: "车尔尼 599", nameColor: Color.textMuted, nameWeight: .regular,
                    showsHairline: false
                ) {
                    Text("暂不开始（预计 \(result.projected599Weeks) 周后）")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.textMuted)
                        .monospacedDigit()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
        .padding(.bottom, 14)
    }

    /// 路线行：左教材图标 + 名，右插入点；前两行底部 1pt #332D29 60% 发丝线
    private func routeRow<Point: View>(
        icon: String,
        iconColor: Color,
        name: String,
        nameColor: Color,
        nameWeight: Font.Weight,
        showsHairline: Bool,
        @ViewBuilder point: () -> Point
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon) // 真值 Material menu_book
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 18, alignment: .center)
            Text(name)
                .font(.system(size: 13.5, weight: nameWeight))
                .foregroundStyle(nameColor)
            Spacer(minLength: 8)
            point()
        }
        .padding(.bottom, showsHairline ? 10 : 0)
        .overlay(alignment: .bottom) {
            if showsHairline {
                Color.border.opacity(0.6)
                    .frame(height: 1)
            }
        }
    }

    // MARK: §5 信息卡

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info") // 真值 Material info
                .font(.system(size: 17))
                .foregroundStyle(Color.textMuted)
                .padding(.top, 2)
            Text("手型维度将在你启用视觉陪练后补充，不影响当前路线。")
                .font(.system(size: 12.5))
                .leading(17, fontSize: 12.5) // 真值 leading-snug 1.375
                .foregroundStyle(Color.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border.opacity(0.7), lineWidth: 1))
        .padding(.bottom, 14)
    }

    // MARK: §6 力度校准卡

    private var calibrationCard: some View {
        Group {
            if let calibration, calibration.isCalibrated {
                HStack(spacing: 10) {
                    Image(systemName: "speedometer") // 真值 Material speed
                        .font(.system(size: 19))
                        .foregroundStyle(Color.amber)
                    Text("个人力度曲线")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.s05CalibratedDot)
                            .frame(width: 6, height: 6)
                        Text("已校准")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.textMuted)
                    }
                }
            } else {
                // 未校准：如实说明，不显示 pp/mf/ff 数字
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.textMuted)
                    Text("本次未完成校准，可在设置里重校")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textMuted)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
        .padding(.bottom, 20)
    }

    // MARK: §7 底部操作

    private var planButton: some View {
        Button {
            onGeneratePlan()
        } label: {
            Text("生成我的第一周计划")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.canvas)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.amber, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.amber.opacity(0.10), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(S05PressScaleButtonStyle())
    }

    private var retakeButton: some View {
        Button {
            showRetakeConfirm = true
        } label: {
            Text("重新评估")
                .font(.system(size: 13))
        }
        .buttonStyle(S05GhostButtonStyle())
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - 雷达几何（真值 SVG viewBox 300×230，中心 (150,112)，外半径 70）
// SwiftUI 侧直接用 viewBox 单位绘制，容器 300×230（等比重放，六边形仍为正六边形）。

private enum S05RadarGeometry {
    static let canvas = CGSize(width: 300, height: 230)
    /// 中心垂直偏上，给底部「速度」标签留位
    static let center = CGPoint(x: 150, y: 112)
    static let outerRadius: CGFloat = 70
    /// 4 圈同心六边形：R=70/17.5 实线，R=52.5/35 虚线（真值 stroke-dasharray 2 2）
    static let solidRingRadii: [CGFloat] = [70, 17.5]
    static let dashedRingRadii: [CGFloat] = [52.5, 35]

    /// 第 index 个轴的顶点：index 0 = 顶部，顺时针每 60°
    static func vertex(_ index: Int, radius: CGFloat) -> CGPoint {
        let radians = Angle.degrees(-90 + 60 * Double(index)).radians
        return CGPoint(
            x: center.x + radius * CGFloat(cos(radians)),
            y: center.y + radius * CGFloat(sin(radians))
        )
    }
}

/// 六轴（顺时针自顶部）：名称、真值轴标签锚点（SVG text 的 x 与基线 y）、水平对齐（text-anchor）
private enum S05RadarAxis {
    static let names = ["音准", "节奏", "连续性", "速度", "读谱", "双手协同"]
    static let anchors: [CGPoint] = [
        CGPoint(x: 150, y: 28),  // 音准 顶
        CGPoint(x: 226, y: 74),  // 节奏 右上
        CGPoint(x: 226, y: 154), // 连续性 右下
        CGPoint(x: 150, y: 202), // 速度 底
        CGPoint(x: 74, y: 154),  // 读谱 左下
        CGPoint(x: 74, y: 74),   // 双手协同 左上
    ]
    static let alignments: [Alignment] = [.center, .leading, .leading, .center, .trailing, .trailing]
}

/// 同心六边形网格圈
private struct RadarRings: Shape {
    let radii: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for radius in radii {
            for index in 0..<6 {
                let vertex = S05RadarGeometry.vertex(index, radius: radius)
                if index == 0 {
                    path.move(to: vertex)
                } else {
                    path.addLine(to: vertex)
                }
            }
            path.closeSubpath()
        }
        return path
    }
}

/// 6 条轴线：中心 → 外圈顶点
private struct RadarSpokes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<6 {
            path.move(to: S05RadarGeometry.center)
            path.addLine(to: S05RadarGeometry.vertex(index, radius: S05RadarGeometry.outerRadius))
        }
        return path
    }
}

/// 数据多边形：按给定顶点顺序闭合（3 个真实顶点 → 三角形；无顶点 → 空路径）
private struct RadarDataPolygon: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - 按钮样式（真值 §6）

/// CTA：pressed 缩放 0.99（真值 active:scale-[0.99]）
private struct S05PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 幽灵链接：13pt #9C948B，按下变 #F5F2ED（真值 hover:text-textMain）
private struct S05GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Color.textPrimary : Color.textMuted)
    }
}

// MARK: - 本页字面量色（DesignSystem token 未覆盖的真值 hex）

fileprivate extension Color {
    /// 力度已校准状态点 #4ADE80（S05 真值；token 无此色）
    static let s05CalibratedDot = Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255)
}

#Preview {
    S05ResultView(onGeneratePlan: {}, onRetake: {})
}
