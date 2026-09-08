import XCTest
@testable import ReaderCore

#if canImport(NaturalLanguage)

/// Разбор в несколько потоков обязан давать ровно тот же результат,
/// что и разбор в один. Иначе текст книги стал бы зависеть от того,
/// сколько ядер у читателя в телефоне.
final class LemmatizerChunkingTests: XCTestCase {

    /// Текст длиннее порога дробления, с абзацами — иначе резать будет негде.
    private var longText: String {
        let paragraph = """
        Дом стоял у самой реки, и по утрам вода была такая тихая, что в ней
        отражалось небо целиком, вместе с облаками и птицами.

        Старик просыпался рано. Он открывал окно, слушал, как в саду падают
        яблоки, и долго сидел за столом с кружкой чая. Кот приходил и садился
        рядом, и это молчание было лучше любого разговора.

        За садом начиналось поле. Летом там росла высокая трава, и ветер ходил
        по ней волнами, как по воде. Осенью поле становилось пустым и серым.

        """
        return String(repeating: paragraph, count: 400)
    }

    func testChunkedMatchesSinglePass() {
        let text = longText
        XCTAssertGreaterThan(text.count, AppleLemmatizer.chunkThreshold * 8,
                             "текст короче порога — дробления не будет, тест ничего не проверит")

        let tokens = Tokenizer.tokenize(text)
        XCTAssertFalse(tokens.isEmpty)

        let single = AppleLemmatizer(language: .russian)
        single.maximumChunks = 1
        let expected = single.lemmas(for: tokens, in: text)

        for chunks in [2, 3, 8] {
            let parallel = AppleLemmatizer(language: .russian)
            parallel.maximumChunks = chunks
            let actual = parallel.lemmas(for: tokens, in: text)

            XCTAssertEqual(actual.count, expected.count)
            let mismatches = zip(expected, actual).enumerated()
                .filter { $0.element.0 != $0.element.1 }
                .prefix(5)
                .map { "\(tokens[$0.offset].surface): \($0.element.0) ≠ \($0.element.1)" }
            XCTAssertTrue(mismatches.isEmpty,
                          "на \(chunks) кусках разбор разошёлся: \(mismatches.joined(separator: ", "))")
        }
    }

    /// Короткому тексту дробление не положено.
    func testShortTextStaysSinglePass() {
        let text = "Кот сидел на кровати и смотрел в окно."
        let tokens = Tokenizer.tokenize(text)
        let lemmatizer = AppleLemmatizer(language: .russian)
        let lemmas = lemmatizer.lemmas(for: tokens, in: text)
        XCTAssertEqual(lemmas.count, tokens.count)
        XCTAssertTrue(lemmas.contains("кровать"), "ожидали лемму «кровать», получили \(lemmas)")
    }
}

#endif
