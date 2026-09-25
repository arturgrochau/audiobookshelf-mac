import ABSCore
import AVFoundation
import AppKit
import Foundation
import Observation

/// Web queue entry (store/globals.js playerQueueItems).
struct QueueItem: Identifiable, Hashable, Codable {
  var libraryItemId: String
  var title: String
  var subtitle: String
  var duration: Double
  var coverUpdatedAt: Double?
  var hasCover: Bool
  var id: String { libraryItemId }
}

/// Everything the player bar, menu bar, miniplayer and Now Playing show.
/// Session and sync semantics follow client/players/PlayerHandler.js; the
/// native additions (auto-rewind, fading sleep timer, sync on pause, silent
/// session recovery) follow the mobile app.
@MainActor @Observable
final class PlayerModel {
  static let shared = PlayerModel()

  // Loaded item
  private(set) var item: LibraryItem?
  private(set) var session: PlaybackSession?
  private(set) var timeline = Timeline(tracks: [], chapters: [])
  private(set) var isLocalPlayback = false
  private(set) var displayTitle = ""
  private(set) var displayAuthor = ""

  // Transport state
  private(set) var isPlaying = false
  private(set) var isLoading = false
  private(set) var isBuffering = false
  /// Refreshed at 1 Hz (web cadence) and on every seek; use `liveTime` for animation.
  private(set) var currentTime: Double = 0
  var rate: Double { liveRateOverride ?? settings.playbackRate }
  private(set) var volume: Double = 1
  private var volumeBeforeMute: Double = 1
  private var fadeMultiplier: Double = 1

  // Sleep timer
  private(set) var sleep = SleepTimer()
  private var autoSleepDisabledUntilWindowEnds = false

  // Queue
  var queue: [QueueItem] = []

  // UI requests (keyboard shortcuts open these)
  var showChapters = false
  var showBookmarks = false
  var showSleepTimer = false
  var showQueue = false
  var showPlayerSettings = false

  let engine = AudioEngine()
  private let settings = AppSettings.shared
  private var app: AppModel { AppModel.shared }
  private var sync = SyncPolicy(sessionStartTime: 0)
  private var tickTimer: Timer?
  private var lastTick = Date()
  private var pausedAt: Date?
  private var sessionLost = false
  private var recovering = false
  private var localSession: LocalSession?
  private var socketHooked = false
  /// Bumped by every play(); an older call that resumes after an await gives up.
  private var playGeneration = 0
  /// Consecutive recoveries without a successful sync; stops a missing file from looping.
  private var recoveryAttempts = 0

  var hasItem: Bool { item != nil }
  var duration: Double {
    timeline.duration > 0 ? timeline.duration : (session?.duration ?? item?.duration ?? 0)
  }
  var chapters: [Chapter] { timeline.chapters }
  var currentChapter: Chapter? { timeline.chapter(at: currentTime) }
  var currentChapterIndex: Int? { timeline.chapterIndex(at: currentTime) }
  var liveTime: Double { item == nil ? 0 : engine.currentTime }
  var bookmarks: [Bookmark] { item.map { app.bookmarks(for: $0.id) } ?? [] }

  private init() {
    volume = settings.volume
    engine.volume = volume
    engine.onEnded = { [weak self] in self?.finished() }
    engine.onPlayingChanged = { [weak self] playing in self?.enginePlayingChanged(playing) }
    engine.onBufferingChanged = { [weak self] b in self?.isBuffering = b }
    engine.onFailed = { [weak self] message, status in self?.playbackFailed(message, status: status)
    }
  }

  func hookSocket() {
    guard !socketHooked else { return }
    socketHooked = true
    app.onSocket { [weak self] name, payload in self?.socketEvent(name, payload) }
  }

  // MARK: Starting playback

  /// Web `playLibraryItem`: resumes an already-loaded item, otherwise opens a
  /// session. `queue` replaces the current queue (every play does, as on the web).
  func play(_ itemId: String, startTime: Double? = nil, queue newQueue: [QueueItem]? = nil) async {
    if let item, item.id == itemId, session != nil || isLocalPlayback {
      if let newQueue { queue = newQueue }
      if let startTime { seek(to: startTime) }
      resume()
      return
    }
    playGeneration += 1
    let gen = playGeneration
    if let newQueue { queue = newQueue }
    await closeCurrent()
    guard gen == playGeneration else { return }
    isLoading = true
    defer { if gen == playGeneration { isLoading = false } }
    recoveryAttempts = 0

    let fetched = await LibraryStore.shared.expandedItem(itemId)
    guard gen == playGeneration else { return }
    guard let expanded = fetched ?? DownloadManager.shared.storedItem(itemId) else {
      clearLoadedItem()
      app.toast("Could not load this item", .error)
      return
    }
    if queue.isEmpty || !queue.contains(where: { $0.libraryItemId == itemId }) {
      queue = [Self.queueItem(expanded)]
    }
    item = expanded
    displayTitle = expanded.title
    displayAuthor = expanded.authorLine
    let local = DownloadManager.shared.localTracks(for: expanded)

    await LocalSessionStore.shared.flush(itemId: itemId)
    guard gen == playGeneration else { return }

    do {
      let s = try await openSession(itemId, forceDirectPlay: local != nil)
      guard gen == playGeneration else {
        try? await app.api.closeSession(s.id, nil)
        return
      }
      session = s
      isLocalPlayback = local != nil
      let start = startTime ?? s.currentTime
      load(session: s, localTracks: local, start: start)
    } catch {
      // Offline: a downloaded book still plays, recorded as a local session.
      guard gen == playGeneration else { return }
      if let local {
        startLocalSession(expanded, localTracks: local, startTime: startTime)
      } else {
        clearLoadedItem()
        app.toast(L.s("MessageServerCouldNotBeReached"), .error)
      }
    }
  }

  private func clearLoadedItem() {
    item = nil
    timeline = Timeline(tracks: [], chapters: [])
    displayTitle = ""
    displayAuthor = ""
    NowPlaying.shared.clear()
  }

  static func queueItem(_ i: LibraryItem) -> QueueItem {
    QueueItem(
      libraryItemId: i.id, title: i.title, subtitle: i.authorLine, duration: i.duration,
      coverUpdatedAt: i.updatedAt, hasCover: i.media.coverPath != nil)
  }

  private func openSession(_ itemId: String, forceDirectPlay: Bool) async throws -> PlaybackSession
  {
    let req = PlayRequest(
      deviceInfo: deviceInfo, supportedMimeTypes: Self.supportedMimeTypes,
      mediaPlayer: "AVPlayer", forceDirectPlay: forceDirectPlay)
    return try await app.api.play(itemId: itemId, request: req)
  }

  var deviceInfo: DeviceInfo {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    return DeviceInfo(
      deviceId: app.account?.deviceId ?? "mac", clientVersion: version, model: Self.macModel)
  }

  static let macModel: String = {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var buf = [CChar](repeating: 0, count: max(size, 1))
    sysctlbyname("hw.model", &buf, &size, nil, 0)
    return String(cString: buf)
  }()

  /// Audio MIME types AVFoundation plays; anything else makes the server transcode.
  static let supportedMimeTypes: [String] = {
    let all = Set(AVURLAsset.audiovisualMIMETypes().filter { $0.hasPrefix("audio/") })
    let wanted = [
      "audio/mpeg", "audio/mp4", "audio/aac", "audio/x-m4a", "audio/m4a", "audio/x-m4b",
      "audio/flac",
      "audio/x-flac", "audio/wav", "audio/x-wav", "audio/aiff", "audio/x-aiff", "audio/mp3",
      "audio/x-mp3",
    ]
    var out = wanted.filter { all.contains($0) }
    for base in ["audio/mpeg", "audio/mp4", "audio/aac", "audio/flac"] where !out.contains(base) {
      out.append(base)
    }
    return out
  }()

  private func load(session s: PlaybackSession, localTracks: [TrackSource]?, start: Double) {
    let tl = Timeline(
      audioTracks: s.audioTracks,
      chapters: s.chapters.isEmpty ? (item?.media.chapters ?? []) : s.chapters)
    timeline = tl
    displayTitle = s.displayTitle ?? displayTitle
    displayAuthor = s.displayAuthor ?? displayAuthor
    let base = app.streamBase
    let sources =
      localTracks
      ?? s.audioTracks.sorted { $0.startOffset < $1.startOffset }.map {
        TrackSource(
          url: base.appendingPathComponent("public/session/\(s.id)/track/\($0.index)"),
          startOffset: $0.startOffset, duration: $0.duration)
      }
    sync = SyncPolicy(sessionStartTime: start)
    sync.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    sessionLost = false
    engine.pitchAlgorithm = settings.pitchAlgorithm == "spectral" ? .spectral : .timeDomain
    engine.volume = volume * fadeMultiplier
    engine.load(
      sources, at: start, rate: rate, autoplay: true, localFiles: localTracks != nil || app.onLAN)
    currentTime = start
    pausedAt = nil
    applyAutoSleepIfNeeded()
    startTicking()
    NowPlaying.shared.update(full: true)
  }

  private func startLocalSession(_ it: LibraryItem, localTracks: [TrackSource], startTime: Double?)
  {
    let chapters = it.media.chapters ?? []
    timeline = Timeline(
      tracks: localTracks.enumerated().map {
        .init(
          index: $0.offset + 1, startOffset: $0.element.startOffset, duration: $0.element.duration)
      },
      chapters: chapters)
    // Newest wins between the offline outbox and the last known server progress;
    // a finished book starts over, as the server does for a new session.
    let progress = app.progress(for: it.id)
    let local = LocalSessionStore.shared.latest(itemId: it.id)
    let start: Double
    if let startTime {
      start = startTime
    } else if let local, local.updatedAt > (progress?.lastUpdate ?? 0) {
      start = local.currentTime
    } else if progress?.isFinished == true {
      start = 0
    } else {
      start = progress?.currentTime ?? 0
    }
    var ls = LocalSession(
      libraryItemId: it.id, displayTitle: it.title, displayAuthor: it.authorLine,
      duration: timeline.duration, chapters: chapters, coverPath: it.media.coverPath,
      startTime: start)
    ls.mediaPlayer = "AVPlayer"
    localSession = ls
    session = nil
    isLocalPlayback = true
    sync = SyncPolicy(sessionStartTime: start)
    engine.pitchAlgorithm = settings.pitchAlgorithm == "spectral" ? .spectral : .timeDomain
    engine.load(localTracks, at: start, rate: rate, autoplay: true, localFiles: true)
    currentTime = start
    startTicking()
    NowPlaying.shared.update(full: true)
  }

  // MARK: Transport

  func playPause() {
    guard item != nil else { return }
    if engine.isPlaying || isLoading { pause() } else { resume() }
  }

  func resume() {
    guard item != nil else { return }
    if sessionLost {
      // A press of Play is a fresh attempt, even after automatic ones gave up.
      recoveryAttempts = 0
      Task { await recoverSession(autoplay: true) }
      return
    }
    if engine.atEnd {
      // Web: play after the end starts the book over.
      engine.seek(to: 0)
      currentTime = 0
      sync.noteSeek()
    }
    if tickTimer == nil { startTicking() }
    // Mobile: rewind a little after a pause, depending on how long it was.
    if let pausedAt, !settings.disableAutoRewind {
      let target = AutoRewind.target(
        currentTime: engine.currentTime, pausedFor: Date().timeIntervalSince(pausedAt),
        timeline: timeline)
      if target < engine.currentTime - 0.5 {
        engine.seek(to: target)
        currentTime = target
      }
    }
    if sleep.playPressed(currentTime: engine.currentTime, timeline: timeline) {
      if sleep.lastEndedWasAuto, settings.autoSleepAutoRewind {
        let t = max(0, engine.currentTime - settings.autoSleepAutoRewindTime)
        engine.seek(to: t)
        currentTime = t
      }
    }
    pausedAt = nil
    applyAutoSleepIfNeeded()
    engine.play(rate: rate)
  }

  func pause() {
    engine.pause()
    pausedAt = Date()
    if let body = sync.eventSync(currentTime: engine.currentTime) { send(body) }
  }

  func seek(to t: Double) {
    guard item != nil else { return }
    let target = max(0, min(t, duration))
    engine.seek(to: target)
    currentTime = target
    sync.noteSeek()
    sleep.noteSeek()
    pausedAt = nil
    if tickTimer == nil { startTicking() }
    if !engine.isPlaying, let body = sync.pausedSeekSync(currentTime: target) { send(body) }
    NowPlaying.shared.update(full: false)
  }

  func jumpForward() { seek(to: min(engine.currentTime + settings.jumpForwardAmount, duration)) }
  func jumpBackward() { seek(to: max(0, engine.currentTime - settings.jumpBackwardAmount)) }

  func previousChapter() { seek(to: timeline.previousChapterTarget(from: engine.currentTime)) }

  /// Web `goToNext`: next chapter, else the next queue item.
  func next() {
    if let t = timeline.nextChapterTarget(from: engine.currentTime) {
      seek(to: t)
    } else if let n = nextQueueItem {
      Task { await play(n.libraryItemId) }
    }
  }

  var hasNext: Bool { timeline.nextChapterTarget(from: currentTime) != nil || nextQueueItem != nil }
  var nextIsQueueItem: Bool {
    timeline.nextChapterTarget(from: currentTime) == nil && nextQueueItem != nil
  }

  var nextQueueItem: QueueItem? {
    guard let id = item?.id, let i = queue.firstIndex(where: { $0.libraryItemId == id }),
      i + 1 < queue.count
    else { return nil }
    return queue[i + 1]
  }

  func setRate(_ r: Double, persist: Bool = true) {
    let clamped = (max(0.5, min(10, r)) * 100).rounded() / 100
    if persist {
      liveRateOverride = nil
      settings.playbackRate = clamped
    } else {
      liveRateOverride = clamped
    }
    engine.setRate(clamped)
    NowPlaying.shared.update(full: false)
  }

  /// Keyboard speed changes are not saved on the web; they still apply.
  private var liveRateOverride: Double?

  func increaseRate() {
    let step = settings.playbackRateIncrementDecrement
    guard rate + step <= 10 + 0.0001 else { return }
    setRate(rate + step, persist: false)
  }

  func decreaseRate() {
    let step = settings.playbackRateIncrementDecrement
    guard rate - step >= 0.5 - 0.0001 else { return }
    setRate(rate - step, persist: false)
  }

  func setVolume(_ v: Double) {
    volume = max(0, min(1, v))
    if volume > 0 { volumeBeforeMute = volume }
    settings.volume = volume
    engine.volume = volume * fadeMultiplier
  }

  func toggleMute() {
    if volume > 0 {
      volumeBeforeMute = volume
      setVolume(0)
    } else {
      setVolume(volumeBeforeMute > 0 ? volumeBeforeMute : 0.5)
    }
  }

  // MARK: Sleep timer

  func setSleepTimer(seconds: Double) {
    sleep.fadeEnabled = !settings.disableSleepTimerFadeOut
    sleep.chimeEnabled = settings.sleepTimerChime
    sleep.set(seconds: seconds)
    restoreFade()
  }

  func setSleepTimerEndOfChapter() {
    sleep.fadeEnabled = !settings.disableSleepTimerFadeOut
    sleep.chimeEnabled = settings.sleepTimerChime
    sleep.setEndOfChapter(currentTime: engine.currentTime, timeline: timeline)
    restoreFade()
  }

  func cancelSleepTimer() {
    if sleep.isAuto { autoSleepDisabledUntilWindowEnds = true }
    sleep.cancel()
    restoreFade()
  }

  func incrementSleepTimer(_ s: Double) {
    sleep.increment(s)
    restoreFade()
  }
  func decrementSleepTimer(_ s: Double) { sleep.decrement(s) }

  var sleepRemaining: Double? { sleep.displayRemaining(currentTime: currentTime, rate: rate) }

  private func restoreFade() {
    fadeMultiplier = 1
    engine.volume = volume
  }

  private func applyAutoSleepIfNeeded() {
    guard settings.autoSleepTimer, !sleep.isSet else { return }
    let window = AutoSleepWindow(start: settings.autoSleepStart, end: settings.autoSleepEnd)
    guard window.contains(Date()) else {
      autoSleepDisabledUntilWindowEnds = false
      return
    }
    guard !autoSleepDisabledUntilWindowEnds else { return }
    sleep.fadeEnabled = !settings.disableSleepTimerFadeOut
    sleep.chimeEnabled = settings.sleepTimerChime
    if settings.autoSleepLength <= 0, !timeline.chapters.isEmpty {
      sleep.setEndOfChapter(currentTime: engine.currentTime, timeline: timeline, auto: true)
    } else {
      sleep.set(seconds: max(60, settings.autoSleepLength), auto: true)
    }
  }

  // MARK: Ticking (1 Hz while playing, like the web's play interval)

  private func startTicking() {
    tickTimer?.invalidate()
    lastTick = Date()
    let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(t, forMode: .common)
    tickTimer = t
  }

  private func stopTicking() {
    tickTimer?.invalidate()
    tickTimer = nil
  }

  private func tick() {
    let now = Date()
    let elapsed = now.timeIntervalSince(lastTick)
    lastTick = now
    currentTime = engine.currentTime
    // Buffering and stalls are not listening, and do not run the sleep timer down.
    guard engine.isAudible else { return }

    if let body = sync.tick(realElapsed: elapsed, currentTime: currentTime) { send(body) }
    if isLocalPlayback, session == nil { recordLocal(listened: elapsed) }

    for ev in sleep.tick(elapsed: elapsed, currentTime: currentTime, rate: rate, now: now) {
      switch ev {
      case .volume(let v):
        fadeMultiplier = v
        engine.volume = volume * v
      case .chime:
        NSSound(named: "Glass")?.play()
      case .fire(let back):
        // Pause, seek back to where the fade began, then sync that position.
        engine.pause()
        pausedAt = Date()
        let t = back ?? engine.currentTime
        if back != nil {
          engine.seek(to: t)
          currentTime = t
          sync.noteSeek()
        }
        restoreFade()
        if let body = sync.eventSync(currentTime: t) { send(body) }
        app.toast(L.s("ToastSleepTimerDone"), .info)
      }
    }
    if Int(now.timeIntervalSince1970) % 15 == 0 {
      applyAutoSleepIfNeeded()
      NowPlaying.shared.update(full: false)
    }
  }

  private func enginePlayingChanged(_ playing: Bool) {
    isPlaying = playing
    if playing { lastTick = Date() }
    currentTime = engine.currentTime
    NowPlaying.shared.update(full: false)
  }

  // MARK: Sync

  private func send(_ body: SyncBody) {
    if let s = session {
      let sid = s.id
      Task {
        do {
          try await app.api.syncSession(sid, body)
          if sync.recordResult(success: true) {}
          recoveryAttempts = 0
        } catch APIError.notFound {
          // A late 404 for a session already replaced is not ours to recover.
          guard session?.id == sid else { return }
          sessionLost = true
          await recoverSession(autoplay: engine.isPlaying)
        } catch {
          if sync.recordResult(success: false) {
            app.toast(L.s("ToastProgressIsNotBeingSynced"), .error, duration: 30)
          }
        }
      }
      if let item {
        var p =
          app.progress(for: item.id)
          ?? MediaProgress(id: "local-\(item.id)", libraryItemId: item.id)
        p.currentTime = body.currentTime
        p.duration = duration
        p.progress = duration > 0 ? body.currentTime / duration : 0
        p.lastUpdate = Date().timeIntervalSince1970 * 1000
        app.updateLocalProgress(p)
      }
    } else {
      // The event gate already passed (and cleared the seek flag): write it.
      recordLocal(force: true)
    }
  }

  /// Records offline listening. Written to the outbox only under the same
  /// rule as the event syncs (20 s listened or a seek), so merely opening a
  /// finished book offline never un-finishes it on the server.
  private func recordLocal(listened: Double = 0, force: Bool = false) {
    guard var ls = localSession else { return }
    ls.record(listened: listened, currentTime: engine.currentTime)
    localSession = ls
    guard force || ls.timeListening > 20 || sync.seekedSinceSync else { return }
    LocalSessionStore.shared.upsert(ls)
  }

  /// One path for every way a server session disappears (sync 404, track 404,
  /// user_session_closed, restart): open a new one and keep our position.
  private func recoverSession(autoplay: Bool) async {
    guard let item, !recovering else { return }
    guard recoveryAttempts < 3 else {
      sessionLost = true
      engine.pause()
      app.toast(L.s("ToastProgressIsNotBeingSynced"), .error, duration: 30)
      return
    }
    recoveryAttempts += 1
    recovering = true
    defer { recovering = false }
    let position = engine.currentTime
    let local = DownloadManager.shared.localTracks(for: item)
    let gen = playGeneration
    do {
      let s = try await openSession(item.id, forceDirectPlay: local != nil)
      // Another book was opened (or the player closed) while this was waiting.
      guard gen == playGeneration, self.item?.id == item.id else {
        try? await app.api.closeSession(s.id, nil)
        return
      }
      session = s
      sessionLost = false
      load(session: s, localTracks: local, start: position)
      if !autoplay {
        engine.pause()
        pausedAt = Date()
      }
    } catch {
      sessionLost = true
    }
  }

  private func playbackFailed(_ message: String, status: Int?) {
    guard item != nil else { return }
    if status == 404 || status == 410 || session != nil {
      sessionLost = true
      Task { await recoverSession(autoplay: true) }
    } else {
      app.toast(message, .error)
    }
  }

  // MARK: End / close

  private func finished() {
    // With no items left the queue player waits at rate 1 instead of pausing.
    engine.pause()
    stopTicking()
    let end = duration
    currentTime = end
    if let body = sync.take(currentTime: end) { send(body) }
    isPlaying = false
    if settings.notifyFinished, let item {
      Notifier.shared.post(title: "Finished", body: item.title)
    }
    // Web mediaFinished: auto-play the next queue item.
    if settings.playerQueueAutoPlay, let n = nextQueueItem {
      Task { await play(n.libraryItemId) }
    }
  }

  private func closeCurrent() async {
    stopTicking()
    let t = engine.currentTime
    if let s = session {
      let body = sync.closeBody(currentTime: t) ?? sync.eventSync(currentTime: t)
      try? await app.api.closeSession(s.id, body)
    }
    recordLocal()
    localSession = nil
    engine.unload()
    session = nil
    isLocalPlayback = false
    isPlaying = false
    sleep.cancel()
    restoreFade()
  }

  /// Close player (✕ in the bar): also clears the queue, like the web.
  func close() async {
    // Cancels a play() still waiting on the network.
    playGeneration += 1
    await closeCurrent()
    item = nil
    queue = []
    timeline = Timeline(tracks: [], chapters: [])
    NowPlaying.shared.clear()
  }

  /// Quit / system sleep: final sync without tearing the UI down.
  func flushForQuit() async {
    engine.pause()
    let t = engine.currentTime
    if let s = session {
      let body = sync.closeBody(currentTime: t) ?? sync.eventSync(currentTime: t)
      try? await app.api.closeSession(s.id, body)
    }
    recordLocal()
  }

  // MARK: Server reconciliation

  /// When the app comes forward or the socket reconnects while paused, adopt a
  /// newer position from another device.
  func reconcileWithServer() async {
    guard let item, !engine.isPlaying, session != nil else { return }
    guard let p = try? await app.api.progress(itemId: item.id), let t = p.currentTime else {
      return
    }
    app.updateLocalProgress(p)
    if abs(t - engine.currentTime) > 1, p.isFinished != true {
      engine.seek(to: t)
      currentTime = t
    }
  }

  private func socketEvent(_ name: String, _ payload: Data?) {
    switch name {
    case "user_item_progress_updated":
      struct P: Decodable {
        var id: String?
        var sessionId: String?
        var deviceDescription: String?
        var data: MediaProgress?
      }
      guard let payload, let p = try? JSONDecoder().decode(P.self, from: payload), let data = p.data
      else { return }
      app.updateLocalProgress(data)
      LibraryStore.shared.revision += 1
      guard let item, data.libraryItemId == item.id, let sid = p.sessionId, sid != session?.id
      else { return }
      if engine.isPlaying {
        app.toast(
          "Another session is open for this item on device \(p.deviceDescription ?? "unknown")",
          .warning, duration: 20)
      } else if let t = data.currentTime, abs(t - engine.currentTime) > 1 {
        engine.seek(to: t)
        currentTime = t
      }
    case "user_session_closed":
      guard let payload, let sid = try? JSONDecoder().decode(String.self, from: payload),
        sid == session?.id
      else { return }
      sessionLost = true
      if engine.isPlaying { Task { await recoverSession(autoplay: true) } }
    default: break
    }
  }

  // MARK: Bookmarks

  func addBookmark(title: String, time at: Double? = nil) async {
    guard let item else { return }
    let time = floor(at ?? engine.currentTime)
    let name = title.isEmpty ? Self.bookmarkDateTitle() : title
    do {
      let b = try await app.api.createBookmark(itemId: item.id, time: time, title: name)
      let marks =
        (app.user?.bookmarks ?? []).filter { !($0.libraryItemId == item.id && $0.time == b.time) }
      app.user?.bookmarks = marks + [b]
      app.toast(L.s("ToastBookmarkCreateSuccess"), .success)
    } catch {
      app.toast(L.s("ToastBookmarkCreateFailed"), .error)
    }
  }

  func renameBookmark(_ b: Bookmark, to title: String) async {
    var nb = b
    nb.title = title
    guard let updated = try? await app.api.updateBookmark(itemId: b.libraryItemId, nb) else {
      return
    }
    let marks = (app.user?.bookmarks ?? []).map {
      $0.libraryItemId == b.libraryItemId && $0.time == b.time ? updated : $0
    }
    app.user?.bookmarks = marks
  }

  func deleteBookmark(_ b: Bookmark) async {
    guard (try? await app.api.deleteBookmark(itemId: b.libraryItemId, time: b.time)) != nil else {
      app.toast(L.s("ToastRemoveFailed"), .error)
      return
    }
    let marks = (app.user?.bookmarks ?? []).filter {
      !($0.libraryItemId == b.libraryItemId && $0.time == b.time)
    }
    app.user?.bookmarks = marks
    app.toast(L.s("ToastBookmarkRemoveSuccess"), .success)
  }

  static func bookmarkDateTitle() -> String {
    let f = DateFormatter()
    f.dateFormat = "MM/dd/yyyy HH:mm"
    return f.string(from: Date())
  }

  // MARK: Queue

  func addToQueue(_ i: LibraryItem) {
    guard !queue.contains(where: { $0.libraryItemId == i.id }) else { return }
    queue.append(Self.queueItem(i))
  }

  func removeFromQueue(_ id: String) { queue.removeAll { $0.libraryItemId == id } }
  func isQueued(_ id: String) -> Bool { queue.contains { $0.libraryItemId == id } }
}
