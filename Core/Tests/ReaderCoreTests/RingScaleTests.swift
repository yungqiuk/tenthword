import XCTest
@testable import ReaderCore

final class RingScaleTests: XCTestCase {

    func testEndpoints() {
        XCTAssertEqual(RingScale.fraction(forPercent: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(RingScale.fraction(forPercent: 100), 1, accuracy: 1e-9)
    }

    /// Первые 60% занимают три четверти оборота — там нужна точная настройка.
    func testBreakPointSitsAtThreeQuarters() {
        XCTAssertEqual(RingScale.fraction(forPercent: 60), 0.75, accuracy: 1e-9)
    }

    func testRoundTrip() {
        for percent in stride(from: 0.0, through: 100.0, by: 0.5) {
            let back = RingScale.percent(forFraction: RingScale.fraction(forPercent: percent))
            XCTAssertEqual(back, percent, accuracy: 1e-6, "не сошлось на \(percent)%")
        }
    }

    func testMonotonic() {
        var previous = -1.0
        for percent in 0...100 {
            let fraction = RingScale.fraction(forPercent: Double(percent))
            XCTAssertGreaterThan(fraction, previous, "шкала не растёт на \(percent)%")
            previous = fraction
        }
    }

    func testClamping() {
        XCTAssertEqual(RingScale.fraction(forPercent: -50), 0, accuracy: 1e-9)
        XCTAssertEqual(RingScale.fraction(forPercent: 500), 1, accuracy: 1e-9)
        XCTAssertEqual(RingScale.percent(forFraction: -1), 0, accuracy: 1e-9)
        XCTAssertEqual(RingScale.percent(forFraction: 2), 100, accuracy: 1e-9)
    }

    /// Точность в рабочей зоне: половина градуса должна давать меньше процента.
    /// Именно ради этого шкала и сделана нелинейной.
    func testFineControlBelowBreakPoint() {
        let atTen = RingScale.degrees(forPercent: 10)
        let atFifteen = RingScale.degrees(forPercent: 15)
        XCTAssertGreaterThan(atFifteen - atTen, 15,
                             "5% в рабочей зоне должны занимать заметную дугу")
    }

    func testZoneLabels() {
        XCTAssertEqual(RingScale.zoneLabel(forPercent: 12), "ЧТЕНИЕ С ОПОРОЙ")
        XCTAssertEqual(RingScale.zoneLabel(forPercent: 60), "ЧТЕНИЕ С ОПОРОЙ")
        XCTAssertEqual(RingScale.zoneLabel(forPercent: 61), "ПОДСТРОЧНИК")
        XCTAssertFalse(RingScale.isGlossZone(60))
        XCTAssertTrue(RingScale.isGlossZone(61))
    }
}

final class ReadingUnitsTests: XCTestCase {

    /// Страница считается в знаках, а не в экранах: иначе крупный шрифт даёт
    /// втрое больше бесплатных страниц в день.
    func testPageCountIsAboutCharacters() {
        XCTAssertEqual(ReadingUnits.pageCount(forCharacters: 0), 0)
        XCTAssertEqual(ReadingUnits.pageCount(forCharacters: 1), 1)
        XCTAssertEqual(ReadingUnits.pageCount(forCharacters: 1800), 1)
        XCTAssertEqual(ReadingUnits.pageCount(forCharacters: 1801), 2)
        XCTAssertEqual(ReadingUnits.pageCount(forCharacters: 18_000), 10)
    }

    func testPageNumbersStartAtOne() {
        XCTAssertEqual(ReadingUnits.pageNumber(atCharacter: 0), 1)
        XCTAssertEqual(ReadingUnits.pageNumber(atCharacter: 1799), 1)
        XCTAssertEqual(ReadingUnits.pageNumber(atCharacter: 1800), 2)
    }

    func testTranslationSlowsReadingDown() {
        let plain = ReadingUnits.minutesToRead(words: 10_000, translationPercent: 0)
        let mixed = ReadingUnits.minutesToRead(words: 10_000, translationPercent: 50)
        XCTAssertGreaterThan(mixed, plain)
    }
}
