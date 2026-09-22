import SwiftUI

// 示范/试听音源署名（B11）。随 app 分发的 MuseScore_General.sf2 为 MIT 授权，
// 署名义务：Frank Wen、Michael Cowgill、S. Christian Collins 等。
// 优先展示 Bundle 内随包的授权全文；缺失时给最小署名，不空白。
struct SoundFontAttributionSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var licenseText: String {
        let candidates = [
            Bundle.main.url(forResource: "MuseScore_General_License", withExtension: "md"),
        ].compactMap { $0 }
        if let url = candidates.first,
           let text = try? String(contentsOf: url, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return Self.fallback
    }

    private static let fallback = """
    MuseScore General SoundFont

    Licensed under the MIT License.

    Copyright / 作者：
    Frank Wen（FluidR3 GM，本音源的基础）
    Michael Cowgill（GeneralUser GS，修正与改进）
    S. Christian Collins（额外修正）
    及 MuseScore 社区贡献者。

    完整 MIT 授权文本见随包的
    MuseScore_General_License.md。
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("示范与试听使用的钢琴音色来自开源音源 MuseScore General（MIT 授权）。")
                        .font(.bodyMd)
                        .foregroundStyle(Color.textBody)
                    Text(licenseText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .background(Color.canvas)
            .navigationTitle("音源署名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.foregroundStyle(Color.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
