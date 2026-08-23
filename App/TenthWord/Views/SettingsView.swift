import SwiftUI
import ReaderCore

/// Оформление и состояние подписки.
struct SettingsView: View {

    @Environment(Theme.self) private var theme
    @Environment(TrialGuard.self) private var trial
    @Environment(PurchaseStore.self) private var store

    @State private var showsPaywall = false

    var body: some View {
        @Bindable var theme = theme

        NavigationStack {
            List {
                accessSection

                Section("Тема") {
                    themeRow
                    colorSlider(title: "Фон", value: $theme.backgroundHex,
                                gradient: [0xFFFFFF, 0xF3EBD8, 0xC9B48C, 0x3A5673, 0x0C1A2B])
                    colorSlider(title: "Текст", value: $theme.textHex,
                                gradient: [0x000000, 0x2A2118, 0x6B7280, 0xC9C4BA, 0xFFFFFF])
                    contrastWarning
                }

                Section("Перевод") {
                    accentRow
                    Picker("Как выделять", selection: $theme.marker) {
                        ForEach(Theme.Marker.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Шрифт") {
                    Picker("Гарнитура", selection: $theme.fontID) {
                        ForEach(Theme.FontChoice.all) { Text($0.name).tag($0.id) }
                    }
                    stepper("Размер", value: $theme.fontSize, range: 12...30, step: 1, unit: "pt")
                    stepper("Межстрочный", value: $theme.lineSpacing, range: 0...20, step: 1, unit: "pt")
                    sample
                }

                Section {
                    NavigationLink("О программе") { AboutView() }
                }
            }
            .navigationTitle("Настройки")
            .sheet(isPresented: $showsPaywall) { PaywallView() }
        }
    }

    // MARK: - Доступ

    @ViewBuilder
    private var accessSection: some View {
        Section {
            switch trial.state {
            case .premium:
                Label("Полный доступ", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(theme.accent)
            case .trial(let days, let hours):
                VStack(alignment: .leading, spacing: 3) {
                    Text("Пробный период")
                    Text(days > 0 ? "осталось \(days) дн. \(hours) ч." : "осталось \(hours) ч.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(store.displayPrice.map { "Купить за \($0)" } ?? "Купить полный доступ") {
                    showsPaywall = true
                }
            case .free(let pagesLeft):
                VStack(alignment: .leading, spacing: 3) {
                    Text("Бесплатный режим")
                    Text("сегодня осталось \(pagesLeft) из \(ReadingUnits.freeDailyPages) страниц")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(store.displayPrice.map { "Снять ограничение за \($0)" } ?? "Снять ограничение") {
                    showsPaywall = true
                }
            }
        }
    }

    // MARK: - Оформление

    private var themeRow: some View {
        HStack(spacing: 10) {
            ForEach(Theme.Preset.all) { preset in
                Circle()
                    .fill(preset.background)
                    .overlay(Circle().strokeBorder(preset.text.opacity(0.35), lineWidth: 1))
                    .overlay {
                        if theme.presetID == preset.id {
                            Circle().strokeBorder(preset.accent, lineWidth: 2.5).padding(-3)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .onTapGesture { theme.apply(preset) }
                    .accessibilityLabel(preset.name)
            }
        }
        .padding(.vertical, 4)
    }

    private var accentRow: some View {
        HStack(spacing: 10) {
            ForEach([0xF2A93B, 0x4FC3B0, 0xEE7A99, 0x9FB6D4, 0xB4720C], id: \.self) { hex in
                Circle()
                    .fill(Color(hex: UInt32(hex)))
                    .overlay {
                        if theme.accentHex == UInt32(hex) {
                            Circle().strokeBorder(theme.text, lineWidth: 2).padding(-3)
                        }
                    }
                    .frame(width: 26, height: 26)
                    .onTapGesture { theme.accentHex = UInt32(hex) }
            }
        }
        .padding(.vertical, 4)
    }

    /// Ползунок цвета: переход по заданной шкале, значение — позиция на ней.
    private func colorSlider(title: String, value: Binding<UInt32>,
                             gradient: [UInt32]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "#%06X", value.wrappedValue))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { position(of: value.wrappedValue, in: gradient) },
                set: { value.wrappedValue = colour(at: $0, in: gradient) }
            ), in: 0...1)
            .tint(Color(hex: value.wrappedValue))
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var contrastWarning: some View {
        if !theme.isReadable {
            Label {
                Text("Контраст \(String(format: "%.1f", theme.contrastRatio)) : 1 — текст будет плохо виден. "
                     + "Нужно хотя бы \(String(format: "%.1f", Theme.minimumContrast)) : 1.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    private func stepper(_ title: String, value: Binding<Double>,
                         range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var sample: some View {
        Text("Сегодня ")
        + Text("morning").foregroundColor(theme.accent).italic()
        + Text(" я встал с ")
        + Text("bed").foregroundColor(theme.accent).italic()
        + Text(", чтобы пойти в сад.")
    }

    // MARK: - Работа со шкалой цвета

    private func colour(at position: Double, in stops: [UInt32]) -> UInt32 {
        guard stops.count > 1 else { return stops.first ?? 0 }
        let scaled = min(max(position, 0), 1) * Double(stops.count - 1)
        let index = min(Int(scaled), stops.count - 2)
        let t = scaled - Double(index)

        func channel(_ shift: UInt32) -> UInt32 {
            let from = Double((stops[index] >> shift) & 0xFF)
            let to = Double((stops[index + 1] >> shift) & 0xFF)
            return UInt32(from + (to - from) * t)
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }

    /// Обратная задача решается перебором: шкала короткая, а точности хватает
    /// на то, чтобы бегунок встал туда, где пользователь его оставил.
    private func position(of colour: UInt32, in stops: [UInt32]) -> Double {
        var best = 0.0
        var bestDistance = Double.greatestFiniteMagnitude
        for step in 0...200 {
            let position = Double(step) / 200
            let candidate = self.colour(at: position, in: stops)
            let distance = abs(Double(Int(candidate) - Int(colour)))
            if distance < bestDistance {
                bestDistance = distance
                best = position
            }
        }
        return best
    }
}

/// Ссылки на страницы сайта.
///
/// Страницы лежат в папке `docs/` репозитория и публикуются через GitHub Pages.
/// Те же ссылки указываются в App Store Connect в полях
/// Privacy Policy URL и Support URL — они обязаны открываться,
/// иначе сборку завернут на ревью.
enum AppLinks {
    static let site = "https://yungqiuk.github.io/tenthword/"
    static let privacy = site + "privacy.html"
    static let support = site + "support.html"
    static let terms = site + "terms.html"
}

/// Атрибуция обязательна: словарь под CC BY-SA. Подробности в `docs/DATA.md`.
struct AboutView: View {

    @Environment(PurchaseStore.self) private var store

    private var version: String {
        let bundle = Bundle.main
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section("Словарь") {
                Text("Построен на данных Викисловаря (ru.wiktionary.org) и распространяется "
                     + "на условиях CC BY-SA 4.0. Частотный список — проект FrequencyWords, "
                     + "лицензия MIT. Производный словарь доступен по той же лицензии "
                     + "CC BY-SA 4.0 — напишите в поддержку, и мы его пришлём.")
                .font(.footnote)
            }
            Section("Как это работает") {
                Text("Приложение подменяет часть слов английскими и ничего не отправляет "
                     + "в сеть: словарь лежит в самом приложении. Сеть нужна только "
                     + "для покупки и её восстановления.")
                .font(.footnote)
            }
            Section("Покупка") {
                Button("Восстановить покупку") {
                    Task { await store.restore() }
                }
            }
            Section("Документы") {
                Link("Политика конфиденциальности", destination: URL(string: AppLinks.privacy)!)
                Link("Условия использования", destination: URL(string: AppLinks.terms)!)
                Link("Поддержка", destination: URL(string: AppLinks.support)!)
            }
            Section {
                LabeledContent("Версия", value: version)
                    .font(.footnote)
            }
        }
        .navigationTitle("О программе")
        .navigationBarTitleDisplayMode(.inline)
    }
}
