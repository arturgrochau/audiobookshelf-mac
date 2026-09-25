import ABSCore
import AVFoundation
import Foundation

/// One audio file of the book and where it sits on the book's timeline.
struct TrackSource: Hashable {
  var url: URL
  var startOffset: Double
  var duration: Double
}

/// Plays a book spread over several files as one timeline.
///
/// AVQueuePlayer holds only the current file and the next one, so moving from
/// file to file is gapless without opening every file at once. Durations and
/// offsets come from the server (AVFoundation only estimates MP3 durations), so
/// items are created with no asset keys loaded. Seeking into another file
/// rebuilds the pair.
@MainActor
final class AudioEngine {
  let player = AVQueuePlayer()
  private(set) var tracks: [TrackSource] = []
  private var itemPositions: [ObjectIdentifier: Int] = [:]
  private var pendingSeek: (position: Int, offset: Double)?
  /// The last file ended: the queue is empty and the position is the book's end.
  private(set) var atEnd = false
  private var lastPosition = 0
  private var observers: [NSObjectProtocol] = []
  private var statusObservation: NSKeyValueObservation?
  private var timeControlObservation: NSKeyValueObservation?

  var onEnded: (() -> Void)?
  var onFailed: ((_ message: String, _ httpStatus: Int?) -> Void)?
  var onPlayingChanged: ((Bool) -> Void)?
  var onBufferingChanged: ((Bool) -> Void)?
  var pitchAlgorithm: AVAudioTimePitchAlgorithm = .timeDomain

  init() {
    player.actionAtItemEnd = .advance
    let nc = NotificationCenter.default
    observers.append(
      nc.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main)
      { [weak self] note in
        MainActor.assumeIsolated { self?.itemEnded(note.object as? AVPlayerItem) }
      })
    observers.append(
      nc.addObserver(
        forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main
      ) { [weak self] note in
        MainActor.assumeIsolated {
          let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
          self?.fail(
            item: note.object as? AVPlayerItem,
            message: err?.localizedDescription ?? "Playback failed")
        }
      })
    observers.append(
      nc.addObserver(forName: AVPlayerItem.newErrorLogEntryNotification, object: nil, queue: .main)
      { [weak self] note in
        MainActor.assumeIsolated {
          guard let item = note.object as? AVPlayerItem, let self, self.owns(item),
            let event = item.errorLog()?.events.last,
            event.errorStatusCode == 404 || event.errorStatusCode == 410
          else { return }
          self.onFailed?("Track not found", event.errorStatusCode)
        }
      })
    timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) {
      [weak self] p, _ in
      let status = p.timeControlStatus
      DispatchQueue.main.async {
        self?.onPlayingChanged?(status == .playing)
        self?.onBufferingChanged?(status == .waitingToPlayAtSpecifiedRate)
      }
    }
  }

  // MARK: Loading

  func load(
    _ tracks: [TrackSource], at time: Double, rate: Double, autoplay: Bool, localFiles: Bool
  ) {
    self.tracks = tracks
    player.automaticallyWaitsToMinimizeStalling = !localFiles
    player.defaultRate = Float(rate)
    let (pos, off) = locate(time)
    rebuild(position: pos, offset: off)
    if autoplay { play(rate: rate) }
  }

  func unload() {
    player.pause()
    player.removeAllItems()
    itemPositions = [:]
    tracks = []
    statusObservation = nil
    pendingSeek = nil
    atEnd = false
    lastPosition = 0
  }

  private func makeItem(_ position: Int) -> AVPlayerItem {
    let asset = AVURLAsset(url: tracks[position].url)
    let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: [])
    item.audioTimePitchAlgorithm = pitchAlgorithm
    item.preferredForwardBufferDuration = 30
    itemPositions[ObjectIdentifier(item)] = position
    return item
  }

  private func rebuild(position: Int, offset: Double) {
    player.removeAllItems()
    itemPositions = [:]
    pendingSeek = nil
    statusObservation = nil
    atEnd = false
    guard tracks.indices.contains(position) else { return }
    lastPosition = position
    let first = makeItem(position)
    player.insert(first, after: nil)
    if position + 1 < tracks.count { player.insert(makeItem(position + 1), after: first) }
    if offset > 0.05 {
      pendingSeek = (position, offset)
      observeReady(first)
      player.seek(
        to: CMTime(seconds: offset, preferredTimescale: 1000), toleranceBefore: .zero,
        toleranceAfter: .zero)
    }
  }

  /// A seek issued before the item is ready can be dropped; repeat it once ready.
  private func observeReady(_ item: AVPlayerItem) {
    statusObservation = item.observe(\.status, options: [.new]) { [weak self] it, _ in
      DispatchQueue.main.async {
        guard let self, it.status == .readyToPlay, let seek = self.pendingSeek,
          self.itemPositions[ObjectIdentifier(it)] == seek.position
        else { return }
        self.pendingSeek = nil
        self.statusObservation = nil
        if abs(it.currentTime().seconds - seek.offset) > 0.5 {
          it.seek(
            to: CMTime(seconds: seek.offset, preferredTimescale: 1000), toleranceBefore: .zero,
            toleranceAfter: .zero,
            completionHandler: nil)
        }
      }
    }
  }

  private func owns(_ item: AVPlayerItem) -> Bool { itemPositions[ObjectIdentifier(item)] != nil }

  private func itemEnded(_ item: AVPlayerItem?) {
    guard let item, let pos = itemPositions[ObjectIdentifier(item)] else { return }
    itemPositions[ObjectIdentifier(item)] = nil
    if pos + 1 >= tracks.count {
      atEnd = true
      onEnded?()
      return
    }
    // The queue advanced to pos+1 on its own; keep one file ahead of it.
    let nextNext = pos + 2
    if nextNext < tracks.count, let current = player.items().last,
      itemPositions[ObjectIdentifier(current)] == pos + 1
    {
      player.insert(makeItem(nextNext), after: current)
    }
  }

  private func fail(item: AVPlayerItem?, message: String) {
    guard let item, owns(item) else { return }
    onFailed?(message, nil)
  }

  // MARK: Transport

  var currentPosition: Int {
    guard let item = player.currentItem, let p = itemPositions[ObjectIdentifier(item)] else {
      return lastPosition
    }
    lastPosition = p
    return p
  }

  /// Global time on the book's timeline.
  var currentTime: Double {
    guard !tracks.isEmpty else { return 0 }
    if atEnd { return duration }
    if let pending = pendingSeek { return tracks[pending.position].startOffset + pending.offset }
    let t = player.currentTime().seconds
    let local = t.isFinite ? t : 0
    let pos = currentPosition
    return tracks[min(pos, tracks.count - 1)].startOffset + local
  }

  var duration: Double { tracks.last.map { $0.startOffset + $0.duration } ?? 0 }

  var bufferedUntil: Double {
    guard let item = player.currentItem, let r = item.loadedTimeRanges.last?.timeRangeValue else {
      return currentTime
    }
    let end = (r.start + r.duration).seconds
    return tracks[min(currentPosition, max(0, tracks.count - 1))].startOffset
      + (end.isFinite ? end : 0)
  }

  var isPlaying: Bool { player.timeControlStatus != .paused }
  /// Actually producing audio (not buffering or stalled): what counts as listening.
  var isAudible: Bool { player.timeControlStatus == .playing }

  func play(rate: Double) {
    player.defaultRate = Float(rate)
    player.play()
  }

  func pause() { player.pause() }

  func setRate(_ rate: Double) {
    player.defaultRate = Float(rate)
    if player.rate != 0 { player.rate = Float(rate) }
  }

  var volume: Double {
    get { Double(player.volume) }
    set { player.volume = Float(max(0, min(1, newValue))) }
  }

  func seek(to time: Double) {
    guard !tracks.isEmpty else { return }
    let t = max(0, min(time, duration - 0.05))
    let (pos, off) = locate(t)
    if !atEnd, pos == currentPosition, let item = player.currentItem {
      if item.status == .readyToPlay {
        pendingSeek = nil
      } else {
        pendingSeek = (pos, off)
        observeReady(item)
      }
      player.seek(
        to: CMTime(seconds: off, preferredTimescale: 1000), toleranceBefore: .zero,
        toleranceAfter: .zero)
    } else {
      let wasPlaying = player.rate != 0
      rebuild(position: pos, offset: off)
      if wasPlaying { player.play() }
    }
  }

  private func locate(_ t: Double) -> (Int, Double) {
    let tl = Timeline(
      tracks: tracks.enumerated().map {
        .init(index: $0.offset, startOffset: $0.element.startOffset, duration: $0.element.duration)
      },
      chapters: [])
    let r = tl.locate(t)
    return (r.position, r.offset)
  }
}
