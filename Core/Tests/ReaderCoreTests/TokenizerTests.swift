import XCTest
@testable import ReaderCore

final class TokenizerTests: XCTestCase {

    func testSplitsSimpleSentence() {
        let tokens = Tokenizer.tokenize("Сегодня утром я встал.")
        XCTAssertEqual(tokens.map(\.surface), ["Сегодня", "утром", "я", "встал"])
        XCTAssertEqual(tokens.map(\.ordinal), [0, 1, 2, 3])
    }

    func testOffsetsPointAtTheWord() {
        let text = "Сегодня утром я встал"
        for token in Tokenizer.tokenize(text) {
            let start = text.utf16.index(text.utf16.startIndex, offsetBy: token.utf16Offset)
            let end = text.utf16.index(start, offsetBy: token.utf16Length)
            XCTAssertEqual(String(text.utf16[start..<end]), token.surface,
                           "смещение не совпало со словом «\(token.surface)»")
        }
    }

    func testHyphenStaysInsideWord() {
        XCTAssertEqual(Tokenizer.tokenize("где-то далеко").map(\.surface),
                       ["где-то", "далеко"])
    }

    func testDashBetweenWordsIsNotPartOfWord() {
        // Тире с пробелами — это пунктуация, а не часть слова.
        XCTAssertEqual(Tokenizer.tokenize("он — герой").map(\.surface), ["он", "герой"])
    }

    func testDigitsAreNotWords() {
        let tokens = Tokenizer.tokenize("в 1990 году")
        XCTAssertEqual(tokens.map(\.surface), ["в", "году"])
    }

    func testSentenceStartsAfterTerminators() {
        let tokens = Tokenizer.tokenize("Первое. Второе! Третье? Четвёртое")
        XCTAssertEqual(tokens.map(\.startsSentence), [true, true, true, true])
    }

    func testWordInsideSentenceDoesNotStartIt() {
        let tokens = Tokenizer.tokenize("Меня ждал Пётр дома")
        XCTAssertEqual(tokens.map(\.startsSentence), [true, false, false, false])
    }

    func testProperNounDetection() {
        let tokens = Tokenizer.tokenize("Меня ждал Пётр")
        XCTAssertFalse(tokens[0].looksLikeProperNoun, "«Меня» стоит в начале предложения")
        XCTAssertFalse(tokens[1].looksLikeProperNoun)
        XCTAssertTrue(tokens[2].looksLikeProperNoun, "«Пётр» — имя собственное")
    }

    func testEmptyText() {
        XCTAssertTrue(Tokenizer.tokenize("").isEmpty)
        XCTAssertTrue(Tokenizer.tokenize("   \n  ...  ").isEmpty)
    }

    func testEmojiDoesNotBreakOffsets() {
        // Эмодзи занимает два UTF-16, и смещения после него обязаны это учитывать.
        let text = "дом 🏠 сад"
        let tokens = Tokenizer.tokenize(text)
        XCTAssertEqual(tokens.map(\.surface), ["дом", "сад"])
        let start = text.utf16.index(text.utf16.startIndex, offsetBy: tokens[1].utf16Offset)
        let end = text.utf16.index(start, offsetBy: tokens[1].utf16Length)
        XCTAssertEqual(String(text.utf16[start..<end]), "сад")
    }
}
