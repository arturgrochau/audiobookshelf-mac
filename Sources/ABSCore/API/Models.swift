import Foundation

// Codable mirrors of the ABS 2.36 JSON. Every field the server may omit is
// optional; shapes that vary by endpoint (series as array vs object, shelf
// entities by type) are decoded by hand.

public struct Permissions: Codable, Sendable, Hashable {
  public var download: Bool?
  public var update: Bool?
  public var delete: Bool?
  public var upload: Bool?
  public var accessAllLibraries: Bool?
  public var accessAllTags: Bool?
  public var accessExplicitContent: Bool?
}

public struct MediaProgress: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var libraryItemId: String
  public var episodeId: String?
  public var duration: Double?
  public var progress: Double?
  public var currentTime: Double?
  public var isFinished: Bool?
  public var hideFromContinueListening: Bool?
  public var ebookLocation: String?
  public var ebookProgress: Double?
  public var lastUpdate: Double?
  public var startedAt: Double?
  public var finishedAt: Double?

  public init(
    id: String, libraryItemId: String, episodeId: String? = nil, duration: Double? = nil,
    progress: Double? = nil, currentTime: Double? = nil, isFinished: Bool? = nil,
    hideFromContinueListening: Bool? = nil, ebookLocation: String? = nil,
    ebookProgress: Double? = nil, lastUpdate: Double? = nil, startedAt: Double? = nil,
    finishedAt: Double? = nil
  ) {
    self.id = id
    self.libraryItemId = libraryItemId
    self.episodeId = episodeId
    self.duration = duration
    self.progress = progress
    self.currentTime = currentTime
    self.isFinished = isFinished
    self.hideFromContinueListening = hideFromContinueListening
    self.ebookLocation = ebookLocation
    self.ebookProgress = ebookProgress
    self.lastUpdate = lastUpdate
    self.startedAt = startedAt
    self.finishedAt = finishedAt
  }
}

public struct Bookmark: Codable, Sendable, Hashable {
  public var libraryItemId: String
  public var time: Double
  public var title: String
  public var createdAt: Double?

  public init(libraryItemId: String, time: Double, title: String, createdAt: Double? = nil) {
    self.libraryItemId = libraryItemId
    self.time = time
    self.title = title
    self.createdAt = createdAt
  }
}

public struct User: Codable, Sendable {
  public var id: String
  public var username: String
  public var type: String?
  public var permissions: Permissions?
  public var mediaProgress: [MediaProgress]?
  public var bookmarks: [Bookmark]?
  public var seriesHideFromContinueListening: [String]?
  public var librariesAccessible: [String]?
  public var accessToken: String?
  public var refreshToken: String?
  public var token: String?

  public var isAdminOrUp: Bool { type == "admin" || type == "root" }

  enum CodingKeys: String, CodingKey {
    case id, username, type, permissions, mediaProgress, bookmarks,
      seriesHideFromContinueListening, librariesAccessible, accessToken, refreshToken, token
  }

  /// Progress and bookmark rows are decoded one by one: a single odd row (a
  /// migrated entry for a deleted item has a null libraryItemId) must not make
  /// the whole user, and so login, fail to decode.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    username = try c.decode(String.self, forKey: .username)
    type = try c.decodeIfPresent(String.self, forKey: .type)
    permissions = try? c.decodeIfPresent(Permissions.self, forKey: .permissions)
    mediaProgress = (try? c.decodeIfPresent(LossyArray<MediaProgress>.self, forKey: .mediaProgress))?
      .elements
    bookmarks = (try? c.decodeIfPresent(LossyArray<Bookmark>.self, forKey: .bookmarks))?.elements
    seriesHideFromContinueListening = try? c.decodeIfPresent(
      [String].self, forKey: .seriesHideFromContinueListening)
    librariesAccessible = try? c.decodeIfPresent([String].self, forKey: .librariesAccessible)
    accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken)
    refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
    token = try? c.decodeIfPresent(String.self, forKey: .token)
  }
}

public struct ServerSettings: Codable, Sendable {
  public var homeBookshelfView: Int?
  public var bookshelfView: Int?
  public var dateFormat: String?
  public var timeFormat: String?
  public var version: String?
  public var sortingIgnorePrefix: Bool?
  public var sortingPrefixes: [String]?
}

public struct LoginResponse: Codable, Sendable {
  public var user: User
  public var userDefaultLibraryId: String?
  public var serverSettings: ServerSettings?
}

public struct ServerStatus: Codable, Sendable {
  public var app: String?
  public var serverVersion: String?
  public var isInit: Bool?
  public var authMethods: [String]?
}

public struct LibrarySettings: Codable, Sendable, Hashable {
  public var coverAspectRatio: Int?
  public var hideSingleBookSeries: Bool?
  public var markAsFinishedPercentComplete: Double?
  public var markAsFinishedTimeRemaining: Double?
}

public struct Library: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var name: String
  public var icon: String?
  public var mediaType: String?
  public var displayOrder: Int?
  public var settings: LibrarySettings?

  /// Web: STANDARD = 1.6 (height = 1.6 × width), SQUARE = 1.
  public var coverAspect: Double { (settings?.coverAspectRatio ?? 1) == 0 ? 1.6 : 1.0 }
}

public struct LibrariesResponse: Codable, Sendable { public var libraries: [Library] }

public struct NamedRef: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var name: String
}

public struct SeriesRef: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var name: String
  public var sequence: String?
}

public struct BookMetadata: Codable, Sendable, Hashable {
  public var title: String?
  public var titleIgnorePrefix: String?
  public var subtitle: String?
  public var authorName: String?
  public var authorNameLF: String?
  public var narratorName: String?
  public var seriesName: String?
  public var genres: [String]?
  public var publishedYear: String?
  public var publishedDate: String?
  public var publisher: String?
  public var description: String?
  public var descriptionPlain: String?
  public var language: String?
  public var explicit: Bool?
  public var abridged: Bool?
  public var isbn: String?
  public var asin: String?
  public var authors: [NamedRef]?
  public var narrators: [String]?
  /// Expanded items carry an array; minified items filtered by series carry one object.
  public var series: [SeriesRef]?

  enum CodingKeys: String, CodingKey {
    case title, titleIgnorePrefix, subtitle, authorName, authorNameLF, narratorName, seriesName,
      genres,
      publishedYear, publishedDate, publisher, description, descriptionPlain, language, explicit,
      abridged, isbn, asin, authors, narrators, series
  }

  public init() {}

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    title = try? c.decodeIfPresent(String.self, forKey: .title)
    titleIgnorePrefix = try? c.decodeIfPresent(String.self, forKey: .titleIgnorePrefix)
    subtitle = try? c.decodeIfPresent(String.self, forKey: .subtitle)
    authorName = try? c.decodeIfPresent(String.self, forKey: .authorName)
    authorNameLF = try? c.decodeIfPresent(String.self, forKey: .authorNameLF)
    narratorName = try? c.decodeIfPresent(String.self, forKey: .narratorName)
    seriesName = try? c.decodeIfPresent(String.self, forKey: .seriesName)
    genres = try? c.decodeIfPresent([String].self, forKey: .genres)
    publishedYear = Self.stringish(c, .publishedYear)
    publishedDate = try? c.decodeIfPresent(String.self, forKey: .publishedDate)
    publisher = try? c.decodeIfPresent(String.self, forKey: .publisher)
    description = try? c.decodeIfPresent(String.self, forKey: .description)
    descriptionPlain = try? c.decodeIfPresent(String.self, forKey: .descriptionPlain)
    language = try? c.decodeIfPresent(String.self, forKey: .language)
    explicit = try? c.decodeIfPresent(Bool.self, forKey: .explicit)
    abridged = try? c.decodeIfPresent(Bool.self, forKey: .abridged)
    isbn = try? c.decodeIfPresent(String.self, forKey: .isbn)
    asin = try? c.decodeIfPresent(String.self, forKey: .asin)
    authors = try? c.decodeIfPresent([NamedRef].self, forKey: .authors)
    narrators = try? c.decodeIfPresent([String].self, forKey: .narrators)
    if let arr = try? c.decodeIfPresent([SeriesRef].self, forKey: .series) {
      series = arr
    } else if let one = try? c.decodeIfPresent(SeriesRef.self, forKey: .series) {
      series = [one]
    }
  }

  private static func stringish(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> String?
  {
    if let s = try? c.decodeIfPresent(String.self, forKey: k) { return s }
    if let i = try? c.decodeIfPresent(Int.self, forKey: k) { return String(i) }
    return nil
  }
}

public struct Chapter: Codable, Sendable, Hashable, Identifiable {
  public var id: Int
  public var start: Double
  public var end: Double
  public var title: String

  public init(id: Int, start: Double, end: Double, title: String) {
    self.id = id
    self.start = start
    self.end = end
    self.title = title
  }

  enum CodingKeys: String, CodingKey { case id, start, end, title }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id =
      (try? c.decode(Int.self, forKey: .id)) ?? Int((try? c.decode(Double.self, forKey: .id)) ?? 0)
    start = (try? c.decode(Double.self, forKey: .start)) ?? 0
    end = (try? c.decode(Double.self, forKey: .end)) ?? 0
    title = (try? c.decode(String.self, forKey: .title)) ?? ""
  }
}

public struct FileMetadata: Codable, Sendable, Hashable {
  public var filename: String?
  public var ext: String?
  public var path: String?
  public var relPath: String?
  public var size: Int64?
}

public struct AudioTrack: Codable, Sendable, Hashable {
  public var index: Int
  public var startOffset: Double
  public var duration: Double
  public var title: String?
  public var contentUrl: String?
  public var mimeType: String?
  public var codec: String?
  public var metadata: FileMetadata?

  public init(
    index: Int, startOffset: Double, duration: Double, title: String? = nil,
    contentUrl: String? = nil, mimeType: String? = nil, codec: String? = nil,
    metadata: FileMetadata? = nil
  ) {
    self.index = index
    self.startOffset = startOffset
    self.duration = duration
    self.title = title
    self.contentUrl = contentUrl
    self.mimeType = mimeType
    self.codec = codec
    self.metadata = metadata
  }
}

public struct AudioFile: Codable, Sendable, Hashable {
  public var index: Int?
  public var ino: String?
  public var duration: Double?
  public var mimeType: String?
  public var codec: String?
  public var bitRate: Double?
  public var metadata: FileMetadata?
}

public struct EbookFile: Codable, Sendable, Hashable {
  public var ino: String?
  public var ebookFormat: String?
  public var metadata: FileMetadata?
}

public struct LibraryFile: Codable, Sendable, Hashable {
  public var ino: String?
  public var fileType: String?
  public var metadata: FileMetadata?
}

public struct BookMedia: Codable, Sendable, Hashable {
  public var id: String?
  public var coverPath: String?
  public var tags: [String]?
  public var numTracks: Int?
  public var numChapters: Int?
  public var numAudioFiles: Int?
  public var duration: Double?
  public var size: Int64?
  public var ebookFormat: String?
  public var ebookFile: EbookFile?
  public var metadata: BookMetadata
  public var chapters: [Chapter]?
  public var tracks: [AudioTrack]?
  public var audioFiles: [AudioFile]?

  enum CodingKeys: String, CodingKey {
    case id, coverPath, tags, numTracks, numChapters, numAudioFiles, duration, size, ebookFormat,
      ebookFile, metadata, chapters, tracks, audioFiles
  }

  public init(metadata: BookMetadata) { self.metadata = metadata }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try? c.decodeIfPresent(String.self, forKey: .id)
    coverPath = try? c.decodeIfPresent(String.self, forKey: .coverPath)
    tags = try? c.decodeIfPresent([String].self, forKey: .tags)
    numTracks = try? c.decodeIfPresent(Int.self, forKey: .numTracks)
    numChapters = try? c.decodeIfPresent(Int.self, forKey: .numChapters)
    numAudioFiles = try? c.decodeIfPresent(Int.self, forKey: .numAudioFiles)
    duration = try? c.decodeIfPresent(Double.self, forKey: .duration)
    size = try? c.decodeIfPresent(Int64.self, forKey: .size)
    ebookFile = try? c.decodeIfPresent(EbookFile.self, forKey: .ebookFile)
    ebookFormat =
      (try? c.decodeIfPresent(String.self, forKey: .ebookFormat)) ?? ebookFile?.ebookFormat
    metadata = (try? c.decode(BookMetadata.self, forKey: .metadata)) ?? BookMetadata()
    chapters = try? c.decodeIfPresent([Chapter].self, forKey: .chapters)
    tracks = try? c.decodeIfPresent([AudioTrack].self, forKey: .tracks)
    audioFiles = try? c.decodeIfPresent([AudioFile].self, forKey: .audioFiles)
  }

  public var hasAudio: Bool {
    (numTracks ?? tracks?.count ?? audioFiles?.count ?? 0) > 0 || (duration ?? 0) > 0
  }
  public var hasEbook: Bool { ebookFormat != nil || ebookFile != nil }
}

public struct CollapsedSeries: Codable, Sendable, Hashable {
  public var id: String
  public var name: String?
  public var numBooks: Int?
  public var libraryItemIds: [String]?
  public var sequence: String?
}

public struct LibraryItem: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var libraryId: String?
  public var mediaType: String?
  public var addedAt: Double?
  public var updatedAt: Double?
  public var birthtimeMs: Double?
  public var mtimeMs: Double?
  public var isMissing: Bool?
  public var isInvalid: Bool?
  public var size: Int64?
  public var numFiles: Int?
  public var media: BookMedia
  public var collapsedSeries: CollapsedSeries?
  public var libraryFiles: [LibraryFile]?
  /// Only on /api/me/items-in-progress.
  public var progressLastUpdate: Double?

  public init(id: String, media: BookMedia) {
    self.id = id
    self.media = media
  }

  public var title: String { media.metadata.title ?? "" }
  public var authorLine: String {
    if let a = media.metadata.authorName, !a.isEmpty { return a }
    return (media.metadata.authors ?? []).map(\.name).joined(separator: ", ")
  }
  public var duration: Double { media.duration ?? 0 }
}

/// Lenient array: one malformed element never sinks the whole response.
public struct LossyArray<T: Decodable & Sendable>: Decodable, Sendable {
  public var elements: [T]
  public init(from decoder: Decoder) throws {
    var c = try decoder.unkeyedContainer()
    var out: [T] = []
    while !c.isAtEnd {
      if let v = try? c.decode(T.self) { out.append(v) } else { _ = try? c.decode(Discard.self) }
    }
    elements = out
  }
  private struct Discard: Decodable {}
}

public struct ItemsPage: Decodable, Sendable {
  public var results: [LibraryItem]
  public var total: Int
  enum CodingKeys: String, CodingKey { case results, total }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    results = (try c.decode(LossyArray<LibraryItem>.self, forKey: .results)).elements
    total = (try? c.decode(Int.self, forKey: .total)) ?? results.count
  }
}

public struct Series: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var name: String
  public var nameIgnorePrefix: String?
  public var description: String?
  public var addedAt: Double?
  public var updatedAt: Double?
  public var libraryId: String?
  public var books: [LibraryItem]?
  public var totalDuration: Double?
}

public struct SeriesPage: Decodable, Sendable {
  public var results: [Series]
  public var total: Int
  enum CodingKeys: String, CodingKey { case results, total }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    results = (try c.decode(LossyArray<Series>.self, forKey: .results)).elements
    total = (try? c.decode(Int.self, forKey: .total)) ?? results.count
  }
}

public struct ABSCollection: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var name: String
  public var description: String?
  public var libraryId: String?
  public var books: [LibraryItem]?
  public var lastUpdate: Double?
  public var createdAt: Double?
}

public struct PlaylistEntry: Codable, Sendable, Hashable {
  public var libraryItemId: String
  public var episodeId: String?
  public var libraryItem: LibraryItem?
}

public struct Playlist: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var name: String
  public var description: String?
  public var userId: String?
  public var libraryId: String?
  public var items: [PlaylistEntry]?
  public var lastUpdate: Double?
}

public struct ResultsPage<T: Decodable & Sendable>: Decodable, Sendable {
  public var results: [T]
  public var total: Int
  enum CodingKeys: String, CodingKey { case results, total }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    results = (try c.decode(LossyArray<T>.self, forKey: .results)).elements
    total = (try? c.decode(Int.self, forKey: .total)) ?? results.count
  }
}

public struct Author: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var name: String
  public var description: String?
  public var imagePath: String?
  public var numBooks: Int?
  public var lastFirst: String?
  public var addedAt: Double?
  public var updatedAt: Double?
  public var libraryItems: [LibraryItem]?
  public var series: [AuthorSeries]?
}

public struct AuthorSeries: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var name: String
  public var items: [LibraryItem]?
}

public struct AuthorsResponse: Decodable, Sendable {
  public var authors: [Author]
  enum CodingKeys: String, CodingKey { case authors, results }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let a = try? c.decode(LossyArray<Author>.self, forKey: .authors) {
      authors = a.elements
    } else {
      authors = (try c.decode(LossyArray<Author>.self, forKey: .results)).elements
    }
  }
}

public struct Narrator: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var name: String
  public var numBooks: Int?
}

public struct NarratorsResponse: Codable, Sendable { public var narrators: [Narrator] }

public struct FilterData: Codable, Sendable {
  public var authors: [NamedRef]?
  public var genres: [String]?
  public var tags: [String]?
  public var series: [NamedRef]?
  public var narrators: [String]?
  public var languages: [String]?
  public var publishers: [String]?
  public var publishedDecades: [String]?
  public var numIssues: Int?
}

public struct LibraryWithFilterData: Decodable, Sendable {
  public var library: Library
  public var filterdata: FilterData?
  public var numUserPlaylists: Int?
}

/// One home-page shelf. `entities` depend on `type`.
public struct Shelf: Decodable, Sendable, Identifiable {
  public enum Entities: Sendable {
    case books([LibraryItem])
    case series([Series])
    case authors([Author])
    case unsupported
  }
  public var id: String
  public var label: String
  public var labelStringKey: String?
  public var type: String
  public var entities: Entities
  public var total: Int?

  enum CodingKeys: String, CodingKey { case id, label, labelStringKey, type, entities, total }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    label = (try? c.decode(String.self, forKey: .label)) ?? id
    labelStringKey = try? c.decodeIfPresent(String.self, forKey: .labelStringKey)
    type = (try? c.decode(String.self, forKey: .type)) ?? "book"
    total = try? c.decodeIfPresent(Int.self, forKey: .total)
    switch type {
    case "book", "episode", "podcast":
      entities = .books(
        (try? c.decode(LossyArray<LibraryItem>.self, forKey: .entities))?.elements ?? [])
    case "series":
      entities = .series(
        (try? c.decode(LossyArray<Series>.self, forKey: .entities))?.elements ?? [])
    case "authors":
      entities = .authors(
        (try? c.decode(LossyArray<Author>.self, forKey: .entities))?.elements ?? [])
    default:
      entities = .unsupported
    }
  }

  public var isEmpty: Bool {
    switch entities {
    case .books(let b): return b.isEmpty
    case .series(let s): return s.isEmpty
    case .authors(let a): return a.isEmpty
    case .unsupported: return true
    }
  }
}

public struct DeviceInfo: Codable, Sendable, Hashable {
  public var clientName: String
  public var deviceId: String
  public var clientVersion: String
  public var manufacturer: String
  public var model: String
  public var sdkVersion: String?

  public init(
    clientName: String = "Abs macOS", deviceId: String, clientVersion: String,
    manufacturer: String = "Apple", model: String, sdkVersion: String? = nil
  ) {
    self.clientName = clientName
    self.deviceId = deviceId
    self.clientVersion = clientVersion
    self.manufacturer = manufacturer
    self.model = model
    self.sdkVersion = sdkVersion
  }
}

public struct PlayRequest: Encodable, Sendable {
  public var deviceInfo: DeviceInfo
  public var supportedMimeTypes: [String]
  public var mediaPlayer: String
  public var forceDirectPlay: Bool
  public var forceTranscode: Bool

  public init(
    deviceInfo: DeviceInfo, supportedMimeTypes: [String], mediaPlayer: String = "AVPlayer",
    forceDirectPlay: Bool = false, forceTranscode: Bool = false
  ) {
    self.deviceInfo = deviceInfo
    self.supportedMimeTypes = supportedMimeTypes
    self.mediaPlayer = mediaPlayer
    self.forceDirectPlay = forceDirectPlay
    self.forceTranscode = forceTranscode
  }
}

public struct PlaybackSession: Codable, Sendable, Identifiable {
  public var id: String
  public var libraryItemId: String
  public var episodeId: String?
  public var mediaType: String?
  public var displayTitle: String?
  public var displayAuthor: String?
  public var duration: Double
  public var playMethod: Int?
  public var currentTime: Double
  public var startTime: Double?
  public var chapters: [Chapter]
  public var audioTracks: [AudioTrack]
  public var libraryItem: LibraryItem?
  public var mediaMetadata: BookMetadata?
  public var timeListening: Double?
  public var startedAt: Double?
  public var updatedAt: Double?
  public var coverPath: String?

  enum CodingKeys: String, CodingKey {
    case id, libraryItemId, episodeId, mediaType, displayTitle, displayAuthor, duration, playMethod,
      currentTime, startTime, chapters, audioTracks, libraryItem, mediaMetadata, timeListening,
      startedAt, updatedAt, coverPath
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    libraryItemId = (try? c.decode(String.self, forKey: .libraryItemId)) ?? ""
    episodeId = try? c.decodeIfPresent(String.self, forKey: .episodeId)
    mediaType = try? c.decodeIfPresent(String.self, forKey: .mediaType)
    displayTitle = try? c.decodeIfPresent(String.self, forKey: .displayTitle)
    displayAuthor = try? c.decodeIfPresent(String.self, forKey: .displayAuthor)
    duration = (try? c.decode(Double.self, forKey: .duration)) ?? 0
    playMethod = try? c.decodeIfPresent(Int.self, forKey: .playMethod)
    currentTime = (try? c.decode(Double.self, forKey: .currentTime)) ?? 0
    startTime = try? c.decodeIfPresent(Double.self, forKey: .startTime)
    chapters = (try? c.decode(LossyArray<Chapter>.self, forKey: .chapters))?.elements ?? []
    audioTracks = (try? c.decode(LossyArray<AudioTrack>.self, forKey: .audioTracks))?.elements ?? []
    libraryItem = try? c.decodeIfPresent(LibraryItem.self, forKey: .libraryItem)
    mediaMetadata = try? c.decodeIfPresent(BookMetadata.self, forKey: .mediaMetadata)
    timeListening = try? c.decodeIfPresent(Double.self, forKey: .timeListening)
    startedAt = try? c.decodeIfPresent(Double.self, forKey: .startedAt)
    updatedAt = try? c.decodeIfPresent(Double.self, forKey: .updatedAt)
    coverPath = try? c.decodeIfPresent(String.self, forKey: .coverPath)
  }
}

public struct SyncBody: Encodable, Sendable {
  public var currentTime: Double
  public var timeListened: Double
  public var duration: Double?
  public init(currentTime: Double, timeListened: Double, duration: Double? = nil) {
    self.currentTime = currentTime
    self.timeListened = timeListened
    self.duration = duration
  }
}

public struct ListeningSessionSummary: Codable, Sendable, Identifiable, Hashable {
  public var id: String
  public var libraryItemId: String?
  public var displayTitle: String?
  public var displayAuthor: String?
  public var mediaMetadata: BookMetadata?
  public var timeListening: Double?
  public var updatedAt: Double?
  public var startedAt: Double?
  public var currentTime: Double?
  public var duration: Double?
}

public struct ListeningStats: Decodable, Sendable {
  public var totalTime: Double
  public var today: Double
  public var days: [String: Double]
  public var dayOfWeek: [String: Double]
  public var recentSessions: [ListeningSessionSummary]

  enum CodingKeys: String, CodingKey { case totalTime, today, days, dayOfWeek, recentSessions }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    totalTime = (try? c.decode(Double.self, forKey: .totalTime)) ?? 0
    today = (try? c.decode(Double.self, forKey: .today)) ?? 0
    days = (try? c.decode([String: Double].self, forKey: .days)) ?? [:]
    dayOfWeek = (try? c.decode([String: Double].self, forKey: .dayOfWeek)) ?? [:]
    recentSessions =
      (try? c.decode(LossyArray<ListeningSessionSummary>.self, forKey: .recentSessions))?.elements
      ?? []
  }
}

public struct SearchResults: Decodable, Sendable {
  public struct BookHit: Decodable, Sendable { public var libraryItem: LibraryItem }
  public struct SeriesHit: Decodable, Sendable {
    public var series: Series
    public var books: [LibraryItem]?
  }
  public struct NameCount: Decodable, Sendable {
    public var name: String
    public var numBooks: Int?
    public var numItems: Int?
  }
  public var book: [BookHit]
  public var series: [SeriesHit]
  public var authors: [Author]
  public var narrators: [NameCount]
  public var tags: [NameCount]
  public var genres: [NameCount]

  enum CodingKeys: String, CodingKey { case book, series, authors, narrators, tags, genres }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    book = (try? c.decode(LossyArray<BookHit>.self, forKey: .book))?.elements ?? []
    series = (try? c.decode(LossyArray<SeriesHit>.self, forKey: .series))?.elements ?? []
    authors = (try? c.decode(LossyArray<Author>.self, forKey: .authors))?.elements ?? []
    narrators = (try? c.decode(LossyArray<NameCount>.self, forKey: .narrators))?.elements ?? []
    tags = (try? c.decode(LossyArray<NameCount>.self, forKey: .tags))?.elements ?? []
    genres = (try? c.decode(LossyArray<NameCount>.self, forKey: .genres))?.elements ?? []
  }
}

public struct BookmarksResponse: Codable, Sendable { public var bookmarks: [Bookmark] }
