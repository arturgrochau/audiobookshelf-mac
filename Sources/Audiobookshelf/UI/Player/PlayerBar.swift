import ABSCore
import SwiftUI

/// The web player (components/app/MediaPlayerContainer.vue + player/PlayerUi.vue):
/// 160 px, primary background, cover top-left, title/author/duration, a close
/// button, centred transport, right-hand cluster, track bar, time row.
struct PlayerBar: View {
  @Bindable var player = PlayerModel.shared
  @Bindable var settings = AppSettings.shared
  var app = AppModel.shared

  var body: some View {
    ZStack(alignment: .topLeading) {
      VStack(spacing: 0) {
        header
        controlsRow
          .padding(.top, -24)
        TrackBar()
          .padding(.top, 4)
        timeRow
          .padding(.top, 2)
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .padding(.bottom, 16)

      cover
        .padding(.leading, 16)
        .padding(.top, 8)
    }
    .frame(height: Theme.playerHeight)
    .frame(maxWidth: .infinity)
    .background(Theme.primary)
  }

  private var aspect: Double { app.currentLibrary?.coverAspect ?? 1 }
  private var coverWidth: CGFloat { 77 / aspect }

  private var cover: some View {
    BookCover(item: player.item, width: coverWidth, aspect: aspect, pixelWidth: 200)
      .onTapGesture { if let id = player.item?.id { app.go(.item(id)) } }
      .linkCursor()
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 0) {
        Text(player.displayTitle.isEmpty ? "No Title" : player.displayTitle)
          .font(Theme.sans(18))
          .foregroundStyle(.white)
          .lineLimit(1)
          .onTapGesture { if let id = player.item?.id { app.go(.item(id)) } }
          .linkCursor()
        HStack(spacing: 6) {
          Icon("person", size: 14)
          authorLinks
        }
        .foregroundStyle(Theme.gray400)
        .frame(maxWidth: 520, alignment: .leading)
        HStack(spacing: 6) {
          Icon("schedule", size: 12)
          Text(Format.timestamp(player.duration / player.rate))
            .font(Theme.mono(14))
        }
        .foregroundStyle(Theme.gray400)
      }
      .padding(.leading, aspect == 1 ? 96 : 64)
      Spacer(minLength: 0)
      HoverIcon(icon: "close", size: 24, color: .white) { Task { await player.close() } }
        .help(L.s("LabelClosePlayer"))
        .padding(16)
    }
  }

  @ViewBuilder private var authorLinks: some View {
    let authors = player.item?.media.metadata.authors ?? []
    if authors.isEmpty {
      Text(player.displayAuthor.isEmpty ? "Unknown" : player.displayAuthor).font(Theme.sans(16))
        .lineLimit(1)
    } else {
      HStack(spacing: 0) {
        ForEach(Array(authors.enumerated()), id: \.offset) { i, a in
          Text(a.name + (i < authors.count - 1 ? ", " : ""))
            .font(Theme.sans(16))
            .lineLimit(1)
            .onTapGesture { app.go(.author(a.id)) }
            .linkCursor()
        }
      }
    }
  }

  private var controlsRow: some View {
    ZStack {
      TransportControls()
      HStack(spacing: 0) {
        Spacer()
        rightCluster
      }
    }
  }

  private var rightCluster: some View {
    HStack(spacing: 16) {
      SpeedControl()
      VolumeControl()
        .help(L.s("LabelVolume"))
      Button {
        player.showSleepTimer = true
      } label: {
        HStack(spacing: 2) {
          Icon("snooze", size: 24)
            .foregroundStyle(player.sleep.isSet ? Theme.warning : Theme.gray300)
          if player.sleep.isSet {
            Text(
              Format.sleepBadge(
                remaining: player.sleepRemaining, isEndOfChapter: player.sleep.mode == .endOfChapter
              )
            )
            .font(Theme.sans(18, .semibold))
            .foregroundStyle(Theme.warning)
            .frame(minWidth: 32)
          }
        }
      }
      .buttonStyle(.plain)
      .help(L.s("LabelSleepTimer"))
      HoverIcon(icon: player.bookmarks.isEmpty ? "bookmark_border" : "bookmarks") {
        player.showBookmarks = true
      }
      .help(L.s("LabelViewBookmarks"))
      if !player.chapters.isEmpty {
        HoverIcon(icon: "format_list_bulleted") { player.showChapters.toggle() }
          .help(L.s("LabelViewChapters"))
      }
      if !player.queue.isEmpty {
        HoverIcon(icon: "playlist_play") { player.showQueue = true }
          .help(L.s("LabelViewQueue"))
      }
      HoverIcon(icon: "settings_slow_motion", size: 27) { player.showPlayerSettings.toggle() }
        .help(L.s("LabelViewPlayerSettings"))
    }
    .padding(.trailing, 8)
  }

  private var timeRow: some View {
    TimelineView(.periodic(from: .now, by: 1)) { _ in
      let t = player.liveTime
      let chapter = player.timeline.chapter(at: t)
      let chapterMode = settings.useChapterTrack && chapter != nil
      let shown = chapterMode ? max(0, t - (chapter?.start ?? 0)) : t
      let span = chapterMode ? ((chapter?.end ?? 0) - (chapter?.start ?? 0)) : player.duration
      let percent = span > 0 ? Int((100 * shown / span).rounded()) : 0
      let remaining = (span - shown) / player.rate
      ZStack {
        HStack(spacing: 0) {
          Text(Format.timestamp(shown / player.rate)).font(Theme.mono(14)).foregroundStyle(
            Theme.gray100)
          Text(" / \(percent)%").font(Theme.mono(14)).foregroundStyle(Theme.gray100)
          Spacer()
          Text(remaining < 0 ? Format.timestamp(-remaining) : "-" + Format.timestamp(remaining))
            .font(Theme.mono(14)).foregroundStyle(Theme.gray100)
        }
        HStack(spacing: 0) {
          Text(chapter?.title ?? "").font(Theme.sans(14)).foregroundStyle(Theme.gray300)
          if chapterMode, let idx = player.timeline.chapterIndex(at: t) {
            Text(
              "  ("
                + L.s(
                  "LabelPlayerChapterNumberMarker", String(idx + 1), String(player.chapters.count))
                + ")"
            )
            .font(Theme.sans(12)).foregroundStyle(Theme.gray400)
          }
        }
        .lineLimit(1)
        .padding(.horizontal, 160)
      }
    }
  }
}

/// Centered transport (player/PlayerPlaybackControls.vue).
struct TransportControls: View {
  @Bindable var player = PlayerModel.shared
  var settings = AppSettings.shared

  var body: some View {
    HStack(spacing: 0) {
      if player.isLoading {
        Icon("autorenew", size: 24)
          .foregroundStyle(Theme.primary)
          .padding(8)
          .background(Circle().fill(Theme.accent))
          .rotationEffect(.degrees(player.isLoading ? 360 : 0))
          .animation(
            .linear(duration: 1).repeatForever(autoreverses: false), value: player.isLoading)
      } else {
        HoverIcon(icon: "first_page", size: 30) { player.previousChapter() }
          .help(L.s("ButtonPreviousChapter"))
          .padding(.trailing, 32)
        HoverIcon(icon: "replay", size: 30) { player.jumpBackward() }
          .help("\(L.s("ButtonJumpBackward")) - \(Format.jumpAmount(settings.jumpBackwardAmount))")
        Button {
          player.playPause()
        } label: {
          Icon(player.isPlaying ? "pause" : "play_arrow", size: 24, filled: true)
            .foregroundStyle(Theme.primary)
            .padding(8)
            .background(Circle().fill(Theme.accent))
            .shadow(color: .black.opacity(0.2), radius: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.isPlaying ? L.s("ButtonPause") : L.s("ButtonPlay"))
        .padding(.horizontal, 32)
        HoverIcon(icon: "forward_media", size: 30) { player.jumpForward() }
          .help("\(L.s("ButtonJumpForward")) - \(Format.jumpAmount(settings.jumpForwardAmount))")
        HoverIcon(icon: "last_page", size: 30, disabled: !player.hasNext) { player.next() }
          .help(player.nextIsQueueItem ? L.s("ButtonNextItemInQueue") : L.s("ButtonNextChapter"))
          .padding(.leading, 32)
      }
    }
    .frame(height: 44)
    .padding(.bottom, 8)
  }
}

/// 8 px track (player/PlayerTrackBar.vue): ready/buffer/played layers,
/// chapter ticks below, hover cursor with a timestamp pill, click to seek.
struct TrackBar: View {
  var player = PlayerModel.shared
  var settings = AppSettings.shared
  @State private var hoverX: CGFloat?

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !player.isPlaying)) { _ in
        let t = player.liveTime
        let span = player.timeline.trackSpan(at: t, useChapterTrack: settings.useChapterTrack)
        let played = CGFloat(max(0, min(1, (t - span.base) / span.length)))
        let buffered = CGFloat(
          max(0, min(1, (player.engine.bufferedUntil - span.base) / span.length)))
        VStack(spacing: 0) {
          ZStack(alignment: .leading) {
            Rectangle().fill(Theme.gray700)
            Rectangle().fill(Theme.gray500).frame(width: w * buffered)
            Rectangle().fill(Theme.gray200).frame(width: w * played)
            if let hoverX {
              Rectangle().fill(Theme.gray100).frame(width: 2).offset(x: hoverX - 1)
            }
          }
          .frame(height: 8)
          .scaleEffect(y: hoverX == nil ? 1 : 1.25)
          .clipped()
          .contentShape(Rectangle())
          .onContinuousHover { phase in
            switch phase {
            case .active(let p): hoverX = p.x
            case .ended: hoverX = nil
            }
          }
          .onTapGesture { location in
            let frac = max(0, min(1, location.x / max(1, w)))
            player.seek(to: span.base + Double(frac) * span.length)
          }
          ZStack(alignment: .leading) {
            if !settings.useChapterTrack, player.duration > 0 {
              ForEach(player.chapters.dropFirst()) { c in
                Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 4)
                  .offset(x: w * CGFloat(c.start / player.duration))
              }
            }
          }
          .frame(height: 8, alignment: .top)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topLeading) {
          if let hoverX {
            let time = span.base + Double(max(0, min(1, hoverX / max(1, w)))) * span.length
            let chapter = player.timeline.chapter(at: time)
            let label =
              Format.timestamp((time - (settings.useChapterTrack ? span.base : 0)) / player.rate)
              + (chapter.map { " - \($0.title)" } ?? "")
            Text(label)
              .font(Theme.mono(13))
              .foregroundStyle(.black)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(RoundedRectangle(cornerRadius: 3).fill(.white))
              .fixedSize()
              .offset(x: min(max(0, hoverX - 40), w - 160), y: -26)
              .allowsHitTesting(false)
          }
        }
      }
    }
    .frame(height: 16)
  }
}

/// `controls/PlaybackSpeedControl.vue`: "1.0x" opens a popover with presets
/// and −/+; changes apply live and are saved when the popover closes.
struct SpeedControl: View {
  @Bindable var player = PlayerModel.shared
  var settings = AppSettings.shared
  @State private var show = false
  @State private var openedAt: Double = 1
  static let rates: [Double] = [0.5, 1, 1.2, 1.5, 2]

  var body: some View {
    Button {
      openedAt = player.rate
      show = true
    } label: {
      (Text(Self.display(player.rate, step: settings.playbackRateIncrementDecrement)).font(
        Theme.sans(16))
        + Text("x").font(Theme.sans(16)))
        .foregroundStyle(Theme.gray200)
    }
    .buttonStyle(.plain)
    .popover(isPresented: $show, arrowEdge: .top) {
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          ForEach(Self.rates, id: \.self) { r in
            Button {
              player.setRate(r, persist: false)
            } label: {
              (Text(Format.trimNumber(r)).font(Theme.sans(12)) + Text("x").font(Theme.sans(14)))
                .foregroundStyle(.white)
                .frame(width: 44, height: 36)
                .background(abs(player.rate - r) < 0.001 ? Theme.black100 : Color.clear)
                .overlay(Rectangle().stroke(Theme.black300, lineWidth: 1))
            }
            .buttonStyle(.plain)
          }
        }
        .frame(width: 220, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        HStack(spacing: 0) {
          IconButton(
            icon: "remove",
            disabled: player.rate - settings.playbackRateIncrementDecrement < 0.5 - 0.0001
          ) {
            player.setRate(player.rate - settings.playbackRateIncrementDecrement, persist: false)
          }
          Spacer()
          (Text(Self.display(player.rate, step: settings.playbackRateIncrementDecrement)).font(
            Theme.sans(30))
            + Text("x").font(Theme.sans(24)))
            .foregroundStyle(.white)
          Spacer()
          IconButton(
            icon: "add",
            disabled: player.rate + settings.playbackRateIncrementDecrement > 10 + 0.0001
          ) {
            player.setRate(player.rate + settings.playbackRateIncrementDecrement, persist: false)
          }
        }
        .padding(.top, 8)
        .frame(width: 220)
      }
      .padding(8)
      .background(Theme.bg)
      .environment(\.colorScheme, .dark)
      .onDisappear {
        if abs(player.rate - openedAt) > 0.0001 { player.setRate(player.rate, persist: true) }
      }
    }
  }

  /// "1.0" with a 0.1 step unless the value has two decimals; always two with 0.05.
  static func display(_ r: Double, step: Double) -> String {
    let twoDecimals = abs((r * 100).rounded() - (r * 10).rounded() * 10) > 0.001
    if abs(step - 0.05) < 0.0001 || twoDecimals { return String(format: "%.2f", r) }
    return String(format: "%.1f", r)
  }
}

/// `controls/VolumeControl.vue`: icon toggles mute; hover shows a vertical
/// slider; the scroll wheel changes volume by 0.1.
struct VolumeControl: View {
  @Bindable var player = PlayerModel.shared
  @State private var show = false

  var icon: String {
    player.volume <= 0 ? "volume_mute" : (player.volume <= 0.5 ? "volume_down" : "volume_up")
  }

  var body: some View {
    HoverIcon(icon: icon) { player.toggleMute() }
      .onHover { inside in if inside { show = true } }
      .popover(isPresented: $show, arrowEdge: .top) {
        Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }), in: 0...1)
          .frame(width: 110)
          .rotationEffect(.degrees(-90))
          .frame(width: 32, height: 120)
          .padding(8)
          .background(Theme.bg)
          .environment(\.colorScheme, .dark)
      }
  }
}
