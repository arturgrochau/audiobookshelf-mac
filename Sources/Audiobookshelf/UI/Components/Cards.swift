import ABSCore
import SwiftUI

/// Card sizing shared by shelves and grids: the web scales everything by
/// `bookshelfCoverSize / 120`, with 1em = 16 px × that multiplier.
struct CardMetrics {
  let m: CGFloat
  let aspect: Double
  var em: CGFloat { 16 * m }
  var coverHeight: CGFloat { 192 * m }
  var coverWidth: CGFloat { coverHeight / aspect }

  @MainActor static var current: CardMetrics {
    CardMetrics(
      m: AppSettings.shared.bookshelfCoverSize / 120,
      aspect: AppModel.shared.currentLibrary?.coverAspect ?? 1)
  }
}

/// cards/LazyBookCard.vue in DETAIL view: cover with progress bar, series
/// badge, hover play and ⋯; title and author under it. No pencil, no radio.
struct BookCard: View {
  let item: LibraryItem
  let metrics: CardMetrics
  var shelfId: String?
  var showSequence = false
  var sortLine: String?
  var onSelect: (() -> Void)?
  var app = AppModel.shared
  @State private var hover = false

  private var progress: MediaProgress? { app.progress(for: item.id) }

  var body: some View {
    let w = metrics.coverWidth
    let em = metrics.em
    VStack(alignment: .leading, spacing: 0) {
      ZStack {
        BookCover(item: item, width: w, aspect: metrics.aspect, pixelWidth: Int(w * 2))
        if let cs = item.collapsedSeries {
          collapsedSeriesOverlay(cs, em: em)
        } else {
          overlays(em: em, w: w)
        }
      }
      .frame(width: w, height: metrics.coverHeight)
      .clipShape(RoundedRectangle(cornerRadius: 2))
      .shadow(color: Color(hex: 0x111111, opacity: 0.4), radius: 4, x: 3, y: 1)
      .onHover { hover = $0 }
      .onTapGesture { open() }
      .contextMenu { ItemMenu(item: item, shelfId: shelfId) }

      VStack(alignment: .leading, spacing: 0) {
        Text(item.collapsedSeries?.name ?? item.title)
          .font(Theme.sans(0.9 * em))
          .foregroundStyle(.white)
          .lineLimit(1)
        if AppSettings.shared.showSubtitles, let sub = item.media.metadata.subtitle, !sub.isEmpty {
          Text(sub).font(Theme.sans(0.6 * em)).foregroundStyle(.white).lineLimit(1)
        }
        Text(item.authorLine)
          .font(Theme.sans(0.8 * em))
          .foregroundStyle(Theme.gray400)
          .lineLimit(1)
        if let sortLine {
          Text(sortLine).font(Theme.sans(0.8 * em)).foregroundStyle(Theme.gray400).lineLimit(1)
        }
      }
      .frame(width: w, alignment: .leading)
      .padding(.vertical, 0.5 * em)
    }
  }

  private func open() {
    if let cs = item.collapsedSeries {
      app.go(.seriesDetail(cs.id))
    } else {
      app.go(.item(item.id))
    }
  }

  @ViewBuilder private func overlays(em: CGFloat, w: CGFloat) -> some View {
    let finished = progress?.isFinished == true
    let pct = finished ? 1.0 : (progress?.progress ?? (progress?.ebookProgress ?? 0))
    ZStack {
      if pct > 0 {
        VStack {
          Spacer()
          HStack(spacing: 0) {
            Rectangle().fill(finished ? Theme.success : Theme.yellow400).frame(
              width: w * CGFloat(min(1, pct)), height: 0.25 * em)
            Spacer(minLength: 0)
          }
        }
      }
      if showSequence, !hover, let seq = item.media.metadata.series?.first?.sequence, !seq.isEmpty {
        VStack {
          HStack {
            Spacer()
            Text("#\(seq)")
              .font(Theme.sans(0.8 * em))
              .foregroundStyle(.white)
              .padding(.horizontal, 0.25 * em)
              .padding(.vertical, 0.1 * em)
              .background(Color.black.opacity(0.9))
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          Spacer()
        }
        .padding(0.375 * em)
      }
      if DownloadManager.shared.isDownloaded(item.id) && !hover {
        VStack {
          Spacer()
          HStack {
            Icon("download_done", size: 0.9 * em).foregroundStyle(.white.opacity(0.9))
              .padding(0.2 * em).background(Circle().fill(Color.black.opacity(0.6)))
            Spacer()
          }
        }
        .padding(0.375 * em)
        .padding(.bottom, 0.25 * em)
      }
      if hover {
        Color.black.opacity(0.4)
        playButton(em: em)
        VStack {
          Spacer()
          HStack {
            if let fmt = item.media.ebookFormat {
              Text(fmt).font(Theme.sans(0.8 * em)).foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Menu {
              ItemMenu(item: item, shelfId: shelfId)
            } label: {
              Icon("more_vert", size: 1.2 * em).foregroundStyle(Theme.gray200)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
          }
          .padding(0.375 * em)
        }
      }
    }
  }

  private func playButton(em: CGFloat) -> some View {
    let ebookOnly = !item.media.hasAudio && item.media.hasEbook
    return Button {
      if ebookOnly {
        ReaderWindows.open(itemId: item.id)
      } else {
        Task { await PlayerModel.shared.play(item.id) }
      }
    } label: {
      Icon(
        ebookOnly ? "auto_stories" : "play_arrow", size: max(2, 3 * metrics.m) * 16, filled: true
      )
      .foregroundStyle(Theme.gray200)
      .shadow(color: .black.opacity(0.5), radius: 3)
    }
    .buttonStyle(ScaleOnHover())
  }

  private func collapsedSeriesOverlay(_ cs: CollapsedSeries, em: CGFloat) -> some View {
    ZStack {
      VStack {
        HStack {
          Spacer()
          Text("\(cs.numBooks ?? 0)")
            .font(Theme.sans(0.8 * em, .semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 1.5 * em, minHeight: 1.5 * em)
            .background(Theme.seriesBadge)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        Spacer()
      }
      .padding(0.375 * em)
      if hover {
        Color.black.opacity(0.6)
        Text(cs.name ?? "").font(Theme.sans(1.2 * em)).foregroundStyle(.white)
          .multilineTextAlignment(.center).padding(em)
      }
    }
  }
}

struct ScaleOnHover: ButtonStyle {
  @State private var hover = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(hover ? 1.1 : 1)
      .foregroundStyle(hover ? .white : Theme.gray200)
      .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h } }
  }
}

/// The ⋯ / right-click menu of a book (LazyBookCard moreMenuItems), minus Share/RSS.
struct ItemMenu: View {
  let item: LibraryItem
  var shelfId: String?
  var app = AppModel.shared
  var player = PlayerModel.shared
  var downloads = DownloadManager.shared

  var body: some View {
    let finished = app.progress(for: item.id)?.isFinished == true
    Button(finished ? L.s("MessageMarkAsNotFinished") : L.s("MessageMarkAsFinished")) {
      Task { await ItemActions.setFinished(item.id, !finished) }
    }
    Divider()
    if item.media.hasAudio && app.user?.permissions?.download != false {
      switch downloads.state(item.id) {
      case .done:
        Button("Show in Finder") { downloads.showInFinder(item.id) }
        Button("Remove Download") { downloads.remove(item.id) }
      case .queued, .downloading:
        Button("Cancel Download") { downloads.cancel(item.id) }
      default:
        Button(L.s("LabelDownload")) { Task { await downloads.download(item.id) } }
      }
    }
    if shelfId == "continue-listening" || shelfId == "continue-reading",
      let p = app.progress(for: item.id)
    {
      Button(
        L.s(
          shelfId == "continue-reading"
            ? "ButtonRemoveFromContinueReading" : "ButtonRemoveFromContinueListening")
      ) {
        Task { await ItemActions.hideFromContinue(p) }
      }
    }
    if player.hasItem, item.media.hasAudio, player.item?.id != item.id {
      if player.isQueued(item.id) {
        Button(L.s("ButtonQueueRemoveItem")) { player.removeFromQueue(item.id) }
      } else {
        Button(L.s("ButtonQueueAddItem")) { player.addToQueue(item) }
      }
    }
  }
}

/// Author card (cards/AuthorCard.vue): 153.6·m × 192·m, image or silhouette,
/// bottom band with name and book count.
struct AuthorCard: View {
  let author: Author
  let m: CGFloat
  var app = AppModel.shared
  @State private var hover = false

  var body: some View {
    let w = 153.6 * m
    let h = 192 * m
    ZStack(alignment: .bottom) {
      Theme.primary
      if let url = app.authorImageURL(author) {
        RemoteImage(url: url, pixelWidth: Int(w * 2)) { silhouette(w) }
          .frame(width: w, height: h)
          .clipped()
      } else {
        silhouette(w)
      }
      VStack(spacing: 2) {
        Text(author.name).font(Theme.sans(0.75 * 16 * m, .semibold)).lineLimit(1)
        if let n = author.numBooks {
          Text("\(n) \(L.s("LabelBooks"))").font(Theme.sans(0.65 * 16 * m)).foregroundStyle(
            Theme.gray200)
        }
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6 * m)
      .background(Color.black.opacity(0.6))
    }
    .frame(width: w, height: h)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).stroke(hover ? Color.white.opacity(0.3) : .clear))
    .onHover { hover = $0 }
    .onTapGesture { app.go(.author(author.id)) }
  }

  private func silhouette(_ w: CGFloat) -> some View {
    Icon("person", size: w * 0.6, filled: true).foregroundStyle(.white.opacity(0.6))
  }
}

/// Series card (LazySeriesCard.vue): 2 × cover width, fanned covers, count badge.
struct SeriesCard: View {
  let series: Series
  let metrics: CardMetrics
  var app = AppModel.shared
  @State private var hover = false

  var body: some View {
    let h = metrics.coverHeight
    let w = metrics.coverWidth * 2
    let books = Array((series.books ?? []).prefix(10))
    let em = metrics.em
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .topLeading) {
        Theme.primary
        if books.count <= 1, let b = books.first {
          ZStack {
            BookCover(item: b, width: w, aspect: h / w, pixelWidth: Int(w)).blur(radius: 12)
              .opacity(0.7)
            BookCover(
              item: b, width: metrics.coverWidth, aspect: metrics.aspect,
              pixelWidth: Int(metrics.coverWidth * 2))
          }
          .frame(width: w, height: h)
        } else {
          let step = books.count > 1 ? (w - metrics.coverWidth) / CGFloat(books.count - 1) : 0
          ForEach(Array(books.enumerated().reversed()), id: \.offset) { i, b in
            BookCover(
              item: b, width: metrics.coverWidth, aspect: metrics.aspect,
              pixelWidth: Int(metrics.coverWidth * 2)
            )
            .shadow(color: .black.opacity(0.5), radius: 3, x: 2)
            .offset(x: CGFloat(i) * step)
          }
        }
        VStack {
          HStack {
            Spacer()
            Text("\(series.books?.count ?? 0)")
              .font(Theme.sans(0.8 * em, .semibold))
              .foregroundStyle(.white)
              .frame(minWidth: 1.5 * em, minHeight: 1.5 * em)
              .background(Theme.seriesBadge)
              .clipShape(RoundedRectangle(cornerRadius: 4))
          }
          Spacer()
          seriesProgressBar(w: w, em: em)
        }
        .padding(0.375 * em)
        if hover {
          Color.black.opacity(0.6)
          Text(series.name).font(Theme.sans(1.2 * em)).foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(em)
        }
      }
      .frame(width: w, height: h)
      .clipShape(RoundedRectangle(cornerRadius: 2))
      .shadow(color: Color(hex: 0x111111, opacity: 0.4), radius: 4, x: 3, y: 1)
      .onHover { hover = $0 }
      .onTapGesture { app.go(.seriesDetail(series.id)) }
      Text(series.name).font(Theme.sans(0.9 * em)).foregroundStyle(.white).lineLimit(1)
        .frame(width: w, alignment: .leading)
        .padding(.vertical, 0.5 * em)
    }
  }

  @ViewBuilder private func seriesProgressBar(w: CGFloat, em: CGFloat) -> some View {
    let books = series.books ?? []
    let done = books.filter { app.progress(for: $0.id)?.isFinished == true }.count
    let started = books.contains { (app.progress(for: $0.id)?.progress ?? 0) > 0 }
    if !books.isEmpty, done > 0 || started {
      let frac = CGFloat(done) / CGFloat(books.count)
      HStack(spacing: 0) {
        Rectangle().fill(done == books.count ? Theme.success : Theme.yellow400).frame(
          width: max(2, (w - 0.75 * em) * frac), height: 0.25 * em)
        Spacer(minLength: 0)
      }
    }
  }
}
