import ABSCore
import AppKit
import SwiftUI

struct RootView: View {
  var app = AppModel.shared

  var body: some View {
    Group {
      if app.isLoggedIn {
        MainView()
      } else {
        LoginView()
      }
    }
    .environment(\.colorScheme, .dark)
    .preferredColorScheme(.dark)
    .task(id: app.isLoggedIn) { AppDelegate.shared?.startServicesIfNeeded() }
    .tint(Theme.accent)
  }
}

struct MainView: View {
  var app = AppModel.shared
  @Bindable var player = PlayerModel.shared

  var body: some View {
    VStack(spacing: 0) {
      AppBar().zIndex(2)
      HStack(spacing: 0) {
        SideRail()
        PageView(route: app.route)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      if player.hasItem {
        PlayerBar()
      }
    }
    .background(Theme.bg)
    .overlay {
      if player.showSleepTimer { SleepTimerModal() }
      if player.showChapters { ChaptersModal() }
      if player.showBookmarks { BookmarksModal() }
      if player.showQueue { QueueModal() }
      if player.showPlayerSettings { PlayerSettingsModal() }
    }
    .overlay(alignment: .bottomTrailing) {
      ToastStack(toasts: app.toasts)
        .padding(.bottom, player.hasItem ? Theme.playerHeight : 0)
    }
    .animation(
      .easeOut(duration: 0.15),
      value: player.showSleepTimer || player.showChapters || player.showBookmarks
        || player.showQueue || player.showPlayerSettings)
  }
}

/// components/app/Appbar.vue inside a real title bar: traffic lights on the
/// left, then logo, wordmark, library picker, search, and the right icons.
struct AppBar: View {
  var app = AppModel.shared
  @State private var searchFocused = false

  var body: some View {
    HStack(spacing: 0) {
      Color.clear.frame(width: 72)
      HStack(spacing: 2) {
        NavArrow(icon: "chevron_left", enabled: app.canGoBack) { app.goBack() }
        NavArrow(icon: "chevron_right", enabled: app.canGoForward) { app.goForward() }
      }
      .padding(.trailing, 12)
      Button {
        app.go(.home)
      } label: {
        HStack(spacing: 12) {
          AppLogo().frame(width: 32, height: 32)
          Text("audiobookshelf").font(Theme.sans(20)).foregroundStyle(.white)
        }
      }
      .buttonStyle(.plain)
      .padding(.trailing, 24)
      LibraryPicker()
        .padding(.trailing, 8)
      GlobalSearch()
      Spacer(minLength: 16)
      HStack(spacing: 20) {
        HoverIcon(icon: "equalizer", size: 24, color: .white) { app.go(.stats) }
          .help(L.s("HeaderYourStats"))
        if app.user?.isAdminOrUp == true {
          HoverIcon(icon: "settings", size: 24, color: .white) { openWebSettings() }
            .help("Server settings (opens in browser)")
        }
        AccountButton()
      }
      .padding(.trailing, 24)
    }
    .frame(height: Theme.appBarHeight)
    .background(Theme.primary)
    .gesture(WindowDragGesture())
    .allowsWindowActivationEvents(true)
  }

  private func openWebSettings() {
    if let u = app.webURL?.appendingPathComponent("config") { NSWorkspace.shared.open(u) }
  }
}

struct NavArrow: View {
  let icon: String
  let enabled: Bool
  let action: () -> Void
  var body: some View {
    HoverIcon(
      icon: icon, size: 24, color: enabled ? Theme.gray300 : Theme.gray600, disabled: !enabled,
      action: action)
  }
}

/// The ABS logo (static/icon.svg rendered into the app bundle as a PNG).
struct AppLogo: View {
  static let image: NSImage? = Bundle.main.resourceURL.flatMap {
    NSImage(contentsOf: $0.appendingPathComponent("images/logo.png"))
  }
  var body: some View {
    if let img = Self.image {
      Image(nsImage: img).resizable().interpolation(.high)
    } else {
      Circle().fill(Color(hex: 0xCD9D49))
    }
  }
}

/// ui/LibrariesDropdown.vue.
struct LibraryPicker: View {
  var app = AppModel.shared

  var body: some View {
    Menu {
      ForEach(app.libraries) { lib in
        Button {
          app.selectLibrary(lib.id)
        } label: {
          if lib.id == app.currentLibraryId {
            Label(lib.name, systemImage: "checkmark")
          } else {
            Text(lib.name)
          }
        }
      }
    } label: {
      HStack(spacing: 6) {
        Icon(libraryIcon(app.currentLibrary), size: 16)
        Text(app.currentLibrary?.name ?? "").font(Theme.sans(14)).lineLimit(1)
      }
      .foregroundStyle(Theme.gray400)
      .padding(.horizontal, 10)
      .frame(minWidth: 128, maxWidth: 208, minHeight: 32, maxHeight: 32, alignment: .leading)
      .background(Color.black.opacity(0.2))
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1)))
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
  }

  func libraryIcon(_ lib: Library?) -> String {
    switch lib?.icon {
    case "podcast", "microphone-1", "microphone-3": return "podcasts"
    case "books-1", "books-2", "book-1": return "menu_book"
    default: return "headphones"
    }
  }
}

/// Account button (w-32 × h-9): username + person icon, menu with Account / Log out.
struct AccountButton: View {
  var app = AppModel.shared
  var body: some View {
    Menu {
      Button("Account") { app.go(.account) }
      Button("Open in Browser") { if let u = app.webURL { NSWorkspace.shared.open(u) } }
      Divider()
      Button("Log out") { Task { await app.logout() } }
    } label: {
      HStack {
        Text(app.user?.username ?? "").font(Theme.sans(14)).lineLimit(1)
        Spacer(minLength: 4)
        Icon("person", size: 20).foregroundStyle(Theme.gray100)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .frame(width: 128, height: 36)
      .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.gray500))
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
  }
}

/// components/app/SideRail.vue: 80 px, 80×80 entries, yellow active bar.
struct SideRail: View {
  var app = AppModel.shared
  var downloads = DownloadManager.shared

  struct Entry: Identifiable {
    let id: String
    let label: String
    let icon: String
    let route: Route
    var iconSize: CGFloat = 24
  }

  var entries: [Entry] {
    var e: [Entry] = [
      Entry(id: "home", label: L.s("ButtonHome"), icon: "home", route: .home),
      Entry(id: "library", label: L.s("ButtonLibrary"), icon: "import_contacts", route: .library),
      Entry(id: "series", label: L.s("ButtonSeries"), icon: "view_column", route: .series),
      Entry(
        id: "collections", label: L.s("ButtonCollections"), icon: "collections_bookmark",
        route: .collections),
    ]
    if app.numUserPlaylists > 0 || !LibraryStore.shared.playlists.isEmpty {
      e.append(
        Entry(
          id: "playlists", label: L.s("ButtonPlaylists"), icon: "queue_music", route: .playlists,
          iconSize: 27))
    }
    e.append(Entry(id: "authors", label: L.s("ButtonAuthors"), icon: "groups", route: .authors))
    e.append(
      Entry(
        id: "narrators", label: L.s("LabelNarrators"), icon: "record_voice_over", route: .narrators)
    )
    if !downloads.downloadedIds.isEmpty {
      e.append(
        Entry(id: "downloads", label: "Downloaded", icon: "download_done", route: .downloads))
    }
    return e
  }

  var body: some View {
    VStack(spacing: 0) {
      ForEach(entries) { e in RailButton(entry: e, active: isActive(e.route)) }
      Spacer()
      VStack(spacing: 2) {
        Text("v\(app.serverSettings?.version ?? "2.36")").font(Theme.mono(12)).foregroundStyle(
          Theme.gray300
        ).underline()
        Text(app.onLAN ? "local" : (app.isOnline ? "remote" : "offline"))
          .font(Theme.sans(10).italic()).foregroundStyle(Theme.gray400)
      }
      .frame(height: 48)
    }
    .frame(width: Theme.railWidth)
    .background(Theme.bg)
    .shadow(color: Color(hex: 0x111111, opacity: 0.4), radius: 5, x: 5)
    .zIndex(1)
  }

  func isActive(_ r: Route) -> Bool {
    switch (app.route, r) {
    case (.home, .home), (.library, .library), (.filtered, .library), (.series, .series),
      (.seriesDetail, .series),
      (.collections, .collections), (.collection, .collections), (.playlists, .playlists),
      (.playlist, .playlists),
      (.authors, .authors), (.author, .authors), (.narrators, .narrators), (.downloads, .downloads):
      return true
    default: return false
    }
  }
}

private struct RailButton: View {
  let entry: SideRail.Entry
  let active: Bool
  @State private var hover = false
  var app = AppModel.shared

  var body: some View {
    Button {
      app.go(entry.route)
    } label: {
      VStack(spacing: 6) {
        Icon(entry.icon, size: entry.iconSize)
        Text(entry.label).font(Theme.sans(14.4)).lineLimit(1).minimumScaleFactor(0.8)
      }
      .foregroundStyle(entry.id == "home" || entry.id == "library" ? .white : .white.opacity(0.8))
      .frame(width: Theme.railWidth, height: 80)
      .background(
        active ? Theme.primary.opacity(0.8) : (hover ? Theme.primary : Theme.bg.opacity(0.6))
      )
      .overlay(alignment: .bottom) { Theme.primary.opacity(0.7).frame(height: 1) }
      .overlay(alignment: .leading) { if active { Theme.yellow400.frame(width: 2) } }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
  }
}

/// controls/GlobalSearch.vue: 320 × 32, debounced suggestions, Enter opens results.
struct GlobalSearch: View {
  @Bindable var app = AppModel.shared
  @State private var results: SearchResults?
  @State private var showResults = false
  @State private var task: Task<Void, Never>?
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 0) {
      TextField(L.s("PlaceholderSearch"), text: $app.searchText)
        .textFieldStyle(.plain)
        .font(Theme.sans(14))
        .focused($focused)
        .onSubmit {
          let q = app.searchText.trimmingCharacters(in: .whitespaces)
          guard !q.isEmpty else { return }
          showResults = false
          app.go(.search(q))
        }
        .onChange(of: app.searchText) { _, q in schedule(q) }
      if app.searchText.isEmpty {
        Icon("search", size: 19).foregroundStyle(Theme.gray400)
      } else {
        HoverIcon(icon: "close", size: 19, color: Theme.gray400) {
          app.searchText = ""
          results = nil
          showResults = false
        }
      }
    }
    .padding(.horizontal, 10)
    .frame(width: 320, height: 32)
    .background(Theme.primary)
    .clipShape(RoundedRectangle(cornerRadius: 4))
    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.gray600))
    // An in-window overlay, not a popover: a popover is its own window and
    // takes the keystrokes that follow while typing.
    .overlay(alignment: .topLeading) {
      if showResults {
        SearchSuggestions(results: results) { showResults = false }
          .frame(width: 320)
          .background(Theme.bg)
          .clipShape(RoundedRectangle(cornerRadius: 4))
          .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.gray600))
          .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
          .offset(y: 36)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .onChange(of: focused) { _, f in
      if f {
        if results != nil, !app.searchText.isEmpty { showResults = true }
      } else {
        // Let a click on a suggestion land before hiding.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { if !focused { showResults = false } }
      }
    }
    .onExitCommand { showResults = false }
  }

  private func schedule(_ q: String) {
    task?.cancel()
    let query = q.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty, let lib = app.currentLibraryId else {
      results = nil
      showResults = false
      return
    }
    task = Task {
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else { return }
      let r = try? await app.api.search(lib, q: query, limit: 3)
      guard !Task.isCancelled else { return }
      results = r
      showResults = r != nil && focused
    }
  }
}

struct SearchSuggestions: View {
  let results: SearchResults?
  let dismiss: () -> Void
  var app = AppModel.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let r = results {
        if r.book.isEmpty && r.authors.isEmpty && r.series.isEmpty && r.narrators.isEmpty
          && r.tags.isEmpty && r.genres.isEmpty
        {
          Text(L.s("MessageNoResults")).font(Theme.sans(14)).foregroundStyle(Theme.gray300).padding(
            12)
        }
        section(L.s("LabelBooks"), !r.book.isEmpty) {
          ForEach(r.book, id: \.libraryItem.id) { h in
            row {
              app.go(.item(h.libraryItem.id))
            } content: {
              HStack(spacing: 8) {
                BookCover(item: h.libraryItem, width: 32, pixelWidth: 100)
                VStack(alignment: .leading) {
                  Text(h.libraryItem.title).font(Theme.sans(13)).lineLimit(1)
                  Text(h.libraryItem.authorLine).font(Theme.sans(11)).foregroundStyle(Theme.gray400)
                    .lineLimit(1)
                }
              }
            }
          }
        }
        section(L.s("LabelAuthors"), !r.authors.isEmpty) {
          ForEach(r.authors) { a in
            row {
              app.go(.author(a.id))
            } content: {
              Text(a.name).font(Theme.sans(13))
            }
          }
        }
        section(L.s("LabelSeries"), !r.series.isEmpty) {
          ForEach(r.series, id: \.series.id) { s in
            row {
              app.go(.seriesDetail(s.series.id))
            } content: {
              Text(s.series.name).font(Theme.sans(13))
            }
          }
        }
        section(L.s("LabelTags"), !r.tags.isEmpty) {
          ForEach(r.tags, id: \.name) { t in
            row {
              app.go(.filtered(FilterEncoding.filter("tags", t.name)))
            } content: {
              Text(t.name).font(Theme.sans(13))
            }
          }
        }
        section(L.s("LabelGenres"), !r.genres.isEmpty) {
          ForEach(r.genres, id: \.name) { g in
            row {
              app.go(.filtered(FilterEncoding.filter("genres", g.name)))
            } content: {
              Text(g.name).font(Theme.sans(13))
            }
          }
        }
        section(L.s("LabelNarrators"), !r.narrators.isEmpty) {
          ForEach(r.narrators, id: \.name) { n in
            row {
              app.go(.filtered(FilterEncoding.filter("narrators", n.name)))
            } content: {
              Text(n.name).font(Theme.sans(13))
            }
          }
        }
      } else {
        Text(L.s("MessageThinking")).font(Theme.sans(14)).foregroundStyle(Theme.gray300).padding(12)
      }
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private func section<C: View>(_ title: String, _ show: Bool, @ViewBuilder _ content: () -> C)
    -> some View
  {
    if show {
      Text(title.uppercased()).font(Theme.sans(11, .semibold)).foregroundStyle(Theme.gray400)
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
      content()
    }
  }

  private func row<C: View>(_ action: @escaping () -> Void, @ViewBuilder content: () -> C)
    -> some View
  {
    Button {
      action()
      dismiss()
    } label: {
      content().foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(
        .horizontal, 12
      )
      .padding(.vertical, 5).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .hoverHighlight(Theme.black400)
  }
}
