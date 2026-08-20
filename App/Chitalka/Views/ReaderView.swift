import SwiftUI
import SwiftData
import ReaderCore

/// Экран чтения.
///
/// Страницы считает TextKit 2 под настоящий размер экрана: страница кончается
/// там, где очередная строка не поместилась по высоте. Отсюда два следствия.
/// Позиция читателя хранится смещением в исходном тексте, а не номером
/// страницы: сменил шрифт — номера поехали, а место в книге осталось тем же.
/// И вёрстка пересчитывается при смене оформления, процента перевода
/// и размера окна — в фоне, потому что на романе это сотни миллисекунд.
struct ReaderView: View {

    @Bindable var book: Book

    @Environment(\.modelContext) private var context
    @Environment(Theme.self) private var theme
    @Environment(TrialGuard.self) private var trial
    @Environment(DictionaryProvider.self) private var dictionaries
    @Environment(\.dismiss) private var dismiss

    @Query private var vocabulary: [VocabularyRecord]

    @State private var prepared: PreparedText?
    @State private var plan: TranslationPlan?

    /// Текст книги держим в состоянии: читать файл с диска на каждую
    /// перерисовку — верный способ получить рывки на каждом кадре.
    @State private var source = ""

    /// Книга с подстановками и её разбивка на страницы.
    @State private var rendered: RenderedBook?
    @State private var pageStarts: [Int] = []
    @State private var pageIndex = 0

    /// Размер, под который посчитана вёрстка. Изменился — пересчитываем.
    @State private var layoutSize: CGSize = .zero
    @State private var isLoading = true
    @State private var isPaginating = false
    @State private var tapped: Candidate?
    @State private var showsRing = false
    @State private var showsPaywall = false
    @State private var glossZoneWarningShown = false

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.background.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(theme.accent)
            } else {
                page
            }

            if showsRing { ringPanel }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbar }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    turnPage(forward: value.translation.width < 0)
                }
        )
        .task { await load() }
        .onAppear { trial.beginReadingSession() }
        .onDisappear { trial.endReadingSession(); save() }
        .onChange(of: style) { Task { await rebuildLayout() } }
        .sheet(item: $tapped) { candidate in
            WordCard(candidate: candidate, theme: theme) { action in
                handle(action, for: candidate)
            }
            .presentationDetents([.height(240)])
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
        .alert("Дальше — подстрочник", isPresented: $glossZoneWarningShown) {
            Button("Понятно") {}
        } message: {
            Text("Выше 60% переводятся и служебные слова. Текст станет английским "
                 + "с русской грамматикой: «Today morning I got up from bed». "
                 + "Читать можно, догадываться из контекста — уже почти не из чего.")
        }
    }

    // MARK: - Текст

    private var page: some View {
        GeometryReader { geometry in
            let size = CGSize(width: geometry.size.width - 44,
                              height: geometry.size.height - 36)
            PageView(attributed: pageAttributed) { ordinal in
                tapped = plan?.candidate(atOrdinal: ordinal)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .task(id: size) {
                // Поворот экрана или первый показ: страницы считаются
                // под конкретную ширину и высоту.
                guard size.width > 1, size.height > 1, size != layoutSize else { return }
                layoutSize = size
                await rebuildLayout()
            }
        }
    }

    /// Текст текущей страницы. Вырезается из готовой книги — сборка целиком
    /// делается один раз на изменение процента, а не на каждый перелистыв.
    private var pageAttributed: NSAttributedString {
        guard let rendered, pageStarts.indices.contains(pageIndex) else {
            return NSAttributedString()
        }
        let range = BookLayout.range(ofPage: pageIndex,
                                     starts: pageStarts,
                                     length: rendered.attributed.length)
        return rendered.attributed.attributedSubstring(from: range)
    }

    /// Оформление, от которого зависит вёрстка. Меняется — страницы пересчитываются.
    private var style: ReadingStyle {
        ReadingStyle(font: theme.readingUIFont,
                     textColor: UIColor(theme.text),
                     accentColor: UIColor(theme.accent),
                     lineSpacing: theme.lineSpacing,
                     marker: theme.marker)
    }

    // MARK: - Перелистывание

    private func turnPage(forward: Bool) {
        let next = pageIndex + (forward ? 1 : -1)
        guard pageStarts.indices.contains(next) else { return }

        // Бесплатный лимит считается перелистываниями, а не временем на экране.
        if forward, !trial.registerPageTurn() {
            showsPaywall = true
            return
        }

        pageIndex = next
        rememberPosition()
    }

    /// Позиция читателя — смещение в исходном тексте книги.
    private func rememberPosition() {
        guard let rendered, pageStarts.indices.contains(pageIndex) else { return }
        book.readingOffset = rendered.sourceOffset(forRendered: pageStarts[pageIndex])
        save()
    }

    // MARK: - Кольцо

    private var ringPanel: some View {
        VStack(spacing: 12) {
            PercentRing(percent: Binding(
                get: { book.translationPercent },
                set: { newValue in
                    if RingScale.isGlossZone(newValue),
                       !RingScale.isGlossZone(book.translationPercent),
                       !UserDefaults.standard.bool(forKey: "warned.glossZone") {
                        UserDefaults.standard.set(true, forKey: "warned.glossZone")
                        glossZoneWarningShown = true
                    }
                    book.translationPercent = newValue
                    rebuildPlan()
                }
            ), diameter: 170, accent: theme.accent,
               track: theme.text.opacity(0.15), label: theme.text)

            if let plan {
                Text(footnote(for: plan))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.text.opacity(0.55))
            }

            Button("Готово") { withAnimation { showsRing = false } }
                .font(.subheadline)
                .foregroundStyle(theme.accent)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
        .transition(.move(edge: .bottom))
    }

    /// На высоких процентах фактическая доля меньше запрошенной: часть слов
    /// просто нет в словаре. Врать круглой цифрой нельзя.
    private func footnote(for plan: TranslationPlan) -> String {
        if plan.actualPercent < plan.percent {
            return "\(plan.actualPercent)% фактически · \(plan.untranslatableCount) слов нет в словаре"
        }
        return "\(plan.translatedCount) из \(plan.totalWords) слов"
    }

    // MARK: - Панель инструментов

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("\(pageIndex + 1) / \(max(pageStarts.count, 1))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.text.opacity(0.6))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation { showsRing.toggle() }
            } label: {
                Image(systemName: "circle.dashed.inset.filled")
            }
            .accessibilityLabel("Доля перевода")
        }
    }

    // MARK: - Загрузка и пересчёт

    private func load() async {
        defer { isLoading = false }

        if case .free(let pagesLeft) = trial.state, pagesLeft <= 0 {
            showsPaywall = true      // бесплатные страницы на сегодня кончились
            return
        }
        await buildPrepared()
    }

    private func buildPrepared() async {
        guard let engine = dictionaries.makeEngine(learnedLemmas: learnedLemmas),
              let text = try? BookStorage.loadText(book.fileName) else { return }

        // Разбор книги — почти секунда на романе.
        // На главном потоке ему делать нечего.
        let result = await Task.detached(priority: .userInitiated) {
            engine.prepare(text)
        }.value

        source = text
        prepared = result
        plan = result.plan(percent: book.translationPercent)
        await rebuildLayout()
    }

    private func rebuildPlan() {
        plan = prepared?.plan(percent: book.translationPercent)
        Task { await rebuildLayout() }
    }

    /// Пересобирает книгу с подстановками и заново считает страницы.
    ///
    /// Вызывается при открытии, смене процента, смене оформления и повороте
    /// экрана. Вся работа — в отдельной задаче: TextKit верстает роман
    /// за сотни миллисекунд, и держать на это главный поток нельзя.
    private func rebuildLayout() async {
        guard let prepared, let plan, !source.isEmpty,
              layoutSize.width > 1, layoutSize.height > 1 else { return }

        isPaginating = true
        defer { isPaginating = false }

        let text = source
        let size = layoutSize
        let currentStyle = style
        let offset = book.readingOffset

        let (renderedBook, starts, index) = await Task.detached(priority: .userInitiated) {
            let rendered = BookLayout.render(source: text,
                                             prepared: prepared,
                                             plan: plan,
                                             style: currentStyle)
            let starts = BookLayout.pageStarts(for: rendered.attributed, size: size)
            // Возвращаем читателя на то же место книги, а не на тот же номер страницы.
            let target = rendered.renderedOffset(forSource: offset)
            let index = starts.lastIndex { $0 <= target } ?? 0
            return (rendered, starts, index)
        }.value

        rendered = renderedBook
        pageStarts = starts
        pageIndex = index
    }

    private var learnedLemmas: Set<String> {
        Set(vocabulary.filter(\.isLearned).map(\.lemma))
    }

    private func save() {
        try? context.save()
    }

    // MARK: - Карточка слова

    private func handle(_ action: WordCard.Action, for candidate: Candidate) {
        let record = vocabulary.first { $0.lemma == candidate.lemma }
            ?? {
                let fresh = VocabularyRecord(lemma: candidate.lemma,
                                             english: candidate.english,
                                             gloss: candidate.gloss)
                context.insert(fresh)
                return fresh
            }()

        switch action {
        case .lookedUp:
            // Карточку просто открыли — она остаётся на экране.
            record.lookups += 1
            record.lastSeenAt = .now
        case .markLearned:
            record.isLearned = true
            tapped = nil
            Task { await buildPrepared() }   // слово освободило свой процент
        }
        save()
    }
}
