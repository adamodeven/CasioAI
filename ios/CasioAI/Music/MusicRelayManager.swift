import MediaPlayer
import UIKit
import Observation

/// Relays watch transport/volume commands to the system music player.
///
/// Volume is the one wrinkle: iOS has no public API to change the system
/// output volume directly. The standard (App-Store-safe) workaround is an
/// offscreen `MPVolumeView`, whose embedded `UISlider` you drive
/// programmatically — that's what `adjustSystemVolume` does. It needs to be
/// mounted in the key window to function, which happens lazily on first use.
@Observable
final class MusicRelayManager: NSObject {
    private let ble: BLEManager
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer
    private let volumeView = MPVolumeView(frame: .zero)
    private var commandListenerTask: Task<Void, Never>?

    init(ble: BLEManager) {
        self.ble = ble
        super.init()
        observeMusicCommands()
    }

    private func observeMusicCommands() {
        commandListenerTask = Task { [weak self] in
            guard let self else { return }
            for await command in self.ble.musicCommandStream() {
                self.handle(command)
            }
        }
    }

    private func handle(_ command: WatchProtocol.MusicCommand) {
        switch command {
        case .playPause:
            if musicPlayer.playbackState == .playing {
                musicPlayer.pause()
            } else {
                musicPlayer.play()
            }
        case .next:
            musicPlayer.skipToNextItem()
        case .previous:
            musicPlayer.skipToPreviousItem()
        case .volumeUp:
            adjustSystemVolume(by: 0.0625)
        case .volumeDown:
            adjustSystemVolume(by: -0.0625)
        }
    }

    private func adjustSystemVolume(by delta: Float) {
        mountVolumeViewIfNeeded()
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = min(1, max(0, slider.value + delta))
        slider.sendActions(for: .touchUpInside)
    }

    private func mountVolumeViewIfNeeded() {
        guard volumeView.superview == nil else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow })
        else { return }

        volumeView.frame = CGRect(x: -1000, y: -1000, width: 1, height: 1)
        volumeView.alpha = 0.001
        window.addSubview(volumeView)
    }
}
