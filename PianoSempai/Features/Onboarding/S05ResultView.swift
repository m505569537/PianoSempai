import SwiftUI
import SwiftData

// MARK: - S05 定级结果 · 你的起点
// 红线 2：P1 只展示真实算出的维度（音准/连贯），节奏/踏板/读谱不编数字、
// 显式声明"P2 完整判分提供"；手型维度缺数据显式声明（红线 5）。
// 红线 3：插入点由 CourseEngine 规则表产出，本页只渲染；文案"建议，不是判决"。

struct S05ResultView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlacementResult.createdAt, order: .reverse) private var results: [PlacementResult]
    @Query private var calibrations: [VelocityCalibration]
    let onGeneratePlan: () -> Void
    let onRetake: () -> Void

    @State private var showRetakeConfirm = false

    private var result: PlacementResult? { results.first }
    private var calibration: VelocityCalibration? {
        calibrations
            .sorted { $0.createdAt > $1.createdAt }
            .first { $0.entityId == result?.velocityCalibrationId }
            ?? calibrations.sorted { $0.createdAt > $1.createdAt }.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("你的起点")
                    .font(.headlineLg)
                    .foregroundStyle(Color.textPrimary)
                if let result {
                    Text("评估完成 · 共 \(result.elapsedSeconds / 60) 分 \(result.elapsedSeconds % 60) 秒")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .monospacedDigit()
                        .padding(.top, 4)
                }
                metricsCard.padding(.top, 20)
                routeCard.padding(.top, 12)
                calibrationCard.padding(.top, 12)

                Button {
                    onGeneratePlan()
                } label: {
                    Text("生成我的第一周计划")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 24)

                Button {
                    showRetakeConfirm = true
                } label: {
                    Text("重新测一次")
                }
                .buttonStyle(GhostButtonStyle())
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.canvas)
        .confirmationDialog("重新评估将替换本次结果（可撤销一次的留痕在 P2 提供）", isPresented: $showRetakeConfirm, titleVisibility: .visible) {
            Button("重新测一次", role: .destructive) { onRetake() }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: 指标卡（诚实呈现：只画真实算出的，其余显式占位）

    private var metricsCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 14) {
                if let result {
                    // 综合参考：规则估算（音准/连贯两维平均），不作过关依据（§9.10 脚注逐字）
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("综合参考")
                            .font(.titleMd)
                            .foregroundStyle(Color.textPrimary)
                        Text("\(result.overallReferenceScore)")
                            .font(.system(size: 28, weight: .regular, design: .serif))
                            .foregroundStyle(Color.amber)
                            .monospacedDigit()
                        Spacer()
                    }
                    Text("综合分仅参考，过关只看连续达标的硬指标。")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)

                    Divider().overlay(Color.border)

                    honestMetricRow(name: "音准", detail: "视奏命中 \(result.sightreadMatched.reduce(0, +))/\(result.sightreadExpected.reduce(0, +)) 音（音序简单匹配）")
                    honestMetricRow(name: "连贯", detail: "停顿 \(result.pauseCounts.reduce(0, +)) 次（相邻音间隔 >2 秒）")

                    // P1 算不出的维度：显式占位，不画假值（红线 2）
                    placeholderMetricRow(name: "节奏")
                    placeholderMetricRow(name: "踏板")
                    placeholderMetricRow(name: "读谱")

                    Text("音准/连贯来自本次视奏的真实 MIDI 采集，按固定规则换算（P2 完整判分将替换为对齐算法，全部六维出分）。")
                        .font(.labelSm)
                        .leading(16, fontSize: 11)
                        .foregroundStyle(Color.textMuted)
                } else {
                    Text("暂无评估结果")
                        .font(.bodyMd)
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
    }

    private func honestMetricRow(name: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(.bodyMd)
                .foregroundStyle(Color.textPrimary)
                .frame(width: 44, alignment: .leading)
            Text(detail)
                .font(.bodySm)
                .foregroundStyle(Color.textBody)
                .monospacedDigit()
        }
    }

    private func placeholderMetricRow(name: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(.bodyMd)
                .foregroundStyle(Color.textMuted)
                .frame(width: 44, alignment: .leading)
            Text("分析将在 P2 提供（当前数据不足以出分，不显示假数字）")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
        }
        .padding(.leading, 2)
        .background(alignment: .leading) {
            // 虚线左边框语义：缺数据维度（S05 spec 占位语言）
            Rectangle().fill(Color.borderInput).frame(width: 2)
        }
    }

    // MARK: 路线卡（建议，不是判决）

    private var routeCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Neko 给你的起点（建议，不是判决）")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                if let result {
                    routeRow("拜厄", "从第 \(result.entryBeyer) 条进入")
                    routeRow("哈农", "从第 \(result.entryHanon) 条开始")
                    routeRow("车尔尼 599", "预计 \(result.projected599Weeks) 周后解锁")
                    Text("插入点由规则表按你的视奏命中率换算（固定规则，可在 docs 查阅）；不是 AI 判决，重测后可变。")
                        .font(.labelSm)
                        .leading(16, fontSize: 11)
                        .foregroundStyle(Color.textMuted)
                }
                // 手型占位（逐字，红线 5）
                Text("手型维度待你录侧拍后补充")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.borderInput).frame(width: 2)
                    }
                    .padding(.leading, -6)
            }
        }
    }

    private func routeRow(_ book: String, _ point: String) -> some View {
        HStack {
            Text(book)
                .font(.bodyMd)
                .foregroundStyle(Color.textBody)
            Spacer()
            Text(point)
                .font(.titleMd)
                .foregroundStyle(Color.amber)
                .monospacedDigit()
        }
    }

    // MARK: 力度校准卡

    @ViewBuilder
    private var calibrationCard: some View {
        NocturneCard {
            if let calibration, calibration.isCalibrated {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.success)
                    // 文案锁定（S05）：真机 = "力度已按你的 V70 个人校准"；模拟源如实标注
                    Text(calibration.deviceName.contains("模拟") ? "力度已按你的个人校准（模拟输入）" : "力度已按你的 V70 个人校准")
                        .font(.bodyMd)
                        .foregroundStyle(Color.success)
                    Spacer()
                    Text("pp \(calibration.ppVelocity) · mf \(calibration.mfVelocity) · ff \(calibration.ffVelocity)")
                        .font(.labelMono(11))
                        .foregroundStyle(Color.textMuted)
                        .monospacedDigit()
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Color.textMuted)
                    Text("力度校准样本不足，本次未完成校准（不影响使用，可在设置里重校）")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
    }
}

#Preview {
    S05ResultView(onGeneratePlan: {}, onRetake: {})
}
