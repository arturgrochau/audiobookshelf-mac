import ABSCore
import SwiftUI

/// pages/item/_id/index.vue in the player's language: cover left, details
/// right, one white Play pill and quiet symbol buttons, then the chapter and
/// track lists as disclosures. No edit pencils: editing is in ⋯.
struct ItemPage: View {
  let itemId: String
  var app = AppModel.shared
  var store = LibraryStore.shared
  var player = PlayerModel.shared
  @State private var showFullDescription = false
  @State private var descriptionClamped = false

  private var item: LibraryItem? { store.expanded[itemId] ?? store.item(itemId) }

  var body: some View {
    ScrollView(.vertical) {
      if let item {
        HStack(alignment: .top, spacing: 0) {
          cover(item)
          VStack(alignment: .leading, spacing: 0) {
            header(item)
            progressBox(item)
            buttons(item)
            description(item)
            if let ch = item.media.chapters, !ch.isEmpty {
              ChaptersTable(item: item, chapters: ch).padding(.top, 20)
            }
            if let tracks = item.media.tracks, !tracks.isEmpty {
              TracksTable(tracks: tracks).padding(.top, 8)
            }
          }
          .padding(.horizontal, 40)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 1152)
        .frame(maxWidth: .infinity)
        .padding(32)
      }
    }
    .background(Theme.bg)
    .task(id: itemId) { _ = await store.expandedItem(itemId) }
  }

  // MARK: Cover

  private func cover(_ item: LibraryItem) -> some View {
    let aspect = app.currentLibrary?.coverAspect ?? 1
    let p = app.progress(for: item.id)
    let finished = p?.isFinished == true
    let pct = finished ? 1 : (p?.progress ?? 0)
    return VStack(spacing: 8) {
      CoverWithPlay(item: item, aspect: aspect, canPlay: showPlay(item) && !isStreaming(item))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
      if pct > 0 {
        Capsule().fill(Color.white.opacity(0.1))
          .overlay(alignment: .leading) {
            Capsule().fill(finished ? Theme.success : Theme.accent).frame(width: 208 * pct)
          }
          .frame(height: 3)
      }
    }
    .frame(width: 208)
  }

  // MARK: Header

  @ViewBuilder private func header(_ item: LibraryItem) -> some View {
    let md = item.media.metadata
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Text(item.title).font(.system(size: 26, weight: .bold)).textSelection(.enabled)
        if md.explicit == true { Badge(text: "E") }
        if md.abridged == true { Badge(text: "A") }
      }
      if let sub = md.subtitle, !sub.isEmpty {
        Text(sub).font(.system(size: 15)).foregroundStyle(Theme.gray300).padding(.top, 2)
      }
      HStack(spacing: 0) {
        let authors = md.authors ?? []
        if authors.isEmpty {
          Text("Unknown").foregroundStyle(Theme.gray200)
        }
        ForEach(Array(authors.enumerated()), id: \.offset) { i, a in
          LinkText(text: a.name, size: 15, color: Theme.gray200) { app.go(.author(a.id)) }
          if i < authors.count - 1 { Text(", ").foregroundStyle(Theme.gray200) }
        }
      }
      .font(.system(size: 15))
      .padding(.top, 6)
      if let series = md.series, !series.isEmpty {
        HStack(spacing: 0) {
          ForEach(Array(series.enumerated()), id: \.offset) { i, s in
            LinkText(
              text: s.sequence.map { "\(s.name) #\($0)" } ?? s.name, size: 13,
              color: Theme.gray400
            ) {
              app.go(.seriesDetail(s.id))
            }
            if i < series.count - 1 { Text(", ").foregroundStyle(Theme.gray400) }
          }
        }
        .font(.system(size: 13))
        .padding(.top, 2)
      }
      DetailsGrid(item: item).padding(.top, 16)
    }
  }

  // MARK: Progress

  @ViewBuilder private func progressBox(_ item: LibraryItem) -> some View {
    if let p = app.progress(for: item.id) {
      let pct = p.isFinished == true ? 1 : (p.progress ?? 0)
      if pct > 0 {
        HStack(spacing: 6) {
          if pct < 1 {
            let remaining = max(0, (p.duration ?? item.duration) - (p.currentTime ?? 0))
            Text("\(Int((pct * 100).rounded()))%").foregroundStyle(Theme.gray200)
            Text("·")
            Text("\(Format.elapsedPretty(remaining)) left")
          } else {
            Text("\(L.s("LabelFinished")) \(Self.date(p.finishedAt))").foregroundStyle(
              Theme.gray200)
          }
          Text("·")
          Text("\(L.s("LabelStarted")) \(Self.date(p.startedAt))")
          SymbolButton(symbol: "xmark", size: 9, weight: .bold, help: "Reset progress") {
            Task { await ItemActions.resetProgress(p) }
          }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.gray400)
        .padding(.top, 14)
      }
    }
  }

  static func date(_ ms: Double?) -> String {
    guard let ms else { return "" }
    let f = DateFormatter()
    f.dateFormat = "MM/dd/yyyy"
    return f.string(from: Date(timeIntervalSince1970: ms / 1000))
  }

  // MARK: Buttons

  private func showPlay(_ item: LibraryItem) -> Bool {
    item.media.hasAudio && item.isMissing != true && item.isInvalid != true
  }

  private func isStreaming(_ item: LibraryItem) -> Bool { player.item?.id == item.id }

  @ViewBuilder private func buttons(_ item: LibraryItem) -> some View {
    let progress = app.progress(for: item.id)
    let finished = progress?.isFinished == true
    let started = !finished && (progress?.progress ?? 0) > 0
    HStack(spacing: 6) {
      if showPlay(item) {
        let streaming = isStreaming(item)
        PillButton(
          title: streaming ? L.s("ButtonPlaying") : started ? "Resume" : L.s("ButtonPlay"),
          symbol: streaming ? "waveform" : "play.fill", prominent: true, disabled: streaming
        ) {
          Task { await player.play(item.id) }
        }
      }
      if item.media.hasEbook {
        PillButton(title: L.s("ButtonRead"), symbol: "book") {
          ReaderWindows.open(itemId: item.id)
        }
      }
      if player.hasItem && !isStreaming(item) && item.media.hasAudio {
        let queued = player.isQueued(item.id)
        SymbolButton(
          symbol: queued ? "text.badge.checkmark" : "text.badge.plus", size: 15, active: queued,
          help: L.s(queued ? "ButtonQueueRemoveItem" : "ButtonQueueAddItem")
        ) {
          if queued { player.removeFromQueue(item.id) } else { player.addToQueue(item) }
        }
      }
      SymbolButton(
        symbol: finished ? "checkmark.circle.fill" : "checkmark.circle", size: 16,
        active: finished,
        help: L.s(finished ? "MessageMarkAsNotFinished" : "MessageMarkAsFinished")
      ) {
        Task { await ItemActions.setFinished(item.id, !finished) }
      }
      Menu {
        ItemMenu(item: item)
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(Theme.gray300)
          .frame(width: 31, height: 31)
          .contentShape(Circle())
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
      .help("More")
    }
    .padding(.top, 18)
  }

  // MARK: Description

  @ViewBuilder private func description(_ item: LibraryItem) -> some View {
    let text = Self.plain(item.media.metadata.description)
    if !text.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text(text)
          .font(.system(size: 13))
          .lineSpacing(3)
          .foregroundStyle(Theme.gray200)
          .lineLimit(showFullDescription ? nil : 4)
          .textSelection(.enabled)
          .background {
            ViewThatFits(in: .vertical) {
              Text(text).font(.system(size: 13)).lineSpacing(3).hidden().onAppear { descriptionClamped = false }
              Color.clear.onAppear { descriptionClamped = true }
            }
          }
        if descriptionClamped || showFullDescription {
          Button {
            showFullDescription.toggle()
          } label: {
            Text(L.s(showFullDescription ? "ButtonReadLess" : "ButtonReadMore"))
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(Theme.gray400)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.top, 20)
    }
  }

  /// The web renders sanitised HTML; paragraphs and breaks become newlines here.
  static func plain(_ html: String?) -> String {
    guard var s = html, !s.isEmpty else { return "" }
    for tag in ["<br>", "<br/>", "<br />", "</p>", "</div>", "</li>"] {
      s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
    }
    s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    let entities = [
      "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " ",
    ]
    for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
    s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private struct ResetButtonStyle: ButtonStyle {
  @State private var hover = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(Circle().fill(hover ? Theme.error : .clear))
      .onHover { hover = $0 }
  }
}

/// The item cover with the hover play button (group-hover:brightness-75).
private struct CoverWithPlay: View {
  let item: LibraryItem
  let aspect: Double
  let canPlay: Bool
  @State private var hover = false

  var body: some View {
    ZStack {
      BookCover(item: item, width: 208, aspect: aspect, pixelWidth: 416)
        .brightness(hover ? -0.25 : 0)
      if hover && canPlay {
        Button {
          Task { await PlayerModel.shared.play(item.id) }
        } label: {
          Image(systemName: "play.fill").font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Theme.primary)
            .offset(x: 2)
            .frame(width: 56, height: 56)
            .background(Circle().fill(.white))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        }
        .buttonStyle(ScaleOnHover())
      }
    }
    .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
  }
}

private struct Badge: View {
  let text: String
  var body: some View {
    Text(text).font(.system(size: 10, weight: .bold))
      .frame(width: 16, height: 16)
      .background(Theme.gray600)
      .clipShape(RoundedRectangle(cornerRadius: 3))
  }
}

/// A nuxt-link: underline on hover, pointing-hand cursor.
struct LinkText: View {
  let text: String
  var size: CGFloat = 16
  var color: Color = .white
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Text(text).font(.system(size: size)).foregroundStyle(color).underline(hover)
      .onHover { hover = $0 }
      .linkCursor()
      .onTapGesture(perform: action)
  }
}

/// content/LibraryItemDetails.vue: uppercase labels in a 136 px column.
struct DetailsGrid: View {
  let item: LibraryItem
  var app = AppModel.shared

  var body: some View {
    let md = item.media.metadata
    VStack(alignment: .leading, spacing: 2) {
      if let n = md.narrators, !n.isEmpty {
        row("LabelNarrators") { links(n) { FilterEncoding.filter("narrators", $0) } }
      }
      if let y = md.publishedYear, !y.isEmpty { row("LabelPublishYear") { Text(y) } }
      if let p = md.publisher, !p.isEmpty {
        row("LabelPublisher") { links([p]) { FilterEncoding.filter("publishers", $0) } }
      }
      if let g = md.genres, !g.isEmpty {
        row("LabelGenres") { links(g) { FilterEncoding.filter("genres", $0) } }
      }
      if let t = item.media.tags, !t.isEmpty {
        row("LabelTags") { links(t) { FilterEncoding.filter("tags", $0) } }
      }
      if let l = md.language, !l.isEmpty {
        row("LabelLanguage") { links([l]) { FilterEncoding.filter("languages", $0) } }
      }
      if !(item.media.tracks ?? []).isEmpty || (item.media.numTracks ?? 0) > 0 {
        row("LabelDuration") { Text(Format.elapsedPretty(item.duration)) }
      }
      row("LabelSize") { Text(Format.bytesPretty(Double(item.media.size ?? item.size ?? 0))) }
    }
    .font(.system(size: 13))
    .foregroundStyle(Theme.gray200)
  }

  private func row<V: View>(_ key: String, @ViewBuilder _ value: () -> V) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      Text(L.s(key)).font(.system(size: 12)).foregroundStyle(Theme.gray500)
        .frame(width: 96, alignment: .leading)
      value()
    }
    .padding(.vertical, 2)
  }

  private func links(_ values: [String], filter: @escaping (String) -> String) -> some View {
    HStack(spacing: 0) {
      ForEach(Array(values.enumerated()), id: \.offset) { i, v in
        LinkText(text: v, size: 13, color: Theme.gray200) { app.go(.filtered(filter(v))) }
        if i < values.count - 1 { Text(", ") }
      }
    }
    .lineLimit(1)
  }
}

/// tables/ChaptersTable.vue as a disclosure list; click a chapter to play from it.
struct ChaptersTable: View {
  let item: LibraryItem
  let chapters: [Chapter]
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      TableHeader(title: L.s("HeaderChapters"), count: chapters.count, expanded: $expanded)
      if expanded {
        ListRows {
          ForEach(Array(chapters.enumerated()), id: \.offset) { i, c in
            ListRow {
              Task { await ItemActions.playFrom(item, time: c.start) }
            } content: {
              Text("\(i + 1)").foregroundStyle(Theme.gray500).frame(width: 28, alignment: .leading)
              Text(c.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
              Text(Format.timestamp(c.start)).foregroundStyle(Theme.gray400)
                .frame(width: 72, alignment: .trailing)
              Text(Format.timestamp(max(0, c.end - c.start))).foregroundStyle(Theme.gray500)
                .frame(width: 72, alignment: .trailing)
            }
            .help("Play from \(Format.timestamp(c.start))")
          }
        }
      }
    }
  }
}

/// tables/TracksTable.vue without the admin buttons.
struct TracksTable: View {
  let tracks: [AudioTrack]
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      TableHeader(title: L.s("LabelStatsAudioTracks"), count: tracks.count, expanded: $expanded)
      if expanded {
        ListRows {
          ForEach(Array(tracks.sorted { $0.index < $1.index }.enumerated()), id: \.offset) { _, t in
            ListRow {
              Text("\(t.index)").foregroundStyle(Theme.gray500).frame(width: 28, alignment: .leading)
              Text(t.metadata?.filename ?? t.title ?? "").lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
              Text(Format.bytesPretty(Double(t.metadata?.size ?? 0))).foregroundStyle(Theme.gray400)
                .frame(width: 72, alignment: .trailing)
              Text(Format.timestamp(t.duration)).foregroundStyle(Theme.gray500)
                .frame(width: 72, alignment: .trailing)
            }
          }
        }
      }
    }
  }
}

/// "Chapters 19 ›": a disclosure row, the chevron turns down when open.
struct TableHeader: View {
  let title: String
  let count: Int
  @Binding var expanded: Bool
  @State private var hover = false

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
        .rotationEffect(.degrees(expanded ? 90 : 0))
        .foregroundStyle(Theme.gray400)
        .frame(width: 12)
      Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(
        hover ? .white : Theme.gray200)
      Text("\(count)").font(.system(size: 12)).foregroundStyle(Theme.gray500)
      Spacer()
    }
    .padding(.vertical, 8)
    .contentShape(Rectangle())
    .onHover { hover = $0 }
    .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } }
  }
}

/// The rows under a disclosure: hairline separators, no zebra, no frame.
struct ListRows<Rows: View>: View {
  @ViewBuilder var rows: () -> Rows

  var body: some View {
    LazyVStack(spacing: 0) { rows() }
      .font(.system(size: 12).monospacedDigit())
      .foregroundStyle(Theme.gray200)
      .padding(.leading, 20)
      .padding(.bottom, 8)
  }
}

struct ListRow<Content: View>: View {
  var action: (() -> Void)?
  @ViewBuilder var content: () -> Content
  @State private var hover = false

  var body: some View {
    HStack(spacing: 8) { content() }
      .padding(.horizontal, 8)
      .frame(height: 28)
      .background(
        RoundedRectangle(cornerRadius: 5).fill(
          Color.white.opacity(hover && action != nil ? 0.06 : 0))
      )
      .contentShape(Rectangle())
      .onHover { hover = $0 }
      .onTapGesture { action?() }
  }
}

/// A capsule text button: white when it is the thing to press, glass otherwise.
struct PillButton: View {
  let title: String
  var symbol: String?
  var prominent = false
  var disabled = false
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
        Text(title).font(.system(size: 13, weight: .semibold))
      }
      .foregroundStyle(prominent ? Theme.primary : .white)
      .padding(.horizontal, 16)
      .frame(height: 30)
      .background(
        Capsule().fill(
          prominent
            ? Color.white.opacity(disabled ? 0.55 : hover ? 0.9 : 1)
            : Color.white.opacity(hover ? 0.14 : 0.08))
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .onHover { hover = $0 }
    .animation(.easeOut(duration: 0.12), value: hover)
  }
}
/// `.tracksTable`: header row on primary, zebra rows, 14 px text.
struct WebTable<Rows: View>: View {
  let columns: [(String, CGFloat?, Alignment)]
  @ViewBuilder var rows: () -> Rows

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        ForEach(Array(columns.enumerated()), id: \.offset) { i, c in
          let label = Text(c.0).font(Theme.sans(14, .semibold))
          if let w = c.1 {
            label.frame(width: w, alignment: c.2).padding(.leading, i == 0 ? 16 : 0)
          } else {
            label.frame(maxWidth: .infinity, alignment: c.2).padding(.leading, i == 0 ? 16 : 0)
          }
        }
      }
      .padding(.vertical, 6)
      .background(Theme.primary)
      rows()
    }
    .font(Theme.sans(14))
    .overlay(Rectangle().stroke(Theme.tableBorder))
  }
}

struct WebTableRow<Content: View>: View {
  let index: Int
  @ViewBuilder var content: () -> Content

  var body: some View {
    HStack(spacing: 0) { content() }
      .padding(.vertical, 6)
      .background(index % 2 == 1 ? Theme.tableEven : Theme.bg)
      .hoverHighlight(Theme.black300)
  }
}
