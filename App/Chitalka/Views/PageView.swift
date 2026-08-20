import SwiftUI
import UIKit

/// Одна страница книги.
///
/// `UITextView` на TextKit 2 без прокрутки: страница уже нарезана так, чтобы
/// поместиться целиком. Своя вьюха нужна ради того же движка вёрстки, что считал
/// разбивку, — `Text` из SwiftUI ломает строки чуть иначе, и последняя строка
/// страницы начала бы срезаться.
struct PageView: UIViewRepresentable {

    let attributed: NSAttributedString
    /// Тап по подставленному английскому слову. Отдаёт номер слова в плане.
    let onWordTap: (Int) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        // Ширину задаём сами — ровно ту, под которую считалась разбивка.
        view.textContainer.widthTracksTextView = false
        view.textContainer.heightTracksTextView = false
        view.adjustsFontForContentSizeCategory = false

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap))
        view.addGestureRecognizer(tap)
        context.coordinator.textView = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onWordTap = onWordTap
        if view.attributedText != attributed {
            view.attributedText = attributed
        }
    }

    /// Ширина приходит от SwiftUI. Её же кладём в текстовый контейнер:
    /// вьюха обязана ломать строки там же, где их ломала разбивка на страницы.
    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: UITextView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width > 1 else { return nil }
        uiView.textContainer.size = CGSize(width: width, height: 0)
        let height = proposal.height
            ?? uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onWordTap: onWordTap) }

    final class Coordinator: NSObject {

        var onWordTap: (Int) -> Void
        weak var textView: UITextView?

        init(onWordTap: @escaping (Int) -> Void) {
            self.onWordTap = onWordTap
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = textView, let text = view.attributedText, text.length > 0,
                  let offset = characterIndex(at: recognizer.location(in: view), in: view),
                  offset >= 0, offset < text.length else { return }

            // Тап между букв попадает на следующий символ — смотрим и предыдущий.
            for index in [offset, max(0, offset - 1)] {
                if let ordinal = text.attribute(RenderedBook.ordinalKey, at: index,
                                                effectiveRange: nil) as? Int {
                    onWordTap(ordinal)
                    return
                }
            }
        }

        /// Символ под пальцем.
        ///
        /// Через TextKit 2, а не через `closestPosition(to:)`: у вьюхи выключено
        /// выделение текста, а вместе с ним отключается и весь `UITextInput`,
        /// откуда `closestPosition` берёт ответ.
        private func characterIndex(at point: CGPoint, in view: UITextView) -> Int? {
            guard let layout = view.textLayoutManager,
                  let content = layout.textContentManager,
                  let fragment = layout.textLayoutFragment(for: point) else { return nil }

            let frame = fragment.layoutFragmentFrame
            let inFragment = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)

            let line = fragment.textLineFragments.first {
                $0.typographicBounds.minY <= inFragment.y
                    && inFragment.y < $0.typographicBounds.maxY
            } ?? fragment.textLineFragments.last

            guard let line else { return nil }

            let inLine = CGPoint(x: inFragment.x - line.typographicBounds.minX,
                                 y: inFragment.y - line.typographicBounds.minY)
            let fragmentStart = content.offset(from: content.documentRange.location,
                                               to: fragment.rangeInElement.location)
            return fragmentStart + line.characterIndex(for: inLine)
        }
    }
}
