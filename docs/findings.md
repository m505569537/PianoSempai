# PianoSempai · Findings（spec 自身矛盾与环境事实记录）

> 规则：发现 spec 自身矛盾 → 记入本文件（F1/F2…），不静默选一个。

## F1 · MIDI 包选型矛盾（PRD vs P1 brief）

- `PRD.md` M1：「底层 CoreMIDI，代码通过 orchetect/SwiftMIDI（MIT）封装层使用，不裸写 CoreMIDI」。
- `P1-BRIEF.md` §1：「MIDI 用 SwiftMIDI（github.com/genedelisa/SwiftMIDI，MIT；先核实包可解析，不行则直接封装 CoreMIDI 的 MIDIManager，不阻塞）」。
- 两处指定了不同的包。**P1 实际采用 brief 的 fallback 分支：CoreMIDI 直封**（`Services/MIDI/CoreMIDISource.swift`），不引第三方、协议面留待日后替换。详见 `docs/spikes/midi-coremidi.md` §3。
- 状态：已按 brief 授权的 fallback 落地；若 Hermes 希望 P2 换回 SwiftMIDI/MIDIKit，只需实现一个新的 `MIDIEventSource`，改动面限于 Services/MIDI。

## F2 · 本机无 iPhone 16 Pro 模拟器

- brief §1/§5 的 build destination 为 `iPhone 16 Pro`；本机 Xcode 26.6 只有 iOS 26.5 运行时（iPhone 17 系列）。
- 处理：build/test destination 用 `iPhone 17 Pro`（README、Scripts/build.sh 已写死并注释）；部署目标保持 iOS 17.0，不影响真机。
- 状态：环境事实，非代码问题。
