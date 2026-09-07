import MediaPlayer
import SwiftUI

/// Control Center and media key integration. Optional, because macOS routes
/// the media keys to the most recent Now Playing app: with Entrain
/// registered, a play/pause key press pauses the soundscape rather than the
/// music it is sitting under.
@MainActor
enum NowPlaying {
    private static var targets: [(MPRemoteCommand, Any)] = []
    private static var attached: Bool { !targets.isEmpty }
    /// One square per mode, drawn the first time that mode is shown.
    private static var artwork: [Mode: MPMediaItemArtwork] = [:]

    static func attach(to session: Session) {
        guard !attached else { return }
        let center = MPRemoteCommandCenter.shared()
        let commands: [(MPRemoteCommand, @MainActor () async -> Void)] = [
            (center.playCommand, session.play),
            (center.pauseCommand, session.pause),
            (center.togglePlayPauseCommand, session.toggle),
        ]
        targets = commands.map { command, action in
            (command, command.addTarget { _ in
                Task { @MainActor in await action() }
                return .success
            })
        }
        update(session)
    }

    static func detach() {
        for (command, target) in targets {
            command.removeTarget(target)
        }
        targets = []
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }

    /// Called on every state change. Timed sessions report position and length
    /// so Control Center draws a progress bar; the system interpolates between
    /// updates from the playback rate, so no per-second refresh is needed.
    static func update(_ session: Session) {
        guard attached else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: session.title,
            MPMediaItemPropertyArtist: "Entrain",
            MPMediaItemPropertyArtwork: artwork(for: session.mode),
            MPNowPlayingInfoPropertyPlaybackRate: session.isPlaying ? 1.0 : 0.0,
        ]
        if let elapsed = session.elapsed {
            info[MPMediaItemPropertyPlaybackDuration] = Double(session.length.seconds)
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(elapsed)
        } else {
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = session.isPlaying ? .playing : .paused
    }

    /// The mode's tint under its symbol, so the Lock Screen and Control
    /// Center show which mode is on rather than a grey square. Rendered once
    /// at 600 points; the system scales it to each slot.
    private static func artwork(for mode: Mode) -> MPMediaItemArtwork {
        if let cached = artwork[mode] { return cached }
        let renderer = ImageRenderer(content: Artwork(mode: mode))
        renderer.scale = 2
        #if canImport(UIKit)
        nonisolated(unsafe) let image = renderer.uiImage ?? UIImage()
        #else
        nonisolated(unsafe) let image = renderer.nsImage ?? NSImage()
        #endif
        // MediaPlayer asks for the image on its own queue, so the handler
        // must not inherit this type's main-actor isolation.
        let made = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
        artwork[mode] = made
        return made
    }
}

private struct Artwork: View {
    let mode: Mode

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 132, style: .continuous)
                .fill(LinearGradient(
                    colors: [mode.tint, mode.tint.mix(with: .black, by: 0.35)],
                    startPoint: .top, endPoint: .bottom
                ))
            Image(systemName: mode.symbol)
                .font(.system(size: 300, weight: .medium))
                .foregroundStyle(mode.onTint)
        }
        .frame(width: 600, height: 600)
    }
}
