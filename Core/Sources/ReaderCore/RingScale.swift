import Foundation

/// Шкала кольца процентов.
///
/// Кольцо ходит от 0 до 100%, но не линейно: первые 60% занимают три четверти
/// оборота. Причина в том, что разница между 10% и 15% ощутима для читателя,
/// и её надо уметь поймать пальцем, а разница между 80% и 85% — уже нет.
/// За отметкой 60% начинается подстрочник, и там точность не нужна.
///
/// Живёт в `Core`, а не в интерфейсе, потому что на эти же константы опираются
/// тесты и подписи в карточке книги.
public enum RingScale {

    /// Граница между «чтением с опорой» и подстрочником.
    public static let breakPoint: Double = 60

    /// Какую долю оборота занимает участок до границы.
    public static let breakFraction: Double = 0.75

    /// Полная развёртка кольца в градусах. Оставшиеся 90° — разрыв внизу.
    public static let sweepDegrees: Double = 270

    /// Начало развёртки, в градусах: 135° — левый нижний край разрыва.
    public static let startDegrees: Double = 135

    /// Шаг тактильной отдачи при вращении.
    public static let hapticStep = 5

    /// Доля оборота [0, 1] для процента.
    public static func fraction(forPercent percent: Double) -> Double {
        let clamped = min(max(percent, 0), 100)
        if clamped <= breakPoint {
            return clamped / breakPoint * breakFraction
        }
        let past = (clamped - breakPoint) / (100 - breakPoint)
        return breakFraction + past * (1 - breakFraction)
    }

    /// Процент для доли оборота [0, 1]. Обратная к `fraction(forPercent:)`.
    public static func percent(forFraction fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        if clamped <= breakFraction {
            return clamped / breakFraction * breakPoint
        }
        let past = (clamped - breakFraction) / (1 - breakFraction)
        return breakPoint + past * (100 - breakPoint)
    }

    /// Угол в градусах для процента — для отрисовки бегунка.
    public static func degrees(forPercent percent: Double) -> Double {
        startDegrees + fraction(forPercent: percent) * sweepDegrees
    }

    /// Подпись в центре кольца.
    public static func zoneLabel(forPercent percent: Int) -> String {
        Double(percent) <= breakPoint ? "ЧТЕНИЕ С ОПОРОЙ" : "ПОДСТРОЧНИК"
    }

    /// Читатель ушёл в зону подстрочника — один раз стоит объяснить, что это значит.
    public static func isGlossZone(_ percent: Int) -> Bool {
        Double(percent) > breakPoint
    }
}
