import SwiftUI

/// M0：空白 app 启动为 canvas（#1C1917）底色全屏。
/// M1 spike 期间挂载两个 spike 视图（渲染验收 + MIDI 模拟源验收）；
/// App 骨架（S06）在后续批次替换。
struct RootView: View {
    enum SpikeTab: String, CaseIterable, Identifiable {
        case score, midi
        var id: Self { self }
    }

    @State private var tab: SpikeTab = .midi

    var body: some View {
        VStack(spacing: 0) {
            Picker("spike", selection: $tab) {
                ForEach(SpikeTab.allCases) { t in
                    Text(t == .score ? "Spike A 渲染" : "Spike B MIDI").tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            switch tab {
            case .score: SpikeScoreView()
            case .midi: MIDISpikeView()
            }
        }
    }
}

#Preview {
    RootView()
}
