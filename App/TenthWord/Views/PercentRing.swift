import SwiftUI
import ReaderCore

/// Кольцо процентов: крутится пальцем, показывает долю перевода.
///
/// Главный орган управления во всём приложении. Живёт в двух размерах — маленьком
/// на карточке книги и большом в читалке, — поэтому все размеры считаются
/// от диаметра, а не задаются числами.
///
/// Шкала нелинейная: первые 60% занимают три четверти оборота. Логика в
/// `RingScale` из `Core` — там же, где её проверяют тесты.
struct PercentRing: View {

    @Binding var percent: Int

    var diameter: CGFloat = 150
    var accent: Color = .orange
    var track: Color = .white.opacity(0.18)
    var label: Color = .white
    var showsZoneLabel = true
    var isInteractive = true

    /// Последнее значение, на котором сработала отдача. Отдача даётся на каждых 5%,
    /// иначе палец получает вибрацию непрерывно и это раздражает.
    @State private var lastHapticStep: Int = -1
    @State private var isDragging = false

    private var lineWidth: CGFloat { diameter * 0.06 }
    private var radius: CGFloat { (diameter - lineWidth) / 2 }

    var body: some View {
        ZStack {
            track_
            progress
            if isInteractive { handle }
            readout
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(isInteractive ? rotation : nil)
        .accessibilityElement()
        .accessibilityLabel("Доля перевода")
        .accessibilityValue("\(percent) процентов, \(RingScale.zoneLabel(forPercent: percent).lowercased())")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: percent = min(100, percent + 1)
            case .decrement: percent = max(0, percent - 1)
            default: break
            }
        }
    }

    // MARK: - Части кольца

    private var track_: some View {
        Circle()
            .trim(from: 0, to: RingScale.sweepDegrees / 360)
            .stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(RingScale.startDegrees))
            .overlay(breakMark)
    }

    private var progress: some View {
        Circle()
            .trim(from: 0, to: RingScale.fraction(forPercent: Double(percent))
                              * RingScale.sweepDegrees / 360)
            .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(RingScale.startDegrees))
            .animation(isDragging ? nil : .snappy(duration: 0.25), value: percent)
    }

    /// Риска на 60%: дальше начинается подстрочник.
    private var breakMark: some View {
        Rectangle()
            .fill(.background)
            .frame(width: 2.5, height: lineWidth + 2)
            .offset(y: -radius)
            .rotationEffect(.degrees(RingScale.degrees(forPercent: RingScale.breakPoint) + 90))
    }

    private var handle: some View {
        Circle()
            .fill(accent)
            .frame(width: lineWidth * 1.35, height: lineWidth * 1.35)
            .offset(y: -radius)
            .rotationEffect(.degrees(RingScale.degrees(forPercent: Double(percent)) + 90))
            .shadow(radius: isDragging ? 6 : 0)
            .animation(isDragging ? nil : .snappy(duration: 0.25), value: percent)
    }

    private var readout: some View {
        VStack(spacing: diameter * 0.035) {
            Text("\(percent)%")
                .font(.system(size: diameter * 0.26, weight: .regular, design: .serif))
                .foregroundStyle(label)
                .contentTransition(.numericText())
                .monospacedDigit()

            if showsZoneLabel {
                Text(RingScale.zoneLabel(forPercent: percent))
                    .font(.system(size: max(8, diameter * 0.065), weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(RingScale.isGlossZone(percent) ? accent : label.opacity(0.55))
            }
        }
    }

    // MARK: - Вращение

    private var rotation: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                update(from: value.location)
            }
            .onEnded { _ in
                isDragging = false
                lastHapticStep = -1
            }
    }

    private func update(from location: CGPoint) {
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y

        // Угол от начала развёртки, по часовой стрелке.
        var degrees = atan2(dy, dx) * 180 / .pi - RingScale.startDegrees
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }

        // Мёртвая зона в разрыве кольца: палец там — значит, промахнулся,
        // а не хочет прыгнуть с нуля на сотню.
        let deadZoneStart = RingScale.sweepDegrees + (360 - RingScale.sweepDegrees) / 2
        guard degrees <= deadZoneStart else { return }

        let fraction = min(degrees, RingScale.sweepDegrees) / RingScale.sweepDegrees
        let newValue = Int(RingScale.percent(forFraction: fraction).rounded())
        guard newValue != percent else { return }

        percent = newValue
        emitHaptic(for: newValue)
    }

    private func emitHaptic(for value: Int) {
        #if canImport(UIKit)
        let step = value / RingScale.hapticStep
        guard step != lastHapticStep else { return }
        lastHapticStep = step
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        #endif
    }
}

#Preview("Кольцо") {
    struct Demo: View {
        @State private var percent = 12
        var body: some View {
            VStack(spacing: 40) {
                PercentRing(percent: $percent, diameter: 180, accent: Color(hex: 0xF2A93B))
                PercentRing(percent: $percent, diameter: 44,
                            accent: Color(hex: 0xF2A93B),
                            showsZoneLabel: false, isInteractive: false)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: 0x0C1A2B))
        }
    }
    return Demo()
}
