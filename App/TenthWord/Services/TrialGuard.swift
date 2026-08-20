import Foundation
import ReaderCore

/// Состояние доступа: триал, бесплатный режим или премиум.
enum AccessState: Equatable {
    case trial(daysLeft: Int, hoursLeft: Int)
    case free(pagesLeftToday: Int)
    case premium

    var isUnlimited: Bool {
        switch self {
        case .trial, .premium: return true
        case .free: return false
        }
    }
}

/// Триал и бесплатный лимит.
///
/// Три слоя защиты и их обоснование — в `docs/TRIAL.md`. Здесь реализованы
/// первые два; третий (CloudKit) подключается снаружи через `applyCloudStart(_:)`.
///
/// Правило поведения: **никаких обвинений**. При срабатывании защиты просто
/// показывается пейволл. Часы могли перевестись честно — при перелёте, при сбросе
/// настроек, — а обвинённый честный пользователь ставит одну звезду.
@Observable
final class TrialGuard {

    static let trialDays = 3
    static let trialReadingHours = 6.0

    private enum Keys {
        static let started = "trial.startedAt"
        static let highWater = "trial.highWaterMark"
        static let secondsUsed = "trial.secondsUsed"
    }

    /// Допуск для метки максимума. Сутки — потому что перелёт через часовые пояса
    /// и сброс настроек дают расхождение честно.
    private static let clockTolerance: TimeInterval = 24 * 3600

    private(set) var isPurchased = false
    private(set) var state: AccessState = .free(pagesLeftToday: ReadingUnits.freeDailyPages)

    /// Момент начала текущей сессии чтения по монотонным часам.
    /// `systemUptime` не зависит от системного времени — его отмоткой не подделать.
    private var sessionStartedUptime: TimeInterval?

    private let budget = PageBudget()

    init() {
        if KeychainStore.date(for: Keys.started) == nil {
            KeychainStore.set(Date(), for: Keys.started)
        }
        refresh()
    }

    // MARK: - Внешние события

    func setPurchased(_ purchased: Bool) {
        isPurchased = purchased
        refresh()
    }

    /// Метка из CloudKit. Если облако помнит более раннее начало — верим облаку:
    /// значит, триал уже был на другом устройстве.
    func applyCloudStart(_ cloudDate: Date) {
        let local = KeychainStore.date(for: Keys.started) ?? .distantFuture
        if cloudDate < local {
            KeychainStore.set(cloudDate, for: Keys.started)
        }
        refresh()
    }

    var trialStartedAt: Date? { KeychainStore.date(for: Keys.started) }

    // MARK: - Учёт времени

    func beginReadingSession() {
        sessionStartedUptime = ProcessInfo.processInfo.systemUptime
    }

    /// Копит секунды чтения. Вызывается при уходе с экрана чтения и при сворачивании.
    func endReadingSession() {
        guard let start = sessionStartedUptime else { return }
        sessionStartedUptime = nil

        let elapsed = ProcessInfo.processInfo.systemUptime - start
        // Отрицательная разница означает перезагрузку устройства посреди сессии —
        // такую сессию просто не засчитываем.
        guard elapsed > 0, elapsed < 12 * 3600 else { return }

        let total = (KeychainStore.double(for: Keys.secondsUsed) ?? 0) + elapsed
        KeychainStore.set(total, for: Keys.secondsUsed)
        refresh()
    }

    var secondsRead: Double { KeychainStore.double(for: Keys.secondsUsed) ?? 0 }

    /// Читатель открыл страницу. Возвращает `false`, если бесплатный лимит исчерпан.
    @discardableResult
    func registerPageTurn() -> Bool {
        if state.isUnlimited { return true }
        let allowed = budget.consumePage()
        refresh()
        return allowed
    }

    // MARK: - Пересчёт состояния

    func refresh() {
        if isPurchased {
            state = .premium
            return
        }
        if let remaining = trialRemaining() {
            state = .trial(daysLeft: remaining.days, hoursLeft: remaining.hours)
        } else {
            state = .free(pagesLeftToday: budget.pagesLeftToday())
        }
    }

    /// `nil` — триал закончился.
    private func trialRemaining() -> (days: Int, hours: Int)? {
        guard let started = KeychainStore.date(for: Keys.started) else { return nil }
        let now = Date()

        // Слой 2а: метка максимума. Часы отмотали назад — триал считаем истёкшим.
        let highWater = KeychainStore.date(for: Keys.highWater) ?? now
        if now < highWater.addingTimeInterval(-Self.clockTolerance) { return nil }
        if now > highWater { KeychainStore.set(now, for: Keys.highWater) }

        // Слой 2б: бюджет секунд. Часы этому не мешают.
        if secondsRead >= Self.trialReadingHours * 3600 { return nil }

        let deadline = started.addingTimeInterval(Double(Self.trialDays) * 24 * 3600)
        guard now < deadline else { return nil }

        let left = deadline.timeIntervalSince(now)
        return (days: Int(left / 86400), hours: Int(left.truncatingRemainder(dividingBy: 86400) / 3600))
    }
}

/// Бесплатный лимит: 10 страниц в сутки, сброс в полночь по времени устройства.
///
/// Живёт в `UserDefaults`, а не в Keychain: обход даёт всего один лишний день
/// чтения, и городить ради этого защиту не стоит.
private final class PageBudget {

    private let countKey = "free.pagesToday"
    private let dayKey = "free.day"

    func pagesLeftToday() -> Int {
        rolloverIfNeeded()
        let used = UserDefaults.standard.integer(forKey: countKey)
        return max(0, ReadingUnits.freeDailyPages - used)
    }

    /// `false` — лимит исчерпан, страницу открывать нельзя.
    func consumePage() -> Bool {
        rolloverIfNeeded()
        let used = UserDefaults.standard.integer(forKey: countKey)
        guard used < ReadingUnits.freeDailyPages else { return false }
        UserDefaults.standard.set(used + 1, forKey: countKey)
        return true
    }

    private func rolloverIfNeeded() {
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        if UserDefaults.standard.double(forKey: dayKey) != today {
            UserDefaults.standard.set(today, forKey: dayKey)
            UserDefaults.standard.set(0, forKey: countKey)
        }
    }
}
