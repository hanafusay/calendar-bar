import AppKit
import CalendarCore
import CryptoKit
import Network
import Security

struct CredentialStore {
  private static let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "io.github.calendar-bar.credentials",
    kSecAttrAccount as String: "google",
  ]
  static func load() throws -> GoogleCredentials? {
    var referenceQuery = Self.query
    referenceQuery[kSecReturnRef as String] = true
    var reference: CFTypeRef?
    let referenceStatus = SecItemCopyMatching(referenceQuery as CFDictionary, &reference)
    if referenceStatus == errSecItemNotFound { return nil }
    guard referenceStatus == errSecSuccess, let reference else {
      throw GoogleError.invalidCredentials
    }
    _ = try KeychainAccess.migrate(reference as! SecKeychainItem)
    var query = Self.query
    query[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw GoogleError.invalidCredentials
    }
    return try JSONDecoder().decode(GoogleCredentials.self, from: data)
  }
  static func save(_ credentials: GoogleCredentials) throws {
    let data = try JSONEncoder().encode(credentials)
    let updates = [kSecValueData as String: data]
    var status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
    if status == errSecItemNotFound {
      var add = query
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      if KeychainAccess.isOfficialRelease() {
        add[kSecAttrAccess as String] = try KeychainAccess.restrictedToCurrentApp()
      }
      status = SecItemAdd(add as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw GoogleError.invalidCredentials }
  }
  static func delete() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw GoogleError.invalidCredentials
    }
  }
}

@MainActor
final class GoogleLogin {
  private var listener: NWListener?
  private var continuation: CheckedContinuation<GoogleCredentials, Error>?
  private var timeout: Task<Void, Never>?
  private var exchange: Task<Void, Never>?
  private var connections: [NWConnection] = []

  func connect(_ credentials: GoogleCredentials) async throws -> GoogleCredentials {
    let state = UUID().uuidString
    let verifier = UUID().uuidString + UUID().uuidString
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let listener = try NWListener(using: parameters)
    self.listener = listener
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      listener.stateUpdateHandler = { [weak self] status in
        Task { @MainActor in
          guard let self, self.continuation != nil else { return }
          switch status {
          case .ready:
            guard let port = listener.port else {
              self.finish(.failure(GoogleError.requestFailed))
              return
            }
            let redirect = "http://127.0.0.1:\(port.rawValue)/oauth/callback"
            var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            url.queryItems = [
              "client_id": credentials.clientID, "redirect_uri": redirect, "response_type": "code",
              "scope": "https://www.googleapis.com/auth/calendar.events.readonly",
              "access_type": "offline", "prompt": "consent", "state": state,
              "code_challenge": challenge, "code_challenge_method": "S256",
            ].map { URLQueryItem(name: $0.key, value: $0.value) }
            if !NSWorkspace.shared.open(url.url!) {
              self.finish(.failure(GoogleError.requestFailed))
            }
          case .failed: self.finish(.failure(GoogleError.requestFailed))
          default: break
          }
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        Task { @MainActor in
          guard let self, self.continuation != nil else {
            connection.cancel()
            return
          }
          self.connections.append(connection)
          connection.start(queue: .main)
          self.receive(
            connection, buffer: Data(), state: state, verifier: verifier, credentials: credentials)
        }
      }
      listener.start(queue: .main)
      timeout = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 180_000_000_000)
        guard !Task.isCancelled else { return }
        self?.finish(.failure(GoogleError.timedOut))
      }
    }
  }
  private func receive(
    _ connection: NWConnection, buffer: Data, state: String, verifier: String,
    credentials: GoogleCredentials
  ) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
      [weak self] data, _, complete, error in
      Task { @MainActor in
        guard let self, self.continuation != nil else {
          connection.cancel()
          return
        }
        var buffer = buffer
        if let data { buffer.append(data) }
        guard buffer.count <= 16384, error == nil else {
          connection.cancel()
          return
        }
        guard let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") else {
          if complete {
            connection.cancel()
          } else {
            self.receive(
              connection, buffer: buffer, state: state, verifier: verifier, credentials: credentials
            )
          }
          return
        }
        let fields = text.components(separatedBy: "\r\n")[0].split(separator: " ")
        guard fields.count == 3, fields[0] == "GET", let port = self.listener?.port else {
          connection.cancel()
          return
        }
        let headers = text.components(separatedBy: "\r\n").dropFirst().filter {
          $0.lowercased().hasPrefix("host:")
        }
        guard headers.count == 1,
          headers[0].dropFirst(5).trimmingCharacters(in: .whitespaces)
            == "127.0.0.1:\(port.rawValue)"
        else {
          connection.cancel()
          return
        }
        let code: String
        do {
          code = try OAuthCallback.code(requestTarget: String(fields[1]), expectedState: state)
        } catch {
          connection.send(
            content: Data(
              "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
            completion: .contentProcessed { _ in connection.cancel() })
          if case GoogleError.cancelled = error { self.finish(.failure(error)) }
          return
        }
        guard self.exchange == nil else {
          connection.cancel()
          return
        }
        connection.send(
          content: Data(
            "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 35\r\nConnection: close\r\n\r\nReturn to the Calendar Bar app now.\n"
              .utf8), completion: .contentProcessed { _ in connection.cancel() })
        self.exchange = Task {
          do {
            var values = [
              "client_id": credentials.clientID, "code": code, "code_verifier": verifier,
              "redirect_uri": "http://127.0.0.1:\(port.rawValue)/oauth/callback",
              "grant_type": "authorization_code",
            ]
            if let secret = credentials.clientSecret { values["client_secret"] = secret }
            let tokens = try await GoogleCalendarAPI().token(values: values)
            guard !Task.isCancelled else { return }
            guard let refresh = tokens.refresh else { throw GoogleError.unauthorized }
            var result = credentials
            result.refreshToken = refresh
            self.finish(.success(result))
          } catch { if !Task.isCancelled { self.finish(.failure(GoogleError.requestFailed)) } }
        }
      }
    }
  }
  func cancel() { finish(.failure(GoogleError.cancelled)) }
  private func finish(_ result: Result<GoogleCredentials, Error>) {
    guard let continuation else { return }
    self.continuation = nil
    timeout?.cancel()
    exchange?.cancel()
    listener?.cancel()
    connections.forEach { $0.cancel() }
    connections.removeAll()
    self.listener = nil
    continuation.resume(with: result)
  }
}
