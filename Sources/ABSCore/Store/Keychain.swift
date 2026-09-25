import Foundation
import Security

/// Generic-password Keychain storage. Holds only the saved password: with a
/// self-signed identity, reading an item written by another build prompts.
public enum Keychain {
  public static let service = "com.arturgrochau.audiobookshelf-mac"

  /// Delete then add: updating an item written by an earlier build would
  /// prompt (access follows the binary's cdhash), deleting does not.
  public static func set(_ data: Data, account: String) {
    delete(account: account)
    let add: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    SecItemAdd(add as CFDictionary, nil)
  }

  public static func get(account: String) -> Data? { read(account: account).data }

  /// The data and the raw status, so callers can tell "no item" from "locked" or "denied".
  public static func read(account: String) -> (data: Data?, status: OSStatus) {
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var out: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &out)
    return (status == errSecSuccess ? out as? Data : nil, status)
  }

  public static func delete(account: String) {
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(q as CFDictionary)
  }

  public static func setCodable<T: Encodable>(_ v: T, account: String) {
    if let d = try? JSONEncoder().encode(v) { set(d, account: account) }
  }

  public static func getCodable<T: Decodable>(_ t: T.Type, account: String) -> T? {
    get(account: account).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
  }
}

/// The signed-in account: where the server is and the current token pair.
public struct Account: Codable, Sendable, Hashable {
  public var serverURL: URL
  /// Optional LAN address of the same server (e.g. http://abs.local:13378).
  public var localURL: URL?
  public var username: String
  public var userId: String
  public var accessToken: String?
  public var refreshToken: String?
  /// Stable per server+user, so the server closes only our own old sessions.
  public var deviceId: String

  public init(
    serverURL: URL, localURL: URL?, username: String, userId: String, accessToken: String?,
    refreshToken: String?, deviceId: String
  ) {
    self.serverURL = serverURL
    self.localURL = localURL
    self.username = username
    self.userId = userId
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.deviceId = deviceId
  }

  /// Stored as a 0600 file, not in the Keychain: with a self-signed identity
  /// the Keychain ties access to the binary's cdhash, so every rebuild would
  /// prompt before the app could even start. The password (the fallback) is
  /// the only secret kept in the Keychain, and it is read only when the
  /// server rejects the refresh token.
  public static var fileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Audiobookshelf", isDirectory: true)
      .appendingPathComponent("account.json")
  }

  public static func load() -> Account? {
    guard let d = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder().decode(Account.self, from: d)
  }

  public func save() {
    guard let d = try? JSONEncoder().encode(self) else { return }
    let url = Self.fileURL
    let fm = FileManager.default
    try? fm.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let tmp = url.appendingPathExtension("tmp")
    guard fm.createFile(atPath: tmp.path, contents: d, attributes: [.posixPermissions: 0o600])
    else { return }
    _ = try? fm.replaceItemAt(url, withItemAt: tmp, options: .usingNewMetadataOnly)
    if !fm.fileExists(atPath: url.path) { try? fm.moveItem(at: tmp, to: url) }
    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  public static func clear() { try? FileManager.default.removeItem(at: fileURL) }
}

/// Saved login so an expired or revoked refresh token never forces a manual login.
public struct Credentials: Codable, Sendable, Hashable {
  public var username: String
  public var password: String

  public init(username: String, password: String) {
    self.username = username
    self.password = password
  }

  public static let keychainAccount = "credentials"
  public static func load() -> Credentials? {
    Keychain.getCodable(Credentials.self, account: keychainAccount)
  }

  public enum Lookup: Sendable {
    case found(Credentials)
    /// Nothing saved: re-login is impossible.
    case missing
    /// Locked keychain or a denied access prompt: try again later, never log out for it.
    case unavailable(OSStatus)
  }

  public static func lookup() -> Lookup {
    let r = Keychain.read(account: keychainAccount)
    if r.status == errSecItemNotFound { return .missing }
    guard let d = r.data, let c = try? JSONDecoder().decode(Credentials.self, from: d) else {
      return r.status == errSecSuccess ? .missing : .unavailable(r.status)
    }
    return .found(c)
  }
  public func save() { Keychain.setCodable(self, account: Self.keychainAccount) }
  public static func clear() { Keychain.delete(account: keychainAccount) }
}
