import Foundation

/// Единицы измерения прочитанного.
///
/// Страница считается в знаках, а не в экранах. Иначе крупный шрифт даёт читателю
/// втрое больше «бесплатных страниц» в день — и бесплатный лимит перестаёт значить
/// что-либо одинаковое для разных людей.
public enum ReadingUnits {

    /// Знаков в условной странице. Примерно столько помещается на бумажной странице
    /// покетбука; менять после релиза нельзя — сломается бесплатный лимит у всех.
    public static let charactersPerPage = 1800

    /// Сколько бесплатных страниц в день после триала.
    public static let freeDailyPages = 10

    public static func pageCount(forCharacters characters: Int) -> Int {
        guard characters > 0 else { return 0 }
        return Int(ceil(Double(characters) / Double(charactersPerPage)))
    }

    /// Номер страницы для позиции в тексте, с единицы.
    public static func pageNumber(atCharacter offset: Int) -> Int {
        max(1, offset / charactersPerPage + 1)
    }

    /// Оценка времени чтения. 180 слов в минуту — средний темп чтения
    /// художественной прозы на родном языке. Английские вставки читаются медленнее,
    /// поэтому оценка растёт вместе с процентом перевода.
    public static func minutesToRead(words: Int, translationPercent: Int) -> Int {
        let baseRate = 180.0
        let slowdown = 1.0 + Double(translationPercent) / 100.0 * 0.6
        return max(1, Int((Double(words) / baseRate * slowdown).rounded()))
    }
}
