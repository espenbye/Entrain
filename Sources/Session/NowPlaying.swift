import MediaPlayer

@MainActor
enum NowPlaying {
    static func attach(to session: Session) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in
            Task { @MainActor in session.play() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in session.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in session.toggle() }
            return .success
        }
        update(session)
    }

    /// Called on every state change. Timed sessions report position and length
    /// so Control Center draws a progress bar; the system interpolates between
    /// updates from the playback rate, so no per-second refresh is needed.
    static func update(_ session: Session) {
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
