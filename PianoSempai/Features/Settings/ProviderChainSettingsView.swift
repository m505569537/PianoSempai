import SwiftData
import SwiftUI

// MARK: - S25 AI 助教 · 服务商链（多服务商 × 每商多模型的有序故障转移链）
// 布局真值：docs/design-reference/screens/S25-apikey/spec.md（2026-09-21 重写版）。
// 单 sheet 路由（沿用 LibraryView 的教训：一个视图只可靠呈现一个 .sheet）。

struct ProviderChainSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \AIProvider.sortOrder) private var providers: [AIProvider]

    /// 常驻链状态（诊断 / 粘性 / key 存在性；brief §1）
    @State private var runtime = ProviderChainRuntime()
    @State private var activeSheet: ActiveSheet?
    @State private var showAllDiagnostics = false

    /// 单一 sheet 路由：详情 / 添加
    private enum ActiveSheet: Identifiable {
        case detail(provider: AIProvider, id: String)
        case add

        var id: String {
            switch self {
            // id 在入栈时取快照：删除服务商后不再触碰已删对象的属性
            case let .detail(_, id): "detail-\(id)"
            case .add: "add"
            }
        }
    }

    private func openDetail(_ provider: AIProvider) {
        activeSheet = .detail(provider: provider, id: provider.providerId)
    }

    // MARK: 拖拽排序（行高固定 → 落位即下标；pitch 恒定，纯函数算 targetIndex）

    @State private var displayOrder: [AIProvider]?
    @State private var draggingProviderId: String?
    @State private var dragStartIndex = 0
    @State private var dragTranslation: CGFloat = 0

    private let rowHeight: CGFloat = 72
    private let rowSpacing: CGFloat = 10
    private var pitch: CGFloat { rowHeight + rowSpacing }

    private var orderedProviders: [AIProvider] { ProviderChainLogic.ordered(providers) }
    private var enabledProviders: [AIProvider] { orderedProviders.filter(\.enabled) }
    private var disabledProviders: [AIProvider] { orderedProviders.filter { !$0.enabled } }
    private var visibleProviders: [AIProvider] { displayOrder ?? enabledProviders }

    private var summary: ProviderChainSummary {
        ProviderChainLogic.summarize(providers) { runtime.keyPresence[$0] == true }
    }

    private var recentFailures: Set<String> {
        ProviderChainLogic.recentFailureProviderIds(runtime.diagnostics)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusCard.padding(.top, 4)
                chainSection.padding(.top, 16)
                addButton.padding(.top, 12)
                diagnosticsCard.padding(.top, 16)
                privacyNote.padding(.top, 16)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top) { header }
        .onAppear { runtime.refreshKeys(providers.map(\.providerId)) }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case let .detail(provider, _):
                ProviderDetailSheet(provider: provider, runtime: runtime)
            case .add:
                AddProviderSheet(
                    runtime: runtime,
                    sortOrder: ProviderChainLogic.nextSortOrder(providers),
                    existingIds: Set(providers.map(\.providerId))
                )
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: 导航头（‹ 返回 + 居中 serif 标题）

    private var header: some View {
        ZStack {
            Text("AI 助教 · 服务商")
                .font(.headlineSm)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .medium))
                        Text("返回")
                            .font(.bodyMd)
                    }
                    .foregroundStyle(Color.amber)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(Color.canvas)
    }

    // MARK: 状态卡

    private var statusCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(summary.state == .healthy ? Color.success : Color.amber)
                        .frame(width: 8, height: 8)
                        .shadow(color: summary.state == .healthy ? Color.success.opacity(0.5) : .clear, radius: 4)
                    Text(statusLine)
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                }
                Text(summary.statusDetail)
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    /// 「链路正常 · 当前使用：百炼 · qwen3-vl」——降级命中时如实写实际生效者（S25 spec 交互态）
    private var statusLine: String {
        var line = summary.statusTitle
        if let current = ProviderChainLogic.statusCurrentText(
            lastSuccessful: runtime.lastSuccessful,
            providers: providers
        ) {
            line += " · \(current)"
        }
        return line
    }

    // MARK: 模型链路

    private var chainSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("模型链路（拖动排序）")
                    .font(.labelMd)
                    .foregroundStyle(Color.textMuted)
                Spacer()
                Text("长按右侧手柄微调优先级")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted.opacity(0.7))
            }
            if enabledProviders.isEmpty {
                emptyChainHint
            }
            ForEach(visibleProviders) { provider in
                chainRow(provider)
            }
            if !disabledProviders.isEmpty {
                disabledSection.padding(.top, 8)
            }
        }
    }

    private var emptyChainHint: some View {
        Text("还没有服务商。添加一个服务商并填入 Key，AI 助教才能回答你的问题。")
            .font(.bodySm)
            .foregroundStyle(Color.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
    }

    /// 已停用的服务商在链区外单独列（否则停用后无法从链上找回——enabled 开关就成单行道）
    private var disabledSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已停用（不参与提问）")
                .font(.labelMd)
                .foregroundStyle(Color.textMuted)
            ForEach(disabledProviders) { provider in
                Button { openDetail(provider) } label: {
                    HStack(spacing: 10) {
                        Text(displayName(provider))
                            .font(.bodyMd)
                            .foregroundStyle(Color.textMuted)
                        Spacer()
                        Text(modelSummary(provider))
                            .font(.labelMono(11))
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textMuted)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chainRow(_ provider: AIProvider) -> some View {
        let isDragging = draggingProviderId == provider.providerId
        let index = visibleProviders.firstIndex { $0.providerId == provider.providerId } ?? 0
        return HStack(spacing: 10) {
            Button { openDetail(provider) } label: {
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.labelMono(13))
                        .foregroundStyle(Color.amber)
                        .frame(width: 16, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(displayName(provider))
                                .font(.titleMd)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            if isEffective(provider) {
                                Text("首选生效")
                                    .font(.labelSm)
                                    .foregroundStyle(Color.amber)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.amber.opacity(0.15), in: Capsule())
                            }
                        }
                        Text(modelSummary(provider))
                            .font(.labelMono(12))
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    statusDot(provider)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            dragHandle(provider: provider)
        }
        .padding(.horizontal, 14)
        .frame(height: rowHeight)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
        .offset(y: isDragging ? dragOffset : 0)
        .scaleEffect(isDragging ? 1.02 : 1)
        .shadow(color: isDragging ? .black.opacity(0.45) : .clear, radius: isDragging ? 10 : 0)
        .zIndex(isDragging ? 1 : 0)
    }

    /// 拖拽中被抬起那一行相对手指的偏移（数组已把它移到目标槽，再补回手指的细微差）
    private var dragOffset: CGFloat {
        let target = ProviderChainLogic.targetIndex(
            startIndex: dragStartIndex,
            translation: dragTranslation,
            pitch: pitch,
            count: visibleProviders.count
        )
        return dragTranslation - CGFloat(target - dragStartIndex) * pitch
    }

    private func dragHandle(provider: AIProvider) -> some View {
        Button { openDetail(provider) } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundStyle(Color.textMuted)
                .frame(width: 30, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if draggingProviderId != provider.providerId {
                        draggingProviderId = provider.providerId
                        dragStartIndex = enabledProviders.firstIndex { $0.providerId == provider.providerId } ?? 0
                        displayOrder = enabledProviders
                    }
                    dragTranslation = value.translation.height
                    reorderDuringDrag()
                }
                .onEnded { _ in commitDrag() }
        )
    }

    /// 拖动过程中把被拖行移到目标槽（纯函数算落位，这里只搬运数组）
    private func reorderDuringDrag() {
        guard let draggedId = draggingProviderId, let base = displayOrder else { return }
        let target = ProviderChainLogic.targetIndex(
            startIndex: dragStartIndex,
            translation: dragTranslation,
            pitch: pitch,
            count: base.count
        )
        guard let current = base.firstIndex(where: { $0.providerId == draggedId }),
              current != target else { return }
        var items = base
        let moved = items.remove(at: current)
        items.insert(moved, at: target)
        displayOrder = items
    }

    /// 落位即存优先级；并清 runner 粘性（语义：用户手动改优先级）
    private func commitDrag() {
        guard let order = displayOrder else { clearDrag(); return }
        var assignments = ProviderChainLogic.sortOrderAssignments(order.map(\.providerId))
        var next = order.count
        for provider in disabledProviders {
            assignments[provider.providerId] = next
            next += 1
        }
        for provider in providers {
            if let value = assignments[provider.providerId] {
                provider.sortOrder = value
            }
        }
        try? context.save()
        runtime.resetChain()
        clearDrag()
    }

    private func clearDrag() {
        displayOrder = nil
        draggingProviderId = nil
        dragTranslation = 0
        dragStartIndex = 0
    }

    private func statusDot(_ provider: AIProvider) -> some View {
        let status = ProviderChainLogic.rowStatus(
            provider: provider,
            hasKey: runtime.keyPresence[provider.providerId] ?? false,
            recentFailure: recentFailures.contains(provider.providerId)
        )
        return Circle()
            .fill(dotColor(status))
            .frame(width: 8, height: 8)
            .shadow(color: status == .available ? Color.success.opacity(0.5) : .clear, radius: 3)
    }

    /// S25 spec 状态点：绿 #7FA97C / 暗灰 #524B46 / 陶土红 #C97064（= danger）
    private func dotColor(_ status: ProviderRowStatus) -> Color {
        switch status {
        case .available: return Color.success
        case .unconfigured: return Color.chainUnconfiguredDot
        case .failedRecently: return Color.danger
        }
    }

    /// 「首选生效」：上次实际命中的那一行（降级时标在真正生效的备用行，不谎称首选）
    private func isEffective(_ provider: AIProvider) -> Bool {
        runtime.lastSuccessful?.providerId == provider.providerId
    }

    private func displayName(_ provider: AIProvider) -> String {
        provider.displayName.isEmpty ? provider.providerId : provider.displayName
    }

    /// 模型摘要：单个显示 id；多个「首个 等 N 个」（brief：自行选清晰的形态）
    private func modelSummary(_ provider: AIProvider) -> String {
        let models = provider.modelIds.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !models.isEmpty else { return "未配置模型" }
        if models.count == 1 { return models[0] }
        return "\(models[0]) 等 \(models.count) 个"
    }

    // MARK: 添加服务商（琥珀虚线全宽按钮，高 46）

    private var addButton: some View {
        Button { activeSheet = .add } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                Text("添加服务商")
                    .font(.titleMd)
            }
            .foregroundStyle(Color.amber)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.amber, style: StrokeStyle(lineWidth: 1, dash: [6]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 诊断记录卡（mono 三列；永不包含 key）

    private var diagnosticsCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("诊断记录")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    if runtime.diagnostics.count > 3 {
                        Button(showAllDiagnostics ? "收起" : "查看全部") {
                            showAllDiagnostics.toggle()
                        }
                        .font(.labelMd)
                        .foregroundStyle(Color.amber)
                    }
                }
                if runtime.diagnostics.isEmpty {
                    Text("还没有调用记录。保存 Key 时会自动发一次最小校验，结果记在这里。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                } else {
                    let entries = showAllDiagnostics
                        ? runtime.diagnostics
                        : Array(runtime.diagnostics.suffix(3))
                    ForEach(entries.map { ProviderChainLogic.diagnosticRow($0) }) { row in
                        diagnosticRowView(row)
                    }
                }
            }
        }
    }

    private func diagnosticRowView(_ row: ChainDiagnosticRow) -> some View {
        HStack(spacing: 8) {
            Text(row.timeText)
                .font(.labelMono(11))
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()
                .frame(width: 72, alignment: .leading)
            Text(row.targetText)
                .font(.labelMono(11))
                .foregroundStyle(Color.textBody)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(row.resultText)
                .font(.labelMono(11))
                .foregroundStyle(row.succeeded ? Color.success : Color.danger)
        }
    }

    // MARK: 隐私卡（S25 spec 末行原文）

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("🔒")
                .font(.bodySm)
            Text("每个 Key 只保存在 iOS 钥匙串，不进入备份、导出包与日志；视频须经你确认后才会发送。")
                .font(.bodySm)
                .leading(19, fontSize: 12)
                .foregroundStyle(Color.textMuted)
        }
    }
}

/// S25 spec 的「未验证」状态点 #524B46（色板无此 token，按 spec 字面值）
private extension Color {
    static let chainUnconfiguredDot = Color(red: 0x52 / 255, green: 0x4B / 255, blue: 0x46 / 255)
}

// MARK: - 预览夹具（内存容器 + 三条示例服务商；不打网络、不碰 Keychain）

#if DEBUG
private enum ProviderChainPreviewContainer {
    @MainActor
    static func make() -> ModelContainer {
        let container = try! ModelContainer(
            for: AIProvider.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        // 必须插 mainContext：@Query 与视图的 modelContext 都读它
        let context = container.mainContext
        context.insert(AIProvider(providerId: "ark", displayName: "火山方舟",
                                  baseURL: "https://ark.cn-beijing.volces.com/api/v3",
                                  modelIds: ["doubao-seed-2-1-pro"], enabled: true, sortOrder: 0))
        context.insert(AIProvider(providerId: "bailian", displayName: "百炼",
                                  baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                                  modelIds: ["qwen3-vl-plus", "qwen3-vl-flash"], enabled: true, sortOrder: 1))
        context.insert(AIProvider(providerId: "deepseek", displayName: "DeepSeek",
                                  baseURL: "https://api.deepseek.com/v1",
                                  modelIds: ["deepseek-vl2"], enabled: false, sortOrder: 2))
        return container
    }
}
#endif

#Preview {
    ProviderChainSettingsView()
        .modelContainer(ProviderChainPreviewContainer.make())
        .preferredColorScheme(.dark)
}
