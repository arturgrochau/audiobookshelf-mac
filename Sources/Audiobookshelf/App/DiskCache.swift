import ABSCore
import Foundation

/// JSON snapshots of server data, so the app paints instantly at launch and
/// keeps working offline. Scoped to the signed-in server and user.
final class DiskCache: @unchecked Sendable {
  static let shared = DiskCache()
  private let queue = DispatchQueue(label: "abs.diskcache", qos: .utility)
  private let root: URL

  private init() {
    root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("com.arturgrochau.audiobookshelf-mac/data", isDirectory: true)
  }

  /// Set by AppModel when an account is configured: "<host>-<userId>".
  var scopeKey = "anon"

  private var scope: URL { root.appendingPathComponent(scopeKey, isDirectory: true) }

  private func file(_ name: String) -> URL {
    scope.appendingPathComponent(name.replacingOccurrences(of: "/", with: "_") + ".json")
  }

  func save<T: Encodable>(_ value: T, _ name: String) {
    let url = file(name)
    guard let data = try? JSONEncoder().encode(value) else { return }
    queue.async {
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: url, options: .atomic)
    }
  }

  func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
    guard let d = try? Data(contentsOf: file(name)) else { return nil }
    return try? JSONDecoder().decode(T.self, from: d)
  }

  func saveRaw(_ data: Data, _ name: String) {
    let url = file(name)
    queue.async {
      try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: url, options: .atomic)
    }
  }

  func loadRaw(_ name: String) -> Data? { try? Data(contentsOf: file(name)) }

  func clearAll() {
    let dir = scope
    queue.async { try? FileManager.default.removeItem(at: dir) }
  }
}
