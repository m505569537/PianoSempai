import Foundation
import SheetMusicCore

// G7 简谱叠加核心层 Stage A（ADR-0009）：MIDI 音高（+ 谱面变音记号）→ 固定调简谱标签
// （数字 1–7 + 升降 + 八度点）。纯函数、零 UI、零几何（LayoutDocument 映射与 overlay 在
// Stage B）。红线同既有各 G：不写 Take/TakeAnalysis、不碰 Piece.status、不触发
// 过关/推进/streak/铺路/矫正；本文件仅 import Foundation 与 SheetMusicCore（后者仅为
// 复用其 `Accidental` 枚举，即 Note.accidental 的类型）。

// SheetMusicCore 的 `Accidental`（rawValue 即 SMuFL SymId，如 "accidentalSharp"）。
// 起别名以免与 NumberedAccidental 混淆。
typealias SheetMusicAccidental = Accidental

/// 固定调简谱标签（ADR-0009 §4–6）。
struct NumberedLabel: Equatable {
    /// 数字 1...7（C D E F G A B）
    let digit: Int
    /// 变音记号（固定调忠实实际音高：黑键必带升降）
    let accidental: NumberedAccidental
    /// 数字上方八度点个数（每高于基准八度一个 +1）
    let octaveDotsUp: Int
    /// 数字下方八度点个数
    let octaveDotsDown: Int
}

enum NumberedAccidental: Equatable {
    case none          // 自然音
    case sharp         // ♯
    case flat          // ♭
    case doubleSharp   // 𝄪
    case doubleFlat    // 𝄫
    case natural       // ♮（显式还原）
}

enum NumberedNotation {

    /// 基准八度：MIDI 60 = C4（中央 C），其八度内数字不带点。
    static let referenceMIDIC = 60

    /// 由 MIDI 音高 + 谱面变音记号求固定调标签。
    ///
    /// 规则（ADR-0009 §5–6，测试钉死）：
    /// - 自然音按 pitch class 直取数字（C=1 … B=7），无记号。
    /// - 谱面 accidental 优先决定等音拼写（数字取哪个自然音为基准）：♯ 基准 pc−1、
    ///   ♭ 基准 pc+1、𝄪 基准 pc−2、𝄫 基准 pc+2（均 mod 12，故 B♯=♯7、C♭=♭1 也成立）。
    /// - accidental 缺省且为黑键时走确定性等音默认：pc ∈ {1,3,6,8} 记 ♯
    ///   （C♯/D♯/F♯/G♯），pc == 10 记 ♭（B♭）；同输入永不摇摆。
    /// - 音高是唯一真值（SheetMusicCore 的 Accidental 文档即注明 display-only）：
    ///   谱面记号与实际音高不一致（如白键 pc 却带 ♯）或记号落在黑键 pc 上时，
    ///   不猜拼写，回退按音高的确定性默认。
    /// - 四分音/箭头/三重/组合等其它 Accidental（真实钢琴谱几乎不出现）：一律按
    ///   缺省处理（由音高确定性兜底），不做四分音猜测。
    /// - 八度点：octave = floor(midiPitch/12) − 1，相对基准八度（referenceMIDIC=60
    ///   即 C4）每高一个八度数字上方 +1 点、每低一个八度下方 +1 点。
    ///
    /// - Parameter midiPitch: Note.pitch（0...127；越界输入防御性处理、不崩）
    /// - Parameter accidental: Note.accidental（可空）
    static func label(midiPitch: Int, accidental: SheetMusicAccidental? = nil) -> NumberedLabel {
        let pc = ((midiPitch % 12) + 12) % 12
        // floor 除法：先减去非负余数再除，midiPitch 为负也不会向零取整。
        let octave = (midiPitch - pc) / 12 - 1
        let referenceOctave = referenceMIDIC / 12 - 1

        let (digit, acc): (Int, NumberedAccidental)
        switch accidental {
        case .sharp:
            (digit, acc) = spelled(basePC: (pc + 11) % 12, fallbackPC: pc, kind: .sharp)
        case .flat:
            (digit, acc) = spelled(basePC: (pc + 1) % 12, fallbackPC: pc, kind: .flat)
        case .doubleSharp:
            (digit, acc) = spelled(basePC: (pc + 10) % 12, fallbackPC: pc, kind: .doubleSharp)
        case .doubleFlat:
            (digit, acc) = spelled(basePC: (pc + 2) % 12, fallbackPC: pc, kind: .doubleFlat)
        case .natural:
            // 显式还原只可能落在自然 pc；防御：黑键带还原时按音高兜底。
            if let d = naturalDigit(of: pc) {
                (digit, acc) = (d, .natural)
            } else {
                (digit, acc) = defaultSpelling(pc: pc)
            }
        default:
            // nil 及四分音/箭头/三重/组合等其它记号：按音高确定性默认。
            (digit, acc) = defaultSpelling(pc: pc)
        }

        return NumberedLabel(
            digit: digit,
            accidental: acc,
            octaveDotsUp: max(0, octave - referenceOctave),
            octaveDotsDown: max(0, referenceOctave - octave)
        )
    }

    // MARK: - 私有映射

    /// 自然音 pc → 数字；黑键 pc 返回 nil。
    private static func naturalDigit(of pc: Int) -> Int? {
        switch pc {
        case 0: return 1  // C
        case 2: return 2  // D
        case 4: return 3  // E
        case 5: return 4  // F
        case 7: return 5  // G
        case 9: return 6  // A
        case 11: return 7 // B
        default: return nil
        }
    }

    /// 按谱面记号拼写：基准 pc 是自然音 → 取其数字 + 该记号；否则（谱面记号与音高
    /// 不一致，如白键 pc 带 ♯）回退按音高的确定性默认拼写。
    private static func spelled(basePC: Int, fallbackPC: Int, kind: NumberedAccidental) -> (Int, NumberedAccidental) {
        if let d = naturalDigit(of: basePC) {
            return (d, kind)
        }
        return defaultSpelling(pc: fallbackPC)
    }

    /// 缺省/兜底拼写：白键直取数字 .none；黑键确定性等音默认 ——
    /// pc ∈ {1,3,6,8} 记 ♯（C♯/D♯/F♯/G♯，数字 = pc−1 自然音），pc == 10 记 ♭（B♭）。
    private static func defaultSpelling(pc: Int) -> (Int, NumberedAccidental) {
        if let d = naturalDigit(of: pc) {
            return (d, .none)
        }
        if pc == 10 {
            return (naturalDigit(of: (pc + 1) % 12)!, .flat) // B♭
        }
        return (naturalDigit(of: (pc + 11) % 12)!, .sharp)   // C♯/D♯/F♯/G♯
    }
}
