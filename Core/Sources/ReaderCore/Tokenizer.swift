import Foundation

/// Слово, найденное в тексте книги.
///
/// Смещения — в единицах UTF-16, потому что TextKit, `NSRange` и `NSAttributedString`
/// работают именно в них. Любое другое представление пришлось бы конвертировать
/// на каждом кадре прокрутки.
public struct WordToken: Equatable, Sendable, Codable {

    /// Как слово выглядит в книге: «кровати», «Сегодня».
    public let surface: String

    /// Смещение начала слова от начала текста, в единицах UTF-16.
    public let utf16Offset: Int

    /// Длина слова в единицах UTF-16.
    public let utf16Length: Int

    /// Порядковый номер слова в тексте, с нуля. Участвует в отборе.
    public let ordinal: Int

    /// Слово стоит в начале предложения.
    /// Нужно, чтобы отличить имя собственное от обычного слова с заглавной буквы.
    public let startsSentence: Bool

    public init(surface: String, utf16Offset: Int, utf16Length: Int,
                ordinal: Int, startsSentence: Bool) {
        self.surface = surface
        self.utf16Offset = utf16Offset
        self.utf16Length = utf16Length
        self.ordinal = ordinal
        self.startsSentence = startsSentence
    }

    /// Слово написано с заглавной буквы.
    public var isCapitalized: Bool {
        guard let first = surface.first else { return false }
        return first.isUppercase
    }

    /// Похоже на имя собственное: заглавная буква не в начале предложения.
    /// Такие слова не переводятся никогда, ни на каком проценте.
    public var looksLikeProperNoun: Bool {
        isCapitalized && !startsSentence
    }
}

/// Разбор текста на слова.
///
/// Правила намеренно простые и одинаковые в Swift и в эталонной реализации на Python
/// (`tools/make_golden.py`). Любое усложнение здесь ломает эталонные тесты — и это
/// хорошо, потому что заставляет менять обе реализации сразу.
///
/// - Слово — максимальная цепочка буквенных символов.
/// - Дефис и апостроф остаются внутри слова, если с обеих сторон от них буквы:
///   «где-то» — одно слово, а «— он» — не слово.
/// - Цифры словами не считаются и разрывают цепочку.
/// - Начало предложения — начало текста либо любой из символов `. ! ? …` перед словом.
public enum Tokenizer {

    private static let sentenceEnders: Set<Character> = [".", "!", "?", "…"]
    private static let wordJoiners: Set<Character> = ["-", "'", "\u{2019}"]

    public static func tokenize(_ text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var buffer = ""
        var bufferStart = 0
        var offset = 0
        var ordinal = 0
        var atSentenceStart = true

        let characters = Array(text)

        func flush() {
            guard !buffer.isEmpty else { return }
            tokens.append(WordToken(surface: buffer,
                                    utf16Offset: bufferStart,
                                    utf16Length: offset - bufferStart,
                                    ordinal: ordinal,
                                    startsSentence: atSentenceStart))
            ordinal += 1
            atSentenceStart = false
            buffer = ""
        }

        for (i, character) in characters.enumerated() {
            if character.isLetter {
                if buffer.isEmpty { bufferStart = offset }
                buffer.append(character)
            } else if wordJoiners.contains(character),
                      !buffer.isEmpty,
                      i + 1 < characters.count,
                      characters[i + 1].isLetter {
                buffer.append(character)
            } else {
                flush()
                if sentenceEnders.contains(character) { atSentenceStart = true }
            }
            offset += character.utf16.count
        }
        flush()

        return tokens
    }
}
