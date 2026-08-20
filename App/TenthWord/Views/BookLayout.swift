import UIKit
import ReaderCore

/// Собранный текст книги: английские слова уже подставлены.
///
/// Кроме самого текста хранит соответствие смещений. Читатель остановился
/// на слове «калитка» — запомнить надо позицию в исходной книге, а не в тексте
/// с подстановками: стоит покрутить кольцо, и текст с подстановками станет другим.
struct RenderedBook {

    /// Номер слова в плане перевода. Висит на подставленных английских словах,
    /// по нему тап находит карточку.
    static let ordinalKey = NSAttributedString.Key("tenthword.ordinal")

    let attributed: NSAttributedString

    /// Опорные точки соответствия: между соседними точками смещение сдвигается
    /// на постоянную величину, поэтому хранить каждый символ незачем.
    private let marks: [(rendered: Int, source: Int)]

    fileprivate init(attributed: NSAttributedString, marks: [(rendered: Int, source: Int)]) {
        self.attributed = attributed
        self.marks = marks
    }

    /// Позиция в исходной книге для позиции в тексте на экране.
    func sourceOffset(forRendered offset: Int) -> Int {
        guard let mark = lastMark(where: { $0.rendered <= offset }) else { return 0 }
        return mark.source + (offset - mark.rendered)
    }

    /// Обратный перевод: где искать позицию читателя после пересчёта.
    func renderedOffset(forSource offset: Int) -> Int {
        guard let mark = lastMark(where: { $0.source <= offset }) else { return 0 }
        return mark.rendered + (offset - mark.source)
    }

    private func lastMark(where predicate: ((rendered: Int, source: Int)) -> Bool)
        -> (rendered: Int, source: Int)? {
        var low = 0, high = marks.count
        while low < high {
            let middle = (low + high) / 2
            if predicate(marks[middle]) { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? marks[low - 1] : nil
    }
}

/// Сборка и разбивка книги на страницы средствами TextKit 2.
enum BookLayout {

    // MARK: - Сборка текста

    /// Собирает всю книгу с подстановками. Делается один раз на изменение процента
    /// или оформления, а не на каждую страницу: страницы потом нарезаются из готового.
    static func render(source: String,
                       prepared: PreparedText,
                       plan: TranslationPlan,
                       style: ReadingStyle) -> RenderedBook {
        let utf16 = Array(source.utf16)
        let result = NSMutableAttributedString()
        var marks: [(rendered: Int, source: Int)] = [(0, 0)]
        var cursor = 0

        func appendPlain(upTo end: Int) {
            guard end > cursor else { return }
            let slice = String(decoding: utf16[cursor..<end], as: UTF16.self)
            marks.append((result.length, cursor))
            result.append(NSAttributedString(string: slice, attributes: style.plainAttributes))
            cursor = end
        }

        for token in prepared.tokens {
            guard let candidate = plan.candidate(atOrdinal: token.ordinal) else { continue }
            appendPlain(upTo: token.utf16Offset)

            var attributes = style.translatedAttributes
            attributes[RenderedBook.ordinalKey] = token.ordinal
            marks.append((result.length, token.utf16Offset))
            result.append(NSAttributedString(
                string: candidate.display(capitalized: token.isCapitalized),
                attributes: attributes))

            cursor = token.utf16Offset + token.utf16Length
        }
        appendPlain(upTo: utf16.count)

        return RenderedBook(attributed: result, marks: marks)
    }

    // MARK: - Разбивка на страницы

    /// Начала страниц в смещениях собранного текста.
    ///
    /// Считается настоящей вёрсткой TextKit 2 под конкретный размер экрана:
    /// страница кончается там, где строка перестала помещаться по высоте,
    /// а не на условной тысяче знаков. Поэтому смена шрифта или размера
    /// требует пересчёта — и поэтому позиция читателя хранится в смещении,
    /// а не в номере страницы.
    ///
    /// Вызывать вне главного потока: на романе это сотни миллисекунд.
    static func pageStarts(for attributed: NSAttributedString, size: CGSize) -> [Int] {
        guard attributed.length > 0, size.width > 1, size.height > 1 else { return [0] }

        let storage = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        // Ширина фиксирована, высота свободна: страницы отмеряем сами,
        // построчно, иначе TextKit отдаст один бесконечный кусок.
        let container = NSTextContainer(size: CGSize(width: size.width, height: 0))
        container.lineFragmentPadding = 0
        layout.textContainer = container
        storage.addTextLayoutManager(layout)
        storage.textStorage?.setAttributedString(attributed)

        var starts = [0]
        // Отсчитываем по координатам строк, а не по сумме их высот: между
        // абзацами есть отступ, и без него страница набирает лишнюю строку,
        // которая потом срезается низом экрана.
        var pageTop: CGFloat = 0

        layout.enumerateTextLayoutFragments(from: storage.documentRange.location,
                                            options: [.ensuresLayout]) { fragment in
            let fragmentTop = fragment.layoutFragmentFrame.minY
            for line in fragment.textLineFragments {
                let lineTop = fragmentTop + line.typographicBounds.minY
                let lineBottom = lineTop + line.typographicBounds.height

                guard lineBottom - pageTop > size.height, lineTop > pageTop else { continue }

                if let location = storage.location(fragment.rangeInElement.location,
                                                   offsetBy: line.characterRange.location) {
                    let offset = storage.offset(from: storage.documentRange.location,
                                                to: location)
                    if offset > starts.last! {
                        starts.append(offset)
                        pageTop = lineTop
                    }
                }
            }
            return true
        }
        return starts
    }

    /// Диапазон страницы по её номеру.
    static func range(ofPage index: Int, starts: [Int], length: Int) -> NSRange {
        guard starts.indices.contains(index) else { return NSRange(location: 0, length: 0) }
        let start = starts[index]
        let end = starts.indices.contains(index + 1) ? starts[index + 1] : length
        return NSRange(location: start, length: max(0, end - start))
    }
}

/// Оформление чтения в виде готовых атрибутов TextKit.
///
/// Одни и те же атрибуты идут и в разбивку на страницы, и в показ страницы:
/// разойдутся — последняя строка будет обрезаться.
struct ReadingStyle: Equatable {

    let font: UIFont
    let textColor: UIColor
    let accentColor: UIColor
    let lineSpacing: CGFloat
    let marker: Theme.Marker

    var plainAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraphStyle]
    }

    var translatedAttributes: [NSAttributedString.Key: Any] {
        var attributes = plainAttributes
        switch marker {
        case .color:
            attributes[.foregroundColor] = accentColor
        case .underline:
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = accentColor
        case .both:
            attributes[.foregroundColor] = accentColor
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = accentColor
        }
        return attributes
    }

    private var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = lineSpacing
        return style
    }
}
