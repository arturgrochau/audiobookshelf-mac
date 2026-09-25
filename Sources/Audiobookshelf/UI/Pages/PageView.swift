import ABSCore
import SwiftUI

/// The content column to the right of the rail, switched by route.
struct PageView: View {
  let route: Route

  var body: some View {
    ZStack {
      Theme.pageGradient
      switch route {
      case .home: HomePage()
      case .library: LibraryGridPage(filter: nil)
      case .filtered(let f): LibraryGridPage(filter: f)
      case .series: SeriesListPage()
      case .seriesDetail(let id): SeriesDetailPage(seriesId: id)
      case .authors: AuthorsPage()
      case .author(let id): AuthorPage(authorId: id)
      case .item(let id): ItemPage(itemId: id)
      case .collections: CollectionsPage()
      case .collection(let id): GroupDetailPage(kind: .collection, id: id)
      case .playlists: PlaylistsPage()
      case .playlist(let id): GroupDetailPage(kind: .playlist, id: id)
      case .narrators: NarratorsPage()
      case .search(let q): SearchPage(query: q)
      case .account: AccountPage()
      case .stats: StatsPage()
      case .downloads: DownloadsPage()
      }
    }
    .id(route)
  }
}

// MARK: Home

/// BookShelfCategorized.vue in the DETAIL view: one ItemSlider per shelf.
struct HomePage: View {
  var store = LibraryStore.shared
  var app = AppModel.shared
  var settings = AppSettings.shared

  var body: some View {
    let metrics = CardMetrics.current
    let shelves = store.shelves.filter { !$0.isEmpty }
    ScrollView(.vertical) {
      LazyVStack(alignment: .leading, spacing: 0) {
        if shelves.isEmpty && !store.loadingHome {
          Text(L.s("MessageXLibraryIsEmpty", app.currentLibrary?.name ?? ""))
            .font(Theme.sans(24))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        }
        ForEach(shelves) { shelf in
          ItemSlider(title: shelfTitle(shelf), metrics: metrics) {
            shelfCards(shelf, metrics: metrics)
          }
          .padding(.leading, 2 * metrics.em)
          .padding(.vertical, 1.5 * metrics.em)
        }
      }
      .padding(.bottom, 6 * metrics.em)
    }
    .scrollIndicators(.automatic)
    .restoresScroll(.home)
    .overlay(alignment: .bottomTrailing) { CoverSizeWidget().padding(16) }
  }

  private func shelfTitle(_ s: Shelf) -> String {
    if let k = s.labelStringKey, L.table[k] != nil { return L.s(k) }
    return s.label
  }

  @ViewBuilder private func shelfCards(_ shelf: Shelf, metrics: CardMetrics) -> some View {
    switch shelf.entities {
    case .books(let items):
      ForEach(items) { BookCard(item: $0, metrics: metrics, shelfId: shelf.id) }
    case .series(let series):
      ForEach(series) { SeriesCard(series: $0, metrics: metrics) }
    case .authors(let authors):
      ForEach(authors) { AuthorCard(author: $0, m: metrics.m) }
    case .unsupported:
      EmptyView()
    }
  }
}

/// widgets/ItemSlider.vue: title row with round chevrons, horizontal row of cards.
struct ItemSlider<Content: View>: View {
  let title: String
  let metrics: CardMetrics
  @ViewBuilder var content: () -> Content
  @State private var position = ScrollPosition(edge: .leading)
  @State private var geo = SliderGeometry()

  struct SliderGeometry: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var container: CGFloat = 0
  }

  var body: some View {
    let em = metrics.em
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        Text(title).font(Theme.sans(em, .semibold)).foregroundStyle(Theme.gray100)
        Spacer()
        if geo.content > geo.container + 1 {
          chevron("chevron_left", enabled: geo.offset > 1) { scroll(-1) }
          chevron("chevron_right", enabled: geo.offset + geo.container < geo.content - 1) {
            scroll(1)
          }
        }
      }
      .padding(.vertical, 0.75 * em)
      .padding(.trailing, 2 * em)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: em) { content() }
          .padding(.trailing, 2 * em)
      }
      .scrollIndicators(.never)
      .scrollPosition($position)
      .onScrollGeometryChange(for: SliderGeometry.self) {
        SliderGeometry(
          offset: $0.contentOffset.x, content: $0.contentSize.width,
          container: $0.containerSize.width)
      } action: { _, new in
        geo = new
      }
    }
  }

  private func scroll(_ dir: CGFloat) {
    let target = max(0, min(geo.content - geo.container, geo.offset + dir * geo.container))
    withAnimation(.easeInOut(duration: 0.3)) { position.scrollTo(x: target) }
  }

  private func chevron(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    let em = metrics.em
    return Button(action: action) {
      Icon(icon, size: 1.5 * em)
        .foregroundStyle(enabled ? Theme.gray300 : Color.white.opacity(0.4))
        .frame(width: 2 * em, height: 2 * em)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .background(Circle().fill(Color.clear)).hoverHighlight(.white.opacity(0.05)).clipShape(Circle())
    .padding(.horizontal, 0.25 * em)
  }
}

/// widgets/CoverSizeWidget.vue: − / + in the bottom-right corner, 60…220 by 20.
struct CoverSizeWidget: View {
  var settings = AppSettings.shared

  var body: some View {
    HStack(spacing: 4) {
      HoverIcon(icon: "remove", size: 20) { step(-1) }
      HoverIcon(icon: "add", size: 20) { step(1) }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Theme.bg.opacity(0.9))
    .clipShape(RoundedRectangle(cornerRadius: 999))
    .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color.white.opacity(0.1)))
  }

  func step(_ d: Double) {
    let v = settings.bookshelfCoverSize + 20 * d
    settings.bookshelfCoverSize = min(220, max(60, v))
  }
}

// MARK: Library grid

/// LazyBookshelf.vue for the Library tab: local sort and filter over the
/// cached minified items.
struct LibraryGridPage: View {
  let filter: String?
  /// Series pages: the server orders by sequence and ignores the library sort.
  var sortOverride: (key: String, desc: Bool)?
  var store = LibraryStore.shared
  var app = AppModel.shared
  var settings = AppSettings.shared

  var body: some View {
    let metrics = CardMetrics.current
    let items = visibleItems()
    let em = metrics.em
    VStack(spacing: 0) {
      LibraryToolbar(count: items.count, filter: filter)
      ScrollView(.vertical) {
        LazyVGrid(
          columns: [
            GridItem(
              .adaptive(minimum: metrics.coverWidth, maximum: metrics.coverWidth),
              spacing: 1.5 * em, alignment: .top)
          ],
          alignment: .leading, spacing: 0
        ) {
          ForEach(items) { item in
            BookCard(
              item: item, metrics: metrics,
              showSequence: LibraryQuery.seriesFilterId(activeFilter) != nil)
          }
        }
        .padding(.horizontal, 4 * em)
        .padding(.vertical, 2 * em)
      }
      .restoresScroll(filter.map { Route.filtered($0) } ?? .library)
      .overlay(alignment: .bottomTrailing) { CoverSizeWidget().padding(16) }
    }
  }

  private var activeFilter: String { filter ?? settings.filterBy }

  private func visibleItems() -> [LibraryItem] {
    _ = store.revision
    let progress = Dictionary(
      (app.user?.mediaProgress ?? []).filter { $0.episodeId == nil }.map { ($0.libraryItemId, $0) },
      uniquingKeysWith: { a, _ in a })
    let ctx = LibraryQuery.Context(
      progress: progress,
      authorsById: Dictionary(
        (app.filterData?.authors ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a }),
      seriesById: Dictionary(
        (app.filterData?.series ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a }),
      ignorePrefix: app.serverSettings?.sortingIgnorePrefix ?? false)
    return LibraryQuery.apply(
      store.items, filter: activeFilter, sort: sortOverride?.key ?? settings.orderBy,
      desc: sortOverride?.desc ?? settings.orderDesc, ctx: ctx)
  }
}

/// The 40 px bar above the grid: count, sort menu, filter reset.
struct LibraryToolbar: View {
  let count: Int
  let filter: String?
  var settings = AppSettings.shared
  var app = AppModel.shared

  static let ascendingSorts: Set<String> = [
    "media.metadata.title", "media.metadata.authorName", "media.metadata.authorNameLF", "sequence",
  ]

  static let sorts: [(String, String)] = [
    ("media.metadata.title", "LabelTitle"),
    ("media.metadata.authorName", "LabelAuthorFirstLast"),
    ("media.metadata.authorNameLF", "LabelAuthorLastFirst"),
    ("media.metadata.publishedYear", "LabelPublishYear"),
    ("addedAt", "LabelAddedAt"),
    ("size", "LabelSize"),
    ("media.duration", "LabelDuration"),
    ("birthtimeMs", "LabelFileBirthtime"),
    ("mtimeMs", "LabelFileModified"),
    ("progress", "LabelLibrarySortByProgress"),
    ("progress.createdAt", "LabelLibrarySortByProgressStarted"),
    ("progress.finishedAt", "LabelLibrarySortByProgressFinished"),
    ("random", "LabelRandomly"),
  ]

  var body: some View {
    HStack(spacing: 12) {
      Text("\(count) \(L.s("LabelBooks"))").font(Theme.sans(15)).foregroundStyle(Theme.gray200)
      if let filter, filter != "all" {
        Button {
          app.go(.library)
        } label: {
          HStack(spacing: 4) {
            Text(Self.describe(filter)).lineLimit(1)
            Icon("close", size: 14)
          }
          .font(Theme.sans(13))
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(Theme.primary)
          .clipShape(RoundedRectangle(cornerRadius: 999))
        }
        .buttonStyle(.plain)
      }
      Spacer()
      Menu {
        ForEach(Self.sorts, id: \.0) { key, label in
          Button {
            if settings.orderBy == key {
              settings.orderDesc.toggle()
            } else {
              // Web LibrarySortSelect: text sorts start ascending, the rest keep the direction.
              if Self.ascendingSorts.contains(key) { settings.orderDesc = false }
              settings.orderBy = key
            }
          } label: {
            if settings.orderBy == key {
              Label(L.s(label), systemImage: settings.orderDesc ? "arrow.down" : "arrow.up")
            } else {
              Text(L.s(label))
            }
          }
        }
      } label: {
        Text(L.s(Self.sorts.first { $0.0 == settings.orderBy }?.1 ?? "LabelTitle"))
          .font(Theme.sans(14))
      }
      .menuStyle(.button)
      .fixedSize()
    }
    .padding(.horizontal, 16)
    .frame(height: Theme.toolbarHeight)
    .background(Theme.bg)
    .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.3)).frame(height: 1) }
  }

  static func describe(_ filter: String) -> String {
    let parts = filter.split(separator: ".", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return filter }
    let value = FilterEncoding.decode(parts[1]) ?? parts[1]
    if parts[0] == "authors" {
      return AppModel.shared.filterData?.authors?.first { $0.id == value }?.name ?? value
    }
    if parts[0] == "series" {
      return AppModel.shared.filterData?.series?.first { $0.id == value }?.name ?? value
    }
    return value
  }
}

// MARK: Series

struct SeriesListPage: View {
  var store = LibraryStore.shared

  var body: some View {
    let metrics = CardMetrics.current
    let em = metrics.em
    ScrollView(.vertical) {
      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(minimum: metrics.coverWidth * 2, maximum: metrics.coverWidth * 2),
            spacing: 1.5 * em, alignment: .top)
        ],
        alignment: .leading, spacing: 0
      ) {
        ForEach(store.series) { SeriesCard(series: $0, metrics: metrics) }
      }
      .padding(.horizontal, 4 * em)
      .padding(.vertical, 2 * em)
    }
    .restoresScroll(.series)
    .task { if store.series.isEmpty { await store.refreshSeries() } }
    .overlay(alignment: .bottomTrailing) { CoverSizeWidget().padding(16) }
  }
}

/// The web opens a series as the bookshelf filtered by that series, sorted by sequence.
struct SeriesDetailPage: View {
  let seriesId: String
  var body: some View {
    LibraryGridPage(filter: FilterEncoding.filter("series", seriesId), sortOverride: ("sequence", false))
  }
}

// MARK: Authors

struct AuthorsPage: View {
  var store = LibraryStore.shared

  var body: some View {
    let m = AppSettings.shared.bookshelfCoverSize / 120
    ScrollView(.vertical) {
      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(minimum: 153.6 * m, maximum: 153.6 * m), spacing: 24 * m, alignment: .top)
        ],
        alignment: .leading, spacing: 24 * m
      ) {
        ForEach(store.authors) { AuthorCard(author: $0, m: m) }
      }
      .padding(.horizontal, 64 * m)
      .padding(.vertical, 32 * m)
    }
    .restoresScroll(.authors)
    .task { if store.authors.isEmpty { await store.refreshAuthors() } }
  }
}

/// pages/author/_id.vue: image, name, description, then a books slider and
/// one slider per series.
struct AuthorPage: View {
  let authorId: String
  var app = AppModel.shared
  @State private var author: Author?

  var body: some View {
    let metrics = CardMetrics.current
    ScrollView(.vertical) {
      if let author {
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .top, spacing: 32) {
            ZStack {
              Theme.primary
              if let url = app.authorImageURL(author) {
                RemoteImage(url: url, pixelWidth: 400) { Icon("person", size: 120, filled: true) }
              } else {
                Icon("person", size: 120, filled: true).foregroundStyle(.white.opacity(0.6))
              }
            }
            .frame(width: 192, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 12) {
              Text(author.name).font(Theme.sans(36, .semibold))
              if let d = author.description, !d.isEmpty {
                Text(d).font(Theme.sans(16)).foregroundStyle(Theme.gray100).textSelection(.enabled)
              }
            }
            Spacer(minLength: 0)
          }
          .padding(32)
          if let books = author.libraryItems, !books.isEmpty {
            ItemSlider(title: "\(L.s("LabelBooks")) (\(books.count))", metrics: metrics) {
              ForEach(books) { BookCard(item: $0, metrics: metrics) }
            }
            .padding(.leading, 32)
            .padding(.vertical, 12)
          }
          ForEach(author.series ?? []) { s in
            ItemSlider(title: "\(s.name) (\(s.items?.count ?? 0))", metrics: metrics) {
              ForEach(s.items ?? []) { BookCard(item: $0, metrics: metrics, showSequence: true) }
            }
            .padding(.leading, 32)
            .padding(.vertical, 12)
          }
        }
        .frame(maxWidth: 1152, alignment: .leading)
        .frame(maxWidth: .infinity)
      }
    }
    .task { author = try? await app.api.author(authorId) }
  }
}
