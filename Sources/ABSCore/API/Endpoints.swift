import Foundation

/// Typed wrappers for the endpoints the client uses (server/routers/ApiRouter.js).
extension APIClient {
  // MARK: Auth

  public func status() async throws -> ServerStatus {
    try await get(ServerStatus.self, "/status", timeout: 6)
  }

  public func login(username: String, password: String) async throws -> LoginResponse {
    let body = try JSONEncoder().encode(["username": username, "password": password])
    let (d, _) = try await data(
      "POST", "/login", body: body, headers: ["x-return-tokens": "true"],
      authorized: false, timeout: 15, retryOn401: false)
    return try decode(LoginResponse.self, d)
  }

  /// POST /api/authorize: the login payload for the current token, no new tokens.
  public func authorize() async throws -> LoginResponse {
    let (d, _) = try await data("POST", "/api/authorize", body: Data("{}".utf8))
    return try decode(LoginResponse.self, d)
  }

  public func logout(allDevices: Bool = false) async throws {
    let refresh = await tokens.refresh ?? ""
    _ = try await data(
      "POST", "/logout", query: allDevices ? ["allDevices": "1"] : [:], body: Data("{}".utf8),
      headers: ["x-refresh-token": refresh], retryOn401: false)
  }

  public func me() async throws -> User { try await get(User.self, "/api/me") }

  // MARK: Libraries

  public func libraries() async throws -> [Library] {
    try await get(LibrariesResponse.self, "/api/libraries").libraries.sorted {
      ($0.displayOrder ?? 0) < ($1.displayOrder ?? 0)
    }
  }

  public func library(_ id: String) async throws -> LibraryWithFilterData {
    try await get(
      LibraryWithFilterData.self, "/api/libraries/\(id)", query: ["include": "filterdata"])
  }

  public func personalized(_ libraryId: String, limit: Int = 10) async throws -> [Shelf] {
    try await get(
      LossyArray<Shelf>.self, "/api/libraries/\(libraryId)/personalized",
      query: ["include": "rssfeed,numEpisodesIncomplete,share", "limit": String(limit)]
    ).elements
  }

  /// `filter` is already encoded (`group.<b64>`), so it goes in the raw query.
  public func items(
    _ libraryId: String, limit: Int = 0, page: Int = 0, sort: String? = nil, desc: Bool = false,
    filter: String? = nil, collapseSeries: Bool = false, minified: Bool = true
  ) async throws -> ItemsPage {
    var q: [String: String] = [
      "limit": String(limit), "page": String(page), "minified": minified ? "1" : "0",
    ]
    if let sort {
      q["sort"] = sort
      q["desc"] = desc ? "1" : "0"
    }
    if collapseSeries { q["collapseseries"] = "1" }
    return try await get(
      ItemsPage.self, "/api/libraries/\(libraryId)/items", query: q,
      rawQuery: filter.map { "filter=\($0)" })
  }

  public func series(
    _ libraryId: String, sort: String = "name", desc: Bool = false, filter: String? = nil,
    limit: Int = 0, page: Int = 0
  ) async throws -> SeriesPage {
    try await get(
      SeriesPage.self, "/api/libraries/\(libraryId)/series",
      query: [
        "sort": sort, "desc": desc ? "1" : "0", "limit": String(limit), "page": String(page),
        "minified": "1", "include": "rssfeed",
      ],
      rawQuery: filter.map { "filter=\($0)" })
  }

  public func seriesDetail(_ libraryId: String, _ seriesId: String) async throws -> Series {
    try await get(
      Series.self, "/api/libraries/\(libraryId)/series/\(seriesId)",
      query: ["include": "progress,rssfeed"])
  }

  public func collections(_ libraryId: String) async throws -> [ABSCollection] {
    try await get(
      ResultsPage<ABSCollection>.self, "/api/libraries/\(libraryId)/collections", query: ["limit": "0"]
    ).results
  }

  public func collection(_ id: String) async throws -> ABSCollection {
    try await get(ABSCollection.self, "/api/collections/\(id)")
  }

  public func playlists(_ libraryId: String) async throws -> [Playlist] {
    try await get(
      ResultsPage<Playlist>.self, "/api/libraries/\(libraryId)/playlists", query: ["limit": "0"]
    ).results
  }

  public func playlist(_ id: String) async throws -> Playlist {
    try await get(Playlist.self, "/api/playlists/\(id)")
  }

  public func authors(_ libraryId: String) async throws -> [Author] {
    try await get(AuthorsResponse.self, "/api/libraries/\(libraryId)/authors").authors
  }

  public func author(_ id: String) async throws -> Author {
    try await get(Author.self, "/api/authors/\(id)", query: ["include": "items,series"])
  }

  public func narrators(_ libraryId: String) async throws -> [Narrator] {
    try await get(NarratorsResponse.self, "/api/libraries/\(libraryId)/narrators").narrators
  }

  public func search(_ libraryId: String, q: String, limit: Int = 12) async throws -> SearchResults
  {
    try await get(
      SearchResults.self, "/api/libraries/\(libraryId)/search",
      query: ["q": q, "limit": String(limit)])
  }

  // MARK: Items

  public func item(_ id: String) async throws -> LibraryItem {
    try await get(
      LibraryItem.self, "/api/items/\(id)", query: ["expanded": "1", "include": "progress"])
  }

  public func itemsInProgress(limit: Int = 25) async throws -> [LibraryItem] {
    struct R: Decodable { var libraryItems: LossyArray<LibraryItem> }
    return try await get(R.self, "/api/me/items-in-progress", query: ["limit": String(limit)])
      .libraryItems.elements
  }

  public func listeningStats() async throws -> ListeningStats {
    try await get(ListeningStats.self, "/api/me/listening-stats")
  }

  // MARK: Playback

  public func play(itemId: String, episodeId: String? = nil, request: PlayRequest) async throws
    -> PlaybackSession
  {
    let path = episodeId.map { "/api/items/\(itemId)/play/\($0)" } ?? "/api/items/\(itemId)/play"
    return try await send(PlaybackSession.self, "POST", path, json: request, timeout: 20)
  }

  public func syncSession(_ id: String, _ body: SyncBody) async throws {
    try await sendVoid("POST", "/api/session/\(id)/sync", json: body, timeout: 9)
  }

  public func closeSession(_ id: String, _ body: SyncBody?) async throws {
    if let body {
      try await sendVoid("POST", "/api/session/\(id)/close", json: body, timeout: 6)
    } else {
      _ = try await data("POST", "/api/session/\(id)/close", timeout: 6)
    }
  }

  public func progress(itemId: String) async throws -> MediaProgress {
    try await get(MediaProgress.self, "/api/me/progress/\(itemId)", timeout: 7)
  }

  public func updateProgress(itemId: String, _ fields: [String: JSONValue]) async throws {
    try await sendVoid("PATCH", "/api/me/progress/\(itemId)", json: fields)
  }

  public func removeProgress(progressId: String) async throws {
    _ = try await data("DELETE", "/api/me/progress/\(progressId)")
  }

  public func hideFromContinueListening(progressId: String) async throws {
    _ = try await data("GET", "/api/me/progress/\(progressId)/remove-from-continue-listening")
  }

  // MARK: Bookmarks

  public func createBookmark(itemId: String, time: Double, title: String) async throws -> Bookmark {
    try await send(
      Bookmark.self, "POST", "/api/me/item/\(itemId)/bookmark",
      json: ["time": JSONValue.number(time), "title": .string(title)])
  }

  public func updateBookmark(itemId: String, _ b: Bookmark) async throws -> Bookmark {
    try await send(Bookmark.self, "PATCH", "/api/me/item/\(itemId)/bookmark", json: b)
  }

  public func deleteBookmark(itemId: String, time: Double) async throws {
    _ = try await data("DELETE", "/api/me/item/\(itemId)/bookmark/\(Self.exactNumber(time))")
  }

  /// The server matches bookmark times exactly, so no rounding.
  static func exactNumber(_ v: Double) -> String {
    v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(v)
  }

  // MARK: Collections & playlists

  public func addToCollection(_ collectionId: String, itemId: String) async throws {
    try await sendVoid("POST", "/api/collections/\(collectionId)/book", json: ["id": itemId])
  }

  public func removeFromCollection(_ collectionId: String, itemId: String) async throws {
    _ = try await data("DELETE", "/api/collections/\(collectionId)/book/\(itemId)")
  }

  public func createCollection(libraryId: String, name: String, books: [String]) async throws
    -> ABSCollection
  {
    try await send(
      ABSCollection.self, "POST", "/api/collections",
      json: [
        "libraryId": JSONValue.string(libraryId), "name": .string(name),
        "books": .array(books.map { .string($0) }),
      ])
  }

  public func updateCollection(_ id: String, _ fields: [String: JSONValue]) async throws
    -> ABSCollection
  {
    try await send(ABSCollection.self, "PATCH", "/api/collections/\(id)", json: fields)
  }

  public func deleteCollection(_ id: String) async throws {
    _ = try await data("DELETE", "/api/collections/\(id)")
  }

  public func createPlaylist(libraryId: String, name: String, itemIds: [String]) async throws
    -> Playlist
  {
    try await send(
      Playlist.self, "POST", "/api/playlists",
      json: [
        "libraryId": JSONValue.string(libraryId), "name": .string(name),
        "items": .array(itemIds.map { .object(["libraryItemId": .string($0)]) }),
      ])
  }

  public func addToPlaylist(_ id: String, itemIds: [String]) async throws {
    try await sendVoid(
      "POST", "/api/playlists/\(id)/batch/add",
      json: ["items": JSONValue.array(itemIds.map { .object(["libraryItemId": .string($0)]) })])
  }

  public func removeFromPlaylist(_ id: String, itemIds: [String]) async throws {
    try await sendVoid(
      "POST", "/api/playlists/\(id)/batch/remove",
      json: ["items": JSONValue.array(itemIds.map { .object(["libraryItemId": .string($0)]) })])
  }

  public func updatePlaylist(_ id: String, _ fields: [String: JSONValue]) async throws -> Playlist {
    try await send(Playlist.self, "PATCH", "/api/playlists/\(id)", json: fields)
  }

  public func deletePlaylist(_ id: String) async throws {
    _ = try await data("DELETE", "/api/playlists/\(id)")
  }

  // MARK: Local sessions

  public func syncLocalSessions(_ body: LocalSessionsBody) async throws -> LocalSessionsResult {
    try await send(
      LocalSessionsResult.self, "POST", "/api/session/local-all", json: body, timeout: 20)
  }
}

/// Minimal JSON value for ad-hoc request bodies.
public enum JSONValue: Codable, Sendable, Hashable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case array([JSONValue])
  case object([String: JSONValue])
  case null

  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let s): try c.encode(s)
    case .number(let n): try c.encode(n)
    case .bool(let b): try c.encode(b)
    case .array(let a): try c.encode(a)
    case .object(let o): try c.encode(o)
    case .null: try c.encodeNil()
    }
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let b = try? c.decode(Bool.self) {
      self = .bool(b)
    } else if let n = try? c.decode(Double.self) {
      self = .number(n)
    } else if let s = try? c.decode(String.self) {
      self = .string(s)
    } else if let a = try? c.decode([JSONValue].self) {
      self = .array(a)
    } else {
      self = .object(try c.decode([String: JSONValue].self))
    }
  }
}
