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
    .overlay { SpeedFlash() }
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

/// The title bar: traffic lights, history, library, search, one account menu.
///
/// The web's Appbar.vue put a logo, a wordmark, a boxed library picker and
/// three icons here. A Mac window already says which app it is, so the bar
/// keeps only what navigates.
struct AppBar: View {
  var app = AppModel.shared

  var body: some View {
    HStack(spacing: 0) {
      Color.clear.frame(width: 76)
      HStack(spacing: 2) {
        SymbolButton(symbol: "chevron.left", size: 13, weight: .semibold,
                     disabled: !app.canGoBack, help: "Back") { app.goBack() }
        SymbolButton(symbol: "chevron.right", size: 13, weight: .semibold,
                     disabled: !app.canGoForward, help: "Forward") { app.goForward() }
      }
      .padding(.trailing, 10)
      LibraryPicker()
      Spacer(minLength: 16)
      GlobalSearch()
      Spacer(minLength: 16)
      AccountButton()
        .padding(.trailing, 14)
    }
    .frame(height: Theme.appBarHeight)
    .background(Theme.primary)
    .overlay(alignment: .bottom) { Color.white.opacity(0.06).frame(height: 1) }
    .gesture(WindowDragGesture())
    .allowsWindowActivationEvents(true)
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

/// ui/LibrariesDropdown.vue as a plain title-bar menu: "Audiobooks ⌄".
struct LibraryPicker: View {
  var app = AppModel.shared
  @State private var hover = false

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
      HStack(spacing: 5) {
        Text(app.currentLibrary?.name ?? "").font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
          .foregroundStyle(Theme.gray400)
      }
      .foregroundStyle(hover ? .white : Theme.gray200)
      .padding(.horizontal, 9)
      .frame(height: 28)
      .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(hover ? 0.08 : 0)))
      .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .onHover { hover = $0 }
    .help("Switch library")
  }
}

/// One menu for the person: stats, account, server settings, log out.
struct AccountButton: View {
  var app = AppModel.shared
  @State private var hover = false

  var body: some View {
    Menu {
      Text(app.user?.username ?? "")
      Divider()
      Button("Your Stats") { app.go(.stats) }
      Button("Account") { app.go(.account) }
      if app.user?.isAdminOrUp == true {
        Button("Server Settings…") {
          if let u = app.webURL?.appendingPathComponent("config") { NSWorkspace.shared.open(u) }
        }
      }
      Button("Open in Browser") { if let u = app.webURL { NSWorkspace.shared.open(u) } }
      Divider()
      Button("Log Out") { Task { await app.logout() } }
    } label: {
      Image(systemName: "person.crop.circle")
        .font(.system(size: 18, weight: .regular))
        .foregroundStyle(hover ? .white : Theme.gray300)
        .frame(width: 32, height: 32)
        .background(Circle().fill(Color.white.opacity(hover ? 0.08 : 0)))
        .contentShape(Circle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .onHover { hover = $0 }
    .help(app.user?.username ?? "Account")
  }
}

/// components/app/SideRail.vue, quieter: symbols over small labels, the page
/// you are on marked by a tinted pill instead of a yellow bar.
struct SideRail: View {
  var app = AppModel.shared
  var downloads = DownloadManager.shared

  struct Entry: Identifiable {
    let id: String
    let label: String
    let symbol: String
    let route: Route
  }

  var entries: [Entry] {
    var e: [Entry] = [
      Entry(id: "home", label: L.s("ButtonHome"), symbol: "house", route: .home),
      Entry(id: "library", label: L.s("ButtonLibrary"), symbol: "books.vertical", route: .library),
      Entry(id: "series", label: L.s("ButtonSeries"), symbol: "square.stack.3d.up", route: .series),
      Entry(
        id: "collections", label: L.s("ButtonCollections"), symbol: "square.grid.2x2",
        route: .collections),
    ]
    if app.numUserPlaylists > 0 || !LibraryStore.shared.playlists.isEmpty {
      e.append(
        Entry(id: "playlists", label: L.s("ButtonPlaylists"), symbol: "music.note.list",
              route: .playlists))
    }
    e.append(Entry(id: "authors", label: L.s("ButtonAuthors"), symbol: "person.2", route: .authors))
    e.append(
      Entry(id: "narrators", label: L.s("LabelNarrators"), symbol: "mic", route: .narrators))
    if !downloads.downloadedIds.isEmpty {
      e.append(
        Entry(id: "downloads", label: "Downloaded", symbol: "arrow.down.circle",
              route: .downloads))
    }
    return e
  }

  var body: some View {
    VStack(spacing: 4) {
      ForEach(entries) { e in RailButton(entry: e, active: isActive(e.route)) }
      Spacer()
      // Nothing to say when the server is on the LAN, which is nearly always.
      if !app.onLAN {
        Image(systemName: app.isOnline ? "globe" : "wifi.slash")
          .font(.system(size: 12))
          .foregroundStyle(Theme.gray500)
          .help(app.isOnline ? "Connected remotely" : "Offline")
          .padding(.bottom, 12)
      }
    }
    .padding(.top, 10)
    .frame(width: Theme.railWidth)
    .background(Theme.primary)
    .overlay(alignment: .trailing) { Color.white.opacity(0.06).frame(width: 1) }
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
      VStack(spacing: 4) {
        Image(systemName: entry.symbol)
          .symbolVariant(active ? .fill : .none)
          .font(.system(size: 17, weight: .regular))
          .frame(height: 20)
        Text(entry.label).font(.system(size: 10, weight: .medium)).lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .foregroundStyle(active ? Theme.accent : hover ? .white : Theme.gray400)
      .frame(width: Theme.railWidth - 12, height: 54)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(active ? Theme.accent.opacity(0.12) : Color.white.opacity(hover ? 0.06 : 0))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
    .animation(.easeOut(duration: 0.12), value: hover)
    .help(entry.label)
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
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.gray400)
      TextField("Search", text: $app.searchText)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .focused($focused)
        .onSubmit {
          let q = app.searchText.trimmingCharacters(in: .whitespaces)
          guard !q.isEmpty else { return }
          showResults = false
          app.go(.search(q))
        }
        .onChange(of: app.searchText) { _, q in schedule(q) }
      if !app.searchText.isEmpty {
        Button {
          app.searchText = ""
          results = nil
          showResults = false
        } label: {
          Image(systemName: "xmark.circle.fill").font(.system(size: 12))
            .foregroundStyle(Theme.gray400)
        }
        .buttonStyle(.plain)
        .help("Clear")
      }
    }
    .padding(.horizontal, 10)
    .frame(width: 320, height: 28)
    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(focused ? 0.1 : 0.06)))
    .overlay(
      RoundedRectangle(cornerRadius: 7).stroke(
        focused ? Theme.accent.opacity(0.6) : Color.white.opacity(0.08)))
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
        if r.isEmpty {
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
