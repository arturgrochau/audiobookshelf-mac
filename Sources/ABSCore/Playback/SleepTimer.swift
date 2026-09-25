import Foundation

/// Sleep timer with the web client's options (SleepTimerModal.vue) and the
/// mobile app's behaviour (SleepTimerManager.kt / AudioPlayerSleepTimer.swift):
/// it only counts while playing, fades out over the last minute and then seeks
/// back to where the fade began, and pressing play within 2 minutes of it
/// ending re-arms it with the same length.
public struct SleepTimer: Sendable {
  public enum Mode: Sendable, Equatable { case countdown, endOfChapter }

  public enum Event: Sendable, Equatable {
    case volume(Double)
    case chime
    /// Pause now; seek back to `seekBackTo` when the fade covered some audio.
    case fire(seekBackTo: Double?)
  }

  public static let presets: [Double] = [5, 15, 20, 30, 45, 60, 90, 120].map { $0 * 60 }
  public static let fadeDuration: Double = 60
  public static let rearmWindow: Double = 120

  public private(set) var mode: Mode?
  /// Countdown: listening seconds left.
  public private(set) var remaining: Double = 0
  /// EoC: absolute media time where playback stops.
  public private(set) var chapterEnd: Double?
  public private(set) var isAuto = false

  public var fadeEnabled = true
  public var chimeEnabled = false

  private var armedLength: Double = 0
  private var lastMode: Mode?
  private var lastWasAuto = false
  private var endedAt: Date?
  private var fadeStartPosition: Double?
  private var fading = false
  private var chimed = false

  public init() {}

  public var isSet: Bool { mode != nil }

  /// Seconds left as shown to the user (EoC: media seconds ÷ rate).
  public func displayRemaining(currentTime: Double, rate: Double) -> Double? {
    switch mode {
    case .countdown: return remaining
    case .endOfChapter: return chapterEnd.map { max(0, ($0 - currentTime) / max(rate, 0.01)) }
    case nil: return nil
    }
  }

  public mutating func set(seconds: Double, auto: Bool = false) {
    guard seconds > 0 else { return }
    mode = .countdown
    remaining = seconds
    armedLength = seconds
    chapterEnd = nil
    isAuto = auto
    resetRun()
  }

  /// End of Chapter. Within 10 s of the chapter's end it targets the next one.
  public mutating func setEndOfChapter(currentTime: Double, timeline: Timeline, auto: Bool = false)
  {
    mode = .endOfChapter
    chapterEnd = Self.endOfChapterTarget(currentTime: currentTime, timeline: timeline)
    remaining = 0
    armedLength = 0
    isAuto = auto
    resetRun()
  }

  public static func endOfChapterTarget(currentTime: Double, timeline: Timeline) -> Double {
    guard let i = timeline.chapterIndex(at: currentTime) else { return timeline.duration }
    var end = timeline.chapters[i].end
    if end - currentTime < 10, i + 1 < timeline.chapters.count {
      end = timeline.chapters[i + 1].end
    }
    return min(end, timeline.duration)
  }

  public mutating func cancel() {
    mode = nil
    remaining = 0
    chapterEnd = nil
    endedAt = nil
    isAuto = false
    resetRun()
  }

  /// Web container: +N only while a timer is set.
  public mutating func increment(_ amount: Double) {
    guard mode == .countdown else { return }
    remaining += amount
    if remaining > Self.fadeDuration { fadeStartPosition = nil }
  }

  /// Web modal + container: an amount larger than what is left becomes
  /// 60 s (or 5 s under a minute); below the amount the timer drops to 3 s.
  public mutating func decrement(_ requested: Double) {
    guard mode == .countdown else { return }
    var amount = requested
    if amount > remaining { amount = remaining > 60 ? 60 : 5 }
    if remaining < amount {
      remaining = 3
      return
    }
    remaining = max(0, remaining - amount)
  }

  /// Advance by `elapsed` real seconds of playback. Call only while playing.
  public mutating func tick(elapsed: Double, currentTime: Double, rate: Double, now: Date = Date())
    -> [Event]
  {
    guard let mode else { return [] }
    var events: [Event] = []
    let left: Double
    switch mode {
    case .countdown:
      remaining = max(0, remaining - max(0, elapsed))
      left = remaining
    case .endOfChapter:
      left = displayRemaining(currentTime: currentTime, rate: rate) ?? 0
    }
    if chimeEnabled, !chimed, left <= 30, left > 0 {
      chimed = true
      events.append(.chime)
    }
    let finished =
      mode == .countdown ? left <= 0 : (chapterEnd.map { currentTime >= $0 - 0.05 } ?? true)
    if finished {
      // No volume restore here: the player pauses first, then restores it.
      events.append(.fire(seekBackTo: fadeEnabled ? fadeStartPosition : nil))
      finish(now: now)
      return events
    }
    if fadeEnabled, left <= Self.fadeDuration {
      if fadeStartPosition == nil { fadeStartPosition = currentTime }
      fading = true
      events.append(.volume(max(0, min(1, left / Self.fadeDuration))))
    } else if fading {
      // More than a fade's worth left again (seek back, +time): full volume.
      fading = false
      events.append(.volume(1))
    }
    return events
  }

  /// Play pressed. Returns true when a timer that ended less than 2 min ago
  /// was re-armed with its previous length.
  public mutating func playPressed(currentTime: Double, timeline: Timeline, now: Date = Date())
    -> Bool
  {
    guard mode == nil, let endedAt, now.timeIntervalSince(endedAt) <= Self.rearmWindow, let lastMode
    else { return false }
    switch lastMode {
    case .countdown: set(seconds: armedLength, auto: lastWasAuto)
    case .endOfChapter:
      setEndOfChapter(currentTime: currentTime, timeline: timeline, auto: lastWasAuto)
    }
    return true
  }

  /// A seek moves away from where the fade began, so the seek-back target is dropped.
  public mutating func noteSeek() { fadeStartPosition = nil }

  /// Whether the last timer that ended was an automatic one (for auto-rewind).
  public var lastEndedWasAuto: Bool { lastWasAuto }

  private mutating func finish(now: Date) {
    lastMode = mode
    lastWasAuto = isAuto
    endedAt = now
    mode = nil
    remaining = 0
    chapterEnd = nil
    isAuto = false
    resetRun()
  }

  private mutating func resetRun() {
    fadeStartPosition = nil
    fading = false
    chimed = false
  }
}

/// Mobile auto-rewind on resume (PlayerListener.kt calcPauseSeekBackTime).
public enum AutoRewind {
  public static func seconds(pausedFor p: Double) -> Double {
    switch p {
    case ..<10: return 0
    case ..<60: return 3
    case ..<300: return 10
    case ..<1800: return 20
    default: return 30
    }
  }

  /// Never rewinds past the start of the current chapter.
  public static func target(currentTime: Double, pausedFor: Double, timeline: Timeline) -> Double {
    let back = seconds(pausedFor: pausedFor)
    guard back > 0 else { return currentTime }
    var t = max(0, currentTime - back)
    if let c = timeline.chapter(at: currentTime) { t = max(t, c.start) }
    return t
  }
}

/// Mobile "Auto sleep timer": a daily window such as 22:00–06:00.
public struct AutoSleepWindow: Sendable, Equatable {
  public var startMinutes: Int
  public var endMinutes: Int

  public init(start: String, end: String) {
    startMinutes = Self.parse(start) ?? 22 * 60
    endMinutes = Self.parse(end) ?? 6 * 60
  }

  public static func parse(_ s: String) -> Int? {
    let p = s.split(separator: ":").compactMap { Int($0) }
    guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
    return p[0] * 60 + p[1]
  }

  public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
    let c = calendar.dateComponents([.hour, .minute], from: date)
    let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
    if startMinutes == endMinutes { return false }
    if startMinutes < endMinutes { return m >= startMinutes && m < endMinutes }
    return m >= startMinutes || m < endMinutes
  }
}
