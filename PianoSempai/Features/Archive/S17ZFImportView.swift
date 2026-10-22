import PhotosUI
import SwiftData
import SwiftUI
import UIKit

// MARK: - S17 导入月度录像（尼康 Zf 相册）
// 布局真值：docs/design-reference/screens/S17-zf-import/spec.md；
// 口径：docs/decisions/0012-zf-monthly-video-import.md（特别是「候选列表口径」补充）。
// 红线：只复制原片（不转码、不上传、不判分）；读不到拍摄日期不猜；失败/取消由 Stage A 回滚；
//       本视图不碰 VideoAttachmentStore / NocturneBottomDrawer。

// MARK: - 纯格式化（可单测）

enum S17Formatting {

    /// 字节 → 约数文案（十进制：1.8 GB / 580 MB / 24 GB）
    static func byteSize(_ bytes: Int64) -> String {
        let clamped = max(0, bytes)
        if clamped >= 1_000_000_000 {
            return trimmedDecimal(Double(clamped) / 1_000_000_000) + " GB"
        }
        if clamped >= 1_000_000 {
            return String(format: "%.0f MB", (Double(clamped) / 1_000_000).rounded())
        }
        if clamped >= 1_000 {
            return String(format: "%.0f KB", (Double(clamped) / 1_000).rounded())
        }
        return "\(clamped) B"
    }

    /// 中文时长（12分40秒 / 45秒；整分为「N分」）
    static func durationChinese(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let minutes = total / 60
        let rest = total % 60
        if minutes == 0 { return "\(rest)秒" }
        if rest == 0 { return "\(minutes)分" }
        return "\(minutes)分\(rest)秒"
    }

    /// 月份汇总行：「已选 3 段 · 共 12分40秒 · 约 1.8 GB」
    static func selectionSummary(count: Int, totalDurationSec: Int, totalBytes: Int64) -> String {
        "已选 \(count) 段 · 共 \(durationChinese(totalDurationSec)) · 约 \(byteSize(totalBytes))"
    }

    /// 导入进度：「正在导入 2/3」
    static func importProgress(completed: Int, total: Int) -> String {
        "正在导入 \(completed)/\(total)"
    }

    /// CTA：「导入所选 3 段」
    static func importCTA(count: Int) -> String {
        "导入所选 \(count) 段"
    }

    /// 准备中行文案（真实进度，不编造）
    static func prepareStatusText(progress: Double?) -> String {
        guard let progress, progress > 0 else { return "准备中…" }
        let percent = Int((min(max(progress, 0), 1) * 100).rounded())
        return "准备中 \(percent)%"
    }

    /// 分辨率 tag（1080p / 4K；无元数据 = —）
    static func resolutionLabel(pixelHeight: Int) -> String {
        guard pixelHeight > 0 else { return "—" }
        return pixelHeight >= 2160 ? "4K" : "\(pixelHeight)p"
    }

    /// 候选行标题（与 Take.title 同口径：「9/14 Zf 录像」；无日期不猜）
    static func rowTitle(for metadata: ZFAssetMetadata, calendar: Calendar = .current) -> String {
        guard let date = metadata.creationDate else { return "Zf 录像" }
        return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date)) Zf 录像"
    }

    /// 「2026 年 9 月」
    static func monthTitle(_ monthKey: String) -> String {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else {
            return monthKey
        }
        return "\(year) 年 \(month) 月"
    }

    /// 行内阻塞原因（替换元信息，不弹窗）
    static func blockReasonText(_ reason: ZFImportBlockReason) -> String {
        switch reason {
        case .missingCreationDate: "读不到拍摄日期"
        case .tooLarge: "超过 2 GB"
        case .alreadyImported: "已导入"
        case .insufficientSpace: "剩余空间不足"
        }
    }

    /// 底部/汇总的整句阻塞说明（点名原因，不连弹）
    static func blockDetailText(_ reason: ZFImportBlockReason) -> String {
        switch reason {
        case let .tooLarge(bytes): "有视频超过 2 GB（\(byteSize(bytes))），无法导入"
        case let .insufficientSpace(needed, available):
            "剩余空间不足：需要 \(byteSize(needed))，可用 \(byteSize(available))"
        case .missingCreationDate: "有视频读不到拍摄日期，无法归月"
        case .alreadyImported: "有视频已经导入过"
        }
    }

    private static func trimmedDecimal(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}

// MARK: - 月份聚合（可单测）

struct S17MonthSummary: Identifiable, Equatable {
    let monthKey: String
    let candidateCount: Int
    let totalDurationSec: Int
    let totalBytes: Int64

    var id: String { monthKey }
}

enum S17MonthGrouping {

    /// 按月聚合：有勾选时只统计勾选；无勾选时统计全部候选。
    /// 排序 = 字节降序（主导月在最前；同字节按月份新→旧），最多 maxSections 个。
    static func summaries(candidates: [ZFImportCandidate],
                          selectedIds: Set<String>,
                          calendar: Calendar = .current,
                          maxSections: Int = 3) -> [S17MonthSummary] {
        let relevant = selectedIds.isEmpty
            ? candidates
            : candidates.filter { selectedIds.contains($0.id) }

        var grouped: [String: [ZFImportCandidate]] = [:]
        for candidate in relevant {
            guard let key = ZFImportPlanner.monthKey(for: candidate.metadata.creationDate, calendar: calendar)
            else { continue }
            grouped[key, default: []].append(candidate)
        }

        let summaries = grouped.map { key, items in
            S17MonthSummary(
                monthKey: key,
                candidateCount: items.count,
                totalDurationSec: items.reduce(0) { $0 + Int($1.metadata.durationSec.rounded()) },
                totalBytes: items.reduce(0) { $0 + $1.byteSize }
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalBytes != rhs.totalBytes { return lhs.totalBytes > rhs.totalBytes }
            return lhs.monthKey > rhs.monthKey
        }
        return Array(summaries.prefix(max(0, maxSections)))
    }

    /// 主导月（字节最多的月份；无选中时看全部候选）
    static func dominantMonthKey(candidates: [ZFImportCandidate],
                                 selectedIds: Set<String>,
                                 calendar: Calendar = .current) -> String? {
        summaries(candidates: candidates, selectedIds: selectedIds, calendar: calendar).first?.monthKey
    }
}

// MARK: - 勾选状态（可单测：阻塞项不可选）

struct S17ImportSelection: Equatable {
    private(set) var selected: Set<String>

    init(selected: Set<String> = []) {
        self.selected = selected
    }

    var count: Int { selected.count }
    var isEmpty: Bool { selected.isEmpty }

    func contains(_ id: String) -> Bool { selected.contains(id) }

    /// 阻塞项（planner reason 非 nil）不可选；已选中的再点即取消
    mutating func toggle(_ id: String, reasons: [String: ZFImportBlockReason]) {
        if selected.contains(id) {
            selected.remove(id)
            return
        }
        guard reasons[id] == nil else { return }
        selected.insert(id)
    }

    mutating func clear() {
        selected.removeAll()
    }

    /// 预检变化后剔除已不可选的项
    mutating func prune(selectable: Set<String>) {
        selected.formIntersection(selectable)
    }

    /// CTA 可点：至少 1 段，且选中的每一段都没有阻塞原因
    func isImportEnabled(reasons: [String: ZFImportBlockReason]) -> Bool {
        !selected.isEmpty && selected.allSatisfy { reasons[$0] == nil }
    }
}

// MARK: - 权限档位 → 页面形态（可单测）

enum S17LibraryMode: Equatable, Sendable {
    case loading
    case full      // 可枚举最近 30 条视频
    case limited   // 只给 PhotosPicker，不伪造列表
    case denied    // 空态 + 去系统设置

    static func from(_ access: PhotoLibraryAccess) -> S17LibraryMode {
        switch access {
        case .full: .full
        case .limited: .limited
        case .denied: .denied
        }
    }

    var showsRecentList: Bool { self == .full }
    var showsPicker: Bool { self == .limited }
    var showsSettingsButton: Bool { self == .denied }
}

// MARK: - 导入服务 seam（测试注入假服务）

@MainActor
protocol S17ImportRunning {
    func importCandidates(_ candidates: [ZFImportCandidate],
                          pieceId: UUID?,
                          sourceURLs: [String: URL],
                          in context: ModelContext,
                          isCancelled: @escaping () -> Bool,
                          progress: (@MainActor (Int, Int) -> Void)?) async throws -> [Take]
}

struct S17LiveImportRunner: S17ImportRunning {
    func importCandidates(_ candidates: [ZFImportCandidate],
                          pieceId: UUID?,
                          sourceURLs: [String: URL],
                          in context: ModelContext,
                          isCancelled: @escaping () -> Bool,
                          progress: (@MainActor (Int, Int) -> Void)?) async throws -> [Take] {
        try await ZFImportService.importCandidates(
            candidates,
            pieceId: pieceId,
            sourceURLs: sourceURLs,
            in: context,
            isCancelled: isCancelled,
            progress: progress
        )
    }
}

enum S17ImportPhase: Equatable {
    case idle
    case importing(completed: Int, total: Int)
}

/// 取消旗标（Stage A 的 isCancelled 闭包读它）
final class S17CancelFlag {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}

// MARK: - 页面模型（库读取 / 准备 / 预检 / 导入）

@MainActor
final class S17ImportModel: ObservableObject {

    enum Preparation: Equatable {
        case waiting
        case preparing
        case preparingProgress(Double)
        case ready
        case failed(String)
    }

    struct Row: Identifiable, Equatable {
        let metadata: ZFAssetMetadata
        var byteSize: Int64 = 0
        var tempURL: URL?
        var preparation: Preparation = .waiting

        var id: String { metadata.assetIdentifier }
    }

    @Published private(set) var mode: S17LibraryMode = .loading
    @Published private(set) var rows: [Row] = []
    @Published private(set) var selection = S17ImportSelection()
    @Published private(set) var reasons: [String: ZFImportBlockReason] = [:]
    @Published private(set) var availableBytes: Int64 = 0
    @Published private(set) var notice: String?
    @Published private(set) var phase: S17ImportPhase = .idle
    @Published private(set) var isPreparing = false
    @Published private(set) var thumbnails: [String: UIImage] = [:]

    private let library: PhotoLibraryAccessing
    private let runner: S17ImportRunning
    private var existingIdentifiers: Set<String> = []
    private var tempDirectory: URL?
    private var prepareFlag: S17CancelFlag?
    private var preparationTask: Task<Void, Never>?
    private var cancelFlag: S17CancelFlag?
    private var didLoad = false

    init(library: PhotoLibraryAccessing = PhotoLibraryService(),
         runner: S17ImportRunning? = nil) {
        self.library = library
        self.runner = runner ?? S17LiveImportRunner()
    }

    var candidates: [ZFImportCandidate] {
        rows.map { ZFImportCandidate(id: $0.id, metadata: $0.metadata, byteSize: $0.byteSize) }
    }

    var selectedRows: [Row] {
        rows.filter { selection.contains($0.id) }
    }

    var selectedCandidates: [ZFImportCandidate] {
        selectedRows.map { ZFImportCandidate(id: $0.id, metadata: $0.metadata, byteSize: $0.byteSize) }
    }

    var isImporting: Bool {
        if case .importing = phase { return true }
        return false
    }

    var canImport: Bool {
        guard !isPreparing, !isImporting else { return false }
        let selected = selectedRows
        guard !selected.isEmpty else { return false }
        return selected.allSatisfy { $0.preparation == .ready && reasons[$0.id] == nil }
    }

    /// 选中项里仍存在的阻塞（预检变化的安全网；正常路径下阻塞行选不中）
    var selectionBlockText: String? {
        let selected = selectedRows
        guard !selected.isEmpty else { return nil }
        for row in selected {
            if let reason = reasons[row.id] { return S17Formatting.blockDetailText(reason) }
        }
        if selected.contains(where: { row in
            if case .failed = row.preparation { return true }
            return false
        }) {
            return "有视频准备失败，无法导入"
        }
        if selected.contains(where: { $0.preparation != .ready }) {
            return "视频还在准备中，稍等再导入"
        }
        return nil
    }

    /// 预检失败的整体说明（空间不足点名 needed/available；行内已逐条标原因）
    var precheckNotice: String? {
        for reason in reasons.values {
            if case let .insufficientSpace(needed, available) = reason {
                return S17Formatting.blockDetailText(.insufficientSpace(needed: needed, available: available))
            }
        }
        return nil
    }

    // MARK: 读取相册

    func loadLibrary(in context: ModelContext) async {
        guard !didLoad else { return }
        didLoad = true
        availableBytes = Self.currentAvailableBytes()
        existingIdentifiers = Self.existingAssetIdentifiers(in: context)

        mode = .loading
        _ = await library.requestReadAccess()
        mode = S17LibraryMode.from(library.accessLevel())

        guard mode == .full else {
            refreshPrecheck()
            return
        }
        replaceRows(with: await library.recentVideos(limit: 30))
        refreshPrecheck()
        prepareAll()
    }

    /// PhotosPicker（limited 口径）选完后追加候选
    func addCandidates(_ metadataList: [ZFAssetMetadata]) {
        let existing = Set(rows.map(\.id))
        let fresh = metadataList.filter { !existing.contains($0.assetIdentifier) }
        guard !fresh.isEmpty else { return }
        rows.append(contentsOf: fresh.map { Row(metadata: $0) })
        rows.sort(by: Self.recencySort)
        notice = nil
        refreshPrecheck()
        prepareAll()
    }

    func metadata(forIdentifier id: String) async -> ZFAssetMetadata? {
        await library.metadata(forIdentifiers: [id])[id]
    }

    func toggleSelection(_ id: String) {
        notice = nil
        guard let row = rows.first(where: { $0.id == id }), row.preparation == .ready else { return }
        selection.toggle(id, reasons: reasons)
    }

    func clearSelection() {
        selection.clear()
    }

    func showNotice(_ text: String) {
        notice = text
    }

    // MARK: 准备（导出原片到临时目录，拿真实字节数）

    func prepareAll() {
        guard preparationTask == nil else { return }
        guard rows.contains(where: { $0.preparation != .ready }) else { return }
        prepareFlag = S17CancelFlag()
        isPreparing = true
        preparationTask = Task { [weak self] in
            await self?.runPreparation()
            guard let self else { return }
            self.preparationTask = nil
            self.isPreparing = false
        }
    }

    func cancelPreparation() {
        prepareFlag?.cancel()
        preparationTask?.cancel()
    }

    private func runPreparation() async {
        let directory = tempDirectory ?? Self.makeTempDirectory()
        tempDirectory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for id in rows.map(\.id) {
            if prepareFlag?.isCancelled ?? true { break }
            guard let row = rows.first(where: { $0.id == id }) else { continue }
            if row.preparation == .ready { continue }
            if case .failed = row.preparation { continue }

            setPreparation(.preparing, for: id)
            do {
                let url = try await library.exportOriginal(identifier: id, to: directory) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.setProgress(progress, for: id)
                    }
                }
                let bytes = Self.fileSize(url)
                setRow(id) { row in
                    row.tempURL = url
                    row.byteSize = bytes
                    row.preparation = .ready
                }
                refreshPrecheck()
            } catch let error as PhotoLibraryError where error == .cancelled {
                setPreparation(.waiting, for: id)
                break
            } catch {
                let text = Self.prepareFailureText(error)
                setRow(id) { $0.preparation = .failed(text) }
            }
        }

        if prepareFlag?.isCancelled == true {
            for row in rows where row.preparation == .preparing || isProgress(row.preparation) {
                setPreparation(.waiting, for: row.id)
            }
            removeTempFiles()
            notice = "已取消准备"
        }
    }

    private func setPreparation(_ preparation: Preparation, for id: String) {
        setRow(id) { $0.preparation = preparation }
    }

    private func setProgress(_ progress: Double, for id: String) {
        setRow(id) { row in
            guard row.tempURL == nil else { return }
            row.preparation = .preparingProgress(min(max(progress, 0), 1))
        }
    }

    private func setRow(_ id: String, _ mutate: (inout Row) -> Void) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        mutate(&rows[index])
    }

    private func refreshPrecheck() {
        let spaceLimit = availableBytes > 0 ? availableBytes : Int64.max
        reasons = ZFImportPlanner.blockReasons(
            candidates: candidates,
            existingAssetIdentifiers: existingIdentifiers,
            availableBytes: spaceLimit
        )
        let selectable = Set(
            rows.filter { reasons[$0.id] == nil && $0.preparation == .ready }.map(\.id)
        )
        selection.prune(selectable: selectable)
    }

    // MARK: 缩略图

    func loadThumbnail(for id: String) async {
        guard thumbnails[id] == nil else { return }
        guard let image = await library.thumbnail(forIdentifier: id, maxPixelSize: 160) else { return }
        thumbnails[id] = image
    }

    // MARK: 导入

    /// 返回成功导入条数；nil = 取消或失败（notice 说明原因）
    func importCandidates(_ candidates: [ZFImportCandidate],
                          sourceURLs: [String: URL],
                          pieceId: UUID?,
                          in context: ModelContext) async -> Int? {
        guard !isImporting, !candidates.isEmpty else { return nil }
        let flag = S17CancelFlag()
        cancelFlag = flag
        notice = nil
        phase = .importing(completed: 0, total: candidates.count)
        do {
            let takes = try await runner.importCandidates(
                candidates,
                pieceId: pieceId,
                sourceURLs: sourceURLs,
                in: context,
                isCancelled: { flag.isCancelled },
                progress: { [weak self] completed, total in
                    self?.phase = .importing(completed: completed, total: total)
                }
            )
            phase = .idle
            cancelFlag = nil
            availableBytes = Self.currentAvailableBytes()
            return takes.count
        } catch let error as PhotoLibraryError where error == .cancelled {
            phase = .idle
            cancelFlag = nil
            notice = "已取消，未导入任何视频"
            return nil
        } catch {
            phase = .idle
            cancelFlag = nil
            notice = "导入失败，请重试"
            return nil
        }
    }

    func cancelImport() {
        cancelFlag?.cancel()
    }

    // MARK: 临时文件清理

    func cleanupTemps() {
        preparationTask?.cancel()
        preparationTask = nil
        removeTempFiles()
    }

    private func removeTempFiles() {
        guard let tempDirectory else { return }
        try? FileManager.default.removeItem(at: tempDirectory)
        self.tempDirectory = nil
    }

    // MARK: 工具

    private func replaceRows(with metadataList: [ZFAssetMetadata]) {
        rows = metadataList.map { Row(metadata: $0) }.sorted(by: Self.recencySort)
    }

    private static func recencySort(_ lhs: Row, _ rhs: Row) -> Bool {
        let left = lhs.metadata.creationDate ?? .distantPast
        let right = rhs.metadata.creationDate ?? .distantPast
        if left != right { return left > right }
        return lhs.id < rhs.id
    }

    private static func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("zf-import-\(UUID().uuidString)", isDirectory: true)
    }

    private static func fileSize(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value else { return 0 }
        return size
    }

    private static func existingAssetIdentifiers(in context: ModelContext) -> Set<String> {
        let takes = (try? context.fetch(FetchDescriptor<Take>())) ?? []
        return Set(takes.compactMap(\.sourceAssetIdentifier))
    }

    /// 本机剩余空间（重要用量口径）；取不到 = 0（页面显「未知」，不猜）
    static func currentAvailableBytes() -> Int64 {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else { return 0 }
        return Int64(capacity)
    }

    private static func prepareFailureText(_ error: Error) -> String {
        guard let photoError = error as? PhotoLibraryError else { return "准备失败" }
        switch photoError {
        case .iCloudUnavailable: return "iCloud 下载失败"
        case .notFound: return "相册里找不到这条视频"
        case .denied: return "没有相册读取权限"
        case .cancelled: return "已取消"
        case .exportFailed: return "准备失败"
        }
    }

    private func isProgress(_ preparation: Preparation) -> Bool {
        if case .preparingProgress = preparation { return true }
        return false
    }
}

// MARK: - S17 页面

struct S17ZFImportView: View {
    /// 成功后回调（N = 已导入段数）；由档案页弹 toast
    var onImported: (Int) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Piece.title) private var pieces: [Piece]

    @StateObject private var model = S17ImportModel()
    @State private var pieceId: UUID?
    @State private var previewItem: S17PreviewItem?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                navBar.padding(.horizontal, 4)
                introCard

                switch model.mode {
                case .loading:
                    loadingState
                case .denied:
                    deniedState
                case .full, .limited:
                    monthCards
                    candidateSection
                    amberInfoCard
                    pieceRow
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard !didLoad else { return }
            didLoad = true
            await model.loadLibrary(in: context)
        }
        // 预览是另一层 cover，不能当作本页退出：只在没有预览时清理临时文件
        .onDisappear {
            if previewItem == nil { model.cleanupTemps() }
        }
        .fullScreenCover(item: $previewItem) { item in
            ZFVideoPreviewView(item: item)
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPicked(items) }
        }
    }

    // MARK: 导航栏

    private var navBar: some View {
        HStack(spacing: 12) {
            Button {
                model.cleanupTemps()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 36, height: 36)
                    .background(Color.card, in: Circle())
                    .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
            }
            .buttonStyle(S17PressStyle())
            .accessibilityLabel("返回")

            Text("导入月度录像")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .tracking(1)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.amber)
                    .frame(width: 6, height: 6)
                Text("尼康 Zf")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    // MARK: 说明卡

    private var introCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "camera")
                .font(.system(size: 17))
                .foregroundStyle(Color.amber)
                .frame(width: 28, height: 28)
                .background(Color.canvas, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
                .padding(.top, 2)

            introText
                .font(.system(size: 12.5))
                .foregroundStyle(Color.textMuted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
    }

    private var introText: Text {
        Text("每月一次，从相册挑选 ")
            + Text("Zf").foregroundColor(Color.textBody).fontWeight(.medium)
            + Text(" 拍的练琴视频存档。这些视频永久保留在本机，只供你回看，不上传、不判分。")
    }

    // MARK: 月份汇总卡（主导月全量；最多 3 个月）

    @ViewBuilder
    private var monthCards: some View {
        let summaries = S17MonthGrouping.summaries(
            candidates: model.candidates,
            selectedIds: model.selection.selected
        )
        ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
            monthCard(summary, showsStorage: index == 0)
        }
    }

    private func monthCard(_ summary: S17MonthSummary, showsStorage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(S17Formatting.monthTitle(summary.monthKey))
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: 8)
                if showsStorage {
                    storageBadge
                }
            }
            if !model.selection.isEmpty {
                Text(S17Formatting.selectionSummary(
                    count: summary.candidateCount,
                    totalDurationSec: summary.totalDurationSec,
                    totalBytes: summary.totalBytes
                ))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.amber)
                .monospacedDigit()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
    }

    private var storageBadge: some View {
        Text(model.availableBytes > 0
             ? "本机剩余空间 \(S17Formatting.byteSize(model.availableBytes))"
             : "本机剩余空间未知")
            .font(.system(size: 11))
            .foregroundStyle(Color.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.canvas, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.border.opacity(0.8), lineWidth: 1))
    }

    // MARK: 候选列表

    private var candidateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("相册候选项 (\(model.rows.count))")
                    .font(.system(size: 11, weight: .medium))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Color.textMuted)
                Spacer(minLength: 8)
                Text("按录制时间排序")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, 4)

            if model.mode == .limited {
                limitedPickerRow
            }

            if model.rows.isEmpty {
                emptyCandidates
            } else {
                ForEach(model.rows) { row in
                    candidateRow(row)
                }
            }
        }
    }

    private var limitedPickerRow: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .videos) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 13))
                    Text("选择视频")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.amber)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.amber.opacity(0.3), lineWidth: 1))
            }
            Text("仅能访问你勾选的照片")
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var emptyCandidates: some View {
        VStack(spacing: 6) {
            Text(model.mode == .limited ? "还没有勾选任何视频。" : "相册里最近没有视频。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
            Text(model.mode == .limited
                 ? "点「选择视频」从相册勾选，列表只显示你选中的条目。"
                 : "先录一段练习，再回来导入。")
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted.opacity(0.8))
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(Color.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func candidateRow(_ row: S17ImportModel.Row) -> some View {
        let reason = model.reasons[row.id]
        let isSelected = model.selection.contains(row.id)
        let selectable = reason == nil && row.preparation == .ready && !model.isPreparing && !model.isImporting

        return HStack(spacing: 12) {
            checkbox(isSelected: isSelected, selectable: selectable)

            rowThumbnail(row)

            VStack(alignment: .leading, spacing: 2) {
                Text(S17Formatting.rowTitle(for: row.metadata))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textMuted)
                    .lineLimit(1)
                rowMetaLine(row, reason: reason)
            }

            Spacer(minLength: 0)

            Image(systemName: "play.circle")
                .font(.system(size: 18))
                .foregroundStyle(Color.textMuted.opacity(0.4))
                .contentShape(Rectangle())
                .onTapGesture { preview(row) }
                .accessibilityLabel("预览视频")
        }
        .padding(12)
        .background(
            Color.card.opacity(isSelected ? 1 : 0.6),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.amber.opacity(0.4) : Color.border, lineWidth: 1)
        )
        .opacity(isSelected ? 1 : 0.75)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if selectable { model.toggleSelection(row.id) }
        }
    }

    private func checkbox(isSelected: Bool, selectable: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.amber : Color.canvas)
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isSelected ? Color.clear : (selectable ? Color.borderInput : Color.border),
                    lineWidth: 1
                )
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.canvas)
            }
        }
        .frame(width: 20, height: 20)
        .opacity(selectable || isSelected ? 1 : 0.6)
    }

    private func rowThumbnail(_ row: S17ImportModel.Row) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = model.thumbnails[row.id] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "video")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.surface)
                }
            }
            .frame(width: 64, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))

            if row.metadata.durationSec > 0 {
                Text(VideoUIFormatting.timecode(Int(row.metadata.durationSec.rounded())))
                    .font(.labelMono(9))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 2))
                    .padding(3)
            }
        }
        .frame(width: 64, height: 44)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { preview(row) }
        .task(id: row.id) { await model.loadThumbnail(for: row.id) }
    }

    @ViewBuilder
    private func rowMetaLine(_ row: S17ImportModel.Row, reason: ZFImportBlockReason?) -> some View {
        if let reason {
            Text(S17Formatting.blockReasonText(reason))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.textMuted)
        } else {
            switch row.preparation {
            case .waiting, .preparing:
                Text("准备中…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.textMuted)
            case let .preparingProgress(progress):
                Text(S17Formatting.prepareStatusText(progress: progress))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.textMuted)
                    .monospacedDigit()
            case let .failed(text):
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.danger)
            case .ready:
                HStack(spacing: 8) {
                    Text(VideoUIFormatting.timecode(Int(row.metadata.durationSec.rounded())))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.amber)
                        .monospacedDigit()
                    Circle()
                        .fill(Color.border)
                        .frame(width: 3, height: 3)
                    Text(S17Formatting.resolutionLabel(pixelHeight: row.metadata.pixelHeight))
                        .font(.labelMono(10))
                        .foregroundStyle(Color.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.canvas, in: RoundedRectangle(cornerRadius: 2))
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.border, lineWidth: 1))
                    Text("约 \(S17Formatting.byteSize(row.byteSize))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.textMuted)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: 琥珀提示卡

    private var amberInfoCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .foregroundStyle(Color.amber)
                .padding(.top, 2)
            Text("导入后可在档案里按月回看；手型标注需要你主动发起，不会自动分析。")
                .font(.system(size: 12))
                .foregroundStyle(Color.textMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 2, bottomLeadingRadius: 2,
                bottomTrailingRadius: 12, topTrailingRadius: 12,
                style: .continuous
            )
            .fill(Color.card)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.amber)
                .frame(width: 2)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 2, bottomLeadingRadius: 2,
                        bottomTrailingRadius: 0, topTrailingRadius: 0,
                        style: .continuous
                    )
                )
        }
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 2, bottomLeadingRadius: 2,
                bottomTrailingRadius: 12, topTrailingRadius: 12,
                style: .continuous
            )
            .strokeBorder(Color.border, lineWidth: 1)
        )
    }

    // MARK: 曲目（可选）

    private var pieceRow: some View {
        Menu {
            Button("不挂曲目") { pieceId = nil }
            ForEach(pieces) { piece in
                Button(piece.title.isEmpty ? "未命名曲目" : piece.title) {
                    pieceId = piece.entityId
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.amber)
                Text("挂到曲目（可选）")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textBody)
                Spacer(minLength: 8)
                Text(selectedPieceTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.border, lineWidth: 1))
        }
    }

    private var selectedPieceTitle: String {
        guard let pieceId,
              let piece = pieces.first(where: { $0.entityId == pieceId }) else { return "不挂曲目" }
        return piece.title.isEmpty ? "未命名曲目" : piece.title
    }

    // MARK: 底部固定操作区

    private var footer: some View {
        VStack(spacing: 8) {
            if let notice = model.notice {
                noticeRow(notice)
            }
            if let blocked = model.selectionBlockText {
                Text(blocked)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let precheck = model.precheckNotice {
                Text(precheck)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if case let .importing(completed, total) = model.phase {
                importProgressRow(completed: completed, total: total)
            } else {
                if model.isPreparing {
                    preparingRow
                }
                actionRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color.canvas)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.border.opacity(0.6))
                .frame(height: 1)
        }
    }

    /// 准备阶段的真实进度（逐条导出；可整体取消，取消会删除临时文件）
    private var preparingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.amber)
            Text("正在准备视频（导出原片到临时目录）")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.textMuted)
            Spacer(minLength: 8)
            Button("取消准备") {
                model.cancelPreparation()
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color.danger)
        }
    }

    private func importProgressRow(completed: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            ProgressView(value: Double(completed), total: Double(max(total, 1)))
                .tint(Color.amber)
            Text(S17Formatting.importProgress(completed: completed, total: total))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textBody)
                .monospacedDigit()
                .fixedSize()
            Button("取消") {
                model.cancelImport()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.danger)
        }
        .frame(height: 48)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button("全不选") {
                model.clearSelection()
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(model.selection.isEmpty ? Color.textMuted.opacity(0.5) : Color.textMuted)
            .frame(height: 48)
            .padding(.horizontal, 16)
            .disabled(model.selection.isEmpty)

            Button {
                startImport()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 19))
                    Text(model.isPreparing ? "准备中…" : S17Formatting.importCTA(count: model.selection.count))
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(0.5)
                }
                .foregroundStyle(model.canImport ? Color.canvas : Color.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    model.canImport ? Color.amber : Color.borderInput,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .buttonStyle(S17PressStyle())
            .disabled(!model.canImport)
        }
    }

    // MARK: 状态页

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color.amber)
            Text("正在读取相册…")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private var deniedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(Color.textMuted)
            Text("没有相册读取权限")
                .font(.titleMd)
                .foregroundStyle(Color.textPrimary)
            Text("导入需要读取你选中的视频；不浏览整库、不上传。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
            Button {
                openSystemSettings()
            } label: {
                Text("去系统设置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.canvas)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.amber, in: Capsule())
            }
            .buttonStyle(S17PressStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func noticeRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(Color.danger)
            Text(text)
                .font(.bodySm)
                .foregroundStyle(Color.danger)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 行为

    private func preview(_ row: S17ImportModel.Row) {
        guard let url = row.tempURL else {
            model.showNotice("视频还在准备中，稍后再预览")
            return
        }
        previewItem = S17PreviewItem(
            id: row.id,
            url: url,
            title: S17Formatting.rowTitle(for: row.metadata)
        )
    }

    private func startImport() {
        guard model.canImport else { return }
        let candidates = model.selectedCandidates
        let sourceURLs = Dictionary(
            uniqueKeysWithValues: model.selectedRows.compactMap { row in
                row.tempURL.map { (row.id, $0) }
            }
        )
        Task {
            if let count = await model.importCandidates(
                candidates,
                sourceURLs: sourceURLs,
                pieceId: pieceId,
                in: context
            ) {
                onImported(count)
                model.cleanupTemps()
                dismiss()
            }
        }
    }

    private func loadPicked(_ items: [PhotosPickerItem]) async {
        var metadataList: [ZFAssetMetadata] = []
        for item in items {
            guard let id = item.itemIdentifier else { continue }
            if let metadata = await model.metadata(forIdentifier: id) {
                metadataList.append(metadata)
            } else {
                // 元数据取不到也不伪造：按「读不到拍摄日期」禁用（planner 会拦）
                metadataList.append(ZFAssetMetadata(
                    assetIdentifier: id,
                    creationDate: nil,
                    durationSec: 0,
                    pixelWidth: 0,
                    pixelHeight: 0
                ))
            }
        }
        model.addCandidates(metadataList)
        pickerItems = []
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - 按压缩放（S17 真值 0.99；沿用档案页 0.95 手势手感）

private struct S17PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
