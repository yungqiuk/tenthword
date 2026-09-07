import XCTest
import Foundation
import NaturalLanguage
@testable import ReaderCore

/// Временный замер: на что уходит время разбора книги.
/// Запуск: TENTHWORD_BOOK=/путь/к/книге.txt swift test -c release --filter PerformanceProbe
final class PerformanceProbe: XCTestCase {

    func testWhereTimeGoes() throws {
        guard let path = ProcessInfo.processInfo.environment["TENTHWORD_BOOK"],
              let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw XCTSkip("нет TENTHWORD_BOOK")
        }
        guard let dictionaryPath = ProcessInfo.processInfo.environment["TENTHWORD_DICT"],
              let dictionary = try? SQLiteDictionary(path: dictionaryPath) else {
            throw XCTSkip("нет TENTHWORD_DICT")
        }

        func measure(_ name: String, _ body: () -> Void) {
            let started = Date()
            body()
            print("⏱ \(name): \(Int(Date().timeIntervalSince(started) * 1000)) мс")
        }

        var tokens: [WordToken] = []
        measure("токенизация") { tokens = Tokenizer.tokenize(text) }
        print("   слов: \(tokens.count)")

        let lemmatizer = AppleLemmatizer(language: .russian) { dictionary.lemmaOverride(for: $0) }
        var lemmas: [String] = []
        measure("лемматизация") { lemmas = lemmatizer.lemmas(for: tokens, in: text) }

        measure("словарь, как сейчас") {
            var found = 0
            for lemma in lemmas where dictionary.entry(for: lemma) != nil { found += 1 }
            print("   найдено: \(found)")
        }

        measure("словарь с памяткой") {
            var cache: [String: Bool] = [:]
            cache.reserveCapacity(20_000)
            var found = 0
            for lemma in lemmas {
                if let known = cache[lemma] {
                    if known { found += 1 }
                } else {
                    let known = dictionary.entry(for: lemma) != nil
                    cache[lemma] = known
                    if known { found += 1 }
                }
            }
            print("   найдено: \(found), уникальных лемм: \(cache.count)")
        }
    }
}
