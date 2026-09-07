import SwiftUI

/// Ряд готовых тем. Используется и на вкладке «Настройки», и в шторке
/// оформления из читалки, поэтому живёт отдельно от обоих.
struct ThemePresetRow: View {

    @Environment(Theme.self) private var theme

    var body: some View {
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
}

/// Числовая настройка со шагом: «Размер — 18 pt».
struct ValueStepper: View {

    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) \(unit)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// Шторка оформления, которая открывается прямо из читалки.
///
/// Здесь только то, что крутят по ходу чтения: тема, шрифт, размер,
/// межстрочный интервал и способ выделения. Точная подстройка цветов
/// осталась на вкладке «Настройки» — вечером под лампой нужен размер
/// шрифта, а не ползунок оттенка фона.
struct ReadingAppearanceSheet: View {

    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var theme = theme

        NavigationStack {
            List {
                Section("Тема") {
                    ThemePresetRow()
                }

                Section("Шрифт") {
                    Picker("Гарнитура", selection: $theme.fontID) {
                        ForEach(Theme.FontChoice.all) { Text($0.name).tag($0.id) }
                    }
                    ValueStepper(title: "Размер", value: $theme.fontSize,
                                 range: 12...30, step: 1, unit: "pt")
                    ValueStepper(title: "Межстрочный", value: $theme.lineSpacing,
                                 range: 0...20, step: 1, unit: "pt")
                    Picker("Выключка", selection: $theme.textAlign) {
                        ForEach(Theme.TextAlign.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Перевод") {
                    Picker("Как выделять", selection: $theme.marker) {
                        ForEach(Theme.Marker.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Перелистывание") {
                    Picker("Направление", selection: $theme.pageTurn) {
                        ForEach(Theme.PageTurn.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            .navigationTitle("Оформление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
