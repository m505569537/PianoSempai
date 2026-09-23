import SheetMusicCore
import SheetMusicLayout
import SheetMusicLayoutApple
import SheetMusicUI
import SwiftUI

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

    /// 转换后（已重排换行）的谱，供 ScoreView 与光标定位共用。
    @State private var displayScore: Score?
    @State private var document: LayoutDocument?
    /// 上一次已居中滚动到的 system 索引；只在光标「跨 system」时才滚，
    /// 避免同一行内每拍都重复触发滚动动画造成抖动。-1 = 尚未定位。
    @State private var lastScrolledSystem: Int = -1

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    content
                }
                .onChange(of: cursor) { _, new in
                    scroll(to: new, proxy: scrollProxy)
                }
                .onAppear { rebuild(width: proxy.size.width) }
                .onChange(of: proxy.size.width) { _, w in rebuild(width: w) }
                .onChange(of: measuresPerLine) { _, _ in rebuild(width: proxy.size.width) }
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
                    playbackCursor: cursor,
                    playbackCursorColor: Color.amber.opacity(0.25),
                )
            }
            .padding(.vertical, 8)
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
        }
    }

    private var options: ScoreViewOptions {
        // honor：我们注入的 lineBreak 必须生效（自动档时已清空，靠宽度换行）。
        ScoreViewOptions(wrapToViewWidth: true, breakPolicy: .honor)
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
        document = LayoutEngine.layout(score: laid, options: options, availableWidth: width)
        // 换行/档位改变后 system 索引整体重算，强制下一次光标变化重新定位。
        lastScrolledSystem = -1
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
