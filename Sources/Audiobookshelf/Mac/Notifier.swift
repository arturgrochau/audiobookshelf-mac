import Foundation
import UserNotifications

/// UNUserNotificationCenter throws an exception when the process is not a real
/// app bundle (e.g. `swift run`), so every call is guarded.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
  static let shared = Notifier()
  private var authorized = false
  private var available: Bool {
    Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
  }

  func requestAuthorization() {
    guard available else { return }
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
      Task { @MainActor in Notifier.shared.authorized = ok }
    }
  }

  /// Show banners while the app is in front too.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  func post(title: String, body: String, id: String = UUID().uuidString) {
    guard available else { return }
    let c = UNMutableNotificationContent()
    c.title = title
    c.body = body
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: id, content: c, trigger: nil))
  }
}
