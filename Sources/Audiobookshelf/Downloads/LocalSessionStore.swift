import ABSCore
import Foundation

/// Outbox of listening sessions recorded offline. Sent to
/// /api/session/local-all at launch, when the network returns, and before a
/// server session is opened for the same book (/play starts from the server's
/// progress, so the server must have ours first).
@MainActor
final class LocalSessionStore {
  static let shared = LocalSessionStore()
  private var sessions: [LocalSession] = []
  private let url: URL

  private init() {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Audiobookshelf", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    url = dir.appendingPathComponent("local-sessions.json")
    if let d = try? Data(contentsOf: url),
      let s = try? JSONDecoder().decode([LocalSession].self, from: d)
    {
      sessions = s
    }
  }

  var pending: [LocalSession] { sessions.filter { !$0.synced } }

  func upsert(_ s: LocalSession) {
    if let i = sessions.firstIndex(where: { $0.id == s.id }) {
      sessions[i] = s
    } else {
      sessions.append(s)
    }
    save()
  }

  func latest(itemId: String) -> LocalSession? {
    sessions.filter { $0.libraryItemId == itemId }.max { $0.updatedAt < $1.updatedAt }
  }

  func flush(itemId: String? = nil) async {
    let toSend = pending.filter { itemId == nil || $0.libraryItemId == itemId }
    guard !toSend.isEmpty else { return }
    let body = LocalSessionsBody(deviceInfo: PlayerModel.shared.deviceInfo, sessions: toSend)
    guard let r = try? await AppModel.shared.api.syncLocalSessions(body) else { return }
    let ok = Set(r.results.filter(\.success).map(\.id))
    // Only what was sent is synced: a session updated while the request was
    // in flight keeps its newer state pending.
    let sentAt = Dictionary(toSend.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { a, _ in a })
    for i in sessions.indices
    where ok.contains(sessions[i].id) && sessions[i].updatedAt == sentAt[sessions[i].id] {
      sessions[i].synced = true
    }
    // Keep a week of synced sessions for "last position" lookups.
    let cutoff = (Date().timeIntervalSince1970 - 7 * 86400) * 1000
    sessions.removeAll { $0.synced && $0.updatedAt < cutoff }
    save()
  }

  private func save() {
    if let d = try? JSONEncoder().encode(sessions) { try? d.write(to: url, options: .atomic) }
  }
}
