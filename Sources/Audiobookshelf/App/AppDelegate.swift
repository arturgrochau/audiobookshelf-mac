import ABSCore
import AppKit
import SwiftUI

/// Owns the main window (AppKit, so closing it keeps playback and the Dock
/// icon reopens it), the web keyboard shortcuts, URL events and quit flush.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  static private(set) weak var shared: AppDelegate?
  private(set) var window: NSWindow?
  private var keyMonitor: Any?
  private var servicesStarted = false

  func applicationWillFinishLaunching(_ notification: Notification) {
    Self.shared = self
    Theme.registerFonts()
    NSAppleEventManager.shared().setEventHandler(
      self, andSelector: #selector(handleURL(_:reply:)),
      forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSWindow.allowsAutomaticWindowTabbing = false
    Notifier.shared.requestAuthorization()
    makeWindow()
    installKeyMonitor()
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification,
      object: nil)
    Task {
      await AppModel.shared.restore()
      await debugLoginIfRequested()
      startServicesIfNeeded()
    }
  }

  /// Test hook: `open --env ABS_TEST_SERVER=… --env ABS_TEST_USER=… --env ABS_TEST_PASS=…`
  /// logs in without typing into the UI. Ignored when already logged in.
  private func debugLoginIfRequested() async {
    let env = ProcessInfo.processInfo.environment
    guard !AppModel.shared.isLoggedIn, let s = env["ABS_TEST_SERVER"], let server = URL(string: s),
      let user = env["ABS_TEST_USER"], let pass = env["ABS_TEST_PASS"]
    else { return }
    let local = env["ABS_TEST_LOCAL"].flatMap(URL.init(string:))
    do {
      try await AppModel.shared.login(server: server, local: local, username: user, password: pass)
    } catch {
      NSLog("ABS test login failed: \(error)")
    }
  }

  /// Logout: the next login starts the services again.
  func resetServices() { servicesStarted = false }

  /// Called once there is a logged-in account (restore or login).
  func startServicesIfNeeded() {
    guard AppModel.shared.isLoggedIn, !servicesStarted else { return }
    servicesStarted = true
    LibraryStore.shared.start()
    PlayerModel.shared.hookSocket()
    NowPlaying.shared.registerCommands()
    Task { await LocalSessionStore.shared.flush() }
  }

  // MARK: Window

  private func makeWindow() {
    let host = NSHostingController(rootView: RootView())
    host.sizingOptions = []
    let w = NSWindow(contentViewController: host)
    w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    w.titlebarAppearsTransparent = true
    w.titleVisibility = .hidden
    w.title = "Audiobookshelf"
    w.isReleasedWhenClosed = false
    w.backgroundColor = NSColor(Theme.bg)
    w.minSize = NSSize(width: 900, height: 560)
    w.delegate = self
    w.setContentSize(NSSize(width: 1400, height: 900))
    if !w.setFrameUsingName("MainWindow") { w.center() }
    w.setFrameAutosaveName("MainWindow")
    w.tabbingMode = .disallowed
    window = w
    w.makeKeyAndOrderFront(nil)
  }

  func showWindow() {
    if window == nil { makeWindow() }
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !(window?.isVisible ?? false) { showWindow() }
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  // MARK: Dock menu

  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let p = PlayerModel.shared
    guard p.hasItem else { return nil }
    let m = NSMenu()
    m.addItem(
      ClosureMenuItem(p.isPlaying ? L.s("ButtonPause") : L.s("ButtonPlay")) { p.playPause() })
    m.addItem(ClosureMenuItem("Jump Forward") { p.jumpForward() })
    m.addItem(ClosureMenuItem("Jump Backward") { p.jumpBackward() })
    m.addItem(ClosureMenuItem(L.s("ButtonNextChapter")) { p.next() })
    return m
  }

  // MARK: Quit

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard PlayerModel.shared.hasItem else { return .terminateNow }
    Task {
      await withTaskGroup(of: Void.self) { g in
        g.addTask { await PlayerModel.shared.flushForQuit() }
        g.addTask { try? await Task.sleep(for: .seconds(3)) }
        await g.next()
        g.cancelAll()
      }
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  @objc private func systemWillSleep(_ n: Notification) {
    if PlayerModel.shared.isPlaying { PlayerModel.shared.pause() }
  }

  // MARK: URL scheme (never raises the window)

  @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
    guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
      let url = URL(string: s)
    else { return }
    URLRoutes.handle(url)
  }

  // MARK: Web keyboard shortcuts (plugins/constants.js Hotkeys.AudioPlayer)

  private func installKeyMonitor() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
      guard let self else { return e }
      return self.handleKey(e) ? nil : e
    }
  }

  private func handleKey(_ e: NSEvent) -> Bool {
    guard e.window === window, let win = window else { return false }
    if win.firstResponder is NSText || win.firstResponder is NSTextView { return false }
    let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
    let p = PlayerModel.shared
    let modalOpen =
      p.showChapters || p.showBookmarks || p.showSleepTimer || p.showQueue || p.showPlayerSettings
    if e.keyCode == 53 {  // Escape
      if modalOpen {
        p.showChapters = false
        p.showBookmarks = false
        p.showSleepTimer = false
        p.showQueue = false
        p.showPlayerSettings = false
        return true
      }
      if p.hasItem {
        Task { await p.close() }
        return true
      }
      return false
    }
    guard p.hasItem, !modalOpen else { return false }
    switch (e.keyCode, mods) {
    case (49, []) where !e.isARepeat: p.playPause()  // Space
    case (124, [.option]): p.jumpForward()
    case (123, [.option]): p.jumpBackward()
    case (124, [.command]): p.next()
    case (123, [.command]): p.previousChapter()
    case (124, []): p.jumpForward()
    case (123, []): p.jumpBackward()
    case (126, []): if p.volume < 1 { p.setVolume(min(1, p.volume + 0.1)) }
    case (125, []): if p.volume > 0 { p.setVolume(max(0, p.volume - 0.1)) }
    case (126, [.shift]): p.increaseRate()
    case (125, [.shift]): p.decreaseRate()
    case (46, []) where !e.isARepeat: p.toggleMute()  // M
    case (37, []) where !e.isARepeat: p.showChapters = true  // L
    default: return false
    }
    return true
  }

  // MARK: NSWindowDelegate

  func windowWillClose(_ notification: Notification) {}
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
  private let handler: () -> Void
  init(_ title: String, _ handler: @escaping () -> Void) {
    self.handler = handler
    super.init(title: title, action: #selector(fire), keyEquivalent: "")
    target = self
  }
  required init(coder: NSCoder) { fatalError() }
  @objc private func fire() { handler() }
}

/// audiobookshelf:// verbs, shared with the loopback control port.
@MainActor
enum URLRoutes {
  static func handle(_ url: URL) {
    let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func v(_ k: String) -> String? { q.first { $0.name == k }?.value }
    let verb = url.host ?? ""
    let p = PlayerModel.shared
    switch verb {
    case "play-pause": p.playPause()
    case "play": if !p.isPlaying { p.resume() }
    case "pause": p.pause()
    case "jump-forward": p.jumpForward()
    case "jump-backward": p.jumpBackward()
    case "next-chapter": p.next()
    case "prev-chapter": p.previousChapter()
    case "speed-up": p.increaseRate()
    case "speed-down": p.decreaseRate()
    case "speed": if let r = v("v").flatMap(Double.init) { p.setRate(r) }
    case "sleep":
      if v("eoc") != nil {
        p.setSleepTimerEndOfChapter()
      } else if let m = v("m").flatMap(Double.init) {
        p.setSleepTimer(seconds: m * 60)
      }
    case "sleep-cancel": p.cancelSleepTimer()
    case "close": Task { await p.close() }
    case "open":
      if let id = v("item") {
        AppModel.shared.go(.item(id))
        AppDelegate.shared?.showWindow()
      }
    case "route":
      // Debug navigation for screenshots: audiobookshelf://route?r=home|library|item&id=…
      let app = AppModel.shared
      switch v("r") ?? "" {
      case "home": app.go(.home)
      case "library": app.go(.library)
      case "series": app.go(.series)
      case "authors": app.go(.authors)
      case "collections": app.go(.collections)
      case "narrators": app.go(.narrators)
      case "stats": app.go(.stats)
      case "account": app.go(.account)
      case "search": if let q = v("q") { app.go(.search(q)) }
      case "item": if let id = v("id") { app.go(.item(id)) }
      case "author": if let id = v("id") { app.go(.author(id)) }
      case "playitem": if let id = v("id") { Task { await p.play(id) } }
      case "download": if let id = v("id") { Task { await DownloadManager.shared.download(id) } }
      case "remove-download": if let id = v("id") { DownloadManager.shared.remove(id) }
      case "seek": if let t = v("t").flatMap(Double.init) { p.seek(to: t) }
      case "modal":
        switch v("m") ?? "" {
        case "sleep": p.showSleepTimer = true
        case "chapters": p.showChapters = true
        case "bookmarks": p.showBookmarks = true
        case "queue": p.showQueue = true
        case "settings": p.showPlayerSettings = true
        default: break
        }
      default: break
      }
    default: break
    }
  }
}
