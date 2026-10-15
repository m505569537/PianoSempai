import SheetMusicCore
import SheetMusicLayout
import SheetMusicLayoutApple
import SheetMusicUI
import SwiftUI

/// iOS 26 起关闭 ScrollView 自动滚动边缘渐隐（低版本无此效果，直通）。
private struct ScrollEdgeEffectHiddenAll: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .all)
        } else {
            content
        }
    }
}

/// 练习室谱面滚动视图（问题3 自动滚动 / 问题4 每行小节数 / 问题5 弹性增高）。
///
/// 与旧实现的差别：
/// - App 层先把原始 score 经 ScoreLineBreaker 转成「每行 N 小节」，再用 LayoutEngine 算出
///   LayoutDocument，交给 ScoreView(document:) 渲染（布局由我们掌控，光标定位基于同一 document）。
/// - 每个 system 配一个真实占位高度的锚点（VStack(spacing: 0) 顺序堆叠，不用 .offset——
///   .offset 只动渲染不动布局，会让 ScrollViewReader 把所有锚点都当成在 y=0），
///   ScrollViewReader 在光标跨 system 时 scrollTo 居中（音符走出视口即自动跟随）。
/// - 自身不设固定高度，由父级 VStack 的弹性空间决定（谱区占满控件以上全部可用高度）。
struct PracticeScoreScrollView: View {
    let score: Score
    let measuresPerLine: Int
    let cursor: ScoreCursor?
    /// P4 纸内谱头/页脚元数据
    let pieceTitle: String
    let pieceBook: String
    let pieceNumber: Int
    let referenceTempo: Int
    let opusTag: String?
    let leftHandNote: String?
    let copyrightNotice: String?
    /// P3 分手模式
    let handMode: HandMode

    /// 转换后（已重排换行）的谱，供 ScoreView 与光标定位共用。
    @State private var displayScore: Score?
    @State private var document: LayoutDocument?
    @State private var referenceNotes: [ReferenceNote] = []
    @State private var playedNoteIDs: Set<NoteID> = []
    /// 上一次已居中滚动到的 system 索引；只在光标「跨 system」时才滚，
    /// 避免同一行内每拍都重复触发滚动动画造成抖动。-1 = 尚未定位。
    @State private var lastScrolledSystem: Int = -1
    /// G7 简谱叠加开关（ADR-0009 Stage B）：不持久化，每次进练习室默认关。
    @State private var showNumbered = false

    /// 纸张 #FBF8F2（S11 真值 §4，与 PracticeRoomView.s11Paper 同值；那边 fileprivate）。
    /// 引擎把页面背景写死为纯白且不许改包源码，故用 multiply 叠染（白×纸色=纸色，
    /// 黑符头×纸色≈黑），谱面与纸张卡颜色一致。
    private static let paper = Color(red: 0xFB / 255, green: 0xF8 / 255, blue: 0xF2 / 255)

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    content
                }
                .onChange(of: cursor) { _, new in
                    scroll(to: new, proxy: scrollProxy)
                    updatePlayedNoteIDs(upTo: new)
                }
                // iOS 26 ScrollView 默认会给滚动边缘加自动渐隐效果（内容淡入深色底层），
                // 在纸卡内表现为谱面上下两道灰色阴影带——练习室谱面不需要，全部关掉。
                .modifier(ScrollEdgeEffectHiddenAll())
                .onAppear { rebuild(width: proxy.size.width) }
                .onChange(of: proxy.size.width) { _, w in rebuild(width: w) }
                .onChange(of: measuresPerLine) { _, _ in rebuild(width: proxy.size.width) }
                // 简谱开关：挂在 ScrollView（滚动容器）上而非内容上，相对
                // GeometryReader 固定、不随滚动跳动。独立视图，不受 overlay
                // 的 allowsHitTesting(false) 影响。
                .overlay(alignment: .topTrailing) {
                    NocturneChip(title: "简谱", isSelected: showNumbered) {
                        showNumbered.toggle()
                    }
                    .padding(.trailing, 12)
                    .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let document, let displayScore {
            // 底层锚点列决定整页滚动高度：按真实文档几何用 VStack(spacing: 0) 顺序堆叠。
            // 每个锚点的「布局位置」严格等于其 system 的文档 y（首行 y=0，其后由前序高度累加），
            // 这样 ScrollViewReader 才能滚到正确位置（不能用 .offset——只动渲染不动布局）。
            // ScoreView 同尺寸整体叠加在顶层，按同一 document 把各 system 画在相同 y，与锚点天然对齐。
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(Array(document.systems.enumerated()), id: \.offset) { idx, sys in
                        Color.clear
                            .frame(width: document.size.width, height: anchorSlotHeight(idx, in: document))
                            .id(idx)
                    }
                }
                ScoreView(
                    document: document,
                    score: displayScore,
                    options: options,
                    selection: selectionForPlayedNotes(),
                    voiceColors: voiceColorsForPlayedNotes(),
                    playbackCursor: cursor,
                    playbackCursorColor: Color.amber.opacity(0.25),
                )
                // 引擎页面背景硬编码纯白（包红线：不改包源码）。colorMultiply 确定性叠染：
                // 白底×纸色=纸色、符头墨黑×纸色≈墨黑，谱面与纸张卡颜色一致、无白块错色。
                .colorMultiply(Self.paper)
                // P4 纸内谱头：与 ScoreView 同处 topLeading ZStack，坐标即文档坐标；不挡手势。
                scoreHeaderOverlay(for: displayScore)
                // G7 简谱叠加：与 ScoreView 同处一个 topLeading ZStack，标注坐标即
                // 文档坐标（文档 (0,0)=ScoreView 左上），与符头天然对齐；自带
                // allowsHitTesting(false)，不挡谱面手势。
                if showNumbered {
                    NumberedNotationOverlayView(
                        annotations: NumberedAnnotationBuilder.build(score: displayScore, document: document),
                        sp: document.metrics.sp)
                }
                // P4 纸内页脚：bottomTrailing，页码 + 来源
                scoreFooterOverlay(for: displayScore, document: document)
            }
            .padding(.vertical, 8)
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
        }
    }

    private var options: ScoreViewOptions {
        Self.makeOptions(staffSize: 28)
    }

    private static func makeOptions(staffSize: CGFloat) -> ScoreViewOptions {
        // honor：我们注入的 lineBreak 必须生效（自动档时已清空，靠宽度换行）。
        // break 徽章关掉：换行是 App 层注入的显示偏好，不是原稿标记，画 ↩ 提示标是噪音。
        var options = ScoreViewOptions(staffSize: staffSize, wrapToViewWidth: true, breakPolicy: .honor)
        options.breakIndicatorVisibility = .none
        return options
    }

    // MARK: - P4 纸内谱头叠加

    @ViewBuilder
    private func scoreHeaderOverlay(for score: Score?) -> some View {
        if let score {
            let totalStaves = score.parts.values.reduce(0) { $0 + $1.staves.count }
            let isTwoHand = totalStaves >= 2
            HStack(alignment: .center, spacing: 8) {
                Text(headerLeftText)
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundStyle(Color.textMuted)
                Spacer()
                if let term = Self.tempoTerm(for: referenceTempo) {
                    Text("♩=\(referenceTempo) \(term)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.amber.opacity(0.1), in: Capsule())
                }
                if let note = leftHandNote, !note.isEmpty {
                    Text("左手：\(note)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
                }
                if isTwoHand {
                    Text("双手")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.amber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.amber.opacity(0.15), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.amber.opacity(0.3), lineWidth: 1))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        } else {
            Color.clear
        }
    }

    private var headerLeftText: String {
        var text = "\(pieceBook) 第\(pieceNumber)条"
        if let opusTag, !opusTag.isEmpty {
            text += " · Op.\(opusTag)"
        }
        return text
    }

    private static func tempoTerm(for bpm: Int) -> String? {
        switch bpm {
        case ..<40:  return "广板"
        case 40..<70: return "慢板"
        case 70..<100: return "行板"
        case 100..<130: return "快板"
        case 130..<170: return "急板"
        default: return bpm > 0 ? "极快" : nil
        }
    }

    // MARK: - P4 纸内页脚叠加

    @ViewBuilder
    private func scoreFooterOverlay(for score: Score?, document: LayoutDocument?) -> some View {
        if let document {
            let totalPages = max(1, document.systems.count)
            HStack(alignment: .center, spacing: 8) {
                Text("\(pieceBook) 第\(pieceNumber)条")
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .foregroundStyle(Color.textMuted)
                Spacer()
                if let notice = copyrightNotice, !notice.isEmpty {
                    Text(notice)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
                }
                Text("共 \(totalPages) 页")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        } else {
            Color.clear
        }
    }

    /// 第 idx 个锚点槽位的高度：从本 system 的 origin 到下一个 system 的 origin；
    /// 最后一个取到文档底。这样各锚点累计 y 严格等于各 system 的文档 origin
    /// （system 间的垂直间距也要算进去——sys.size.height 只覆盖谱面本体，不含 system 间距）。
    private func anchorSlotHeight(_ idx: Int, in document: LayoutDocument) -> CGFloat {
        let originY = document.systems[idx].origin.y
        if idx + 1 < document.systems.count {
            return max(1, document.systems[idx + 1].origin.y - originY)
        }
        return max(1, document.size.height - originY)
    }

    private func rebuild(width rawWidth: CGFloat) {
        // 直接调 LayoutEngine.layout（而非只走 ScoreView）前必须确保已安装
        // CoreText 字体度量，否则 DEBUG 下命中 Stub provider 断言。包官方入口。
        _ = SheetMusicLayoutApple.install
        let width = max(rawWidth, options.staffSize * 4)
        let laid = ScoreLineBreaker.apply(to: score, measuresPerLine: measuresPerLine)
        displayScore = laid
        if measuresPerLine >= 2 {
            // 固定档：可用宽度放不下 N 小节时引擎会按宽度提前折行、每行不齐，
            // 用 fittingStaffSize 二分出能放下「每行恰 N 小节」的最大字号；
            // 无满足解回退基础字号（诚实不生效，不错乱）。
            let fitted = ScoreLineBreaker.fittingStaffSize(
                score: laid,
                perLine: measuresPerLine,
                availableWidth: width
            ) { size in
                Self.makeOptions(staffSize: size)
            }
            document = fitted.document
        } else {
            document = LayoutEngine.layout(
                score: laid,
                options: Self.makeOptions(staffSize: 28),
                availableWidth: width)
        }
        // 换行/档位改变后 system 索引整体重算，强制下一次光标变化重新定位。
        lastScrolledSystem = -1
        rebuildReferenceNotes()
    }

    private func rebuildReferenceNotes() {
        guard let displayScore = displayScore else { return }
        referenceNotes = ScoreReferenceNotes.extract(score: displayScore).notes
    }

    private func updatePlayedNoteIDs(upTo cursor: ScoreCursor?) {
        guard let cursor = cursor,
              let displayScore = displayScore,
              case .beat(let measureIndex, let tickInMeasure) = cursor else {
            playedNoteIDs = []
            return
        }
        let currentBeat = Double(tickInMeasure) / Double(displayScore.division)
        playedNoteIDs = Set(referenceNotes.filter { note in
            if note.measureIndex < measureIndex { return true }
            if note.measureIndex == measureIndex && note.beatInMeasure <= currentBeat { return true }
            return false
        }.compactMap(\.noteID))
    }

    private func selectionForPlayedNotes() -> ScoreSelection {
        guard !playedNoteIDs.isEmpty else { return .none }
        return .multi(Set(playedNoteIDs.map(ScoreItemID.note)))
    }

    private func voiceColorsForPlayedNotes() -> [Int: Color] {
        // P3 hand 模式 + P2 已弹着色合并：非激活 hand 整组变灰，激活 hand 内已弹音符琥珀。
        var voiceHandMap: [Int: Hand] = [:]
        for note in referenceNotes {
            guard let voiceIndex = note.noteID?.voiceIndex else { continue }
            voiceHandMap[voiceIndex] = note.hand
        }
        var map: [Int: Color] = [:]
        for (voiceIndex, hand) in voiceHandMap {
            let handActive: Bool = switch handMode {
            case .both: true
            case .right: hand == .right
            case .left: hand == .left
            }
            if !handActive {
                map[voiceIndex] = Color.gray.opacity(0.3)
            } else if playedNoteIDs.contains(where: { $0.voiceIndex == voiceIndex }) {
                map[voiceIndex] = Color.amber
            }
        }
        return map
    }

    /// 「除最后一行外每行恰 perLine 小节」判定（二分目标；行数为空或某行为 0 视为不满足）。
    static func breaksRespected(_ doc: LayoutDocument, perLine: Int) -> Bool {
        let counts = doc.systems.map(\.measures.count)
        guard !counts.isEmpty, counts.allSatisfy({ $0 > 0 }) else { return false }
        for (i, c) in counts.enumerated() where i < counts.count - 1 {
            if c != perLine { return false }
        }
        return true
    }

    /// 光标变化 → 找它所在的 system；仅当跨 system 时居中滚动。
    private func scroll(to cursor: ScoreCursor?, proxy: ScrollViewProxy) {
        guard let cursor, let document, let displayScore,
              let frame = document.cursorFrame(for: cursor, in: displayScore) else { return }
        let y = frame.minY
        let idx = document.systems.firstIndex { sys in
            y >= sys.origin.y - 1 && y < sys.origin.y + sys.size.height
        } ?? 0
        guard idx != lastScrolledSystem else { return }
        lastScrolledSystem = idx
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(idx, anchor: .center)
        }
    }
}
