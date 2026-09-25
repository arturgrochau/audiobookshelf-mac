import Foundation

/// A listening session recorded while playing a downloaded book (playMethod 3).
/// Sent to POST /api/session/local-all; the server keeps it by `id`, so the
/// same id is re-sent as the session grows, with the absolute listening total.
/// Progress is applied only when `updatedAt` is newer than the server's.
public struct LocalSession: Codable, Sendable, Identifiable, Hashable {
  public var id: String
  public var libraryItemId: String
  public var episodeId: String?
  public var mediaType: String = "book"
  public var displayTitle: String
  public var displayAuthor: String
  public var duration: Double
  public var playMethod: Int = 3
  public var mediaPlayer: String = "AVPlayer"
  public var chapters: [Chapter] = []
  public var coverPath: String?
  public var timeListening: Double
  public var startTime: Double
  public var currentTime: Double
  public var startedAt: Double
  public var updatedAt: Double
  public var date: String
  public var dayOfWeek: String
  /// Local bookkeeping: true once the server accepted the latest state.
  public var synced: Bool = false

  public init(
    libraryItemId: String, displayTitle: String, displayAuthor: String, duration: Double,
    chapters: [Chapter], coverPath: String?, startTime: Double, now: Date = Date()
  ) {
    id = UUID().uuidString.lowercased()
    self.libraryItemId = libraryItemId
    self.displayTitle = displayTitle
    self.displayAuthor = displayAuthor
    self.duration = duration
    self.chapters = chapters
    self.coverPath = coverPath
    timeListening = 0
    self.startTime = startTime
    currentTime = startTime
    startedAt = now.timeIntervalSince1970 * 1000
    updatedAt = startedAt
    (date, dayOfWeek) = Self.dayStrings(now)
  }

  public mutating func record(listened: Double, currentTime: Double, now: Date = Date()) {
    timeListening += max(0, listened)
    self.currentTime = currentTime
    updatedAt = now.timeIntervalSince1970 * 1000
    (date, dayOfWeek) = Self.dayStrings(now)
    synced = false
  }

  static func dayStrings(_ d: Date) -> (String, String) {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    let w = DateFormatter()
    w.locale = Locale(identifier: "en_US_POSIX")
    w.dateFormat = "EEEE"
    return (f.string(from: d), w.string(from: d))
  }

  enum CodingKeys: String, CodingKey {
    case id, libraryItemId, episodeId, mediaType, displayTitle, displayAuthor, duration, playMethod,
      mediaPlayer,
      chapters, coverPath, timeListening, startTime, currentTime, startedAt, updatedAt, date,
      dayOfWeek, synced
  }
}

public struct LocalSessionsBody: Encodable, Sendable {
  public var deviceInfo: DeviceInfo
  public var sessions: [LocalSession]
  public init(deviceInfo: DeviceInfo, sessions: [LocalSession]) {
    self.deviceInfo = deviceInfo
    self.sessions = sessions
  }
}

public struct LocalSessionsResult: Decodable, Sendable {
  public struct Entry: Decodable, Sendable {
    public var id: String
    public var success: Bool
    public var progressSynced: Bool?
    public var error: String?
  }
  public var results: [Entry]
}
