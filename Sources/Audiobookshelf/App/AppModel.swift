import ABSCore
import AppKit
import Foundation
import Observation

/// Pages of the main window (the web client's routes).
enum Route: Hashable {
  case home, library, series, collections, playlists, authors, narrators, stats, downloads, account
  case search(String)
  case item(String)
  case author(String)
  case seriesDetail(String)
  case collection(String)
  case playlist(String)
  /// Library grid with a preset filter (e.g. from a genre/narrator link).
  case filtered(String)
}

struct Toast: Identifiable, Equatable {
  enum Kind { case info, success, warning, error }
  let id = UUID()
  var text: String
  var kind: Kind
  var duration: Double = 4
}

@MainActor @Observable
final class AppModel {
  static let shared = AppModel()

  var account: Account?
  var user: User?
  var serverSettings: ServerSettings?
  var libraries: [Library] = []
  var currentLibraryId: String? {
    didSet {
      if let currentLibraryId {
        UserDefaults.standard.set(currentLibraryId, forKey: "currentLibraryId")
      }
    }
  }
  var numUserPlaylists = 0
  var filterData: FilterData?

  // Navigation (browser-like history).
  var route: Route = .home
  private(set) var back: [Route] = []
  private(set) var forward: [Route] = []

  var toasts: [Toast] = []
  var isOnline = true
  var onLAN = false
  var socketConnected = false
  var searchText = ""

  let settings = AppSettings.shared
  private(set) var api: APIClient
  private(set) var router: ServerRouter?
  let socket = SocketClient()
  private var socketHandlers: [(String, Data?) -> Void] = []
  /// Refreshes the token pair daily so the 30-day sliding refresh token never
  /// lapses while the app runs in the background with nothing to fetch.
  private var keepAliveTimer: Timer?
  private var refreshingSession = false
  private var loggingOut = false
  private var expiring = false
  private var lastFullRefresh = Date.distantPast

  var isLoggedIn: Bool { account != nil && user != nil }
  var currentLibrary: Library? { libraries.first { $0.id == currentLibraryId } }

  private init() {
    api = APIClient(
      baseURL: nil, tokens: TokenStore(access: nil, refresh: nil, persist: { _, _ in }))
  }

  // MARK: Session bootstrap

  /// Restore the saved account and paint from cache immediately; refresh in the background.
  func restore() async {
    guard let acc = Account.load() else { return }
    configure(acc)
    if let cachedUser = DiskCache.shared.load(User.self, "user") { user = cachedUser }
    if let libs = DiskCache.shared.load([Library].self, "libraries") { libraries = libs }
    if let ss = DiskCache.shared.load(ServerSettings.self, "serverSettings") { serverSettings = ss }
    currentLibraryId =
      UserDefaults.standard.string(forKey: "currentLibraryId") ?? libraries.first?.id
    loadCachedFilterData()
    if user == nil {
      // Nothing cached yet: must reach the server before showing the app.
      await refreshSession()
    } else {
      Task { await refreshSession() }
    }
  }

  func configure(_ acc: Account) {
    account = acc
    DiskCache.shared.scopeKey = "\(acc.serverURL.host ?? "server")-\(acc.userId)"
    // The server rotates the refresh token and destroys the session if an old
    // one is reused after a short grace window, so the new pair is written to
    // the Keychain synchronously, before anything else can use it.
    let uid = acc.userId
    let tokens = TokenStore(access: acc.accessToken, refresh: acc.refreshToken) { a, r in
      // A late refresh from a previous account's client must not land here.
      guard var stored = Account.load(), stored.userId == uid else { return }
      stored.accessToken = a
      stored.refreshToken = r
      stored.save()
      Task { @MainActor in
        guard AppModel.shared.account?.userId == stored.userId else { return }
        AppModel.shared.account = stored
      }
    }
    let client = APIClient(baseURL: acc.serverURL, tokens: tokens)
    client.onUnauthorized = { Task { @MainActor in AppModel.shared.sessionExpired() } }
    client.relogin = { [weak client] in
      guard let client else { throw APIError.unauthorized }
      let creds: Credentials
      switch Credentials.lookup() {
      case .found(let c): creds = c
      case .missing: throw APIError.unauthorized
      case .unavailable(let status): throw APIError.network("Keychain unavailable (\(status))")
      }
      let r = try await client.login(username: creds.username, password: creds.password)
      guard let a = r.user.accessToken, let rt = r.user.refreshToken else {
        throw APIError.unauthorized
      }
      return TokenPair(access: a, refresh: rt)
    }
    api = client
    keepAliveTimer?.invalidate()
    let t = Timer(timeInterval: 24 * 3600, repeats: true) { _ in
      Task { @MainActor in _ = try? await AppModel.shared.api.refreshAccessToken() }
    }
    RunLoop.main.add(t, forMode: .common)
    keepAliveTimer = t
    let r = ServerRouter(publicURL: acc.serverURL, localURL: acc.localURL)
    r.onChange = { choice in
      Task { @MainActor in AppModel.shared.routeChanged(choice) }
    }
    router = r
    r.start()
    Task {
      let c = await r.probe()
      self.routeChanged(c)
    }
  }

  private func routeChanged(_ c: ServerRouter.Choice) {
    guard account != nil else { return }
    api.baseURL = c.api
    onLAN = c.onLAN
    if isOnline && socket.isStarted {
      socket.switchBase(c.api)
    } else {
      // Launched offline (or the socket never started): the network is back.
      Task {
        await refreshSession()
        if isOnline { LibraryStore.shared.refreshAll() }
      }
    }
  }

  var streamBase: URL {
    router?.choice.stream ?? account?.serverURL ?? URL(string: "http://localhost")!
  }

  /// /api/authorize → user, settings; then libraries.
  func refreshSession() async {
    guard account != nil, !refreshingSession else { return }
    refreshingSession = true
    defer { refreshingSession = false }
    do {
      let r = try await api.authorize()
      apply(login: r)
      isOnline = true
      let libs = try await api.libraries()
      libraries = libs
      DiskCache.shared.save(libs, "libraries")
      if currentLibraryId == nil || !libs.contains(where: { $0.id == currentLibraryId }) {
        currentLibraryId = r.userDefaultLibraryId ?? libs.first?.id
        loadCachedFilterData()
        LibraryStore.shared.libraryChanged()
      }
      await refreshLibraryMeta()
      startSocket()
    } catch APIError.unauthorized {
      sessionExpired()
    } catch {
      isOnline = false
    }
  }

  func refreshLibraryMeta() async {
    guard let id = currentLibraryId else { return }
    if let lf = try? await api.library(id), id == currentLibraryId {
      filterData = lf.filterdata
      if let fd = lf.filterdata { DiskCache.shared.save(fd, "filterdata-\(id)") }
      numUserPlaylists = lf.numUserPlaylists ?? 0
      if let i = libraries.firstIndex(where: { $0.id == id }) { libraries[i] = lf.library }
    }
  }

  /// Filter data (author and series names) is cached so series and author
  /// pages work offline and right after a library switch.
  private func loadCachedFilterData() {
    guard let id = currentLibraryId else { return }
    filterData = DiskCache.shared.load(FilterData.self, "filterdata-\(id)")
  }

  /// Every user payload goes through here: tokens (including the server's
  /// non-expiring legacy `token`) are never kept in memory or on disk.
  func setUser(_ incoming: User) {
    var u = incoming
    u.accessToken = nil
    u.refreshToken = nil
    u.token = nil
    user = u
    DiskCache.shared.save(u, "user")
  }

  func apply(login r: LoginResponse) {
    setUser(r.user)
    if let ss = r.serverSettings {
      serverSettings = ss
      DiskCache.shared.save(ss, "serverSettings")
    }
  }

  func login(server: URL, local: URL?, username: String, password: String) async throws {
    let deviceKey = "deviceId.\(server.host ?? "server").\(username.lowercased())"
    let deviceId =
      UserDefaults.standard.string(forKey: deviceKey)
      ?? {
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: deviceKey)
        return id
      }()
    // Log in against whichever address answers.
    let probeRouter = ServerRouter(publicURL: server, localURL: local)
    let choice = await probeRouter.probe()
    let client = APIClient(
      baseURL: choice.api, tokens: TokenStore(access: nil, refresh: nil, persist: { _, _ in }))
    let r = try await client.login(username: username, password: password)
    let acc = Account(
      serverURL: server, localURL: local, username: r.user.username, userId: r.user.id,
      accessToken: r.user.accessToken, refreshToken: r.user.refreshToken, deviceId: deviceId)
    acc.save()
    Credentials(username: username, password: password).save()
    UserDefaults.standard.set(username, forKey: "lastUsername")
    configure(acc)
    apply(login: r)
    currentLibraryId = r.userDefaultLibraryId
    await refreshSession()
  }

  func logout(allDevices: Bool = false) async {
    guard !loggingOut else { return }
    loggingOut = true
    defer { loggingOut = false }
    await PlayerModel.shared.close()
    try? await api.logout(allDevices: allDevices)
    socket.onStateChange = nil
    socket.disconnect()
    router?.onChange = nil
    router?.stop()
    router = nil
    Account.clear()
    Credentials.clear()
    keepAliveTimer?.invalidate()
    keepAliveTimer = nil
    DiskCache.shared.clearAll()
    DiskCache.shared.scopeKey = "anon"
    LibraryStore.shared.reset()
    AppDelegate.shared?.resetServices()
    account = nil
    user = nil
    serverSettings = nil
    libraries = []
    currentLibraryId = nil
    UserDefaults.standard.removeObject(forKey: "currentLibraryId")
    filterData = nil
    numUserPlaylists = 0
    searchText = ""
    socketConnected = false
    isOnline = true
    route = .home
    back = []
    forward = []
    api = APIClient(
      baseURL: nil, tokens: TokenStore(access: nil, refresh: nil, persist: { _, _ in }))
  }

  /// Only reached when the saved password itself is rejected.
  private func sessionExpired() {
    guard account != nil, !loggingOut, !expiring else { return }
    expiring = true
    toast("Your session expired. Please log in again.", .warning)
    Task {
      await logout()
      expiring = false
    }
  }

  // MARK: Socket

  private func startSocket() {
    guard socket.isAuthenticated == false else { return }
    socket.onStateChange = { connected, reconnected in
      Task { @MainActor in
        AppModel.shared.socketConnected = connected
        if connected && reconnected { await AppModel.shared.afterReconnect() }
      }
    }
    socket.freshToken = { try? await AppModel.shared.api.refreshAccessToken() }
    socket.connect(
      baseURL: api.baseURL ?? streamBase, token: { await AppModel.shared.api.tokens.access }
    ) { name, payload in
      Task { @MainActor in AppModel.shared.handleSocket(name, payload) }
    }
  }

  func onSocket(_ handler: @escaping (String, Data?) -> Void) { socketHandlers.append(handler) }

  private func handleSocket(_ name: String, _ payload: Data?) {
    switch name {
    case "user_updated":
      if let payload, let u = try? JSONDecoder().decode(User.self, from: payload), u.id == user?.id
      {
        setUser(u)
      }
    case "admin_message":
      if let payload, let s = try? JSONDecoder().decode(String.self, from: payload) {
        toast(s, .info)
      }
    default: break
    }
    for h in socketHandlers { h(name, payload) }
  }

  private func afterReconnect() async {
    if let u = try? await api.me() { setUser(u) }
    // A LAN/public switch also reconnects; skip the full refetch if one just ran.
    if Date().timeIntervalSince(lastFullRefresh) > 60 {
      lastFullRefresh = Date()
      LibraryStore.shared.refreshAll()
    }
    await PlayerModel.shared.reconcileWithServer()
  }

  // MARK: Progress helpers

  func progress(for itemId: String) -> MediaProgress? {
    user?.mediaProgress?.first { $0.libraryItemId == itemId && $0.episodeId == nil }
  }

  func updateLocalProgress(_ p: MediaProgress) {
    guard var u = user else { return }
    var list = u.mediaProgress ?? []
    if let i = list.firstIndex(where: {
      $0.libraryItemId == p.libraryItemId && $0.episodeId == p.episodeId
    }) {
      list[i] = p
    } else {
      list.append(p)
    }
    u.mediaProgress = list
    user = u
  }

  func bookmarks(for itemId: String) -> [Bookmark] {
    (user?.bookmarks ?? []).filter { $0.libraryItemId == itemId }.sorted { $0.time < $1.time }
  }

  // MARK: Navigation

  func go(_ r: Route) {
    guard r != route else { return }
    back.append(route)
    if back.count > 100 { back.removeFirst() }
    forward.removeAll()
    route = r
  }

  func goBack() {
    guard let r = back.popLast() else { return }
    forward.append(route)
    route = r
  }

  func goForward() {
    guard let r = forward.popLast() else { return }
    back.append(route)
    route = r
  }

  var canGoBack: Bool { !back.isEmpty }
  var canGoForward: Bool { !forward.isEmpty }

  func selectLibrary(_ id: String) {
    guard id != currentLibraryId else { return }
    currentLibraryId = id
    loadCachedFilterData()
    // Routes do not carry a library, so history from the old one is dropped.
    back.removeAll()
    forward.removeAll()
    if case .item = route {} else if case .author = route {} else { route = .home }
    Task { await refreshLibraryMeta() }
    LibraryStore.shared.libraryChanged()
  }

  // MARK: Toasts

  func toast(_ text: String, _ kind: Toast.Kind = .info, duration: Double = 4) {
    let t = Toast(text: text, kind: kind, duration: duration)
    toasts.append(t)
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
      self?.toasts.removeAll { $0.id == t.id }
    }
  }

  // MARK: URLs

  func coverURL(_ item: LibraryItem, width: Int = 400) -> URL? {
    guard item.media.coverPath != nil else { return nil }
    return coverURL(itemId: item.id, updatedAt: item.updatedAt, width: width)
  }

  /// Same request as the web (width 400, no format): hits the server's resize cache.
  func coverURL(itemId: String, updatedAt: Double?, width: Int = 400) -> URL? {
    guard let base = api.baseURL ?? account?.serverURL else { return nil }
    var c = URLComponents(
      url: base.appendingPathComponent("api/items/\(itemId)/cover"), resolvingAgainstBaseURL: false)!
    var q = [URLQueryItem(name: "ts", value: String(Int(updatedAt ?? 0)))]
    if width != 400 { q.append(URLQueryItem(name: "width", value: String(width))) }
    c.queryItems = q
    return c.url
  }

  func authorImageURL(_ a: Author, width: Int = 400) -> URL? {
    guard a.imagePath != nil, let base = api.baseURL ?? account?.serverURL else { return nil }
    var c = URLComponents(
      url: base.appendingPathComponent("api/authors/\(a.id)/image"), resolvingAgainstBaseURL: false)!
    c.queryItems = [URLQueryItem(name: "ts", value: String(Int(a.updatedAt ?? 0)))]
    return c.url
  }

  var webURL: URL? { account?.serverURL }
}
