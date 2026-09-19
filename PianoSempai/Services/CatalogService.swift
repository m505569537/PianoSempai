import Foundation

// 内置公版教材目录（brief：拜厄/哈农条目本地 JSON，599 仅锁定占位）。
// 目录编排为开发期产物（PRD M3 内容来源铁律），用户审阅后成教学宪法。

struct CatalogEntry: Identifiable, Equatable, Hashable {
    let book: String
    let number: Int
    let referenceTempo: Int

    var id: String { "\(book)-\(number)" }
    var title: String { "\(book) 第\(number)条" }
}

enum CatalogLoader {

    struct CatalogFile: Codable {
        let version: String
        let entries: [Entry]
        struct Entry: Codable {
            let book: String
            let number: Int
            let referenceTempo: Int
        }
    }

    static func loadBuiltin(bundle: Bundle = .main) -> [CatalogEntry] {
        guard let url = bundle.url(forResource: "BuiltinCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CatalogFile.self, from: data) else {
            return []
        }
        return file.entries.map { CatalogEntry(book: $0.book, number: $0.number, referenceTempo: $0.referenceTempo) }
    }
}

// MARK: - 曲目状态（P1 规则，CourseEngine 唯一写手；可测纯函数）

extension CourseEngine {

    enum PieceStatus: String, Equatable {
        case locked, notStarted, practicing, passed
    }

    /// 内置教材条目状态（library.md 状态流转：locked → notStarted → practicing → passed）。
    /// P1 规则：拜厄/哈农 n > current → locked；n == current → practicing；n < current → notStarted。
    /// 车尔尼 599 P1 全部锁定（仅占位；"约 N 周后"取 CoursePathState.projected599Week 真实推算值）。
    static func catalogStatus(book: String, number: Int, pathState: CoursePathState) -> PieceStatus {
        switch book {
        case "拜厄":
            return statusAgainstCurrent(number, current: pathState.currentBeyer)
        case "哈农":
            return statusAgainstCurrent(number, current: pathState.currentHanon)
        case "车尔尼599":
            return .locked
        default:
            return .notStarted
        }
    }

    private static func statusAgainstCurrent(_ number: Int, current: Int) -> PieceStatus {
        if number == current { return .practicing }
        return number < current ? .notStarted : .locked
    }

    /// 599 锁定行的"约 N 周后"文案值（CoursePathState 真实推算；0 表示尚未定级 → 不显示周数）
    static func projected599WeeksLabel(pathState: CoursePathState) -> Int? {
        pathState.projected599Week > 0 ? pathState.projected599Week : nil
    }
}
