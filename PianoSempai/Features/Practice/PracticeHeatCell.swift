import SwiftUI

// MARK: - 练习热力共享件（L7 详情页练习进度网格 + C4 报告页错音热力双条，同一处实现）
//
// S13 报告页原来私有的 heatCell / S13HeatTier 抽到这儿：详情页（S09）与报告页（S13）画的是
// 同一件东西（小节 → 热度档位 + 该小节真实问题音数 + 小节标号），不各写一份、不各留一版阈值。
// 纯函数部分（档位 / 网格截断 / 热点文案 / 双条 delta）可单测，视图只负责渲染。
//
// 诚实红线：算不出的（无区间 / 无热度 / 无上一遍）一律由调用方显式说没有，不画空图、不放假数据。

/// 热力三档（真值：中性格 / amber 35% / #A04523 + 发光）
enum PracticeHeatTier {
    case neutral
    case mid
    case heavy

    /// 档位只由真实 heat 决定（0/极低 → 中性；≥0.5 → 最重）
    static func tier(heat: Double) -> PracticeHeatTier {
        if heat >= 0.5 { return .heavy }
        if heat > 0.02 { return .mid }
        return .neutral
    }

    var fill: Color {
        switch self {
        case .neutral: Color.s13CellNeutral
        case .mid: Color.amber.opacity(0.35)
        case .heavy: Color.s13CellHot
        }
    }

    var border: Color {
        switch self {
        case .neutral: Color.s13CellNeutralBorder
        case .mid: Color.amber.opacity(0.4)
        case .heavy: Color.s13Danger
        }
    }

    var textColor: Color {
        switch self {
        case .neutral: Color.s13Subtle
        case .mid: Color.amber
        case .heavy: Color.s13CellHotText
        }
    }

    var labelColor: Color {
        switch self {
        case .neutral: Color.textMuted
        case .mid: Color.amber
        case .heavy: Color.s13Danger
        }
    }
}

/// 单个热力格（真值 34×28pt / r6 / 格与标号间距 4pt）
struct PracticeHeatCell: View {
    /// 1-based 小节号（格下标号）
    let measure: Int
    /// 该小节热度 0...1（无该小节 = 0 → 中性格）
    let heat: Double
    /// 该小节真实问题音数（0 时留空，不编数字）
    let problemCount: Int
    /// 是否错误热点（0-based hotspotMeasures 换算成 1-based 后命中；详情页标注用）
    var isHotspot: Bool = false

    var body: some View {
        let tier = PracticeHeatTier.tier(heat: heat)
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(tier.fill)
                    .frame(height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).strokeBorder(tier.border, lineWidth: 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        // 热点标记：右上角 5pt 琥珀点（只有真实 hotspotMeasures 命中才画）
                        if isHotspot {
                            Circle()
                                .fill(Color.amber)
                                .frame(width: 5, height: 5)
                                .padding(3)
                        }
                    }
                    .shadow(
                        color: tier == .heavy ? Color.s13AmberDeep.opacity(0.4) : Color.clear,
                        radius: 4
                    )
                switch tier {
                case .neutral:
                    Text("✓")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.s13Subtle)
                case .mid, .heavy:
                    // 只显该小节真实问题音数；为 0 时留空，不编数字
                    if problemCount > 0 {
                        Text("\(problemCount)")
                            .font(.labelMono(10, weight: .bold))
                            .foregroundStyle(tier.textColor)
                    }
                }
            }
            Text("\(measure)")
                .font(.labelMono(10, weight: tier == .heavy ? .bold : .regular))
                .foregroundStyle(tier.labelColor)
        }
    }
}

/// 网格口径（列数 / 两页各自的上限 / 截断说明）：报告页与详情页共用同一组常数与同一句说明
enum PracticeHeatGrid {
    /// 列数（真值 8 列）
    static let columns = 8
    /// 报告页热力格上限（8 列 × 4 行；区间异常长时只画前 N 格并如实说明，不无限拉长页面）
    static let reportCellLimit = 32
    /// 详情页练习进度格上限（8 列 1 行：只看区间开头，全量进报告页）
    static let detailCellLimit = 8

    /// 网格列（两页同一份，不各写一遍 GridItem）
    static var items: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: columns)
    }

    /// 由存储的小节起止算展示区间（1-based）。任一端缺失 / 反向 → nil：
    /// 调用方据此显诚实文案，不画空图（ClosedRange 自身拒绝反向区间，故校验只能在构造前做）。
    static func range(from: Int?, to: Int?) -> ClosedRange<Int>? {
        guard let from, let to, from <= to else { return nil }
        return from...to
    }

    /// 要画的小节（1-based，区间前 limit 格）
    static func shownMeasures(_ range: ClosedRange<Int>, limit: Int) -> [Int] {
        Array(range.prefix(max(limit, 0)))
    }

    /// 截断说明：区间比画下的格长时才说（不悄悄截断）；没截断 → nil
    static func truncationText(total: Int, shown: Int) -> String? {
        guard shown < total else { return nil }
        return "…共 \(total) 小节，此处显示前 \(shown) 格"
    }
}

/// 热点小节文案（真实派生：`TakeAnalysis.hotspotMeasures` 是 0-based，展示 +1）。
/// 空 / 非法（负下标）→ nil，不编小节号。
enum PracticeHeatHotspot {
    /// 「第 X–Y 小节」；单节「第 X 小节」
    static func rangeLine(_ hotspots: [Int]) -> String? {
        guard let first = hotspots.min(), let last = hotspots.max(), first >= 0 else { return nil }
        return first == last ? "第 \(first + 1) 小节" : "第 \(first + 1)–\(last + 1) 小节"
    }

    /// 详情页进度网格上的热点行：「重点小节：第 X–Y 小节」；无热点 → nil（整行不渲染）
    static func labelLine(_ hotspots: [Int]) -> String? {
        rangeLine(hotspots).map { "重点小节：\($0)" }
    }

    /// 0-based 热点数组 → 1-based 集合（格子标号是 1-based，换算只在这一处做）
    static func oneBased(_ hotspots: [Int]) -> Set<Int> {
        Set(hotspots.filter { $0 >= 0 }.map { $0 + 1 })
    }
}

/// 空态诚实文案（集中一处：两页与测试对齐，不留「假装会有」的占位句）
enum PracticeHeatText {
    /// 详情页：该曲目没有任何逐小节热度（没练过 / 没判分）
    static let noData = "暂无练习数据。练过并判分后，这里显示逐小节热度。"
    /// 详情页：有热度，但所属 take 没有小节区间（自由弹奏）
    static let noMeasureRange = "最近一次练习没有小节区间（自由弹奏），不画进度网格。"
    /// 报告页 C4：没有上一遍可对比（首遍 / 上一遍没有热度数据）
    static let noPreviousPass = "暂无上一遍对比（第一遍，或上一遍没有热度数据）。"
    /// 报告页 C4：两遍没有共同小节（不拿 0 冒充没练过的小节）
    static let noSharedMeasures = "与上一遍没有共同小节，不做热度对比。"
}

/// 双条的一列（C4）：同一小节的两遍热度，上条＝上一遍、下条＝这一遍
struct PracticeHeatBar: Equatable, Identifiable {
    /// 1-based 小节
    let measure: Int
    let previousHeat: Double
    let currentHeat: Double

    var id: Int { measure }

    /// 按给定小节（已截断的展示区间）取两遍热度；任一遍缺该小节 → 不生成（不拿 0 冒充）
    static func bars(previous: [MeasureHeat], current: [MeasureHeat], measures: [Int]) -> [PracticeHeatBar] {
        let previousByMeasure = previous.heatByMeasure
        let currentByMeasure = current.heatByMeasure
        return measures.compactMap { measure in
            guard let before = previousByMeasure[measure], let now = currentByMeasure[measure] else { return nil }
            return PracticeHeatBar(measure: measure, previousHeat: before, currentHeat: now)
        }
    }
}

/// 关键 delta（C4）：这一遍 heat − 上一遍 heat，四舍五入到整数百分比。
/// 两遍各自来自自己那一条分析行（单 take 单行），只并排比较，不做任何跨 take 聚合。
struct PracticeHeatDelta: Equatable, Identifiable {
    /// 关键 delta 列表条数（取 |delta| 最大的前 N 个）
    static let topCount = 3

    /// 1-based 小节
    let measure: Int
    /// 这一遍 − 上一遍（整数百分比；+30 = 这一遍这个小节更热，即问题更多）
    let deltaPercent: Int

    var id: Int { measure }

    /// 「小节 3：热度 +30%」/ 负值「小节 5：热度 -20%」（如实带符号，不用「低」含糊掉）
    var text: String {
        let sign = deltaPercent > 0 ? "+" : ""
        return "小节 \(measure)：热度 \(sign)\(deltaPercent)%"
    }

    /// |delta| 最大的前 limit 个小节（降序；并列取较小小节）。
    /// 上一遍或这一遍为空 → 空数组：调用方不画双条，改显「暂无上一遍对比」。
    /// 只在两遍都真实出现过的小节上比（一边没有的小节不编 delta）。
    static func list(
        previous: [MeasureHeat],
        current: [MeasureHeat],
        limit: Int = topCount
    ) -> [PracticeHeatDelta] {
        guard !previous.isEmpty, !current.isEmpty else { return [] }
        let previousByMeasure = previous.heatByMeasure
        let currentByMeasure = current.heatByMeasure
        let shared = Set(previousByMeasure.keys).intersection(currentByMeasure.keys).sorted()
        let ranked = shared
            .map { measure -> PracticeHeatDelta in
                let delta = (currentByMeasure[measure] ?? 0) - (previousByMeasure[measure] ?? 0)
                return PracticeHeatDelta(measure: measure, deltaPercent: Int((delta * 100).rounded()))
            }
            .sorted { lhs, rhs in
                let lhsMagnitude = abs(lhs.deltaPercent)
                let rhsMagnitude = abs(rhs.deltaPercent)
                // 并列取较小小节（结果稳定，不随入序抖）
                if lhsMagnitude == rhsMagnitude { return lhs.measure < rhs.measure }
                return lhsMagnitude > rhsMagnitude
            }
        return limit > 0 ? Array(ranked.prefix(limit)) : []
    }
}

extension Array where Element == MeasureHeat {
    /// 小节 → 热度（重复键取后者；不用 uniqueKeysWithValues，防调用方传入重复项时崩）
    var heatByMeasure: [Int: Double] {
        var map: [Int: Double] = [:]
        for entry in self { map[entry.measure] = entry.heat }
        return map
    }
}

// MARK: - S13 字面量色（DesignSystem token 未覆盖的真值 hex）
// 详情页进度网格与报告页热力共用，故从 TakeReportView 移到这处（不再是单文件私有）。

extension Color {
    /// 深橙 #C86D2B：计数 badge 底、尖峰点
    static let s13AmberDeep = Color(red: 0xC8 / 255, green: 0x6D / 255, blue: 0x2B / 255)
    /// 危险红橙 #E07A5F：错音圆点、最热格描边/标号
    static let s13Danger = Color(red: 0xE0 / 255, green: 0x7A / 255, blue: 0x5F / 255)
    /// 弱注记 #6A635B
    static let s13Subtle = Color(red: 0x6A / 255, green: 0x63 / 255, blue: 0x5B / 255)
    /// 热力图网格容器底 #1F1B19
    static let s13HeatWell = Color(red: 0x1F / 255, green: 0x1B / 255, blue: 0x19 / 255)
    /// 中性格底 #2C2724 / 边框 #3A332F
    static let s13CellNeutral = Color(red: 0x2C / 255, green: 0x27 / 255, blue: 0x24 / 255)
    static let s13CellNeutralBorder = Color(red: 0x3A / 255, green: 0x33 / 255, blue: 0x2F / 255)
    /// 最热格底 #A04523 / 格内字 #FFF1EB
    static let s13CellHot = Color(red: 0xA0 / 255, green: 0x45 / 255, blue: 0x23 / 255)
    static let s13CellHotText = Color(red: 0xFF / 255, green: 0xF1 / 255, blue: 0xEB / 255)
    /// 节奏图容器底 #1B1816 / 0 轴 #4A423C
    static let s13ChartWell = Color(red: 0x1B / 255, green: 0x18 / 255, blue: 0x16 / 255)
    static let s13AxisZero = Color(red: 0x4A / 255, green: 0x42 / 255, blue: 0x3C / 255)
    /// 雷达最外环描边 #3F3732
    static let s13RingOuter = Color(red: 0x3F / 255, green: 0x37 / 255, blue: 0x32 / 255)
}
