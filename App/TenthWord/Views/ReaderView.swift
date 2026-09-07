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
    @State private var showsAppearance = false
    @State private var showsPaywall = false
    @State private var glossZoneWarningShown = false

    /// Смещение пальца при перелистывании и размер экрана, на который
    /// уезжает страница. Оба нужны, чтобы анимация шла за пальцем,
    /// а не проигрывалась вслепую после отпускания.
    @State private var dragOffset: CGFloat = 0
    @State private var screenSpan: CGSize = .zero

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
        .sheet(isPresented: $showsAppearance) { ReadingAppearanceSheet() }
        .alert("Дальше — подстрочник", isPresented: $glossZoneWarningShown) {
            Button("Понятно") {}
        } message: {
            Text("Выше 60% переводятся и служебные слова. Текст станет английским "
                 + "с русской грамматикой: «Today morning I got up from bed». "
                 + "Читать можно, догадываться из контекста — уже почти не из чего.")
        }
    }

    // MARK: - Текст

    /// Соседние страницы держим смонтированными: только так перелистывание
    /// может идти за пальцем, а не проигрываться после отпускания.
    private var visiblePages: [Int] {
        [pageIndex - 1, pageIndex, pageIndex + 1].filter { pageStarts.indices.contains($0) }
    }

    private var page: some View {
        GeometryReader { geometry in
            let size = CGSize(width: geometry.size.width - 44,
                              height: geometry.size.height - 36)
            ZStack {
                ForEach(visiblePages, id: \.self) { index in
                    PageView(attributed: attributed(ofPage: index)) { ordinal in
                        tapped = plan?.candidate(atOrdinal: ordinal)
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .offset(shift(ofPage: index))
                }
            }
            // Без подрезки соседняя страница просвечивает сквозь верхнюю
            // панель: она стоит ровно на экран выше, а панель полупрозрачна.
            .clipped()
            .contentShape(Rectangle())
            .gesture(turnGesture)
            .task(id: geometry.size) { screenSpan = geometry.size }
            .task(id: size) {
                // Поворот экрана или первый показ: страницы считаются
                // под конкретную ширину и высоту.
                guard size.width > 1, size.height > 1, size != layoutSize else { return }
                layoutSize = size
                await rebuildLayout()
            }
        }
    }

    /// Текст одной страницы. Вырезается из готовой книги — сборка целиком
    /// делается один раз на изменение процента, а не на каждый перелистыв.
    private func attributed(ofPage index: Int) -> NSAttributedString {
        guard let rendered, pageStarts.indices.contains(index) else {
            return NSAttributedString()
        }
        let range = BookLayout.range(ofPage: index,
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
                     marker: theme.marker,
                     textAlign: theme.textAlign)
    }

    // MARK: - Перелистывание

    /// Насколько далеко уезжает страница: во всю ширину или во всю высоту.
    private var span: CGFloat {
        theme.pageTurn == .horizontal ? screenSpan.width : screenSpan.height
    }

    /// Положение страницы относительно текущей. Соседние стоят ровно
    /// на экран в стороне и въезжают следом за пальцем.
    private func shift(ofPage index: Int) -> CGSize {
        let delta = CGFloat(index - pageIndex) * span + dragOffset
        return theme.pageTurn == .horizontal
            ? CGSize(width: delta, height: 0)
            : CGSize(width: 0, height: delta)
    }

    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = resisted(travel(value.translation))
            }
            .onEnded { value in
                let travelled = travel(value.translation)
                let predicted = travel(value.predictedEndTranslation)
                // Либо утащили заметно, либо бросили с размаху — оба случая
                // читатель считает перелистыванием.
                let decided = abs(travelled) > span * 0.22 || abs(predicted) > span * 0.6
                if decided, travelled != 0 {
                    turnPage(forward: travelled < 0)
                } else {
                    settle()
                }
            }
    }

    /// Смещение вдоль той оси, по которой листаем.
    private func travel(_ translation: CGSize) -> CGFloat {
        theme.pageTurn == .horizontal ? translation.width : translation.height
    }

    /// На первой и последней странице палец вязнет — вместо мёртвого упора.
    private func resisted(_ raw: CGFloat) -> CGFloat {
        let beforeFirst = pageIndex == 0 && raw > 0
        let afterLast = pageIndex >= pageStarts.count - 1 && raw < 0
        return (beforeFirst || afterLast) ? raw / 3 : raw
    }

    private func settle() {
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.86)) {
            dragOffset = 0
        }
    }

    func turnPage(forward: Bool) {
        let next = pageIndex + (forward ? 1 : -1)
        guard pageStarts.indices.contains(next) else { settle(); return }

        // Бесплатный лимит считается перелистываниями, а не временем на экране.
        if forward, !trial.registerPageTurn() {
            settle()
            showsPaywall = true
            return
        }

        // Страница доезжает до края, и только потом лента переставляется
        // на новую середину — иначе видно рывок.
        withAnimation(.easeOut(duration: 0.26)) {
            dragOffset = forward ? -span : span
        } completion: {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                pageIndex = next
                dragOffset = 0
            }
            rememberPosition()
        }
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
        // Шрифт и тему крутят по ходу чтения, а нижняя панель вкладок
        // здесь спрятана — без этой кнопки пришлось бы выходить из книги.
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showsAppearance = true
            } label: {
                Image(systemName: "textformat.size")
            }
            .accessibilityLabel("Оформление")
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
        let started = Date()
        let result = await Task.detached(priority: .userInitiated) {
            engine.prepare(text)
        }.value
        #if DEBUG
        print("⏱ разбор \(text.count) знаков: \(Int(Date().timeIntervalSince(started) * 1000)) мс")
        #endif

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
            let renderStarted = Date()
            let rendered = BookLayout.render(source: text,
                                             prepared: prepared,
                                             plan: plan,
                                             style: currentStyle)
            #if DEBUG
            print("⏱ сборка текста: \(Int(Date().timeIntervalSince(renderStarted) * 1000)) мс")
            let paginateStarted = Date()
            #endif
            let starts = BookLayout.pageStarts(for: rendered.attributed, size: size)
            #if DEBUG
            print("⏱ разбивка на \(starts.count) страниц: \(Int(Date().timeIntervalSince(paginateStarted) * 1000)) мс")
            #endif
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
