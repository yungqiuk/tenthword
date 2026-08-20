import SwiftUI
import UIKit

/// Оформление читалки: фон, текст, цвет перевода, шрифт.
///
/// Всё хранится в `AppStorage`, потому что настройки оформления — это ровно тот
/// случай, для которого он и сделан: несколько скалярных значений, которые нужны
/// половине экранов.
@Observable
final class Theme {

    // MARK: - Готовые темы

    struct Preset: Identifiable, Hashable {
        let id: String
        let name: String
        let background: Color
        let text: Color
        let accent: Color

        /// Тёмно-синяя — та, ради которой всё затевалось. Стоит первой и по умолчанию.
        static let all: [Preset] = [
            Preset(id: "navy", name: "Ночь",
                   background: Color(hex: 0x0C1A2B), text: Color(hex: 0xE7EEF6),
                   accent: Color(hex: 0xF2A93B)),
            Preset(id: "paper", name: "Бумага",
                   background: Color(hex: 0xFBF9F4), text: Color(hex: 0x1B2430),
                   accent: Color(hex: 0xB4720C)),
            Preset(id: "sepia", name: "Сепия",
                   background: Color(hex: 0xF3EBD8), text: Color(hex: 0x2A2118),
                   accent: Color(hex: 0x9A5B1E)),
            Preset(id: "forest", name: "Лес",
                   background: Color(hex: 0x14261C), text: Color(hex: 0xDDE9DF),
                   accent: Color(hex: 0x8FD694)),
            Preset(id: "ink", name: "Чернила",
                   background: Color(hex: 0x1C1620), text: Color(hex: 0xEDE4F0),
                   accent: Color(hex: 0xE39BC4))
        ]
    }

    // MARK: - Как выделяется переведённое слово

    enum Marker: String, CaseIterable, Identifiable {
        case color      // цветом
        case underline  // подчёркиванием, цвет текста обычный
        case both

        var id: String { rawValue }
        var label: String {
            switch self {
            case .color: return "Цветом"
            case .underline: return "Подчёркнуто"
            case .both: return "И то, и другое"
            }
        }
    }

    // MARK: - Шрифты
    //
    // Системные и те, что есть на устройстве без докачки. Свои гарнитуры добавятся
    // позже: каждая — это лицензия и полтора мегабайта в бандле.

    struct FontChoice: Identifiable, Hashable {
        let id: String
        let name: String
        /// nil — системный шрифт (New York для serif-режима).
        let postScriptName: String?

        static let all: [FontChoice] = [
            FontChoice(id: "system", name: "Системный", postScriptName: nil),
            FontChoice(id: "newyork", name: "New York", postScriptName: "NewYork-Regular"),
            FontChoice(id: "georgia", name: "Georgia", postScriptName: "Georgia"),
            FontChoice(id: "palatino", name: "Palatino", postScriptName: "Palatino-Roman"),
            FontChoice(id: "avenir", name: "Avenir", postScriptName: "AvenirNext-Regular")
        ]
    }

    // MARK: - Состояние

    var presetID: String { didSet { save() } }
    var backgroundHex: UInt32 { didSet { save() } }
    var textHex: UInt32 { didSet { save() } }
    var accentHex: UInt32 { didSet { save() } }
    var fontID: String { didSet { save() } }
    var fontSize: Double { didSet { save() } }
    var lineSpacing: Double { didSet { save() } }
    var marker: Marker { didSet { save() } }

    var background: Color { Color(hex: backgroundHex) }
    var text: Color { Color(hex: textHex) }
    var accent: Color { Color(hex: accentHex) }

    var readingFont: Font {
        if let name = Theme.FontChoice.all.first(where: { $0.id == fontID })?.postScriptName {
            return .custom(name, size: fontSize)
        }
        return .system(size: fontSize, design: .serif)
    }

    /// Тот же шрифт для TextKit: им считается разбивка на страницы,
    /// и разойтись со шрифтом показа он не имеет права.
    var readingUIFont: UIFont {
        if let name = Theme.FontChoice.all.first(where: { $0.id == fontID })?.postScriptName,
           let font = UIFont(name: name, size: fontSize) {
            return font
        }
        let system = UIFont.systemFont(ofSize: fontSize)
        guard let descriptor = system.fontDescriptor.withDesign(.serif) else { return system }
        return UIFont(descriptor: descriptor, size: fontSize)
    }

    // MARK: - Контраст
    //
    // Ползунки цвета позволяют выставить светло-серый по белому. Не даём:
    // читалка, в которой не видно текста, — это не оформление, а поломка.

    static let minimumContrast = 4.5

    var contrastRatio: Double {
        Color.contrastRatio(backgroundHex, textHex)
    }

    var isReadable: Bool { contrastRatio >= Theme.minimumContrast }

    /// Ближайший читаемый оттенок текста для выбранного фона.
    /// Подсказываем, а не запрещаем: пользователь двигает ползунок и видит,
    /// куда его надо довести.
    func nearestReadableText() -> Color {
        Color.contrastRatio(backgroundHex, 0xFFFFFF) >= Color.contrastRatio(backgroundHex, 0x000000)
            ? Color(hex: 0xFFFFFF)
            : Color(hex: 0x000000)
    }

    // MARK: -

    func apply(_ preset: Preset) {
        presetID = preset.id
        backgroundHex = preset.background.hexValue
        textHex = preset.text.hexValue
        accentHex = preset.accent.hexValue
    }

    init() {
        let defaults = UserDefaults.standard

        // UserDefaults отдаёт 0 и для «сохранён ноль», и для «ничего не сохранено».
        // Чёрный (0x000000) как осмысленное значение здесь не встречается — ни одна
        // тема не ставит чистый чёрный, — поэтому 0 трактуем как «первый запуск».
        func storedColor(_ key: String, fallback: Color) -> UInt32 {
            let stored = defaults.integer(forKey: key)
            return stored == 0 ? fallback.hexValue : UInt32(stored)
        }
        func storedNumber(_ key: String, fallback: Double) -> Double {
            let stored = defaults.double(forKey: key)
            return stored == 0 ? fallback : stored
        }

        let base = Preset.all[0]   // «Ночь» — тёмно-синяя, по умолчанию
        presetID = defaults.string(forKey: Keys.preset) ?? base.id
        backgroundHex = storedColor(Keys.background, fallback: base.background)
        textHex = storedColor(Keys.text, fallback: base.text)
        accentHex = storedColor(Keys.accent, fallback: base.accent)
        fontID = defaults.string(forKey: Keys.font) ?? "system"
        fontSize = storedNumber(Keys.size, fallback: 18)
        lineSpacing = storedNumber(Keys.spacing, fallback: 8)
        marker = Marker(rawValue: defaults.string(forKey: Keys.marker) ?? "") ?? .color
    }

    private enum Keys {
        static let preset = "theme.preset"
        static let background = "theme.background"
        static let text = "theme.text"
        static let accent = "theme.accent"
        static let font = "theme.font"
        static let size = "theme.size"
        static let spacing = "theme.spacing"
        static let marker = "theme.marker"
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(presetID, forKey: Keys.preset)
        defaults.set(Int(backgroundHex), forKey: Keys.background)
        defaults.set(Int(textHex), forKey: Keys.text)
        defaults.set(Int(accentHex), forKey: Keys.accent)
        defaults.set(fontID, forKey: Keys.font)
        defaults.set(fontSize, forKey: Keys.size)
        defaults.set(lineSpacing, forKey: Keys.spacing)
        defaults.set(marker.rawValue, forKey: Keys.marker)
    }
}

// MARK: - Цвет из HEX и контраст

extension Color {

    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Обратное преобразование. Нужно, чтобы сохранить выбор ползунка.
    var hexValue: UInt32 {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32(r * 255) << 16) | (UInt32(g * 255) << 8) | UInt32(b * 255)
        #else
        return 0
        #endif
    }

    /// Коэффициент контраста по WCAG. 4.5 — минимум для основного текста.
    static func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        let a = relativeLuminance(first), b = relativeLuminance(second)
        let lighter = max(a, b), darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let normalized = Double(value) / 255
            return normalized <= 0.03928
                ? normalized / 12.92
                : pow((normalized + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF)
             + 0.7152 * channel((hex >> 8) & 0xFF)
             + 0.0722 * channel(hex & 0xFF)
    }
}
