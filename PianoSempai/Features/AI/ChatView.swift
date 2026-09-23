import SwiftData
import SwiftUI

// M7.1 Stage B2 · S18 问 Neko 对话（视觉真值：docs/design-reference/screens/S18-chat/spec.md，
// Stitch 390pt 稿 —— 带 grab handle 的 sheet 式全屏页）。
//
// 真值要点：我方气泡深琥珀灰底浅字（非琥珀实底）、证据引用 chips 收在 Neko 气泡内部、
// 输入框聚焦转琥珀边、发送钮 32×32 圆角 12pt 方形、脚注「不会替你解锁过关」。
// 附件/摄像机钮与视频气泡在真值里存在但功能 blocked（S18b / backlog V 系列）→ 本 Stage 不画死元素。
//
// 边界（红线 3）：AI 输出只渲染、只作建议。回答里若出现动作建议，只渲染为文字，
// 本 Stage 不提供任何执行入口——不改课程/判分/设置状态。M7.1 纯文字：无附件/视频/TTS。
// 无证据/低置信如实呈现（ContextBuilder.degradations 直显），不编造（红线 2）。
// 一个视图只挂一个呈现层级：本页不再弹任何 sheet/cover，错误重试在原位完成。

struct ChatView: View {
    let mode: ChatMode
    @Environment(\.dismiss) private var dismiss
    @State private var store: ChatStore
    @State private var draft = ""
    /// 输入框聚焦态（真值：focus-within 输入框边框转琥珀 70%）。
    /// 必须走 @FocusState：.focused() 修饰符在 TextField 上不可靠。
    @FocusState private var inputFocused: Bool

    init(mode: ChatMode, context: ModelContext) {
        self.mode = mode
        _store = State(initialValue: ChatStore(mode: mode, context: context))
    }

    /// 有空文本 + 链路可用 + 不在发送中才允许发送（发送中禁用防重复）
    private var canSend: Bool {
        store.hasAvailableProvider
            && !store.isSending
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            contextBar
            messageArea
            footnote
            inputBar
        }
        .background(Color.canvas.ignoresSafeArea())
        .onAppear { store.refreshAvailability() }
    }

    // MARK: 顶部（sheet 式：grab handle + 头像/标题 + ✕）

    private var header: some View {
        VStack(spacing: 0) {
            // grab handle：40×4 全圆角 #443E3A，居中，上 12 / 下 12（sheet 式全屏页标识）
            HStack {
                Spacer(minLength: 0)
                Capsule()
                    .fill(Color.s18GrabHandle)
                    .frame(width: 40, height: 4)
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .padding(.bottom, 12)

            // 标题行：左簇（猫脸头像 + serif 标题）｜右（✕ dismiss）
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    nekoAvatar
                    Text(store.headerTitle)
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.canvas.opacity(0.95)
            }
            .overlay(alignment: .bottom) {
                // 底边发丝线 #332D29 60%
                Rectangle()
                    .fill(Color.border.opacity(0.6))
                    .frame(height: 1)
            }
            .ignoresSafeArea(edges: .top)
        )
    }

    /// 头像：32×32 正圆，琥珀 15% 底 + 琥珀 40% 边，猫脸 18pt 琥珀（真值 §3.1）
    private var nekoAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.amber.opacity(0.15))
            Image(systemName: "cat")
                .font(.system(size: 18))
                .foregroundStyle(Color.amber)
        }
        .frame(width: 32, height: 32)
        .overlay(Circle().strokeBorder(Color.amber.opacity(0.4), lineWidth: 1))
    }

    // MARK: 上下文条（本次回答基于哪次练习；降级如实提示）

    private var contextBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 上下文 chip：前置 6×6 琥珀呼吸点（真值 animate-pulse，替代图标）；
            // 文案仍取 store 真实文本，不改来源
            HStack(spacing: 6) {
                ChatPulseDot()
                Text(store.contextChipText)
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))

            // 该 take 无判分结果等降级：明说只带了部分数据，不假装完整
            ForEach(store.contextDegradations, id: \.self) { line in
                Text(line)
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: 消息流

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    // 无可用服务商 = 顶部空态卡（历史消息照常显示，不因链路不可用就藏起来）
                    if !store.hasAvailableProvider {
                        noProviderCard
                    } else if store.messages.isEmpty && !store.isSending {
                        firstRunHint
                    }
                    ForEach(store.messages) { message in
                        messageRow(message)
                    }
                    if store.isSending {
                        thinkingBubble
                    }
                    if let failure = store.failure {
                        failureCard(failure)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.count) { scrollToBottom(proxy) }
            .onChange(of: store.isSending) { scrollToBottom(proxy) }
            .onChange(of: store.failure != nil) { scrollToBottom(proxy) }
        }
    }

    private static let bottomAnchor = "chat-bottom"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        if message.isUser {
            // 我的气泡：右对齐深琥珀灰底 + 描边、浅字，最大宽 85%，右上角 2pt（真值 §3.2）
            GeometryReader { proxy in
                HStack {
                    Spacer(minLength: 0)
                    Text(message.text)
                        .font(.bodyMd)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.s18UserBubble, in: userBubbleShape)
                        .overlay(userBubbleShape.strokeBorder(Color.s18UserBubbleBorder, lineWidth: 1))
                        .frame(maxWidth: proxy.size.width * 0.85, alignment: .trailing)
                }
            }
        } else {
            // Neko 气泡：左对齐，最大宽 92%；正文 + 证据 chips + 服务商行都在同一个气泡内
            GeometryReader { proxy in
                nekoBubble(message)
                    .frame(maxWidth: proxy.size.width * 0.92, alignment: .leading)
            }
        }
    }

    /// 我方气泡形：圆角 16pt、右上角 2pt（真值 rounded-2xl + rounded-tr-sm）
    private var userBubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 16, bottomLeading: 16, bottomTrailing: 16, topTrailing: 2
            ),
            style: .continuous
        )
    }

    /// Neko 气泡形：圆角 16pt、左上角 2pt（真值 rounded-2xl + rounded-tl-sm）
    private var nekoBubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 2, bottomLeading: 16, bottomTrailing: 16, topTrailing: 16
            ),
            style: .continuous
        )
    }

    /// Neko 气泡：单个卡 = 署名簇 + 正文 + 证据引用 chips + 服务商行（真值：chips 在气泡内部）
    private func nekoBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "cat")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.amber)
                Text("Neko")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
            Text(message.text)
                .font(.bodyMd)
                .foregroundStyle(Color.textPrimary)
                .leading(22.4, fontSize: 14) // 真值行高 1.6
                .fixedSize(horizontal: false, vertical: true)
            evidenceChips(message)
            providerLine(message)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.card, in: nekoBubbleShape)
        .overlay(nekoBubbleShape.strokeBorder(Color.border, lineWidth: 1))
    }

    /// 证据引用 chips：只显示 evidence 里真实存在的字段（deviationMs 为 nil 就不显示偏差）。
    /// 真值：收在气泡内正文下方、flex-wrap gap6；单 chip bgDark 底 + 发丝边、r6、px8 py2、11pt。
    @ViewBuilder
    private func evidenceChips(_ message: ChatMessage) -> some View {
        let refs = message.evidenceRefs
        if !refs.isEmpty {
            WrapChipRow(spacing: 6, rowSpacing: 6) {
                ForEach(refs, id: \.id) { ref in
                    HStack(spacing: 4) {
                        Text(EvidenceChipText.measure(ref))
                            .font(.labelSm)
                            .foregroundStyle(Color.textMuted)
                        if let deviation = EvidenceChipText.deviation(ref) {
                            Text(deviation)
                                .font(.labelMono(11))
                                .foregroundStyle(Color.amber)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.canvas, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.border, lineWidth: 1))
                }
            }
        }
    }

    /// 命中「服务商 · 模型」：极弱文字，透明可溯（S18b 服务商披露同源，不写死）
    @ViewBuilder
    private func providerLine(_ message: ChatMessage) -> some View {
        if !message.providerModel.isEmpty {
            Text(message.providerModel)
                .font(.labelMono(10))
                .foregroundStyle(Color.textMuted.opacity(0.55))
                .monospacedDigit()
        }
    }

    /// 发送中：Neko 侧三点呼吸思考态（输入区同时禁用发送，防重复）
    private var thinkingBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "cat")
                .font(.system(size: 12))
                .foregroundStyle(Color.amber)
            Text("Neko 正在想…")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
            TimelineView(.animation) { timeline in
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.textMuted)
                            .frame(width: 5, height: 5)
                            .opacity(dotOpacity(timeline.date.timeIntervalSinceReferenceDate, index: index))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.card, in: nekoBubbleShape)
        .overlay(nekoBubbleShape.strokeBorder(Color.border, lineWidth: 1))
    }

    /// 三点呼吸相位（本地算，不引外部动画依赖）
    private func dotOpacity(_ t: TimeInterval, index: Int) -> Double {
        let wave = sin((t * 2.4) - Double(index) * 0.6)
        return 0.3 + 0.55 * max(0, wave)
    }

    // MARK: 特殊态

    /// 未配置任何可用服务商：空态卡 + 引导去「设置 → AI 助教」，输入区禁用。
    /// 只作顶部卡：历史消息照常在下方显示（链路暂时不可用不该抹掉过去的对话）。
    private var noProviderCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "cat")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.amber)
                    Text("还没有可用的 AI 服务商")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                }
                Text("Neko 现在没有可用的服务商，回答不了问题。去「设置 → AI 助教 · 服务商链」添加服务商并填入 Key，链上任一可用就能提问。")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    dismiss()
                } label: {
                    Text("关闭")
                        .font(.titleMd)
                        .foregroundStyle(Color.amber)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(Color.amber.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 首次进入（链路可用）：一句中性引导，不承诺能力边界之外的事
    private var firstRunHint: some View {
        Text("问我任何练琴问题：某个小节总卡、转指怎么练、速度稳不住……我会引用你本机的练习数据回答；没有证据的地方我会直说。")
            .font(.bodySm)
            .foregroundStyle(Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
    }

    /// 全链失败：错误气泡展示各商·各模型失败原因，消息保留可重试（不吞错）
    private func failureCard(_ failure: ProviderChainFailure) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.danger)
                Text("这次没连上，没有回答")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
            }
            Text(failure.summary)
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if !failure.attempts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(failure.attempts.enumerated()), id: \.offset) { _, attempt in
                        Text("\(attempt.providerDisplayName)·\(attempt.modelId)：\(attempt.errorSummary)")
                            .font(.labelMono(11))
                            .foregroundStyle(Color.textMuted)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 12) {
                Button {
                    store.retry()
                } label: {
                    Text("重试")
                        .frame(width: 88)
                }
                .buttonStyle(SecondaryButtonStyle(cornerRadius: 8))
                Button {
                    dismiss()
                } label: {
                    Text("关闭")
                }
                .buttonStyle(GhostButtonStyle())
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.danger.opacity(0.4), lineWidth: 1))
    }

    // MARK: 常驻脚注 + 输入栏

    /// Neko 只有建议权（红线 3，S18 spec：常驻脚注，真值逐字文案）
    private var footnote: some View {
        Text("Neko 只有建议权，不会替你解锁过关")
            .font(.labelSm)
            .foregroundStyle(Color.textMuted.opacity(0.75))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("问问这一段…", text: $draft, axis: .vertical)
                .font(.bodyMd)
                .foregroundStyle(Color.textPrimary)
                .tint(Color.amber)
                .lineLimit(1...4)
                .focused($inputFocused)
                .disabled(!store.hasAvailableProvider)
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canSend ? Color.canvas : Color.textMuted)
                    .frame(width: 32, height: 32)
                    .background(
                        canSend ? Color.amber : Color.borderInput,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("发送")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(inputFocused ? Color.amber.opacity(0.7) : Color.border, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background(alignment: .top) {
            // 容器顶边 #332D29 70%
            Rectangle()
                .fill(Color.border.opacity(0.7))
                .frame(height: 1)
        }
    }

    private func send() {
        store.send(text: draft)
        draft = ""
    }
}

// MARK: - 呼吸圆点（上下文 chip 前置；真值 animate-pulse）

/// 6×6 琥珀点持续呼吸（真值：w-1.5 h-1.5 bg-amberAccent animate-pulse）
private struct ChatPulseDot: View {
    @State private var lit = false

    var body: some View {
        Circle()
            .fill(Color.amber)
            .frame(width: 6, height: 6)
            .opacity(lit ? 1 : 0.45)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    lit = true
                }
            }
    }
}

// MARK: - 换行 chip 行（证据引用用；iOS 16+ Layout）

/// 简易换行布局：子视图按序排，超出宽度换行；每个子视图保持自身理想尺寸（胶囊不被拉宽）。
private struct WrapChipLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var contentWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                contentWidth = max(contentWidth, x - spacing)
                x = 0
                y += lineHeight + rowSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        contentWidth = max(contentWidth, x - spacing)
        // 收在气泡内：宽度按实际内容算（不占满可用宽），否则气泡会被 chip 行撑成整宽
        return CGSize(width: min(maxWidth, max(contentWidth, 0)), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + rowSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// 换行 chip 行的 View 包装（Layout 的 callAsFunction 只接内容闭包，配置参数经本类传入）
private struct WrapChipRow<Content: View>: View {
    private let layout: WrapChipLayout
    private let content: Content

    init(spacing: CGFloat = 6, rowSpacing: CGFloat = 6, @ViewBuilder content: () -> Content) {
        self.layout = WrapChipLayout(spacing: spacing, rowSpacing: rowSpacing)
        self.content = content()
    }

    var body: some View {
        layout { content }
    }
}

// MARK: - S18 屏内私有色（不写入 Assets / 不改全局 token）

fileprivate extension Color {
    /// hex → sRGB（S18 真值局部色专用）
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// 顶部 grab handle #443E3A（真值内联色；token 无此色）
    static let s18GrabHandle = Color(hex: 0x443E3A)
    /// 我方气泡底 #2E261F（真值 userBubbleBg）
    static let s18UserBubble = Color(hex: 0x2E261F)
    /// 我方气泡描边 #4A3B2C（真值 userBubbleBorder）
    static let s18UserBubbleBorder = Color(hex: 0x4A3B2C)
}

// MARK: - 预览夹具（内存容器；不打网络、不碰 Keychain）

#if DEBUG
private enum ChatPreviewContainer {
    static func make() -> ModelContainer {
        try! ModelContainer(
            for: Take.self, TakeAnalysis.self, ChatThread.self, ChatMessage.self, AIProvider.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// 游离 take（不入库）：ChatStore 对 take 只读，预览不需要它真的落库
    static func sampleTake() -> Take {
        Take(
            startedAt: Date(timeIntervalSinceNow: -5400),
            durationSec: 134,
            taskType: "main",
            hasMidi: true,
            measureFrom: 12,
            measureTo: 20,
            tempoAvg: 72,
            noteCount: 132,
            wrongNoteCount: 2,
            title: "拜厄 45"
        )
    }
}

/// 预览宿主：自备内存容器（ChatView 不自己造数据）
private struct ChatPreviewScene: View {
    let mode: ChatMode
    @State private var container = ChatPreviewContainer.make()

    var body: some View {
        ChatView(mode: mode, context: container.mainContext)
            .modelContainer(container)
    }
}

#Preview {
    ChatPreviewScene(mode: .freeform)
        .preferredColorScheme(.dark)
}

#Preview {
    ChatPreviewScene(mode: .take(ChatPreviewContainer.sampleTake(), analysis: nil, pieceTitle: "拜厄 45"))
        .preferredColorScheme(.dark)
}
#endif
