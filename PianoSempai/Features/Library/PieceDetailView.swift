import SwiftData
import SwiftUI

// MARK: - S09 曲目详情（P1 简化：硬标准展示/选段/最近 take；判分与热点 P2）

struct PieceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var errorMarks: [ScoreErrorMark]

    /// 内置教材条目（与导入 Piece 二选一）
    var entry: CatalogEntry?
    var piece: Piece?

    @State private var rangeStart = 1
    @State private var rangeEnd = 8
    @State private var showPracticePlaceholder = false

    private var title: String {
        if let entry { return entry.title }
        return piece?.title ?? ""
    }

    private var referenceTempo: Int {
        entry?.referenceTempo ?? piece?.referenceTempo ?? 0
    }

    private var statusText: String {
        if let entry {
            let state = CourseEngine.catalogStatus(book: entry.book, number: entry.number, pathState: CoursePathState())
            return state == .practicing ? "练习中" : state == .locked ? "未开始" : "未开始"
        }
        return piece.map { p in
            switch p.status {
            case "practicing": "练习中"
            case "passed": "已拿下"
            default: "未开始"
            }
        } ?? ""
    }

    private var scoreName: String {
        entry?.title ?? piece?.title ?? ""
    }

    /// 锁定条目：详情可看（S07b 契约），练习 CTA 禁用并引导
    private var isLocked: Bool {
        guard let entry else { return false }
        return CourseEngine.catalogStatus(book: entry.book, number: entry.number, pathState: CoursePathState()) == .locked
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    passStandardCard.padding(.top, 16)
                    rangeCard.padding(.top, 12)
                    recentTakesCard.padding(.top, 12)

                    // P2 占位：完整判分（TakeAnalysis.measureHeat）落地后提供
                    Button {
                    } label: {
                        HStack {
                            Text("只练错误热点")
                                .font(.titleMd)
                            Spacer()
                            Text("P2 完整判分后提供")
                                .font(.labelSm)
                                .foregroundStyle(Color.textMuted)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                    }
                    .buttonStyle(SecondaryButtonStyle(isEnabled: false, cornerRadius: 8))
                    .disabled(true)
                    .padding(.top, 20)

                    Button {
                        showPracticePlaceholder = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(isLocked ? "路线到达后解锁" : "开始练习")
                            if !isLocked {
                                Image(systemName: "arrow.right")
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: !isLocked, cornerRadius: 12))
                    .disabled(isLocked)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.canvas)
            .overlay(alignment: .topLeading) {
                backButton
            }
            .fullScreenCover(isPresented: $showPracticePlaceholder) { PracticeRoomPlaceholder() }
        }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.textBody)
                .frame(width: 44, height: 44)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.headlineLg)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(statusText)
                    .font(.labelSm)
                    .foregroundStyle(Color.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(Color.amber.opacity(0.4), lineWidth: 1))
            }
            .padding(.leading, 44)
            Text("参考速度 ♩=\(referenceTempo) \(errorLine)")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()
                .padding(.leading, 44)
        }
        .padding(.top, 12)
    }

    /// 疑似谱错计数（真实 ScoreErrorMark 聚合；无标记不显示）
    private var errorLine: String {
        let marks = errorMarks.filter { $0.scoreName == scoreName }
        guard !marks.isEmpty else { return "" }
        let total = marks.reduce(0) { $0 + $1.occurrenceCount }
        return "· 疑似谱面错误 \(total) 处 ⚠"
    }

    /// 过关标准卡（硬指标锁定文案；判定主体声明红线 3）
    private var passStandardCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("过关标准（硬指标，连续 2 遍达标）")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                standardRow("错音率", "≤ 2%")
                standardRow("节奏偏差中位数", "≤ 50ms")
                standardRow("速度", "≥ ♩=72（参考 \(referenceTempo)）")
                Text("由规则引擎判定 · Neko 不能改结果")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private func standardRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.labelMd).foregroundStyle(Color.textBody)
            Spacer()
            Text(value).font(.labelMd).foregroundStyle(Color.textPrimary).monospacedDigit()
        }
    }

    /// 选段卡：起/止步进器（越界钳制；长按连改走系统重复手势——P1 单击步进）
    private var rangeCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("选段")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 24) {
                    measureStepper(label: "起", value: $rangeStart, lowerBound: 1, upperBound: rangeEnd - 1)
                    measureStepper(label: "止", value: $rangeEnd, lowerBound: rangeStart + 1, upperBound: 32)
                }
                Text("开始练习将练第 \(rangeStart)–\(rangeEnd) 小节（共 \(rangeEnd - rangeStart + 1) 小节）")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                    .monospacedDigit()
            }
        }
    }

    private func measureStepper(label: String, value: Binding<Int>, lowerBound: Int, upperBound: Int) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.bodyMd)
                .foregroundStyle(Color.textBody)
            Text("\(value.wrappedValue)")
                .font(.labelMono(16, weight: .medium))
                .foregroundStyle(Color.amber)
                .monospacedDigit()
                .frame(minWidth: 30)
            Button {
                value.wrappedValue = max(lowerBound, value.wrappedValue - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(value.wrappedValue <= lowerBound ? Color.textMuted.opacity(0.4) : Color.textBody)
                    .frame(width: 30, height: 30)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(value.wrappedValue <= lowerBound)
            Button {
                value.wrappedValue = min(upperBound, value.wrappedValue + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(value.wrappedValue >= upperBound ? Color.textMuted.opacity(0.4) : Color.textBody)
                    .frame(width: 30, height: 30)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(value.wrappedValue >= upperBound)
        }
    }

    /// 最近 take（≤3；P1 练习室未接入 pieceId → 诚实空态）
    private var recentTakesCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("最近 Take")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                }
                // P1：Take 与 Piece 的关联（take.pieceId）随练习室批次接入；
                // 现在如实显示空态，不借假数据占位（红线 2）。
                Text("还没有 take。练习室接入后，这里显示最近 3 次。")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }
}
