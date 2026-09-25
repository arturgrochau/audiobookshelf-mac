import Foundation
import Network

/// Picks which address of the same server to talk to. The LAN address and
/// the public one are raced with /ping at launch and whenever the network
/// path changes; streaming and downloads prefer the LAN when it answered, the
/// API uses whichever answered first. One token set is valid on both.
public final class ServerRouter: @unchecked Sendable {
  public struct Choice: Sendable, Equatable {
    public var api: URL
    public var stream: URL
    public var onLAN: Bool
  }

  public let publicURL: URL
  public let localURL: URL?
  private let lock = NSLock()
  private var _choice: Choice
  private let monitor = NWPathMonitor()
  private var lastPathKey = ""
  private var probeGeneration = 0
  public var onChange: (@Sendable (Choice) -> Void)?
  public private(set) var localNetworkDenied = false

  public init(publicURL: URL, localURL: URL?) {
    self.publicURL = publicURL
    self.localURL = localURL
    _choice = Choice(api: publicURL, stream: publicURL, onLAN: false)
  }

  public var choice: Choice {
    lock.lock()
    defer { lock.unlock() }
    return _choice
  }

  public func stop() {
    monitor.pathUpdateHandler = nil
    monitor.cancel()
  }

  public func start() {
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      let key = "\(path.status)-\(path.availableInterfaces.map(\.name).joined(separator: ","))"
      guard key != self.lastPathKey else { return }
      self.lastPathKey = key
      Task { await self.probe() }
    }
    monitor.start(queue: DispatchQueue(label: "abs.router.path"))
  }

  /// Races both origins. Returns the new choice.
  @discardableResult
  public func probe() async -> Choice {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.timeoutIntervalForRequest = 2.5
    cfg.waitsForConnectivity = false
    let session = URLSession(configuration: cfg)
    defer { session.finishTasksAndInvalidate() }

    let local = localURL
    async let lan: TimeInterval? = Self.pingOptional(local, session: session, timeout: 1.2)
    async let pub: TimeInterval? = Self.ping(publicURL, session: session, timeout: 4)
    let gen = lock.withLock {
      probeGeneration += 1
      return probeGeneration
    }
    let (l, p) = await (lan, pub)

    var next = Choice(api: publicURL, stream: publicURL, onLAN: false)
    if let l, let local = localURL {
      next.stream = local
      next.onLAN = true
      next.api = (p == nil || l <= (p ?? .infinity)) ? local : publicURL
    }
    let (changed, current) = lock.withLock { () -> (Bool, Choice) in
      // A slower, older probe must not overwrite a newer result.
      guard gen == probeGeneration else { return (false, _choice) }
      let c = next != _choice
      _choice = next
      return (c, next)
    }
    if changed { onChange?(next) }
    return current
  }

  static func pingOptional(_ base: URL?, session: URLSession, timeout: TimeInterval) async -> TimeInterval? {
    guard let base else { return nil }
    return await ping(base, session: session, timeout: timeout)
  }

  static func ping(_ base: URL, session: URLSession, timeout: TimeInterval) async -> TimeInterval? {
    var req = URLRequest(url: base.appendingPathComponent("ping"))
    req.timeoutInterval = timeout
    let t0 = Date()
    guard let (_, resp) = try? await session.data(for: req),
      (resp as? HTTPURLResponse)?.statusCode == 200
    else {
      return nil
    }
    return Date().timeIntervalSince(t0)
  }
}
