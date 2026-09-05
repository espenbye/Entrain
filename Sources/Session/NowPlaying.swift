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

    static func update(_ session: Session) {
        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: session.title,
            MPMediaItemPropertyArtist: "Entrain",
            MPNowPlayingInfoPropertyIsLiveStream: true,
        ]
        info.playbackState = session.isPlaying ? .playing : .paused
    }
}
