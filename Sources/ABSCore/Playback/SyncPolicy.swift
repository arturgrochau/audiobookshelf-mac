import Foundation

/// When to report listening progress to the server.
///
/// Periodic syncs copy client/players/PlayerHandler.js exactly: listening time
/// is real seconds, the first sync waits for 20 s of listening, later ones for
/// 10 s, and a sync is skipped when the position moved less than 1 s.
///
/// Event syncs (pause, stop, quit, system sleep, sleep timer) come from the
/// mobile app, but are gated: the server marks a finished book unfinished and
/// un-hides it from Continue Listening whenever currentTime changes
/// (MediaProgress.js), so merely opening a finished book and pausing must not
/// sync. We only send when real listening (>20 s) or a seek happened, and never
/// a position within 1 s of where the session started.
public struct SyncPolicy: Sendable {
  public private(set) var listenedSinceSync: Double = 0
  public private(set) var lastSyncTime: Double = 0
  public private(set) var seekedSinceSync = false
  public let sessionStartTime: Double
  public var lowPowerMode = false
  public private(set) var failedSyncs = 0

  public init(sessionStartTime: Double) { self.sessionStartTime = sessionStartTime }

  /// Seconds of listening before the next periodic sync.
  public var threshold: Double {
    if lastSyncTime <= 0 { return 20 }
    return lowPowerMode ? 60 : 10
  }

  /// Called once per second while playing with the real time elapsed.
  /// Returns a body when a periodic sync is due.
  public mutating func tick(realElapsed: Double, currentTime: Double) -> SyncBody? {
    listenedSinceSync += max(0, realElapsed)
    guard listenedSinceSync >= threshold else { return nil }
    return take(currentTime: currentTime)
  }

  /// Web `sendProgressSync`: nil when the position moved < 1 s.
  public mutating func take(currentTime: Double) -> SyncBody? {
    guard abs(lastSyncTime - currentTime) >= 1 else { return nil }
    lastSyncTime = currentTime
    let listened = max(0, floor(listenedSinceSync))
    listenedSinceSync = 0
    seekedSinceSync = false
    return SyncBody(currentTime: currentTime, timeListened: listened)
  }

  public mutating func noteSeek() { seekedSinceSync = true }

  /// Pause / stop / quit / sleep: sync only once real listening happened in
  /// this session (a periodic sync went out, or > 20 s unsynced) or after a seek.
  public mutating func eventSync(currentTime: Double) -> SyncBody? {
    guard lastSyncTime > 0 || listenedSinceSync > 20 || seekedSinceSync else { return nil }
    guard abs(currentTime - sessionStartTime) >= 1 else { return nil }
    return take(currentTime: currentTime)
  }

  /// A seek while paused syncs immediately in the web client.
  public mutating func pausedSeekSync(currentTime: Double) -> SyncBody? {
    guard abs(currentTime - sessionStartTime) >= 1 || lastSyncTime > 0 else { return nil }
    return take(currentTime: currentTime)
  }

  /// Web `sendCloseSession`: carries data only when > 20 s are unsynced.
  public mutating func closeBody(currentTime: Double) -> SyncBody? {
    defer {
      listenedSinceSync = 0
      lastSyncTime = 0
    }
    if listenedSinceSync > 20 {
      return SyncBody(currentTime: currentTime, timeListened: max(0, floor(listenedSinceSync)))
    }
    // Otherwise the same gated event sync a pause would send.
    return eventSync(currentTime: currentTime)
  }

  /// Returns true when the web would show "Progress is not being synced".
  public mutating func recordResult(success: Bool) -> Bool {
    if success {
      failedSyncs = 0
      return false
    }
    failedSyncs += 1
    if failedSyncs >= 4 {
      failedSyncs = 0
      return true
    }
    return false
  }
}
