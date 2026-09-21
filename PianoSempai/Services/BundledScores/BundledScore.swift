import Foundation

// MARK: 内置公版谱定位（拜厄/哈农 Resources/BundledScores 资源名 → Bundle URL）
// resourceName 是纯函数（不碰磁盘）：三态决策与单测都可用；url() 才真去 Bundle 找。
// 车尔尼599 / 示例曲没有内置谱 → nil：诚实不可用，不拿别的谱冒充（SPEC §10）。

enum BundledScore {

    /// 资源名（不含扩展名）；该书/条数没有内置谱时 nil。
    /// 磁盘实际命名为 beyer_01…beyer_106 / hanon_01…hanon_20（%02d 补零）。
    static func resourceName(book: String, number: Int) -> String? {
        switch book {
        case "拜厄":
            return (1...106).contains(number) ? String(format: "beyer_%02d", number) : nil
        case "哈农":
            return (1...20).contains(number) ? String(format: "hanon_%02d", number) : nil
        default:
            return nil // 车尔尼599 / 示例 / 其他
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
