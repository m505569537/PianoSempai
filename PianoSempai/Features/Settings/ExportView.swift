import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - S26 导出我的全部数据（完整包 zip；Key 永不入包；恢复 = 预览差异 → 确认 → 自动快照）
//
// 真值：/tmp/stitch-truth/revised/S26.md（390 逻辑宽；介绍卡 / 导出内容清单卡 / 导出格式卡 /
// 安全卡 + 底部 dock）。本任务只重排视觉与补真实体积，不改导出/恢复机制：
// buildExport / previewRestore / makePreRestoreSnapshot / restore / ShareSheet 全部原样保留。
//
// 诚实数据：清单里的体积一律 FileManager 实测（Documents 下 midi / scores / pdfs / video
// 目录递归真实字节）+ metadata.json 编码后字节，不写死任何示例数字；
// 没有独立文件的分项（课程/笔记/Take 元数据，都合并在 metadata.json 内）显「—」而不是编数字。

/// 导出格式（真值 §4.3）。「仅报告 PDF」当前没有全量实现（现有只有月报单份 PDF）：
/// 选中即禁用主 CTA 并如实说明，不假导出。
private enum ExportFormat {
    case fullPackage
    case pdfOnly
}

/// 实测体积快照（nil = 尚未量好，界面显「—」）
private struct ExportSizeReport {
    var metadataBytes = 0
    var midiBytes = 0
    var midiFileCount = 0
    var scoreBytes = 0
    var scoreFileCount = 0
    var videoBytes = 0
    var videoFileCount = 0
}

struct ExportView: View {
    @Environment(\.modelContext) private var context
    @State private var includeVideos = false // 视频默认不勾（红线）
    @State private var format: ExportFormat = .fullPackage
    @State private var exportedURL: URL?
    @State private var showRestorePicker = false
    @State private var restorePreview: ExportService.RestorePreview?
    @State private var restoreSourceURL: URL?
    @State private var restoreDone: String?
    @State private var exportError: String?
    /// 真实体积（FileManager 实测；出现时由 .task 量好）
    @State private var measured: ExportSizeReport?

    private var videoCount: Int { 0 } // P1 无视频捕获（S15/M8 批次接入）
    private var videoRowDisabled: Bool { videoCount == 0 } // 无视频时置灰（brief）
    /// 只有完整包模式能导出（「仅报告 PDF」未支持 → 主 CTA 置灰不可点）
    private var canExport: Bool { format == .fullPackage }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        introCard
                        contentListCard
                        formatCard
                        safetyCard
                        if let exportError {
                            Text(exportError)
                                .font(.bodySm)
                                .foregroundStyle(Color.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                }
                .background(Color.canvas)
                bottomDock
            }
            .background(Color.canvas)
            .navigationBarHidden(true) // 标题排在自绘导航头里（serif 19pt bold）
            .task { measured = Self.measure(context: context) }
            .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [UTType.zip, UTType.data], allowsMultipleSelection: false) { result in
                handleRestorePick(result)
            }
            .sheet(isPresented: Binding(
                get: { exportedURL != nil },
                set: { if !$0 { exportedURL = nil } }
            )) {
                if let exportedURL {
                    ShareSheet(items: [exportedURL])
                }
            }
            .alert("确认恢复？", isPresented: Binding(
                get: { restorePreview != nil },
                set: { if !$0 { restorePreview = nil; restoreSourceURL = nil } }
            )) {
                Button("取消", role: .cancel) { restorePreview = nil; restoreSourceURL = nil }
                Button("恢复（自动先生成快照）") { performRestore() }
            } message: {
                if let preview = restorePreview {
                    Text("将覆盖：\(preview.takes) 条 take · \(preview.gateEvents) 条门禁记录 · \(preview.pieces) 首曲目 · \(preview.files) 个文件。恢复前会自动在本机生成快照。")
                }
            }
            .alert("恢复完成", isPresented: Binding(
                get: { restoreDone != nil },
                set: { if !$0 { restoreDone = nil } }
            )) {
                Button("好的") {}
            } message: {
                Text(restoreDone ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    @Environment(\.dismiss) private var dismiss
    private func dismissSheet() { dismiss() }

    // MARK: 导航头（真值 §3：px-5 py-3、下边 border/60；返回 36×36 琥珀 chevron；19pt serif bold 标题）

    private var header: some View {
        HStack(spacing: 4) {
            Button { dismissSheet() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.amber)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("完成")
            Text("导出我的全部数据")
                .font(.system(size: 19, weight: .bold, design: .serif))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 12) // 真值 -ml-2：返回钮左缘距屏边 12
        .padding(.trailing, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.border.opacity(0.6))
                .frame(height: 1)
        }
    }

    // MARK: 介绍卡（真值 §4.1：card / 边 / r16 / p16；32×32 r12 amber10% 云图标）

    private var introCard: some View {
        S26Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.amber)
                    .frame(width: 32, height: 32)
                    .background(Color.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 2) // 真值 mt-0.5
                Text("你的所有数据只存在这台手机上。导出为一个 zip，可用于备份或换新机恢复。")
                    .font(.system(size: 13.5))
                    .leading(22, fontSize: 13.5)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 导出内容清单卡（真值 §4.2：card / 边 / r16 / overflow-hidden）

    private var contentListCard: some View {
        S26Card(padding: 0) {
            VStack(spacing: 0) {
                listHeader
                includedRow("课程与路线状态", value: dash)
                includedRow("Take 元数据与分析结果", value: dash)
                includedRow("原始 MIDI 事件流（\(midiFileCount) 条）", value: rowSize(measured?.midiBytes))
                includedRow("乐谱文件（\(scoreFileCount) 个）", value: rowSize(measured?.scoreBytes))
                includedRow("练琴笔记", value: dash)
                videoRow
                videoToggleRow
            }
        }
    }

    /// 卡头：左「导出内容」uppercase muted；右 amber「共 N 项已勾选 · 约 N MB」（N 全真实）
    private var listHeader: some View {
        HStack(spacing: 8) {
            Text("导出内容")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .tracking(0.65) // 真值 uppercase tracking-wider（0.05em）
            Spacer(minLength: 8)
            Text("共 \(includedCount) 项已勾选 · 约 \(totalSizeLabel)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.amber)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.border.opacity(0.7))
                .frame(height: 1)
        }
    }

    /// 前 5 行：恒已选。ExportService.buildExport 不支持按项排除，
    /// 所以这里不给取消交互（不造假），只如实显成固定已选行。
    private func includedRow(_ title: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.amber)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.canvas) // 真值：琥珀底上深色对勾（#1C1917）
            }
            .frame(width: 20, height: 20)
            Text(title)
                .font(.bodyMd)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Text(value)
                .font(.labelMono(13))
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48) // 真值 §6：整行最小高约 48
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.border.opacity(0.6))
                .frame(height: 1)
        }
    }

    /// 视频行（真值 §4.2）：底 #211E1C/60、20×20 方形 r4 空框、muted 文案；
    /// videoCount 恒 0（P1 无视频捕获）→ 整行置灰、不给勾选。
    private var videoRow: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.textMuted.opacity(0.5), lineWidth: 1)
                .frame(width: 20, height: 20)
                .padding(.top, 2) // 真值 mt-0.5
            VStack(alignment: .leading, spacing: 2) {
                Text("视频（\(videoCount) 条，可选）")
                    .font(.bodyMd)
                    .foregroundStyle(Color.textMuted)
                Text("体积较大，默认不包含")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.textMuted.opacity(0.7))
            }
            Spacer(minLength: 8)
            Text(videoSizeLabel)
                .font(.labelMono(13))
                .foregroundStyle(Color.textMuted.opacity(0.7))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.s26VideoRow.opacity(0.6))
        .opacity(videoRowDisabled ? 0.6 : 1) // 无视频：置灰不可勾
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.border.opacity(0.6))
                .frame(height: 1)
        }
    }

    /// 「包含视频」开关行（真值 §4.2）：底 #231F1D；无视频时 Toggle 禁用，不允许打开
    private var videoToggleRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("包含视频")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Text("每曲仅保留最近 8 条")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.textMuted)
            }
            Spacer(minLength: 8)
            Toggle("包含视频", isOn: $includeVideos)
                .labelsHidden()
                .tint(Color.amber)
                .disabled(videoRowDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.s26ToggleRow)
    }

    // MARK: 导出格式卡（真值 §4.3：segmented surface 底 / p4 / r12 / border70）

    private var formatCard: some View {
        S26Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("导出格式")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .tracking(0.65)
                HStack(spacing: 8) {
                    formatOption(.fullPackage, title: "完整包（可恢复）")
                    formatOption(.pdfOnly, title: "仅报告 PDF")
                }
                .padding(4)
                .background(Color.canvas, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.border.opacity(0.7), lineWidth: 1)
                )
                if format == .pdfOnly {
                    // 如实说明：全量报告 PDF 没有实现，不假导出
                    Text("全量报告 PDF 尚未支持")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func formatOption(_ option: ExportFormat, title: String) -> some View {
        let isSelected = format == option
        return Button {
            format = option
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? Color.amber : Color.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                isSelected ? Color.card : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.amber.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: 安全卡（真值 §4.4：左 3pt amber 竖条 / r16 / p14）

    private var safetyCard: some View {
        S26Card(padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.amber)
                    .padding(.top, 2) // 真值 mt-0.5
                Text("导出包不含 API Key；分享 zip 前请确认接收方可信，里面有你的全部弹奏记录。")
                    .font(.system(size: 12.5))
                    .leading(20, fontSize: 12.5)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 16, bottomLeadingRadius: 16,
                bottomTrailingRadius: 0, topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.amber)
            .frame(width: 3)
        }
    }

    // MARK: 底部 dock（真值 §5：px-5 pt-3 pb-6、surface→透明渐变）

    private var bottomDock: some View {
        VStack(spacing: 12) {
            Button {
                doExport()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                    Text("导出到“文件” App")
                }
            }
            .buttonStyle(S26ExportButtonStyle(isEnabled: canExport))
            .disabled(!canExport)

            Button {
                showRestorePicker = true
            } label: {
                Text("从备份恢复")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color.canvas, location: 0),
                    .init(color: Color.canvas, location: 0.5),
                    .init(color: Color.clear, location: 1)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }

    // MARK: 体积（真实计算，禁止写死示例数字）

    /// 无独立文件的分项（课程/笔记/Take 元数据都合并在包内 metadata.json，无法精确拆分）
    private var dash: String { "—" }

    /// 已勾选条数：前 5 项恒包含（导出本就含）；视频仅在开启且真有文件时计入
    private var includedCount: Int {
        5 + (includeVideos && (measured?.videoFileCount ?? 0) > 0 ? 1 : 0)
    }

    /// 真实参与导出的字节之和（metadata.json + midi + scores + pdfs；视频仅在开启时计入）
    private var totalBytes: Int {
        guard let measured else { return 0 }
        return measured.metadataBytes + measured.midiBytes + measured.scoreBytes
            + (includeVideos ? measured.videoBytes : 0)
    }

    private var totalSizeLabel: String {
        guard measured != nil else { return "—" }
        return totalBytes == 0 ? "约 0 MB" : "约 " + Self.byteLabel(totalBytes)
    }

    private var videoSizeLabel: String {
        guard let bytes = measured?.videoBytes, bytes > 0 else { return "0 MB" }
        return Self.byteLabel(bytes)
    }

    /// 分项体积：未量好或无独立文件显「—」（不编数字）
    private func rowSize(_ bytes: Int?) -> String {
        guard let bytes else { return "—" }
        return Self.byteLabel(bytes)
    }

    private var midiFileCount: Int { measured?.midiFileCount ?? 0 }
    private var scoreFileCount: Int { measured?.scoreFileCount ?? 0 }

    /// 实测体积：沙盒目录真实字节（FileManager 递归，只数普通文件）+ metadata.json 编码后字节
    private static func measure(context: ModelContext) -> ExportSizeReport {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let metadata = ExportService.collectMetadata(context: context)
        let midi = folderSizeAndCount(docs.appendingPathComponent("midi", isDirectory: true))
        let scores = folderSizeAndCount(docs.appendingPathComponent("scores", isDirectory: true))
        let pdfs = folderSizeAndCount(docs.appendingPathComponent("pdfs", isDirectory: true))
        let video = folderSizeAndCount(docs.appendingPathComponent("video", isDirectory: true))
        return ExportSizeReport(
            metadataBytes: (try? JSONEncoder.iso.encode(metadata))?.count ?? 0,
            midiBytes: midi.bytes,
            midiFileCount: midi.count,
            // 乐谱项 = scores + pdfs（两者都会进包，真值无独立 PDF 行）
            scoreBytes: scores.bytes + pdfs.bytes,
            scoreFileCount: scores.count + pdfs.count,
            videoBytes: video.bytes,
            videoFileCount: video.count
        )
    }

    /// 递归统计目录下普通文件的真实字节与文件数（量不到返回 0）
    private static func folderSizeAndCount(_ url: URL) -> (bytes: Int, count: Int) {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return (0, 0)
        }
        var bytes = 0
        var count = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            bytes += values.fileSize ?? 0
            count += 1
        }
        return (bytes, count)
    }

    /// 字节 → KB/MB（1024 换算；0 显「0 KB」；MB 取一位小数，整数不带小数点）
    private static func byteLabel(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 KB" }
        let kb = Double(bytes) / 1024
        guard kb >= 1024 else { return "\(Int(kb.rounded())) KB" }
        let mb = (kb / 1024 * 10).rounded() / 10
        if mb == mb.rounded() { return "\(Int(mb)) MB" }
        return String(format: "%.1f MB", mb)
    }

    // MARK: 动作（导出/恢复机制原样，不改）

    private func doExport() {
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            exportedURL = try ExportService.buildExport(
                baseDir: documents, includeVideos: includeVideos, context: context
            )
            exportError = nil
        } catch {
            exportError = "导出失败：\(error.localizedDescription)" // 不吞错
        }
    }

    private func handleRestorePick(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // 先拷到沙盒（恢复中要重复读取）
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString).zip")
        do {
            try FileManager.default.copyItem(at: url, to: local)
            restoreSourceURL = local
            restorePreview = try ExportService.previewRestore(from: local)
        } catch {
            exportError = "备份文件无法读取：\(error.localizedDescription)"
        }
    }

    private func performRestore() {
        guard let source = restoreSourceURL else { return }
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            // S26：自动先在本机生成恢复前快照
            _ = try ExportService.makePreRestoreSnapshot(baseDir: documents, context: context)
            let report = try ExportService.restore(from: source, into: documents, in: context)
            try? context.save()
            restoreDone = "已恢复 \(report.restoredTakes) 条 take、\(report.restoredPieces) 首曲目、\(report.restoredFiles) 个文件。恢复前快照保留在「文件/exports」。"
            restorePreview = nil
            restoreSourceURL = nil
        } catch {
            restorePreview = nil
            restoreSourceURL = nil
            exportError = "恢复失败：\(error.localizedDescription)" // 不吞错
        }
    }
}

// MARK: - 本屏私有组件（S26 真值；NocturneCard 固定 r8 且被多屏复用，不为本屏改全局组件）

/// S26 卡片（真值 §4）：bg `#262220`、1pt `#332D29` 边、圆角 **16**、轻投影。
/// `padding: 0` 给清单卡用（行自带 px16，并需要 overflow-hidden 裁掉深色行底的圆角外溢）。
fileprivate struct S26Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16)) // 真值 overflow-hidden
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.2), radius: 6, y: 2)
    }
}

/// 底部主 CTA（真值 §5）：全宽高 48、r12、amber 底、15pt semibold 深色字；disabled 置灰不可点
fileprivate struct S26ExportButtonStyle: ButtonStyle {
    var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.canvas : Color.textMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isEnabled ? (configuration.isPressed ? Color.amberBright : Color.amber) : Color.borderInput)
            )
            .shadow(color: isEnabled ? Color.amber.opacity(0.1) : .clear, radius: isEnabled ? 12 : 0, y: isEnabled ? 4 : 0)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 真值字面量色（DesignSystem token 未覆盖，仅本文件使用）
fileprivate extension Color {
    /// 视频清单行底 #211E1C（S26 真值，/60 透明）
    static let s26VideoRow = Color(red: 0x21 / 255, green: 0x1E / 255, blue: 0x1C / 255)
    /// 「包含视频」开关行底 #231F1D（S26 真值）
    static let s26ToggleRow = Color(red: 0x23 / 255, green: 0x1F / 255, blue: 0x1D / 255)
}

/// 系统分享面板（存"文件"/AirDrop 给自己）
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
