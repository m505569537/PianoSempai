import Foundation
import UIKit

// M7.2 月报 PDF 导出（S22 左下「导出 PDF」→ 系统分享）。
// 系统渲染 + 手动分页：固定 A4 页面（595x842 pt），逐块 draw，y 逼近页底就 beginPage。
// 不用 SwiftUI 截图拼超长单页（长月报会被压扁/裁切）。
// 内容全部来自 MonthlyReportSnapshot 真实值，缺数据显「数据不足」、观察未生成显「观察未生成」——
// 不编造（红线 1）；纸面不含任何服务商 Key（Key 只在 Keychain，红线 3）。

// MARK: - 纸面样式（值与 Nocturne 的 scorePaper/scoreInk/amber 一致；不放彩色资产依赖，单测无需 bundle）

private enum PDFStyle {
    static let paper = UIColor(red: 0.961, green: 0.941, blue: 0.902, alpha: 1)
    static let ink = UIColor(red: 0.110, green: 0.098, blue: 0.090, alpha: 1)
    static let inkMuted = UIColor(red: 0.42, green: 0.40, blue: 0.375, alpha: 1)
    static let amber = UIColor(red: 0.831, green: 0.635, blue: 0.306, alpha: 1)
    static let success = UIColor(red: 0.498, green: 0.663, blue: 0.486, alpha: 1)
    static let danger = UIColor(red: 0.788, green: 0.439, blue: 0.392, alpha: 1)
    static let hairline = UIColor(red: 0.239, green: 0.208, blue: 0.192, alpha: 1)

    static let titleFont = UIFont.systemFont(ofSize: 21, weight: .medium)
    static let sectionFont = UIFont.systemFont(ofSize: 15, weight: .medium)
    static let statValueFont = UIFont.systemFont(ofSize: 17, weight: .medium)
    static let bodyFont = UIFont.systemFont(ofSize: 12)
    static let labelFont = UIFont.systemFont(ofSize: 10)
}

enum MonthlyReportPDF {
    /// A4 @72dpi（pt）
    static let pageSize = CGSize(width: 595, height: 842)

    private static let geometry = Geometry(margin: 44, bottomMargin: 46, contentWidth: pageSize.width - 88)

    // MARK: - 生成

    /// 纯函数：snapshot → PDF data（不碰 SwiftData、不出网、不写文件）。
    static func makePDF(snapshot: MonthlyReportSnapshot, generatedAt: Date = Date()) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            let layout = PDFLayout(context: context, geometry: geometry)
            drawHeader(snapshot, layout: layout)
            drawStats(snapshot, layout: layout)
            drawRoute(snapshot, layout: layout)
            drawWarmupAndOverrides(snapshot, layout: layout)
            drawRhythm(snapshot, layout: layout)
            drawObservation(snapshot, layout: layout)
            drawGeneratedAt(generatedAt, layout: layout)
        }
    }

    // MARK: - 各块（显隐与 S22 视图同一套降级口径）

    private static func drawHeader(_ snapshot: MonthlyReportSnapshot, layout: PDFLayout) {
        layout.paragraph("\(snapshot.year) 年 \(snapshot.month) 月 · 月度报告", font: PDFStyle.titleFont, color: PDFStyle.ink)
        layout.spacing(5)
        layout.paragraph("统计区间：\(periodRangeText(snapshot))（本机真实练习记录汇总）", font: PDFStyle.labelFont, color: PDFStyle.inkMuted)
        layout.spacing(7)
        layout.hairline()
        layout.spacing(12)
    }

    /// 2x2 统计卡（有效练习 / 总时长 / take 数 / 平均周频）
    private static func drawStats(_ snapshot: MonthlyReportSnapshot, layout: PDFLayout) {
        layout.sectionTitle("本月统计")
        layout.statGrid(MonthlyReportText.statCells(snapshot))
        layout.spacing(6)
    }

    /// 教材路线：只写当前值（无月内起点历史、无分母 ⇒ 不写推进箭头与百分比，红线 1）
    private static func drawRoute(_ snapshot: MonthlyReportSnapshot, layout: PDFLayout) {
        layout.sectionTitle("教材路线（\(MonthlyReportText.routeDeclaration)）")
        for row in MonthlyReportText.routeRows(snapshot) {
            let detail = row.detail.isEmpty ? "" : " \(row.detail)"
            layout.paragraph("\(row.title)\(detail)", font: PDFStyle.bodyFont, color: row.isLocked ? PDFStyle.inkMuted : PDFStyle.ink)
        }
    }

    private static func drawWarmupAndOverrides(_ snapshot: MonthlyReportSnapshot, layout: PDFLayout) {
        layout.sectionTitle("热身与门禁")
        let warmup = MonthlyReportText.warmupText(snapshot)
        let warmupColor: UIColor = snapshot.warmupCompletionPct == nil ? PDFStyle.inkMuted : PDFStyle.success
        layout.paragraph("热身完成率：\(warmup)", font: PDFStyle.bodyFont, color: warmupColor)

        if snapshot.overrideCount == 0 {
            layout.paragraph("强开主菜：\(MonthlyReportText.noOverrideText)", font: PDFStyle.bodyFont, color: PDFStyle.ink)
        } else {
            layout.paragraph("强开主菜：\(snapshot.overrideCount) 次", font: PDFStyle.bodyFont, color: PDFStyle.danger)
            let chips = MonthlyReportText.overrideReasonChips(snapshot).joined(separator: "、")
            layout.paragraph("原因分布：\(chips)", font: PDFStyle.bodyFont, color: PDFStyle.ink)
        }
        layout.spacing(4)
        layout.paragraph(MonthlyReportText.overrideFootnote, font: PDFStyle.labelFont, color: PDFStyle.inkMuted)
    }

    private static func drawRhythm(_ snapshot: MonthlyReportSnapshot, layout: PDFLayout) {
        layout.sectionTitle("节奏稳定度")
        switch MonthlyReportText.rhythm(snapshot) {
        case .insufficient:
            layout.paragraph(MonthlyReportText.rhythmInsufficientText, font: PDFStyle.bodyFont, color: PDFStyle.inkMuted)
        case .trend:
            layout.paragraph(MonthlyReportText.rhythmText(MonthlyReportText.rhythm(snapshot)), font: PDFStyle.bodyFont, color: PDFStyle.ink)
        }
    }

    /// 手型趋势整段不渲染：无视频/侧拍模型（refsVideoCount 恒 0），降级隐藏（红线 1）。
    private static func drawObservation(_ snapshot: MonthlyReportSnapshot, layout: PDFLayout) {
        layout.sectionTitle("Neko 的本月观察")
        if snapshot.observationStatus == "ok" {
            if !snapshot.observationTitle.isEmpty {
                layout.paragraph(snapshot.observationTitle, font: PDFStyle.sectionFont, color: PDFStyle.ink)
                layout.spacing(4)
            }
            layout.paragraph(
                snapshot.observationBody.isEmpty ? "（观察正文为空）" : snapshot.observationBody,
                font: PDFStyle.bodyFont,
                color: PDFStyle.ink
            )
            if let model = snapshot.observationProviderModel, !model.isEmpty {
                layout.spacing(6)
                layout.paragraph("本次观察由 \(model) 生成", font: PDFStyle.labelFont, color: PDFStyle.inkMuted)
            }
        } else {
            // pending / failed：静态汇总，如实说明（不编一段观察）
            layout.paragraph(MonthlyReportText.observationNotGeneratedText, font: PDFStyle.bodyFont, color: PDFStyle.inkMuted)
        }
        let chips = MonthlyReportText.observationChips(snapshot).map(\.text)
        if !chips.isEmpty {
            layout.spacing(6)
            layout.paragraph("证据：\(chips.joined(separator: "、"))", font: PDFStyle.labelFont, color: PDFStyle.inkMuted)
        }
    }

    private static func drawGeneratedAt(_ generatedAt: Date, layout: PDFLayout) {
        layout.spacing(16)
        layout.hairline()
        layout.spacing(8)
        layout.paragraph("生成时间：\(Self.stamp(generatedAt))", font: PDFStyle.labelFont, color: PDFStyle.inkMuted)
    }

    // MARK: - 工具

    /// 「2026-09-01 至 2026-09-30」（由 snapshot 的 year/month 反查真实月界）
    private static func periodRangeText(_ snapshot: MonthlyReportSnapshot) -> String {
        guard let start = MonthlyCalendar.monthStart(year: snapshot.year, month: snapshot.month),
              let nextStart = MonthlyCalendar.nextMonthStart(year: snapshot.year, month: snapshot.month),
              let lastDay = MonthlyCalendar.calendar.date(byAdding: .day, value: -1, to: nextStart) else {
            return snapshot.periodKey
        }
        return "\(Self.stamp(start)) 至 \(Self.stamp(lastDay))"
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = MonthlyCalendar.calendar
        formatter.timeZone = MonthlyCalendar.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static func stamp(_ date: Date) -> String {
        stampFormatter.string(from: date)
    }
}

// MARK: - 页面布局（y 坐标管理 + 分页）

private struct Geometry {
    var margin: CGFloat
    var bottomMargin: CGFloat
    var contentWidth: CGFloat
}

/// 一页纸上的书写位置：paragraph/sectionTitle/statGrid 内部按需 beginPage，调用方不用管分页。
private final class PDFLayout {
    private let context: UIGraphicsPDFRendererContext
    private let geometry: Geometry
    private var pageStarted = false
    private var y: CGFloat = 0

    init(context: UIGraphicsPDFRendererContext, geometry: Geometry) {
        self.context = context
        self.geometry = geometry
    }

    var contentWidth: CGFloat { geometry.contentWidth }

    // MARK: 段落

    func paragraph(_ text: String, font: UIFont, color: UIColor) {
        let height = paragraphHeight(text, font: font, width: contentWidth)
        ensure(height)
        _ = textAt(text, font: font, color: color, x: geometry.margin, y: y, width: contentWidth)
        y += height
    }

    /// 小节标题：标题 + 至少两行内容同页，避免标题孤行落在页底
    func sectionTitle(_ text: String) {
        spacing(18)
        let height = paragraphHeight(text, font: PDFStyle.sectionFont, width: contentWidth)
        ensure(height + 56)
        _ = textAt(text, font: PDFStyle.sectionFont, color: PDFStyle.ink, x: geometry.margin, y: y, width: contentWidth)
        y += height
    }

    func spacing(_ value: CGFloat) { y += value }

    func hairline() {
        ensure(1)
        let cg = context.cgContext
        cg.setStrokeColor(PDFStyle.hairline.cgColor)
        cg.setLineWidth(0.6)
        cg.move(to: CGPoint(x: geometry.margin, y: y))
        cg.addLine(to: CGPoint(x: geometry.margin + contentWidth, y: y))
        cg.strokePath()
        y += 1
    }

    // MARK: 2x2 统计格

    func statGrid(_ cells: [MonthlyStatCell]) {
        let cellHeight: CGFloat = 58
        let totalHeight = cellHeight * 2
        ensure(totalHeight + 10)
        let top = y
        let box = CGRect(x: geometry.margin, y: top, width: contentWidth, height: totalHeight)

        let cg = context.cgContext
        cg.setStrokeColor(PDFStyle.hairline.cgColor)
        cg.setLineWidth(0.6)
        cg.stroke(box)
        cg.move(to: CGPoint(x: box.midX, y: box.minY))
        cg.addLine(to: CGPoint(x: box.midX, y: box.maxY))
        cg.move(to: CGPoint(x: box.minX, y: box.midY))
        cg.addLine(to: CGPoint(x: box.maxX, y: box.midY))
        cg.strokePath()

        let columnWidth = contentWidth / 2
        for (index, cell) in cells.enumerated() {
            let row = index / 2
            let column = index % 2
            let x = geometry.margin + 8 + CGFloat(column) * columnWidth
            let cellTop = top + 8 + CGFloat(row) * cellHeight
            textAt(cell.value, font: PDFStyle.statValueFont, color: PDFStyle.amber, x: x, y: cellTop, width: columnWidth - 16)
            textAt(cell.label, font: PDFStyle.labelFont, color: PDFStyle.inkMuted, x: x, y: cellTop + 26, width: columnWidth - 16)
        }
        y = box.maxY
    }

    // MARK: 分页

    private func ensure(_ height: CGFloat) {
        if !pageStarted || y + height > MonthlyReportPDF.pageSize.height - geometry.bottomMargin {
            context.beginPage()
            pageStarted = true
            y = geometry.margin
            paintBackground()
        }
    }

    private func paintBackground() {
        let cg = context.cgContext
        cg.setFillColor(PDFStyle.paper.cgColor)
        cg.fill(CGRect(origin: .zero, size: MonthlyReportPDF.pageSize))
    }

    // MARK: 文字测量与绘制

    private func attributes(_ font: UIFont, _ color: UIColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    private func paragraphHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let bounds = NSString(string: text).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(font, .black), // 颜色不影响测量
            context: nil
        )
        return ceil(bounds.height)
    }

    @discardableResult
    private func textAt(_ text: String, font: UIFont, color: UIColor, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        let height = paragraphHeight(text, font: font, width: width)
        NSString(string: text).draw(
            with: CGRect(x: x, y: y, width: width, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(font, color),
            context: nil
        )
        return height
    }
}
