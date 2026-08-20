import Foundation

/// Разбор книжного файла в плоский текст.
///
/// Читалке нужен именно поток текста: перевод подменяет слова по смещениям,
/// а разметка EPUB для этого только мешает. Форматирование теряется сознательно —
/// абзацы сохраняются, всё остальное отбрасывается.
///
/// PDF не поддерживается: там нет потока текста, есть координаты символов.
/// Решение зафиксировано, см. `docs/DECISIONS.md`.
enum BookImporter {

    struct Result {
        let title: String
        let author: String
        let text: String
        let cover: Data?
        let format: String
    }

    enum Failure: LocalizedError {
        case unsupportedFormat(String)
        case unreadable(String)
        case zipSupportMissing

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext):
                return "Формат .\(ext) не поддерживается. Подойдут EPUB, FB2 и TXT."
            case .unreadable(let reason):
                return "Не удалось прочитать файл: \(reason)"
            case .zipSupportMissing:
                return "Для EPUB нужен пакет ZIPFoundation — добавьте его в проект (см. README)."
            }
        }
    }

    static func read(_ url: URL) throws -> Result {
        // Файл пришёл из Files и лежит вне песочницы — доступ надо запросить.
        let needsRelease = url.startAccessingSecurityScopedResource()
        defer { if needsRelease { url.stopAccessingSecurityScopedResource() } }

        switch url.pathExtension.lowercased() {
        case "epub": return try readEPUB(url)
        case "fb2": return try readFB2(url)
        case "txt": return try readTXT(url)
        default: throw Failure.unsupportedFormat(url.pathExtension)
        }
    }

    // MARK: - TXT

    private static func readTXT(_ url: URL) throws -> Result {
        // Русские тексты до сих пор встречаются в CP1251 — пробуем обе кодировки.
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1251)
            ?? String(decoding: data, as: UTF8.self)

        return Result(title: url.deletingPathExtension().lastPathComponent,
                      author: "", text: normalize(text), cover: nil, format: "txt")
    }

    // MARK: - FB2
    //
    // Один XML-файл целиком. Для русских книг формат распространённый,
    // и разбирается он проще, чем EPUB.

    private static func readFB2(_ url: URL) throws -> Result {
        let data = try Data(contentsOf: url)
        let parser = FB2Parser()
        guard parser.parse(data) else {
            throw Failure.unreadable("повреждённый FB2")
        }
        return Result(title: parser.title.isEmpty
                          ? url.deletingPathExtension().lastPathComponent : parser.title,
                      author: parser.author,
                      text: normalize(parser.body),
                      cover: parser.cover,
                      format: "fb2")
    }

    // MARK: - EPUB

    private static func readEPUB(_ url: URL) throws -> Result {
        #if canImport(ZIPFoundation)
        return try EPUBReader.read(url)
        #else
        throw Failure.zipSupportMissing
        #endif
    }

    // MARK: - Общее

    /// Схлопывает пробелы и лишние переводы строк, сохраняя абзацы.
    static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

/// Разбор FB2. Нужны заголовок, автор, обложка и текст абзацами.
private final class FB2Parser: NSObject, XMLParserDelegate {

    private(set) var title = ""
    private(set) var author = ""
    private(set) var body = ""
    private(set) var cover: Data?

    private var path: [String] = []
    private var buffer = ""
    private var binaryBuffer = ""
    private var authorParts: [String] = []
    private var isInsideDescription = false

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        path.append(name)
        buffer = ""
        if name == "description" { isInsideDescription = true }
        if name == "binary" { binaryBuffer = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
        if path.last == "binary" { binaryBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "description":
            isInsideDescription = false
        case "book-title" where title.isEmpty:
            title = text
        case "first-name", "middle-name", "last-name":
            if isInsideDescription, !text.isEmpty { authorParts.append(text) }
        case "p":
            // Абзацы из description — это аннотация, в текст книги они не идут.
            if !isInsideDescription, !text.isEmpty { body += text + "\n" }
        case "binary":
            if cover == nil {
                cover = Data(base64Encoded: binaryBuffer,
                             options: .ignoreUnknownCharacters)
            }
            binaryBuffer = ""
        default:
            break
        }

        buffer = ""
        path.removeLast()

        if name == "author", author.isEmpty {
            author = authorParts.joined(separator: " ")
            authorParts = []
        }
    }
}

#if canImport(ZIPFoundation)
import ZIPFoundation

/// Разбор EPUB.
///
/// EPUB — это ZIP с XHTML внутри. Порядок глав лежит в OPF-манифесте,
/// на который указывает META-INF/container.xml.
enum EPUBReader {

    static func read(_ url: URL) throws -> BookImporter.Result {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw BookImporter.Failure.unreadable("не открывается как ZIP")
        }

        guard let containerData = extract("META-INF/container.xml", from: archive),
              let opfPath = firstAttribute(in: containerData, element: "rootfile", named: "full-path"),
              let opfData = extract(opfPath, from: archive) else {
            throw BookImporter.Failure.unreadable("нет манифеста OPF")
        }

        let opf = OPFParser()
        _ = opf.parse(opfData)

        let base = (opfPath as NSString).deletingLastPathComponent
        func resolve(_ href: String) -> String {
            base.isEmpty ? href : base + "/" + href
        }

        var text = ""
        for href in opf.spineHrefs {
            guard let chapter = extract(resolve(href), from: archive) else { continue }
            text += stripHTML(String(decoding: chapter, as: UTF8.self)) + "\n\n"
        }

        let cover = opf.coverHref.flatMap { extract(resolve($0), from: archive) }

        return BookImporter.Result(
            title: opf.title.isEmpty
                ? url.deletingPathExtension().lastPathComponent : opf.title,
            author: opf.author,
            text: BookImporter.normalize(text),
            cover: cover,
            format: "epub")
    }

    private static func extract(_ path: String, from archive: Archive) -> Data? {
        guard let entry = archive[path] else { return nil }
        var data = Data()
        _ = try? archive.extract(entry) { data.append($0) }
        return data.isEmpty ? nil : data
    }

    /// Разметка выбрасывается целиком: читалке нужен поток текста.
    /// Блочные теги превращаются в перевод строки, чтобы не слиплись абзацы.
    private static func stripHTML(_ html: String) -> String {
        var result = html
        for pattern in ["<script[^>]*>[\\s\\S]*?</script>",
                        "<style[^>]*>[\\s\\S]*?</style>"] {
            result = result.replacingOccurrences(of: pattern, with: "",
                                                 options: [.regularExpression, .caseInsensitive])
        }
        result = result.replacingOccurrences(
            of: "</(p|div|h[1-6]|li|br)\\s*>", with: "\n",
            options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: "<[^>]+>", with: "",
                                             options: .regularExpression)
        return decodeEntities(result)
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, character) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<",
                                    "&gt;": ">", "&quot;": "\"", "&#39;": "'",
                                    "&mdash;": "—", "&ndash;": "–", "&laquo;": "«",
                                    "&raquo;": "»", "&hellip;": "…"] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }

    private static func firstAttribute(in data: Data, element: String,
                                       named attribute: String) -> String? {
        let finder = AttributeFinder(element: element, attribute: attribute)
        let parser = XMLParser(data: data)
        parser.delegate = finder
        parser.parse()
        return finder.value
    }

    private final class AttributeFinder: NSObject, XMLParserDelegate {
        private let element: String
        private let attribute: String
        var value: String?

        init(element: String, attribute: String) {
            self.element = element
            self.attribute = attribute
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            if value == nil, name == element { value = attributes[attribute] }
        }
    }

    /// OPF: заголовок, автор, порядок глав, обложка.
    private final class OPFParser: NSObject, XMLParserDelegate {
        private(set) var title = ""
        private(set) var author = ""
        private(set) var spineHrefs: [String] = []
        private(set) var coverHref: String?

        private var manifest: [String: String] = [:]      // id → href
        private var spineIDs: [String] = []
        private var coverID: String?
        private var buffer = ""

        func parse(_ data: Data) -> Bool {
            let parser = XMLParser(data: data)
            parser.delegate = self
            let ok = parser.parse()
            spineHrefs = spineIDs.compactMap { manifest[$0] }
            coverHref = coverID.flatMap { manifest[$0] }
            return ok
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            buffer = ""
            switch name {
            case "item":
                if let id = attributes["id"], let href = attributes["href"] {
                    manifest[id] = href
                    if attributes["properties"]?.contains("cover-image") == true {
                        coverID = id
                    }
                }
            case "itemref":
                if let idref = attributes["idref"] { spineIDs.append(idref) }
            case "meta":
                if attributes["name"] == "cover", let content = attributes["content"] {
                    coverID = coverID ?? content
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.hasSuffix("title"), title.isEmpty { title = text }
            if name.hasSuffix("creator"), author.isEmpty { author = text }
            buffer = ""
        }
    }
}
#endif
