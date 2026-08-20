import SwiftUI
import SwiftData
import ReaderCore

/// Полка. Первое, что видит читатель.
///
/// Сетка обложек, на каждой две шкалы: полоса — сколько прочитано, кольцо —
/// доля перевода. Третьей шкале места нет, см. `docs/DECISIONS.md`.
struct LibraryView: View {

    @Environment(\.modelContext) private var context
    @Environment(Theme.self) private var theme
    @Environment(TrialGuard.self) private var trial

    @Query(sort: \Book.lastOpenedAt, order: .reverse) private var books: [Book]

    @State private var isImporting = false
    @State private var importError: String?
    @State private var openedBook: Book?

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyShelf
                } else {
                    shelf
                }
            }
            .background(theme.background)
            .navigationTitle("Моя полка")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isImporting = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить книгу")
                }
            }
            .fileImporter(isPresented: $isImporting,
                          allowedContentTypes: [.epub, .fb2, .plainText],
                          allowsMultipleSelection: true) { result in
                importFiles(result)
            }
            .alert("Не получилось", isPresented: .constant(importError != nil)) {
                Button("Понятно") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .navigationDestination(item: $openedBook) { book in
                ReaderView(book: book)
            }
        }
    }

    // MARK: - Состояния полки

    private var shelf: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(books) { book in
                    BookCard(book: book, theme: theme) {
                        book.lastOpenedAt = .now
                        openedBook = book
                    }
                    .contextMenu {
                        Button("Удалить", systemImage: "trash", role: .destructive) {
                            LibraryService(context: context).delete(book)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var emptyShelf: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(theme.text.opacity(0.35))
            Text("Полка пустая")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.text)
            Text("Добавьте книгу в EPUB, FB2 или TXT —\nи выберите, какую долю слов переводить.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.text.opacity(0.6))
            Button("Добавить книгу") { isImporting = true }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let service = LibraryService(context: context)
            for url in urls {
                do { _ = try service.addBook(from: url) }
                catch { importError = error.localizedDescription }
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

/// Карточка книги: обложка, кольцо перевода, полоса прочитанного.
struct BookCard: View {

    @Bindable var book: Book
    let theme: Theme
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            cover
            progressBar
            HStack {
                Text("\(book.readPercent)% прочт.")
                Spacer()
                Text("\(book.translationPercent)% eng")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.text.opacity(0.5))
        }
    }

    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = book.coverImage, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                generatedCover
            }

            // Кольцо прямо на обложке: доля перевода меняется, не заходя в книгу.
            PercentRing(percent: $book.translationPercent,
                        diameter: 42,
                        accent: theme.accent,
                        track: .black.opacity(0.35),
                        label: .white,
                        showsZoneLabel: false)
                .background(Circle().fill(.black.opacity(0.45)))
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .aspectRatio(3 / 4.1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onOpen)
    }

    private var generatedCover: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hex: UInt32(book.coverHex)), Color(hex: 0x0C1A2B)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(book.coverGlyph)
                .font(.system(size: 76, weight: .regular, design: .serif))
                .foregroundStyle(.white.opacity(0.16))
                .offset(x: 6, y: -30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            Text(book.title)
                .font(.system(size: 11, weight: .medium, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(3)
                .padding(8)
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.text.opacity(0.15))
                Capsule().fill(theme.text.opacity(0.55))
                    .frame(width: geometry.size.width * book.readProgress)
            }
        }
        .frame(height: 3)
    }
}

import UniformTypeIdentifiers

extension UTType {
    /// EPUB система знает сама, а FB2 — нет: объявляем по расширению.
    static let epub = UTType(importedAs: "org.idpf.epub-container")
    static let fb2 = UTType(filenameExtension: "fb2") ?? .xml
}
