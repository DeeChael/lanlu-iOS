import SwiftUI
import AVFoundation
import MediaPlayer

enum ReaderVolumeButtonMode: String, CaseIterable, Identifiable {
    case off
    case volumeUpNext
    case volumeDownNext

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: String(localized: "reader_volume_button_off")
        case .volumeUpNext: String(localized: "reader_volume_up_next")
        case .volumeDownNext: String(localized: "reader_volume_down_next")
        }
    }
}

struct ReaderVolumeButtonControl: UIViewRepresentable {
    let mode: ReaderVolumeButtonMode
    let onVolumeUp: () -> Void
    let onVolumeDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onVolumeUp: onVolumeUp, onVolumeDown: onVolumeDown)
    }

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.showsRouteButton = false
        view.showsVolumeSlider = true
        view.alpha = 0.001
        context.coordinator.attach(to: view, mode: mode)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        context.coordinator.update(
            mode: mode,
            onVolumeUp: onVolumeUp,
            onVolumeDown: onVolumeDown
        )
    }

    static func dismantleUIView(_ uiView: MPVolumeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        private let audioSession = AVAudioSession.sharedInstance()
        private var observation: NSKeyValueObservation?
        private weak var slider: UISlider?
        private var originalVolume: Float?
        private var isResetting = false
        private var mode: ReaderVolumeButtonMode = .off
        private var onVolumeUp: () -> Void
        private var onVolumeDown: () -> Void
        private let baselineVolume: Float = 0.5

        init(onVolumeUp: @escaping () -> Void, onVolumeDown: @escaping () -> Void) {
            self.onVolumeUp = onVolumeUp
            self.onVolumeDown = onVolumeDown
        }

        func attach(to volumeView: MPVolumeView, mode: ReaderVolumeButtonMode) {
            self.mode = mode
            slider = volumeView.subviews.compactMap { $0 as? UISlider }.first
            originalVolume = audioSession.outputVolume
            try? audioSession.setActive(true)

            observation = audioSession.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                guard let newVolume = change.newValue else { return }
                DispatchQueue.main.async {
                    self?.handleVolumeChange(newVolume)
                }
            }
            resetVolumeToBaseline()
        }

        func update(
            mode: ReaderVolumeButtonMode,
            onVolumeUp: @escaping () -> Void,
            onVolumeDown: @escaping () -> Void
        ) {
            self.mode = mode
            self.onVolumeUp = onVolumeUp
            self.onVolumeDown = onVolumeDown
        }

        func detach() {
            observation?.invalidate()
            observation = nil
            if let originalVolume {
                setSystemVolume(originalVolume)
            }
            slider = nil
            originalVolume = nil
            mode = .off
        }

        private func handleVolumeChange(_ newVolume: Float) {
            guard mode != .off, !isResetting else { return }
            let difference = newVolume - baselineVolume
            guard abs(difference) > 0.001 else { return }

            if difference > 0 {
                onVolumeUp()
            } else {
                onVolumeDown()
            }
            resetVolumeToBaseline()
        }

        private func resetVolumeToBaseline() {
            isResetting = true
            setSystemVolume(baselineVolume)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.isResetting = false
            }
        }

        private func setSystemVolume(_ volume: Float) {
            guard let slider else { return }
            slider.setValue(volume, animated: false)
            slider.sendActions(for: .valueChanged)
        }
    }
}
