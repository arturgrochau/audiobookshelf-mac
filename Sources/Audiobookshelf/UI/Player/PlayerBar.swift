import ABSCore
import SwiftUI

/// The player: one quiet row of controls over a thin progress line.
///
/// Deliberately not the web's PlayerUi.vue any more. That bar is 160 px with
/// eleven icons, a person and a clock glyph, "/ 0%", and a tick for every file
/// (481 on a CD rip). Here the row keeps what is used every minute: transport,
/// speed, sleep, keep awake, chapters. Everything else lives in the ••• menu.
struct PlayerBar: View {
  @Bindable var player = PlayerModel.shared
  var app = AppModel.shared

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        HStack(spacing: 12) {
          nowPlaying
          Spacer(minLength: 16)
          PlayerActions()
        }
        TransportControls()
      }
      .frame(height: 52)
      ProgressRow()
    }
    .padding(.horizontal, 18)
    .padding(.top, 10)
    .padding(.bottom, 10)
    .frame(height: Theme.playerHeight)
    .frame(maxWidth: .infinity)
    .background(Theme.primary)
    .overlay(alignment: .top) { Color.white.opacity(0.06).frame(height: 1) }
  }

  private var aspect: Double { app.currentLibrary?.coverAspect ?? 1 }

  private var nowPlaying: some View {
    HStack(spacing: 12) {
      BookCover(item: player.item, width: 48 / aspect, aspect: aspect, pixelWidth: 160)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .onTapGesture { if let id = player.item?.id { app.go(.item(id)) } }
        .linkCursor()
      VStack(alignment: .leading, spacing: 2) {
        Text(player.displayTitle.isEmpty ? "No Title" : player.displayTitle)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
          .onTapGesture { if let id = player.item?.id { app.go(.item(id)) } }
          .linkCursor()
        Text(byline)
          .font(.system(size: 12))
          .foregroundStyle(Theme.gray400)
        ChapterLine()
      }
      .lineLimit(1)
      .frame(maxWidth: 300, alignment: .leading)
    }
  }

  /// "Bryce Courtenay · read by Humphrey Bower".
  private var byline: String {
    let author = player.displayAuthor.isEmpty ? "Unknown" : player.displayAuthor
    let narrators = player.item?.media.metadata.narrators ?? []
    let reader = narrators.filter { $0 != author }.joined(separator: ", ")
    return reader.isEmpty ? author : "\(author) · read by \(reader)"
  }
}

/// SF Symbol button with a soft circular hover, the native equivalent of the
/// web's icon font buttons.
struct SymbolButton: View {
  let symbol: String
  var size: CGFloat = 15
  var weight: Font.Weight = .medium
  var active = false
  var disabled = false
  let help: String
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: size, weight: weight))
        .foregroundStyle(
          disabled ? Theme.gray600 : active ? Theme.accent : hover ? .white : Theme.gray300
        )
        .frame(width: size + 16, height: size + 16)
        .background(Circle().fill(Color.white.opacity(hover && !disabled ? 0.08 : 0)))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .help(help)
    .accessibilityLabel(help)
    .onHover { hover = $0 }
    .animation(.easeOut(duration: 0.12), value: hover)
  }
}

/// Centered transport: chapter back, jump back, play/pause, jump forward, next.
struct TransportControls: View {
  @Bindable var player = PlayerModel.shared
  var settings = AppSettings.shared

  var body: some View {
    HStack(spacing: 14) {
      SymbolButton(symbol: "backward.end.fill", size: 12, help: L.s("ButtonPreviousChapter")) {
        player.previousChapter()
      }
      SymbolButton(
        symbol: Self.jumpSymbol("gobackward", settings.jumpBackwardAmount), size: 18,
        help: "\(L.s("ButtonJumpBackward")) - \(Format.jumpAmount(settings.jumpBackwardAmount))"
      ) { player.jumpBackward() }
      playButton
      SymbolButton(
        symbol: Self.jumpSymbol("goforward", settings.jumpForwardAmount), size: 18,
        help: "\(L.s("ButtonJumpForward")) - \(Format.jumpAmount(settings.jumpForwardAmount))"
      ) { player.jumpForward() }
      SymbolButton(
        symbol: "forward.end.fill", size: 12, disabled: !player.hasNext,
        help: player.nextIsQueueItem ? L.s("ButtonNextItemInQueue") : L.s("ButtonNextChapter")
      ) { player.next() }
    }
  }

  private var playButton: some View {
    Button {
      player.playPause()
    } label: {
      ZStack {
        Circle().fill(.white)
        if player.isLoading {
          ProgressView().controlSize(.small).tint(Theme.primary)
        } else {
          Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.primary)
            .offset(x: player.isPlaying ? 0 : 1.5)
        }
      }
      .frame(width: 40, height: 40)
      .contentShape(Circle())
    }
    .buttonStyle(PressScale())
    .accessibilityLabel(player.isPlaying ? L.s("ButtonPause") : L.s("ButtonPlay"))
  }

  /// SF Symbols only ship numbered jump glyphs for these amounts.
  static func jumpSymbol(_ base: String, _ seconds: Double) -> String {
    let n = Int(seconds)
    return [5, 10, 15, 30, 45, 60, 75, 90].contains(n) ? "\(base).\(n)" : base
  }
}

struct PressScale: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.92 : 1)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }
}

/// Right cluster: speed, sleep, keep awake, chapters, and a ••• menu.
struct PlayerActions: View {
  @Bindable var player = PlayerModel.shared
  var awake = KeepAwake.shared

  var body: some View {
    HStack(spacing: 4) {
      SpeedControl()
      sleepButton
      SymbolButton(
        symbol: awake.enabled ? "cup.and.heat.waves.fill" : "cup.and.heat.waves",
        active: awake.enabled,
        help: awake.enabled
          ? "Keeping the Mac awake while playing\(awake.lidSupported ? ", lid closed too" : "")"
          : "Keep the Mac awake while playing"
      ) { awake.toggle() }
      if !player.chapters.isEmpty {
        SymbolButton(symbol: "list.bullet", help: L.s("LabelViewChapters") + " (L)") {
          player.showChapters.toggle()
        }
      }
      MoreMenu()
    }
  }

  private var sleepButton: some View {
    Button {
      player.showSleepTimer = true
    } label: {
      HStack(spacing: 3) {
        Image(systemName: player.sleep.isSet ? "moon.zzz.fill" : "moon.zzz")
          .font(.system(size: 15, weight: .medium))
        if player.sleep.isSet {
          Text(
            Format.sleepBadge(
              remaining: player.sleepRemaining, isEndOfChapter: player.sleep.mode == .endOfChapter)
          )
          .font(.system(size: 12, weight: .semibold).monospacedDigit())
        }
      }
      .foregroundStyle(player.sleep.isSet ? Theme.warning : Theme.gray300)
      .padding(.horizontal, 8)
      .frame(height: 31)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(L.s("LabelSleepTimer"))
  }
}

/// Everything that is not needed every minute.
struct MoreMenu: View {
  @Bindable var player = PlayerModel.shared

  var body: some View {
    Menu {
      Button(player.bookmarks.isEmpty ? "Bookmarks" : "Bookmarks (\(player.bookmarks.count))") {
        player.showBookmarks = true
      }
      if !player.queue.isEmpty {
        Button("Queue (\(player.queue.count))") { player.showQueue = true }
      }
      Divider()
      Button(player.volume > 0 ? "Mute" : "Unmute") { player.toggleMute() }
      Button("Mini Player  ⌘⇧M") { MiniPlayer.shared.toggle() }
      Button(L.s("HeaderPlayerSettings")) { player.showPlayerSettings = true }
      Divider()
      Button(L.s("LabelClosePlayer")) { Task { await player.close() } }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Theme.gray300)
        .frame(width: 31, height: 31)
        .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("More")
  }
}

/// Elapsed · progress line · remaining.
struct ProgressRow: View {
  var player = PlayerModel.shared
  var settings = AppSettings.shared

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { _ in
      let t = player.liveTime
      let chapter = player.timeline.chapter(at: t)
      let chapterMode = settings.useChapterTrack && chapter != nil
      let shown = chapterMode ? max(0, t - (chapter?.start ?? 0)) : t
      let span = chapterMode ? ((chapter?.end ?? 0) - (chapter?.start ?? 0)) : player.duration
      let remaining = max(0, span - shown) / player.rate
      HStack(spacing: 10) {
        Text(Format.timestamp(shown / player.rate))
          .frame(width: 64, alignment: .leading)
        TrackBar()
        Text("-" + Format.timestamp(remaining))
          .frame(width: 64, alignment: .trailing)
      }
      .font(.system(size: 11, weight: .medium).monospacedDigit())
      .foregroundStyle(Theme.gray400)
    }
  }
}

/// A 4 pt capsule that thickens under the pointer. Chapter marks are drawn
/// only when they are far enough apart to mean something: a tick per file on
/// a 481-file CD rip was a comb, not information.
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
        let thick: CGFloat = hoverX == nil ? 4 : 6
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.12))
          Capsule().fill(Color.white.opacity(0.18)).frame(width: w * buffered)
          Capsule().fill(Color.white.opacity(0.9)).frame(width: max(thick, w * played))
          ticks(width: w)
          if hoverX != nil {
            Circle().fill(.white).frame(width: 11, height: 11)
              .offset(x: w * played - 5.5)
              .shadow(color: .black.opacity(0.3), radius: 2)
          }
        }
        .frame(height: thick)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
          switch phase {
          case .active(let p): hoverX = p.x
          case .ended: hoverX = nil
          }
        }
        .gesture(
          DragGesture(minimumDistance: 0).onEnded { v in
            let frac = max(0, min(1, v.location.x / max(1, w)))
            player.seek(to: span.base + Double(frac) * span.length)
          }
        )
        .overlay(alignment: .topLeading) { hoverLabel(width: w, span: span) }
        .animation(.easeOut(duration: 0.12), value: hoverX == nil)
      }
    }
    .frame(height: 14)
  }

  @ViewBuilder private func ticks(width w: CGFloat) -> some View {
    let marks = player.chapters.dropFirst()
    if !settings.useChapterTrack, player.duration > 0, !marks.isEmpty,
      w / CGFloat(marks.count + 1) >= 14
    {
      ForEach(Array(marks)) { c in
        Rectangle().fill(Theme.primary.opacity(0.9)).frame(width: 1.5)
          .offset(x: w * CGFloat(c.start / player.duration))
      }
    }
  }

  @ViewBuilder private func hoverLabel(width w: CGFloat, span: (base: Double, length: Double)) -> some View {
    if let hoverX {
      let time = span.base + Double(max(0, min(1, hoverX / max(1, w)))) * span.length
      let chapter = player.timeline.chapter(at: time)
      let label =
        Format.timestamp((time - (settings.useChapterTrack ? span.base : 0)) / player.rate)
        + (chapter.map { player.chapters.count > 1 ? "  \($0.title)" : "" } ?? "")
      Text(label)
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.85)))
        .fixedSize()
        .offset(x: min(max(0, hoverX - 30), w - 150), y: -26)
        .allowsHitTesting(false)
    }
  }
}

/// "1.5x" opens presets and a fine −/+ stepper. Keys: S 2x, A 1.5x, X 1.2x, Z 1x.
struct SpeedControl: View {
  @Bindable var player = PlayerModel.shared
  var settings = AppSettings.shared
  @State private var show = false
  @State private var hover = false
  static let rates: [Double] = [1, 1.2, 1.5, 1.75, 2]

  var body: some View {
    Button {
      show = true
    } label: {
      Text(Format.rate(player.rate))
        .font(.system(size: 12, weight: .semibold).monospacedDigit())
        .foregroundStyle(
          abs(player.rate - 1) < 0.001 ? (hover ? .white : Theme.gray300) : Theme.accent
        )
        .padding(.horizontal, 8)
        .frame(minWidth: 44)
        .frame(height: 24)
        .background(Capsule().stroke(Color.white.opacity(hover ? 0.3 : 0.15)))
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
    .help("Playback speed  (S 2x · A 1.5x · X 1.2x · Z 1x)")
    .popover(isPresented: $show, arrowEdge: .top) {
      VStack(spacing: 10) {
        HStack(spacing: 4) {
          ForEach(Self.rates, id: \.self) { r in
            let on = abs(player.rate - r) < 0.001
            Button {
              player.setRate(r)
            } label: {
              Text(Format.rate(r))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(on ? Theme.primary : .white)
                .frame(width: 44, height: 26)
                .background(
                  RoundedRectangle(cornerRadius: 6).fill(on ? .white : Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
          }
        }
        HStack {
          SymbolButton(symbol: "minus", size: 12, help: "Slower") {
            player.setRate(player.rate - settings.playbackRateIncrementDecrement)
          }
          Spacer()
          Text(Format.rate(player.rate))
            .font(.system(size: 22, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
          Spacer()
          SymbolButton(symbol: "plus", size: 12, help: "Faster") {
            player.setRate(player.rate + settings.playbackRateIncrementDecrement)
          }
        }
      }
      .padding(12)
      .frame(width: 252)
      .environment(\.colorScheme, .dark)
    }
  }
}

/// The big "2x" that flashes when a speed key is pressed.
struct SpeedFlash: View {
  var player = PlayerModel.shared

  var body: some View {
    if let flash = player.speedFlash {
      Text(Format.rate(flash.rate))
        .font(.system(size: 30, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
        .id(flash.id)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .allowsHitTesting(false)
    }
  }
}

/// The current chapter, under the author. It used to float over the progress
/// line, where it crowded the play button.
struct ChapterLine: View {
  var player = PlayerModel.shared

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { _ in
      if player.chapters.count > 1, let c = player.timeline.chapter(at: player.liveTime) {
        Text(c.title)
          .font(.system(size: 11))
          .foregroundStyle(Theme.gray500)
      }
    }
  }
}
