import SwiftData
import SwiftUI

// MARK: - S13 Take 报告（P1 简化：真实统计 + P2 占位；不判定过关、不写课程状态）

struct TakeReportView: View {
    let take: Take
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var errorMarks: [ScoreErrorMark]
    @State private var showMarkSheet = false
    @State private var showPractice = false
    @State private var nekoToast = false

    private var analysis: P1TakeAnalysis {
        TakeAnalysisService.analyze(take: take, errorMarks: errorMarks)
    }

    private var title: String {
        if take.isFreePlay { return take.title.isEmpty ? "自由弹奏" : take.title }
        if let from = take.measureFrom, let to = take.measureTo {
            return "练习 · 第\(from)–\(to)小节"
        }
        return "练习 take"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                wrongNoteCard.padding(.top, 16)
                wrongListCard.padding(.top, 12)
                pendingCard.padding(.top, 12)
                confidenceCard.padding(.top, 12)
                actions.padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.canvas)
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.textBody)
                    .frame(width: 44, height: 44)
            }
        }
        .sheet(isPresented: $showMarkSheet) {
            S13bMarkSheet(
                scoreName: title,
                measure: analysis.wrongNotes.first?.measure ?? 1
            ) { type, note in
                submitMark(type: type, note: note)
            }
        }
        .fullScreenCover(isPresented: $showPractice) {
            PracticeRoomView(taskType: take.taskType.isEmpty ? "main" : take.taskType)
        }
        .overlay {
            if nekoToast {
                ToastCapsule(text: "AI 助教将在后续版本开放")
            }
        }
    }

    private func submitMark(type: String, note: String) {
        let measure = analysis.wrongNotes.first?.measure ?? 1
        // 同小节重复提交合并计数（spec）
        if let existing = errorMarks.first(where: { $0.scoreName == title && $0.measure == measure }) {
            existing.occurrenceCount += 1
            existing.type = type
            if !note.isEmpty { existing.note = note }
        } else {
            context.insert(ScoreErrorMark(scoreName: title, measure: measure, type: type, note: note))
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Take 报告 · \(title)")
                .font(.headlineLg)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            let dateText = take.startedAt.formatted(date: .abbreviated, time: .omitted)
            Text("\(dateText) \(take.startedAt.formatted(date: .omitted, time: .shortened)) · ♩=\(take.tempoAvg) · 时长 \(take.durationSec / 60)分\(take.durationSec % 60)秒")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()
        }
        .padding(.top, 8)
        .padding(.leading, 44)
    }

    // MARK: 错音率卡（真实统计；剔除规则可见）

    private var wrongNoteCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                statRow("时长", "\(take.durationSec / 60)分\(take.durationSec % 60)秒")
                statRow("音符数", "\(analysis.noteCount)")
                HStack(alignment: .firstTextBaseline) {
                    Text("错音数")
                        .font(.labelMd)
                        .foregroundStyle(Color.textBody)
                    Spacer()
                    if analysis.exclusionApplied {
                        // S13b 展示：被标小节从分子扣除（引擎规则）
                        Text("\(analysis.wrongNotes.count - analysis.effectiveWrongCount) 处已标谱错剔除")
                            .font(.labelSm)
                            .foregroundStyle(Color.amber)
                    }
                    Text("\(analysis.effectiveWrongCount)")
                        .font(.titleMd)
                        .foregroundStyle(analysis.effectiveWrongCount > 0 ? Color.danger : Color.success)
                        .monospacedDigit()
                }
                if let rate = analysis.wrongNoteRate {
                    statRow("错音率", String(format: "%.1f%%", rate * 100))
                } else {
                    statRow("错音率", "没有音符，不计算")
                }
                statRow("速度", "♩=\(analysis.tempoAvg)")
                statRow("踏板事件（CC64）", "\(analysis.pedalEventCount)")
                statRow("MIDI 事件", "\(analysis.midiEventCount)")
                if !take.interruptionRanges.isEmpty {
                    statRow("断连续录", "\(take.interruptionRanges.count) 次（断点已标）")
                }
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.labelMd).foregroundStyle(Color.textBody)
            Spacer()
            Text(value).font(.labelMd).foregroundStyle(Color.textPrimary).monospacedDigit()
        }
    }

    // MARK: 错音清单（有明细才展示；被标行显示谱错标签）

    @ViewBuilder
    private var wrongListCard: some View {
        if analysis.hasDetail {
            NocturneCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("错音清单")
                            .font(.titleMd)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("长按可标疑似谱错")
                            .font(.labelSm)
                            .foregroundStyle(Color.textMuted)
                    }
                    ForEach(analysis.wrongNotes, id: \.self) { wrong in
                        let marked = analysis.excludedMeasures.contains(wrong.measure)
                        WrongNoteRow(wrong: wrong, marked: marked)
                            .contextMenu {
                                Button {
                                    showMarkSheet = true
                                } label: {
                                    Label("标记疑似谱面错误", systemImage: "flag")
                                }
                            }
                    }
                    Text("匹配口径：P1 简单匹配（音序贪心），非对齐算法。")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
    }

    // MARK: P2 占位卡（绝不填假数字）

    private var pendingCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("完整判分")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                ForEach(analysis.pendingDimensionNames, id: \.self) { name in
                    HStack {
                        Rectangle().fill(Color.borderInput).frame(width: 2, height: 14)
                        Text("\(name)：分析将在 P2 提供")
                            .font(.bodySm)
                            .foregroundStyle(Color.textMuted)
                    }
                }
                Text("本页不判定过关；连续 2 遍达标由课程引擎在 take 写入后判定（P2 接入）。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    // MARK: 置信度与数据卡

    private var confidenceCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("P1 简化匹配 · 无对齐置信度（P2 提供）")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                Text("踏板 CC64 已记录 \(analysis.pedalEventCount) 次（判分参与在 P2）")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                Text("MIDI 原始事件已存本机（只追加）")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    // MARK: 底部动作

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                showPractice = true
            } label: {
                Text("再练一遍 ♩=60")
            }
            .buttonStyle(SecondaryButtonStyle(cornerRadius: 8))
            Button {
                nekoToast = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    nekoToast = false
                }
            } label: {
                Text("问 Neko 这一段")
                    .font(.titleMd)
                    .foregroundStyle(Color.amber)
            }
            .buttonStyle(.plain)
        }
    }
}

/// 错音行（小节号琥珀 mono + 被标行谱错标签）
struct WrongNoteRow: View {
    let wrong: WrongNoteRecord
    let marked: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("第\(wrong.measure)小节")
                .font(.labelMono(12, weight: .medium))
                .foregroundStyle(Color.amber)
                .frame(width: 76, alignment: .leading)
                .monospacedDigit()
            if marked {
                Text("疑似谱错 · 已标记")
                    .font(.labelSm)
                    .foregroundStyle(Color.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Color.amber.opacity(0.4), lineWidth: 1))
            } else {
                Text("多弹/错音 \(SightReadSession.noteName(wrong.actualPitch))（\(wrong.actualPitch)）")
                    .font(.bodySm)
                    .foregroundStyle(Color.textBody)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Take 列表（hub「最近 take」与档案共用）

struct TakesListView: View {
    @Query(sort: \Take.startedAt, order: .reverse) private var takes: [Take]
    @State private var selected: Take?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if takes.isEmpty {
                        Text("还没有 take。去练习室弹一段，这里会出现记录。")
                            .font(.bodySm)
                            .foregroundStyle(Color.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                    ForEach(takes.prefix(50)) { take in
                        Button {
                            selected = take
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rowTitle(take))
                                        .font(.bodyMd)
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)
                                    Text("\(take.startedAt.formatted(date: .abbreviated, time: .shortened)) · ♩=\(take.tempoAvg) · \(take.durationSec / 60)分\(take.durationSec % 60)秒")
                                        .font(.labelSm)
                                        .foregroundStyle(Color.textMuted)
                                        .monospacedDigit()
                                }
                                Spacer()
                                if !take.interruptionRanges.isEmpty {
                                    Image(systemName: "wifi.slash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.textMuted)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textMuted)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 56)
                        }
                        .buttonStyle(.plain)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color.canvas)
            .navigationTitle("Take 记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.amber)
                }
            }
            .sheet(item: $selected) { take in
                TakeReportView(take: take)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func rowTitle(_ take: Take) -> String {
        if take.isFreePlay { return take.title.isEmpty ? "自由弹奏" : take.title }
        let type = switch take.taskType {
        case "warmup": "热身"
        case "reward": "奖励曲"
        default: "主菜"
        }
        if let from = take.measureFrom, let to = take.measureTo {
            return "\(type) · 第\(from)–\(to)小节"
        }
        return type
    }
}

// MARK: - Take 列表（hub「最近 take」与档案共用）
