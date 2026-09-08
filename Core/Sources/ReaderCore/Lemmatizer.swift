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

    /// На сколько кусков резать текст. По числу ядер: `NLTagger` однопоточный,
    /// и на романе он один занимает две трети времени разбора.
    /// Тест выставляет вручную, чтобы сравнить разбор в один поток и в несколько.
    var maximumChunks = ProcessInfo.processInfo.activeProcessorCount

    /// Ниже этого объёма резать не на чем: накладные расходы съедят выигрыш.
    static let chunkThreshold = 20_000

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

        let ranges = chunkRanges(of: text)

        if ranges.count == 1 {
            for (position, lemma) in tags(in: ranges[0], of: text, positions: positionOfIndex)
            where position < result.count {
                result[position] = lemma
            }
        } else {
            // Каждый кусок разбирает свой `NLTagger`, но строку все видят целиком:
            // разрыв проходит по концу абзаца, и слова у края читаются в контексте
            // соседей, как при разборе в один проход.
            var collected = [[(Int, String)]](repeating: [], count: ranges.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: ranges.count) { i in
                let pairs = tags(in: ranges[i], of: text, positions: positionOfIndex)
                lock.lock()
                collected[i] = pairs
                lock.unlock()
            }
            for chunk in collected {
                for (position, lemma) in chunk where position < result.count {
                    result[position] = lemma
                }
            }
        }

        // Исключения важнее системного разбора.
        for (i, token) in tokens.enumerated() {
            if let exception = override(token.surface.lowercased()) {
                result[i] = exception
            }
        }

        return result
    }

    /// Леммы одного куска: пары «номер слова — лемма».
    private func tags(in range: Range<String.Index>, of text: String,
                      positions: [String.Index: Int]) -> [(Int, String)] {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.setLanguage(language, range: text.startIndex..<text.endIndex)

        var pairs: [(Int, String)] = []
        tagger.enumerateTags(in: range,
                             unit: .word,
                             scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, tokenRange in
            if let lemma = tag?.rawValue, !lemma.isEmpty,
               let position = positions[tokenRange.lowerBound] {
                pairs.append((position, lemma.lowercased()))
            }
            return true
        }
        return pairs
    }

    /// Куски примерно равной длины с границами по концам абзацев.
    ///
    /// Резать посреди предложения нельзя: у края куска разбор поедет,
    /// и текст станет зависеть от числа ядер на устройстве.
    private func chunkRanges(of text: String) -> [Range<String.Index>] {
        let wanted = min(maximumChunks, max(1, text.count / Self.chunkThreshold))
        guard wanted > 1 else { return [text.startIndex..<text.endIndex] }

        // Один проход: собираем места переводов строки вместе с их смещениями,
        // чтобы потом искать ближайшую границу без пересчёта расстояний.
        var breaks: [(offset: Int, index: String.Index)] = []
        var offset = 0
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            offset += 1
            if text[index] == "\n" { breaks.append((offset, next)) }
            index = next
        }
        let total = offset
        guard !breaks.isEmpty else { return [text.startIndex..<text.endIndex] }

        var bounds = [text.startIndex]
        var lastOffset = 0
        for i in 1..<wanted {
            let target = total * i / wanted
            guard let candidate = breaks.last(where: { $0.offset <= target }),
                  candidate.offset > lastOffset else { continue }
            bounds.append(candidate.index)
            lastOffset = candidate.offset
        }
        bounds.append(text.endIndex)

        return (0..<bounds.count - 1).map { bounds[$0]..<bounds[$0 + 1] }
    }
}
#endif
