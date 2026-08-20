import SwiftUI
import SwiftData

@main
struct TenthWordApp: App {

    @State private var theme = Theme()
    @State private var trial = TrialGuard()
    @State private var store = PurchaseStore()
    @State private var dictionaries = DictionaryProvider()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(theme)
                .environment(trial)
                .environment(store)
                .environment(dictionaries)
                .preferredColorScheme(theme.contrastRatio > 0 && isDarkBackground ? .dark : .light)
                .task {
                    await store.load()
                    trial.setPurchased(store.isPurchased)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Секунды чтения копятся, пока приложение на экране.
                    // Ушли в фон — засчитали сессию, см. docs/TRIAL.md.
                    if phase == .active { trial.beginReadingSession() }
                    else { trial.endReadingSession() }
                }
        }
        .modelContainer(for: [Book.self, VocabularyRecord.self])
    }

    /// Системные элементы (клавиатура, меню) подстраиваем под выбранный фон.
    private var isDarkBackground: Bool {
        Color.contrastRatio(theme.backgroundHex, 0xFFFFFF) > 2.5
    }
}

struct RootView: View {

    @Environment(Theme.self) private var theme
    @Environment(DictionaryProvider.self) private var dictionaries

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Полка", systemImage: "books.vertical") }
            VocabularyView()
                .tabItem { Label("Словарь", systemImage: "character.book.closed") }
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "slider.horizontal.3") }
        }
        .tint(theme.accent)
        .overlay(alignment: .top) { dictionaryWarning }
    }

    /// Без словаря приложение работает как обычная читалка. Это лучше, чем падать
    /// при запуске, но сказать об этом надо — иначе выглядит как поломка перевода.
    @ViewBuilder
    private var dictionaryWarning: some View {
        if let error = dictionaries.loadError {
            Text(error)
                .font(.caption)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(.orange.opacity(0.9))
                .foregroundStyle(.black)
        }
    }
}
