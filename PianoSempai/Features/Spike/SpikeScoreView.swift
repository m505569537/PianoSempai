import SwiftUI
import SheetMusicCore
import SheetMusicLayout
import SheetMusicLoader
import SheetMusicUI

/// M1 Spike A：swift-sheet-music 渲染可行性验证（docs/spikes/score-rendering.md）。
/// 验收：32 小节双谱表 MusicXML 在模拟器渲染纸白五线谱；光标按拍推进并报告当前小节；
/// 能枚举每个音符的小节/音高（MIDI）供跟弹匹配使用。
struct SpikeScoreView: View {
    @State private var score: Score?
    @State private var loadError: String?
    @State private var cursor: ScoreCursor?
    @State private var playheadSeconds: Double = 0
    @State private var noteDump: String = ""
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            if let score {
                ScrollView {
                    ScoreView(
                        score: score,
                        options: ScoreViewOptions(wrapToViewWidth: true),
                        playbackCursor: cursor,
                        playbackCursorColor: Color.amber.opacity(0.3),
                        availableWidth: UIScreen.main.bounds.width - 24,
                    )
                    .background(Color.scorePaper)
                    .padding(.vertical, 16)
                }
            } else if let loadError {
                Text(loadError)
                    .font(.bodyMd)
                    .foregroundStyle(Color.danger)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer
        }
        .background(Color.canvas)
        .task {
            load()
            startClock()
        }
        .onDisappear { timer?.invalidate() }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let score, let cursor {
                Text("当前小节 \(cursor.measureIndex + 1) / \(score.parts.first?.staves.first?.measures.count ?? 0)")
                    .font(.labelMono(12, weight: .medium))
                    .foregroundStyle(Color.amber)
                    .monospacedDigit()
                Text("playhead \(String(format: "%.1f", playheadSeconds))s")
                    .font(.labelMono(11))
                    .foregroundStyle(Color.textMuted)
                    .monospacedDigit()
            }
            Text(noteDump)
                .font(.labelMono(10))
                .foregroundStyle(Color.textMuted)
                .lineLimit(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.card)
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "SpikeSample32", withExtension: "musicxml") else {
            loadError = "SpikeSample32.musicxml 不在 bundle 里"
            return
        }
        do {
            let loaded = try ScoreLoader.loadScore(contentsOf: url)
            score = loaded
            cursor = loaded.cursor(atSeconds: 0)
            dumpNotes(loaded)
        } catch {
            loadError = "解析失败: \(error)"
        }
    }

    /// 跟弹数据探针：枚举音符（小节 → MIDI 音高），并演示 notated seconds 映射。
    private func dumpNotes(_ score: Score) {
        var lines: [String] = []
        var total = 0
        for part in score.parts {
            for (staffIdx, staff) in part.staves.enumerated() {
                for (measureIdx, measure) in staff.measures.enumerated() {
                    for voice in measure.voices {
                        for element in voice.elements {
                            if case let .chord(chord) = element {
                                let pitches = chord.notes.map { $0.pitch }
                                guard !pitches.isEmpty else { continue }
                                total += pitches.count
                                if lines.count < 6, measureIdx.isMultiple(of: 4) {
                                    lines.append("m\(measureIdx + 1)/s\(staffIdx): \(pitches.map(String.init).joined(separator: ","))")
                                }
                            }
                        }
                    }
                }
            }
        }
        let first = score.parts.first?.staves.first?.measures.first
        let firstChordTick: Int = 0
        lines.insert("音符总数 \(total)；first measure voices \(first?.voices.count ?? 0)；tick\(firstChordTick)", at: 0)
        noteDump = lines.joined(separator: "\n")
    }

    private func startClock() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard let score else { return }
            playheadSeconds += 0.25
            cursor = score.cursor(atSeconds: playheadSeconds)
        }
    }
}

#Preview {
    SpikeScoreView()
}
