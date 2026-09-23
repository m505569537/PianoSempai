import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - S08 曲库（三段 + 筛选 + 导入；PDF 走 S10）

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query private var pathStates: [CoursePathState]
    @Query private var allPieces: [Piece]
    @Query private var scoreFiles: [ScoreFile]

    enum Segment: String, CaseIterable {
        case training = "训练教材"
        case reward = "奖励曲库"
        case imports = "全部导入"
    }

    @State private var segment: Segment = .training
    @State private var bookFilter: String? // nil = 全部
    @State private var showImporter = false
    /// F2：搜索钮展开的输入态 + 本地筛选词（仅内存，不新建 service、不写库）
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var importTarget: ImportTarget? // 统一导入入口：选教材/奖励曲库
    @State private var importError: LibraryImportService.ImportError?
    @State private var importedFileName = ""
    /// 单一 sheet 路由（SwiftUI 一个视图只可靠呈现一个 .sheet；三链曾致 S09 死路）
    enum ActiveSheet: Identifiable {
        case pdf
        case entry(CatalogEntry)
        case piece(Piece)

        var id: String {
            switch self {
            case .pdf: "pdf"
            case let .entry(entry): "entry-\(entry.id)"
            case let .piece(piece): "piece-\(piece.entityId.uuidString)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?

    private var pathState: CoursePathState? { pathStates.first }
    private var catalog: [CatalogEntry] { CatalogLoader.loadBuiltin() }

    /// 导入曲（奖励曲库/PDF 段用）。只列 book="导入" 的真实导入——
    /// M5b 给目录条目建档的 Piece 不能混进来（红线：曲库只呈现真实来源）。
    private var importedPieces: [Piece] {
        allPieces.filter { $0.book == "导入" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                // F2：搜索框展开在 header 下方；只在训练教材段渲染（其余段不出现无用控件）
                if isSearching, segment == .training {
                    searchField
                        .padding(.bottom, 12)
                }
                segmentBar
                segmentContent
            }
            .background(Color.canvas)
            .navigationBarHidden(true)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .pdf: PDFLibraryView()
            case let .entry(entry): PieceDetailView(entry: entry)
            case let .piece(piece): PieceDetailView(piece: piece)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType.data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .overlay {
            if let importError {
                S08bImportFailDialog(
                    fileName: importedFileName,
                    error: importError,
                    onRetry: {
                        self.importError = nil
                        showImporter = true
                    },
                    onHelp: {
                        self.importError = nil
                        activeSheet = .pdf
                    },
                    onDismiss: { self.importError = nil }
                )
            }
        }
    }

    // MARK: 头部（真值 §2）

    private var header: some View {
        // 对齐用 .center（真值 items-center，同 S07 headerRow）：右侧是两枚 36×36 圆钮，
        // 无文本基线可对齐；.firstTextBaseline 会把无文字子视图按底边对齐，圆钮会整体上跳。
        HStack(alignment: .center, spacing: 8) {
            Text("曲库")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .tracking(-0.5)
                .foregroundStyle(Color.textPrimary)
            Text("Library")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.textMuted)
            Spacer()
            // 真值 §2：右上一枚导入圆钮 + 一枚搜索圆钮（间距 10，均 36×36）
            HStack(spacing: 10) {
                importCircleButton
                searchCircleButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// 36×36 圆钮共用样式（真值 §2）：card/80 底 + 1pt border；active scale .95。
    /// hover 边 amber/60 是桌面端交互，本 App 为 iPhone（iOS 17），无 hover 态，故不实现。
    private func s08CircleButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Color.card.opacity(0.8), in: Circle())
                .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(S08ScaleButtonStyle(scale: 0.95))
    }

    /// 导入钮（真值 §2）：16pt 琥珀 plus，沿用 v1 的 showImporter。
    private var importCircleButton: some View {
        s08CircleButton(icon: "plus", tint: Color.amber) {
            showImporter = true
        }
    }

    /// 搜索钮（真值 §2）：未激活图标 textMuted；展开后转琥珀表示当前在搜索（与筛选 chip 选中同一套强调色）。
    private var searchCircleButton: some View {
        s08CircleButton(icon: "magnifyingglass", tint: isSearching ? Color.amber : Color.textMuted) {
            isSearching.toggle()
        }
    }

    // MARK: 搜索输入框（F2：本地按曲名筛选，不新建 service / 不写库 / 不联网）

    /// 去掉首尾空白后的搜索词；空 = 不筛选。
    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Color.textMuted)
            TextField("搜索曲名", text: $searchText)
                .font(.system(size: 13))
                .foregroundStyle(Color.textPrimary)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    // brief：再次点搜索钮或清空可收起 → ✕ 清空文本并收起搜索框，列表随即恢复
                    searchText = ""
                    isSearching = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.border, lineWidth: 1))
        .padding(.horizontal, 20)
    }

    // MARK: 三段分段（真值 §3：统一容器 + 琥珀实心选中块）

    private var segmentBar: some View {
        HStack(spacing: 4) {
            ForEach(Segment.allCases, id: \.self) { seg in
                let selected = segment == seg
                Button {
                    segment = seg
                } label: {
                    Text(seg.rawValue)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.canvas : Color.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selected ? Color.amber : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        // v2 移除原先的「内阴影近似」overlay：不再用硬编码 1pt 暗线模拟 shadow-inner。
        // TODO(视觉)：真值容器带 shadow-inner，需要时用 Canvas / 真正内阴影实现，勿再加 overlay 线。
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: 内容

    @ViewBuilder
    private var segmentContent: some View {
        switch segment {
        case .training: trainingSegment
        case .reward: rewardSegment
        case .imports: importsSegment
        }
    }

    private var trainingSegment: some View {
        let entries = filteredCatalog
        let layout = catalogLayout
        return VStack(spacing: 0) {
            filterChips
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if entries.isEmpty {
                        // F2：搜索词无命中时换成「没找到」的文案；教材 chip 自身无命中仍用原空态
                        emptyHint(searchQuery.isEmpty ? "这个筛选下还没有曲子" : "没找到匹配的曲子")
                    }
                    // 示例曲 featured：在教材列表顶部单独展示，不沉底
                    if let sample = entries.first(where: \.isSample) {
                        sampleFeaturedCard(sample)
                    }
                    ForEach(entries.filter { !$0.isSample }) { entry in
                        catalogRow(
                            entry,
                            index: layout.order[entry.id] ?? 0,
                            isFocus: entry.id == layout.focusId
                        )
                    }
                    // 底部虚线导入卡（与 header 导入钮共用同一 showImporter）
                    importCard
                }
                // 顶部不另加留白：segmentBar 的 pb-12 + filterChips 的 pb-12 已是真值间距
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var filteredCatalog: [CatalogEntry] {
        var entries = catalog
        // 教材 chip 与曲名搜索叠加生效：先按教材收窄，再按曲名子串收窄
        if let bookFilter {
            entries = entries.filter { $0.book == bookFilter }
        }
        if !searchQuery.isEmpty {
            entries = entries.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
        }
        return entries
    }

    /// 完整训练教材 catalog 的稳定顺序号 + 当前主练条目。
    /// 一次解码 `catalog`，避免每行重复 `loadBuiltin()`（136 条 × 每行一次解码不可接受）。
    /// - 序号：sample 条目不参与编号；其余按 catalog 顺序 1-based（`%02d`，三位不截断）。
    /// - 焦点：catalog 顺序里第一条 `status == .practicing` 的教材条目（同一时刻仅一条）。
    ///   拜厄排在哈农前，故两者都在练时焦点落在拜厄，与真值行2/行4 的分工一致。
    private struct CatalogLayout {
        var order: [String: Int] = [:]
        var focusId: String?
    }

    private var catalogLayout: CatalogLayout {
        var layout = CatalogLayout()
        var n = 0
        let path = pathState ?? CoursePathState()
        for entry in catalog {
            guard !entry.isSample else { continue }
            n += 1
            layout.order[entry.id] = n
            if layout.focusId == nil,
               CourseEngine.catalogStatus(book: entry.book, number: entry.number, pathState: path) == .practicing {
                layout.focusId = entry.id
            }
        }
        return layout
    }

    // MARK: 教材筛选 chips（真值 §4：单行横滚；只做 4 枚教材）

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([nil, "拜厄", "哈农", "车尔尼599"], id: \.self) { book in
                    filterChip(title: book ?? "全部", isSelected: bookFilter == book) {
                        bookFilter = (bookFilter == book) ? nil : book
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .padding(.bottom, 12)
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.amber : Color.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(isSelected ? Color.amber.opacity(0.2) : Color.card, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color.amber.opacity(0.5) : Color.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 曲目行（真值 §5）

    /// - Parameters:
    ///   - index: 该条目在完整训练教材 catalog 中的稳定顺序号（sample 不参与编号）
    ///   - isFocus: 是否当前主练条目（同一时刻仅一条，享竖条/发光/脉动点/旋转）
    private func catalogRow(_ entry: CatalogEntry, index: Int, isFocus: Bool) -> some View {
        let path = pathState ?? CoursePathState()
        let status = CourseEngine.catalogStatus(
            book: entry.book, number: entry.number,
            pathState: path
        )
        let projected = CourseEngine.projected599WeeksLabel(pathState: path)
        // 谱可用性四态（M5a 纯决策；M5b 诚实呈现）：内置教材条目有公版谱时可判分，无谱时不冒充样例谱
        let availability = ScoreAvailability.resolve(
            scoreFile: nil,
            isSampleEntry: entry.isSample,
            bundledBook: entry.book,
            bundledNumber: entry.number
        )
        // 车尔尼599 P1 全部锁定 → 真值行6「未解锁」态（副行「路线解锁：约 N 周后」）
        let isUnlockedLocked = entry.book == "车尔尼599" && status == .locked
        let dimmed = status == .locked || status == .notStarted

        // 速度记号只在条目有真实 referenceTempo 时出现（禁编造）；无参考谱条目必带诚实标记
        let tempo = entry.referenceTempo > 0 ? entry.referenceTempo : nil
        let honestyText: String? = {
            guard case .unavailable = availability else { return nil }
            return "无参考谱"
        }()

        let statusText: String
        switch status {
        case .passed: statusText = "已拿下"
        case .practicing: statusText = "练习中"
        case .notStarted: statusText = "未开始"
        case .locked:
            if isUnlockedLocked, let projected {
                statusText = "路线解锁：约 \(projected) 周后"
            } else if isUnlockedLocked {
                statusText = "未解锁"
            } else {
                statusText = "未开始"
            }
        }

        let rowFill: Color = isUnlockedLocked
            ? Color.card.opacity(0.5)
            : (dimmed ? Color.card.opacity(0.6) : Color.card)
        let rowBorder: Color = isUnlockedLocked
            ? Color.border.opacity(0.5)
            : (dimmed
                ? Color.border.opacity(0.6)
                : (isFocus ? Color.amber.opacity(0.4) : Color.border))
        let rowOpacity: Double = isUnlockedLocked ? 0.70 : (dimmed ? 0.75 : 1)

        return Button {
            activeSheet = .entry(entry)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                // mono 序号：20pt 宽居中；三位序号（哈农/599 段）靠 minWidth 自然放开，不截断
                Text(String(format: "%02d", index))
                    .font(.labelMono(12, weight: dimmed ? .regular : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(dimmed ? Color.s08Subtle : Color.amber)
                    .frame(minWidth: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.title)
                            .font(.system(size: 14, weight: dimmed ? .medium : .semibold, design: .serif))
                            .foregroundStyle(dimmed ? Color.textPrimary.opacity(0.9) : Color.textPrimary)
                            .lineLimit(1)
                        if isFocus {
                            S08PulseDot()
                        } else if dimmed {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.s08Subtle)
                        }
                    }
                    subline(
                        statusText: statusText,
                        tempo: tempo,
                        honestyText: honestyText,
                        dimmed: dimmed
                    )
                    .lineLimit(1)
                }

                Spacer(minLength: 8)
                statusPill(status: status, isUnlockedLocked: isUnlockedLocked, isFocus: isFocus)
            }
            // p-3.5 = 14pt；焦点行按真值 pl-1 再左移 4pt 补偿竖条占位
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .padding(.leading, isFocus ? 4 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 16).fill(rowFill)
                    // 焦点行 4pt 琥珀竖条，贯穿行高（被卡面圆角裁切，同真值 overflow-hidden）
                    if isFocus {
                        Rectangle()
                            .fill(Color.amber)
                            .frame(width: 4)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(rowBorder, lineWidth: 1))
            // 焦点行柔和琥珀外发光（真值 0 0 14pt rgba(212,162,78,0.06)）
            .shadow(color: isFocus ? Color.amber.opacity(0.06) : .clear, radius: isFocus ? 7 : 0)
            .opacity(rowOpacity)
            .contentShape(Rectangle())
        }
        .buttonStyle(S08ScaleButtonStyle(scale: 0.99))
    }

    /// 副行（真值 §5）：状态 • ♩=NN（mono 琥珀/90），`•` 用 Color.border。
    /// M5 红线：无参考谱条目在此带 muted「无参考谱」，不因副行改真值样式而伪装成可判分。
    @ViewBuilder
    private func subline(
        statusText: String,
        tempo: Int?,
        honestyText: String?,
        dimmed: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Text(statusText)
                .foregroundStyle(dimmed ? Color.s08Subtle : Color.textMuted)
            if let honestyText {
                sublineDot
                Text(honestyText)
                    .foregroundStyle(Color.textMuted)
            }
            if let tempo {
                sublineDot
                Text("♩=\(tempo)")
                    .font(.labelMono(12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.amber.opacity(0.9))
            }
        }
        .font(.system(size: 12))
    }

    private var sublineDot: some View {
        Text("•").foregroundStyle(Color.border)
    }

    /// 状态 pill（真值 §5：三色半透明底 + 11pt + 1pt 边）。
    /// 仅焦点练习中行 pill 内带 4s 旋转圆环；其余练习中行（如哈农）常规琥珀 pill，不转。
    @ViewBuilder
    private func statusPill(
        status: CourseEngine.PieceStatus,
        isUnlockedLocked: Bool,
        isFocus: Bool
    ) -> some View {
        HStack(spacing: 4) {
            switch status {
            case .passed:
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
            case .practicing:
                if isFocus {
                    S08SpinRing()
                }
            case .locked, .notStarted:
                EmptyView()
            }
            Text(pillText(status: status, isUnlockedLocked: isUnlockedLocked))
        }
        .font(.system(size: 11, weight: status == .passed || status == .practicing ? .medium : .regular))
        .foregroundStyle(pillTextColor(status: status))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(pillFill(status: status), in: Capsule())
        .overlay(Capsule().strokeBorder(pillBorder(status: status, isFocus: isFocus), lineWidth: 1))
        .fixedSize()
    }

    private func pillText(status: CourseEngine.PieceStatus, isUnlockedLocked: Bool) -> String {
        switch status {
        case .passed: "已拿下"
        case .practicing: "练习中"
        case .locked: isUnlockedLocked ? "未解锁" : "未开始"
        case .notStarted: "未开始"
        }
    }

    private func pillTextColor(status: CourseEngine.PieceStatus) -> Color {
        switch status {
        case .passed: Color.s08Done
        case .practicing: Color.amber
        case .locked, .notStarted: Color.textMuted
        }
    }

    private func pillFill(status: CourseEngine.PieceStatus) -> Color {
        switch status {
        case .passed: Color.s08DoneBg
        case .practicing: Color.s08ActiveBg
        case .locked, .notStarted: Color.s08MutedBg
        }
    }

    private func pillBorder(status: CourseEngine.PieceStatus, isFocus: Bool) -> Color {
        switch status {
        case .passed: Color.s08Done.opacity(0.3)
        // 真值：焦点行边 /40（行2），其余练习中行边 /30（行4）
        case .practicing: Color.amber.opacity(isFocus ? 0.4 : 0.3)
        case .locked, .notStarted: Color.border
        }
    }

    // MARK: 奖励曲库（空态显示导入卡；有数据后隐藏，去「全部导入」tab）

    private var rewardSegment: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                let pieces = importedPieces
                if pieces.isEmpty {
                    emptyHint("还没有导入的奖励曲。")
                    Button { importTarget = .reward; showImporter = true } label: {
                        importCard
                    }
                    .buttonStyle(.plain)
                }
                ForEach(pieces) { piece in
                    Button {
                        activeSheet = .piece(piece)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(piece.title)
                                    .font(.system(size: 14, weight: .semibold, design: .serif))
                                    .foregroundStyle(Color.textPrimary)
                                Text("手动导入")
                                    .font(.bodySm)
                                    .foregroundStyle(Color.textMuted)
                            }
                            Spacer(minLength: 8)
                            statusPill(status: .notStarted, isUnlockedLocked: false, isFocus: false)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(S08ScaleButtonStyle(scale: 0.99))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: 全部导入（统一入口：选教材/奖励曲库/PDF 资料库）

    private var importsSegment: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("统一导入")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                Text("选择一个分类，导入后将进入对应曲库。")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)

                // 教材
                Button { importTarget = .training; showImporter = true } label: {
                    importChoiceRow(icon: "book.fill", title: "训练教材", desc: "拜厄 / 哈农 / 车尔尼 599 等系统教材")
                }
                // 奖励曲库
                Button { importTarget = .reward; showImporter = true } label: {
                    importChoiceRow(icon: "star.fill", title: "奖励曲库", desc: "课外曲 / 音乐会曲 / 自己加的曲子")
                }
                // PDF 资料库
                Button { importTarget = .pdf; activeSheet = .pdf } label: {
                    importChoiceRow(icon: "doc.richtext", title: "PDF 资料库", desc: "只查看 · 不判分 · 不能跟弹")
                }
            }
            .padding(.horizontal, 20)
            // 原为 16pt；segmentBar 已带 pb-12，故这里只补 4，保持与原稿一致的视觉间距
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private func importChoiceRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.textBody)
                .frame(width: 40, height: 40)
                .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                Text(desc)
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundStyle(Color.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
        .buttonStyle(.plain)
    }

    private enum ImportTarget {
        case training, reward, pdf
    }

    private func iconName(for kind: String) -> String {
        switch kind {
        case "pdf": "doc.richtext"
        case "mid": "music.note"
        default: "music.quarternote.3"
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.bodySm)
            .foregroundStyle(Color.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
    }

    // MARK: 示例曲 featured 卡（M5b：不沉底，放在教材列表顶部）

    private func sampleFeaturedCard(_ entry: CatalogEntry) -> some View {
        Button {
            activeSheet = .entry(entry)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.amber)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(entry.title)
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.textPrimary)
                        Text("示例")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.amber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(Color.amber.opacity(0.5), lineWidth: 1))
                    }
                    Text("示例曲 · 可跟弹可判分（演示用）")
                        .font(.bodySm)
                        .foregroundStyle(Color.amber.opacity(0.9))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.amber.opacity(0.4), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(S08ScaleButtonStyle(scale: 0.99))
    }

    // MARK: 导入虚线卡（真值 §6：全宽、16pt 圆角、1pt 虚线 amber/50、底 amber/4%）

    private var importCard: some View {
        Button {
            showImporter = true
        } label: {
            // HStack 主轴不自动居中，左右各放一枚 Spacer 把「圆托 + 文案」作为整体居中（真值 justify-center）
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .fill(Color.amber.opacity(0.2))
                        .frame(width: 20, height: 20)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.amber)
                }
                Text("导入乐谱（MusicXML / .mxl / .mscz / MIDI）")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Color.amber)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(Color.amber.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.amber.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(S08ScaleButtonStyle(scale: 0.99))
    }

    // MARK: 导入处理（真实校验；失败走 S08b，不吞错）

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            importError = LibraryImportService.ImportError(
                code: .copyFailed, detail: "选择文件失败：\(error.localizedDescription)", hint: "重试或换一个文件。"
            )
        case let .success(urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            importedFileName = url.lastPathComponent
            switch LibraryImportService.importScore(from: url, into: sandboxDocuments()) {
            case let .success(imported):
                CourseEngine.registerImportedScore(imported, in: context)
                importError = nil
            case let .failure(error):
                self.importError = error
            }
        }
    }

    private func sandboxDocuments() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - S08b 导入失败 dialog（不用系统 Alert；承载详情与出路）

struct S08bImportFailDialog: View {
    let fileName: String
    let error: LibraryImportService.ImportError
    let onRetry: () -> Void
    let onHelp: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.scrim.ignoresSafeArea().onTapGesture {}
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.danger)
                    Text("这个文件没能解析")
                        .font(.headlineSm)
                        .foregroundStyle(Color.textPrimary)
                }
                Text("\(fileName)")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 8)

                // 错误详情卡（surface-low + mono 错误码）
                VStack(alignment: .leading, spacing: 6) {
                    Text(error.detail)
                        .font(.bodySm)
                        .leading(18, fontSize: 12)
                        .foregroundStyle(Color.textBody)
                    Text("错误代码：\(error.code.rawValue)")
                        .font(.labelMono(11))
                        .foregroundStyle(Color.danger)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
                .padding(.top, 14)

                Text(error.hint)
                    .font(.bodySm)
                    .leading(18, fontSize: 12)
                    .foregroundStyle(Color.textBody)
                    .padding(.top, 12)

                Text("· 支持 .xml / .mxl / .mscz / .mid\n· PDF 请放进 PDF 资料库（不能跟弹）")
                    .font(.labelSm)
                    .leading(16, fontSize: 11)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 10)

                HStack(spacing: 10) {
                    Button("查看导入帮助", action: onHelp)
                        .font(.bodySm)
                        .foregroundStyle(Color.textBody)
                    Spacer()
                    Button("重新选择文件", action: onRetry)
                        .font(.bodyMd)
                        .foregroundStyle(Color.amber)
                    Button("我知道了", action: onDismiss)
                        .font(.bodyMd)
                        .foregroundStyle(Color.textBody)
                }
                .padding(.top, 18)
            }
            .padding(20)
            .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
            .padding(.horizontal, 36)
        }
    }
}

// MARK: - S08 屏内私有色（同 S07 做法；不写入 Assets、不改全局 Color.success）

fileprivate extension Color {
    /// hex → sRGB（S08 真值局部色专用）
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// 「已拿下」pill 文字/边（真值 #38A169；全局 success 仍为 #7FA97C，不动）
    static let s08Done = Color(hex: 0x38A169)
    /// 「已拿下」pill 底（真值 rgba(56,161,105,0.16)）
    static let s08DoneBg = Color(hex: 0x38A169, opacity: 0.16)
    /// 「练习中」pill 底（真值 rgba(212,162,78,0.16)）
    static let s08ActiveBg = Color(hex: 0xD4A24E, opacity: 0.16)
    /// 「未开始/未解锁」pill 底（真值 rgba(156,148,139,0.12)）
    static let s08MutedBg = Color(hex: 0x9C948B, opacity: 0.12)
    /// 弱化序号/副行/锁（真值 textSubtle #686058）
    static let s08Subtle = Color(hex: 0x686058)
}

// MARK: - S08 交互辅助

/// 真值 active:scale 系列（圆钮 .95 / 行与虚线卡 .99）
fileprivate struct S08ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.99

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 焦点行 6pt 琥珀脉动点（真值 animate-pulse：opacity 1↔0.4 呼吸）
fileprivate struct S08PulseDot: View {
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(Color.amber)
            .frame(width: 6, height: 6)
            .opacity(dim ? 0.4 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

/// 焦点练习中行 pill 内的 4s 周期旋转圆环。
/// 真值 SVG：circle r=10、dasharray 24 / offset 12（周长 62.8，可见弧 38%）、animate-spin 4s。
fileprivate struct S08SpinRing: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.31, to: 0.69)
            .stroke(Color.amber, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
    }
}
