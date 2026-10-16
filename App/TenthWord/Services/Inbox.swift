import Foundation
import SwiftData

/// Приём книг извне: «Поделиться → Открыть в…», двойной тап по файлу в Files,
/// тап по вложению в почте.
///
/// Здесь же лежит путь навигации полки. Это не ради удобства: книгу могут
/// прислать, когда полка закрыта другой открытой книгой, и тогда ни её `.task`,
/// ни её состояние не доступны. Приём обязан работать с любого экрана,
/// поэтому и очередь, и «какую книгу показать» живут выше — у всего приложения.
@MainActor
@Observable
final class Inbox {

    /// Ссылки, которые ещё не разобраны.
    private(set) var pending: [URL] = []

    /// Открытая книга. Список, а не одно значение: замена содержимого пути
    /// подменяет книгу на экране, присваивание в `item:` — нет.
    var path: [Book] = []

    /// Последняя ошибка разбора. Показывает полка.
    var failure: String?

    init() {
        sweep()
    }

    func receive(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !pending.contains(where: { $0.standardizedFileURL.path == path }) else { return }
        pending.append(url)
    }

    /// Разбирает всё накопленное и открывает последнюю книгу: человек выбрал
    /// «Открыть в Десятом слове», а не «положить на полку».
    func drain(into context: ModelContext) {
        guard !pending.isEmpty else { return }

        let urls = pending
        pending = []

        let service = LibraryService(context: context)
        var opened: Book?
        for url in urls {
            do { opened = try service.addBook(from: url) }
            catch let error { failure = error.localizedDescription }
        }
        if let opened { path = [opened] }
    }

    /// Папка, в которую система складывает файлы из «Открыть в…».
    static var directory: URL {
        URL.documentsDirectory.appending(path: "Inbox")
    }

    /// Книги, оставшиеся в `Documents/Inbox` с прошлых запусков.
    ///
    /// Система кладёт туда файл и уведомляет приложение ссылкой — но если
    /// уведомление пропало (а в версиях до 1.0.1 его никто не слушал),
    /// файл остаётся лежать молча. Подбираем такие при запуске: иначе книга,
    /// которую читатель уже «отправил» в приложение, не появится никогда.
    private func sweep() {
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []

        for url in leftovers { receive(url) }
    }
}
