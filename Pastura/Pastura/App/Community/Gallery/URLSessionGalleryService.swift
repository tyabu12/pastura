import CryptoKit
import Foundation

/// URLSession-backed implementation of `GalleryService`.
///
/// Uses an ephemeral session configuration (no cookies, no credential
/// persistence, no URLCache) plus a per-request delegate that restricts
/// HTTP redirects to the same host. ETags are persisted alongside the
/// cached index as a `.etag` sidecar so If-None-Match conditional GETs
/// work across app launches.
public final class URLSessionGalleryService: NSObject, GalleryService, @unchecked Sendable {
  // @unchecked Sendable: stored state is immutable after init.

  // MARK: - Tunables

  /// Maximum accepted size of `gallery.json`, in bytes.
  public static let indexSizeLimit = 1_048_576  // 1 MiB

  /// Maximum accepted size of a single scenario YAML, in bytes.
  public static let yamlSizeLimit = 262_144  // 256 KiB

  /// Default remote URL for the gallery index.
  ///
  /// The literal is a compile-time constant; `preconditionFailure` signals
  /// an unreachable state, not a runtime error path.
  public static var defaultIndexURL: URL {
    guard
      let url = URL(
        string:
          "https://raw.githubusercontent.com/tyabu12/pastura/main/docs/gallery/gallery.json")
    else {
      preconditionFailure("Invalid gallery index URL literal")
    }
    return url
  }

  // MARK: - State

  private let indexURL: URL
  private let cacheDirectory: URL
  private let session: URLSession

  public init(
    indexURL: URL = URLSessionGalleryService.defaultIndexURL,
    cacheDirectory: URL = URLSessionGalleryService.defaultCacheDirectory(),
    sessionConfiguration: URLSessionConfiguration? = nil
  ) {
    self.indexURL = indexURL
    self.cacheDirectory = cacheDirectory
    self.session = URLSession(configuration: sessionConfiguration ?? Self.hardenedConfiguration())
    super.init()
  }

  // MARK: - Configuration helpers

  /// Default cache directory: `<Caches>/Pastura/Gallery/`.
  public static func defaultCacheDirectory() -> URL {
    let base =
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("Pastura/Gallery", isDirectory: true)
  }

  /// Ephemeral configuration with tight timeouts, no cookies, no auth headers.
  public static func hardenedConfiguration() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 20
    config.httpShouldSetCookies = false
    config.httpCookieAcceptPolicy = .never
    config.httpShouldUsePipelining = false
    config.httpAdditionalHeaders = [:]
    config.urlCache = nil
    return config
  }

  // MARK: - GalleryService

  public func loadCachedIndex() throws -> GalleryIndex? {
    let path = cacheIndexURL
    guard FileManager.default.fileExists(atPath: path.path) else { return nil }
    let data = try Data(contentsOf: path)
    do {
      return try JSONDecoder().decode(GalleryIndex.self, from: data)
    } catch {
      throw GalleryServiceError.corruptedCache
    }
  }

  public func refreshIndex() async throws -> GalleryIndex? {
    var request = URLRequest(url: indexURL)
    request.httpMethod = "GET"
    if let etag = try? loadCachedETag() {
      request.setValue(etag, forHTTPHeaderField: "If-None-Match")
    }
    let (data, response) = try await performDataRequest(
      request, limit: Self.indexSizeLimit)
    guard let http = response as? HTTPURLResponse else {
      throw GalleryServiceError.invalidResponse
    }
    switch http.statusCode {
    case 304:
      return nil
    case 200:
      let index: GalleryIndex
      do {
        index = try JSONDecoder().decode(GalleryIndex.self, from: data)
      } catch {
        // Network succeeded but the body is unparseable — treat as corrupt.
        throw GalleryServiceError.corruptedCache
      }
      try persistCache(data: data, etag: http.value(forHTTPHeaderField: "ETag"))
      return index
    default:
      throw GalleryServiceError.unexpectedStatus(http.statusCode)
    }
  }

  public func fetchScenarioYAML(from url: URL, expectedSHA256: String) async throws -> String {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    let (data, response) = try await performDataRequest(request, limit: Self.yamlSizeLimit)
    guard let http = response as? HTTPURLResponse else {
      throw GalleryServiceError.invalidResponse
    }
    guard http.statusCode == 200 else {
      throw GalleryServiceError.unexpectedStatus(http.statusCode)
    }
    let actual = Self.sha256Hex(data)
    let expected = expectedSHA256.lowercased()
    guard actual == expected else {
      throw GalleryServiceError.hashMismatch(expected: expected, actual: actual)
    }
    guard let yaml = String(data: data, encoding: .utf8) else {
      throw GalleryServiceError.invalidResponse
    }
    return yaml
  }

  // MARK: - Private

  private var cacheIndexURL: URL {
    cacheDirectory.appendingPathComponent("gallery.json")
  }
  private var cacheETagURL: URL {
    cacheDirectory.appendingPathComponent("gallery.json.etag")
  }

  private func loadCachedETag() throws -> String? {
    let url = cacheETagURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    return String(data: data, encoding: .utf8)
  }

  private func persistCache(data: Data, etag: String?) throws {
    try FileManager.default.createDirectory(
      at: cacheDirectory, withIntermediateDirectories: true)
    try data.write(to: cacheIndexURL, options: .atomic)
    if let etag, let etagData = etag.data(using: .utf8) {
      try etagData.write(to: cacheETagURL, options: .atomic)
    } else {
      // No ETag — clear any stale sidecar so we don't send it next time.
      try? FileManager.default.removeItem(at: cacheETagURL)
    }
  }

  private func performDataRequest(
    _ request: URLRequest, limit: Int
  ) async throws -> (Data, URLResponse) {
    let delegate = RedirectPolicyDelegate(sameHost: request.url?.host)
    let (data, response) = try await session.data(for: request, delegate: delegate)

    // Authoritative size check after download. Pre-flight header check
    // below rejects large responses earlier when the server advertises
    // Content-Length truthfully, but the post-download check is what
    // actually bounds memory in the general case.
    if let http = response as? HTTPURLResponse {
      let declared = http.expectedContentLength
      if declared > 0, declared > Int64(limit) {
        throw GalleryServiceError.responseTooLarge(limit: limit)
      }
    }
    if data.count > limit {
      throw GalleryServiceError.responseTooLarge(limit: limit)
    }
    return (data, response)
  }

  static func sha256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}

/// Per-request delegate that cancels cross-host HTTP redirects.
///
/// Allowing redirects to arbitrary hosts would let a compromised server
/// steer the client to an attacker-controlled origin; we prefer failing
/// the fetch to silently following.
private final class RedirectPolicyDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let sameHost: String?

  init(sameHost: String?) {
    self.sameHost = sameHost
    super.init()
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    if let newHost = request.url?.host, newHost == sameHost {
      completionHandler(request)
    } else {
      completionHandler(nil)
    }
  }
}
