import XCTest
import Foundation
@testable import ReaderCore

/// Проверка на настоящем словаре: слова, у которых в Викисловаре взяло верх
/// редкое значение, не должны попадать в перевод ни при каком проценте.
/// Запуск: TENTHWORD_DICT=Data/ru-en.sqlite swift test --filter DictionaryGuardProbe
final class DictionaryGuardProbe: XCTestCase {

    func testNoisyWordsNeverTranslated() throws {
        guard let path = ProcessInfo.processInfo.environment["TENTHWORD_DICT"],
              let dictionary = try? SQLiteDictionary(path: path) else {
            throw XCTSkip("нет TENTHWORD_DICT")
        }
        let text = """
        У меня есть сад. Ничего, что там темно. Ага, сказал он. Мир был тихим,
        и всё равно пора было идти. Он стоит у окна. Эта книга о том, что есть
        и чего нет.
        """
        let engine = TranslationEngine(dictionary: dictionary,
                                       lemmatizer: AppleLemmatizer(language: .russian) {
                                           dictionary.lemmaOverride(for: $0)
                                       })
        let prepared = engine.prepare(text)
        let plan = prepared.plan(percent: 100)
        let translated = Set(plan.items.values.map { $0.surface.lowercased() })
        let forbidden = ["есть", "ничего", "ага", "мир", "равно", "эта", "том", "стоит", "у"]
        for word in forbidden {
            XCTAssertFalse(translated.contains(word),
                           "«\(word)» перевелось: \(plan.items.values.first { $0.surface.lowercased() == word }?.english ?? "")")
        }
        print("переведено: " + plan.items.values.sorted { $0.ordinal < $1.ordinal }
            .map { "\($0.surface)→\($0.english)" }.joined(separator: ", "))
    }
}
