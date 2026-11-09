import SheetMusicCore
import SheetMusicLayout
import SwiftUI

// G11 指法叠加 Stage A（ADR-0014）：.mscz 路径的 fingerings 已抵达 Score
// （MSCXDecoder+Fingering，探针测试 FingeringProbeTests 实证），本文件补渲染层
// 缺口——app 层叠加指法数字。红线同 G7/ADR-0009：不改 Piece.status、不写
// Take/TakeAnalysis、不触发判分链；不改 swift-sheet-music 包源码。Stage A 只交付
// 数据 + 纯 builder + 提前放好的 overlay 视图；PracticeScoreScrollView 的
// 「指法」开关接线是 Stage B（单独批次），本文件不挂任何 @State。
//
// 无指法数据源的谱（.musicxml/.mxl/.mid 导入、内置拜厄/哈农）fingerings 自然为
// 空数组 → builder 返回空集，Stage B 开关点了也只是没有标注，不报错（ADR-0014
// 红线：不造假装饰）。

/// 单个符头的指法标注（文档坐标 + 文本）。
struct FingeringAnnotation: Equatable {
    /// 符头框（与 NumberedAnnotation 的 noteFrame 同构，宽高 sp*1.1）。
    let frame: CGRect
    /// 如 "1" "5"——取 role == .fingering 的首条；空白串不产生标注。
    let text: String
}

enum FingeringAnnotationBuilder {

    /// 遍历 document 的 system/measure/.chord，按符头文档几何 + score 指法数据
    /// 生成标注。纯函数、无副作用。规则（ADR-0014 实现要点）：
    /// - 只取 role == .fingering 的首条——吉他手（leftHandGuitar/rightHandGuitar）、
    ///   弦号（stringNumber）、other 一律不显示，避免把 p/i/m/a 或圈号误标成指法；
    /// - text trim 后为空 → 跳过该音（MuseScore 允许空 <Fingering> 元素）；
    /// - `score[note.noteID]` 为 nil（含 grace 合成 ID 1000/2000 段）→ 跳过；
    /// - 无指法的音不产生标注（空 fingerings 自然为空集，不报错）。
    ///
    /// 几何遍历完全照抄 NumberedAnnotationBuilder.build（G7 已真机验收的路径）：
    /// 文档 (0,0) = ScoreView 左上，中心 = system.origin + measure.origin +
    /// note.origin，x 再加 mirrorDx（二度叠置时符头画在词干对侧）。只处理普通
    /// `.chord`——`.graceChord` 不在 11 槽位分支内，天然跳过。
    static func build(score: Score, document: LayoutDocument) -> [FingeringAnnotation] {
        let sp = document.metrics.sp
        var annotations: [FingeringAnnotation] = []
        for system in document.systems {
            for measure in system.measures {
                for element in measure.elements {
                    // 11 个槽位顺序：notes, duration, stem, stemOrigin, hasArpeggio,
                    // arpeggioRawType, isBeamed, voiceIndex, stemExtension,
                    // stemIsInvisible, mag；不关心的用 _，但顺序/数量必须对
                    // （与 NumberedAnnotationBuilder 逐字一致，漂移即几何错位）。
                    guard case let .chord(notes, _, stem, _, _, _, _, _, _, _, _) = element else { continue }
                    for note in notes {
                        guard let noteModel = score[note.noteID] else { continue }
                        guard let fingering = noteModel.fingerings.first(where: { $0.role == .fingering }) else { continue }
                        let text = fingering.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        let centerX = system.origin.x + measure.origin.x
                            + note.origin.x + note.mirrorDx(stem: stem, sp: sp)
                        let centerY = system.origin.y + measure.origin.y + note.origin.y
                        annotations.append(FingeringAnnotation(
                            frame: noteFrame(centerX: centerX, centerY: centerY, sp: sp),
                            text: text))
                    }
                }
            }
        }
        return annotations
    }

    /// 与 NumberedAnnotationBuilder.noteFrame 相同的符头框几何：以符头中心为
    /// 中心、宽高 sp*1.1 的小方框。纯几何、不依赖 layout，独立可单测
    /// （testNoteFrameMatchesNumberedGeometry 锁两处同构）。
    static func noteFrame(centerX: CGFloat, centerY: CGFloat, sp: CGFloat) -> CGRect {
        let side = sp * 1.1
        return CGRect(
            x: centerX - side / 2,
            y: centerY - side / 2,
            width: side,
            height: side)
    }
}

/// SwiftUI overlay（Stage A 提前放好，Stage B 只在 PracticeScoreScrollView 接线
/// 「指法」开关）：每条标注一个 Text，画在符头**下方**。
///
/// 位置（ADR-0014 决策三）：简谱数字标符头上方（G7 既有，上移 sp*1.6），指法标
/// 符头下方（下移 sp*1.4）——两开关独立、可同开，天然零冲突，不为重叠改几何。
/// 右手谱指法可能被符干挡住，属已拍板的可接受取舍。字号 sp*1.2 semibold（介于
/// 符头与简谱 sp*1.35 之间，可读且不压符头）。allowsHitTesting(false) 不挡谱面
/// 手势。墨色 scoreInk（#1C1917 符头墨黑 token；画在白纸上，不能用浅米色
/// textPrimary——真机不可见，G7 踩过）。
struct FingeringsOverlayView: View {
    let annotations: [FingeringAnnotation]
    let sp: CGFloat

    var body: some View {
        ForEach(Array(annotations.enumerated()), id: \.offset) { _, annotation in
            Text(annotation.text)
                .font(.system(size: sp * 1.2, weight: .semibold))
                .foregroundStyle(Color.scoreInk)
                // frame 仍是符头框（noteFrame 几何/测试不变），仅渲染位置下移：
                // 整体中心相对符头中心下移 sp*1.4（约一个符头高度 + 间隙）。
                .position(x: annotation.frame.midX, y: annotation.frame.midY + sp * 1.4)
        }
        .allowsHitTesting(false)
    }
}
