import SwiftData
import SwiftUI

// MARK: - S13b 标记疑似谱面错误（Sheet；标记不扣分、不影响过关）

struct S13bMarkSheet: View {
    let scoreName: String
    let measure: Int
    /// 提交回调（视图层负责落库）
    let onSubmit: (_ type: String, _ note: String) -> Void
    @Environment(\.dismiss) private var dismiss

    enum MarkType: String, CaseIterable {
        case note = "note"
        case rhythm = "rhythm"
        case fingering = "fingering"
        var label: String {
            switch self {
            case .note: "音符/和弦不对"
            case .rhythm: "节奏不对"
            case .fingering: "指法标记可疑"
            }
        }
    }

    @State private var selected: MarkType = .note
    @State private var noteText = ""
    @Query private var existingMarks: [ScoreErrorMark]

    /// 同小节重复提交合并计数（spec：按次数显示）
    private var existingCount: Int {
        existingMarks.filter { $0.scoreName == scoreName && $0.measure == measure }
            .map(\.occurrenceCount).max() ?? 0
    }

    var body: some View {
        NocturneBottomDrawer {
            HStack {
                Text("标记疑似谱面错误")
                    .font(.headlineSm)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Text("\(scoreName) · 第\(measure)小节")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 6)

            // 纸白谱条占位（红虚线圈住疑点——示意；真实截图渲染 M6b+）
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.scorePaper)
                .frame(height: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.danger, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .padding(10)
                )
                .overlay(alignment: .center) {
                    Text("第 \(measure) 小节")
                        .font(.labelMono(12))
                        .foregroundStyle(Color.scoreInk)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

            Text("这个小节总是弹成与谱面不符的音？可能是谱子印错了，也可能是听谱习惯。")
                .font(.bodySm)
                .leading(19, fontSize: 12)
                .foregroundStyle(Color.textBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            Text("这个标记不会扣分，也不会影响过关。")
                .font(.bodySm)
                .foregroundStyle(Color.amber)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            Text("哪里不对？")
                .font(.bodyMd)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
            HStack(spacing: 8) {
                ForEach(MarkType.allCases, id: \.rawValue) { tag in
                    NocturneChip(title: tag.label, isSelected: selected == tag) {
                        selected = tag
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            HStack {
                Text("备注（选填）")
                    .font(.bodyMd)
                    .foregroundStyle(Color.textBody)
                TextField("选填", text: $noteText)
                    .font(.bodyMd)
                    .foregroundStyle(Color.textPrimary)
                    .padding(8)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderInput, lineWidth: 1))
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if existingCount > 0 {
                Text("这一小节你已标记 \(existingCount) 次，再次提交将合并计数。")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            HStack(spacing: 12) {
                Button("取消") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle(cornerRadius: 8))
                Button {
                    onSubmit(selected.rawValue, noteText)
                    dismiss()
                } label: {
                    Text("提交标记")
                }
                .buttonStyle(PrimaryButtonStyle(cornerRadius: 8))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
    }
}
