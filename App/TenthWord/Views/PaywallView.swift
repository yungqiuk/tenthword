import SwiftUI
import ReaderCore

/// Пейволл. Показывается по окончании триала и по кнопке в настройках.
///
/// Правило из `docs/TRIAL.md`: **никаких обвинений**. Если защита сработала
/// на переводе часов, пользователь видит ровно этот экран и ничего больше.
/// Часы могли перевестись честно, а обвинённый честный пользователь ставит
/// одну звезду.
struct PaywallView: View {

    @Environment(Theme.self) private var theme
    @Environment(PurchaseStore.self) private var store
    @Environment(TrialGuard.self) private var trial
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 11) {
                benefit("Сколько угодно страниц в день")
                benefit("Перевод от 1% до 100%")
                benefit("Все языковые пакеты, включая будущие")
                benefit("Синхронизация полки через iCloud")
            }

            freeTierNote

            Spacer()

            if let error = store.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            buyButton

            HStack {
                Button("Восстановить покупки") {
                    Task { await store.restore(); sync() }
                }
                Spacer()
                Button("Не сейчас") { dismiss() }
            }
            .font(.footnote)
            .foregroundStyle(theme.text.opacity(0.55))

            Text("Разовая покупка, не подписка. Ничего не спишется повторно.")
                .font(.caption2)
                .foregroundStyle(theme.text.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.background)
        .task { await store.load(); sync() }
    }

    // MARK: -

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(theme.text.opacity(0.5))

            (Text("Дальше — ")
             + Text("без ограничений").foregroundColor(theme.accent).italic()
             + Text(", один раз и навсегда"))
                .font(.system(size: 27, weight: .regular, design: .serif))
                .foregroundStyle(theme.text)
        }
        .padding(.top, 18)
    }

    private var eyebrow: String {
        switch trial.state {
        case .trial: return "ПРОБНЫЙ ПЕРИОД ИДЁТ"
        case .free: return "ТРИ ДНЯ ЗАКОНЧИЛИСЬ"
        case .premium: return "ДОСТУП ОТКРЫТ"
        }
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Text("∞")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 14)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(theme.text.opacity(0.75))
        }
    }

    /// Бесплатный режим показывается честно и до покупки. Это и правило App Store,
    /// и просто разумно: человек должен понимать, что теряет, если не купит.
    private var freeTierNote: some View {
        HStack {
            Text("Без покупки")
                .foregroundStyle(theme.text.opacity(0.55))
            Spacer()
            Text("\(ReadingUnits.freeDailyPages) страниц в день,\nбез рекламы")
                .multilineTextAlignment(.trailing)
                .foregroundStyle(theme.text)
        }
        .font(.footnote)
        .padding(13)
        .overlay(RoundedRectangle(cornerRadius: 13)
            .strokeBorder(theme.text.opacity(0.15)))
    }

    private var buyButton: some View {
        Button {
            Task { await store.purchase(); sync() }
        } label: {
            Group {
                if store.isWorking {
                    ProgressView().tint(theme.background)
                } else {
                    Text("Купить за \(store.displayPrice)")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
        }
        .background(theme.accent, in: RoundedRectangle(cornerRadius: 13))
        .foregroundStyle(theme.background)
        .disabled(store.isWorking)
    }

    private func sync() {
        trial.setPurchased(store.isPurchased)
        if store.isPurchased { dismiss() }
    }
}
