import Foundation

public enum APIError: Error, Sendable, CustomStringConvertible {
  case http(Int, String)
  case unauthorized
  case rateLimited
  case notFound
  case network(String)
  case decoding(String)
  case noServer

  public var description: String {
    switch self {
    case .http(let c, let b): return "HTTP \(c): \(b.prefix(200))"
    case .unauthorized: return "Unauthorized"
    case .rateLimited: return "Too many requests"
    case .notFound: return "Not found"
    case .network(let m): return m
    case .decoding(let m): return "Decoding failed: \(m)"
    case .noServer: return "Server could not be reached"
    }
  }
}

/// Access + refresh token pair with single-flight refresh. The server rotates
/// the refresh token on every refresh, so the new pair is persisted before the
/// new access token is handed out.
public actor TokenStore {
  public private(set) var access: String?
  public private(set) var refresh: String?
  private var refreshing: Task<String, Error>?
  private let persist: @Sendable (String?, String?) -> Void

  public init(
    access: String?, refresh: String?, persist: @escaping @Sendable (String?, String?) -> Void
  ) {
    self.access = access
    self.refresh = refresh
    self.persist = persist
  }

  public func set(access: String?, refresh: String?) {
    self.access = access
    self.refresh = refresh
    persist(access, refresh)
  }

  /// Runs `perform` at most once concurrently; waiters share the result.
  public func refreshAccess(_ perform: @escaping @Sendable (String) async throws -> TokenPair) async throws -> String {
    if let refreshing { return try await refreshing.value }
    // No refresh token at all still goes through `perform`, so the saved-password
    // re-login gets its chance (the server rejects the empty token with 401).
    let token = refresh ?? ""
    let task = Task<String, Error> {
      let pair = try await perform(token)
      self.set(access: pair.access, refresh: pair.refresh)
      return pair.access
    }
    refreshing = task
    defer { refreshing = nil }
    return try await task.value
  }
}

public struct TokenPair: Sendable {
  public var access: String
  public var refresh: String
  public init(access: String, refresh: String) { self.access = access; self.refresh = refresh }
}

/// Thin URLSession wrapper for the ABS REST API.
public final class APIClient: @unchecked Sendable {
  public let tokens: TokenStore
  public let session: URLSession
  private let lock = NSLock()
  private var _baseURL: URL?
  public var onUnauthorized: (@Sendable () -> Void)?
  /// Logs in again with saved credentials when the refresh token is dead.
  public var relogin: (@Sendable () async throws -> TokenPair)?
  /// Called after every successful refresh (the socket re-auths on reconnect only).
  public var onTokensRefreshed: (@Sendable (String) -> Void)?

  public var baseURL: URL? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _baseURL
    }
    set {
      lock.lock()
      _baseURL = newValue
      lock.unlock()
    }
  }

  public init(baseURL: URL?, tokens: TokenStore, session: URLSession? = nil) {
    self._baseURL = baseURL
    self.tokens = tokens
    if let session {
      self.session = session
    } else {
      let cfg = URLSessionConfiguration.default
      cfg.httpShouldSetCookies = false
      cfg.httpCookieAcceptPolicy = .never
      cfg.httpMaximumConnectionsPerHost = 8
      cfg.timeoutIntervalForRequest = 20
      cfg.waitsForConnectivity = false
      self.session = URLSession(configuration: cfg)
    }
  }

  public static let decoder: JSONDecoder = JSONDecoder()

  public func url(_ path: String, query: [String: String] = [:], rawQuery: String? = nil) throws
    -> URL
  {
    guard let base = baseURL else { throw APIError.noServer }
    var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
    let basePath = comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path
    comps.path = basePath + path
    var parts: [String] = []
    for (k, v) in query.sorted(by: { $0.key < $1.key }) {
      parts.append("\(Self.escape(k))=\(Self.escape(v))")
    }
    if let rawQuery, !rawQuery.isEmpty { parts.append(rawQuery) }
    comps.percentEncodedQuery = parts.isEmpty ? nil : parts.joined(separator: "&")
    return comps.url!
  }

  static func escape(_ s: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~,")
    return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
  }

  @discardableResult
  public func data(
    _ method: String, _ path: String, query: [String: String] = [:], rawQuery: String? = nil,
    body: Data? = nil, headers: [String: String] = [:], authorized: Bool = true,
    timeout: TimeInterval? = nil, retryOn401: Bool = true
  ) async throws -> (Data, HTTPURLResponse) {
    var req = URLRequest(url: try url(path, query: query, rawQuery: rawQuery))
    req.httpMethod = method
    if let timeout { req.timeoutInterval = timeout }
    if let body {
      req.httpBody = body
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    let sentToken = authorized ? await tokens.access : nil
    if let sentToken {
      req.setValue("Bearer \(sentToken)", forHTTPHeaderField: "Authorization")
    }
    let (data, resp): (Data, URLResponse)
    do {
      (data, resp) = try await session.data(for: req)
    } catch {
      throw APIError.network(error.localizedDescription)
    }
    guard let http = resp as? HTTPURLResponse else { throw APIError.network("No HTTP response") }
    switch http.statusCode {
    case 200..<300:
      return (data, http)
    case 401 where authorized && retryOn401:
      // Another request may already have refreshed while this one was in flight.
      if await tokens.access == sentToken { _ = try await refreshAccessToken() }
      return try await self.data(
        method, path, query: query, rawQuery: rawQuery, body: body, headers: headers,
        authorized: authorized, timeout: timeout, retryOn401: false)
    case 401:
      throw APIError.unauthorized
    case 404:
      throw APIError.notFound
    case 429:
      throw APIError.rateLimited
    default:
      throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }
  }

  public func get<T: Decodable>(
    _ type: T.Type = T.self, _ path: String, query: [String: String] = [:],
    rawQuery: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> T {
    let (d, _) = try await data("GET", path, query: query, rawQuery: rawQuery, timeout: timeout)
    return try decode(T.self, d)
  }

  public func send<T: Decodable>(
    _ type: T.Type = T.self, _ method: String, _ path: String, json: Encodable? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> T {
    let body = try json.map { try JSONEncoder().encode(AnyEncodable($0)) }
    let (d, _) = try await data(method, path, body: body, timeout: timeout)
    return try decode(T.self, d)
  }

  public func sendVoid(
    _ method: String, _ path: String, json: Encodable? = nil, timeout: TimeInterval? = nil
  ) async throws {
    let body = try json.map { try JSONEncoder().encode(AnyEncodable($0)) }
    _ = try await data(
      method, path, body: body ?? (method == "GET" || method == "DELETE" ? nil : Data("{}".utf8)),
      timeout: timeout)
  }

  public func decode<T: Decodable>(_ type: T.Type, _ d: Data) throws -> T {
    do { return try Self.decoder.decode(T.self, from: d) } catch {
      throw APIError.decoding(String(describing: error).prefix(400).description)
    }
  }

  /// POST /auth/refresh with x-refresh-token; single-flight through TokenStore.
  /// When the refresh token itself is rejected (expired after 30 idle days,
  /// revoked, or rotated past the grace window) and `relogin` is set, logs in
  /// again with the saved credentials inside the same single flight. Only a
  /// rejected login counts as unauthorized; 5xx and network errors never do.
  @discardableResult
  public func refreshAccessToken() async throws -> String {
    let access = try await tokens.refreshAccess { [weak self] refresh in
      guard let self else { throw APIError.unauthorized }
      do {
        return try await self.performRefresh(refresh)
      } catch APIError.unauthorized {
        if let relogin = self.relogin {
          do {
            return try await relogin()
          } catch APIError.unauthorized {
            self.onUnauthorized?()
            throw APIError.unauthorized
          }
        }
        self.onUnauthorized?()
        throw APIError.unauthorized
      }
    }
    onTokensRefreshed?(access)
    return access
  }

  private func performRefresh(_ refresh: String) async throws -> TokenPair {
    var req = URLRequest(url: try url("/auth/refresh"))
    req.httpMethod = "POST"
    req.timeoutInterval = 15
    req.setValue(refresh, forHTTPHeaderField: "x-refresh-token")
    req.setValue("true", forHTTPHeaderField: "x-return-tokens")
    let (d, resp): (Data, URLResponse)
    do {
      (d, resp) = try await session.data(for: req)
    } catch {
      throw APIError.network(error.localizedDescription)
    }
    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
    switch code {
    case 200: break
    case 401, 403: throw APIError.unauthorized
    case 429: throw APIError.rateLimited
    default: throw APIError.http(code, String(data: d, encoding: .utf8) ?? "")
    }
    let login = try decode(LoginResponse.self, d)
    guard let a = login.user.accessToken else { throw APIError.unauthorized }
    return TokenPair(access: a, refresh: login.user.refreshToken ?? refresh)
  }
}

struct AnyEncodable: Encodable {
  let value: Encodable
  init(_ v: Encodable) { value = v }
  func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

/// Web `$encode`: encodeURIComponent(base64(utf8)). Used in `filter=group.<value>`.
public enum FilterEncoding {
  public static func encode(_ value: String) -> String {
    let b64 = Data(value.utf8).base64EncodedString()
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-_.!~*'()")
    return b64.addingPercentEncoding(withAllowedCharacters: allowed) ?? b64
  }

  public static func decode(_ value: String) -> String? {
    guard let raw = value.removingPercentEncoding, let d = Data(base64Encoded: raw) else {
      return nil
    }
    return String(data: d, encoding: .utf8)
  }

  /// `group.<encoded>` or a bare keyword such as `issues`.
  public static func filter(_ group: String, _ value: String?) -> String {
    guard let value else { return group }
    return "\(group).\(encode(value))"
  }
}
