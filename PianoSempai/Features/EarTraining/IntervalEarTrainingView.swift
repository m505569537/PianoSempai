import AVFoundation
import SwiftData
import SwiftUI

// G6 Stage B（ADR-0008）：听音辨音程的发声、练耳页与设置入口。
// 三块同文件：轻量播放器（隔离音频引擎）/ 会话状态机（@Observable，可单测）/ 视图。
// 红线同 Stage A：不写 Take/TakeAnalysis、不碰 Piece.status、不触发过关/推进/streak/铺路。

// MARK: - 轻量播放器

/// 音程发声：独立 AVAudioEngine + AVAudioUnitSampler 系统内置音色。
/// 刻意不复用 SamplerSynthBackend（那是 AVAudioSequencer + 同步加载 215MB SF2 的整曲范式，
/// 对两个短音太重），也不常驻全局——只在练耳页存活，onDisappear 停引擎释放。
/// 音程听辨只听相对音高，默认音色足够；配置/启动失败静默（页面仍可点选，只没声音），不崩。
@MainActor
final class IntervalTonePlayer {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var configured = false

    /// 懒配置（首次播放时）：attach/connect sampler→mainMixer，start engine。不加载任何 sf2。
    private func ensureRunning() {
        if !configured {
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            configured = true
        }
        guard !engine.isRunning else { return }
        try? engine.start()
    }

    /// 依次弹 root→top 两个上行旋律音：root 起，约 0.6s 后停、停 0.25s 再起 top（力度 80）。
    /// 重复调用以最新一次为准，不取消旧序列（短音、自然结束即可）。
    func playInterval(rootMIDINote: Int, topMIDINote: Int) {
        ensureRunning()
        guard engine.isRunning else { return }
        // 本题音域 55...79，钳到 MIDI 全域只为防御；Int→UInt8 直接转换
        let root = UInt8(max(0, min(127, rootMIDINote)))
        let top = UInt8(max(0, min(127, topMIDINote)))
        Task { @MainActor in
            sampler.startNote(root, withVelocity: 80, onChannel: 0)
            try? await Task.sleep(nanoseconds: 600_000_000)
            sampler.stopNote(root, onChannel: 0)
            try? await Task.sleep(nanoseconds: 250_000_000)
            sampler.startNote(top, withVelocity: 80, onChannel: 0)
            try? await Task.sleep(nanoseconds: 600_000_000)
            sampler.stopNote(top, onChannel: 0)
        }
    }

    /// 页面消失时停引擎，释放音频资源。
    func stop() {
        engine.stop()
        configured = false
    }
}

// MARK: - 会话状态机（抽离以便单测）

/// 一轮听音练耳（10 题）的状态机：出题在 init 预生成、作答幂等、收尾一轮只写一条 round。
@Observable
@MainActor
final class IntervalQuizSession {
    static let questionsPerRound = 10

    private let makeQuestion: () -> IntervalQuestion
    private let context: ModelContext
    /// 当前题序号（0-based；private(set)：外部只读以便视图观察，写入仍只在内部）
    private(set) var index = 0
    private var correct = 0

    /// 本轮题目（按序）
    private(set) var questions: [IntervalQuestion] = []
    /// 当前题已选的半音数（nil = 未作答）
    private(set) var selected: Int? = nil
    /// true = 第 10 题已作答且 next 收尾，本轮结束
    private(set) var finished = false
    /// 本轮命中率（finished 后可用，= EarTrainingRound.hitRate）
    private(set) var finalHitRate: Double? = nil

    var currentQuestion: IntervalQuestion? { questions.indices.contains(index) ? questions[index] : nil }
    var displayIndex: Int { min(index + 1, Self.questionsPerRound) }

    /// makeQuestion 以闭包注入（生产：按 currentBeyer 求 allowed 后用系统随机出题；
    /// 测试：喂固定题目序列），便于脱离真实随机与音频做状态机单测。
    /// init 预生成整轮 10 题（调用 10 次 makeQuestion）。
    init(allowed: Set<Int>, context: ModelContext, makeQuestion: @escaping () -> IntervalQuestion) {
        self.makeQuestion = makeQuestion
        self.context = context
        self.questions = (0..<Self.questionsPerRound).map { _ in makeQuestion() }
    }

    /// 作答一题：未作答才接受（幂等）；用 IntervalJudging.isCorrect 判定并累计。
    func answer(_ semitone: Int) {
        guard !finished, selected == nil, currentQuestion != nil else { return }
        selected = semitone
        if IntervalJudging.isCorrect(selected: semitone, question: currentQuestion!) {
            correct += 1
        }
    }

    /// 推进：未到第 10 题 → index+1、selected=nil；第 10 题作答后触发收尾——
    /// finished=true 并落库（EarTrainingStore.save，一轮只写一条：finished 后 next 直接返回防重入）。
    func next() {
        guard !finished else { return } // 收尾防重入：finished 后再调 next 不产生第二条 round
        guard currentQuestion != nil, selected != nil else { return } // 未作答不推进
        if index < Self.questionsPerRound - 1 {
            index += 1
            selected = nil
            return
        }
        // 第 10 题收尾
        let round = EarTrainingStore.save(kind: "interval", correct: correct,
                                          total: Self.questionsPerRound, in: context)
        finalHitRate = round.hitRate
        finished = true
    }
}

// MARK: - 练耳页

struct IntervalEarTrainingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var pathStates: [CoursePathState]
    @Query private var rounds: [EarTrainingRound]

    @State private var player = IntervalTonePlayer()
    @State private var session: IntervalQuizSession?

    private var pathState: CoursePathState? { pathStates.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let session {
                if session.finished {
                    resultView(session)
                } else {
                    quizView(session)
                }
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .background(Color.canvas)
        .onAppear(perform: ensureSession)
        .onChange(of: session?.index) { _, _ in playCurrent() } // 每题出现自动播放一次
        .onDisappear { player.stop() }
    }

    // MARK: 顶部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textMuted)
                        .frame(width: 32, height: 32)
                        .background(Color.card, in: Circle())
                        .overlay(Circle().strokeBorder(Color.border, lineWidth: 1))
                }
                .accessibilityLabel("关闭")
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 8)

            Text("听音练耳")
                .font(.headlineLg)
                .foregroundStyle(Color.textPrimary)
            Text(subtitle)
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .padding(.bottom, 20)
        }
    }

    private var subtitle: String {
        guard let session, !session.finished else { return "听音辨音程 · 本轮结束" }
        return "听音辨音程 · 第 \(session.displayIndex)/\(IntervalQuizSession.questionsPerRound) 题"
    }

    // MARK: 答题区

    private func quizView(_ session: IntervalQuizSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            playButton(session)
            if let question = session.currentQuestion {
                VStack(spacing: 10) {
                    ForEach(question.options, id: \.self) { semitone in
                        optionRow(semitone, session: session)
                    }
                }
            }
            if session.selected != nil {
                Button("下一题") { session.next() }
                    .buttonStyle(PrimaryButtonStyle(cornerRadius: 12))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playButton(_ session: IntervalQuizSession) -> some View {
        Button {
            playCurrent()
        } label: {
            Label(session.selected == nil ? "播放" : "再听一次", systemImage: "speaker.wave.2")
        }
        .buttonStyle(SecondaryButtonStyle(cornerRadius: 12))
    }

    /// 选项行：未作答中性可点；作答后正确项高亮（success 填充）、错选项标红（danger）、其余置灰，不可再点。
    private func optionRow(_ semitone: Int, session: IntervalQuizSession) -> some View {
        let answered = session.selected != nil
        let isAnswer = semitone == session.currentQuestion?.answerSemitones
        let isWrongPick = answered && semitone == session.selected && !isAnswer
        let label = IntervalID(rawValue: semitone)?.displayName ?? "—"

        let background: Color = {
            if answered && isAnswer { return Color.success }
            if isWrongPick { return Color.danger }
            return Color.card
        }()
        let foreground: Color = {
            if answered && isAnswer { return Color.canvas }
            if isWrongPick { return Color.canvas }
            if answered { return Color.textMuted } // 其余置灰
            return Color.textPrimary
        }()

        return Button {
            session.answer(semitone)
        } label: {
            Text(label)
                .font(.titleMd)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(answered ? Color.clear : Color.border, lineWidth: 1)
                )
        }
        .disabled(answered)
        .opacity(answered && !isAnswer && !isWrongPick ? 0.55 : 1)
    }

    // MARK: 结算

    private func resultView(_ session: IntervalQuizSession) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 8) {
                Text("本轮命中率")
                    .font(.labelMd)
                    .foregroundStyle(Color.textMuted)
                Text(hitRateText(session.finalHitRate))
                    .font(.displayLg)
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.5)
            }

            trendCard

            Spacer()

            HStack(spacing: 12) {
                Button("再练一轮") { rebuildSession() }
                    .buttonStyle(SecondaryButtonStyle(cornerRadius: 12))
                Button("完成") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle(cornerRadius: 12))
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "7/10 · 70%"（finalHitRate 在 finished 后恒有值；防御性兜底 0）
    private func hitRateText(_ hitRate: Double?) -> String {
        let rate = hitRate ?? 0
        let correct = Int((rate * Double(IntervalQuizSession.questionsPerRound)).rounded())
        return "\(correct)/\(IntervalQuizSession.questionsPerRound) · \(Int((rate * 100).rounded()))%"
    }

    /// 趋势：最近轮次简易竖柱（左旧右新）+ 均值线；<3 轮 mean==nil 不画线，诚实留白。
    private var trendCard: some View {
        let summary = EarTrainingTrend.summarize(rounds: rounds)
        return VStack(alignment: .leading, spacing: 12) {
            Text("最近轮次命中率")
                .font(.labelMd)
                .foregroundStyle(Color.textMuted)
            if summary.hitRates.isEmpty {
                Text("还没有轮次记录。")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            } else {
                TrendBars(hitRates: summary.hitRates, mean: summary.mean)
                if let mean = summary.mean {
                    Text("均值 \(Int((mean * 100).rounded()))%")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                } else {
                    Text("再练几轮看趋势")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
    }

    /// 最近轮次竖柱：左旧右新；均值线按占比从底部上移（柱底对齐）。
    /// app 无现成柱状组件，按最简 RoundedRectangle 柱 + 既有 token（amber 柱 / textMuted 线）。
    private struct TrendBars: View {
        let hitRates: [Double]
        let mean: Double?

        private let barHeight: CGFloat = 96

        var body: some View {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(hitRates.indices, id: \.self) { i in
                    let rate = min(max(hitRates[i], 0), 1)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.amber)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, barHeight * rate))
                }
            }
            .frame(height: barHeight, alignment: .bottom)
            .overlay(alignment: .bottom) {
                if let mean {
                    Rectangle()
                        .fill(Color.textMuted.opacity(0.6))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .offset(y: -barHeight * min(max(mean, 0), 1))
                }
            }
        }
    }

    // MARK: 会话构建与播放

    /// 生产构造：按 currentBeyer 求 allowed，闭包内用系统随机出题；init 预生成 10 题。
    private func ensureSession() {
        guard session == nil else { return }
        session = makeSession()
        // 首题播放统一由 .onChange(of: session?.index)（nil→0）触发，避免与此处重复叠播
    }

    private func rebuildSession() {
        session = makeSession()
        // 新轮 index 9→0 触发 onChange 自动播放首题
    }

    private func makeSession() -> IntervalQuizSession {
        let allowed = IntervalUnlock.allowedSemitones(currentBeyer: pathState?.currentBeyer ?? 0)
        var gen = SystemRandomNumberGenerator()
        return IntervalQuizSession(allowed: allowed, context: context) {
            IntervalQuiz.makeQuestion(allowed: allowed, using: &gen)
        }
    }

    private func playCurrent() {
        guard let question = session?.currentQuestion else { return }
        player.playInterval(rootMIDINote: question.rootMIDINote, topMIDINote: question.topMIDINote)
    }
}
