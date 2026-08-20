import SwiftUI
import ReaderCore

/// Карточка слова: показывается по тапу на переведённое слово.
///
/// Главное здесь — связь между английским словом и той формой, в которой оно
/// стояло в книге. «bed ← кровати» запоминается лучше, чем просто «bed».
struct WordCard: View {

    enum Action {
        case lookedUp       // читатель посмотрел перевод — слово ещё не выучено
        case markLearned    // «больше не переводить»
    }

    let candidate: Candidate
    let theme: Theme
    let onAction: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(candidate.english)
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(theme.accent)
                Text(candidate.pos.russianLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(theme.text.opacity(0.5))
                Spacer()
            }

            Text(candidate.gloss)
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(theme.text)

            VStack(alignment: .leading, spacing: 3) {
                Text("в тексте: \(candidate.surface.lowercased()) → \(candidate.lemma)")
                if let note = candidate.note {
                    Text(note)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(theme.text.opacity(0.5))

            Spacer(minLength: 0)

            Button {
                onAction(.markLearned)
            } label: {
                Text("Больше не переводить")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .background(theme.text.opacity(0.08), in: Capsule())
            .foregroundStyle(theme.text)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.background)
        .onAppear { onAction(.lookedUp) }
    }
}
