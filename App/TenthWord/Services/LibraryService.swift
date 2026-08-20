import Foundation
import SwiftData
import ReaderCore

/// Словарь и движок перевода — один на всё приложение.
///
/// SQLite открывается один раз: файл в бандле, только для чтения.
/// Если словаря нет, приложение продолжает работать как обычная читалка
/// без перевода — это лучше, чем падать при запуске.
@Observable
final class DictionaryProvider {

    private(set) var dictionary: WordDictionary?
    private(set) var loadError: String?

    var isReady: Bool { dictionary != nil }

    init() { load() }

    private func load() {
        guard let path = Bundle.main.path(forResource: "ru-en", ofType: "sqlite") else {
            loadError = "Словарь не найден в бандле. Соберите его: python3 tools/build_dictionary.py"
            return
        }
        do {
            dictionary = try SQLiteDictionary(path: path)
        } catch {
            loadError = "Словарь не открывается: \(error)"
        }
    }

    /// Движок для конкретной книги: список выученных слов у каждого читателя свой.
    func makeEngine(learnedLemmas: Set<String>) -> TranslationEngine? {
        guard let dictionary else { return nil }
        #if canImport(NaturalLanguage)
        // Исключения спрашиваем по одному слову: таблица форм в словаре
        // на полмиллиона строк, поднимать её в память незачем.
        let lemmatizer = AppleLemmatizer(override: { [dictionary] form in
            dictionary.lemmaOverride(for: form)
        })
        #else
        let lemmatizer = PassthroughLemmatizer()
        #endif
        return TranslationEngine(dictionary: dictionary,
                                 lemmatizer: lemmatizer,
                                 learnedLemmas: learnedLemmas)
    }
}

/// Файлы книг в песочнице.
///
/// Абсолютные пути хранить нельзя: контейнер приложения переезжает между
/// запусками и обновлениями. В базе лежит только имя файла.
enum BookStorage {

    static var directory: URL {
        let base = URL.applicationSupportDirectory.appending(path: "Books")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func url(for fileName: String) -> URL {
        directory.appending(path: fileName)
    }

    static func save(text: String, suggestedName: String) throws -> String {
        let fileName = "\(UUID().uuidString)-\(suggestedName).txt"
        try text.write(to: url(for: fileName), atomically: true, encoding: .utf8)
        return fileName
    }

    static func loadText(_ fileName: String) throws -> String {
        try String(contentsOf: url(for: fileName), encoding: .utf8)
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}

/// Добавление книг на полку и удаление с неё.
@MainActor
struct LibraryService {

    let context: ModelContext

    /// Разбирает файл и кладёт книгу на полку.
    /// Текст сохраняется уже разобранным: повторно парсить EPUB при каждом
    /// открытии незачем, а места плоский текст занимает меньше исходника.
    func addBook(from url: URL) throws -> Book {
        let parsed = try BookImporter.read(url)
        let fileName = try BookStorage.save(text: parsed.text,
                                            suggestedName: safeName(parsed.title))

        let book = Book(title: parsed.title,
                        author: parsed.author,
                        fileName: fileName,
                        format: parsed.format,
                        characterCount: parsed.text.count)
        book.coverImage = parsed.cover

        context.insert(book)
        try context.save()
        return book
    }

    func delete(_ book: Book) {
        BookStorage.delete(book.fileName)
        context.delete(book)
        try? context.save()
    }

    private func safeName(_ title: String) -> String {
        let allowed = title.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " "
        }
        return String(String.UnicodeScalarView(allowed))
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
            .prefix(40)
            .description
    }
}
