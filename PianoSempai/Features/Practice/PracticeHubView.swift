import SwiftData
import SwiftUI

// MARK: - 主菜续练路由载荷（item 式呈现：闭包参数全部取自 route，不读侧 @State。
// 旧 Bool + side-@State 写法下，内容闭包求值早于 side-state 写入曾致 pieceTitle 为空、无谱进房）

struct MainPracticeRoute: Identifiable, Equatable {
    let id: UUID
    let book: String
    let number: Int
    let timeLimitMinutes: Int?

    init(book: String, number: Int, timeLimitMinutes: Int?, id: UUID = UUID()) {
        self.id = id
        self.book = book
        self.number = number
        self.timeLimitMinutes = timeLimitMinutes
    }
}

// MARK: - tab3 练习室聚合入口（practice.md：主菜续练/选曲/自由弹奏/最近 take）

struct PracticeHubView: View {
    @Environment(\.modelContext) private var context
    @Query private var dailyPlans: [DailyPlan]
    @Query private var tasks: [PracticeTask]
    let onBrowseLibrary: () -> Void
    let onBrowseArchive: () -> Void

    /// 续练路由载荷（nil = 不呈现；每次点击新建实例，id 不同可再次弹出）
    @State private var mainPracticeRoute: MainPracticeRoute?
    @State private var showFreeplay = false
    @State private var showRecentTakes = false

    private var todayPlan: DailyPlan? {
        let today = Calendar.current.startOfDay(for: Date())
        return dailyPlans.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("练习室")
                    .font(.displayLg)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.top, 8)

                if let plan = todayPlan, let mainTask = tasks.first(where: { $0.taskId == plan.mainTaskId }) {
                    // 今日主菜续练（置顶）
                    hubCard(
                        icon: "arrow.clockwise",
                        title: "今日主菜续练",
                        subtitle: "\(mainTask.book) 第\(mainTask.number)条 · 今日还剩约 \(plan.durationChoice) 分钟",
                        accent: .amber
                    ) {
                        mainPracticeRoute = MainPracticeRoute(book: mainTask.book,
                                                              number: mainTask.number,
                                                              timeLimitMinutes: todayPlan?.durationChoice)
                    }
                    .padding(.top, 16)
                } else {
                    Text("今天还没有主菜任务；完成定级后会出现在这里。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 16)
                }

                hubCard(icon: "music.note.list", title: "选曲练习", subtitle: "从曲库挑一条进入练习室", accent: .amber) {
                    onBrowseLibrary()
                }
                .padding(.top, 12)

                hubCard(icon: "waveform.path", title: "自由弹奏", subtitle: "不打分 · MIDI 记录 · 一句话存档", accent: .compareB) {
                    showFreeplay = true
                }
                .padding(.top, 12)

                hubCard(icon: "clock.arrow.circlepath", title: "最近 take", subtitle: "报告与时间线", accent: .compareB) {
                    showRecentTakes = true
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.canvas)
        .fullScreenCover(item: $mainPracticeRoute) { route in
            let coords = BundledScoreCoordinates.resolve(book: route.book, number: route.number)
            PracticeRoomView(
                taskType: "main",
                pieceTitle: "\(route.book) \(route.number)",
                timeLimitSec: route.timeLimitMinutes.map { $0 * 60 },
                bundledBook: coords?.book,
                bundledNumber: coords?.number ?? 0
            )
        }
        .fullScreenCover(isPresented: $showFreeplay) {
            FreePlayView(onSaved: onBrowseArchive) // S14 spec：保存后跳档案
        }
        .sheet(isPresented: $showRecentTakes) {
            TakesListView()
        }
    }

    private func hubCard(icon: String, title: String, subtitle: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Rectangle().fill(accent).frame(width: 3)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(accent)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    Text(subtitle)
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.vertical, 14)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
