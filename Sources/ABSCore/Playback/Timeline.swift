import Foundation

/// The book as one continuous timeline over its audio files and chapters.
/// Mirrors client/players/LocalAudioPlayer.js (track lookup by startOffset)
/// and PlayerUi.vue (chapter navigation).
public struct Timeline: Sendable, Hashable {
  public struct Track: Sendable, Hashable {
    public var index: Int
    public var startOffset: Double
    public var duration: Double
    public var end: Double { startOffset + duration }
    public init(index: Int, startOffset: Double, duration: Double) {
      self.index = index
      self.startOffset = startOffset
      self.duration = duration
    }
  }

  public var tracks: [Track]
  public var chapters: [Chapter]

  public init(tracks: [Track], chapters: [Chapter]) {
    self.tracks = tracks.sorted { $0.startOffset < $1.startOffset }
    self.chapters = chapters.sorted { $0.start < $1.start }
  }

  public init(audioTracks: [AudioTrack], chapters: [Chapter]) {
    self.init(
      tracks: audioTracks.map {
        Track(index: $0.index, startOffset: $0.startOffset, duration: $0.duration)
      },
      chapters: chapters)
  }

  public var duration: Double { tracks.last.map { $0.end } ?? 0 }

  /// Position of global time `t` as (array position, seconds into that track).
  public func locate(_ t: Double) -> (position: Int, offset: Double) {
    guard !tracks.isEmpty else { return (0, max(0, t)) }
    let t = max(0, min(t, duration))
    for (i, tr) in tracks.enumerated() where t >= tr.startOffset && t < tr.end {
      return (i, t - tr.startOffset)
    }
    let last = tracks.count - 1
    return (last, max(0, min(tracks[last].duration, t - tracks[last].startOffset)))
  }

  public func globalTime(position: Int, offset: Double) -> Double {
    guard tracks.indices.contains(position) else { return offset }
    return tracks[position].startOffset + offset
  }

  // MARK: Chapters

  /// `chapters.find(c => c.start <= t && t < c.end)`.
  public func chapterIndex(at t: Double) -> Int? {
    chapters.firstIndex { $0.start <= t && t < $0.end }
  }

  public func chapter(at t: Double) -> Chapter? { chapterIndex(at: t).map { chapters[$0] } }

  /// Previous-chapter button: start of the current chapter, or of the one
  /// before it when we are within 3 s of the current chapter's start.
  public func previousChapterTarget(from t: Double) -> Double {
    guard let i = chapterIndex(at: t), i > 0 else { return 0 }
    if t - chapters[i].start <= 3 { return chapters[i - 1].start }
    return chapters[i].start
  }

  /// Next-chapter button: the next chapter's start, nil in the last chapter.
  public func nextChapterTarget(from t: Double) -> Double? {
    if let i = chapterIndex(at: t) {
      return i + 1 < chapters.count ? chapters[i + 1].start : nil
    }
    return chapters.first { $0.start > t }?.start
  }

  // MARK: Chapter-track projections (useChapterTrack)

  /// What the track bar spans: the chapter when the chapter track is on.
  public func trackSpan(at t: Double, useChapterTrack: Bool) -> (base: Double, length: Double) {
    if useChapterTrack, let c = chapter(at: t) { return (c.start, max(0.001, c.end - c.start)) }
    return (0, max(0.001, duration))
  }
}
