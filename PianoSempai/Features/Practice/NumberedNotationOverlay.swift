import SheetMusicCore
import SheetMusicLayout
import SwiftUI

// G7 简谱叠加 UI 批次 Stage B（ADR-0009）：把 Stage A 的固定调简谱标签按符头几何
// 叠加到练习室谱面。红线同既有各 G：不改 Piece.status、不写 Take/TakeAnalysis、
// 不触发过关/推进/streak/铺路/矫正；不改 swift-sheet-music 包源码。本文件不改
// Stage A 的标签算法（NumberedNotation），只做几何遍历与渲染。

/// 单个符头的叠加标注（文档坐标 + 标签）。
struct NumberedAnnotation: Equatable {
    let frame: CGRect
    let label: NumberedLabel
}

enum NumberedAnnotationBuilder {

    /// 遍历 document 的 system/measure/.chord，按符头文档几何 + displayScore 音高生成标注。
    /// 跳过 grace 与无法解析音高的 note。纯函数、无副作用。
    ///
    /// 坐标（全部文档空间）：文档 (0,0) = ScoreView 左上。中心 x/y 按
    /// system.origin + measure.origin + note.origin（chord note 的 origin 在
    /// measure 局部空间）累加，x 再加镜像偏移 mirrorDx（二度叠置时符头画在
    /// 词干对侧）。只处理普通 `.chord`——`.graceChord` 的 noteID 是合成的
    /// （1000/2000 段），score 下标取 nil，本批跳过以免错标；
    /// `score[note.noteID]` 为 nil（含 grace 同因）也跳过该 note。
    ///
    /// 命中测试不用 `ScoreHitTester.elementHitRect(for:)`——其对 note 无效
    /// （`ScoreHitTarget.note` 的 elementID 返回 nil），故自行遍历几何。
    static func build(score: Score, document: LayoutDocument) -> [NumberedAnnotation] {
        let sp = document.metrics.sp
        var annotations: [NumberedAnnotation] = []
        for system in document.systems {
            for measure in system.measures {
                for element in measure.elements {
                    // 11 个槽位顺序：notes, duration, stem, stemOrigin, hasArpeggio,
                    // arpeggioRawType, isBeamed, voiceIndex, stemExtension,
                    // stemIsInvisible, mag；不关心的用 _，但顺序/数量必须对。
                    // .graceChord 不在此分支内 → 天然跳过（见 doc 注释）。
                    guard case let .chord(notes, _, stem, _, _, _, _, _, _, _, _) = element else { continue }
                    for note in notes {
                        guard let noteModel = score[note.noteID] else { continue }
                        let centerX = system.origin.x + measure.origin.x
                            + note.origin.x + note.mirrorDx(stem: stem, sp: sp)
                        let centerY = system.origin.y + measure.origin.y + note.origin.y
                        annotations.append(NumberedAnnotation(
                            frame: noteFrame(centerX: centerX, centerY: centerY, sp: sp),
                            label: NumberedNotation.label(
                                midiPitch: noteModel.pitch,
                                accidental: note.accidental)))
                    }
                }
            }
        }
        return annotations
    }

    /// 符头中心 → 以其为中心、相对 sp 的小尺寸 CGRect（宽高 sp*1.1，
    /// 保证不压五线谱过多）。纯几何、不依赖 layout，独立可单测。
    static func noteFrame(centerX: CGFloat, centerY: CGFloat, sp: CGFloat) -> CGRect {
        let side = sp * 1.1
        return CGRect(
            x: centerX - side / 2,
            y: centerY - side / 2,
            width: side,
            height: side)
    }
}

/// 标签 → 可渲染文本部件（纯数据，便于单测）。
struct NumberedGlyphText: Equatable {
    /// 如 "♯1" "♭7" "1"（变音符号 + 数字）
    let core: String
    /// 上方八度点（每个 "·"，个数 = octaveDotsUp）
    let dotsUp: [String]
    /// 下方八度点
    let dotsDown: [String]

    /// 变音符号映射 sharp→"♯"、flat→"♭"、doubleSharp→"𝄪"、doubleFlat→"𝄫"、
    /// natural→"♮"、none→""；core = 变音符号 + 数字。
    static func from(_ label: NumberedLabel) -> NumberedGlyphText {
        let symbol: String
        switch label.accidental {
        case .none: symbol = ""
        case .sharp: symbol = "♯"
        case .flat: symbol = "♭"
        case .doubleSharp: symbol = "𝄪"
        case .doubleFlat: symbol = "𝄫"
        case .natural: symbol = "♮"
        }
        return NumberedGlyphText(
            core: symbol + "\(label.digit)",
            dotsUp: Array(repeating: "·", count: label.octaveDotsUp),
            dotsDown: Array(repeating: "·", count: label.octaveDotsDown))
    }
}

/// SwiftUI overlay：ForEach annotations，在各 frame 处用 VStack(dotsUp / core / dotsDown)
/// 渲染。允许命中穿透（.allowsHitTesting(false)），不挡谱面手势。
struct NumberedNotationOverlayView: View {
    let annotations: [NumberedAnnotation]
    let sp: CGFloat

    var body: some View {
        // 墨色用 scoreInk（#1C1917，色板既有的符头墨黑 token）——标注画在白纸上，
        // 不能用 textPrimary（浅米色，画在白纸上不可见，真机验收即踩）。
        // 字号 sp*1.35（原 sp*0.95≈7pt 在真机上不可读，调大一档仍不压符头）。
        ForEach(Array(annotations.enumerated()), id: \.offset) { _, annotation in
            let glyph = NumberedGlyphText.from(annotation.label)
            VStack(spacing: 0) {
                ForEach(Array(glyph.dotsUp.enumerated()), id: \.offset) { _, dot in
                    Text(dot).font(.system(size: sp * 0.6, weight: .bold))
                }
                Text(glyph.core)
                    .font(.system(size: sp * 1.35, weight: .semibold))
                ForEach(Array(glyph.dotsDown.enumerated()), id: \.offset) { _, dot in
                    Text(dot).font(.system(size: sp * 0.6, weight: .bold))
                }
            }
            .foregroundStyle(Color.scoreInk)
            // 数字标在符头**上方**（ADR-0009 §「逐音符上方标」），不压符头：
            // 整体中心相对符头中心上移 sp*1.6（约一个符头高度 + 间隙）。
            // frame 仍是符头框（noteFrame 几何/测试不变），仅渲染位置上抬。
            .position(x: annotation.frame.midX, y: annotation.frame.midY - sp * 1.6)
        }
        .allowsHitTesting(false)
    }
}
