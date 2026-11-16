import Foundation

// MARK: 内置公版谱定位（拜厄/哈农/车尔尼599 → Resources/BundledScores 资源名 → Bundle URL）
// resourceName 是纯函数（不碰磁盘）：三态决策与单测都可用；url() 才真去 Bundle 找。
// 未配谱的教材条目返回 nil：诚实不可用，不拿别的谱冒充（SPEC §10）。

enum BundledScore {

    /// 车尔尼599 已随包落盘的条目（补谱时逐个加进来）。
    ///
    /// 必须与 `Resources/BundledScores/c599_*.musicxml` 实际文件**严格一致**：
    /// 这里声明了却没有对应文件，`ScoreAvailability` 会报 `bundledScore` 而
    /// `Bundle.main.url` 取不到，练习室就变成「有谱可用却加载失败」。
    /// `BundledScoreTests` 有断言守着这条不变量。
    static let czerny599BundledNumbers: Set<Int> = [1]

    /// 资源名（不含扩展名）；该书/条数没有内置谱时 nil。
    /// 磁盘实际命名：beyer_01…beyer_106 / hanon_01…hanon_20 / c599_01…（%02d 补零）。
    static func resourceName(book: String, number: Int) -> String? {
        switch book {
        case "拜厄":
            return (1...106).contains(number) ? String(format: "beyer_%02d", number) : nil
        case "哈农":
            return (1...20).contains(number) ? String(format: "hanon_%02d", number) : nil
        case "车尔尼599":
            // 只认已落盘的条目：没导入的编号继续诚实 nil，不预设全覆盖
            guard czerny599BundledNumbers.contains(number) else { return nil }
            return String(format: "c599_%02d", number)
        default:
            return nil // 示例 / 其他
        }
    }

    /// Bundle 内的谱面 URL（资源缺失时为 nil，由调用方诚实报错）
    static func url(book: String, number: Int) -> URL? {
        guard let name = resourceName(book: book, number: number) else { return nil }
        return Bundle.main.url(forResource: name, withExtension: "musicxml")
    }

    /// 该书/条数是否配有内置谱（纯决策，不看磁盘）
    static func hasBundled(book: String, number: Int) -> Bool {
        resourceName(book: book, number: number) != nil
    }
}
