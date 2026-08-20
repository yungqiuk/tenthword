import Foundation

/// Приведение словоформы к словарной форме: `кровати → кровать`.
///
/// Без этого шага русская морфология убивает попадание в словарь: у существительного
/// двенадцать форм, у глагола — за пятьдесят.
public protocol Lemmatizer {
    /// Леммы для всех токенов, в том же порядке. Длина результата равна длине `tokens`.
    ///
    /// Принимает весь текст целиком, а не отдельные слова: разбор по контексту точнее,
    /// и это позволяет реализациям вроде `NLTagger` работать за один проход.
    func lemmas(for tokens: [WordToken], in text: String) -> [String]
}

/// Заглушка: лемма — это само слово в нижнем регистре.
/// Для тестов и для платформ без `NaturalLanguage`.
public struct PassthroughLemmatizer: Lemmatizer {
    public init() {}

    public func lemmas(for tokens: [WordToken], in text: String) -> [String] {
        tokens.map { $0.surface.lowercased() }
    }
}

/// Леммы берутся из готовой таблицы «словоформа → лемма».
/// Используется в эталонных тестах, где нужен предсказуемый разбор без NLTagger.
public struct TableLemmatizer: Lemmatizer {
    private let table: [String: String]

    public init(_ table: [String: String]) {
        self.table = table
    }

    public func lemmas(for tokens: [WordToken], in text: String) -> [String] {
        tokens.map { token in
            let key = token.surface.lowercased()
            return table[key] ?? key
        }
    }
}

#if canImport(NaturalLanguage)
import NaturalLanguage

/// Лемматизация средствами системы.
///
/// `NLTagger` со схемой `.lemma` умеет русский, работает офлайн и не весит в бандле
/// ни байта. Это отменило исходный план тащить таблицу словоформ OpenCorpora
/// на 15–20 МБ — см. `docs/DECISIONS.md`.
///
/// Промахи бывают: редкие формы, устаревшая орфография, авторские неологизмы.
/// Они закрываются таблицей `overrides`, которая приходит из словаря.
public final class AppleLemmatizer: Lemmatizer {

    private let language: NLLanguage
    private let override: (String) -> String?

    /// `override` спрашивают только про слова, которые реально встретились в главе.
    /// Словарь отвечает запросом по индексу, таблица форм в память не поднимается.
    public init(language: NLLanguage = .russian,
                override: @escaping (String) -> String? = { _ in nil }) {
        self.language = language
        self.override = override
    }

    public func lemmas(for tokens: [WordToken], in text: String) -> [String] {
        var result = tokens.map { $0.surface.lowercased() }
        guard !tokens.isEmpty else { return result }

        // Смещения UTF-16 переводим в String.Index одним проходом: смещения
        // возрастают, поэтому каждый следующий индекс считается от предыдущего.
        // Иначе получился бы квадрат по длине главы.
        var positionOfIndex: [String.Index: Int] = [:]
        positionOfIndex.reserveCapacity(tokens.count)
        var cursor = text.utf16.startIndex
        var consumed = 0
        for (i, token) in tokens.enumerated() {
            guard let moved = text.utf16.index(cursor, offsetBy: token.utf16Offset - consumed,
                                               limitedBy: text.utf16.endIndex) else { break }
            cursor = moved
            consumed = token.utf16Offset
            if let stringIndex = String.Index(cursor, within: text) {
                positionOfIndex[stringIndex] = i
            }
        }

        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            if let lemma = tag?.rawValue, !lemma.isEmpty,
               let position = positionOfIndex[range.lowerBound],
               position < result.count {
                result[position] = lemma.lowercased()
            }
            return true
        }

        // Исключения важнее системного разбора.
        for (i, token) in tokens.enumerated() {
            if let exception = override(token.surface.lowercased()) {
                result[i] = exception
            }
        }

        return result
    }
}
#endif
