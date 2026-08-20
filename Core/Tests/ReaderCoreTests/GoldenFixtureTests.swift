import XCTest
@testable import ReaderCore

/// Сверка с эталоном, который сгенерирован независимой реализацией того же
/// алгоритма на Python (`tools/make_golden.py`).
///
/// Смысл в независимости: если Swift и Python дают разный ответ, значит кто-то
/// из них неправ. Чаще всего расходятся токенизатор и `StableHash`.
///
/// **Если тест покраснел — чинить надо код, а не перегенерировать эталон.**
/// Перегенерация оправдана только когда алгоритм отбора менялся сознательно,
/// и тогда меняются обе реализации сразу.
final class GoldenFixtureTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Entry: Decodable {
            let english: String
            let pos: String
            let rank: Int?
            let ambiguous: Bool?
        }
        let text: String
        let lemmas: [String: String]
        let entries: [String: Entry]
        let functionWords: [String]
        let learned: [String]
        let totalWords: Int
        let tokens: [WordToken]
        let order: [Int]
        let plans: [String: [Int]]
    }

    private var fixture: Fixture!
    private var prepared: PreparedText!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "golden_plan", withExtension: "json",
                              subdirectory: "Fixtures"),
            "не найден Fixtures/golden_plan.json — запустите python3 tools/make_golden.py"
        )
        fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))

        let entries = fixture.entries.map { lemma, entry in
            DictionaryEntry(lemma: lemma,
                            english: entry.english,
                            pos: PartOfSpeech(rawValue: entry.pos) ?? .other,
                            isAmbiguous: entry.ambiguous ?? false)
        }
        let ranks = fixture.entries.compactMapValues { $0.rank }

        let engine = TranslationEngine(
            dictionary: InMemoryDictionary(entries: entries, ranks: ranks),
            lemmatizer: TableLemmatizer(fixture.lemmas),
            learnedLemmas: Set(fixture.learned),
            functionWords: Set(fixture.functionWords)
        )
        prepared = engine.prepare(fixture.text)
    }

    func testTokenizerMatchesReference() {
        XCTAssertEqual(prepared.tokens.count, fixture.tokens.count,
                       "разное число слов — разъехались правила разбора на слова")
        for (actual, expected) in zip(prepared.tokens, fixture.tokens) {
            XCTAssertEqual(actual, expected, "слово №\(expected.ordinal) не совпало")
        }
    }

    func testTotalWordsMatchesReference() {
        XCTAssertEqual(prepared.totalWords, fixture.totalWords)
    }

    /// Порядок кандидатов — самое хрупкое место: он зависит от хеша, от формулы веса
    /// и от правил сортировки. Расхождение здесь означает, что план перевода
    /// на разных платформах будет разным.
    func testCandidateOrderMatchesReference() {
        XCTAssertEqual(prepared.orderedCandidates.map(\.ordinal), fixture.order)
    }

    func testEveryPlanMatchesReference() {
        for (percentKey, expected) in fixture.plans.sorted(by: { Int($0.key)! < Int($1.key)! }) {
            let percent = Int(percentKey)!
            let actual = prepared.plan(percent: percent).items.keys.sorted()
            XCTAssertEqual(actual, expected.sorted(), "план на \(percent)% не совпал с эталоном")
        }
    }
}
