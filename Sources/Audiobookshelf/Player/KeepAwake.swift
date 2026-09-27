import AppKit
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import Observation

/// The ☕ toggle: keep the Mac awake while a book plays, lid closed included.
///
/// Lid open, an idle-sleep assertion is enough. Lid closed, macOS sleeps no
/// matter what an app asserts (PreventSystemSleep is 0 on current Macs), unless
/// `pmset -a disablesleep 1` is set, which needs root. A one-time sudoers rule,
/// installed through the standard admin password prompt, allows exactly
/// `pmset -a disablesleep 0|1` and nothing else.
///
/// A Mac that cannot sleep in a closed bag gets hot, so the hold is released
/// whenever listening stops: paused for 2 minutes, book finished, sleep timer
/// fired (which also turns the toggle off), app quit, or battery under 20%.
/// If the app dies holding it, a detached watchdog releases it within 20 s,
/// and the next launch clears anything left over.
@MainActor @Observable
final class KeepAwake {
  static let shared = KeepAwake()

  private(set) var enabled: Bool
  private(set) var lidHeld = false
  /// pmset runs synchronously, and waiting on it spins the main run loop, so
  /// a play/pause callback can re-enter apply() mid-call. This keeps that from
  /// starting a second hold and a second watchdog.
  private var lidPending = false
  var lidSupported: Bool { FileManager.default.fileExists(atPath: Self.sudoersPath) }

  private static let sudoersPath = "/etc/sudoers.d/audiobookshelf-lid"
  private static let marker: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Audiobookshelf", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("lid-hold")
  }()

  private var assertion: IOPMAssertionID = 0
  private var releaseTask: Task<Void, Never>?
  private var batteryTimer: Timer?
  private var watchdog: Process?

  private init() {
    enabled = UserDefaults.standard.bool(forKey: "keepAwake")
    // A previous run that crashed or was killed while holding the lid.
    // No toast from here: AppModel may not exist yet. A failed release keeps
    // the marker, so the next launch tries again.
    if FileManager.default.fileExists(atPath: Self.marker.path), Self.pmset(false) {
      try? FileManager.default.removeItem(at: Self.marker)
    }
  }

  // MARK: Inputs

  func toggle() {
    setEnabled(!enabled)
    if enabled, !lidSupported, !UserDefaults.standard.bool(forKey: "lidSetupDeclined") {
      if offerLidSetup() { return }  // setup showed its own toast
    }
    AppModel.shared.toast(
      enabled
        ? (lidSupported
          ? "Keeping the Mac awake while playing, lid closed too."
          : "Keeping the Mac awake while playing.")
        : "The Mac can sleep again.", .info, duration: 2.5)
  }

  func playbackChanged(playing: Bool) {
    if playing {
      releaseTask?.cancel()
      releaseTask = nil
      apply()
    } else if hasHold {
      // A short pause keeps the hold; walking away does not.
      releaseTask?.cancel()
      releaseTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(120))
        guard !Task.isCancelled else { return }
        self?.releaseAll()
      }
    }
  }

  func sleepTimerFired() {
    guard enabled else { return }
    setEnabled(false)
  }

  /// Called from applicationShouldTerminate.
  func releaseForQuit() { releaseAll() }

  // MARK: State

  private var hasHold: Bool { assertion != 0 || lidHeld }

  private func setEnabled(_ on: Bool) {
    enabled = on
    UserDefaults.standard.set(on, forKey: "keepAwake")
    if on { apply() } else { releaseAll() }
  }

  private func apply() {
    guard enabled, PlayerModel.shared.isPlaying else { return }
    if assertion == 0 {
      var id: IOPMAssertionID = 0
      let ok = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "Audiobookshelf is playing" as CFString, &id)
      if ok == kIOReturnSuccess { assertion = id }
    }
    if lidSupported, !lidHeld, !lidPending, Self.batteryOK() {
      lidPending = true
      defer { lidPending = false }
      if Self.pmset(true) {
        lidHeld = true
        FileManager.default.createFile(atPath: Self.marker.path, contents: nil)
        startWatchdog()
        startBatteryWatch()
      }
    }
  }

  /// Give sleep back. The marker only goes once pmset confirms it, because
  /// `disablesleep 1` survives reboots: a failed release is retried at the
  /// next launch and the user is told how to undo it by hand.
  private func releaseLid() {
    if Self.pmset(false) {
      try? FileManager.default.removeItem(at: Self.marker)
    } else {
      AppModel.shared.toast(
        "Could not restore lid sleep. Run: sudo pmset -a disablesleep 0", .warning, duration: 8)
    }
    lidHeld = false
  }

  private func releaseAll() {
    releaseTask?.cancel()
    releaseTask = nil
    if assertion != 0 {
      IOPMAssertionRelease(assertion)
      assertion = 0
    }
    if lidHeld { releaseLid() }
    watchdog?.terminate()
    watchdog = nil
    batteryTimer?.invalidate()
    batteryTimer = nil
  }

  // MARK: Lid hold

  @discardableResult
  private static func pmset(_ disable: Bool) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    p.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", disable ? "1" : "0"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
  }

  /// Outlives a crash: once this app's pid is gone, give sleep back.
  private func startWatchdog() {
    watchdog?.terminate()
    let pid = ProcessInfo.processInfo.processIdentifier
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    // Values go in as arguments, never pasted into the script.
    p.arguments = [
      "-c",
      "while kill -0 \"$1\" 2>/dev/null; do sleep 20; done; "
        + "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 && rm -f \"$2\"",
      "sh", "\(pid)", Self.marker.path,
    ]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
    watchdog = p
  }

  private func startBatteryWatch() {
    batteryTimer?.invalidate()
    let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.lidHeld, !Self.batteryOK() else { return }
        self.releaseLid()
        self.watchdog?.terminate()
        self.watchdog = nil
        AppModel.shared.toast("Battery low: the Mac will sleep when the lid closes.", .warning)
      }
    }
    RunLoop.main.add(t, forMode: .common)
    batteryTimer = t
  }

  /// On AC, or on battery above 20%.
  private static func batteryOK() -> Bool {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return true }
    for ps in list {
      guard
        let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue()
          as? [String: Any]
      else { continue }
      if (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue { return true }
      if let cap = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int,
        max > 0
      {
        return Double(cap) / Double(max) >= 0.2
      }
    }
    return true
  }

  // MARK: One-time setup

  /// Returns true when it handled the user-facing message itself.
  private func offerLidSetup() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Keep playing with the lid closed?"
    alert.informativeText =
      "macOS sleeps when the lid closes, whatever an app asks. Audiobookshelf can switch "
      + "that off while a book plays and back on the moment it stops. That needs permission "
      + "for one command (pmset disablesleep), asked once with your password.\n\n"
      + "Without it, the Mac still stays awake while playing with the lid open."
    alert.addButton(withTitle: "Allow")
    alert.addButton(withTitle: "Lid Open Only")
    guard alert.runModal() == .alertFirstButtonReturn else {
      UserDefaults.standard.set(true, forKey: "lidSetupDeclined")
      return false
    }

    let user = NSUserName()
    // The name goes into a root shell and a sudoers line: short names only.
    guard user.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
      return false
    }
    let rule =
      "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
    // The rule is written, checked and moved into place entirely inside the
    // root shell, staged in /etc/sudoers.d itself (root-owned; sudo ignores
    // names with a dot). Staging anywhere the user can write, their temp dir
    // included, would let a process running as them swap the file between
    // visudo's check and the install.
    let shell =
      "umask 077; t=$(/usr/bin/mktemp /etc/sudoers.d/.abs-lid.XXXXXX) && "
      + "printf '%s\\\\n' '\(rule)' > \\\"$t\\\" && /usr/sbin/visudo -cf \\\"$t\\\" && "
      + "/usr/sbin/chown root:wheel \\\"$t\\\" && /bin/chmod 0440 \\\"$t\\\" && "
      + "/bin/mv -f \\\"$t\\\" '\(Self.sudoersPath)'; "
      + "s=$?; rm -f \\\"$t\\\"; exit $s"
    let script = "do shell script \"\(shell)\" with administrator privileges"
    var err: NSDictionary?
    NSAppleScript(source: script)?.executeAndReturnError(&err)
    if lidSupported {
      apply()
      AppModel.shared.toast("Done: playback continues with the lid closed.", .success)
      return true
    }
    if err != nil {
      AppModel.shared.toast("Not set up. The Mac stays awake with the lid open only.", .warning)
      return true
    }
    return false
  }
}
