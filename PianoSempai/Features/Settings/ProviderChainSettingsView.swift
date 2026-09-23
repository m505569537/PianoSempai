import SwiftData
import SwiftUI

// MARK: - S25 AI 助教 · 服务商（对齐 2026-09-23 修订版 spec）
// 真值：docs/design-reference/screens/S25-apikey/spec.md 与同目录 code.html。
// 施工口径：html 内壳 428 逻辑宽换算 pt；圆角一律按 DOM 类名（rounded-xl=12 / rounded-lg=8 / 胶囊 99）。
// 屏内私有色（token 未覆盖的真值 hex）集中在文件末尾，不写入 Assets、不改全局 token。
// 单 sheet 路由（沿用 LibraryView 的教训：一个视图只可靠呈现一个 .sheet）。

struct ProviderChainSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \AIProvider.sortOrder) private var providers: [AIProvider]

    /// 常驻链状态（诊断 / 粘性 / key 存在性；brief §1）
    @State private var runtime = ProviderChainRuntime()
    @State private var activeSheet: ActiveSheet?
    @State private var showAllDiagnostics = false
    @State private var showHelp = false

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

    /// 真值行内容约 39pt + p-3.5（14×2）≈ 67，取 72 留呼吸；pitch 必须等于 行高 + 行间距
    private let rowHeight: CGFloat = 72
    private let rowSpacing: CGFloat = 8 // 真值列表 space-y-2
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
            VStack(alignment: .leading, spacing: 20) { // 真值 main space-y-5
                statusCard
                chainSection
                diagnosticsSection
                keychainCard
            }
            .padding(.horizontal, 16) // px-4
            .padding(.top, 14) // pt-3.5
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden) // 真值 custom-scrollbar 隐藏滚动条
        .background(Color.canvas)
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { homeIndicator }
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
        .alert("服务商链怎么用", isPresented: $showHelp) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(helpText)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: 导航头（‹ 返回 + 居中 serif 标题 + 帮助；真值 h-12 = 48）

    private var header: some View {
        ZStack {
            HStack(spacing: 6) { // 6×6 琥珀点 + serif 标题
                Circle()
                    .fill(Color.amber)
                    .frame(width: 6, height: 6)
                Text("AI 助教 · 服务商")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.s25OnSurface)
                    .lineLimit(1)
            }
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 24))
                        Text("返回")
                            .font(.bodyMd)
                    }
                    .foregroundStyle(Color.amber)
                }
                .buttonStyle(.plain)
                Spacer()
                Button { showHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.textMuted)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12) // px-3
        .frame(height: 48) // h-12
        .background(Color.canvas) // 真值 surface/90 + backdrop-blur；纯色底观感等价
    }

    private var helpText: String {
        "服务商按顺序尝试：任一可用即工作，遇到超限或故障会毫秒级自动切换到下一个。\n"
            + "按住右侧手柄拖动可调整优先级；点每行的调节按钮可配置 Key 与模型。\n"
            + "Key 只写在本机钥匙串，不进入备份、导出包与日志。"
    }

    // MARK: 状态横幅卡（spec §4：p-4 / 圆角 12 / shadow-lg / overflow-hidden）

    private var statusCard: some View {
        ZStack(alignment: .topTrailing) {
            // 氛围光：112×112 amber/10 blur-2xl（≈40px），右上 -40/-40
            Circle()
                .fill(Color.amber.opacity(0.1))
                .frame(width: 112, height: 112)
                .blur(radius: 20)
                .offset(x: 40, y: -40)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) { // space-y-1.5
                        statusPill
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("当前主力：\(effectiveProvider.map(displayName) ?? "未配置")")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.s25OnSurface)
                                    .lineLimit(1)
                                Text(effectiveModelText)
                                    .font(.labelMono(12))
                                    .foregroundStyle(Color.amber)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.s25SecondaryContainer, in: RoundedRectangle(cornerRadius: 2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .strokeBorder(Color.amber.opacity(0.25), lineWidth: 1)
                                    )
                            }
                            Text(statusDetailText)
                                .font(.bodySm)
                                .leading(20, fontSize: 12) // leading-relaxed ≈ 1.625
                                .foregroundStyle(Color.s25OnSurfaceVariant)
                        }
                        .padding(.top, 4) // pt-1
                    }
                    // 右图标盒：36×36 圆角 8，#2D2825 底 + 边，swap_calls 20pt 琥珀
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.amber)
                        .frame(width: 36, height: 36)
                        .background(Color.s25SurfaceHigh, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1)
                        )
                }
                // 延迟行：mt-3 pt-2.5 + 顶边发丝线
                latencyRow
                    .padding(.top, 10)
                    .overlay(alignment: .top) {
                        Color.border.frame(height: 1).frame(maxWidth: .infinity)
                    }
                    .padding(.top, 12)
            }
            .padding(16) // p-4
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 12)) // overflow-hidden：裁掉氛围光溢出
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6) // shadow-lg 近似
    }

    /// 状态胶囊：surface 底 + 边 + 圆角 99，8×8 绿点（真值 animate-ping）+ 12pt medium
    private var statusPill: some View {
        HStack(spacing: 8) {
            if summary.state == .healthy {
                StatusPingDot()
            } else {
                Circle()
                    .fill(pillColor)
                    .frame(width: 8, height: 8)
            }
            Text(pillText)
                .font(.labelMd)
                .foregroundStyle(pillColor)
        }
        .padding(.horizontal, 10) // px-2.5
        .padding(.vertical, 4) // py-1
        .background(Color.canvas, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
    }

    private var pillText: String {
        switch summary.state {
        case .healthy: return "链路正常 · 实时就绪"
        case .noneAvailable: return "链路暂不可用"
        case .empty: return "尚未配置服务商"
        }
    }

    private var pillColor: Color {
        switch summary.state {
        case .healthy: return Color.success
        case .noneAvailable: return Color.amber
        case .empty: return Color.textMuted
        }
    }

    private var statusDetailText: String {
        summary.state == .healthy
            ? "提问时按顺序尝试，任一可用即工作，遇到超限或故障毫秒级自动平滑切换。"
            : summary.statusDetail
    }

    private var latencyRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "speedometer") // Material speed
                .font(.system(size: 14))
                .foregroundStyle(Color.amber)
            Text(latencyText)
                .font(.system(size: 11))
                .foregroundStyle(Color.s25OnSurfaceVariant)
            Spacer(minLength: 8)
            Text("容灾策略：故障顺延 (Failover)")
                .font(.labelMono(11))
                .foregroundStyle(Color.textMuted)
                .lineLimit(1)
        }
    }

    /// 响应延迟：最近一次成功调用的耗时（真值样例「~1.8s」；无记录时如实说暂无）
    private var latencyText: String {
        guard let last = runtime.diagnostics.last(where: \.succeeded) else {
            return "响应延迟：暂无记录"
        }
        return "响应延迟：~\(ProviderChainLogic.durationText(last.durationMs))"
    }

    // MARK: 模型链路（spec §5：拖动排序）

    private var chainSection: some View {
        VStack(alignment: .leading, spacing: 10) { // space-y-2.5
            sectionHeader(
                icon: "arrow.triangle.branch", // Material alt_route
                title: "模型链路（拖动排序）",
                hint: "长按右侧手柄微调优先级"
            )
            if visibleProviders.isEmpty {
                emptyChainHint
            } else {
                VStack(spacing: rowSpacing) {
                    ForEach(chainRows) { row in
                        chainRow(row)
                    }
                }
            }
            addButton
            if !disabledProviders.isEmpty {
                disabledSection
            }
        }
    }

    /// 区块头：18pt 琥珀图标 + 14pt semibold 标题；右 11pt muted 提示（真值 px-1）
    private func sectionHeader(icon: String, title: String, hint: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.amber)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.s25OnSurface)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
    }

    private var emptyChainHint: some View {
        Text("还没有服务商。添加一个服务商并填入 Key，AI 助教才能回答你的问题。")
            .font(.bodySm)
            .foregroundStyle(Color.s25OnSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
    }

    /// 已停用的服务商在链区外单独列（否则停用后无法从链上找回——enabled 开关就成单行道）。
    /// 真值本屏只有启用中的行；停用行沿用链路行样式，标签换「已停用」且不给手柄。
    private var disabledSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已停用（不参与提问）")
                .font(.labelMd)
                .foregroundStyle(Color.textMuted)
            ForEach(disabledProviders) { provider in
                Button { openDetail(provider) } label: {
                    HStack(spacing: 8) {
                        Text(displayName(provider))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.s25OnSurface)
                            .lineLimit(1)
                        Text("已停用")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.canvas, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4).strokeBorder(Color.border, lineWidth: 1)
                            )
                        Spacer(minLength: 8)
                        Text(modelSummary(provider))
                            .font(.labelMono(12))
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 链路行展示数据（位置 / 是否生效 / 备选序号 / 行状态）。拖动时随 displayOrder 重算。
    private struct ChainRow: Identifiable {
        let provider: AIProvider
        /// 链上位置（0-based，用于序号盒）
        let position: Int
        /// 是否当前生效（上次真实命中；无记录时取链上第一个可用者）
        let isEffective: Bool
        /// 备选序号（非生效行从 1 起；生效行为 0）
        let backupRank: Int
        let status: ProviderRowStatus

        var id: String { provider.providerId }
    }

    private var chainRows: [ChainRow] {
        var backup = 0
        var rows: [ChainRow] = []
        for (position, provider) in visibleProviders.enumerated() {
            let status = ProviderChainLogic.rowStatus(
                provider: provider,
                hasKey: runtime.keyPresence[provider.providerId] ?? false,
                recentFailure: recentFailures.contains(provider.providerId)
            )
            if isEffective(provider) {
                rows.append(ChainRow(provider: provider, position: position, isEffective: true, backupRank: 0, status: status))
            } else {
                backup += 1
                rows.append(ChainRow(provider: provider, position: position, isEffective: false, backupRank: backup, status: status))
            }
        }
        return rows
    }

    private func chainRow(_ row: ChainRow) -> some View {
        let provider = row.provider
        let isDragging = draggingProviderId == provider.providerId
        return HStack(spacing: 12) { // 序号盒 + 文案组 gap-3
            priorityBadge(number: row.position + 1, isPrimary: row.isEffective)
            VStack(alignment: .leading, spacing: 2) { // space-y-0.5
                HStack(spacing: 8) {
                    Text(displayName(provider))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.s25OnSurface)
                        .lineLimit(1)
                    statusTag(row)
                }
                HStack(spacing: 8) {
                    Text(modelSummary(provider))
                        .font(.labelMono(12))
                        .foregroundStyle(Color.s25OnSurfaceVariant)
                        .lineLimit(1)
                        .frame(maxWidth: 150, alignment: .leading) // 真值 max-w-[150px] 截断
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textMuted)
                    statusWord(row)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) { // tune + 手柄 gap-2
                Button { openDetail(provider) } label: {
                    Image(systemName: "sliders.horizontal") // Material tune
                        .font(.system(size: 18))
                        .foregroundStyle(Color.textMuted)
                        .padding(6) // p-1.5
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                dragHandle(provider: provider)
            }
        }
        .padding(.horizontal, 14) // p-3.5（纵向由固定行高承载）
        .frame(height: rowHeight)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(row.isEffective ? Color.amber.opacity(0.5) : Color.border, lineWidth: 1)
        )
        .overlay {
            // 拖动中整行 ring-2 amber + scale 1.01（真值 html 脚本 300ms 反馈）
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.amber, lineWidth: isDragging ? 2 : 0)
        }
        .scaleEffect(isDragging ? 1.01 : 1)
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2) // shadow-sm 近似
        .offset(y: isDragging ? dragOffset : 0)
        .zIndex(isDragging ? 1 : 0)
    }

    /// 序号盒：28×28 圆角 8；首选琥珀实心 + canvas 粗体，备选 #2D2825 + 边 + muted
    private func priorityBadge(number: Int, isPrimary: Bool) -> some View {
        Text("\(number)")
            .font(.labelMono(12, weight: isPrimary ? .bold : .medium))
            .foregroundStyle(isPrimary ? Color.canvas : Color.textMuted)
            .frame(width: 28, height: 28)
            .background(isPrimary ? Color.amber : Color.s25SurfaceHigh, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isPrimary ? Color.clear : Color.border, lineWidth: 1)
            )
    }

    /// 行标签：生效行 = 琥珀胶囊「首选生效」（含 4×4 绿点）；其余 = 「备选 N」
    @ViewBuilder
    private func statusTag(_ row: ChainRow) -> some View {
        if row.isEffective {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.success)
                    .frame(width: 4, height: 4)
                Text("首选生效")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Color.amber)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.amber.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.amber.opacity(0.3), lineWidth: 1))
        } else {
            Text("备选 \(row.backupRank)")
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.canvas, in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Color.border, lineWidth: 1)
                )
        }
    }

    /// 副行右词：生效「活跃中」绿；备选「待命就绪」muted；降级态如实写「最近失败 / 未配置」
    @ViewBuilder
    private func statusWord(_ row: ChainRow) -> some View {
        if row.isEffective {
            Text("活跃中")
                .font(.labelMono(11))
                .foregroundStyle(Color.success)
        } else {
            switch row.status {
            case .available:
                Text("待命就绪")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
            case .failedRecently:
                Text("最近失败")
                    .font(.labelMono(11))
                    .foregroundStyle(Color.s25Error)
            case .unconfigured:
                Text("未配置")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
            }
        }
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

    /// 纯拖动手柄（真值 touch-none）：不再兼作进入详情的按钮，入口统一在 tune 按钮
    private func dragHandle(provider: AIProvider) -> some View {
        Image(systemName: "line.3.horizontal") // Material drag_indicator
            .font(.system(size: 20))
            .foregroundStyle(draggingProviderId == provider.providerId ? Color.amber : Color.textMuted)
            .padding(6) // p-1.5
            .frame(width: 32, height: 44) // 热区 ≥32pt
            .contentShape(Rectangle())
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

    /// 链上第一个可用者（无命中记录时的「当前主力」候选）
    private var firstAvailable: AIProvider? {
        enabledProviders.first { provider in
            ProviderChainLogic.isAvailable(provider) { id in runtime.keyPresence[id] == true }
        }
    }

    /// 当前生效的服务商：优先上次真实命中（降级时如实反映实际生效者），否则链上第一个可用者
    private var effectiveProvider: AIProvider? {
        guard let last = runtime.lastSuccessful else { return firstAvailable }
        return providers.first { $0.providerId == last.providerId } ?? firstAvailable
    }

    /// 生效行：降级命中时标在真正生效的备用行，不谎称链首
    private func isEffective(_ provider: AIProvider) -> Bool {
        effectiveProvider?.providerId == provider.providerId
    }

    /// 生效模型 id：命中记录里的实际模型，否则该商首个非空模型
    private var effectiveModelText: String {
        if let last = runtime.lastSuccessful, effectiveProvider?.providerId == last.providerId {
            return last.modelId
        }
        return effectiveProvider?.modelIds.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "未配置模型"
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

    // MARK: 添加服务商（琥珀虚线全宽按钮；真值高约 44）

    private var addButton: some View {
        Button { activeSheet = .add } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle") // Material add_circle
                    .font(.system(size: 18))
                Text("添加模型服务商")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Color.amber)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12) // py-3
            .padding(.horizontal, 16) // px-4
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.amber.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [6]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 诊断记录（spec §6：卡内 mono 12pt，行间发丝线 /60，末行无）

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 8) { // space-y-2
            sectionHeader(
                icon: "terminal",
                title: "诊断记录",
                hint: "最近调用与自动化健康探测"
            )
            S25Card {
                VStack(alignment: .leading, spacing: 10) { // space-y-2.5
                    if runtime.diagnostics.isEmpty {
                        Text("还没有调用记录。保存 Key 时会自动发一次最小校验，结果记在这里。")
                            .font(.bodySm)
                            .foregroundStyle(Color.s25OnSurfaceVariant)
                    } else {
                        let entries = showAllDiagnostics
                            ? runtime.diagnostics
                            : Array(runtime.diagnostics.suffix(3))
                        let rows = entries.map { ProviderChainLogic.diagnosticRow($0) }
                        ForEach(rows) { row in
                            diagnosticRowView(row, isLast: row.id == rows.last?.id)
                        }
                    }
                    if runtime.diagnostics.count > 3 {
                        HStack {
                            Spacer()
                            Button { showAllDiagnostics.toggle() } label: {
                                HStack(spacing: 2) {
                                    Text(showAllDiagnostics ? "收起" : "查看全部诊断日志")
                                    Image(systemName: showAllDiagnostics ? "chevron.up" : "chevron.right")
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(Color.amber)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 6) // 真值卡尾 pt-1.5
                    }
                }
            }
        }
    }

    private func diagnosticRowView(_ row: ChainDiagnosticRow, isLast: Bool) -> some View {
        HStack(spacing: 8) {
            Text(row.timeText)
                .font(.labelMono(11))
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()
            Text(row.targetText)
                .font(.labelMono(12, weight: .medium))
                .foregroundStyle(row.succeeded ? Color.s25OnSurface : Color.s25OnSurfaceVariant)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Image(systemName: row.succeeded ? "checkmark.circle" : "xmark.circle")
                    .font(.system(size: 14))
                Text(resultValue(row.resultText))
                    .font(.labelMono(11, weight: .semibold))
            }
            .foregroundStyle(row.succeeded ? Color.success : Color.s25Error)
            .lineLimit(1)
        }
        .padding(.bottom, 8) // pb-2
        .overlay(alignment: .bottom) {
            if !isLast {
                Color.border.opacity(0.6).frame(height: 1).frame(maxWidth: .infinity)
            }
        }
    }

    /// 结果值：logic 的 resultText 前缀 ✓/✗（格式由测试锁定），图标在本视图单独画，故剥掉首符号
    private func resultValue(_ text: String) -> String {
        guard let first = text.first, first == "✓" || first == "✗" else { return text }
        return String(text.dropFirst())
    }

    // MARK: Keychain 安全卡（spec §7：#38312B lock 盒，无 emoji）

    private var keychainCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock")
                .font(.system(size: 18))
                .foregroundStyle(Color.amber)
                .padding(6) // p-1.5
                .background(Color.s25SecondaryContainer, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
                .offset(y: 2) // 真值 mt-0.5
            VStack(alignment: .leading, spacing: 2) { // space-y-0.5
                Text("钥匙串硬件加密保障")
                    .font(.labelMd)
                    .foregroundStyle(Color.s25OnSurface)
                Text("每个 API Key 仅加密存于本机 iOS Keychain，不进入 iCloud 备份、导出包或日志；"
                     + "练习分析视频须经你单独确认后才会传输。")
                    .font(.system(size: 11))
                    .leading(18, fontSize: 11) // leading-relaxed ≈ 1.625
                    .foregroundStyle(Color.s25OnSurfaceVariant)
            }
        }
        .padding(14) // p-3.5
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
    }

    // MARK: 底部 home indicator（真值 128×4 muted/30）

    private var homeIndicator: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.textMuted.opacity(0.3))
                .frame(width: 128, height: 4)
            Spacer()
        }
        .padding(.top, 16) // pt-4
        .padding(.bottom, 8) // pb-2
        .background(Color.canvas)
    }
}

// MARK: - 屏内小组件

/// 真值 `animate-ping` 状态点：8×8 实点 + 同步扩散环（1.2s 一圈，不自动回弹）
private struct StatusPingDot: View {
    var color: Color = Color.success
    @State private var ping = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(color.opacity(0.75), lineWidth: 1)
                .frame(width: 8, height: 8)
                .scaleEffect(ping ? 1.9 : 1)
                .opacity(ping ? 0 : 0.75)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 8, height: 8)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                ping = true
            }
        }
    }
}

/// S25 卡面（真值 rounded-xl = 12 + p-3.5 = 14；DesignSystem 的 NocturneCard 固定 16/8，不适用于本屏）
private struct S25Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
    }
}

// MARK: - S25 屏内私有色（真值 hex；token 未覆盖，不写入 Assets / 不改全局 token）

fileprivate extension Color {
    /// hex → sRGB（S25 真值局部色专用）
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// on-surface（真值 #E6E1DC；token textPrimary 是 #F5F2ED）
    static let s25OnSurface = Color(hex: 0xE6E1DC)
    /// on-surface-variant（真值 #C8C2BC；token textBody 是 #C2BCB4）
    static let s25OnSurfaceVariant = Color(hex: 0xC8C2BC)
    /// surface-container-high：序号盒（备选）/ 右上图标盒（真值 #2D2825；token cardElevated 是 #2D2724）
    static let s25SurfaceHigh = Color(hex: 0x2D2825)
    /// secondary-container：模型标签底 + 安全卡 lock 盒底（真值 #38312B）
    static let s25SecondaryContainer = Color(hex: 0x38312B)
    /// error：失败诊断图标与文字（真值 #E06D63；token danger 是 #C97064，spec §9.4 已判错）
    static let s25Error = Color(hex: 0xE06D63)
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
