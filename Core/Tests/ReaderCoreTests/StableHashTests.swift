import XCTest
@testable import ReaderCore

final class StableHashTests: XCTestCase {

    /// Канонические значения FNV-1a 64. Если они разошлись, разошёлся и весь отбор:
    /// у читателя при каждом открытии книги будут переведены разные слова.
    func testKnownVectors() {
        XCTAssertEqual(StableHash.fnv1a64(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(StableHash.fnv1a64("a"), 0xaf63_dc4c_8601_ec8c)
        XCTAssertEqual(StableHash.fnv1a64("foobar"), 0x85944171f73967e8)
    }

    func testUnitIntervalStaysInRange() {
        for i in 0..<5_000 {
            let value = StableHash.unitInterval("кровать#\(i)")
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }

    func testDistributionIsRoughlyUniform() {
        // Если хеш перекошен, переведённые слова соберутся в одном месте страницы.
        var buckets = [Int](repeating: 0, count: 10)
        let count = 10_000
        for i in 0..<count {
            let bucket = Int(StableHash.unitInterval("слово#\(i)") * 10)
            buckets[min(bucket, 9)] += 1
        }
        for (index, hits) in buckets.enumerated() {
            XCTAssertGreaterThan(hits, count / 20,
                                 "корзина \(index) почти пустая: \(hits)")
        }
    }

    func testStableAcrossCalls() {
        XCTAssertEqual(StableHash.unitInterval("кровать#7"),
                       StableHash.unitInterval("кровать#7"))
    }
}
