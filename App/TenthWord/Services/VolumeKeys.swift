import AVFoundation
import MediaPlayer
import SwiftUI

/// Перелистывание кнопками громкости.
///
/// **Осторожно, правило App Store 2.5.9.** Apple запрещает менять назначение
/// системных кнопок: «Apps that alter or disable the functions of standard
/// switches, such as the Volume Up/Down… will be rejected». Читалки с такой
/// возможностью в магазине есть, то есть правило применяется не всегда, —
/// но риск отказа реальный. Поэтому переключатель в настройках выключен
/// по умолчанию и включается только руками читателя.
///
/// Как это работает: iOS не отдаёт нажатия кнопок напрямую, поэтому мы следим
/// за громкостью аудиосессии. Изменилась вверх — листаем вперёд, вниз — назад,
/// после чего громкость возвращается на место, а системный ползунок на экране
/// не показывается: его подавляет невидимый `MPVolumeView` в иерархии.
@MainActor
final class VolumeKeys {

    /// Куда громкость возвращается после каждого нажатия. Не край шкалы:
    /// на нуле и на максимуме одно из двух направлений перестало бы работать.
    private static let restingVolume: Float = 0.5

    private var observation: NSKeyValueObservation?
    private var isRestoring = false
    private var onTurn: ((Bool) -> Void)?

    func start(onTurn: @escaping (Bool) -> Void) {
        guard observation == nil else { return }
        self.onTurn = onTurn

        let session = AVAudioSession.sharedInstance()
        do {
            // `.ambient` с `.mixWithOthers` — единственная категория, которая
            // не глушит чужую музыку. Читатель слушает подкаст и листает книгу.
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            return
        }

        setSystemVolume(Self.restingVolume)
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor [weak self] in self?.volumeChanged(to: value) }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        onTurn = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    deinit { observation?.invalidate() }

    private func volumeChanged(to value: Float) {
        // Возврат громкости на место — это тоже изменение громкости.
        // Без этого флага одно нажатие листало бы страницу дважды.
        if isRestoring {
            isRestoring = false
            return
        }
        guard abs(value - Self.restingVolume) > 0.001 else { return }
        onTurn?(value > Self.restingVolume)
        isRestoring = true
        setSystemVolume(Self.restingVolume)
    }

    /// Публичного способа выставить громкость нет — только ползунок внутри
    /// `MPVolumeView`. Это тот самый общеизвестный приём, на котором держатся
    /// все читалки с таким перелистыванием.
    private func setSystemVolume(_ value: Float) {
        let host = MPVolumeView(frame: .zero)
        guard let slider = host.subviews.compactMap({ $0 as? UISlider }).first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            slider.value = value
            slider.sendActions(for: .valueChanged)
        }
    }
}

/// Невидимый `MPVolumeView` в иерархии окна. Нужен ровно за тем, чтобы iOS
/// не показывала свой ползунок громкости поверх страницы на каждое нажатие.
struct VolumeKeysHost: UIViewRepresentable {

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        view.alpha = 0.0001
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}
