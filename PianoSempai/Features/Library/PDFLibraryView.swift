import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - S10 PDF 资料库（只读查看器；红线：不做 OMR、PDF 不判分）
//
// 对齐真值：/tmp/stitch-truth/revised/S10.md（390 逻辑宽）。
// 视觉：serif 导航标题 + 搜索钮（真实本地过滤）、琥珀细边 callout、双段切换
// （我的 PDF / 如何获取可练谱）、真实页数与导入日期、琥珀虚线导入钮、渐变吸底脚注。
// 数据红线：文件名/页数/导入日期一律取真实 ScoreFile；页数由 PDFKit 后台预热，
// 读不到就省略或显「—」，不写死、不编造。

struct PDFLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var pdfFiles: [ScoreFile]

    /// 双段切换（真值 §3.3）：左「我的 PDF」实底琥珀选中，右「如何获取可练谱」未选 muted。
    enum Tab: String, CaseIterable {
        case mine = "我的 PDF"
        case guide = "如何获取可练谱"
    }

    @State private var tab: Tab = .mine
    @State private var viewing: ScoreFile?
    /// F2 同款：搜索钮展开输入框，本地按文件名过滤（不新建 service、不写库、不联网）
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var showImporter = false
    /// 导入失败不吞：选择器结果里的失败文件在此汇总，alert 明示（同 S08b 契约）
    @State private var importFailures: [String] = []
    /// 页数缓存：PDFKit 真实读取（后台预热）。键缺失 = 读不到 → 行内省略页数。
    @State private var pageCounts: [PersistentIdentifier: Int] = [:]

    private var pdfs: [ScoreFile] {
        pdfFiles.filter { $0.kind == "pdf" }.sorted { $0.importedAt > $1.importedAt }
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 真实本地过滤：按文件名子串（大小写不敏感）；空词显全部。
    private var visiblePdfs: [ScoreFile] {
        guard !searchQuery.isEmpty else { return pdfs }
        return pdfs.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    /// 预热键：PDF 集合变化（导入/删除）才重读页数
    private var warmupKey: [PersistentIdentifier] {
        pdfs.map(\.persistentModelID)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    header
                    // 搜索输入只作用于「我的 PDF」段（同 F2：其余段不出现无用控件）
                    if isSearching, tab == .mine {
                        searchField
                            .padding(.bottom, 12)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            callout
                            segmentBar
                            switch tab {
                            case .mine: mineTab
                            case .guide: guideTab
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        // 底部留白让开吸底 footer（渐变 28 + 脚注约 32），末行不被永久遮住
                        .padding(.bottom, 72)
                    }
                    .background(Color.canvas)
                }
                .background(Color.canvas)
                footer
            }
            .navigationBarHidden(true)
            .sheet(item: $viewing) { file in
                PDFViewerScreen(file: file)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .alert("部分 PDF 导入失败", isPresented: importFailuresPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importFailures.joined(separator: "\n\n"))
            }
        }
        .task(id: warmupKey) {
            await warmPageCounts()
        }
    }

    private var importFailuresPresented: Binding<Bool> {
        Binding(
            get: { !importFailures.isEmpty },
            set: { if !$0 { importFailures = [] } }
        )
    }

    // MARK: 导航头（真值 §3.1：返回 40×40 圆钮 + serif 18pt 标题 + 搜索 40×40 圆钮）

    private var header: some View {
        HStack(spacing: 8) {
            s10CircleButton(icon: "chevron.left", tint: Color.textPrimary) {
                dismiss()
            }
            Spacer()
            Text("PDF 资料库")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .tracking(0.5)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            // 真值右侧是搜索（不是 ＋）：琥珀表示当前在搜索态
            s10CircleButton(icon: "magnifyingglass", tint: isSearching ? Color.amber : Color.textPrimary) {
                // 搜索只过滤 PDF 列表；在指引段点时先切回「我的 PDF」
                if tab != .mine { tab = .mine }
                isSearching.toggle()
                if !isSearching { searchText = "" }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// 40×40 圆钮（真值 §3.1）：card/80 底 + 1pt border；active scale .99。
    /// hover 底 #262220 是桌面端交互，本 App 为 iPhone，无 hover 态，故不实现。
    private func s10CircleButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Color.card.opacity(0.8), in: Circle())
                .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(S10ScaleButtonStyle(scale: 0.99))
    }

    /// 搜索输入框（真实过滤标题；空 = 显全部）
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Color.textMuted)
            TextField("搜索 PDF 文件名", text: $searchText)
                .font(.system(size: 13))
                .foregroundStyle(Color.textPrimary)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
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

    // MARK: 顶部提示 Callout（真值 §3.2：全周琥珀/30 细边，无左缘竖条）

    /// 逐字文案，其中「MusicXML」琥珀 medium（真值 §3.2）：用 AttributedString 的 run 级
    /// 样式做行内强调（Text 拼接 `+` 只接受 Text，无法只给一个词上色）。
    private var calloutText: Text {
        var text = AttributedString("PDF 仅可查看，不支持跟弹判分。想要可练的谱，请转换为 ")
        text.foregroundColor = Color.textMuted
        text.font = .system(size: 12.5)
        var emphasis = AttributedString("MusicXML")
        emphasis.foregroundColor = Color.amber
        emphasis.font = .system(size: 12.5, weight: .medium)
        text.append(emphasis)
        text.append(AttributedString("。"))
        return Text(text)
    }

    private var callout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 19))
                .foregroundStyle(Color.amber)
                .padding(.top, 2)
            calloutText
                .leading(18.75, fontSize: 12.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.amber.opacity(0.3), lineWidth: 1))
    }

    // MARK: 双段切换（真值 §3.3：两等宽段 + 真实计数徽标）

    private var segmentBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { item in
                let selected = tab == item
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 6) {
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.canvas : Color.textMuted)
                        if selected, item == .mine {
                            // 真实 pdfs.count（不是真值示例「4」）
                            Text("\(pdfs.count)")
                                .font(.system(size: 11, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Color.canvas)
                                .padding(.horizontal, 6)
                                .background(Color.canvas.opacity(0.2), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
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
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
    }

    // MARK: 段一：我的 PDF（真实列表 + 虚线导入钮）

    private var mineTab: some View {
        VStack(spacing: 0) {
            if visiblePdfs.isEmpty {
                if pdfs.isEmpty {
                    // 诚实空态：无 PDF（含搜索为空时）
                    VStack(spacing: 8) {
                        Text("还没有 PDF 文件")
                            .font(.titleMd)
                            .foregroundStyle(Color.textPrimary)
                        Text("用下面的按钮把 PDF 谱子存进来当资料库，或切到「如何获取可练谱」看获取指引。")
                            .font(.bodySm)
                            .foregroundStyle(Color.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    // 搜索无命中（同样诚实：没有匹配，不补假数据）
                    VStack(spacing: 8) {
                        Text("没找到匹配的 PDF")
                            .font(.titleMd)
                            .foregroundStyle(Color.textPrimary)
                        Text("换个关键词试试，或清空搜索显示全部。")
                            .font(.bodySm)
                            .foregroundStyle(Color.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                pdfList
            }
            importButton
                .padding(.top, 8)
        }
    }

    private var pdfList: some View {
        VStack(spacing: 10) {
            ForEach(visiblePdfs) { file in
                Button {
                    viewing = file
                } label: {
                    HStack(spacing: 12) {
                        pdfIcon
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            Text(subtitle(for: file))
                                .font(.bodySm)
                                .foregroundStyle(Color.textMuted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.textMuted.opacity(0.7))
                    }
                    .padding(14)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
                    // hover 变 #D4A24E/40 是桌面端交互；iPhone 无 hover 态，故只画静息边框
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(S10ScaleButtonStyle(scale: 0.99))
            }
        }
    }

    /// 40×40 r8 图标盒（真值 §3.4）：#1C1917 底 + border，琥珀 PDF 字形 + 8pt 琥珀小字
    private var pdfIcon: some View {
        ZStack {
            Color.canvas
            VStack(spacing: 0) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.amber)
                Text("PDF")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.amber.opacity(0.8))
                    .offset(y: -2)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
    }

    /// 副信息：真实「N 页 · 导入于 M月D日」。页数读不到 / importedAt 零值 → 省略，不编。
    private func subtitle(for file: ScoreFile) -> String {
        var parts: [String] = []
        if let pages = pageCounts[file.persistentModelID] {
            parts.append("\(pages) 页")
        }
        if let date = Self.importDateText(file.importedAt) {
            parts.append("导入于 \(date)")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private static let importDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    /// 真实导入日期，格式「M月D日」；零值（字段不可得）返回 nil → 省略，不画假日期。
    private static func importDateText(_ date: Date) -> String? {
        guard date.timeIntervalSince1970 > 0 else { return nil }
        return importDateFormatter.string(from: date)
    }

    // MARK: 导入虚线按钮（真值 §3.5：1pt dashed 琥珀/60 + 琥珀/5 底）

    private var importButton: some View {
        Button {
            showImporter = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.amber)
                Text("导入 PDF（仅查看）")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.amber)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.amber.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.amber.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(S10ScaleButtonStyle(scale: 0.99))
    }

    // MARK: 段二：如何获取可练谱（沿用现有诚实指引，不另编）

    private var guideTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("如何获取可练的谱子")
                .font(.titleMd)
                .foregroundStyle(Color.textPrimary)
            Text("· 用 Mac 端 MuseScore / Audiveris（开源 OMR）把 PDF 转成 MusicXML")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
            Text("· 找现成的 MusicXML / .mscz 工程文件")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
            Text("· 转好后回到「曲库 → 导入乐谱」")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border, lineWidth: 1))
    }

    // MARK: Footer（真值 §3.6：自下而上 bg → bg/95 → 透明）

    private var footer: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.canvas.opacity(0), Color.canvas.opacity(0.95), Color.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            Text("PDF 不会出现在训练教材与判分流程中")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(Color.canvas)
        }
        .background(Color.canvas)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: 页数预热（PDFKit 真实读取，后台执行；读不到的键不入表）

    private func warmPageCounts() async {
        let targets = pdfs.map { (id: $0.persistentModelID, url: SandboxPaths.resolve($0.fileURL)) }
        let loaded = await Task.detached(priority: .utility) { () -> [PersistentIdentifier: Int] in
            var out: [PersistentIdentifier: Int] = [:]
            for target in targets {
                guard let url = target.url, let document = PDFDocument(url: url) else { continue }
                let count = document.pageCount
                if count > 0 { out[target.id] = count }
            }
            return out
        }.value
        pageCounts.merge(loaded) { _, new in new }
    }

    // MARK: 导入处理（复用 LibraryImportService 的 PDF 分支；多选；失败不吞）

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            importFailures = ["选择文件失败：\(error.localizedDescription)\n提示：重试或换一个文件。"]
        case let .success(urls):
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            var failures: [String] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                switch LibraryImportService.importScore(from: url, into: documents) {
                case let .success(imported):
                    // PDF 走 pdfs/ + canFollow=false（红线：不 OMR、不建 Piece）
                    CourseEngine.registerImportedScore(imported, in: context)
                case let .failure(error):
                    failures.append("\(url.lastPathComponent)：\(error.detail)\n提示：\(error.hint)")
                }
            }
            importFailures = failures
        }
    }
}

/// 按压缩放按钮样式（真值 active scale 0.99；S08ScaleButtonStyle 是 LibraryView 的 fileprivate，此处不跨文件借用）
private struct S10ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.99

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 单个 PDF 查看页（PDFKit 只读；无任何判分/录音入口）
struct PDFViewerScreen: View {
    @Environment(\.dismiss) private var dismiss
    let file: ScoreFile

    var body: some View {
        NavigationStack {
            Group {
                if let url = SandboxPaths.resolve(file.fileURL) {
                    PDFKitRepresentable(url: url)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    Text("文件不存在（可能已被移动或删除）")
                        .font(.bodySm)
                        .foregroundStyle(Color.danger)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(file.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// 沙盒相对路径解析（data-model §3：DB 只存相对路径）
enum SandboxPaths {
    static func resolve(_ relativePath: String) -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

struct PDFKitRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
