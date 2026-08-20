#if canImport(SQLite3)
import Foundation
import SQLite3

/// Словарь поверх SQLite-файла из бандла приложения.
///
/// Файл собирается скриптом `tools/build_dictionary.py` из открытых данных Викисловаря.
/// Схема описана в `docs/DATA.md`.
///
/// **Не потокобезопасен.** Один экземпляр — один поток. В приложении живёт
/// в акторе, который владеет разбором главы.
public final class SQLiteDictionary: WordDictionary {

    private var handle: OpaquePointer?
    private var entryStatement: OpaquePointer?
    private var rankStatement: OpaquePointer?
    private var overrideStatement: OpaquePointer?

    /// Разбор одной главы трогает одни и те же леммы десятки раз — кеш снимает
    /// с SQLite почти всю нагрузку.
    private var cache: [String: DictionaryEntry?] = [:]
    private var overrideCache: [String: String?] = [:]

    public enum Failure: Error, CustomStringConvertible {
        case cannotOpen(String)
        case cannotPrepare(String)

        public var description: String {
            switch self {
            case .cannotOpen(let path): return "Не удалось открыть словарь: \(path)"
            case .cannotPrepare(let message): return "Не удалось подготовить запрос: \(message)"
            }
        }
    }

    public init(path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? path
            sqlite3_close(handle)
            throw Failure.cannotOpen(message)
        }

        tune()

        entryStatement = try prepare("""
            SELECT lemma, english, gloss, pos, ambiguous, note
            FROM entries WHERE lemma = ? LIMIT 1
            """)
        rankStatement = try prepare("SELECT rank FROM frequency WHERE lemma = ? LIMIT 1")
        overrideStatement = try prepare(
            "SELECT lemma FROM lemma_overrides WHERE form = ? LIMIT 1")
    }

    /// Словарь в бандле только читается и никогда не меняется, поэтому его
    /// можно отобразить в память целиком: страницы подтягиваются по мере
    /// обращения, а не копируются на старте.
    private func tune() {
        for pragma in ["PRAGMA mmap_size = 268435456",   // 256 МБ
                       "PRAGMA cache_size = -8000",      // 8 МБ страниц
                       "PRAGMA temp_store = MEMORY"] {
            sqlite3_exec(handle, pragma, nil, nil, nil)
        }
    }

    deinit {
        sqlite3_finalize(entryStatement)
        sqlite3_finalize(rankStatement)
        sqlite3_finalize(overrideStatement)
        sqlite3_close(handle)
    }

    // MARK: - WordDictionary

    public func entry(for lemma: String) -> DictionaryEntry? {
        if let cached = cache[lemma] { return cached }

        let result = fetchEntry(lemma)
        cache[lemma] = result
        return result
    }

    /// Исключение лемматизации. Запрос идёт по первичному ключу таблицы,
    /// то есть по индексу: полмиллиона строк ищутся за микросекунды и в памяти
    /// оседают только те формы, что встретились в тексте.
    public func lemmaOverride(for form: String) -> String? {
        if let cached = overrideCache[form] { return cached }

        var result: String?
        if let statement = overrideStatement {
            defer { sqlite3_reset(statement) }
            bind(form, to: statement, at: 1)
            if sqlite3_step(statement) == SQLITE_ROW {
                result = text(statement, 0)
            }
        }
        overrideCache[form] = result
        return result
    }

    public func frequencyRank(for lemma: String) -> Int? {
        guard let statement = rankStatement else { return nil }
        defer { sqlite3_reset(statement) }
        bind(lemma, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int(statement, 0))
    }

    // MARK: - Внутреннее

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? sql
            throw Failure.cannotPrepare(message)
        }
        return statement
    }

    private func fetchEntry(_ lemma: String) -> DictionaryEntry? {
        guard let statement = entryStatement else { return nil }
        defer { sqlite3_reset(statement) }
        bind(lemma, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        return DictionaryEntry(
            lemma: text(statement, 0) ?? lemma,
            english: text(statement, 1) ?? "",
            gloss: text(statement, 2) ?? "",
            pos: PartOfSpeech(rawValue: text(statement, 3) ?? "other") ?? .other,
            isAmbiguous: sqlite3_column_int(statement, 4) != 0,
            note: text(statement, 5)
        )
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        // SQLITE_TRANSIENT: SQLite обязан скопировать строку, иначе она умрёт раньше запроса.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }
}
#endif
