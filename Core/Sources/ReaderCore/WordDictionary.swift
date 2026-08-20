import Foundation

/// Часть речи. Определяет, попадёт слово в первый ярус отбора или в последний.
public enum PartOfSpeech: String, Sendable, Codable, CaseIterable {
    case noun, verb, adjective, adverb
    case pronoun, preposition, conjunction, particle, numeral, interjection
    case other

    /// Знаменательные части речи. Только они переводятся до ~55%.
    public var isContent: Bool {
        switch self {
        case .noun, .verb, .adjective, .adverb: return true
        default: return false
        }
    }

    /// Подпись для карточки слова.
    public var russianLabel: String {
        switch self {
        case .noun: return "сущ."
        case .verb: return "глаг."
        case .adjective: return "прил."
        case .adverb: return "нареч."
        case .pronoun: return "мест."
        case .preposition: return "предл."
        case .conjunction: return "союз"
        case .particle: return "частица"
        case .numeral: return "числ."
        case .interjection: return "межд."
        case .other: return ""
        }
    }
}

/// Словарная статья.
public struct DictionaryEntry: Equatable, Sendable, Codable {

    /// Словарная форма: «кровать».
    public let lemma: String

    /// Английский эквивалент, который подставляется в текст: «bed».
    public let english: String

    /// Полное толкование для карточки слова: «кровать, постель».
    public let gloss: String

    public let pos: PartOfSpeech

    /// У слова несколько несвязанных значений («ключ» — key или spring).
    /// Такие слова не переводятся: без контекста мы выберем неверно.
    public let isAmbiguous: Bool

    /// Пояснение для карточки слова: правило выбора предлога, устойчивое сочетание.
    public let note: String?

    public init(lemma: String, english: String, gloss: String = "",
                pos: PartOfSpeech = .other, isAmbiguous: Bool = false, note: String? = nil) {
        self.lemma = lemma
        self.english = english
        self.gloss = gloss.isEmpty ? english : gloss
        self.pos = pos
        self.isAmbiguous = isAmbiguous
        self.note = note
    }
}

/// Источник переводов. Реализации: `SQLiteDictionary` в приложении,
/// `InMemoryDictionary` в тестах.
public protocol WordDictionary {

    func entry(for lemma: String) -> DictionaryEntry?

    /// Ранг частотности: 1 — самое частое слово языка. `nil` — слова нет в списке.
    /// Частые слова переводятся раньше: они полезнее для запоминания.
    func frequencyRank(for lemma: String) -> Int?

    /// Исключение лемматизации для одной словоформы: «кроватью → кровать».
    ///
    /// Запрос точечный, а не выгрузка таблицы целиком: в собранном словаре
    /// полмиллиона словоформ, и держать их все в памяти ради десятка слов
    /// на странице — это секунды на запуске и десятки мегабайт впустую.
    func lemmaOverride(for form: String) -> String?
}

public extension WordDictionary {
    func lemmaOverride(for form: String) -> String? { nil }
}

/// Словарь в памяти. Для тестов и для эталонных фикстур.
public struct InMemoryDictionary: WordDictionary {

    private let entries: [String: DictionaryEntry]
    private let ranks: [String: Int]
    private let overrides: [String: String]

    public init(entries: [DictionaryEntry],
                ranks: [String: Int] = [:],
                lemmaOverrides: [String: String] = [:]) {
        self.entries = Dictionary(entries.map { ($0.lemma, $0) }, uniquingKeysWith: { first, _ in first })
        self.ranks = ranks
        self.overrides = lemmaOverrides
    }

    public func entry(for lemma: String) -> DictionaryEntry? { entries[lemma] }
    public func frequencyRank(for lemma: String) -> Int? { ranks[lemma] }
    public func lemmaOverride(for form: String) -> String? { overrides[form] }
}
