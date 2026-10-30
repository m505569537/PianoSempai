import SwiftData
import SwiftUI

// MARK: - S09 曲目详情 · 全部 Take 与趋势（PRD 288：全部 take + 维度趋势曲线）
//
// 数据口径（红线 1/2：不编分、不编点）：
// - take 只认真实 pieceId 关联，时间升序（startedAt）；
// - 一条 take 的分析行经 takeId 关联，多条取 analyzedAt 最新（与 S13 查询口径一致）；
// - 某维度在该分析上没有真实值（Int? 为 nil）→ 该 take 在这条序列里不产出点：
//   不补零、不插值（PRD 210：总分仅用于进步曲线；六维各画各的真实序列）。
// 视觉沿用房子风格：琥珀折线 + 0–100 百分制域（同档案页趋势图语言）、S09 卡面、muted 标注。

/// 纯序列构建（不进 View struct，可完整单测）
enum PieceTrend {

    /// 七条可选序列：总分 + 六维（PRD §M5 六维判分）
    enum Series: String, CaseIterable {
        case weakTotal, pitch, rhythm, tempo, dynamics, continuity, hands

        var title: String {
            switch self {
            case .weakTotal: "总分"
            case .pitch: "音准"
            case .rhythm: "节奏"
            case .tempo: "速度"
            case .dynamics: "力度"
            case .continuity: "连贯"
            case .hands: "双手"
            }
        }

        /// 只有总分带红线注（PRD 210）；其余序列没有脚注
        var footnote: String? {
            self == .weakTotal ? "总分仅用于进步曲线，不当过关依据" : nil
        }

        /// 该维度在分析行上的真实值（nil = 没判出来，绝不补数）
        func value(of analysis: TakeAnalysis) -> Int? {
            switch self {
            case .weakTotal: analysis.weakTotal
            case .pitch: analysis.pitchScore
            case .rhythm: analysis.rhythmScore
            case .tempo: analysis.tempoScore
            case .dynamics: analysis.dynamicsScore
            case .continuity: analysis.continuityScore
            case .hands: analysis.handsScore
            }
        }
    }

    struct Point: Identifiable {
        let index: Int
        let value: Int
        let date: Date
        var id: Int { index }
    }

    /// 趋势点：take 按 startedAt 升序；某 take 的最新分析在该维度无真实值 → 不产点。
    /// 没有任何真实值 → []。
    static func points(series: Series, takes: [Take], analyses: [TakeAnalysis]) -> [Point] {
        let sortedTakes = takes.sorted { $0.startedAt < $1.startedAt }
        var points: [Point] = []
        for take in sortedTakes {
            guard let value = latestValue(series: series, take: take, analyses: analyses) else { continue }
            points.append(Point(index: points.count, value: value, date: take.startedAt))
        }
        return points
    }

    /// ≥2 个真实点才画趋势（视图据此显「数据不足」，不画单点假趋势）
    static func canDrawTrend(_ points: [Point]) -> Bool {
        points.count >= 2
    }

    /// 一条 take 的最新分析（多条取 analyzedAt 最新）在该维度上的真实值
    static func latestValue(series: Series, take: Take, analyses: [TakeAnalysis]) -> Int? {
        guard let latest = analyses
            .filter({ $0.takeId == take.entityId })
            .max(by: { $0.analyzedAt < $1.analyzedAt })
        else { return nil }
        return series.value(of: latest)
    }
}

/// 曲目详情二级页：维度趋势曲线 + 全部 take 列表（行点开 S13 报告，同 PieceDetailView）。
struct PieceTakesTrendView: View {
    let piece: Piece

    @Environment(\.dismiss) private var dismiss
    @Query private var takes: [Take]
    @Query(sort: \TakeAnalysis.analyzedAt, order: .reverse) private var analyses: [TakeAnalysis]

    @State private var series: PieceTrend.Series = .weakTotal
    /// 行路由：点行开 S13 Take 报告（.sheet(item:)，与 PieceDetailView/ArchiveView 一致；本页唯一 sheet）
    @State private var selectedTake: Take?

    /// 该曲目全部 take（真实 pieceId 关联，时间升序；与分析同一口径）
    private var pieceTakes: [Take] {
        takes.filter { $0.pieceId == piece.entityId }.sorted { $0.startedAt < $1.startedAt }
    }

    private var points: [PieceTrend.Point] {
        PieceTrend.points(series: series, takes: pieceTakes, analyses: analyses)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                trendCard
                takesCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.canvas)
        .navigationTitle("全部 Take 与趋势")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTake) { take in
            TakeReportView(take: take)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: 趋势卡（chips + 曲线 / 诚实空态 + 脚注）

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PieceTrend.Series.allCases, id: \.self) { candidate in
                        NocturneChip(title: candidate.title, isSelected: series == candidate) {
                            series = candidate
                        }
                    }
                }
            }

            if pieceTakes.isEmpty {
                // 一次都没练过：没有可画的东西，如实说
                Text("还没有 take。练过之后，这里显示全部记录与趋势。")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
            } else if !PieceTrend.canDrawTrend(points) {
                Text("数据不足：至少 2 次可判分的 take 才能画出趋势")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
            } else {
                PieceTrendChart(points: points)
                    .frame(height: 96)
            }

            if let footnote = series.footnote {
                Text(footnote)
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
    }

    // MARK: 全部 take 列表（行点开 S13；当前序列无真实值的行如实标「数据不足」）

    private var takesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("全部 Take")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if !pieceTakes.isEmpty {
                    Text("共 \(pieceTakes.count) 次")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                        .monospacedDigit()
                }
            }
            .padding(.bottom, 8)

            ForEach(Array(pieceTakes.enumerated()), id: \.element.entityId) { index, take in
                Button {
                    selectedTake = take
                } label: {
                    trendTakeRow(take, isFirst: index == 0)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
    }

    /// 行样式同 PieceDetailView.recentTakeRow：左时间 + 速度/时长副行，右该序列真实分值
    private func trendTakeRow(_ take: Take, isFirst: Bool) -> some View {
        let value = PieceTrend.latestValue(series: series, take: take, analyses: analyses)
        return VStack(alignment: .leading, spacing: 0) {
            if !isFirst {
                Color.border.opacity(0.6)
                    .frame(height: 1)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(take.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                    Text(takeMetaText(take))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.textMuted)
                        .monospacedDigit()
                }
                Spacer(minLength: 12)
                Text(value.map { "\($0)" } ?? "数据不足")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(value != nil ? Color.amber : Color.textMuted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
                    .padding(.leading, 4)
            }
            .frame(minHeight: 44)
            .padding(.vertical, 10)
        }
    }

    /// 副行只列真实数据：速度（>0 才有）与时长（>0 才有）；两者都缺 → 「—」
    private func takeMetaText(_ take: Take) -> String {
        var parts: [String] = []
        if take.tempoAvg > 0 { parts.append("♩=\(take.tempoAvg)") }
        if take.durationSec > 0 { parts.append("\(take.durationSec / 60)分\(take.durationSec % 60)秒") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

/// 趋势折线：琥珀 polyline + 渐变面积，x = take 序（点数均分），y = 百分制 0–100。
/// 只标首末两点数值（中点点多字挤，不如不标——诚实且可读）。
/// 视觉同档案页趋势图语言（0–100 域、25/50/75 虚线网格、末点实心强调），不与其类型耦合。
private struct PieceTrendChart: View {
    let points: [PieceTrend.Point]

    private let chartHeight: CGFloat = 96
    /// 绘图区上下留白：顶部给数值标签，底部给基线
    private let plotTop: CGFloat = 22
    private let plotBottom: CGFloat = 90
    /// 左右留白：首末点的圆点与标签不被裁掉
    private let plotInset: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let left = plotInset
            let right = max(width - plotInset, left + 1)
            ZStack {
                gridLines(left: left, right: right)
                areaPath(left: left, right: right)
                linePath(left: left, right: right)
                endpointLabels(left: left, right: right)
            }
        }
        .frame(height: chartHeight)
        .frame(maxWidth: .infinity)
    }

    /// x：按点数均分（index 0…n-1 → left…right）
    private func x(for index: Int, left: CGFloat, right: CGFloat) -> CGFloat {
        let span = max(points.count - 1, 1)
        return left + CGFloat(index) / CGFloat(span) * (right - left)
    }

    /// y：分值 0–100 映射到绘图区（各维度都是百分制真实分）
    private func y(for value: Int) -> CGFloat {
        let clamped = min(max(value, 0), 100)
        return plotBottom - (plotBottom - plotTop) * CGFloat(clamped) / 100
    }

    private func gridLines(left: CGFloat, right: CGFloat) -> some View {
        ZStack {
            Path { path in
                for value in [25, 50, 75] {
                    let gridY = y(for: value)
                    path.move(to: CGPoint(x: left, y: gridY))
                    path.addLine(to: CGPoint(x: right, y: gridY))
                }
            }
            .stroke(Color.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            Path { path in
                path.move(to: CGPoint(x: left, y: plotBottom))
                path.addLine(to: CGPoint(x: right, y: plotBottom))
            }
            .stroke(Color.border, lineWidth: 1)
        }
    }

    private func areaPath(left: CGFloat, right: CGFloat) -> some View {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: x(for: first.index, left: left, right: right), y: plotBottom))
            for point in points {
                path.addLine(to: CGPoint(x: x(for: point.index, left: left, right: right), y: y(for: point.value)))
            }
            path.addLine(to: CGPoint(x: x(for: last.index, left: left, right: right), y: plotBottom))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [Color.amber.opacity(0.28), Color.amber.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func linePath(left: CGFloat, right: CGFloat) -> some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: x(for: first.index, left: left, right: right), y: y(for: first.value)))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: x(for: point.index, left: left, right: right), y: y(for: point.value)))
            }
        }
        .stroke(Color.amber, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    /// 首末点：圆点 + 数值标签（首点 muted、末点实心琥珀强调——最新一次最重要）
    private func endpointLabels(left: CGFloat, right: CGFloat) -> some View {
        ZStack {
            if let first = points.first {
                pointDot(value: first.value, index: first.index, left: left, right: right, isLatest: points.count == 1)
            }
            if let last = points.last, last.id != points.first?.id {
                pointDot(value: last.value, index: last.index, left: left, right: right, isLatest: true)
            }
        }
    }

    private func pointDot(value: Int, index: Int, left: CGFloat, right: CGFloat, isLatest: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isLatest ? Color.amber : Color.canvas)
                .overlay(
                    Circle().strokeBorder(
                        isLatest ? Color.textPrimary : Color.amber,
                        lineWidth: isLatest ? 1.5 : 2
                    )
                )
                .frame(width: isLatest ? 9 : 6, height: isLatest ? 9 : 6)
            Text("\(value)")
                .font(isLatest ? .system(size: 10, weight: .bold) : .labelMono(9))
                .foregroundStyle(isLatest ? Color.textPrimary : Color.textMuted)
                .monospacedDigit()
                .offset(y: -15)
        }
        .position(x: x(for: index, left: left, right: right), y: y(for: value))
    }
}
