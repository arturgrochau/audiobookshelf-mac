import ABSCore
import AppKit
import Foundation
import MediaPlayer

/// Control Center / media keys / AirPods. On macOS `playbackState` must be set
/// explicitly or remote commands misbehave (MPNowPlayingInfoCenter.h).
@MainActor
final class NowPlaying {
  static let shared = NowPlaying()
  private var artwork: MPMediaItemArtwork?
  private var artworkItemId: String?
  private var registered = false

  private var player: PlayerModel { PlayerModel.shared }
  private var settings: AppSettings { AppSettings.shared }

  func registerCommands() {
    guard !registered else { return }
    registered = true
    let c = MPRemoteCommandCenter.shared()
    c.togglePlayPauseCommand.addTarget(handler: Self.run { $0.playPause() })
    c.playCommand.addTarget(handler: Self.run { $0.resume() })
    c.pauseCommand.addTarget(handler: Self.run { $0.pause() })
    // Web maps "stop" to pause.
    c.stopCommand.addTarget(handler: Self.run { $0.pause() })
    c.skipForwardCommand.addTarget(handler: Self.run { $0.jumpForward() })
    c.skipBackwardCommand.addTarget(handler: Self.run { $0.jumpBackward() })
    c.nextTrackCommand.addTarget(
      handler: Self.run { p in
        if AppSettings.shared.nextPrevSkipsChapters { p.next() } else { p.jumpForward() }
      })
    c.previousTrackCommand.addTarget(
      handler: Self.run { p in
        if AppSettings.shared.nextPrevSkipsChapters { p.previousChapter() } else { p.jumpBackward() }
      })
    c.changePlaybackPositionCommand.addTarget { event in
      guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      return MainActor.assumeIsolated {
        let p = PlayerModel.shared
        guard p.hasItem else { return .noActionableNowPlayingItem }
        let base = AppSettings.shared.useChapterTrack ? (p.currentChapter?.start ?? 0) : 0
        p.seek(to: base + e.positionTime * p.rate)
        return .success
      }
    }
    c.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 1, 1.2, 1.5, 2].map {
      NSNumber(value: $0)
    }
    c.changePlaybackRateCommand.addTarget { event in
      guard let e = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
      return MainActor.assumeIsolated {
        guard PlayerModel.shared.hasItem else { return .noActionableNowPlayingItem }
        PlayerModel.shared.setRate(Double(e.playbackRate))
        return .success
      }
    }
    refreshCommandConfig()
  }

  /// A remote-command handler that reports "nothing playing" when no item is loaded.
  private static func run(_ action: @escaping @MainActor (PlayerModel) -> Void)
    -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
  {
    { _ in
      MainActor.assumeIsolated {
        let p = PlayerModel.shared
        guard p.hasItem else { return .noActionableNowPlayingItem }
        action(p)
        return .success
      }
    }
  }

  func refreshCommandConfig() {
    let c = MPRemoteCommandCenter.shared()
    c.skipForwardCommand.preferredIntervals = [NSNumber(value: settings.jumpForwardAmount)]
    c.skipBackwardCommand.preferredIntervals = [NSNumber(value: settings.jumpBackwardAmount)]
    c.changePlaybackPositionCommand.isEnabled = settings.allowSeekingOnMediaControls
  }

  /// `full` also refreshes title/artwork; otherwise only time and rate.
  func update(full: Bool) {
    guard let item = player.item else {
      clear()
      return
    }
    refreshCommandConfig()
    let center = MPNowPlayingInfoCenter.default()
    // A new book starts from an empty dictionary so nothing of the previous one leaks.
    var info = (full || artworkItemId != item.id) ? [:] : (center.nowPlayingInfo ?? [:])
    let rate = player.rate
    let t = player.engine.currentTime
    let chapter = player.timeline.chapter(at: t)
    let chapterMode = settings.useChapterTrack && chapter != nil

    if full || info[MPMediaItemPropertyTitle] == nil || artworkItemId != item.id {
      info[MPMediaItemPropertyArtist] = player.displayAuthor
      info[MPMediaItemPropertyAlbumTitle] = item.media.metadata.seriesName ?? ""
      loadArtwork(item)
      info[MPMediaItemPropertyArtwork] = artworkItemId == item.id ? artwork : nil
    }
    info[MPMediaItemPropertyTitle] =
      chapterMode ? (chapter?.title ?? player.displayTitle) : player.displayTitle
    if chapterMode, let chapter {
      info[MPMediaItemPropertyPlaybackDuration] = (chapter.end - chapter.start) / rate
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = (t - chapter.start) / rate
      info[MPMediaItemPropertyAlbumTitle] = player.displayTitle
    } else {
      info[MPMediaItemPropertyPlaybackDuration] = player.duration / rate
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = t / rate
    }
    // Times are reported in listening time (÷ rate), as the player bar shows them.
    info[MPNowPlayingInfoPropertyPlaybackRate] = player.isPlaying ? 1.0 : 0.0
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
    if let idx = player.timeline.chapterIndex(at: t) {
      info[MPNowPlayingInfoPropertyChapterNumber] = idx
      info[MPNowPlayingInfoPropertyChapterCount] = player.timeline.chapters.count
    } else {
      info[MPNowPlayingInfoPropertyChapterNumber] = nil
      info[MPNowPlayingInfoPropertyChapterCount] = nil
    }
    center.nowPlayingInfo = info
    center.playbackState = player.isPlaying ? .playing : .paused
  }

  func clear() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
    artwork = nil
    artworkItemId = nil
  }

  private func loadArtwork(_ item: LibraryItem) {
    guard artworkItemId != item.id else { return }
    artworkItemId = item.id
    artwork = nil
    guard let url = AppModel.shared.coverURL(item) else { return }
    Task {
      guard let img = await ImagePipeline.shared.image(url, pixelWidth: 600) else { return }
      let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
      guard self.artworkItemId == item.id else { return }
      self.artwork = art
      self.update(full: false)
      var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
      info[MPMediaItemPropertyArtwork] = art
      MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
  }
}
