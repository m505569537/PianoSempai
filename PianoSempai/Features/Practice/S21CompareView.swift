import Foundation
import SwiftData
import SwiftUI

struct S21CompareView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Take.startedAt, order: .reverse) private var allTakes: [Take]
    @Query(sort: \TakeAnalysis.analyzedAt, order: .reverse) private var analyses: [TakeAnalysis]
    @Query private var pieces: [Piece]

    @State private var takeA: Take?
    @State private var takeB: Take?
    @State private var showPicker = false
    @State private var pickerTargetA = true

    init(takeA: Take?) {
        _takeA = State(initialValue: takeA)
    }

    private var pieceA: Piece? { takeA.flatMap { piece in pieces.first { $0.entityId == piece.pieceId } } }
    private var pieceB: Piece? { takeB.flatMap { piece in pieces.first { $0.entityId == piece.pieceId } } }

    private var analysisA: TakeAnalysis? { takeA.flatMap { analysis(for: $0) } }
    private var analysisB: TakeAnalysis? { takeB.flatMap { analysis(for: $0) } }

    private var canCompare: Bool {
        guard let a = takeA, let b = takeB else { return false }
        return a.pieceId == b.pieceId && a.measureFrom == b.measureFrom && a.measureTo == b.measureTo
    }

    private var comparison: ComparisonData? {
        guard canCompare, let a = analysisA, let b = analysisB else { return nil }
        return ComparisonData(a: a, b: b, piece: pieceA)
    }

    private func analysis(for take: Take) -> TakeAnalysis? {
        if let id = take.analysisId, let row = analyses.first(where: { $0.entityId == id }) { return row }
        return analyses.first { $0.takeId == take.entityId && !$0.engineVersion.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sampleSelectionCard
                    if let comp = comparison {
                        radarCard(comp)
                        tempoCard(comp)
                        heatCompareCard(comp)
                        deltaCard(comp)
                        ctaCard(comp)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color.canvas)
            .navigationTitle("Take 对比")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.textMuted)
                            .frame(width: 32, height: 32)
                            .background(Color.card, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showPicker) {
                S21TakePickerView(
                    title: pickerTargetA ? "选择 Take A（基准）" : "选择 Take B（对比）"
                ) { selected in
                    if pickerTargetA { takeA = selected } else { takeB = selected }
                    showPicker = false
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func candidateTakes(for current: Take?) -> [Take] {
        guard let current else { return allTakes }
        return allTakes.filter {
            $0.entityId != current.entityId &&
            $0.pieceId == current.pieceId &&
            $0.measureFrom == current.measureFrom &&
            $0.measureTo == current.measureTo
        }
    }

    private var sampleSelectionCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("对比样本设置", trailing: canCompare ? "基准: Take A" : nil)
                sampleRow(label: "Take A", take: takeA, color: .amber) { pickerTargetA = true; showPicker = true }
                sampleRow(label: "Take B", take: takeB, color: .compareB) { pickerTargetA = false; showPicker = true }
                Text("只对比同一首曲目同一小节段")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private func sampleRow(label: String, take: Take?, color: Color, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.labelMd).foregroundStyle(Color.textBody)
            Spacer()
            if let take = take {
                Text(takeOrdinalLabel(take)).font(.labelMono(13)).foregroundStyle(color)
                Text("♩=\(take.tempoAvg)").font(.labelMono(12)).foregroundStyle(Color.textMuted)
                Text(weakTotalLabel(take)).font(.labelMono(14, weight: .bold)).foregroundStyle(color)
            } else {
                Text("未选择").font(.labelMd).foregroundStyle(Color.textMuted)
            }
            Button(action: action) {
                Image(systemName: "chevron.right").font(.system(size: 14)).foregroundStyle(Color.textMuted)
            }
        }
        .padding(10)
        .background(Color.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.3), lineWidth: 1))
    }

    private func takeOrdinalLabel(_ take: Take) -> String {
        guard let pieceId = take.pieceId else { return "自由弹奏" }
        let samePiece = allTakes.filter { $0.pieceId == pieceId }.sorted { $0.startedAt < $1.startedAt }
        guard let idx = samePiece.firstIndex(where: { $0.entityId == take.entityId }) else { return "?" }
        let type = switch take.taskType {
        case "warmup": "热身"
        case "reward": "奖励曲"
        case "review": "复习"
        default: "主课"
        }
        return "\(type) 第\(idx + 1)遍"
    }

    private func weakTotalLabel(_ take: Take) -> String {
        guard let a = analysis(for: take) else { return "—" }
        if let weak = a.weakTotal { return "\(weak)分" }
        return "数据不足"
    }

    private func radarCard(_ comp: ComparisonData) -> some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("六维对比").font(.system(size: 15, weight: .bold, design: .serif))
                    Spacer()
                    HStack(spacing: 12) {
                        legendDot(color: .amber, label: "A 今天")
                        legendDot(color: .compareB, label: "B 周一")
                    }
                }
                .font(.labelMd)
                .foregroundStyle(Color.textBody)
                S21RadarChart(scoresA: comp.scoresA, scoresB: comp.scoresB)
                    .frame(height: 200)
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(.labelSm).foregroundStyle(Color.textMuted)
        }
    }

    private func tempoCard(_ comp: ComparisonData) -> some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("速度对比").font(.system(size: 15, weight: .bold, design: .serif)).foregroundStyle(Color.textBody)
                Text("♩= 参考线 \(comp.referenceTempo > 0 ? "\(comp.referenceTempo)" : "—")")
                    .font(.labelMono(11)).foregroundStyle(Color.textMuted)
                if comp.avgBPMA > 0 && comp.avgBPMB > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 20) {
                        VStack(spacing: 4) {
                            Text(String(format: "%g", comp.avgBPMA)).font(.titleMd).foregroundStyle(Color.amber)
                            Text("A").font(.labelMono(12)).foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        VStack(spacing: 4) {
                            Text(String(format: "%g", comp.avgBPMB)).font(.titleMd).foregroundStyle(Color.compareB)
                            Text("B").font(.labelMono(12)).foregroundStyle(Color.textMuted)
                        }
                    }
                    .padding(.horizontal, 8)
                } else {
                    Text("速度数据不足").font(.bodySm).foregroundStyle(Color.textMuted)
                }
            }
        }
    }

    private func heatCompareCard(_ comp: ComparisonData) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("错音热点对比").font(.system(size: 15, weight: .bold, design: .serif)).foregroundStyle(Color.textBody)
                heatRow(label: "A（这一遍）", measures: comp.hotMeasuresA, summary: comp.heatSummaryA, color: .amber)
                heatRow(label: "B（上一遍）", measures: comp.hotMeasuresB, summary: comp.heatSummaryB, color: .compareB)
            }
        }
    }

    private func heatRow(label: String, measures: [Int], summary: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.labelMd).foregroundStyle(Color.textBody)
                Spacer()
                Text(summary).font(.labelMono(12)).foregroundStyle(color)
            }
            if measures.isEmpty {
                Text("无热点数据").font(.labelSm).foregroundStyle(Color.textMuted)
            } else {
                HStack(spacing: 4) {
                    ForEach(measures.prefix(8), id: \.self) { m in
                        Text("\(m)").font(.labelMono(10)).foregroundStyle(color)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.3), lineWidth: 1))
                    }
                }
            }
        }
    }

    private func deltaCard(_ comp: ComparisonData) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("关键指标进阶").font(.system(size: 15, weight: .bold, design: .serif)).foregroundStyle(Color.textBody)
                if let delta = comp.improvementDelta {
                    HStack {
                        Text("综合提升 +\(delta)分").font(.labelMono(12)).foregroundStyle(Color.amber)
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Color.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.amber.opacity(0.2), lineWidth: 1))
                }
                deltaRow(label: "错音率", oldValue: comp.wrongRateA.map { String(format: "%.1f%%", $0 * 100) } ?? "—", newValue: comp.wrongRateB.map { String(format: "%.1f%%", $0 * 100) } ?? "—")
                deltaRow(label: "平均速度", oldValue: comp.avgBPMA > 0 ? "\(Int(comp.avgBPMA)) BPM" : "—", newValue: comp.avgBPMB > 0 ? "\(Int(comp.avgBPMB)) BPM" : "—")
                deltaRow(label: "弱总分", oldValue: comp.weakTotalA.map { "\($0)分" } ?? "数据不足", newValue: comp.weakTotalB.map { "\($0)分" } ?? "数据不足")
                Text("对比仅展示，不产生新的过关判定。")
                    .font(.labelSm).foregroundStyle(Color.textMuted).padding(.top, 8)
            }
        }
    }

    private func deltaRow(label: String, oldValue: String, newValue: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.labelMd).foregroundStyle(Color.textBody)
            Spacer()
            Text(oldValue).font(.labelMono(13)).foregroundStyle(Color.textMuted)
            Text("→").font(.labelSm).foregroundStyle(Color.textMuted)
            Text(newValue).font(.labelMono(13)).foregroundStyle(Color.amber)
        }
        .padding(10)
        .background(Color.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border.opacity(0.4), lineWidth: 1))
    }

    private func ctaCard(_ comp: ComparisonData) -> some View {
        let hottest = comp.sharedHotMeasure
        return Button {
            // TODO: 接入 LoopService 预填热点小节（待 P12 热点锁定能力确认后接入）
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.trianglehead.clockwise").font(.system(size: 16))
                Text(hottest.map { "针对第\($0)小节发起专项循环" } ?? "选择有热点的 take 发起循环")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.canvas)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.amber, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.amber.opacity(0.25), radius: 16, y: 4)
        }
        .buttonStyle(S21PressScaleStyle())
        .padding(.top, 4)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
    }

    private func cardHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(Color.amber).frame(width: 6, height: 14)
            Text(title).font(.system(size: 15, weight: .bold, design: .serif)).tracking(0.4).foregroundStyle(Color.textPrimary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.labelMono(12, weight: .semibold)).foregroundStyle(Color.amber)
            }
        }
    }
}

private struct ComparisonData {
    let scoresA: [Double?]
    let scoresB: [Double?]
    let avgBPMA: Double
    let avgBPMB: Double
    let referenceTempo: Int
    let weakTotalA: Int?
    let weakTotalB: Int?
    let improvementDelta: Int?
    let wrongRateA: Double?
    let wrongRateB: Double?
    let hotMeasuresA: [Int]
    let hotMeasuresB: [Int]
    let heatSummaryA: String
    let heatSummaryB: String
    let sharedHotMeasure: Int?

    init(a: TakeAnalysis, b: TakeAnalysis, piece: Piece?) {
        func radarScores(for analysis: TakeAnalysis) -> [Double?] {
            let report = TakeReportPresentation.build(analysis: analysis, standards: ScoringStandards.standards(forBook: ""), consecutivePasses: 0)
            let pitch = report.dimensions.first { $0.name == "音高" }?.score.map { Double($0) / 100 }
            let rhythm = report.dimensions.first { $0.name == "节奏" }?.score.map { Double($0) / 100 }
            let continuity = report.dimensions.first { $0.name == "连续性" }?.score.map { Double($0) / 100 }
            let tempo = report.dimensions.first { $0.name == "速度稳定性" }?.score.map { Double($0) / 100 }
            let hands = report.dimensions.first { $0.name == "双手协同" }?.score.map { Double($0) / 100 }
            return [pitch, rhythm, continuity, tempo, pitch, hands]
        }

        self.scoresA = radarScores(for: a)
        self.scoresB = radarScores(for: b)
        self.avgBPMA = a.avgBPM
        self.avgBPMB = b.avgBPM
        self.referenceTempo = piece?.referenceTempo ?? 0
        self.weakTotalA = a.weakTotal
        self.weakTotalB = b.weakTotal
        self.improvementDelta = (weakTotalB.map { Double($0) } ?? 0.0) > 0 && (weakTotalA.map { Double($0) } ?? 0.0) > 0
            ? Int((Double(weakTotalB!) - Double(weakTotalA!)).rounded()) : nil
        self.wrongRateA = a.referenceNoteCount > 0 ? Double(a.wrongPitchCount) / Double(a.referenceNoteCount) : nil
        self.wrongRateB = b.referenceNoteCount > 0 ? Double(b.wrongPitchCount) / Double(b.referenceNoteCount) : nil

        let heatA = TakeReportPresentation.decodeHeat(a.measureHeatJSON)
        let heatB = TakeReportPresentation.decodeHeat(b.measureHeatJSON)
        let hotA = heatA.sorted { $0.heat > $1.heat }.prefix(3).map { $0.measure }
        let hotB = heatB.sorted { $0.heat > $1.heat }.prefix(3).map { $0.measure }
        self.hotMeasuresA = Array(hotA)
        self.hotMeasuresB = Array(hotB)
        self.heatSummaryA = "共 \(a.wrongPitchCount) 处错音 · 集中在 \(hotA.first.map { "第\($0)小节" } ?? "—")"
        self.heatSummaryB = "共 \(b.wrongPitchCount) 处错音 · \(hotB.map { "第\($0)" }.joined(separator: "/")) 小节"
        self.sharedHotMeasure = Set(hotA).intersection(Set(hotB)).first
    }
}

private struct S21TakePickerView: View {
    let title: String
    let onSelect: (Take) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Take.startedAt, order: .reverse) private var takes: [Take]

    var body: some View {
        NavigationStack {
            List(takes) { take in
                Button {
                    onSelect(take)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(takeOrdinal(take)).font(.bodyMd).foregroundStyle(Color.textPrimary)
                            Text("♩=\(take.tempoAvg) · \(take.durationSec / 60)分\(take.durationSec % 60)秒").font(.labelSm).foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func takeOrdinal(_ take: Take) -> String {
        let type = switch take.taskType {
        case "warmup": "热身"
        case "reward": "奖励曲"
        case "review": "复习"
        default: "主课"
        }
        if let from = take.measureFrom, let to = take.measureTo {
            return "\(type) · 第\(from)–\(to)小节"
        }
        return type
    }
}

private struct S21RadarChart: View {
    let scoresA: [Double?]
    let scoresB: [Double?]

    private static let canvas = CGSize(width: 290, height: 240)
    private static let center = CGPoint(x: 145, y: 115)
    private static let radii: [CGFloat] = [25, 50, 75, 95]
    private static let axisNames = ["音准", "节奏", "连续性", "速度", "读谱", "双手协同"]

    private func vertex(_ index: Int, radius: CGFloat) -> CGPoint {
        let r = Angle.degrees(-90 + 60 * Double(index)).radians
        return CGPoint(x: Self.center.x + radius * CGFloat(cos(r)), y: Self.center.y + radius * CGFloat(sin(r)))
    }

    private func points(for scores: [Double?]) -> [CGPoint] {
        Array(scores.enumerated()).compactMap { idx, score in
            guard let s = score else { return nil }
            return vertex(idx, radius: CGFloat(s) * Self.radii.last!)
        }
    }

    var body: some View {
        ZStack {
            ForEach(Self.radii, id: \.self) { radius in
                S21Hexagon(center: Self.center, radius: radius)
                    .stroke(radius == Self.radii.last! ? Color.border : Color.border.opacity(0.6), style: StrokeStyle(lineWidth: radius == Self.radii.last! ? 1.2 : 0.8, dash: radius == Self.radii.first! ? [2, 2] : []))
            }
            ForEach(0..<6, id: \.self) { i in
                Path { p in
                    p.move(to: Self.center)
                    p.addLine(to: vertex(i, radius: Self.radii.last!))
                }
                .stroke(Color.border, lineWidth: 1)
            }
            S21RadarPolygon(points: points(for: scoresB))
                .fill(Color.compareB.opacity(0.15))
                .overlay(S21RadarPolygon(points: points(for: scoresB)).stroke(Color.compareB, lineWidth: 2))
            S21RadarPolygon(points: points(for: scoresA))
                .fill(Color.amber.opacity(0.22))
                .overlay(S21RadarPolygon(points: points(for: scoresA)).stroke(Color.amber, lineWidth: 2.2))
            ForEach(Array(Self.axisNames.enumerated()), id: \.offset) { idx, name in
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 44, alignment: idx == 0 || idx == 3 ? .center : (idx < 3 ? .leading : .trailing))
                    .position(vertex(idx, radius: Self.radii.last! + 22))
            }
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
    }
}

private struct S21Hexagon: Shape {
    let center: CGPoint
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 0..<6 {
            let r = Angle.degrees(-90 + 60 * Double(i)).radians
            let pt = CGPoint(x: center.x + radius * CGFloat(cos(r)), y: center.y + radius * CGFloat(sin(r)))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

private struct S21RadarPolygon: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }
}

private struct S21PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}