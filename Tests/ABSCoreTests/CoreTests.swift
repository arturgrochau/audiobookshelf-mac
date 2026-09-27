import Foundation
import Testing

@testable import ABSCore

@Suite struct FormatTests {
  @Test func timestamps() {
    #expect(Format.timestamp(0) == "0:00")
    #expect(Format.timestamp(59.9) == "0:59")
    #expect(Format.timestamp(61) == "1:01")
    #expect(Format.timestamp(3600) == "1:00:00")
    #expect(Format.timestamp(3725.4) == "1:02:05")
    #expect(Format.timestamp(3725, alwaysIncludeHours: true) == "01:02:05")
  }

  @Test func elapsedPretty() {
    #expect(Format.elapsedPretty(42) == "42 sec")
    #expect(Format.elapsedPretty(69 * 60) == "69 min")
    #expect(Format.elapsedPretty(3 * 3600) == "3 hr")
    #expect(Format.elapsedPretty(12 * 3600 + 34 * 60 + 5) == "12 hr 34 min")
  }

  @Test func extended() {
    #expect(Format.elapsedPrettyExtended(3723) == "1h 2m 3s")
    #expect(Format.elapsedPrettyExtended(90000) == "1d 1h")
  }

  @Test func bytes() {
    #expect(Format.bytesPretty(82_500_000) == "82.5 MB")
    #expect(Format.bytesPretty(512_340_000) == "512.34 MB")
    #expect(Format.bytesPretty(0) == "0 Bytes")
  }

  @Test func rateAndBadge() {
    #expect(Format.rate(1) == "1x")
    #expect(Format.rate(1.2) == "1.2x")
    #expect(Format.rate(1.25) == "1.25x")
    #expect(Format.sleepBadge(remaining: 45, isEndOfChapter: false) == "45s")
    #expect(Format.sleepBadge(remaining: 30 * 60, isEndOfChapter: false) == "30m")
    #expect(Format.sleepBadge(remaining: 120 * 60, isEndOfChapter: false) == "2h")
    #expect(Format.sleepBadge(remaining: nil, isEndOfChapter: true) == "EoC")
    #expect(Format.jumpAmount(10) == "10 seconds")
    #expect(Format.jumpAmount(300) == "5 minutes")
  }
}

func sampleTimeline() -> Timeline {
  // Three files, like a multi-file mp3 book; chapters cross the file boundaries.
  Timeline(
    tracks: [
      .init(index: 1, startOffset: 0, duration: 100),
      .init(index: 2, startOffset: 100, duration: 100),
      .init(index: 3, startOffset: 200, duration: 50),
    ],
    chapters: [
      Chapter(id: 0, start: 0, end: 60, title: "One"),
      Chapter(id: 1, start: 60, end: 150, title: "Two"),
      Chapter(id: 2, start: 150, end: 250, title: "Three"),
    ])
}

@Suite struct TimelineTests {
  @Test func locateAcrossFiles() {
    let t = sampleTimeline()
    #expect(t.duration == 250)
    #expect(t.locate(0) == (0, 0))
    #expect(t.locate(99.5).position == 0)
    #expect(t.locate(100).position == 1)
    #expect(t.locate(150).offset == 50)
    #expect(t.locate(249).position == 2)
    #expect(t.locate(9999).position == 2)
    #expect(t.globalTime(position: 2, offset: 10) == 210)
  }

  @Test func chapterNavigation() {
    let t = sampleTimeline()
    #expect(t.chapter(at: 70)?.title == "Two")
    // Within 3 s of a chapter start: previous goes to the chapter before.
    #expect(t.previousChapterTarget(from: 62) == 0)
    #expect(t.previousChapterTarget(from: 80) == 60)
    #expect(t.previousChapterTarget(from: 10) == 0)
    #expect(t.nextChapterTarget(from: 70) == 150)
    #expect(t.nextChapterTarget(from: 200) == nil)
  }

  @Test func chapterTrack() {
    let t = sampleTimeline()
    let span = t.trackSpan(at: 70, useChapterTrack: true)
    #expect(span.base == 60 && span.length == 90)
    #expect(t.trackSpan(at: 70, useChapterTrack: false).length == 250)
  }
}

@Suite struct SyncPolicyTests {
  @Test func firstAfter20ThenEvery10() {
    var p = SyncPolicy(sessionStartTime: 0)
    var sent: [SyncBody] = []
    for i in 1...40 {
      if let b = p.tick(realElapsed: 1, currentTime: Double(i)) { sent.append(b) }
    }
    #expect(sent.count == 3)
    #expect(sent[0].currentTime == 20 && sent[0].timeListened == 20)
    #expect(sent[1].currentTime == 30 && sent[1].timeListened == 10)
  }

  @Test func skipsWhenPositionBarelyMoved() {
    var p = SyncPolicy(sessionStartTime: 0)
    let r1 = p.take(currentTime: 50)
    #expect(r1 != nil)
    let r2 = p.take(currentTime: 50.5)
    #expect(r2 == nil)
  }

  @Test func finishedBookOpenedAndPausedDoesNotSync() {
    // Server restarts finished books at 0; a pause right away must not sync.
    var p = SyncPolicy(sessionStartTime: 0)
    _ = p.tick(realElapsed: 5, currentTime: 5)
    let r3 = p.eventSync(currentTime: 5)
    #expect(r3 == nil)
    let r4 = p.closeBody(currentTime: 5)
    #expect(r4 == nil)
  }

  @Test func pauseAfterRealListeningSyncs() {
    var p = SyncPolicy(sessionStartTime: 100)
    for i in 1...25 { _ = p.tick(realElapsed: 1, currentTime: 100 + Double(i)) }
    let b = p.eventSync(currentTime: 125)
    #expect(b != nil)
    #expect(b?.timeListened == 5)
  }

  @Test func seekThenPauseSyncs() {
    var p = SyncPolicy(sessionStartTime: 0)
    p.noteSeek()
    let r5 = p.eventSync(currentTime: 300)
    #expect(r5 != nil)
  }

  @Test func failureToast() {
    var p = SyncPolicy(sessionStartTime: 0)
    let r6 = p.recordResult(success: false)
    #expect(!r6)
    let r7 = p.recordResult(success: false)
    #expect(!r7)
    let r8 = p.recordResult(success: false)
    #expect(!r8)
    let r9 = p.recordResult(success: false)
    #expect(r9)
  }
}

@Suite struct SleepTimerTests {
  @Test func countsOnlyTicksAndFires() {
    var s = SleepTimer()
    s.fadeEnabled = false
    s.set(seconds: 5)
    var events: [SleepTimer.Event] = []
    for _ in 0..<5 { events += s.tick(elapsed: 1, currentTime: 10, rate: 1) }
    #expect(events.contains(.fire(seekBackTo: nil)))
    #expect(!s.isSet)
  }

  @Test func fadeThenSeekBack() {
    var s = SleepTimer()
    s.set(seconds: 90)
    var t = 0.0
    var fired: SleepTimer.Event?
    for _ in 0..<95 {
      t += 1
      for e in s.tick(elapsed: 1, currentTime: t, rate: 1) {
        if case .fire = e { fired = e }
      }
      if fired != nil { break }
    }
    // Fade begins at 60 s left, i.e. after 30 s of listening.
    #expect(fired == .fire(seekBackTo: 30))
  }

  @Test func decrementRules() {
    var s = SleepTimer()
    s.set(seconds: 600)
    s.decrement(300)
    #expect(s.remaining == 300)
    s.decrement(1800)  // larger than what is left: becomes 60 s
    #expect(s.remaining == 240)
    s.set(seconds: 40)
    s.decrement(300)  // under a minute: 5 s
    #expect(s.remaining == 35)
    s.increment(300)
    #expect(s.remaining == 335)
  }

  @Test func endOfChapterNearEndTargetsNext() {
    let t = sampleTimeline()
    #expect(SleepTimer.endOfChapterTarget(currentTime: 20, timeline: t) == 60)
    #expect(SleepTimer.endOfChapterTarget(currentTime: 55, timeline: t) == 150)
    var s = SleepTimer()
    s.fadeEnabled = false
    s.setEndOfChapter(currentTime: 20, timeline: t)
    let r10 = s.tick(elapsed: 1, currentTime: 59, rate: 1)
    #expect(r10.isEmpty)
    let r11 = s.tick(elapsed: 1, currentTime: 60, rate: 1)
    #expect(r11.contains(.fire(seekBackTo: nil)))
  }

  @Test func playWithinTwoMinutesRearms() {
    let t = sampleTimeline()
    var s = SleepTimer()
    s.fadeEnabled = false
    let start = Date()
    s.set(seconds: 2)
    _ = s.tick(elapsed: 2, currentTime: 5, rate: 1, now: start)
    #expect(!s.isSet)
    let r12 = s.playPressed(currentTime: 5, timeline: t, now: start.addingTimeInterval(60))
    #expect(r12)
    #expect(s.remaining == 2)
    s.cancel()
    let r13 = s.playPressed(currentTime: 5, timeline: t, now: start.addingTimeInterval(300))
    #expect(!r13)
  }
}

@Suite struct AutoRewindTests {
  @Test func table() {
    #expect(AutoRewind.seconds(pausedFor: 5) == 0)
    #expect(AutoRewind.seconds(pausedFor: 30) == 3)
    #expect(AutoRewind.seconds(pausedFor: 120) == 10)
    #expect(AutoRewind.seconds(pausedFor: 600) == 20)
    #expect(AutoRewind.seconds(pausedFor: 7200) == 30)
  }

  @Test func clampsToChapterStart() {
    #expect(AutoRewind.target(currentTime: 62, pausedFor: 7200, timeline: sampleTimeline()) == 60)
    #expect(AutoRewind.target(currentTime: 100, pausedFor: 7200, timeline: sampleTimeline()) == 70)
  }

  @Test func overnightWindow() {
    let w = AutoSleepWindow(start: "22:00", end: "06:00")
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    func at(_ h: Int, _ m: Int) -> Date {
      cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: h, minute: m))!
    }
    #expect(w.contains(at(23, 0), calendar: cal))
    #expect(w.contains(at(2, 0), calendar: cal))
    #expect(!w.contains(at(12, 0), calendar: cal))
  }
}

@Suite struct EncodingTests {
  @Test func filterMatchesWeb() {
    // encodeURIComponent(Buffer.from('Philosophy').toString('base64'))
    #expect(FilterEncoding.encode("Philosophy") == "UGhpbG9zb3BoeQ%3D%3D")
    #expect(FilterEncoding.filter("genres", "Philosophy") == "genres.UGhpbG9zb3BoeQ%3D%3D")
    #expect(FilterEncoding.decode("UGhpbG9zb3BoeQ%3D%3D") == "Philosophy")
    #expect(FilterEncoding.filter("issues", nil) == "issues")
  }

  @Test func socketPackets() {
    #expect(SocketPacket.parse("2") == .ping)
    #expect(SocketPacket.parse("40{\"sid\":\"x\"}") == .connect)
    if case .open(let sid, let interval, _) = SocketPacket.parse(
      "0{\"sid\":\"abc\",\"pingInterval\":25000,\"pingTimeout\":20000}")
    {
      #expect(sid == "abc" && interval == 25000)
    } else {
      Issue.record("open not parsed")
    }
    if case .event(let name, let payload) = SocketPacket.parse(
      "42[\"user_session_closed\",\"sess-1\"]")
    {
      #expect(name == "user_session_closed")
      #expect(String(data: payload!, encoding: .utf8) == "\"sess-1\"")
    } else {
      Issue.record("event not parsed")
    }
    if case .event(let name, _) = SocketPacket.parse("42[\"init\"]") {
      #expect(name == "init")
    } else {
      Issue.record("init")
    }
    #expect(SocketPacket.emit("auth", "tok") == "42[\"auth\",\"tok\"]")
  }
}

@Suite struct ModelTests {
  @Test func populatedSeriesKeepsBooksAndCovers() throws {
    let json = """
      {"results":[{"id":"series-1","name":"A Series","books":[
        {"id":"book-1","media":{"coverPath":"/covers/one.jpg","metadata":{"title":"One"}}},
        {"id":"book-2","media":{"coverPath":"/covers/two.jpg","metadata":{"title":"Two"}}}
      ],"totalDuration":7200}],"total":1}
      """
    let page = try JSONDecoder().decode(SeriesPage.self, from: Data(json.utf8))
    #expect(page.total == 1)
    let series = try #require(page.results.first)
    #expect(series.name == "A Series")
    #expect(series.books?.map(\.id) == ["book-1", "book-2"])
    #expect(series.books?.map(\.media.coverPath) == ["/covers/one.jpg", "/covers/two.jpg"])
    #expect(series.totalDuration == 7200)
  }

  @Test(arguments: ["narrators", "tags", "genres"])
  func metadataOnlySearchIsNotEmpty(_ group: String) throws {
    let json = """
      {"book":[],"series":[],"authors":[],"\(group)": [{"name":"A match","numItems":2}]}
      """
    let results = try JSONDecoder().decode(SearchResults.self, from: Data(json.utf8))
    #expect(!results.isEmpty)
    let empty = try JSONDecoder().decode(SearchResults.self, from: Data("{}".utf8))
    #expect(empty.isEmpty)
  }

  @Test func decodesPlaySessionWithManyTracks() throws {
    // Regression: every track is kept, with its offset (multi-file books).
    let json = """
      {"id":"s1","libraryItemId":"li","duration":250,"currentTime":12.5,"playMethod":0,
       "chapters":[{"id":0,"start":0,"end":60,"title":"One"}],
       "audioTracks":[{"index":1,"startOffset":0,"duration":100,"contentUrl":"/api/items/li/file/1","mimeType":"audio/mpeg"},
                      {"index":2,"startOffset":100,"duration":150,"contentUrl":"/api/items/li/file/2","mimeType":"audio/mpeg"}]}
      """
    let s = try JSONDecoder().decode(PlaybackSession.self, from: Data(json.utf8))
    #expect(s.audioTracks.count == 2)
    #expect(Timeline(audioTracks: s.audioTracks, chapters: s.chapters).duration == 250)
  }

  @Test func seriesAsObjectOrArray() throws {
    let a = try JSONDecoder().decode(
      BookMetadata.self,
      from: Data(#"{"title":"T","series":{"id":"1","name":"S","sequence":"2"}}"#.utf8))
    #expect(a.series?.first?.sequence == "2")
    let b = try JSONDecoder().decode(
      BookMetadata.self,
      from: Data(
        #"{"title":"T","series":[{"id":"1","name":"S","sequence":"3"}],"publishedYear":2001}"#.utf8)
    )
    #expect(b.series?.first?.sequence == "3")
    #expect(b.publishedYear == "2001")
  }

  @Test func syncBodyIsNumeric() throws {
    // The server expects numbers here, not strings.
    let d = try JSONEncoder().encode(SyncBody(currentTime: 12.5, timeListened: 10))
    let o = try JSONSerialization.jsonObject(with: d) as! [String: Any]
    #expect(o["currentTime"] is Double && o["timeListened"] is Double)
  }
}

@Suite struct LibraryQueryTests {
  @Test func minifiedSeriesUsesFilterDataAndNumericSequence() throws {
    let json = """
      {"results":[
        {"id":"ten","media":{"metadata":{"title":"Ten","seriesName":"Saga #10"}}},
        {"id":"other","media":{"metadata":{"title":"Other","seriesName":"Other Saga #1"}}},
        {"id":"two-half","media":{"metadata":{"title":"Two and a half","seriesName":"Saga #2.5"}}},
        {"id":"two","media":{"metadata":{"title":"Two","seriesName":"Saga #2"}}},
        {"id":"standalone","media":{"metadata":{"title":"Standalone","seriesName":""}}}
      ],"total":5}
      """
    let page = try JSONDecoder().decode(ItemsPage.self, from: Data(json.utf8))
    let filterData = try JSONDecoder().decode(
      FilterData.self,
      from: Data(#"{"series":[{"id":"series-1","name":"Saga"}]}"#.utf8))
    let context = LibraryQuery.Context(
      seriesById: Dictionary(uniqueKeysWithValues: (filterData.series ?? []).map { ($0.id, $0.name) }))
    let books = LibraryQuery.apply(
      page.results, filter: FilterEncoding.filter("series", "series-1"), sort: "sequence",
      desc: false, ctx: context)
    #expect(books.map(\.id) == ["two", "two-half", "ten"])
  }
}

private final class GroupListProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "abs.test"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    if url.lastPathComponent == "series" {
      let library = url.deletingLastPathComponent().lastPathComponent
      let limit = Int(query.first { $0.name == "limit" }?.value ?? "0") ?? 0
      let page = Int(query.first { $0.name == "page" }?.value ?? "0") ?? 0
      // Bound a broken pagination loop without letting an HTTP error satisfy decoding-error tests.
      guard page < 5 else { respond(url, status: 500, body: "{}"); return }
      let total = library == "empty" ? 0 : 205
      let start = library == "repeated" ? 0 : page * limit
      let end = min(start + max(0, limit), total)
      let rows: [[String: String]] = library == "incomplete" || limit <= 0 || start >= end
        ? [] : (start..<end).map { ["id": "series-\($0)", "name": "Series \($0)"] }
      let data = try! JSONSerialization.data(withJSONObject: ["results": rows, "total": total])
      respond(url, body: String(decoding: data, as: UTF8.self))
      return
    }
    let limitedToZero = query.contains { $0.name == "limit" && $0.value == "0" }
    let group: String
    switch url.path {
    case "/api/libraries/library-1/collections":
      group = #"{"id":"collection-1","name":"Saved books","books":[]}"#
    case "/api/libraries/library-1/playlists":
      group = #"{"id":"playlist-1","name":"Listen next","items":[]}"#
    default:
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    // ABS 2.36 slices group results to zero when the query contains limit="0".
    let body = "{\"results\":[\(limitedToZero ? "" : group)],\"total\":1}"
    respond(url, body: body)
  }

  private func respond(_ url: URL, status: Int = 200, body: String) {
    let response = HTTPURLResponse(
      url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite struct GroupEndpointTests {
  private func client() -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GroupListProtocol.self]
    let session = URLSession(configuration: configuration)
    return APIClient(
      baseURL: URL(string: "https://abs.test"),
      tokens: TokenStore(access: "test-token", refresh: nil, persist: { _, _ in }), session: session)
  }

  @Test func collectionsAndPlaylistsPopulateOnABS236() async throws {
    let api = client()
    defer { api.session.invalidateAndCancel() }
    let collections = try await api.collections("library-1")
    let playlists = try await api.playlists("library-1")
    #expect(collections.map(\.id) == ["collection-1"])
    #expect(playlists.map(\.id) == ["playlist-1"])
  }

  @Test func defaultSeriesRequestLoadsEveryPage() async throws {
    let api = client()
    defer { api.session.invalidateAndCancel() }
    let page = try await api.series("populated")
    #expect(page.total == 205)
    #expect(page.results.map(\.id) == (0..<205).map { "series-\($0)" })
    let cached = try JSONDecoder().decode(SeriesPage.self, from: JSONEncoder().encode(page))
    #expect(cached.results.map(\.id) == page.results.map(\.id))
    #expect(cached.total == 205)
  }

  @Test func positiveSeriesLimitReturnsRequestedPage() async throws {
    let api = client()
    defer { api.session.invalidateAndCancel() }
    let page = try await api.series("populated", limit: 2, page: 2)
    #expect(page.total == 205)
    #expect(page.results.map(\.id) == ["series-4", "series-5"])
  }

  @Test func emptySeriesLibrarySucceeds() async throws {
    let api = client()
    defer { api.session.invalidateAndCancel() }
    let page = try await api.series("empty")
    #expect(page.total == 0)
    #expect(page.results.isEmpty)
  }

  @Test(arguments: ["incomplete", "repeated"])
  func inconsistentSeriesPaginationFails(_ library: String) async {
    let api = client()
    defer { api.session.invalidateAndCancel() }
    do {
      _ = try await api.series(library)
      Issue.record("Incomplete or repeated Series results must fail")
    } catch APIError.decoding {
    } catch {
      Issue.record("Expected a Series decoding error, received \(error)")
    }
  }
}
