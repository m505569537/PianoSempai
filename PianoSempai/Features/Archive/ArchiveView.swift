import SwiftData
import SwiftUI

// MARK: - S20 档案（P1 简版：本周统计 + take 时间线（筛选 chips）；趋势/周报入口置后续版本）

struct ArchiveView: View {
    @Query(sort: \Take.startedAt, order: .reverse) private var takes: [Take]
    @Query private var settingsList: [AppSettings]

    enum Filter: String, CaseIterable {
        case all = "全部"
        case warmup = "热身"
        case main = "主菜"
        case reward = "奖励曲"
        case free = "自由弹奏"
    }

    @State private var filter: Filter = .all
    @State private var selected: Take?
    @State private var now = Date()

    private var settings: AppSettings? { settingsList.first }

    private var filtered: [Take] {
        takes.filter { take in
            switch filter {
            case .all: true
            case .warmup: take.taskType == "warmup"
            case .main: take.taskType == "main"
            case .reward: take.taskType == "reward"
            case .free: take.isFreePlay
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("档案")
                    .font(.displayLg)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.top, 8)

                weekStatsCard.padding(.top, 16)

                Text("Take 时间线")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.top, 20)

                filterChips.padding(.top, 10)

                if filtered.isEmpty {
                    Text(filter == .all
                        ? "还没有 take。练习室弹一段，这里会出现记录。"
                        : "这个筛选下还没有 take。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                }
                ForEach(filtered) { take in
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

                // 趋势图 / 周报：后续版本（brief P1 简版边界）
                Text("趋势图与周报入口将在后续版本提供。")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.canvas)
        .sheet(item: $selected) { take in
            TakeReportView(take: take)
        }
        .onAppear { now = Date() }
    }

    private var weekStatsCard: some View {
        let progress = TodayPlanService.weekProgress(
            takes: takes, weeklyGoal: settings?.weeklyGoal ?? 3,
            dailyChoiceMinutes: 30, today: now
        )
        let streak = TodayPlanService.weekStreak(takes: takes, today: now)
        return NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("本周")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 16) {
                    stat("\(progress.doneMinutes) 分钟", "有效练习")
                    stat("\(streak.litDays.filter { $0 }.count) / 7", "streak 灯")
                    stat("\(takes.count)", "累计 take")
                }
                // 7 灯
                HStack(spacing: 0) {
                    let labels = ["一", "二", "三", "四", "五", "六", "日"]
                    ForEach(0..<7, id: \.self) { i in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(streak.litDays[i] ? Color.amber : Color.clear)
                                .overlay(Circle().strokeBorder(
                                    streak.litDays[i] ? Color.amber : Color.borderInput, lineWidth: 1
                                ))
                                .frame(width: 10, height: 10)
                            Text(labels[i])
                                .font(.labelSm)
                                .foregroundStyle(Color.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.labelMono(15, weight: .medium))
                .foregroundStyle(Color.amber)
                .monospacedDigit()
            Text(label)
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases, id: \.self) { f in
                NocturneChip(title: f.rawValue, isSelected: filter == f) {
                    filter = f
                }
            }
            Spacer()
        }
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
