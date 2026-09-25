import ABSCore
import AppKit
import SwiftUI

@main
struct AudiobookshelfApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

  var body: some Scene {
    Settings {
      SettingsView()
    }
    .commands { AppCommands() }
  }
}

/// Menu bar commands: View (rail pages, cover size) and Controls (player).
struct AppCommands: Commands {
  var app = AppModel.shared
  var player = PlayerModel.shared
  var settings = AppSettings.shared

  var body: some Commands {
    CommandGroup(after: .appSettings) {
      if app.user?.isAdminOrUp == true {
        Button("Open Server Settings in Browser") {
          if let u = app.webURL { NSWorkspace.shared.open(u.appendingPathComponent("config")) }
        }
      }
      if app.isLoggedIn {
        Button(L.s("ButtonLogout")) { Task { await app.logout() } }
      }
    }
    CommandGroup(replacing: .newItem) {}
    CommandGroup(before: .toolbar) {
      Button(L.s("ButtonHome")) { app.go(.home) }.keyboardShortcut("1")
      Button(L.s("ButtonLibrary")) { app.go(.library) }.keyboardShortcut("2")
      Button(L.s("ButtonSeries")) { app.go(.series) }.keyboardShortcut("3")
      Button(L.s("ButtonCollections")) { app.go(.collections) }.keyboardShortcut("4")
      Button(L.s("ButtonPlaylists")) { app.go(.playlists) }.keyboardShortcut("5")
      Button(L.s("ButtonAuthors")) { app.go(.authors) }.keyboardShortcut("6")
      Button(L.s("LabelNarrators")) { app.go(.narrators) }.keyboardShortcut("7")
      Divider()
      Button("Back") { app.goBack() }.keyboardShortcut("[").disabled(!app.canGoBack)
      Button("Forward") { app.goForward() }.keyboardShortcut("]").disabled(!app.canGoForward)
      Divider()
      Button("Larger Covers") {
        settings.bookshelfCoverSize = min(220, settings.bookshelfCoverSize + 20)
      }
      .keyboardShortcut("+")
      Button("Smaller Covers") {
        settings.bookshelfCoverSize = max(60, settings.bookshelfCoverSize - 20)
      }
      .keyboardShortcut("-")
      Toggle(L.s("LabelShowSubtitles"), isOn: Bindable(settings).showSubtitles)
      Divider()
    }
    CommandMenu("Controls") {
      Button(player.isPlaying ? L.s("ButtonPause") : L.s("ButtonPlay")) { player.playPause() }
        .disabled(!player.hasItem)
      // ⌥←/⌥→ and ⌘←/⌘→ are handled by the window's key monitor, not as menu
      // key equivalents, so they keep moving the caret inside text fields.
      Button("Jump Forward  ⌥→") { player.jumpForward() }
        .disabled(!player.hasItem)
      Button("Jump Backward  ⌥←") { player.jumpBackward() }
        .disabled(!player.hasItem)
      Button(L.s("ButtonNextChapter") + "  ⌘→") { player.next() }
        .disabled(!player.hasItem)
      Button(L.s("ButtonPreviousChapter") + "  ⌘←") { player.previousChapter() }
        .disabled(!player.hasItem)
      Divider()
      Menu("Speed") {
        ForEach([0.5, 1, 1.2, 1.5, 2], id: \.self) { r in
          Button(Format.rate(r)) { player.setRate(r) }
        }
        Divider()
        Button("Faster") { player.increaseRate() }
        Button("Slower") { player.decreaseRate() }
      }
      .disabled(!player.hasItem)
      Menu(L.s("HeaderSleepTimer")) {
        ForEach([5, 15, 20, 30, 45, 60, 90, 120], id: \.self) { m in
          Button(m < 60 ? "\(m) min" : m == 60 ? "60 min" : m == 90 ? "90 min" : "2 hr") {
            player.setSleepTimer(seconds: Double(m) * 60)
          }
        }
        Button(L.s("LabelEndOfChapter")) { player.setSleepTimerEndOfChapter() }
        Divider()
        Button(L.s("ButtonCancel")) { player.cancelSleepTimer() }
      }
      .disabled(!player.hasItem)
      Divider()
      Button(L.s("LabelYourBookmarks")) { player.showBookmarks = true }
        .keyboardShortcut("d")
        .disabled(!player.hasItem)
      Button(L.s("HeaderChapters")) { player.showChapters = true }
        .disabled(!player.hasItem)
    }
  }
}

/// Settings window (phase 4 fills it in).
struct SettingsView: View {
  var settings = AppSettings.shared

  var body: some View {
    Form {
      Toggle("Disable auto rewind", isOn: Bindable(settings).disableAutoRewind)
      Toggle("Disable sleep timer fade out", isOn: Bindable(settings).disableSleepTimerFadeOut)
      Toggle(
        "Allow seeking from media controls", isOn: Bindable(settings).allowSeekingOnMediaControls)
      Toggle("Next and previous skip chapters", isOn: Bindable(settings).nextPrevSkipsChapters)
    }
    .formStyle(.grouped)
    .frame(width: 460)
    .padding()
  }
}
