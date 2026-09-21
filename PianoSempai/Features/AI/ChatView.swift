import SwiftData
import SwiftUI

// M7.1 Stage B2 · S18 问 Neko 对话（布局真值：docs/design-reference/screens/S18-chat/spec.md）。
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

    // MARK: 顶部（X 关闭 + 居中 serif 标题）

    private var header: some View {
        ZStack {
            Text(store.headerTitle)
                .font(.headlineSm)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.textBody)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(Color.canvas)
    }

    // MARK: 上下文条（本次回答基于哪次练习；降级如实提示）

    private var contextBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: store.hasTakeContext ? "music.note" : "bubble.left")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
                Text(store.contextChipText)
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.surface, in: Capsule())
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
        .padding(.horizontal, 20)
        .padding(.top, 4)
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
                .padding(.horizontal, 20)
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
            // 我的气泡：右对齐琥珀底深字，最大宽 78%，尾角小（S18 spec 视觉规范）
            GeometryReader { proxy in
                HStack {
                    Spacer(minLength: 0)
                    Text(message.text)
                        .font(.bodyMd)
                        .foregroundStyle(Color.canvas)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Color.amber,
                            in: UnevenRoundedRectangle(
                                cornerRadii: RectangleCornerRadii(
                                    topLeading: 12, bottomLeading: 12, bottomTrailing: 4, topTrailing: 12
                                ),
                                style: .continuous
                            )
                        )
                        .frame(maxWidth: proxy.size.width * 0.78, alignment: .trailing)
                }
            }
        } else {
            // Neko 气泡：左对齐 card 表面 + 发丝边，带猫标识
            VStack(alignment: .leading, spacing: 6) {
                nekoBubble(message)
                evidenceChips(message)
                providerLine(message)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func nekoBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .foregroundStyle(Color.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
    }

    /// 证据引用 chips：只显示 evidence 里真实存在的字段（deviationMs 为 nil 就不显示偏差）
    @ViewBuilder
    private func evidenceChips(_ message: ChatMessage) -> some View {
        let refs = message.evidenceRefs
        if !refs.isEmpty {
            WrapChipRow(spacing: 6, rowSpacing: 6) {
                ForEach(refs) { ref in
                    HStack(spacing: 4) {
                        Text(EvidenceChipText.measure(ref))
                            .font(.labelSm)
                            .foregroundStyle(Color.textBody)
                        if let deviation = EvidenceChipText.deviation(ref) {
                            Text(deviation)
                                .font(.labelMono(11))
                                .foregroundStyle(Color.amber)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
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
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
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
            .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
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

    /// Neko 只有建议权（红线 3，S18 spec：常驻脚注）
    private var footnote: some View {
        Text("Neko 只有建议权，过关由你的弹奏数据判定。")
            .font(.labelSm)
            .foregroundStyle(Color.textMuted.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.bottom, 2)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("说说你想练什么…", text: $draft, axis: .vertical)
                .font(.bodyMd)
                .foregroundStyle(Color.textPrimary)
                .tint(Color.amber)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderInput, lineWidth: 1))
                .disabled(!store.hasAvailableProvider)
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canSend ? Color.canvas : Color.textMuted)
                    .frame(width: 40, height: 40)
                    .background(canSend ? Color.amber : Color.borderInput, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("发送")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private func send() {
        store.send(text: draft)
        draft = ""
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
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + rowSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
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
