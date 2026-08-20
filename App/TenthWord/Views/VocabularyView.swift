import SwiftUI
import SwiftData

/// Словарь: побочный продукт чтения.
///
/// Показывает не то, что человек «учил», а то, что ему попадалось. Уверенность
/// растёт от встреч и падает от обращений к переводу — см. `VocabularyRecord`.
struct VocabularyView: View {

    @Environment(Theme.self) private var theme
    @Query(sort: \VocabularyRecord.lastSeenAt, order: .reverse)
    private var words: [VocabularyRecord]

    @State private var showsLearnedOnly = false

    private var shown: [VocabularyRecord] {
        showsLearnedOnly ? words.filter(\.isLearned) : words
    }

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .background(theme.background)
            .navigationTitle("Словарь")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Выученные", isOn: $showsLearnedOnly)
                        .toggleStyle(.button)
                        .font(.caption)
                }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(shown) { word in
                    row(word)
                }
            } header: {
                Text("\(words.count) слов встречено · \(words.filter(\.isLearned).count) выучено")
            }
        }
        .listStyle(.plain)
    }

    private func row(_ word: VocabularyRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(word.english)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(theme.text)
                Text("\(word.gloss) · \(word.encounters) раз")
                    .font(.caption)
                    .foregroundStyle(theme.text.opacity(0.5))
            }
            Spacer()
            confidenceBars(word.confidence)
        }
        .swipeActions {
            Button(word.isLearned ? "Учить снова" : "Выучено") {
                word.isLearned.toggle()
            }
            .tint(theme.accent)
        }
    }

    private func confidenceBars(_ level: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(index < level ? theme.accent : theme.text.opacity(0.15))
                    .frame(width: 5, height: 16)
            }
        }
        .accessibilityLabel("Уверенность \(level) из 5")
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("Пока пусто")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.text)
            Text("Слова появятся здесь сами, когда вы начнёте читать.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.text.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
