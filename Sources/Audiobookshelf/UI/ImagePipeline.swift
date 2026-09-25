import AppKit
import ImageIO
import SwiftUI

/// Covers and author photos: URLCache on disk (the server sends max-age with
/// `ts`), decoded off the main thread at display size with ImageIO, kept in
/// memory by NSCache. Requests for the same URL share one download.
final class ImagePipeline: @unchecked Sendable {
  static let shared = ImagePipeline()

  private let memory = NSCache<NSString, NSImage>()
  private let session: URLSession
  private let lock = NSLock()
  private var inflight: [String: Task<NSImage?, Never>] = [:]

  private let diskCache: URLCache

  private init() {
    memory.countLimit = 800
    diskCache = URLCache(
      memoryCapacity: 32 << 20, diskCapacity: 1 << 30,
      directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.arturgrochau.audiobookshelf-mac/images"))
    let cfg = URLSessionConfiguration.default
    cfg.urlCache = nil
    cfg.httpMaximumConnectionsPerHost = 8
    cfg.httpShouldSetCookies = false
    session = URLSession(configuration: cfg)
  }

  /// Cache key without the host: the same cover over the LAN and through the
  /// public address is one entry, so a route switch never refetches covers.
  private static func key(_ url: URL, _ pixelWidth: Int) -> String {
    if url.isFileURL { return "\(url.path)#\(pixelWidth)" }
    let c = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let path = c?.path ?? url.path
    let query = c?.percentEncodedQuery.map { "?\($0)" } ?? ""
    return "\(path)\(query)#\(pixelWidth)"
  }

  private static func canonicalRequest(_ url: URL) -> URLRequest {
    var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    c.scheme = "https"
    c.host = "abs-cover.cache"
    c.port = nil
    return URLRequest(url: c.url!)
  }

  func cached(_ url: URL, pixelWidth: Int) -> NSImage? {
    memory.object(forKey: Self.key(url, pixelWidth) as NSString)
  }

  func image(_ url: URL, pixelWidth: Int) async -> NSImage? {
    let key = Self.key(url, pixelWidth)
    if let img = memory.object(forKey: key as NSString) { return img }
    let task: Task<NSImage?, Never> = lock.withLock {
      if let t = inflight[key] { return t }
      let t = Task.detached(priority: .userInitiated) { [session, diskCache, memory, weak self] () -> NSImage? in
        defer { self?.lock.withLock { self?.inflight[key] = nil } }
        let img: NSImage?
        if url.isFileURL {
          img = Self.decode(try? Data(contentsOf: url), pixelWidth: pixelWidth)
        } else {
          let canonical = Self.canonicalRequest(url)
          if let hit = diskCache.cachedResponse(for: canonical) {
            img = Self.decode(hit.data, pixelWidth: pixelWidth)
          } else if let (data, resp) = try? await session.data(from: url),
            let http = resp as? HTTPURLResponse, http.statusCode == 200
          {
            if let r = HTTPURLResponse(
              url: canonical.url!, statusCode: 200, httpVersion: "HTTP/1.1",
              headerFields: http.allHeaderFields as? [String: String])
            {
              diskCache.storeCachedResponse(CachedURLResponse(response: r, data: data), for: canonical)
            }
            img = Self.decode(data, pixelWidth: pixelWidth)
          } else {
            img = nil
          }
        }
        if let img { memory.setObject(img, forKey: key as NSString) }
        return img
      }
      inflight[key] = t
      return t
    }
    return await task.value
  }

  func prefetch(_ urls: [URL], pixelWidth: Int) {
    for u in urls where cached(u, pixelWidth: pixelWidth) == nil {
      Task.detached(priority: .utility) { _ = await self.image(u, pixelWidth: pixelWidth) }
    }
  }

  static func decode(_ data: Data?, pixelWidth: Int) -> NSImage? {
    guard let data, let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: max(64, pixelWidth),
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
      return nil
    }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
  }
}

/// Async image view backed by ImagePipeline. Shows the cached image in the
/// first frame when available, so scrolling back never flickers.
struct RemoteImage<Placeholder: View>: View {
  let url: URL?
  let pixelWidth: Int
  var contentMode: ContentMode = .fill
  @ViewBuilder var placeholder: () -> Placeholder
  @State private var image: NSImage?

  var body: some View {
    let initial = image ?? url.flatMap { ImagePipeline.shared.cached($0, pixelWidth: pixelWidth) }
    ZStack {
      if let initial {
        Image(nsImage: initial).resizable().aspectRatio(contentMode: contentMode)
      } else {
        placeholder()
      }
    }
    .task(id: url) {
      guard let url else {
        image = nil
        return
      }
      if let c = ImagePipeline.shared.cached(url, pixelWidth: pixelWidth) {
        image = c
        return
      }
      image = await ImagePipeline.shared.image(url, pixelWidth: pixelWidth)
    }
  }
}
