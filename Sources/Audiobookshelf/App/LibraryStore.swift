import ABSCore
import Foundation
import Observation

/// Server data for the current library. Every list is painted from the disk
/// cache first, then refreshed; socket events trigger debounced refreshes.
@MainActor @Observable
final class LibraryStore {
  static let shared = LibraryStore()

  var shelves: [Shelf] = []
  var items: [LibraryItem] = []
  var itemsLoaded = false
  var series: [Series] = []
  var collections: [ABSCollection] = []
  var playlists: [Playlist] = []
  var authors: [Author] = []
  var narrators: [Narrator] = []
  var expanded: [String: LibraryItem] = [:]
  var loadingHome = false
  /// Bumped whenever items or progress change, so derived views recompute.
  var revision = 0

  private var app: AppModel { AppModel.shared }
  private var api: APIClient { app.api }
  private var libId: String? { app.currentLibraryId }
  private var refreshTask: Task<Void, Never>?
  private var socketHooked = false

  private init() {}

  func start() {
    loadCaches()
    refreshAll()
    guard !socketHooked else { return }
    socketHooked = true
    app.onSocket { [weak self] name, payload in self?.socketEvent(name, payload) }
  }

  func libraryChanged() {
    shelves = []
    items = []
    itemsLoaded = false
    series = []
    collections = []
    playlists = []
    authors = []
    narrators = []
    loadCaches()
    refreshAll()
  }

  private func key(_ name: String) -> String { "\(libId ?? "none")-\(name)" }

  private func loadCaches() {
    guard libId != nil else { return }
    if let d = DiskCache.shared.loadRaw(key("personalized")),
      let s = try? JSONDecoder().decode(LossyArray<Shelf>.self, from: d)
    {
      shelves = s.elements
    }
    if let d = DiskCache.shared.loadRaw(key("items")),
      let p = try? JSONDecoder().decode(ItemsPage.self, from: d)
    {
      items = p.results
      itemsLoaded = true
    }
    if let d = DiskCache.shared.loadRaw(key("series")),
      let p = try? JSONDecoder().decode(SeriesPage.self, from: d)
    {
      series = p.results
    }
    if let c = DiskCache.shared.load([ABSCollection].self, key("collections")) { collections = c }
    if let p = DiskCache.shared.load([Playlist].self, key("playlists")) { playlists = p }
    if let a = DiskCache.shared.load([Author].self, key("authors")) { authors = a }
    if let n = DiskCache.shared.load([Narrator].self, key("narrators")) { narrators = n }
    revision += 1
  }

  /// Logout: drop everything from the previous account.
  func reset() {
    refreshTask?.cancel()
    refreshTask = nil
    for t in debounces.values { t.cancel() }
    debounces = [:]
    shelves = []
    items = []
    itemsLoaded = false
    series = []
    collections = []
    playlists = []
    authors = []
    narrators = []
    expanded = [:]
    loadingHome = false
    revision += 1
  }

  func refreshAll() {
    // Set before the task hops, so Home never flashes "Library is empty!".
    if shelves.isEmpty, libId != nil { loadingHome = true }
    refreshTask?.cancel()
    refreshTask = Task {
      await refreshHome()
      await refreshItems()
      await refreshSeries()
      await refreshCollections()
      await refreshPlaylists()
      await refreshAuthors()
      await refreshNarrators()
    }
  }

  func refreshHome() async {
    guard let id = libId else { return }
    loadingHome = shelves.isEmpty
    defer { loadingHome = false }
    do {
      let (d, _) = try await api.data(
        "GET", "/api/libraries/\(id)/personalized",
        query: ["include": "rssfeed,numEpisodesIncomplete,share", "limit": "10"])
      let s = try JSONDecoder().decode(LossyArray<Shelf>.self, from: d)
      guard id == libId else { return }
      shelves = s.elements
      DiskCache.shared.saveRaw(d, key("personalized"))
    } catch {}
  }

  func refreshItems() async {
    guard let id = libId else { return }
    do {
      let (d, _) = try await api.data(
        "GET", "/api/libraries/\(id)/items", query: ["limit": "0", "minified": "1"],
        timeout: 60)
      let page = try JSONDecoder().decode(ItemsPage.self, from: d)
      guard id == libId else { return }
      items = page.results
      itemsLoaded = true
      revision += 1
      DiskCache.shared.saveRaw(d, key("items"))
    } catch {}
  }

  func refreshSeries() async {
    guard let id = libId else { return }
    do {
      let (d, _) = try await api.data(
        "GET", "/api/libraries/\(id)/series",
        query: ["limit": "0", "minified": "1", "sort": "name", "desc": "0"], timeout: 60)
      let page = try JSONDecoder().decode(SeriesPage.self, from: d)
      guard id == libId else { return }
      series = page.results
      DiskCache.shared.saveRaw(d, key("series"))
    } catch {}
  }

  func refreshCollections() async {
    guard let id = libId, let c = try? await api.collections(id), id == libId else { return }
    collections = c
    DiskCache.shared.save(c, key("collections"))
  }

  func refreshPlaylists() async {
    guard let id = libId, let p = try? await api.playlists(id), id == libId else { return }
    playlists = p
    app.numUserPlaylists = p.count
    DiskCache.shared.save(p, key("playlists"))
  }

  func refreshAuthors() async {
    guard let id = libId, let a = try? await api.authors(id), id == libId else { return }
    authors = a
    DiskCache.shared.save(a, key("authors"))
  }

  func refreshNarrators() async {
    guard let id = libId, let n = try? await api.narrators(id), id == libId else { return }
    narrators = n
    DiskCache.shared.save(n, key("narrators"))
  }

  /// Expanded item (chapters, tracks, files): memory → disk → server.
  func expandedItem(_ id: String, refresh: Bool = true) async -> LibraryItem? {
    if expanded[id] == nil, let cached = DiskCache.shared.load(LibraryItem.self, "item-\(id)") {
      expanded[id] = cached
    }
    if refresh || expanded[id] == nil, let fresh = try? await api.item(id) {
      expanded[id] = fresh
      DiskCache.shared.save(fresh, "item-\(id)")
    }
    return expanded[id]
  }

  func item(_ id: String) -> LibraryItem? {
    expanded[id] ?? items.first { $0.id == id }
  }

  // MARK: Socket

  private var debounces: [String: Task<Void, Never>] = [:]

  private func socketEvent(_ name: String, _ payload: Data?) {
    switch name {
    case "item_updated", "item_added", "item_removed", "items_updated", "items_added":
      if name == "item_updated", let payload,
        let it = try? JSONDecoder().decode(LibraryItem.self, from: payload)
      {
        if expanded[it.id] != nil { expanded[it.id] = it }
      }
      scheduleRefresh(home: true, items: true)
    case "user_updated":
      revision += 1
      scheduleRefresh(home: true, items: false)
    case "user_item_progress_updated":
      // Fires on every sync of our own session (10 s); the web only updates
      // local state here. PlayerModel applies the progress itself.
      revision += 1
    case "series_updated", "series_removed":
      debounced("series") { await self.refreshSeries() }
    case "collection_added", "collection_updated", "collection_removed":
      debounced("collections") { await self.refreshCollections() }
    case "playlist_added", "playlist_updated", "playlist_removed":
      debounced("playlists") { await self.refreshPlaylists() }
    case "author_updated", "author_removed":
      debounced("authors") { await self.refreshAuthors() }
    default: break
    }
  }

  private func scheduleRefresh(home: Bool, items: Bool) {
    if home { debounced("home") { await self.refreshHome() } }
    if items { debounced("items") { await self.refreshItems() } }
  }

  private func debounced(_ key: String, _ work: @escaping @MainActor () async -> Void) {
    debounces[key]?.cancel()
    debounces[key] = Task {
      try? await Task.sleep(nanoseconds: 800_000_000)
      guard !Task.isCancelled else { return }
      await work()
    }
  }
}
