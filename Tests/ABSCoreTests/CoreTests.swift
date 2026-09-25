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
