import Foundation

/// Engine.IO v4 / Socket.IO v4 packets, just what ABS uses (default namespace,
/// events as JSON arrays). Kept separate from the transport so it is testable.
public enum SocketPacket: Equatable, Sendable {
  case open(sid: String, pingInterval: Double, pingTimeout: Double)
  case ping
  case pong
  case connect
  case connectError(String)
  case event(name: String, payload: Data?)
  case close
  case other(String)

  public static func parse(_ text: String) -> SocketPacket {
    guard let first = text.first else { return .other(text) }
    let rest = String(text.dropFirst())
    switch first {
    case "0":
      let obj = (try? JSONSerialization.jsonObject(with: Data(rest.utf8))) as? [String: Any]
      return .open(
        sid: obj?["sid"] as? String ?? "",
        pingInterval: (obj?["pingInterval"] as? Double) ?? 25000,
        pingTimeout: (obj?["pingTimeout"] as? Double) ?? 20000)
    case "1": return .close
    case "2": return .ping
    case "3": return .pong
    case "4":
      guard let kind = rest.first else { return .other(text) }
      let body = String(rest.dropFirst())
      switch kind {
      case "0": return .connect
      case "4": return .connectError(body)
      case "2":
        // Optional namespace ("/ns,") and ack id digits precede the JSON array.
        var json = Substring(body)
        if json.hasPrefix("/"), let comma = json.firstIndex(of: ",") {
          json = json[json.index(after: comma)...]
        }
        while let c = json.first, c.isNumber { json = json.dropFirst() }
        guard
          let arr =
            (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]))
            as? [Any],
          let name = arr.first as? String
        else { return .other(text) }
        var payload: Data?
        if arr.count > 1 {
          payload = try? JSONSerialization.data(
            withJSONObject: arr[1], options: [.fragmentsAllowed])
        }
        return .event(name: name, payload: payload)
      default: return .other(text)
      }
    default: return .other(text)
    }
  }

  public static func emit(_ name: String, _ arg: Any?) -> String {
    var arr: [Any] = [name]
    if let arg { arr.append(arg) }
    let d =
      (try? JSONSerialization.data(withJSONObject: arr, options: [.fragmentsAllowed]))
      ?? Data("[]".utf8)
    return "42" + (String(data: d, encoding: .utf8) ?? "[]")
  }
}

/// WebSocket-only Socket.IO client (the web client also skips polling).
/// Authenticates with `auth` after connecting; reconnects with backoff and
/// after 45 s of silence.
public final class SocketClient: NSObject, @unchecked Sendable {
  public typealias Handler = @Sendable (_ event: String, _ payload: Data?) -> Void

  private let lock = NSLock()
  private var task: URLSessionWebSocketTask?
  private var session: URLSession?
  private var baseURL: URL?
  private var tokenProvider: (@Sendable () async -> String?)?
  private var handler: Handler?
  private var generation = 0
  private var lastMessage = Date()
  private var backoff: Double = 1
  private var watchdog: Timer?
  public private(set) var isAuthenticated = false
  /// connect() was called and disconnect() was not.
  public var isStarted: Bool { lock.withLock { !stopped } }
  public var onStateChange: (@Sendable (_ connected: Bool, _ reconnected: Bool) -> Void)?
  private var everConnected = false
  /// True until connect(): a route switch before login must not open a socket.
  private var stopped = true
  private var reconnectPending = false
  /// One re-auth with a refreshed token per connection after `auth_failed`.
  private var reauthTried = false
  /// Returns a freshly refreshed access token (the stored one may have expired).
  public var freshToken: (@Sendable () async -> String?)?

  public override init() { super.init() }

  public func connect(
    baseURL: URL, token: @escaping @Sendable () async -> String?, handler: @escaping Handler
  ) {
    lock.lock()
    self.baseURL = baseURL
    self.tokenProvider = token
    self.handler = handler
    stopped = false
    lock.unlock()
    open()
  }

  public func disconnect() {
    lock.lock()
    stopped = true
    generation += 1
    task?.cancel(with: .goingAway, reason: nil)
    task = nil
    session?.invalidateAndCancel()
    session = nil
    isAuthenticated = false
    everConnected = false
    lock.unlock()
    DispatchQueue.main.async {
      self.watchdog?.invalidate()
      self.watchdog = nil
    }
  }

  /// Point at a different origin (LAN ↔ public) and reconnect.
  public func switchBase(_ url: URL) {
    lock.lock()
    let same = url == baseURL
    baseURL = url
    lock.unlock()
    if !same { open() }
  }

  private func open() {
    lock.lock()
    if stopped {
      lock.unlock()
      return
    }
    generation += 1
    let gen = generation
    task?.cancel(with: .goingAway, reason: nil)
    guard let base = baseURL, var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
    else {
      lock.unlock()
      return
    }
    comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
    comps.path =
      (comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path) + "/socket.io/"
    comps.queryItems = [
      URLQueryItem(name: "EIO", value: "4"), URLQueryItem(name: "transport", value: "websocket"),
    ]
    let cfg = URLSessionConfiguration.default
    cfg.httpShouldSetCookies = false
    let s = URLSession(configuration: cfg)
    let t = s.webSocketTask(with: comps.url!)
    t.maximumMessageSize = 32 * 1024 * 1024
    session?.invalidateAndCancel()
    session = s
    reauthTried = false
    task = t
    isAuthenticated = false
    lastMessage = Date()
    lock.unlock()
    t.resume()
    receive(t, gen: gen)
    DispatchQueue.main.async { self.startWatchdog() }
  }

  private func startWatchdog() {
    watchdog?.invalidate()
    watchdog = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.lock.lock()
      let silent = Date().timeIntervalSince(self.lastMessage)
      self.lock.unlock()
      if silent > 45 { self.scheduleReconnect() }
    }
  }

  private func receive(_ t: URLSessionWebSocketTask, gen: Int) {
    t.receive { [weak self] result in
      guard let self else { return }
      self.lock.lock()
      let current = gen == self.generation
      if current { self.lastMessage = Date() }
      self.lock.unlock()
      guard current else { return }
      switch result {
      case .failure:
        self.scheduleReconnect()
      case .success(let msg):
        if case .string(let text) = msg { self.handle(text, task: t) }
        self.receive(t, gen: gen)
      }
    }
  }

  private func send(_ text: String, on t: URLSessionWebSocketTask) {
    t.send(.string(text)) { _ in }
  }

  private func handle(_ text: String, task t: URLSessionWebSocketTask) {
    switch SocketPacket.parse(text) {
    case .open:
      send("40", on: t)
    case .ping:
      send("3", on: t)
    case .connect:
      Task {
        let token = await self.tokenProvider?() ?? nil
        guard let token else { return }
        self.send(SocketPacket.emit("auth", token), on: t)
      }
    case .event(let name, let payload):
      if name == "auth_failed" {
        // Usually an access token that expired while the Mac slept: refresh
        // once and authenticate again on the same socket.
        lock.lock()
        let tried = reauthTried
        reauthTried = true
        lock.unlock()
        Task {
          if !tried, let tok = await self.freshToken?() {
            self.send(SocketPacket.emit("auth", tok), on: t)
          } else {
            self.scheduleReconnect()
          }
        }
        return
      }
      if name == "init" {
        lock.lock()
        isAuthenticated = true
        backoff = 1
        let reconnected = everConnected
        everConnected = true
        lock.unlock()
        onStateChange?(true, reconnected)
      }
      handler?(name, payload)
    case .close, .connectError:
      scheduleReconnect()
    default:
      break
    }
  }

  private func scheduleReconnect() {
    lock.lock()
    if stopped || reconnectPending { lock.unlock(); return }
    reconnectPending = true
    generation += 1
    task?.cancel(with: .goingAway, reason: nil)
    task = nil
    let wasAuth = isAuthenticated
    isAuthenticated = false
    let delay = backoff
    backoff = min(backoff * 2, 30)
    lock.unlock()
    if wasAuth { onStateChange?(false, false) }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self else { return }
      self.lock.lock()
      self.reconnectPending = false
      let stop = self.stopped
      self.lock.unlock()
      if !stop { self.open() }
    }
  }
}
