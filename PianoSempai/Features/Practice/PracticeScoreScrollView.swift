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
    /// 示范播放中：此时光标是「示范走到哪」，不是「用户弹到哪」，
    /// 不能据此把音符标成琥珀「已弹」（用户反馈：听示范时音符自己变色）。
    let isDemoPlaying: Bool

    /// 转换后（已重排换行）的谱，供 ScoreView 与光标定位共用。
    @State private var displayScore: Score?
    @State private var document: LayoutDocument?
    @State private var referenceNotes: [ReferenceNote] = []
    @State private var playedNoteIDs: Set<NoteID> = []
    /// 上一次已居中滚动到的 system 索引；只在光标「跨 system」时才滚，
    /// 避免同一行内每拍都重复触发滚动动画造成抖动。-1 = 尚未定位。
    @State private var lastScrolledSystem: Int = -1
    /// G7 简谱叠加开关（ADR-0009 Stage B）：状态由练习室持有（工具条在纸外，不压谱面）。
    @Binding var showNumbered: Bool
    /// G11 指法叠加开关（ADR-0014 Stage B）：同上。
    @Binding var showFingerings: Bool

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
                // 示范开始/结束要立刻重算：否则停在示范期间的点亮态，退出示范后仍残留
                .onChange(of: isDemoPlaying) { _, _ in
                    updatePlayedNoteIDs(upTo: cursor)
                }
                // iOS 26 ScrollView 默认会给滚动边缘加自动渐隐效果（内容淡入深色底层），
                // 在纸卡内表现为谱面上下两道灰色阴影带——练习室谱面不需要，全部关掉。
                .modifier(ScrollEdgeEffectHiddenAll())
                .onAppear { rebuild(width: proxy.size.width) }
                .onChange(of: proxy.size.width) { _, w in rebuild(width: w) }
                .onChange(of: measuresPerLine) { _, _ in rebuild(width: proxy.size.width) }
                // 简谱/指法开关已移到纸卡上方的工具条（见 PracticeRoomView.scoreToolbar）：
                // 贴在谱面内部必然盖住小节内容，实测会挡住第 3–4 小节的音符。
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
                // 纸内谱头已移除（2026-11-17）：曲目编号/速度术语/双手标记会压在第一行谱上，
                // 而这些信息在顶栏副行已有；手机屏幕小，位置全部让给谱面。
                // G7 简谱叠加：与 ScoreView 同处一个 topLeading ZStack，标注坐标即
                // 文档坐标（文档 (0,0)=ScoreView 左上），与符头天然对齐；自带
                // allowsHitTesting(false)，不挡谱面手势。
                if showNumbered {
                    NumberedNotationOverlayView(
                        annotations: NumberedAnnotationBuilder.build(score: displayScore, document: document),
                        sp: document.metrics.sp)
                }
                // G11 指法叠加：符头下方，与简谱上方天然零冲突（ADR-0014 决策三）。
                if showFingerings {
                    FingeringsOverlayView(
                        annotations: FingeringAnnotationBuilder.build(score: displayScore, document: document),
                        sp: document.metrics.sp)
                }
                // 纸内页脚同上去掉：「共 N 行」属于噪音且会压最后一行谱。
            }
            // 卡片内侧留白：谱号/小节号不要贴死纸边（外侧 12pt 由练习室给）
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
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
        // 引擎默认 systemGap 40pt，手机竖屏下显得空；28 更紧凑但仍能一眼分开两行
        options.systemGap = 28
        return options
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

    /// 让每个谱表的声部索引在 part 内唯一。
    ///
    /// 引擎的 `voiceColors` 只有 voiceIndex 一个维度（没有 staff），双谱表如果两个谱表
    /// 都用 0 号声部，着色会互相覆盖——表现就是「点了右手/左手没有任何反应」。
    /// 做法：给第 N 个谱表前面塞 N 个空声部，把真实声部顶到唯一索引（空声部没有元素，不渲染内容）。
    private static func uniquifyingVoiceIndices(_ score: Score) -> Score {
        var score = score
        for partIndex in score.parts.indices {
            score.parts.updateValue(at: partIndex) { part in
                for staffIndex in part.staves.indices where staffIndex > 0 {
                    part.staves.updateValue(at: staffIndex) { staff in
                        // 声部挂在每个 Measure 上（Staff 没有 voices 字段），逐小节插入
                        for measureIndex in staff.measures.indices {
                            for _ in 0..<staffIndex {
                                staff.measures[measureIndex].voices.insert(Voice(elements: []), at: 0)
                            }
                        }
                    }
                }
            }
        }
        return score
    }

    /// 清空 part 名/乐器名：布局引擎按 longName → trackName 的顺序取显示名并为它留白。
    private static func strippingPartNames(_ score: Score) -> Score {
        var score = score
        for index in score.parts.indices {
            // updateValue 的闭包是原地修改语义（返回 Void），不要 return
            score.parts.updateValue(at: index) { part in
                part.instrument.longName = nil
                part.instrument.shortName = nil
                part.instrument.trackName = nil
                part.trackName = nil
            }
        }
        return score
    }

    private func rebuild(width rawWidth: CGFloat) {
        // 直接调 LayoutEngine.layout（而非只走 ScoreView）前必须确保已安装
        // CoreText 字体度量，否则 DEBUG 下命中 Stub provider 断言。包官方入口。
        _ = SheetMusicLayoutApple.install
        let width = max(rawWidth, options.staffSize * 4)
        var laid = ScoreLineBreaker.apply(to: score, measuresPerLine: measuresPerLine)
        // 手机竖屏宽度紧张：part 名（`グランドピアノ` / `Pno.`）会让引擎在每行左侧
        // 预留一列文本宽度，单人练习没有任何信息量，直接清掉把宽度全给谱面。
        laid = Self.strippingPartNames(laid)
        laid = Self.uniquifyingVoiceIndices(laid)
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
        // 示范播放时光标属于播放器，不代表用户弹过 → 不点亮任何音符
        guard !isDemoPlaying else {
            playedNoteIDs = []
            return
        }
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
        var ids = playedNoteIDs
        // 分手：引擎的着色只作用于「选中项」（ScoreLayerBuilder 只遍历 selectedIDs），
        // 所以必须把非激活手的全部音符显式放进选中集，否则点右手/左手在画面上毫无变化。
        if handMode != .both {
            for note in referenceNotes {
                guard let noteID = note.noteID else { continue }
                let isActive = (handMode == .right) ? (note.hand == .right) : (note.hand == .left)
                if !isActive { ids.insert(noteID) }
            }
        }
        guard !ids.isEmpty else { return .none }
        return .multi(Set(ids.map(ScoreItemID.note)))
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
