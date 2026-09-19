import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - S26 导出我的全部数据（完整包 zip；Key 永不入包；恢复 = 预览差异 → 确认 → 自动快照）

struct ExportView: View {
    @Environment(\.modelContext) private var context
    @Query private var takes: [Take]
    @Query private var scoreFiles: [ScoreFile]
    @State private var includeVideos = false // 视频默认不勾（红线）
    @State private var exportedURL: URL?
    @State private var showRestorePicker = false
    @State private var restorePreview: ExportService.RestorePreview?
    @State private var restoreSourceURL: URL?
    @State private var restoreDone: String?
    @State private var exportError: String?

    private var videoCount: Int { 0 } // P1 无视频捕获（S15/M8 批次接入）
    private var videoRowDisabled: Bool { videoCount == 0 } // 无视频时置灰（brief）

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("导出我的全部数据")
                        .font(.headlineLg)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.leading, 44)
                        .padding(.top, 8)
                    Text("数据只存在这台手机上。导出一个 zip，换新机时可以完整恢复。")
                        .font(.bodySm)
                        .leading(18, fontSize: 12)
                        .foregroundStyle(Color.textMuted)
                        .padding(.leading, 44)
                        .padding(.top, 4)

                    contentCard.padding(.top, 16)
                    safetyCard.padding(.top, 12)
                    if let exportError {
                        Text(exportError)
                            .font(.bodySm)
                            .foregroundStyle(Color.danger)
                            .padding(.top, 10)
                    }

                    Button {
                        doExport()
                    } label: {
                        Text("导出到「文件」App")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 20)

                    Button {
                        showRestorePicker = true
                    } label: {
                        Text("从备份恢复")
                    }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.canvas)
            .navigationTitle("导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismissSheet() }
                        .foregroundStyle(Color.amber)
                }
            }
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

    // MARK: 内容清单

    private var contentCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("导出内容")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                checkRow("课程状态与路线", included: true, detail: "路线/计划/门禁记录")
                checkRow("Take 元数据", included: true, detail: "\(takes.count) 条")
                checkRow("原始 MIDI", included: true, detail: "只追加事件文件")
                checkRow("乐谱文件", included: true, detail: "\(scoreFiles.filter(\.canFollow).count) 个")
                checkRow("练琴笔记", included: true, detail: "随元数据")
                // 视频行：无视频时置灰（brief），默认不勾
                HStack {
                    Image(systemName: includeVideos ? "checkmark.square.fill" : "square")
                        .foregroundStyle(videoRowDisabled ? Color.textMuted.opacity(0.4) : (includeVideos ? Color.amber : Color.textMuted))
                    Text("视频（\(videoCount) 条）")
                        .foregroundStyle(videoRowDisabled ? Color.textMuted.opacity(0.6) : Color.textBody)
                    Spacer()
                    Text("按保留规则清理")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
                .opacity(videoRowDisabled ? 0.6 : 1)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !videoRowDisabled else { return }
                    includeVideos.toggle()
                }
            }
        }
    }

    private func checkRow(_ label: String, included: Bool, detail: String) -> some View {
        HStack {
            Image(systemName: "checkmark.square.fill")
                .foregroundStyle(Color.amber)
            Text(label)
                .font(.bodyMd)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(detail)
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
        }
    }

    private var safetyCard: some View {
        NocturneCard {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color.amber)
                Text("导出包不含 API Key（Key 只在系统钥匙串里）。")
                    .font(.bodySm)
                    .leading(18, fontSize: 12)
                    .foregroundStyle(Color.textBody)
            }
        }
    }

    // MARK: 动作

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

/// 系统分享面板（存"文件"/AirDrop 给自己）
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
