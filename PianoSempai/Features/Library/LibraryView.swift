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
                segmentBar.padding(.top, 12)
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

    // MARK: 头部

    private var header: some View {
        HStack {
            Text("曲库")
                .font(.displayLg)
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: 三段分段（自定义，非 iOS 灰底）

    private var segmentBar: some View {
        HStack(spacing: 0) {
            ForEach(Segment.allCases, id: \.self) { seg in
                Button {
                    segment = seg
                } label: {
                    VStack(spacing: 6) {
                        Text(seg.rawValue)
                            .font(.titleMd)
                            .foregroundStyle(segment == seg ? Color.amber : Color.textMuted)
                        Rectangle()
                            .fill(segment == seg ? Color.amber : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                filterChips.padding(.top, 12)
                let entries = filteredCatalog
                if entries.isEmpty {
                    emptyHint("这个筛选下还没有曲子")
                }
                // 示例曲 featured：在教材列表顶部单独展示，不沉底
                if let sample = entries.first(where: \.isSample) {
                    sampleFeaturedCard(sample)
                        .padding(.top, 12)
                }
                ForEach(entries.filter { !$0.isSample }) { entry in
                    catalogRow(entry)
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var filteredCatalog: [CatalogEntry] {
        guard let bookFilter else { return catalog }
        return catalog.filter { $0.book == bookFilter }
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach([nil, "拜厄", "哈农", "车尔尼599"], id: \.self) { book in
                NocturneChip(title: book ?? "全部", isSelected: bookFilter == book) {
                    bookFilter = (bookFilter == book) ? nil : book
                }
            }
            Spacer()
        }
    }

    private func catalogRow(_ entry: CatalogEntry) -> some View {
        let status = CourseEngine.catalogStatus(
            book: entry.book, number: entry.number,
            pathState: pathState ?? CoursePathState()
        )
        let projected = CourseEngine.projected599WeeksLabel(pathState: pathState ?? CoursePathState())
        // 谱可用性三态（M5a 纯决策；M5b 诚实呈现）：内置教材条目无谱文件时不冒充样例谱
        let availability = ScoreAvailability.resolve(scoreFile: nil, isSampleEntry: entry.isSample)
        return Button {
            activeSheet = .entry(entry)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.title)
                            .font(.titleMd)
                            .foregroundStyle(status == .locked ? Color.textMuted : Color.textPrimary)
                        if entry.isSample {
                            Text("示例")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.amber)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .overlay(Capsule().strokeBorder(Color.amber.opacity(0.5), lineWidth: 1))
                        }
                    }
                    switch availability {
                    case .unavailable:
                        Text("暂无参考谱 · 可自由弹奏（不判分）")
                            .font(.bodySm)
                            .foregroundStyle(Color.textMuted)
                    case .samplePiece:
                        Text("示例曲 · 可跟弹可判分（演示用）")
                            .font(.bodySm)
                            .foregroundStyle(Color.amber)
                    case .realScore:
                        EmptyView()
                    }
                    if status == .locked, entry.book == "车尔尼599", let projected {
                        Text("约 \(projected) 周后")
                            .font(.bodySm)
                            .foregroundStyle(Color.textMuted)
                            .monospacedDigit()
                    }
                }
                Spacer()
                statusBadge(status)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .opacity(status == .locked ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
        .padding(.top, 8)
    }

    @ViewBuilder
    private func statusBadge(_ status: CourseEngine.PieceStatus) -> some View {
        switch status {
        case .practicing:
            HStack(spacing: 5) {
                Circle().fill(Color.amber).frame(width: 6, height: 6)
                Text("练习中").font(.bodySm).foregroundStyle(Color.amber)
            }
        case .passed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                Text("已拿下").font(.bodySm)
            }
            .foregroundStyle(Color.success)
        case .locked:
            HStack(spacing: 4) {
                Image(systemName: "lock").font(.system(size: 11))
                Text("未开始").font(.bodySm)
            }
            .foregroundStyle(Color.textMuted)
        case .notStarted:
            Text("未开始").font(.bodySm).foregroundStyle(Color.textMuted)
        }
    }

    // MARK: 奖励曲库（空态显示导入卡；有数据后隐藏，去「全部导入」tab）

    private var rewardSegment: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                let pieces = importedPieces
                if pieces.isEmpty {
                    emptyHint("还没有导入的奖励曲。")
                    Button { importTarget = .reward; showImporter = true } label: {
                        importCard
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                ForEach(pieces) { piece in
                    Button {
                        activeSheet = .piece(piece)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(piece.title)
                                    .font(.titleMd)
                                    .foregroundStyle(Color.textPrimary)
                                Text("手动导入")
                                    .font(.bodySm)
                                    .foregroundStyle(Color.textMuted)
                            }
                            Spacer()
                            statusBadge(.notStarted)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 56)
                    }
                    .buttonStyle(.plain)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
                    .padding(.top, 8)
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
            .padding(.top, 16)
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
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
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
                            .font(.titleMd)
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
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.card.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.amber.opacity(0.35), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 导入虚线卡

    private var importCard: some View {
        Button {
            showImporter = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.amber)
                Text("导入乐谱")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                Text("MusicXML / .mxl / .mscz / MIDI")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.amber.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
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
