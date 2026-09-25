import ABSCore
import AppKit
import Foundation
import Observation

/// Downloads a book's audio files, cover and expanded item JSON into
/// `<downloads>/<Author>/<Title>/` (mobile AbsDownloader.kt layout).
///
/// Three files download at once; a file that fails or stalls for 60 s is
/// retried up to 5 times (resuming when possible); a 401 refreshes the token
/// first. Each request is built just before it starts, with a fresh token.
@MainActor @Observable
final class DownloadManager: NSObject {
  static let shared = DownloadManager()

  enum State: Equatable {
    case none
    case queued
    case downloading(Double)
    case done
    case failed(String)
  }

  struct FileEntry: Codable, Hashable {
    var ino: String
    var filename: String
    var index: Int
    var startOffset: Double
    var duration: Double
    var size: Int64?
  }

  struct Record: Codable, Hashable {
    var itemId: String
    var libraryId: String?
    var title: String
    var author: String
    var folder: String
    var files: [FileEntry]
    var completed: Bool
    var addedAt: Date
    var completedAt: Date?
    var finishedAt: Date?
  }

  private(set) var records: [String: Record] = [:]
  private(set) var states: [String: State] = [:]
  private(set) var revision = 0

  private struct Job {
    var itemId: String
    var file: FileEntry
    var destination: URL
    var attempts = 0
    var resumeData: Data?
    var lastProgress = Date()
    var bytesWritten: Int64 = 0
  }

  private var pending: [Job] = []
  private var active: [Int: Job] = [:]
  private var bytesDone: [String: Int64] = [:]
  private var bytesTotal: [String: Int64] = [:]
  private var session: URLSession!
  private var stallTimer: Timer?
  private let indexURL: URL
  private let maxConcurrent = 3

  private override init() {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Audiobookshelf", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    indexURL = dir.appendingPathComponent("downloads.json")
    super.init()
    let cfg = URLSessionConfiguration.default
    cfg.httpShouldSetCookies = false
    cfg.timeoutIntervalForRequest = 60
    cfg.timeoutIntervalForResource = 60 * 60 * 6
    session = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
    if let d = try? Data(contentsOf: indexURL),
      let r = try? JSONDecoder().decode([String: Record].self, from: d)
    {
      records = r
      for (id, rec) in r { states[id] = rec.completed ? .done : .failed("Interrupted") }
    }
  }

  var root: URL { URL(fileURLWithPath: AppSettings.shared.downloadsFolder, isDirectory: true) }

  func state(_ itemId: String) -> State { states[itemId] ?? .none }
  func isDownloaded(_ itemId: String) -> Bool { records[itemId]?.completed == true }
  var downloadedIds: [String] {
    records.values.filter(\.completed).sorted { $0.addedAt > $1.addedAt }.map(\.itemId)
  }

  // MARK: Local playback

  /// Local track sources for a fully downloaded book.
  func localTracks(for item: LibraryItem) -> [TrackSource]? {
    guard let rec = records[item.id], rec.completed else { return nil }
    let folder = URL(fileURLWithPath: rec.folder, isDirectory: true)
    let sources = rec.files.sorted { $0.startOffset < $1.startOffset }.map {
      TrackSource(
        url: folder.appendingPathComponent($0.filename), startOffset: $0.startOffset,
        duration: $0.duration)
    }
    guard sources.allSatisfy({ FileManager.default.fileExists(atPath: $0.url.path) }) else {
      return nil
    }
    return sources
  }

  /// The expanded item saved with the download (works offline).
  func storedItem(_ itemId: String) -> LibraryItem? {
    guard let rec = records[itemId] else { return nil }
    let url = URL(fileURLWithPath: rec.folder).appendingPathComponent("item.json")
    return (try? Data(contentsOf: url)).flatMap {
      try? JSONDecoder().decode(LibraryItem.self, from: $0)
    }
  }

  func localCoverURL(_ itemId: String) -> URL? {
    guard let rec = records[itemId] else { return nil }
    let u = URL(fileURLWithPath: rec.folder).appendingPathComponent("cover.jpg")
    return FileManager.default.fileExists(atPath: u.path) ? u : nil
  }

  // MARK: Start / cancel / remove

  func download(_ itemId: String) async {
    guard states[itemId] != .queued, !(isDownloaded(itemId)) else { return }
    if case .downloading = state(itemId) { return }
    guard AppModel.shared.user?.permissions?.download != false else {
      AppModel.shared.toast("You do not have permission to download", .error)
      return
    }
    // Claim the item before the first await so a double click queues it once.
    states[itemId] = .queued
    guard let item = await LibraryStore.shared.expandedItem(itemId) else {
      states[itemId] = nil
      AppModel.shared.toast("Could not load this item", .error)
      return
    }
    let tracks = (item.media.tracks ?? []).sorted { $0.startOffset < $1.startOffset }
    guard !tracks.isEmpty else {
      states[itemId] = nil
      AppModel.shared.toast("Nothing to download", .warning)
      return
    }
    let files: [FileEntry] = tracks.compactMap { t in
      let ino = t.contentUrl.flatMap { $0.split(separator: "/").last.map(String.init) } ?? ""
      guard !ino.isEmpty else { return nil }
      let name = Self.clean(
        t.metadata?.filename
          ?? "track-\(t.index).\(t.metadata?.ext?.replacingOccurrences(of: ".", with: "") ?? "mp3")"
      )
      return FileEntry(
        ino: ino, filename: name, index: t.index, startOffset: t.startOffset, duration: t.duration,
        size: t.metadata?.size)
    }
    let author = Self.clean(item.authorLine.isEmpty ? "Unknown Author" : item.authorLine)
    let title = Self.clean(item.title.isEmpty ? item.id : item.title)
    let folder = root.appendingPathComponent(author, isDirectory: true).appendingPathComponent(
      title, isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    if let d = try? JSONEncoder().encode(item) {
      try? d.write(to: folder.appendingPathComponent("item.json"))
    }
    if let cover = AppModel.shared.coverURL(item, width: 800),
      let (d, r) = try? await URLSession.shared.data(from: cover),
      (r as? HTTPURLResponse)?.statusCode == 200
    {
      try? d.write(to: folder.appendingPathComponent("cover.jpg"))
    }
    // Cancelled while the item and cover were loading.
    guard states[itemId] == .queued else { return }
    records[itemId] = Record(
      itemId: itemId, libraryId: item.libraryId, title: item.title, author: item.authorLine,
      folder: folder.path, files: files, completed: false, addedAt: Date())
    bytesTotal[itemId] = files.reduce(0) { $0 + ($1.size ?? 0) }
    bytesDone[itemId] = 0
    for f in files {
      let dest = folder.appendingPathComponent(f.filename)
      if let size = f.size,
        let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
        (attrs[.size] as? Int64) == size
      {
        bytesDone[itemId, default: 0] += size
        continue
      }
      pending.append(Job(itemId: itemId, file: f, destination: dest))
    }
    states[itemId] = .queued
    saveIndex()
    pump()
    checkCompleted(itemId)
  }

  func cancel(_ itemId: String) {
    if records[itemId] == nil { states[itemId] = nil }
    pending.removeAll { $0.itemId == itemId }
    for (tid, job) in active where job.itemId == itemId {
      session.getAllTasks { tasks in tasks.first { $0.taskIdentifier == tid }?.cancel() }
      active[tid] = nil
    }
    remove(itemId)
  }

  func remove(_ itemId: String) {
    if let rec = records[itemId] {
      try? FileManager.default.removeItem(atPath: rec.folder)
      let parent = URL(fileURLWithPath: rec.folder).deletingLastPathComponent()
      if (try? FileManager.default.contentsOfDirectory(atPath: parent.path))?.isEmpty == true {
        try? FileManager.default.removeItem(at: parent)
      }
    }
    records[itemId] = nil
    states[itemId] = nil
    revision += 1
    saveIndex()
  }

  func showInFinder(_ itemId: String) {
    guard let rec = records[itemId] else { return }
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: rec.folder)])
  }

  var totalBytes: Int64 {
    records.values.reduce(0) { acc, r in acc + r.files.reduce(0) { $0 + ($1.size ?? 0) } }
  }

  // MARK: Queue

  /// Jobs between leaving `pending` and getting a task (awaiting the token).
  private var startingJobs: [String: Int] = [:]
  private var startingCount: Int { startingJobs.values.reduce(0, +) }

  private func pump() {
    while active.count + startingCount < maxConcurrent, !pending.isEmpty {
      let job = pending.removeFirst()
      startingJobs[job.itemId, default: 0] += 1
      Task {
        await self.start(job)
        self.startingJobs[job.itemId, default: 1] -= 1
        if self.startingJobs[job.itemId] == 0 { self.startingJobs[job.itemId] = nil }
        self.checkCompleted(job.itemId)
      }
    }
    if stallTimer == nil, !active.isEmpty || !pending.isEmpty || startingCount > 0 {
      stallTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
        MainActor.assumeIsolated { DownloadManager.shared.checkStalls() }
      }
    }
  }

  private func start(_ job: Job) async {
    let api = AppModel.shared.api
    let base = AppModel.shared.streamBase
    let token = await api.tokens.access ?? ""
    // Cancelled or removed while waiting for the token.
    guard records[job.itemId] != nil else { return }
    var req = URLRequest(
      url: base.appendingPathComponent("api/items/\(job.itemId)/file/\(job.file.ino)/download"))
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let task: URLSessionDownloadTask
    if let resume = job.resumeData {
      task = session.downloadTask(withResumeData: resume)
    } else {
      task = session.downloadTask(with: req)
    }
    var j = job
    j.lastProgress = Date()
    active[task.taskIdentifier] = j
    states[job.itemId] = .downloading(progress(job.itemId))
    task.resume()
  }

  private func progress(_ itemId: String) -> Double {
    let total = max(1, bytesTotal[itemId] ?? 1)
    let inflightBytes = active.values.filter { $0.itemId == itemId }.reduce(Int64(0)) {
      $0 + $1.bytesWritten
    }
    return min(1, Double((bytesDone[itemId] ?? 0) + inflightBytes) / Double(total))
  }

  private func checkStalls() {
    let now = Date()
    for (tid, job) in active where now.timeIntervalSince(job.lastProgress) > 60 {
      // Take the job out first so the cancellation error is ignored, then retry
      // from the resume data instead of starting the file over.
      active[tid] = nil
      session.getAllTasks { tasks in
        guard let t = tasks.first(where: { $0.taskIdentifier == tid }) as? URLSessionDownloadTask
        else { return }
        t.cancel { data in
          DispatchQueue.main.async {
            MainActor.assumeIsolated {
              DownloadManager.shared.retry(job, resumeData: data, refreshToken: false)
            }
          }
        }
      }
    }
    if active.isEmpty && pending.isEmpty && startingCount == 0 {
      stallTimer?.invalidate()
      stallTimer = nil
    }
  }

  private func retry(_ job: Job, resumeData: Data?, refreshToken: Bool) {
    var j = job
    j.attempts += 1
    j.resumeData = resumeData
    j.bytesWritten = 0
    guard j.attempts <= 5 else {
      states[job.itemId] = .failed("Download failed")
      AppModel.shared.toast("Download failed: \(records[job.itemId]?.title ?? "")", .error)
      return
    }
    Task {
      if refreshToken { _ = try? await AppModel.shared.api.refreshAccessToken() }
      guard records[j.itemId] != nil else { return }
      pending.insert(j, at: 0)
      pump()
    }
  }

  private func fileFinished(_ job: Job) {
    bytesDone[job.itemId, default: 0] += job.file.size ?? job.bytesWritten
    checkCompleted(job.itemId)
  }

  private func checkCompleted(_ itemId: String) {
    guard var rec = records[itemId], !rec.completed else { return }
    let stillWorking =
      pending.contains { $0.itemId == itemId } || active.values.contains { $0.itemId == itemId }
      || (startingJobs[itemId] ?? 0) > 0
    if stillWorking {
      states[itemId] = .downloading(progress(itemId))
      return
    }
    let folder = URL(fileURLWithPath: rec.folder)
    guard
      rec.files.allSatisfy({
        FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.filename).path)
      })
    else {
      if case .failed = states[itemId] {} else { states[itemId] = .failed("Incomplete") }
      return
    }
    rec.completed = true
    rec.completedAt = Date()
    records[itemId] = rec
    states[itemId] = .done
    revision += 1
    saveIndex()
    if AppSettings.shared.notifyDownloads {
      Notifier.shared.post(title: "Download complete", body: rec.title)
    }
  }

  private func saveIndex() {
    if let d = try? JSONEncoder().encode(records) { try? d.write(to: indexURL, options: .atomic) }
  }

  static func clean(_ s: String) -> String {
    var out = s.replacingOccurrences(of: ":", with: " -").replacingOccurrences(of: "/", with: "_")
    out = out.filter { !"\\?%*|\"<>".contains($0) }
    out = out.trimmingCharacters(in: .whitespacesAndNewlines)
    if out.count > 150 { out = String(out.prefix(150)) }
    return out.isEmpty ? "Untitled" : out
  }
}

extension DownloadManager: URLSessionDownloadDelegate {
  nonisolated func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    let tid = downloadTask.taskIdentifier
    MainActor.assumeIsolated {
      guard var job = active[tid] else { return }
      job.bytesWritten = totalBytesWritten
      job.lastProgress = Date()
      active[tid] = job
      if job.file.size == nil, totalBytesExpectedToWrite > 0 {
        bytesTotal[job.itemId, default: 0] += totalBytesExpectedToWrite
        job.file.size = totalBytesExpectedToWrite
        active[tid] = job
      }
      states[job.itemId] = .downloading(progress(job.itemId))
    }
  }

  nonisolated func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    let tid = downloadTask.taskIdentifier
    let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
    // The temp file is deleted when this returns: move it synchronously.
    let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.moveItem(at: location, to: staged)
    MainActor.assumeIsolated {
      guard let job = active[tid] else {
        try? FileManager.default.removeItem(at: staged)
        return
      }
      active[tid] = nil
      if status == 200 || status == 206 {
        try? FileManager.default.removeItem(at: job.destination)
        try? FileManager.default.createDirectory(
          at: job.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: staged, to: job.destination)
        fileFinished(job)
      } else {
        try? FileManager.default.removeItem(at: staged)
        retry(job, resumeData: nil, refreshToken: status == 401)
      }
      pump()
    }
  }

  nonisolated func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
  ) {
    guard let error else { return }
    let tid = task.taskIdentifier
    let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    MainActor.assumeIsolated {
      guard let job = active[tid] else { return }
      active[tid] = nil
      retry(job, resumeData: resume, refreshToken: false)
      pump()
    }
  }
}
