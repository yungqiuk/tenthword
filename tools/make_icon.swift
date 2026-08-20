#!/usr/bin/env swift
// Иконка приложения. Рисуется кодом, а не лежит картинкой: цвета обязаны
// совпадать с темой приложения, а править их придётся ещё не раз.
//
// Запуск:
//     swift tools/make_icon.swift
//
// Кладёт 1024×1024 в App/TenthWord/Assets.xcassets/AppIcon.appiconset/.
// App Store требует иконку без прозрачности и без скруглений — систему
// скругляет сама.

import AppKit
import CoreGraphics
import Foundation

let side = 1024
let scale = CGFloat(side) / 1024

// Цвета из тёмной темы приложения (Theme.swift, пресет «Ночь»).
let background = CGColor(red: 0.055, green: 0.086, blue: 0.145, alpha: 1)   // #0E1625
let ink        = CGColor(red: 0.937, green: 0.945, blue: 0.961, alpha: 1)   // #EFF1F5
let accent     = CGColor(red: 0.976, green: 0.678, blue: 0.216, alpha: 1)   // #F9AD37

guard let context = CGContext(data: nil, width: side, height: side,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("не создаётся контекст")
}

// Фон
context.setFillColor(background)
context.fill(CGRect(x: 0, y: 0, width: side, height: side))

let center = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)

// Кольцо доли перевода: неполный круг — ровно та метафора, что в приложении.
let radius = 300 * scale
let lineWidth = 84 * scale

context.setLineWidth(lineWidth)
context.setLineCap(.round)

// Дорожка
context.setStrokeColor(ink.copy(alpha: 0.16)!)
context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
context.strokePath()

// Заполненная часть — 35%, отсчёт от верха по часовой стрелке.
let start = CGFloat.pi / 2
let filled = CGFloat.pi * 2 * 0.35
context.setStrokeColor(accent)
context.addArc(center: center, radius: radius,
               startAngle: start, endAngle: start - filled, clockwise: true)
context.strokePath()

// Две буквы внутри: русская и английская — это и есть суть приложения.
let font = NSFont(name: "NewYork-Semibold", size: 300 * scale)
    ?? NSFont.systemFont(ofSize: 300 * scale, weight: .semibold)

func draw(_ text: String, color: CGColor, at point: CGPoint) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color)!
    ]
    let line = NSAttributedString(string: text, attributes: attributes)
    let size = line.size()
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    line.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    NSGraphicsContext.restoreGraphicsState()
}

draw("Я", color: ink, at: CGPoint(x: center.x - 88 * scale, y: center.y))
draw("I", color: accent, at: CGPoint(x: center.x + 96 * scale, y: center.y))

guard let image = context.makeImage() else { fatalError("не выходит картинка") }

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = root.appendingPathComponent("App/TenthWord/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

let destination = folder.appendingPathComponent("icon-1024.png")
let bitmap = NSBitmapImageRep(cgImage: image)
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("не выходит PNG")
}
try data.write(to: destination)
print("Записано: \(destination.path)")
