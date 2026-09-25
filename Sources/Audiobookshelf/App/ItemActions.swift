import ABSCore
import AppKit
import Foundation

/// Item-level actions shared by cards, the item page and menus.
@MainActor
enum ItemActions {
  static var app: AppModel { AppModel.shared }

  /// PATCH /api/me/progress/:id {isFinished}, updated locally first.
  static func setFinished(_ itemId: String, _ finished: Bool) async {
    let now = Date().timeIntervalSince1970 * 1000
    var p =
      app.progress(for: itemId)
      ?? MediaProgress(id: UUID().uuidString, libraryItemId: itemId, startedAt: now)
    let before = p
    p.isFinished = finished
    p.finishedAt = finished ? now : nil
    if finished { p.progress = 1 }
    p.lastUpdate = now
    app.updateLocalProgress(p)
    do {
      try await app.api.updateProgress(itemId: itemId, ["isFinished": .bool(finished)])
      if let fresh = try? await app.api.progress(itemId: itemId) { app.updateLocalProgress(fresh) }
    } catch {
      app.updateLocalProgress(before)
      app.toast(L.s("ToastItemMarkedAsFinishedFailed"), .error)
    }
    LibraryStore.shared.revision += 1
  }

  /// DELETE /api/me/progress/:progressId (the reset ✕ on the progress box).
  static func resetProgress(_ p: MediaProgress) async {
    do {
      try await app.api.removeProgress(progressId: p.id)
      if var u = app.user {
        u.mediaProgress?.removeAll { $0.id == p.id }
        app.user = u
      }
      LibraryStore.shared.revision += 1
    } catch {
      app.toast(L.s("ToastFailedToUpdate"), .error)
    }
  }

  static func hideFromContinue(_ p: MediaProgress) async {
    do {
      try await app.api.hideFromContinueListening(progressId: p.id)
      var np = p
      np.hideFromContinueListening = true
      app.updateLocalProgress(np)
      await LibraryStore.shared.refreshHome()
    } catch {
      app.toast(L.s("ToastFailedToUpdate"), .error)
    }
  }

  /// Chapter start in the item page table: seek if it is the current item, else play from there.
  static func playFrom(_ item: LibraryItem, time: Double) async {
    let player = PlayerModel.shared
    if player.item?.id == item.id {
      player.seek(to: time)
    } else {
      await player.play(item.id, startTime: time)
    }
  }
}

/// Ebook reader windows (phase 6). Until then the web reader opens in the browser.
@MainActor
enum ReaderWindows {
  static func open(itemId: String) {
    guard let base = AppModel.shared.webURL else { return }
    NSWorkspace.shared.open(base.appendingPathComponent("item").appendingPathComponent(itemId))
  }
}
