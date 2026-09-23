import SheetMusicCore
import SheetMusicLoader
import SheetMusicLayout
import SheetMusicUI
import SwiftData
import SwiftUI

// MARK: - S04 入学评估（自评 1min → 视奏 2 段 → 力度校准 2min；无独立视奏稿，S11 简化评估态）

struct S04PlacementView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject var hub = MIDIHub.shared

    enum SubStep: Int {
        case selfReport = 0, sightread, calibration
    }

    /// §4 表单行（真值五行「标签 + 值」；点行打开底部 Sheet 选择）
    enum RowField: String, CaseIterable, Identifiable {
        case years, books, times, duration, genres
        var id: String { rawValue }

        var title: String {
            switch self {
            case .years: "琴龄"
            case .books: "现有教材"
            case .times: "每周可练次数"
            case .duration: "每次时长"
            case .genres: "偏好风格"
            }
        }

        var options: [String] {
            switch self {
            case .years: ["半年内", "约 1 年", "约 2 年", "3 年以上", "5 年以上"]
            case .books: ["拜厄", "哈农", "车尔尼599", "大汤", "布格缪勒", "巴赫初级"]
            case .times: ["1-2 次", "3 次", "4-5 次", "每天"]
            case .duration: ["15 分钟", "30 分钟", "30 分钟（偶尔 45）", "45 分钟以上"]
            case .genres: ["古典", "日式轻音乐", "流行", "爵士", "其他"]
            }
        }

        /// 教材 / 曲风为多选（chips），其余单选
        var isMultiSelect: Bool {
            switch self {
            case .books, .genres: true
            default: false
            }
        }
    }

    @State private var subStep: SubStep = .selfReport

    // 自评字段（默认值按真实用户画像，S04 spec §4/§9）
    @State private var yearsExperience = "约 2 年"
    @State private var books: Set<String> = ["拜厄", "哈农"]
    @State private var timesPerWeek = "3 次"
    @State private var durationPref = "30 分钟（偶尔 45）"
    @State private var genres: Set<String> = ["古典", "日式轻音乐"]
    /// §5 目标保留曲库（默认空：只有用户真录入曲子才出 chip，Stitch 图上的《Summer》只是示例，不作默认值）
    @State private var carryPieces: [String] = []
    /// §4 表单行底部选择器（点行打开）
    @State private var activeRow: RowField?
    /// §5 添加曲目输入
    @State private var showAddPiece = false
    @State private var newPiece = ""

    // 视奏
    @StateObject private var session = SightReadSession()
    @State private var segmentIndex = 0
    @State private var segmentResults: [SightReadSegmentResult] = []
    private let segments: [(title: String, range: ClosedRange<Int>)] = [
        ("视奏段落 1/2", 1...8),
        ("视奏段落 2/2", 17...24),
    ]

    // 力度校准
    enum CalibrationPhase: Int, CaseIterable {
        case pp = 0, mf, ff
        var label: String {
            switch self {
            case .pp: "最弱"
            case .mf: "舒适"
            case .ff: "最强"
            }
        }
        var instruction: String {
            switch self {
            case .pp: "请用你所能弹出最轻的音，弹几个音"
            case .mf: "请用平时最自然的力度，弹几个音"
            case .ff: "请用你所能弹出最强的音（不砸琴），弹几个音"
            }
        }
    }
    @State private var calPhase: CalibrationPhase = .pp
    @State private var calSamples: [CalibrationPhase: [Int]] = [:]
    /// 模拟源专用力度（屏幕无法产生真实力度，用滑块如实模拟）
    @State private var simulatedVelocity: Double = 64

    @State private var startedAt = Date()
    @State private var showExitConfirm = false

    let onLater: () -> Void // 稍后评估（轻确认后退出，进度保存）
    let onFinished: () -> Void // 三段全部完成 → S05

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            navBar

            switch subStep {
            case .selfReport: selfReportStep
            case .sightread: sightreadStep
            case .calibration: calibrationStep
            }
        }
        .background(Color.canvas)
        .onAppear {
            hub.onEvent = { event in
                session.handle(event)
                collectCalibrationSample(event)
            }
            startedAt = Date()
        }
        .onDisappear { hub.onEvent = nil }
        // 时长口径按 Stitch 真值统一为「约 20 分钟」（导航行胶囊，spec §2）；旧流程「3 分钟」文案已移除，
        // 确认弹窗只作进度承诺、不写分钟数。六个自评字段仍由 saveReport 全量落库。
        .confirmationDialog("进度会保留，随时可以继续评估", isPresented: $showExitConfirm, titleVisibility: .visible) {
            Button("稍后评估", role: .none) { saveReport(); onLater() }
            Button("继续评估", role: .cancel) {}
        }
    }

    private var navBar: some View {
        HStack(spacing: 12) {
            Button {
                if subStep == .selfReport {
                    showExitConfirm = true
                } else {
                    subStep = SubStep(rawValue: subStep.rawValue - 1) ?? .selfReport
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.textBody)
                    .frame(width: 36, height: 36)
            }
            Spacer(minLength: 8)
            // 真值 §2 步骤指示：自评 / 三段测试 / 校准（旧 spec 的「1/3」数字标号不存在）
            StepIndicator(current: subStep.rawValue, count: 3, titles: ["自评", "三段测试", "校准"])
            Spacer(minLength: 8)
            Text("约 20 分钟")
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.border.opacity(0.8), lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: 1/3 自评（真值：标题区 → 表单卡 → 曲库卡 → 说明卡 → 胶囊 CTA）

    private var selfReportStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // §3 标题区
                Text("开始前，先了解你")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.top, 8)
                Text("评估只用于规划你的起点，不是考试，可以随时退出。")
                    .font(.system(size: 13))
                    .leading(21, fontSize: 13)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 8)

                // §4 表单分组卡（5 行均有默认值，不阻塞继续）
                selfReportFormCard
                    .padding(.top, 20)

                // §5 目标保留曲库卡
                carryPiecesCard
                    .padding(.top, 16)

                // §6 说明卡
                nextStepCard
                    .padding(.top, 16)

                // §7 底部操作：全宽胶囊琥珀 CTA + 居中幽灵链接
                Button {
                    saveReport()
                    subStep = .sightread
                } label: {
                    Text("开始三段测试")
                }
                .buttonStyle(PrimaryButtonStyle(cornerRadius: 25))
                .padding(.top, 20)

                // 幽灵链接居中（GhostButtonStyle 自带上下 12pt，即真值 mt 12）
                Button("稍后评估，先随便看看") { showExitConfirm = true }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .sheet(item: $activeRow) { field in
            rowPickerSheet(field)
        }
        .alert("添加曲目", isPresented: $showAddPiece) {
            TextField("如：久石让《Summer》", text: $newPiece)
            Button("添加") {
                let piece = newPiece.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty, !carryPieces.contains(piece) {
                    carryPieces.append(piece)
                }
                newPiece = ""
            }
            Button("取消", role: .cancel) { newPiece = "" }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.border).frame(height: 1)
    }

    /// §4 表单分组卡：圆角 16，行间 1pt 发丝线
    private var selfReportFormCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            formValueRow(.years)
            divider
            formValueRow(.books)
            divider
            formValueRow(.times)
            divider
            formValueRow(.duration)
            divider
            formValueRow(.genres)
        }
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
    }

    /// §4 表单行：左标签 + 琥珀右值 + chevron；整行可点，打开底部选择 Sheet
    private func formValueRow(_ field: RowField) -> some View {
        Button { activeRow = field } label: {
            HStack {
                Text(field.title)
                    .font(.bodyMd)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                HStack(spacing: 6) {
                    Text(valueLabel(field))
                        .font(.bodyMd)
                        .foregroundStyle(Color.amber)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                }
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// §4 右值渲染（多选按选项序拼接，避免 Set 乱序）
    private func valueLabel(_ field: RowField) -> String {
        switch field {
        case .years: return yearsExperience
        case .times: return timesPerWeek
        case .duration: return durationPref
        case .books:
            let picked = RowField.books.options.filter { books.contains($0) }
            return picked.isEmpty ? "未选择" : picked.joined(separator: " · ")
        case .genres:
            let picked = RowField.genres.options.filter { genres.contains($0) }
            return picked.isEmpty ? "未选择" : picked.joined(separator: " · ")
        }
    }

    /// §4 点行打开的底部 Sheet：单选即点即走，多选 chips + 完成
    private func rowPickerSheet(_ field: RowField) -> some View {
        NavigationStack {
            Group {
                if field.isMultiSelect {
                    ScrollView {
                        FlowChips(
                            options: field.options,
                            isSelected: { isSelected(field, $0) },
                            toggle: { toggle(field, $0) }
                        )
                        .padding(20)
                    }
                } else {
                    List {
                        ForEach(field.options, id: \.self) { option in
                            Button {
                                select(field, option)
                                activeRow = nil
                            } label: {
                                HStack {
                                    Text(option)
                                        .font(.bodyMd)
                                        .foregroundStyle(Color.textPrimary)
                                    Spacer()
                                    if isSelected(field, option) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Color.amber)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.card)
                            .listRowSeparatorTint(Color.border)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.canvas)
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { activeRow = nil }
                        .font(.titleMd)
                        .foregroundStyle(Color.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }

    private func isSelected(_ field: RowField, _ option: String) -> Bool {
        switch field {
        case .books: books.contains(option)
        case .genres: genres.contains(option)
        default: false
        }
    }

    private func toggle(_ field: RowField, _ option: String) {
        switch field {
        case .books: books.formSymmetricDifference([option])
        case .genres: genres.formSymmetricDifference([option])
        default: break
        }
    }

    private func select(_ field: RowField, _ option: String) {
        switch field {
        case .years: yearsExperience = option
        case .times: timesPerWeek = option
        case .duration: durationPref = option
        case .books, .genres: break
        }
    }

    /// §5 目标保留曲库卡：圆角 16，chips wrap + 虚线「添加曲目」
    private var carryPiecesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.amber)
                Text("我要随身携带的曲子")
                    .font(.bodyMd)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("目标保留曲库")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
            FlowLayout(spacing: 8) {
                ForEach(carryPieces, id: \.self) { piece in
                    carryPieceChip(piece)
                }
                addPieceButton
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
    }

    /// §5 已选曲目 chip：琥珀 10% 底 + 70% 描边，右侧 16×16 移除键
    private func carryPieceChip(_ piece: String) -> some View {
        HStack(spacing: 6) {
            Text(piece)
                .font(.bodyMd)
                .fontWeight(.medium)
                .foregroundStyle(Color.amber)
            Button {
                carryPieces.removeAll { $0 == piece }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.amber)
                    .frame(width: 16, height: 16)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(Color.amber.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.amber.opacity(0.7), lineWidth: 1))
    }

    /// §5 添加按钮：全圆角 + 虚线描边
    private var addPieceButton: some View {
        Button { showAddPiece = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                Text("添加曲目")
                    .font(.bodyMd)
            }
            .foregroundStyle(Color.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.card.opacity(0.5), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.border, style: StrokeStyle(lineWidth: 1, dash: [4])))
        }
        .buttonStyle(.plain)
    }

    /// §6 说明卡：card 60% 底 + 圆角 12，info 图标顶对齐
    private var nextStepCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 19))
                .foregroundStyle(Color.amber)
            (
                Text("下一步：")
                    .font(.bodySm)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)
                + Text("你将完成 3 个小测试——最拿手的一首、视奏陌生片段、技术探针（音阶与哈农）。")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            )
            .leading(20, fontSize: 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.border.opacity(0.8), lineWidth: 1))
    }

    private func saveReport() {
        let report = PlacementSelfReport()
        report.yearsExperience = yearsExperience
        // 按选项序落库，避免 Set 无序导致每次顺序不同
        report.books = RowField.books.options.filter { books.contains($0) }
        report.timesPerWeek = timesPerWeek
        report.durationPref = durationPref
        report.genres = RowField.genres.options.filter { genres.contains($0) }
        // §5 曲库 chips 合并落 recentPiece（模型暂无列表字段，P1 不改 schema）
        report.recentPiece = carryPieces.joined(separator: "、")
        context.insert(report)
    }

    // MARK: 2/3 视奏（两段，仅采原始数据）

    private var sightreadStep: some View {
        let segment = segments[segmentIndex]
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("视奏：没见过的片段")
                    .font(.headlineLg)
                    .foregroundStyle(Color.textPrimary)
                Text("即时读谱弹一遍。自学党最容易藏拙的维度——放心，只用来帮你选起点。")
                    .font(.bodySm)
                    .leading(18, fontSize: 12)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 4)

                // 谱面（真实引擎渲染，示意区间为第 1–32 小节内置公版小样）
                ScoreSightReadView(measureRange: segment.range)
                    .frame(height: 220)
                    .padding(.top, 16)

                HStack {
                    Text("\(segment.title) · 第 \(segment.range.lowerBound)–\(segment.range.upperBound) 小节")
                        .font(.labelMd)
                        .foregroundStyle(Color.textBody)
                    Spacer()
                    if session.isCollecting {
                        Text("采集中… 已收到 \(session.collectedPitches.count) 音")
                            .font(.labelMono(11))
                            .foregroundStyle(Color.amber)
                            .monospacedDigit()
                    }
                }
                .padding(.top, 12)

                if let last = session.lastNoteName, session.isCollecting {
                    Text("最近收到：\(last)")
                        .font(.labelMono(12))
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 4)
                }

                // 模拟源：屏幕琴键
                if hub.mode == .simulated, let simulated = hub.simulated {
                    Text("模拟输入：点按琴键弹奏（真实琴则直接在琴上弹）")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 16)
                    HStack(spacing: 4) {
                        ForEach([UInt8(60), 62, 64, 65, 67, 69, 71, 72], id: \.self) { note in
                            Button {
                                simulated.press(note: note)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    simulated.release(note: note)
                                }
                            } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.scorePaper)
                                    .frame(height: 56)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }

                HStack(spacing: 12) {
                    if session.isCollecting {
                        Button("弹完了") {
                            finishSegment()
                        }
                        .buttonStyle(PrimaryButtonStyle(cornerRadius: 8))
                    } else {
                        Button("开始弹奏") {
                            session.start()
                        }
                        .buttonStyle(PrimaryButtonStyle(cornerRadius: 8))
                    }
                }
                .padding(.top, 20)

                if segmentIndex == 1, let first = segmentResults.first {
                    // 上一段的真实结算（数字可解释）
                    HStack(spacing: 16) {
                        Text("上段命中 \(first.matched)/\(first.expected)")
                        if let rate = first.hitRate {
                            Text(String(format: "命中率 %.0f%%", rate * 100))
                        }
                    }
                    .font(.labelMono(12))
                    .foregroundStyle(Color.textMuted)
                    .monospacedDigit()
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func finishSegment() {
        let expected = SightReadSession.loadExpectedPitches(measures: segments[segmentIndex].range)
        let result = session.stop(expectedPitches: expected)
        segmentResults.append(result)
        if segmentIndex == 0 {
            segmentIndex = 1
        } else {
            subStep = .calibration
        }
    }

    // MARK: 3/3 力度校准

    private var calibrationStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("力度校准")
                    .font(.headlineLg)
                    .foregroundStyle(Color.textPrimary)
                Text("三档各弹几个音（约 2 分钟）。之后所有力度分析都按你自己的曲线，不做横向比较。")
                    .font(.bodySm)
                    .leading(18, fontSize: 12)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 4)

                ForEach(CalibrationPhase.allCases, id: \.rawValue) { phase in
                    let samples = calSamples[phase] ?? []
                    HStack(spacing: 12) {
                        Image(systemName: samples.count >= 3 ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(samples.count >= 3 ? Color.success : Color.textMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phase.label)
                                .font(.titleMd)
                                .foregroundStyle(Color.textPrimary)
                            Text(phase.instruction)
                                .font(.bodySm)
                                .foregroundStyle(Color.textMuted)
                            if !samples.isEmpty {
                                Text("已收 \(samples.count) 音 · 中位 \(samples.sorted()[samples.count / 2])")
                                    .font(.labelMono(11))
                                    .foregroundStyle(Color.amber)
                                    .monospacedDigit()
                            }
                        }
                        Spacer()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
                    .padding(.top, 12)
                }

                // 模拟源力度滑块（如实模拟设备事件）
                if hub.mode == .simulated, let simulated = hub.simulated {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("模拟力度：\(Int(simulatedVelocity))")
                            .font(.labelMd)
                            .foregroundStyle(Color.textMuted)
                            .monospacedDigit()
                        Slider(value: $simulatedVelocity, in: 1...127, step: 1)
                            .tint(Color.amber)
                        HStack(spacing: 4) {
                            ForEach([UInt8(60), 64, 67], id: \.self) { note in
                                Button {
                                    simulated.press(note: note, velocity: UInt8(simulatedVelocity))
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        simulated.release(note: note)
                                    }
                                } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.scorePaper)
                                        .frame(height: 48)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 16)
                } else {
                    Text("请直接在琴上弹奏")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 16)
                }

                Button {
                    advanceCalibrationOrFinish()
                } label: {
                    Text(calPhase == .ff ? "完成校准" : "下一档")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
    }

    private func collectCalibrationSample(_ event: MIDIEvent) {
        guard subStep == .calibration, case let .noteOn(_, velocity) = event.kind, velocity > 0 else { return }
        calSamples[calPhase, default: []].append(Int(velocity))
    }

    private func advanceCalibrationOrFinish() {
        if calPhase == .ff {
            persistCalibration()
            persistResult()
            onFinished()
        } else {
            calPhase = CalibrationPhase(rawValue: calPhase.rawValue + 1) ?? .ff
        }
    }

    private func persistCalibration() {
        let calibration = VelocityCalibration()
        let pp = (calSamples[.pp] ?? []).sorted()
        let mf = (calSamples[.mf] ?? []).sorted()
        let ff = (calSamples[.ff] ?? []).sorted()
        calibration.ppSamples = pp.count
        calibration.mfSamples = mf.count
        calibration.ffSamples = ff.count
        // 中位数（真实采集；样本不足时仍存实收值，isCalibrated 会如实反映）
        calibration.ppVelocity = pp.isEmpty ? 0 : pp[pp.count / 2]
        calibration.mfVelocity = mf.isEmpty ? 0 : mf[mf.count / 2]
        calibration.ffVelocity = ff.isEmpty ? 0 : ff[ff.count / 2]
        calibration.deviceName = hub.mode == .simulated ? "模拟输入" : (hub.real?.sourceNames.first ?? "未知设备")
        context.insert(calibration)
    }

    private func persistResult() {
        // CourseEngine（唯一写手）落 PlacementResult + CoursePathState
        let hitRates = segmentResults.compactMap(\.hitRate)
        let expected = segmentResults.map(\.expected)
        let matched = segmentResults.map(\.matched)
        let pauses = segmentResults.map(\.pauses)

        // 取本次评估存下的最新自评报告
        let descriptor = FetchDescriptor<PlacementSelfReport>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let report = (try? context.fetch(descriptor).first) ?? PlacementSelfReport()

        let elapsed = Int(Date().timeIntervalSince(startedAt))
        _ = CourseEngine.finalizePlacement(
            report: report,
            hitRates: hitRates,
            expected: expected,
            matched: matched,
            pauseCounts: pauses,
            calibration: latestCalibration(),
            elapsedSeconds: elapsed,
            in: context
        )
    }

    private func latestCalibration() -> VelocityCalibration? {
        let descriptor = FetchDescriptor<VelocityCalibration>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try? context.fetch(descriptor).first
    }
}

// MARK: - 谱面视图（真实渲染引擎；视奏示意）

struct ScoreSightReadView: View {
    let measureRange: ClosedRange<Int>
    @State private var score: Score?

    var body: some View {
        Group {
            if let score {
                ScrollView {
                    ScoreView(
                        score: score,
                        options: ScoreViewOptions(wrapToViewWidth: true),
                        availableWidth: UIScreen.main.bounds.width - 56,
                    )
                }
                .background(Color.scorePaper, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("谱面加载失败")
                    .font(.bodySm)
                    .foregroundStyle(Color.danger)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.scorePaper, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .task {
            if let url = Bundle.main.url(forResource: "SpikeSample32", withExtension: "musicxml") {
                score = try? ScoreLoader.loadScore(contentsOf: url)
            }
        }
    }
}

/// 换行 wrap 的 chips
struct FlowChips: View {
    let options: [String]
    let isSelected: (String) -> Bool
    let toggle: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                NocturneChip(title: option, isSelected: isSelected(option)) {
                    toggle(option)
                }
            }
        }
    }
}

/// 流式布局（chips wrap，不横向滚动——S04 spec）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    S04PlacementView(onLater: {}, onFinished: {})
}
