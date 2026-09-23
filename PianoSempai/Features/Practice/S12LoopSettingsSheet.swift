import SwiftUI

// MARK: - S12 段落循环设置（底部抽屉；校验走 LoopService，非法区间拒绝开始）

struct S12LoopSettingsSheet: View {
    @ObservedObject var session: PracticeSession
    let totalMeasures: Int
    @Environment(\.dismiss) private var dismiss

    @State private var start: Int = 1
    @State private var end: Int = 8
    @State private var mode: LoopMode = .loop
    @State private var gapSec: Int = 3
    @State private var countIn: Bool = true
    @State private var initialized = false

    private var rangeValid: Bool {
        LoopService.isValid(start: start, end: end, totalMeasures: totalMeasures)
    }

    var body: some View {
        NocturneBottomDrawer {
            DrawerGrabHandle()

            HStack {
                Text("段落循环")
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
            .padding(.top, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 起/终点步进器
                    HStack(spacing: 32) {
                        measureStepper("起点", value: $start, min: 1, max: end - 1)
                        measureStepper("终点", value: $end, min: start + 1, max: totalMeasures)
                        Spacer()
                    }
                    .padding(.top, 16)

                    measureBand.padding(.top, 14)

                    quickChips.padding(.top, 12)

                    Text("循环方式（单选）")
                        .font(.bodyMd)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.top, 20)
                    modeRow(.loop, "逐遍循环（练完停 3 秒再来）")
                    modeRow(.adaptiveUp, "达标后自动 +5 BPM")
                    modeRow(.adaptiveDown, "崩了自动 −5 BPM（连崩 2 遍暂停，提示休息）")

                    if mode == .adaptiveDown {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.danger)
                            Text("连崩 2 遍会提示休息（陈述建议，不强制）。")
                                .font(.bodySm)
                                .foregroundStyle(Color.danger)
                        }
                        .padding(10)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.danger.opacity(0.5), lineWidth: 1))
                        .padding(.top, 8)
                    }

                    HStack {
                        Text("循环间隔")
                            .font(.bodyMd)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        stepperControls(value: $gapSec, min: 1, max: 10)
                        Text("\(gapSec) 秒")
                            .font(.bodyMd)
                            .foregroundStyle(Color.textBody)
                            .monospacedDigit()
                            .frame(minWidth: 40)
                    }
                    .padding(.top, 16)

                    Button {
                        countIn.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: countIn ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16))
                                .foregroundStyle(countIn ? Color.amber : Color.textMuted)
                            Text("开始前 1 小节节拍器预备拍")
                                .font(.bodyMd)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            HStack(spacing: 12) {
                Button("取消") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle(cornerRadius: 8))
                Button {
                    applyAndStart()
                } label: {
                    Text(rangeValid ? "开始循环练习" : "区间无效")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: rangeValid, cornerRadius: 8))
                .disabled(!rangeValid)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            start = session.loopConfig.startMeasure
            end = session.loopConfig.endMeasure
            mode = session.loopConfig.mode
            gapSec = session.loopConfig.gapSec
            countIn = session.loopConfig.countIn
        }
    }

    // MARK: 部件

    private func measureStepper(_ label: String, value: Binding<Int>, min minValue: Int, max maxValue: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.bodyMd)
                .foregroundStyle(Color.textBody)
            stepperControls(value: value, min: minValue, max: maxValue)
            Text("\(value.wrappedValue)")
                .font(.labelMono(16, weight: .medium))
                .foregroundStyle(Color.amber)
                .monospacedDigit()
                .frame(minWidth: 26)
        }
    }

    private func stepperControls(value: Binding<Int>, min minValue: Int, max maxValue: Int) -> some View {
        HStack(spacing: 6) {
            stepButton("minus") { value.wrappedValue = max(minValue, value.wrappedValue - 1) }
                .disabled(value.wrappedValue <= minValue)
            stepButton("plus") { value.wrappedValue = min(maxValue, value.wrappedValue + 1) }
                .disabled(value.wrappedValue >= maxValue)
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textBody)
                .frame(width: 28, height: 28)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    /// 小节条带：totalMeasures 等分格，循环段琥珀；P2 接热点标记
    private var measureBand: some View {
        GeometryReader { proxy in
            let total = max(1, totalMeasures)
            let cellWidth = proxy.size.width / CGFloat(total)
            ZStack(alignment: .topLeading) {
                ForEach(1...total, id: \.self) { m in
                    let inRange = m >= start && m <= end
                    Rectangle()
                        .fill(inRange ? Color.amber : Color.surface)
                        .frame(width: cellWidth - 1.5, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.borderInput, lineWidth: 0.5))
                        .offset(x: CGFloat(m - 1) * cellWidth)
                }
            }
        }
        .frame(height: 28)
        .overlay(alignment: .top) {
            Text(rangeValid ? "\(start)–\(end) 小节" : "区间无效（1 ≤ 起 < 止 ≤ \(totalMeasures)）")
                .font(.labelSm)
                .foregroundStyle(rangeValid ? Color.textMuted : Color.danger)
                .offset(y: 32)
        }
        .padding(.bottom, 24)
    }

    /// 快捷 chips：整段/全曲真实可用；热点相关 P2（显式禁用，不留死按钮）
    private var quickChips: some View {
        HStack(spacing: 8) {
            NocturneChip(title: "整段", isSelected: false) {
                start = 1
                end = max(2, min(8, totalMeasures))
            }
            NocturneChip(title: "全曲", isSelected: false) {
                start = 1
                end = totalMeasures
            }
            ZStack {
                NocturneChip(title: "只练错误热点", isSelected: false) {}
                    .disabled(true)
                Text("P2")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.canvas)
                    .background(Circle().fill(Color.amber).frame(width: 14, height: 14))
                    .offset(x: 34, y: -10)
            }
        }
    }

    private func modeRow(_ tag: LoopMode, _ label: String) -> some View {
        Button {
            mode = tag
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(mode == tag ? Color.amber : Color.borderInput, lineWidth: 1)
                        .frame(width: 16, height: 16)
                    Circle().fill(Color.amber).frame(width: 8, height: 8)
                        .opacity(mode == tag ? 1 : 0)
                }
                Text(label)
                    .font(.bodyMd)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private func applyAndStart() {
        guard rangeValid else { return }
        session.loopConfig = LoopConfig(
            startMeasure: start,
            endMeasure: end,
            mode: mode,
            gapSec: gapSec,
            countIn: countIn
        )
        // TODO(P2)：错误计数接 M5 完整对齐判分；当前按简单匹配错音口径（brief 授权）
        dismiss()
    }
}
