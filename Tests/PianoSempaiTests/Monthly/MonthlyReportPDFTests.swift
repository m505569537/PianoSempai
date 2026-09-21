import Foundation
import PDFKit
import XCTest

@testable import PianoSempai

/// M7.2 月报 PDF 导出：A4 分页渲染、非空且以 %PDF 开头、页数 ≥1；
/// 空数据 / 观察未生成 / 全 nil 节奏分都不崩（红线 1：缺数据显「数据不足」而非编造）。
final class MonthlyReportPDFTests: XCTestCase {

    private func makeSnapshot() -> MonthlyReportSnapshot {
        MonthlyReportSnapshot(
            year: 2026,
            month: 9,
            validDays: 14,
            totalDurationSec: 30_720,
            takeCount: 47,
            avgSessionsPerWeek: 3.2,
            beyerCurrent: 48,
            hanonCurrent: 4,
            unlocked599: true,
            current599: 5,
            projected599Week: 44,
            warmupCompletionPct: 79,
            overrideCount: 3,
            overrideReasons: ["时间不够": 2, "other": 1],
            rhythmFirstWeekScore: 52,
            rhythmLastWeekScore: 71,
            weeklyRhythmScores: [52, nil, 63, 71],
            observationTitle: "转指稳住了",
            observationBody: "这个月转指的节奏偏差从 +120ms 收到 +64ms，21 小节的转指明显顺了。下月建议：热身保持每周 3 次哈农 1，主菜速度不要超过 ♩=76；奖励曲可以开始摸《Summer》前 16 小节。",
            observationProviderModel: "百炼 qwen3-max",
            refsTakeCount: 47,
            refsVideoCount: 0,
            observationStatus: "ok",
            generatedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
    }

    private func pageCount(of data: Data) -> Int {
        PDFDocument(data: data)?.pageCount ?? 0
    }

    // MARK: 基本形态

    func testMakePDFReturnsNonEmptyPDFData() {
        let data = MonthlyReportPDF.makePDF(snapshot: makeSnapshot())
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
        XCTAssertGreaterThanOrEqual(pageCount(of: data), 1)
    }

    func testPDFPageSizeIsA4() throws {
        let data = MonthlyReportPDF.makePDF(snapshot: makeSnapshot())
        let page = PDFDocument(data: data)?.page(at: 0)
        let bounds = try XCTUnwrap(page?.bounds(for: .mediaBox))
        XCTAssertEqual(bounds.width, 595, accuracy: 0.5)
        XCTAssertEqual(bounds.height, 842, accuracy: 0.5)
    }

    // MARK: 降级：空数据 / 观察未生成都不崩

    func testEmptySnapshotStillProducesPDF() {
        let data = MonthlyReportPDF.makePDF(snapshot: MonthlyReportSnapshot(year: 2026, month: 2))
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
        XCTAssertGreaterThanOrEqual(pageCount(of: data), 1)
    }

    func testPendingAndFailedObservationStillProducesPDF() {
        for status in ["pending", "failed"] {
            var snapshot = makeSnapshot()
            snapshot.observationStatus = status
            snapshot.observationTitle = ""
            snapshot.observationBody = ""
            let data = MonthlyReportPDF.makePDF(snapshot: snapshot)
            XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF", status)
            XCTAssertGreaterThanOrEqual(pageCount(of: data), 1, status)
        }
    }

    func testLongObservationPaginatesInsteadOfClipping() {
        var snapshot = makeSnapshot()
        // 超长正文：必须分页而不是溢出/截断
        snapshot.observationBody = Array(repeating: "转指偏差收窄，下月继续单手慢练热身。", count: 60).joined()
        let data = MonthlyReportPDF.makePDF(snapshot: snapshot)
        XCTAssertGreaterThan(pageCount(of: data), 1, "超长观察应触发分页")
    }

    func testAllNilRhythmDoesNotCrash() {
        var snapshot = makeSnapshot()
        snapshot.weeklyRhythmScores = [nil, nil]
        snapshot.rhythmFirstWeekScore = nil
        snapshot.rhythmLastWeekScore = nil
        let data = MonthlyReportPDF.makePDF(snapshot: snapshot)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
    }

    func testPDFContainsNoProviderCredentials() {
        // Key 只在 Keychain（红线 3）：纸面只允许出现「服务商·模型」字样
        let data = MonthlyReportPDF.makePDF(snapshot: makeSnapshot())
        let text = String(decoding: data, as: UTF8.self)
        for needle in ["sk-", "apiKey", "api-key", "bearer ", "Authorization"] {
            XCTAssertFalse(text.contains(needle), "PDF 不得含凭据字样：\(needle)")
        }
    }
}
