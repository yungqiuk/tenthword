import XCTest
@testable import ReaderCore

final class TranslationPlanTests: XCTestCase {

    // MARK: - Приспособления

    private func makeEngine(learned: Set<String> = []) -> TranslationEngine {
        let entries = [
            DictionaryEntry(lemma: "утро", english: "morning", pos: .noun),
            DictionaryEntry(lemma: "кровать", english: "bed", pos: .noun),
            DictionaryEntry(lemma: "сад", english: "garden", pos: .noun),
            DictionaryEntry(lemma: "яблоко", english: "apple", pos: .noun),
            DictionaryEntry(lemma: "встать", english: "get up", pos: .verb),
            DictionaryEntry(lemma: "пойти", english: "go", pos: .verb),
            DictionaryEntry(lemma: "ключ", english: "key", pos: .noun, isAmbiguous: true),
            DictionaryEntry(lemma: "я", english: "I", pos: .pronoun),
            DictionaryEntry(lemma: "с", english: "with", pos: .preposition),
            DictionaryEntry(lemma: "в", english: "in", pos: .preposition),
            DictionaryEntry(lemma: "за", english: "behind", pos: .preposition),
            DictionaryEntry(lemma: "чтобы", english: "in order to", pos: .conjunction)
        ]
        let ranks = ["утро": 620, "кровать": 1450, "сад": 1980, "яблоко": 4300,
                     "встать": 810, "пойти": 240, "я": 12, "с": 21, "в": 3, "за": 48]
        let lemmas = ["утром": "утро", "встал": "встать", "кровати": "кровать",
                      "пойти": "пойти", "сад": "сад", "яблоками": "яблоко",
                      "ключом": "ключ"]

        return TranslationEngine(
            dictionary: InMemoryDictionary(entries: entries, ranks: ranks),
            lemmatizer: TableLemmatizer(lemmas),
            learnedLemmas: learned
        )
    }

    private let sample = "Сегодня утром я встал с кровати, чтобы пойти в сад за яблоками."

    // MARK: - Главное свойство

    /// План на большем проценте обязан содержать в себе весь план на меньшем.
    ///
    /// Если это сломать, текст будет перетасовываться под пальцем читателя, пока он
    /// крутит кольцо, и вернуться к прежнему набору слов станет невозможно.
    /// Это то свойство, ради которого порядок кандидатов считается один раз
    /// и не зависит от процента.
    func testMonotonicity() {
        let prepared = makeEngine().prepare(sample)

        var previous = Set<Int>()
        for percent in 0...100 {
            let current = Set(prepared.plan(percent: percent).items.keys)
            XCTAssertTrue(previous.isSubset(of: current),
                          "на \(percent)% пропали слова, которые были на \(percent - 1)%: " +
                          "\(previous.subtracting(current).sorted())")
            previous = current
        }
    }

    func testCountNeverShrinks() {
        let prepared = makeEngine().prepare(sample)
        var previous = 0
        for percent in 0...100 {
            let count = prepared.plan(percent: percent).translatedCount
            XCTAssertGreaterThanOrEqual(count, previous, "на \(percent)% слов стало меньше")
            previous = count
        }
    }

    func testSamePercentGivesSameResult() {
        let first = makeEngine().prepare(sample).plan(percent: 30)
        let second = makeEngine().prepare(sample).plan(percent: 30)
        XCTAssertEqual(Set(first.items.keys), Set(second.items.keys),
                       "отбор недетерминирован — ищите Hasher вместо StableHash")
    }

    // MARK: - Смысл процента

    /// Процент считается от всех слов текста, а не от переводимых. Решение заказчика.
    func testPercentIsMeasuredAgainstAllWords() {
        let prepared = makeEngine().prepare(sample)
        XCTAssertEqual(prepared.totalWords, 12)

        // 25% от 12 слов — это 3 слова, независимо от того, сколько всего переводимых.
        XCTAssertEqual(prepared.plan(percent: 25).translatedCount, 3)
        XCTAssertEqual(prepared.plan(percent: 50).translatedCount, 6)
    }

    func testZeroPercentTranslatesNothing() {
        XCTAssertEqual(makeEngine().prepare(sample).plan(percent: 0).translatedCount, 0)
    }

    func testPercentIsClamped() {
        let prepared = makeEngine().prepare(sample)
        XCTAssertEqual(prepared.plan(percent: -20).translatedCount, 0)
        XCTAssertEqual(prepared.plan(percent: 300).translatedCount,
                       prepared.plan(percent: 100).translatedCount)
    }

    /// На 100% часть слов остаётся русской: их нет в словаре. Показывать надо
    /// фактическую долю, а не круглую цифру.
    func testHundredPercentIsHonest() {
        let prepared = makeEngine().prepare(sample)
        let plan = prepared.plan(percent: 100)
        XCTAssertGreaterThan(plan.untranslatableCount, 0, "«Сегодня» нет в словаре")
        XCTAssertLessThan(plan.actualPercent, 100)
        XCTAssertEqual(plan.translatedCount + plan.untranslatableCount, prepared.totalWords)
    }

    // MARK: - Что исключается

    func testProperNounIsNeverTranslated() {
        let engine = TranslationEngine(
            dictionary: InMemoryDictionary(entries: [
                DictionaryEntry(lemma: "роза", english: "rose", pos: .noun)
            ]),
            lemmatizer: PassthroughLemmatizer()
        )
        // «Роза» в середине предложения — это имя, а не цветок.
        let prepared = engine.prepare("Меня встретила Роза")
        XCTAssertEqual(prepared.plan(percent: 100).translatedCount, 0)
    }

    func testAmbiguousWordIsSkipped() {
        let prepared = makeEngine().prepare("Он открыл дверь ключом")
        XCTAssertFalse(prepared.orderedCandidates.contains { $0.lemma == "ключ" },
                       "«ключ» многозначное: key или spring — без контекста не угадать")
    }

    func testLearnedWordFreesItsPercent() {
        let text = sample
        let withoutLearned = makeEngine().prepare(text).orderedCandidates.count
        let withLearned = makeEngine(learned: ["кровать"]).prepare(text)

        XCTAssertEqual(withLearned.orderedCandidates.count, withoutLearned - 1)
        XCTAssertFalse(withLearned.orderedCandidates.contains { $0.lemma == "кровать" })
    }

    // MARK: - Ярусы

    /// Служебные слова стоят в хвосте очереди: до них дело доходит только
    /// на высоких процентах.
    func testFunctionWordsComeLast() {
        let candidates = makeEngine().prepare(sample).orderedCandidates
        let firstFunction = candidates.firstIndex { $0.isFunctionWord }
        let lastContent = candidates.lastIndex { !$0.isFunctionWord }

        if let firstFunction, let lastContent {
            XCTAssertGreaterThan(firstFunction, lastContent,
                                 "служебное слово пролезло вперёд знаменательного")
        }
    }

    func testLowPercentTakesOnlyContentWords() {
        let plan = makeEngine().prepare(sample).plan(percent: 20)
        for candidate in plan.items.values {
            XCTAssertFalse(candidate.isFunctionWord,
                           "«\(candidate.surface)» переведено на 20%, а это служебное слово")
        }
    }

    // MARK: - Отображение

    func testCapitalIsCarriedOver() {
        let candidate = makeEngine().prepare("Утром я встал").orderedCandidates
            .first { $0.lemma == "утро" }
        XCTAssertEqual(candidate?.display(capitalized: true), "Morning")
        XCTAssertEqual(candidate?.display(capitalized: false), "morning")
    }

    // MARK: - Границы

    func testEmptyText() {
        let prepared = makeEngine().prepare("")
        XCTAssertEqual(prepared.totalWords, 0)
        XCTAssertEqual(prepared.plan(percent: 50).translatedCount, 0)
        XCTAssertEqual(prepared.plan(percent: 50).actualPercent, 0)
    }

    func testTextWithoutKnownWords() {
        let prepared = makeEngine().prepare("Абракадабра шурум-бурум")
        XCTAssertEqual(prepared.orderedCandidates.count, 0)
        XCTAssertEqual(prepared.maximumUsefulPercent, 0)
    }
}
