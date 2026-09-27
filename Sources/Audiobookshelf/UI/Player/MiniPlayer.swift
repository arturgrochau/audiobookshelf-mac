import ABSCore
import AppKit
import SwiftUI

/// ⌘⇧M: a small always-on-top panel with the book, play/pause and the jumps.
/// Non-activating, so clicking it never steals focus from what you are doing;
/// it floats over full-screen apps and follows you across Spaces. The cover
/// brings the main window back.
@MainActor
final class MiniPlayer {
  static let shared = MiniPlayer()
  private var panel: NSPanel?

  var isVisible: Bool { panel?.isVisible ?? false }

  func toggle() { isVisible ? hide() : show() }

  func show() {
    guard PlayerModel.shared.hasItem else { return }
    if panel == nil { panel = makePanel() }
    panel?.orderFrontRegardless()
  }

  func hide() { panel?.orderOut(nil) }

  private func makePanel() -> NSPanel {
    let p = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 340, height: 84),
      styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
      backing: .buffered, defer: false)
    p.titleVisibility = .hidden
    p.titlebarAppearsTransparent = true
    p.standardWindowButton(.closeButton)?.isHidden = true
    p.standardWindowButton(.miniaturizeButton)?.isHidden = true
    p.standardWindowButton(.zoomButton)?.isHidden = true
    p.isMovableByWindowBackground = true
    p.level = .floating
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    p.hidesOnDeactivate = false
    p.isReleasedWhenClosed = false
    p.backgroundColor = .clear
    p.isOpaque = false
    p.hasShadow = true
    let host = NSHostingView(rootView: MiniPlayerView())
    host.frame = p.contentRect(forFrameRect: p.frame)
    p.contentView = host
    if !p.setFrameUsingName("MiniPlayer"), let screen = NSScreen.main {
      let v = screen.visibleFrame
      p.setFrameOrigin(NSPoint(x: v.maxX - 360, y: v.maxY - 104))
    }
    p.setFrameAutosaveName("MiniPlayer")
    return p
  }
}

struct MiniPlayerView: View {
  @Bindable var player = PlayerModel.shared
  var settings = AppSettings.shared
  @State private var hover = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        BookCover(item: player.item, width: 52, aspect: 1, pixelWidth: 160)
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .onTapGesture { (NSApp.delegate as? AppDelegate)?.showWindow() }
          .help("Show Audiobookshelf")
        VStack(alignment: .leading, spacing: 2) {
          Text(player.displayTitle)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
          Text(player.displayAuthor)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.6))
        }
        .lineLimit(1)
        Spacer(minLength: 4)
        MiniSpeed()
        SymbolButton(
          symbol: TransportControls.jumpSymbol("gobackward", settings.jumpBackwardAmount),
          size: 14, help: L.s("ButtonJumpBackward")
        ) { player.jumpBackward() }
        Button {
          player.playPause()
        } label: {
          Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.primary)
            .offset(x: player.isPlaying ? 0 : 1)
            .frame(width: 32, height: 32)
            .background(Circle().fill(.white))
            .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        SymbolButton(
          symbol: TransportControls.jumpSymbol("goforward", settings.jumpForwardAmount),
          size: 14, help: L.s("ButtonJumpForward")
        ) { player.jumpForward() }
      }
      .padding(.horizontal, 12)
      .frame(maxHeight: .infinity)
      progress
    }
    .frame(width: 340, height: 84)
    .background(.ultraThinMaterial)
    .background(Color.black.opacity(0.35))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1)))
    .overlay(alignment: .topTrailing) {
      if hover {
        Button {
          MiniPlayer.shared.hide()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.6))
        }
        .buttonStyle(.plain)
        .help("Close mini player")
        .padding(6)
      }
    }
    .onHover { hover = $0 }
    .environment(\.colorScheme, .dark)
  }

  private var progress: some View {
    TimelineView(.periodic(from: .now, by: 1)) { _ in
      GeometryReader { geo in
        let frac = player.duration > 0 ? player.liveTime / player.duration : 0
        ZStack(alignment: .leading) {
          Rectangle().fill(Color.white.opacity(0.12))
          Rectangle().fill(Color.white.opacity(0.85))
            .frame(width: geo.size.width * CGFloat(max(0, min(1, frac))))
        }
      }
      .frame(height: 3)
    }
  }
}

/// "1.5x" in the mini player. A menu rather than the bar's popover: a menu
/// tracks fine in the non-activating panel without taking focus from the app
/// you are in. Presets and the fine step are both saved, like the bar's.
private struct MiniSpeed: View {
  @Bindable var player = PlayerModel.shared
  var settings = AppSettings.shared
  @State private var hover = false

  var body: some View {
    Menu {
      ForEach(SpeedControl.rates, id: \.self) { r in
        Toggle(
          Format.rate(r),
          isOn: Binding(
            get: { abs(player.rate - r) < 0.001 },
            set: { _ in player.setRate(r) }))
      }
      Divider()
      Button("Faster") { player.setRate(player.rate + settings.playbackRateIncrementDecrement) }
        .disabled(player.rate >= 10)
      Button("Slower") { player.setRate(player.rate - settings.playbackRateIncrementDecrement) }
        .disabled(player.rate <= 0.5)
    } label: {
      Text(Format.rate(player.rate))
        .font(.system(size: 11, weight: .semibold).monospacedDigit())
        .foregroundStyle(
          abs(player.rate - 1) < 0.001 ? .white.opacity(hover ? 0.9 : 0.6) : Theme.accent
        )
        .padding(.horizontal, 7)
        .frame(minWidth: 38)
        .frame(height: 22)
        .background(Capsule().stroke(Color.white.opacity(hover ? 0.3 : 0.15)))
        .contentShape(Capsule())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .onHover { hover = $0 }
    .help("Playback speed")
  }
}
