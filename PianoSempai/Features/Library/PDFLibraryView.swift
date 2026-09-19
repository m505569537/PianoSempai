import PDFKit
import SwiftData
import SwiftUI

// MARK: - S10 PDF 资料库（只读查看器；红线：不做 OMR、PDF 不判分）

struct PDFLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var pdfFiles: [ScoreFile]

    @State private var viewing: ScoreFile?

    private var pdfs: [ScoreFile] {
        pdfFiles.filter { $0.kind == "pdf" }.sorted { $0.importedAt > $1.importedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 双声明（brief：明确不判分；S10 spec）
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.amber)
                        Text("PDF 只做资料查看，不做判分分析；认真练的曲子请用 MuseScore 转成 MusicXML 导入。")
                            .font(.bodySm)
                            .leading(18, fontSize: 12)
                            .foregroundStyle(Color.textBody)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 12)

                    if pdfs.isEmpty {
                        VStack(spacing: 8) {
                            Text("还没有 PDF 文件")
                                .font(.titleMd)
                                .foregroundStyle(Color.textPrimary)
                            Text("把现有 PDF 谱子存进来当资料库，或看下面的获取指引。")
                                .font(.bodySm)
                                .foregroundStyle(Color.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }

                    ForEach(pdfs) { file in
                        Button {
                            viewing = file
                        } label: {
                            HStack {
                                Image(systemName: "doc.richtext")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.textBody)
                                Text(file.title)
                                    .font(.bodyMd)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(file.importedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.labelSm)
                                    .foregroundStyle(Color.textMuted)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 56)
                        }
                        .buttonStyle(.plain)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
                        .padding(.top, 8)
                    }

                    // 如何获取可练谱（S08b 帮助承接点；转换工具不进 P1，PRD M2 Q2）
                    NocturneCard {
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
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color.canvas)
            .navigationTitle("PDF 资料库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.amber)
                }
            }
            .sheet(item: $viewing) { file in
                PDFViewerScreen(file: file)
            }
        }
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
