import ABSCore
import SwiftUI

/// pages/item/_id/index.vue: cover left, details right, buttons, description,
/// then the Chapters and Audio Tracks tables. No edit pencils: editing is in ⋯.
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
              ChaptersTable(item: item, chapters: ch).padding(.top, 24)
            }
            if let tracks = item.media.tracks, !tracks.isEmpty {
              TracksTable(tracks: tracks).padding(.top, 24)
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
    return CoverWithPlay(item: item, aspect: aspect, canPlay: showPlay(item) && !isStreaming(item))
      .overlay(alignment: .bottomLeading) {
        if pct > 0 {
          Rectangle().fill(finished ? Theme.success : Theme.yellow400)
            .frame(width: 208 * pct, height: 6)
        }
      }
      .frame(width: 208)
  }

  // MARK: Header

  @ViewBuilder private func header(_ item: LibraryItem) -> some View {
    let md = item.media.metadata
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Text(item.title).font(Theme.sans(30, .semibold)).textSelection(.enabled)
        if md.explicit == true { Badge(text: "E") }
        if md.abridged == true { Badge(text: "A") }
      }
      if let sub = md.subtitle, !sub.isEmpty {
        Text(sub).font(Theme.sans(24)).foregroundStyle(Theme.gray200)
      }
      if let series = md.series, !series.isEmpty {
        HStack(spacing: 0) {
          ForEach(Array(series.enumerated()), id: \.offset) { i, s in
            LinkText(
              text: s.sequence.map { "\(s.name) #\($0)" } ?? s.name, size: 18, color: Theme.gray300
            ) {
              app.go(.seriesDetail(s.id))
            }
            if i < series.count - 1 {
              Text(", ").font(Theme.sans(18)).foregroundStyle(Theme.gray300)
            }
          }
        }
      }
      HStack(spacing: 0) {
        Text(L.s("LabelByAuthor", "")).font(Theme.sans(20)).foregroundStyle(Theme.gray200)
        let authors = md.authors ?? []
        if authors.isEmpty {
          Text("Unknown").font(Theme.sans(20)).foregroundStyle(Theme.gray200)
        }
        ForEach(Array(authors.enumerated()), id: \.offset) { i, a in
          LinkText(text: a.name, size: 20, color: Theme.gray200) { app.go(.author(a.id)) }
          if i < authors.count - 1 {
            Text(", ").font(Theme.sans(20)).foregroundStyle(Theme.gray200)
          }
        }
      }
      .padding(.top, 2)
      .padding(.bottom, 8)
      DetailsGrid(item: item).padding(.bottom, 16)
    }
  }

  // MARK: Progress

  @ViewBuilder private func progressBox(_ item: LibraryItem) -> some View {
    if let p = app.progress(for: item.id) {
      let pct = p.isFinished == true ? 1 : (p.progress ?? 0)
      if pct > 0 {
        VStack(alignment: .leading, spacing: 0) {
          if pct < 1 {
            Text("\(L.s("LabelYourProgress")): \(Int((pct * 100).rounded()))%")
              .font(Theme.sans(14, .semibold))
            let remaining = max(0, (p.duration ?? item.duration) - (p.currentTime ?? 0))
            Text(L.s("LabelTimeRemaining", Format.elapsedPretty(remaining)))
              .font(Theme.sans(12, .semibold)).foregroundStyle(Theme.gray200)
          } else {
            Text("\(L.s("LabelFinished")) \(Self.date(p.finishedAt))").font(
              Theme.sans(12, .semibold))
          }
          Text("\(L.s("LabelStarted")) \(Self.date(p.startedAt))")
            .font(Theme.sans(12, .semibold)).foregroundStyle(Theme.gray400).padding(.top, 4)
        }
        .foregroundStyle(Theme.gray100)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
          Button {
            Task { await ItemActions.resetProgress(p) }
          } label: {
            Icon("close", size: 14)
              .frame(width: 20, height: 20)
              .background(Circle().fill(Theme.bg))
              .overlay(Circle().stroke(Theme.primary))
          }
          .buttonStyle(ResetButtonStyle())
          .offset(x: 6, y: -6)
        }
        .padding(.top, 16)
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
    let finished = app.progress(for: item.id)?.isFinished == true
    HStack(spacing: 4) {
      if showPlay(item) {
        let streaming = isStreaming(item)
        WebButton(color: Theme.success, small: true, disabled: streaming, paddingX: 16) {
          Task { await player.play(item.id) }
        } label: {
          HStack(spacing: 4) {
            if !streaming { Icon("play_arrow", size: 24, filled: true).padding(.leading, -8) }
            Text(L.s(streaming ? "ButtonPlaying" : "ButtonPlay"))
          }
          .frame(height: 28)
        }
        .padding(.trailing, 4)
      }
      if item.media.hasEbook {
        WebButton(color: Theme.info, small: true, paddingX: 16) {
          ReaderWindows.open(itemId: item.id)
        } label: {
          HStack(spacing: 4) {
            Icon("auto_stories", size: 24).padding(.leading, -8)
            Text(L.s("ButtonRead"))
          }
          .frame(height: 28)
        }
        .padding(.trailing, 4)
      }
      if player.hasItem && !isStreaming(item) && item.media.hasAudio {
        let queued = player.isQueued(item.id)
        IconButton(
          icon: queued ? "playlist_add_check" : "playlist_play",
          bg: queued ? Theme.primary : Theme.success.opacity(0.6)
        ) {
          if queued { player.removeFromQueue(item.id) } else { player.addToQueue(item) }
        }
        .help(L.s(queued ? "ButtonQueueRemoveItem" : "ButtonQueueAddItem"))
      }
      IconButton(icon: "beenhere", bg: finished ? Theme.success : Theme.primary) {
        Task { await ItemActions.setFinished(item.id, !finished) }
      }
      .help(L.s(finished ? "MessageMarkAsNotFinished" : "MessageMarkAsFinished"))
      Menu {
        ItemMenu(item: item)
      } label: {
        Icon("more_vert", size: 24)
          .frame(width: 36, height: 36)
          .background(Theme.primary)
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.gray600))
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
    }
    .padding(.top, 16)
  }

  // MARK: Description

  @ViewBuilder private func description(_ item: LibraryItem) -> some View {
    let text = Self.plain(item.media.metadata.description)
    if !text.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text(text)
          .font(Theme.sans(16))
          .foregroundStyle(Theme.gray100)
          .lineLimit(showFullDescription ? nil : 4)
          .textSelection(.enabled)
          .background {
            ViewThatFits(in: .vertical) {
              Text(text).font(Theme.sans(16)).hidden().onAppear { descriptionClamped = false }
              Color.clear.onAppear { descriptionClamped = true }
            }
          }
        if descriptionClamped || showFullDescription {
          Button {
            showFullDescription.toggle()
          } label: {
            HStack(spacing: 4) {
              Text(L.s(showFullDescription ? "ButtonReadLess" : "ButtonReadMore"))
              Icon(showFullDescription ? "expand_less" : "expand_more", size: 20)
            }
            .font(Theme.sans(16))
            .foregroundStyle(Color(hex: 0xCAD5E2))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.vertical, 16)
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
          Icon("play_arrow", size: 36, filled: true)
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
    Text(text).font(Theme.sans(12, .semibold))
      .frame(width: 16, height: 16)
      .background(Theme.gray600)
      .clipShape(RoundedRectangle(cornerRadius: 2))
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
    Text(text).font(Theme.sans(size)).foregroundStyle(color).underline(hover)
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
        row("LabelNarrators") { links(n) { FilterEncoding.filter("narrators", $0) } }.padding(
          .top, 16)
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
    .font(Theme.sans(16))
  }

  private func row<V: View>(_ key: String, @ViewBuilder _ value: () -> V) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      Text(L.s(key).uppercased()).font(Theme.sans(14)).foregroundStyle(.white.opacity(0.6))
        .frame(width: 136, alignment: .leading)
      value()
    }
    .padding(.vertical, 2)
  }

  private func links(_ values: [String], filter: @escaping (String) -> String) -> some View {
    HStack(spacing: 0) {
      ForEach(Array(values.enumerated()), id: \.offset) { i, v in
        LinkText(text: v) { app.go(.filtered(filter(v))) }
        if i < values.count - 1 { Text(", ") }
      }
    }
    .lineLimit(1)
  }
}

/// tables/ChaptersTable.vue: collapsible bar with a count pill; click a start time to seek.
struct ChaptersTable: View {
  let item: LibraryItem
  let chapters: [Chapter]
  @State private var expanded = false

  var body: some View {
    VStack(spacing: 0) {
      TableHeader(title: L.s("HeaderChapters"), count: chapters.count, expanded: $expanded)
      if expanded {
        WebTable(columns: [
          ("Id", 64, .leading), (L.s("LabelTitle"), nil, .leading),
          (L.s("LabelStart"), 100, .center), (L.s("LabelDuration"), 100, .center),
        ]) {
          ForEach(Array(chapters.enumerated()), id: \.offset) { i, c in
            WebTableRow(index: i) {
              Text("\(c.id)").frame(width: 64, alignment: .leading).padding(.leading, 16)
              Text(c.title).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
              Text(Format.timestamp(c.start)).font(Theme.mono(14)).frame(width: 100)
                .underline(false).linkCursor()
                .onTapGesture { Task { await ItemActions.playFrom(item, time: c.start) } }
              Text(Format.timestamp(max(0, c.end - c.start))).font(Theme.mono(14)).frame(width: 100)
            }
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
    VStack(spacing: 0) {
      TableHeader(title: L.s("LabelStatsAudioTracks"), count: tracks.count, expanded: $expanded)
      if expanded {
        WebTable(columns: [
          ("#", 64, .leading), (L.s("LabelFilename"), nil, .leading),
          (L.s("LabelSize"), 100, .center), (L.s("LabelDuration"), 100, .center),
        ]) {
          ForEach(Array(tracks.sorted { $0.index < $1.index }.enumerated()), id: \.offset) { i, t in
            WebTableRow(index: i) {
              Text("\(t.index)").frame(width: 64, alignment: .leading).padding(.leading, 16)
              Text(t.metadata?.filename ?? t.title ?? "").frame(
                maxWidth: .infinity, alignment: .leading
              ).lineLimit(1)
              Text(Format.bytesPretty(Double(t.metadata?.size ?? 0))).frame(width: 100)
              Text(Format.timestamp(t.duration)).font(Theme.mono(14)).frame(width: 100)
            }
          }
        }
      }
    }
  }
}

struct TableHeader: View {
  let title: String
  let count: Int
  @Binding var expanded: Bool

  var body: some View {
    HStack(spacing: 0) {
      Text(title).font(Theme.sans(16)).padding(.trailing, 16)
      Text("\(count)").font(Theme.mono(14))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.black400).clipShape(RoundedRectangle(cornerRadius: 12))
      Spacer()
      Icon("expand_more", size: 36)
        .rotationEffect(.degrees(expanded ? 180 : 0))
        .frame(width: 40, height: 40)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 8)
    .background(Theme.primary)
    .contentShape(Rectangle())
    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
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
