import Foundation
import SwiftData
import ReaderCore

/// Книга на полке.
///
/// Сам текст в базе не лежит — только путь к разобранному файлу в песочнице.
/// Роман на 700 страниц в SwiftData загонять незачем: он читается кусками,
/// а база нужна для списка и позиции чтения.
@Model
final class Book {

    @Attribute(.unique) var id: UUID
    var title: String
    var author: String

    /// Имя файла в Application Support/Books. Полный путь строится на лету:
    /// песочница переезжает между запусками, абсолютный путь хранить нельзя.
    var fileName: String

    var format: String          // epub | fb2 | txt
    var addedAt: Date

    /// Сколько знаков в книге. Из этого считается число страниц.
    var characterCount: Int

    /// Позиция чтения — смещение в знаках от начала книги.
    var readingOffset: Int

    /// Доля перевода для этой книги. У каждой книги своя: детектив хочется читать,
    /// а учебник — разбирать.
    var translationPercent: Int

    var lastOpenedAt: Date?

    /// Цвет обложки, если картинки в файле не было. Генерируется из названия,
    /// чтобы у книги всегда был свой узнаваемый вид.
    var coverHex: Int

    /// Данные обложки, если они нашлись в EPUB.
    @Attribute(.externalStorage) var coverImage: Data?

    init(title: String, author: String, fileName: String, format: String,
         characterCount: Int) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.fileName = fileName
        self.format = format
        self.addedAt = .now
        self.characterCount = characterCount
        self.readingOffset = 0
        self.translationPercent = 10
        self.lastOpenedAt = nil
        self.coverHex = Book.generatedCoverHex(for: title)
    }

    // MARK: - Производное

    var pageCount: Int { ReadingUnits.pageCount(forCharacters: characterCount) }
    var currentPage: Int { ReadingUnits.pageNumber(atCharacter: readingOffset) }

    /// Доля прочитанного, 0…1. Это полоса под обложкой — не путать с кольцом.
    var readProgress: Double {
        guard characterCount > 0 else { return 0 }
        return min(1, Double(readingOffset) / Double(characterCount))
    }

    var readPercent: Int { Int((readProgress * 100).rounded()) }

    /// Буква на обложке, когда картинки нет.
    var coverGlyph: String {
        String(title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    /// Устойчивый цвет обложки из названия. `StableHash`, а не `hashValue`:
    /// иначе книга меняла бы цвет при каждом запуске приложения.
    private static func generatedCoverHex(for title: String) -> Int {
        let palette: [Int] = [0x243B55, 0x3A2F4A, 0x1F3D3A, 0x4A2B2B,
                              0x2B3A24, 0x3C3320, 0x2A3550, 0x402A38]
        let index = Int(StableHash.fnv1a64(title) % UInt64(palette.count))
        return palette[index]
    }
}

/// Слово, которое читатель встретил. Побочный продукт чтения и основа экрана «Словарь».
@Model
final class VocabularyRecord {

    @Attribute(.unique) var lemma: String
    var english: String
    var gloss: String

    /// Сколько раз слово попадалось в переведённом виде.
    var encounters: Int

    /// Сколько раз читатель нажал на него, чтобы посмотреть перевод.
    /// Много нажатий — слово ещё не выучено.
    var lookups: Int

    var firstSeenAt: Date
    var lastSeenAt: Date

    /// Читатель отметил слово выученным вручную либо оно набрало уверенность.
    var isLearned: Bool

    init(lemma: String, english: String, gloss: String) {
        self.lemma = lemma
        self.english = english
        self.gloss = gloss
        self.encounters = 0
        self.lookups = 0
        self.firstSeenAt = .now
        self.lastSeenAt = .now
        self.isLearned = false
    }

    /// Уверенность от нуля до пяти — столбики на экране «Словарь».
    ///
    /// Растёт от встреч и падает от обращений к переводу: если человек лезет
    /// за переводом, слово он не помнит, сколько бы раз оно ни попадалось.
    var confidence: Int {
        let net = encounters - lookups * 2
        switch net {
        case ..<1: return 0
        case 1...2: return 1
        case 3...5: return 2
        case 6...9: return 3
        case 10...15: return 4
        default: return 5
        }
    }

    /// Порог, после которого слово перестаёт переводиться и освобождает свой процент.
    static let confidenceToRetire = 5
}
