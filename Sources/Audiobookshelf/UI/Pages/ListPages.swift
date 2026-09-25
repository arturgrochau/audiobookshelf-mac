import ABSCore
import SwiftUI

// MARK: Collections & playlists

/// A group of books shown as a card: the first covers side by side, name and count.
struct GroupCard: View {
  let name: String
  let books: [LibraryItem]
  let metrics: CardMetrics
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    let w = metrics.coverWidth * 2
    let em = metrics.em
    VStack(alignment: .leading, spacing: 0) {
      ZStack {
        Theme.primary
        HStack(spacing: 0) {
          ForEach(Array(books.prefix(2).enumerated()), id: \.offset) { _, b in
            BookCover(
              item: b, width: metrics.coverWidth, aspect: metrics.aspect,
              pixelWidth: Int(metrics.coverWidth * 2))
          }
        }
        .frame(width: w, alignment: .leading)
        if books.isEmpty {
          Icon("collections_bookmark", size: 3 * em).foregroundStyle(Theme.gray500)
        }
        if hover {
          Color.black.opacity(0.4)
        }
      }
      .frame(width: w, height: metrics.coverHeight)
      .clipShape(RoundedRectangle(cornerRadius: 2))
      .shadow(color: Color(hex: 0x111111, opacity: 0.4), radius: 4, x: 3, y: 1)
      .onHover { hover = $0 }
      .onTapGesture(perform: action)
      Text(name).font(Theme.sans(0.9 * em)).foregroundStyle(.white).lineLimit(1)
        .padding(.top, 0.5 * em)
      Text("\(books.count) \(L.s("LabelBooks"))").font(Theme.sans(0.8 * em))
        .foregroundStyle(Theme.gray400)
    }
    .frame(width: w, alignment: .leading)
    .padding(.bottom, 0.5 * em)
  }
}

private struct CardGrid<Content: View>: View {
  let minWidth: CGFloat
  let metrics: CardMetrics
  @ViewBuilder var content: () -> Content

  var body: some View {
    let em = metrics.em
    ScrollView(.vertical) {
      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(minimum: minWidth, maximum: minWidth), spacing: 1.5 * em, alignment: .top)
        ],
        alignment: .leading, spacing: 0.5 * em
      ) { content() }
      .padding(.horizontal, 4 * em)
      .padding(.vertical, 2 * em)
    }
  }
}

private struct EmptyMessage: View {
  let text: String
  var detail: String?
  var body: some View {
    VStack(spacing: 8) {
      Text(text).font(Theme.sans(24))
      if let detail { Text(detail).font(Theme.sans(15)).foregroundStyle(Theme.gray400) }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct CollectionsPage: View {
  var store = LibraryStore.shared
  var app = AppModel.shared

  var body: some View {
    let metrics = CardMetrics.current
    Group {
      if store.collections.isEmpty {
        EmptyMessage(text: L.s("MessageNoCollections"))
      } else {
        CardGrid(minWidth: metrics.coverWidth * 2, metrics: metrics) {
          ForEach(store.collections) { c in
            GroupCard(name: c.name, books: c.books ?? [], metrics: metrics) {
              app.go(.collection(c.id))
            }
          }
        }
      }
    }
    .task { await store.refreshCollections() }
  }
}

struct PlaylistsPage: View {
  var store = LibraryStore.shared
  var app = AppModel.shared

  var body: some View {
    let metrics = CardMetrics.current
    Group {
      if store.playlists.isEmpty {
        EmptyMessage(text: L.s("MessageNoUserPlaylists"), detail: L.s("MessageNoUserPlaylistsHelp"))
      } else {
        CardGrid(minWidth: metrics.coverWidth * 2, metrics: metrics) {
          ForEach(store.playlists) { p in
            GroupCard(
              name: p.name, books: (p.items ?? []).compactMap(\.libraryItem), metrics: metrics
            ) { app.go(.playlist(p.id)) }
          }
        }
      }
    }
    .task { await store.refreshPlaylists() }
  }
}

/// pages/collection/_id.vue and pages/playlist/_id.vue: header with name,
/// description and Play, then the books in order.
struct GroupDetailPage: View {
  enum Kind { case collection, playlist }
  let kind: Kind
  let id: String
  var app = AppModel.shared
  @State private var name = ""
  @State private var detail: String?
  @State private var books: [LibraryItem] = []
  @State private var loaded = false

  var body: some View {
    let metrics = CardMetrics.current
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
          Text(name).font(Theme.sans(30, .semibold))
          Text("\(books.count) \(L.s("LabelBooks"))").font(Theme.sans(16))
            .foregroundStyle(Theme.gray400)
          Spacer()
        }
        if let detail, !detail.isEmpty {
          Text(detail).font(Theme.sans(16)).foregroundStyle(Theme.gray200)
        }
        if books.contains(where: \.media.hasAudio) {
          WebButton(color: Theme.success, small: true, paddingX: 16) {
            playAll()
          } label: {
            HStack(spacing: 4) {
              Icon("play_arrow", size: 24, filled: true).padding(.leading, -8)
              Text(L.s("ButtonPlay"))
            }
            .frame(height: 28)
          }
        }
        if loaded && books.isEmpty {
          Text(L.s("MessageNoItemsFound")).font(Theme.sans(16)).foregroundStyle(Theme.gray400)
            .padding(.vertical, 24)
        }
        LazyVGrid(
          columns: [
            GridItem(
              .adaptive(minimum: metrics.coverWidth, maximum: metrics.coverWidth),
              spacing: 1.5 * metrics.em, alignment: .top)
          ],
          alignment: .leading, spacing: 0
        ) {
          ForEach(books) { BookCard(item: $0, metrics: metrics) }
        }
      }
      .padding(.horizontal, 4 * metrics.em)
      .padding(.vertical, 32)
    }
    .task(id: id) { await load() }
  }

  private func load() async {
    switch kind {
    case .collection:
      if let c = try? await app.api.collection(id) {
        name = c.name
        detail = c.description
        books = c.books ?? []
      }
    case .playlist:
      if let p = try? await app.api.playlist(id) {
        name = p.name
        detail = p.description
        books = (p.items ?? []).compactMap(\.libraryItem)
      }
    }
    loaded = true
  }

  /// Web: plays the first unfinished book with the whole group as the queue.
  private func playAll() {
    let playable = books.filter(\.media.hasAudio)
    guard !playable.isEmpty else { return }
    let first = playable.first { app.progress(for: $0.id)?.isFinished != true } ?? playable[0]
    Task {
      await PlayerModel.shared.play(first.id, queue: playable.map(PlayerModel.queueItem))
    }
  }
}

// MARK: Narrators

/// pages/library/_library/narrators.vue: a table of names and book counts.
struct NarratorsPage: View {
  var store = LibraryStore.shared
  var app = AppModel.shared

  var body: some View {
    ScrollView(.vertical) {
      WebTable(columns: [
        (L.s("LabelName"), nil, .leading), (L.s("LabelBooks"), 120, .center),
      ]) {
        ForEach(Array(store.narrators.enumerated()), id: \.offset) { i, n in
          WebTableRow(index: i) {
            Text(n.name).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
            Text("\(n.numBooks ?? 0)").frame(width: 120)
          }
          .contentShape(Rectangle())
          .onTapGesture { app.go(.filtered(FilterEncoding.filter("narrators", n.name))) }
          .linkCursor()
        }
      }
      .frame(maxWidth: 900)
      .padding(32)
      .frame(maxWidth: .infinity)
    }
    .task { await store.refreshNarrators() }
  }
}

// MARK: Search

/// pages/library/_library/search.vue: books, series, authors for the query.
struct SearchPage: View {
  let query: String
  var app = AppModel.shared
  @State private var results: SearchResults?

  var body: some View {
    let metrics = CardMetrics.current
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 0) {
        if let r = results {
          if r.book.isEmpty && r.series.isEmpty && r.authors.isEmpty {
            Text(L.s("MessageNoResults")).font(Theme.sans(20)).foregroundStyle(Theme.gray300)
              .padding(32)
          }
          if !r.book.isEmpty {
            ItemSlider(title: L.s("LabelBooks"), metrics: metrics) {
              ForEach(r.book, id: \.libraryItem.id) {
                BookCard(item: $0.libraryItem, metrics: metrics)
              }
            }
            .padding(.leading, 2 * metrics.em).padding(.vertical, 1.5 * metrics.em)
          }
          if !r.series.isEmpty {
            ItemSlider(title: L.s("LabelSeries"), metrics: metrics) {
              ForEach(r.series, id: \.series.id) { h in
                SeriesCard(series: Self.withBooks(h), metrics: metrics)
              }
            }
            .padding(.leading, 2 * metrics.em).padding(.vertical, 1.5 * metrics.em)
          }
          if !r.authors.isEmpty {
            ItemSlider(title: L.s("LabelAuthors"), metrics: metrics) {
              ForEach(r.authors) { AuthorCard(author: $0, m: metrics.m) }
            }
            .padding(.leading, 2 * metrics.em).padding(.vertical, 1.5 * metrics.em)
          }
        }
      }
    }
    .task(id: query) {
      guard let lib = app.currentLibraryId else { return }
      results = try? await app.api.search(lib, q: query, limit: 25)
    }
  }
}

extension SearchPage {
  /// Search hits carry the series' books next to it, not inside it.
  static func withBooks(_ h: SearchResults.SeriesHit) -> Series {
    var s = h.series
    if s.books == nil { s.books = h.books }
    return s
  }
}

// MARK: Account

struct AccountPage: View {
  var app = AppModel.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(L.s("HeaderAccount")).font(Theme.sans(30, .semibold))
      HStack(spacing: 0) {
        Text(L.s("LabelUsername").uppercased()).font(Theme.sans(14)).foregroundStyle(
          .white.opacity(0.6)
        )
        .frame(width: 136, alignment: .leading)
        Text(app.user?.username ?? "").font(Theme.sans(16))
      }
      HStack(spacing: 0) {
        Text("SERVER").font(Theme.sans(14)).foregroundStyle(.white.opacity(0.6))
          .frame(width: 136, alignment: .leading)
        Text(app.account?.serverURL.absoluteString ?? "").font(Theme.sans(16))
      }
      HStack(spacing: 8) {
        WebButton(L.s("ButtonLogout"), small: true) { Task { await app.logout() } }
        WebButton(L.s("ButtonLogoutAllDevices"), small: true) {
          Task { await app.logout(allDevices: true) }
        }
      }
      .padding(.top, 8)
      Spacer()
    }
    .padding(32)
    .frame(maxWidth: 800, alignment: .leading)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

// MARK: Stats

/// pages/config/stats.vue: the three totals, the last 7 days, recent sessions.
struct StatsPage: View {
  var app = AppModel.shared
  @State private var stats: ListeningStats?

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 24) {
        Text(L.s("HeaderYourStats")).font(Theme.sans(30, .semibold))
        if let s = stats {
          HStack(spacing: 48) {
            total(Double(finishedCount), L.s("LabelStatsItemsFinished"), "local_library")
            total(Double(s.days.count), L.s("LabelStatsDaysListened"), "event")
            total((s.totalTime / 60).rounded(), L.s("LabelStatsMinutesListening"), "watch_later")
          }
          Text(L.s("HeaderStatsMinutesListeningChart")).font(Theme.sans(18, .semibold))
            .padding(.top, 8)
          weekChart(s)
          Text(L.s("HeaderStatsRecentSessions")).font(Theme.sans(18, .semibold)).padding(.top, 8)
          if s.recentSessions.isEmpty {
            Text(L.s("MessageNoListeningSessions")).foregroundStyle(Theme.gray400)
          }
          VStack(spacing: 0) {
            ForEach(Array(s.recentSessions.prefix(10).enumerated()), id: \.offset) { i, r in
              WebTableRow(index: i) {
                Text(r.displayTitle ?? "").frame(maxWidth: .infinity, alignment: .leading)
                  .lineLimit(1).padding(.leading, 16)
                Text(Format.elapsedPretty(r.timeListening ?? 0)).frame(width: 110)
                Text(Self.day(r.updatedAt)).foregroundStyle(Theme.gray400).frame(width: 110)
              }
            }
          }
          .font(Theme.sans(14))
        }
      }
      .padding(32)
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .task { stats = try? await app.api.listeningStats() }
  }

  private var finishedCount: Int {
    (app.user?.mediaProgress ?? []).filter { $0.isFinished == true }.count
  }

  private func total(_ n: Double, _ label: String, _ icon: String) -> some View {
    HStack(spacing: 12) {
      Icon(icon, size: 40).foregroundStyle(Theme.gray400)
      VStack(alignment: .leading, spacing: 0) {
        Text(String(Int(n))).font(Theme.sans(36, .semibold))
        Text(label).font(Theme.sans(14)).foregroundStyle(Theme.gray300)
      }
    }
  }

  private func weekChart(_ s: ListeningStats) -> some View {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    let label = DateFormatter()
    label.dateFormat = "EEE"
    let days: [(String, Double)] = (0..<7).reversed().map { back in
      let d = Calendar.current.date(byAdding: .day, value: -back, to: Date()) ?? Date()
      return (label.string(from: d), (s.days[f.string(from: d)] ?? 0) / 60)
    }
    let peak = max(1, days.map(\.1).max() ?? 1)
    return HStack(alignment: .bottom, spacing: 16) {
      ForEach(Array(days.enumerated()), id: \.offset) { _, d in
        VStack(spacing: 4) {
          Text(String(Int(d.1.rounded()))).font(Theme.sans(12)).foregroundStyle(Theme.gray400)
          RoundedRectangle(cornerRadius: 2).fill(Theme.accent.opacity(0.8))
            .frame(width: 36, height: max(2, 140 * d.1 / peak))
          Text(d.0).font(Theme.sans(12)).foregroundStyle(Theme.gray300)
        }
      }
    }
    .frame(height: 190, alignment: .bottom)
  }

  static func day(_ ms: Double?) -> String {
    guard let ms else { return "" }
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f.string(from: Date(timeIntervalSince1970: ms / 1000))
  }
}

// MARK: Downloads

/// Native-only: books stored on this Mac, with Show in Finder and Remove.
struct DownloadsPage: View {
  var downloads = DownloadManager.shared
  var app = AppModel.shared

  var body: some View {
    let metrics = CardMetrics.current
    let items = downloads.downloadedIds.compactMap {
      LibraryStore.shared.item($0) ?? downloads.storedItem($0)
    }
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(
          "\(items.count) \(L.s("LabelBooks")) · \(Format.bytesPretty(Double(downloads.totalBytes)))"
        )
        .font(Theme.sans(15)).foregroundStyle(Theme.gray200)
        Spacer()
        WebButton("Show in Finder", small: true) {
          NSWorkspace.shared.open(downloads.root)
        }
      }
      .padding(.horizontal, 16)
      .frame(height: Theme.toolbarHeight + 8)
      CardGrid(minWidth: metrics.coverWidth, metrics: metrics) {
        ForEach(items) { BookCard(item: $0, metrics: metrics) }
      }
    }
  }
}
