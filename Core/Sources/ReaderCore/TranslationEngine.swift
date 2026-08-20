import Foundation

/// Слово, которое может быть переведено, с посчитанным весом.
public struct Candidate: Equatable, Sendable {

    /// Порядковый номер слова в тексте.
    public let ordinal: Int

    /// Как слово выглядит в книге: «кровати».
    public let surface: String

    /// Словарная форма: «кровать».
    public let lemma: String

    /// Что подставляем в текст: «bed».
    public let english: String

    /// Полное толкование для карточки слова: «кровать, постель».
    public let gloss: String

    public let pos: PartOfSpeech

    /// Служебное слово — последний ярус отбора.
    public let isFunctionWord: Bool

    /// Пояснение для карточки слова.
    public let note: String?

    /// Вес в очереди. Меньше — переводится раньше. Не участвует в равенстве:
    /// сравнивать кандидатов имеет смысл по содержанию, а не по числу с плавающей точкой.
    public let weight: Double

    /// Слово с заглавной буквы в начале предложения — заглавная переносится
    /// на английское: «Небо» → «Sky».
    public func display(capitalized: Bool) -> String {
        guard capitalized, let first = english.first else { return english }
        return first.uppercased() + english.dropFirst()
    }

    public static func == (lhs: Candidate, rhs: Candidate) -> Bool {
        lhs.ordinal == rhs.ordinal && lhs.lemma == rhs.lemma && lhs.english == rhs.english
    }
}

/// Что переводить при данном проценте.
public struct TranslationPlan: Sendable {

    /// Процент, который выставил читатель.
    public let percent: Int

    /// Всего слов в тексте — знаменатель процента.
    public let totalWords: Int

    /// Переводы по порядковому номеру слова.
    public let items: [Int: Candidate]

    /// Сколько слов в тексте вообще не могут быть переведены: нет в словаре,
    /// имя собственное, многозначное. Нужно, чтобы на 100% показать
    /// честное «96% — 4 слова нет в словаре», а не круглую цифру.
    public let untranslatableCount: Int

    public var translatedCount: Int { items.count }

    /// Фактическая доля перевода, в процентах. На высоких значениях расходится
    /// с запрошенным процентом — и это надо показывать читателю.
    public var actualPercent: Int {
        guard totalWords > 0 else { return 0 }
        return Int((Double(translatedCount) / Double(totalWords) * 100).rounded())
    }

    public func candidate(atOrdinal ordinal: Int) -> Candidate? { items[ordinal] }
}

/// Текст, разобранный и готовый к перевода при любом проценте.
///
/// Строится один раз на главу. Порядок кандидатов зафиксирован при построении
/// и **не зависит от процента** — процент только отрезает префикс. Отсюда следует
/// главное свойство продукта: план на 10% содержит в себе весь план на 5%,
/// текст не перетасовывается под пальцем читателя.
/// Кандидат опознаётся номером слова: он уникален в пределах книги.
/// Нужно для `.sheet(item:)` в приложении, но объявлять conformance
/// на стороне приложения нельзя — компилятор справедливо ругается.
extension Candidate: Identifiable {
    public var id: Int { ordinal }
}

public struct PreparedText: Sendable {

    public let tokens: [WordToken]

    /// Кандидаты в порядке перевода: первый переводится раньше всех.
    public let orderedCandidates: [Candidate]

    /// Знаменатель процента — все слова текста, а не только переводимые.
    /// Так решено заказчиком: «10%» значит «каждое десятое слово страницы».
    public var totalWords: Int { tokens.count }

    /// Сколько слов перевести невозможно ни при каком проценте.
    public var untranslatableCount: Int { totalWords - orderedCandidates.count }

    /// Потолок: процент, выше которого добавлять уже нечего.
    public var maximumUsefulPercent: Int {
        guard totalWords > 0 else { return 0 }
        return Int((Double(orderedCandidates.count) / Double(totalWords) * 100).rounded())
    }

    public func plan(percent: Int) -> TranslationPlan {
        let clamped = max(0, min(100, percent))
        let target = Int((Double(clamped) / 100.0 * Double(totalWords)).rounded())
        let taken = orderedCandidates.prefix(max(0, min(target, orderedCandidates.count)))

        var items: [Int: Candidate] = [:]
        items.reserveCapacity(taken.count)
        for candidate in taken { items[candidate.ordinal] = candidate }

        return TranslationPlan(percent: clamped,
                               totalWords: totalWords,
                               items: items,
                               untranslatableCount: untranslatableCount)
    }
}

/// Сборка `PreparedText` из текста главы.
public struct TranslationEngine {

    /// Вклад частотности в вес. Остальное — хеш от позиции.
    ///
    /// Частотность даёт полезность: частые слова учатся первыми.
    /// Хеш даёт разброс по странице, чтобы переведённые слова не собирались
    /// в начале главы. Пропорция подобрана на глаз и подлежит проверке
    /// на реальных книгах.
    public static let frequencyWeight = 0.65

    /// Ранг, выше которого слово считается одинаково редким.
    public static let frequencyHorizon = 20_000.0

    private let dictionary: WordDictionary
    private let lemmatizer: Lemmatizer
    private let learnedLemmas: Set<String>
    private let functionWords: Set<String>

    /// - Parameters:
    ///   - learnedLemmas: слова, которые читатель уже знает. Исключаются из отбора,
    ///     их процент достаётся новым словам.
    ///   - functionWords: список служебных слов. Вынесен в параметр, чтобы эталонные
    ///     тесты проверяли алгоритм отбора, а не содержимое списка.
    public init(dictionary: WordDictionary,
                lemmatizer: Lemmatizer,
                learnedLemmas: Set<String> = [],
                functionWords: Set<String> = FunctionWords.all) {
        self.dictionary = dictionary
        self.lemmatizer = lemmatizer
        self.learnedLemmas = learnedLemmas
        self.functionWords = functionWords
    }

    public func prepare(_ text: String) -> PreparedText {
        let tokens = Tokenizer.tokenize(text)
        guard !tokens.isEmpty else {
            return PreparedText(tokens: [], orderedCandidates: [])
        }

        let lemmas = lemmatizer.lemmas(for: tokens, in: text)
        var candidates: [Candidate] = []
        candidates.reserveCapacity(tokens.count / 2)

        /// Ближайший предшествующий глагол — нужен для устойчивых сочетаний
        /// вроде «лаять на» → *bark at*.
        var lastVerbLemma: String?

        for (i, token) in tokens.enumerated() {
            let lemma = lemmas[i]

            // Имена собственные не переводятся никогда.
            if token.looksLikeProperNoun { continue }

            // Формы местоимений, которые лемматизатор путает с существительными:
            // «о том» — это не книжный том. Проверяем и форму, и лемму.
            if FunctionWords.ambiguousPronounForms.contains(token.surface.lowercased())
                || FunctionWords.ambiguousPronounForms.contains(lemma) { continue }

            guard let entry = dictionary.entry(for: lemma) else { continue }

            if entry.pos == .verb { lastVerbLemma = lemma }

            // Многозначное без контекста переведём неверно — лучше не трогать.
            if entry.isAmbiguous { continue }

            // Выученное слово освобождает свой процент под новое.
            if learnedLemmas.contains(lemma) { continue }

            let isFunction = functionWords.contains(lemma) || !entry.pos.isContent

            var english = entry.english
            var note = entry.note

            if entry.pos == .preposition,
               let rule = PrepositionRules.english(for: lemma, governingVerb: lastVerbLemma) {
                english = rule.word
                note = rule.note
            }

            candidates.append(Candidate(
                ordinal: token.ordinal,
                surface: token.surface,
                lemma: lemma,
                english: english,
                gloss: entry.gloss,
                pos: entry.pos,
                isFunctionWord: isFunction,
                note: note,
                weight: weight(lemma: lemma, ordinal: token.ordinal)
            ))
        }

        candidates.sort { left, right in
            // Ярус: знаменательные раньше служебных, всегда.
            if left.isFunctionWord != right.isFunctionWord {
                return !left.isFunctionWord
            }
            if left.weight != right.weight {
                return left.weight < right.weight
            }
            // Порядок в тексте как последний разрыв — чтобы сортировка была
            // полной и одинаковой на любой платформе.
            return left.ordinal < right.ordinal
        }

        return PreparedText(tokens: tokens, orderedCandidates: candidates)
    }

    private func weight(lemma: String, ordinal: Int) -> Double {
        let frequency: Double
        if let rank = dictionary.frequencyRank(for: lemma) {
            frequency = min(Double(rank) / Self.frequencyHorizon, 1.0)
        } else {
            frequency = 0.5   // о слове ничего не знаем — середина
        }
        let jitter = StableHash.unitInterval("\(lemma)#\(ordinal)")
        return Self.frequencyWeight * frequency + (1 - Self.frequencyWeight) * jitter
    }
}
