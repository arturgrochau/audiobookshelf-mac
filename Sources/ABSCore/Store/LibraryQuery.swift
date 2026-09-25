import Foundation

/// Client-side sort and filter over the cached minified item list, following
/// server/utils/queries/libraryItemsBookFilters.js so results match the web.
/// Title/author comparisons use SQLite's NOCASE rule (ASCII case fold only).
public enum LibraryQuery {
  public struct Context: Sendable {
    public var progress: [String: MediaProgress]
    public var authorsById: [String: String]
    public var seriesById: [String: String]
    public var ignorePrefix: Bool
    public var randomSeed: UInt64

    public init(
      progress: [String: MediaProgress] = [:], authorsById: [String: String] = [:],
      seriesById: [String: String] = [:], ignorePrefix: Bool = false, randomSeed: UInt64 = 1
    ) {
      self.progress = progress
      self.authorsById = authorsById
      self.seriesById = seriesById
      self.ignorePrefix = ignorePrefix
      self.randomSeed = randomSeed
    }
  }

  /// Filters that need data the minified list does not carry.
  public static func needsServer(filter: String) -> Bool {
    let group = filter.split(separator: ".", maxSplits: 1).first.map(String.init) ?? filter
    return ["feed-open", "share-open"].contains(group)
      || (group == "ebooks"
        && (filter.hasSuffix(FilterEncoding.encode("supplementary"))
          || filter.hasSuffix(FilterEncoding.encode("no-supplementary"))))
  }

  public static func apply(
    _ items: [LibraryItem], filter: String, sort: String, desc: Bool, ctx: Context
  ) -> [LibraryItem] {
    let filtered = items.filter { matches($0, filter: filter, ctx: ctx) }
    return sorted(
      filtered, sort: sort, desc: desc, ctx: ctx, seriesFilterId: seriesFilterId(filter))
  }

  public static func seriesFilterId(_ filter: String) -> String? {
    guard filter.hasPrefix("series.") else { return nil }
    let v = FilterEncoding.decode(String(filter.dropFirst("series.".count)))
    return v == "no-series" ? nil : v
  }

  // MARK: Filter

  public static func matches(_ item: LibraryItem, filter: String, ctx: Context) -> Bool {
    if filter.isEmpty || filter == "all" { return true }
    let parts = filter.split(separator: ".", maxSplits: 1).map(String.init)
    let group = parts[0]
    let value = parts.count > 1 ? (FilterEncoding.decode(parts[1]) ?? "") : ""
    let m = item.media.metadata
    let p = ctx.progress[item.id]
    switch group {
    case "genres": return (m.genres ?? []).contains(value)
    case "tags": return (item.media.tags ?? []).contains(value)
    case "narrators": return narrators(of: item).contains(value)
    case "authors":
      guard let name = ctx.authorsById[value] else { return false }
      return authors(of: item).contains(name)
    case "series":
      if value == "no-series" { return (m.seriesName ?? "").isEmpty && (m.series ?? []).isEmpty }
      if let refs = m.series, refs.contains(where: { $0.id == value }) { return true }
      guard let name = ctx.seriesById[value] else { return false }
      return seriesEntries(of: item).contains { $0.name == name }
    case "publishers": return m.publisher == value
    case "languages": return m.language == value
    case "publishedDecades":
      guard let start = Int(value), let y = Int(m.publishedYear ?? "") else { return false }
      return y >= start && y <= start + 9
    case "progress":
      switch value {
      case "finished": return p?.isFinished == true
      case "not-finished": return p?.isFinished != true
      case "not-started": return (p?.currentTime ?? 0) == 0 && p?.isFinished != true
      case "in-progress":
        guard let p else { return false }
        return ((p.currentTime ?? 0) > 0 || (p.ebookProgress ?? 0) > 0) && p.isFinished == false
      case "audio-in-progress":
        guard let p else { return false }
        return (p.currentTime ?? 0) > 0 && p.isFinished == false
      default: return true
      }
    case "tracks":
      let n = item.media.numAudioFiles ?? item.media.numTracks ?? 0
      switch value {
      case "none": return n == 0
      case "multi": return n > 1
      default: return n == 1
      }
    case "ebooks":
      switch value {
      case "ebook": return item.media.hasEbook
      case "no-ebook": return !item.media.hasEbook
      default: return true
      }
    case "missing":
      switch value {
      case "asin": return (m.asin ?? "").isEmpty
      case "isbn": return (m.isbn ?? "").isEmpty
      case "subtitle": return (m.subtitle ?? "").isEmpty
      case "publishedYear": return (m.publishedYear ?? "").isEmpty
      case "description": return (m.description ?? "").isEmpty
      case "publisher": return (m.publisher ?? "").isEmpty
      case "language": return (m.language ?? "").isEmpty
      case "cover": return (item.media.coverPath ?? "").isEmpty
      case "genres": return (m.genres ?? []).isEmpty
      case "tags": return (item.media.tags ?? []).isEmpty
      case "narrators": return narrators(of: item).isEmpty
      case "chapters": return (item.media.numChapters ?? 0) == 0
      case "authors": return authors(of: item).isEmpty
      case "series": return seriesEntries(of: item).isEmpty
      default: return true
      }
    case "abridged": return m.abridged == true
    case "explicit": return m.explicit == true
    case "issues": return item.isMissing == true || item.isInvalid == true
    default: return true
    }
  }

  public static func narrators(of item: LibraryItem) -> [String] {
    if let n = item.media.metadata.narrators, !n.isEmpty { return n }
    return splitNames(item.media.metadata.narratorName)
  }

  public static func authors(of item: LibraryItem) -> [String] {
    if let a = item.media.metadata.authors, !a.isEmpty { return a.map(\.name) }
    return splitNames(item.media.metadata.authorName)
  }

  static func splitNames(_ s: String?) -> [String] {
    (s ?? "").components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }.filter {
      !$0.isEmpty
    }
  }

  /// "Name #1, Other #2.5" → [(Name, "1"), (Other, "2.5")].
  public static func seriesEntries(of item: LibraryItem) -> [(name: String, sequence: String?)] {
    if let refs = item.media.metadata.series, !refs.isEmpty {
      return refs.map { ($0.name, $0.sequence) }
    }
    return splitNames(item.media.metadata.seriesName).map { entry in
      if let r = entry.range(of: " #", options: .backwards) {
        return (String(entry[..<r.lowerBound]), String(entry[r.upperBound...]))
      }
      return (entry, nil)
    }
  }

  // MARK: Sort

  public static func sorted(
    _ items: [LibraryItem], sort: String, desc: Bool, ctx: Context, seriesFilterId: String?
  ) -> [LibraryItem] {
    func title(_ i: LibraryItem) -> String {
      ctx.ignorePrefix ? (i.media.metadata.titleIgnorePrefix ?? i.title) : i.title
    }

    switch sort {
    case "random":
      var rng = SeededRandom(seed: ctx.randomSeed)
      return items.shuffled(using: &rng)
    case "media.metadata.authorName", "media.metadata.authorNameLF":
      let lf = sort.hasSuffix("LF")
      return items.sorted { a, b in
        let x = (lf ? a.media.metadata.authorNameLF : a.media.metadata.authorName) ?? ""
        let y = (lf ? b.media.metadata.authorNameLF : b.media.metadata.authorName) ?? ""
        let c = nocase(x, y)
        if c != 0 { return desc ? c > 0 : c < 0 }
        // Server: the title tie-break follows the same direction.
        let t = nocase(title(a), title(b))
        return desc ? t > 0 : t < 0
      }
    case "sequence":
      let name = seriesFilterId.flatMap { ctx.seriesById[$0] }
      func seq(_ i: LibraryItem) -> Double? {
        if let refs = i.media.metadata.series,
          let r = refs.first(where: { $0.id == seriesFilterId })
        {
          return r.sequence.flatMap { Double($0) }
        }
        return seriesEntries(of: i).first { $0.name == name }?.sequence.flatMap { Double($0) }
      }
      return items.sorted { a, b in
        switch (seq(a), seq(b)) {
        case (let x?, let y?): return desc ? x > y : x < y
        case (nil, _?): return desc
        case (_?, nil): return !desc
        default: return false
        }
      }
    case "progress", "progress.createdAt", "progress.finishedAt":
      func key(_ i: LibraryItem) -> Double? {
        let p = ctx.progress[i.id]
        switch sort {
        case "progress": return p?.lastUpdate
        case "progress.createdAt": return p?.startedAt
        default: return p?.finishedAt
        }
      }
      return items.sorted { a, b in
        switch (key(a), key(b)) {
        case (let x?, let y?): return desc ? x > y : x < y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return false
        }
      }
    default:
      func num(_ i: LibraryItem) -> Double? {
        switch sort {
        case "addedAt": return i.addedAt
        case "size": return i.size.map(Double.init)
        case "birthtimeMs": return i.birthtimeMs
        case "mtimeMs": return i.mtimeMs
        case "media.duration": return i.media.duration
        case "media.metadata.publishedYear": return Double(i.media.metadata.publishedYear ?? "")
        default: return nil
        }
      }
      let numericSorts = ["addedAt", "size", "birthtimeMs", "mtimeMs", "media.duration", "media.metadata.publishedYear"]
      guard numericSorts.contains(sort) else {
        return items.sorted {
          let c = nocase(title($0), title($1))
          return desc ? c > 0 : c < 0
        }
      }
      // SQLite: NULLs sort first ascending.
      return items.sorted { a, b in
        switch (num(a), num(b)) {
        case (let x?, let y?): return desc ? x > y : x < y
        case (nil, _?): return !desc
        case (_?, nil): return desc
        default: return false
        }
      }
    }
  }

  /// SQLite COLLATE NOCASE: byte comparison with only A–Z folded.
  public static func nocase(_ a: String, _ b: String) -> Int {
    var ia = a.utf8.makeIterator()
    var ib = b.utf8.makeIterator()
    while true {
      let x = ia.next()
      let y = ib.next()
      switch (x, y) {
      case (nil, nil): return 0
      case (nil, _): return -1
      case (_, nil): return 1
      case (let x?, let y?):
        let fx = (x >= 65 && x <= 90) ? x + 32 : x
        let fy = (y >= 65 && y <= 90) ? y + 32 : y
        if fx != fy { return fx < fy ? -1 : 1 }
      }
    }
  }
}

/// Deterministic shuffle so "Randomly" stays stable until re-chosen.
public struct SeededRandom: RandomNumberGenerator {
  private var state: UInt64
  public init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
  public mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
