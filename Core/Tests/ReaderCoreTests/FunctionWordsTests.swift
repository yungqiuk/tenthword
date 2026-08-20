import XCTest
@testable import ReaderCore

final class FunctionWordsTests: XCTestCase {

    func testCoversCommonServiceWords() {
        for word in ["в", "на", "с", "и", "но", "не", "я", "он", "который", "быть", "чтобы"] {
            XCTAssertTrue(FunctionWords.contains(word), "«\(word)» должно быть служебным")
        }
    }

    func testDoesNotSwallowContentWords() {
        for word in ["кровать", "яблоко", "бежать", "холодный", "медленно", "сад"] {
            XCTAssertFalse(FunctionWords.contains(word),
                           "«\(word)» — знаменательное слово, его нельзя откладывать в хвост")
        }
    }

    /// «Казался», «стал», «был» — связки. Читатель ставил приложение не ради них.
    func testLinkingVerbsAreFunctionWords() {
        for word in ["быть", "стать", "становиться", "казаться", "выглядеть"] {
            XCTAssertTrue(FunctionWords.contains(word))
        }
    }
}

final class PrepositionRulesTests: XCTestCase {

    func testFallsBackToCommonVariant() {
        let result = PrepositionRules.english(for: "между", governingVerb: nil)
        XCTAssertEqual(result?.word, "between")
    }

    /// Английский предлог зависит от падежа, которого у нас нет. Устойчивые
    /// сочетания — то немногое, что мы можем поймать точно.
    func testCollocationBeatsCommonVariant() {
        XCTAssertEqual(PrepositionRules.english(for: "с", governingVerb: nil)?.word, "with")
        XCTAssertEqual(PrepositionRules.english(for: "с", governingVerb: "встать")?.word, "from",
                       "«встал с кровати» — это from, а не with")

        XCTAssertEqual(PrepositionRules.english(for: "на", governingVerb: nil)?.word, "on")
        XCTAssertEqual(PrepositionRules.english(for: "на", governingVerb: "лаять")?.word, "at",
                       "«лаять на» — это bark at, а не bark on")
    }

    func testUnknownPrepositionGivesNothing() {
        XCTAssertNil(PrepositionRules.english(for: "кровать", governingVerb: nil))
    }

    func testNoteExplainsTheChoice() {
        let collocation = PrepositionRules.english(for: "от", governingVerb: "блестеть")
        XCTAssertEqual(collocation?.word, "with")
        XCTAssertTrue(collocation?.note.contains("устойчивое") == true)

        let common = PrepositionRules.english(for: "без", governingVerb: nil)
        XCTAssertTrue(common?.note.contains("падеж") == true)
    }
}
