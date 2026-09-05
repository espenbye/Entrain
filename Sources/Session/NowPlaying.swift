import MediaPlayer

/// Control Center and media key integration. Optional, because macOS routes
/// the media keys to the most recent Now Playing app: with Entrain
/// registered, a play/pause key press pauses the soundscape rather than the
/// music it is sitting under.
@MainActor
enum NowPlaying {
    private static var targets: [(MPRemoteCommand, Any)] = []
    private static var attached: Bool { !targets.isEmpty }

    static func attach(to session: Session) {
        guard !attached else { return }
        let center = MPRemoteCommandCenter.shared()
        let commands: [(MPRemoteCommand, @MainActor () -> Void)] = [
            (center.playCommand, session.play),
            (center.pauseCommand, session.pause),
            (center.togglePlayPauseCommand, session.toggle),
        ]
        targets = commands.map { command, action in
            (command, command.addTarget { _ in
                Task { @MainActor in action() }
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
}
