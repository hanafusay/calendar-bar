import Foundation

public struct GoogleCredentials: Codable, Sendable {
  public var clientID: String
  public var clientSecret: String?
  public var refreshToken: String?
  public init(clientID: String, clientSecret: String? = nil, refreshToken: String? = nil) {
    self.clientID = clientID
    self.clientSecret = clientSecret
    self.refreshToken = refreshToken
  }
  public static func importing(_ data: Data) throws -> GoogleCredentials {
    struct Client: Decodable {
      let client_id: String
      let client_secret: String?
      let refresh_token: String?
    }
    struct File: Decodable {
      let installed: Client?
      let client_id: String?
      let client_secret: String?
      let refresh_token: String?
      let type: String?
    }
    let file = try JSONDecoder().decode(File.self, from: data)
    if let client = file.installed, client.client_id.hasSuffix(".apps.googleusercontent.com") {
      return GoogleCredentials(clientID: client.client_id, clientSecret: client.client_secret)
    }
    if file.type == "authorized_user", let id = file.client_id,
      id.hasSuffix(".apps.googleusercontent.com"), let token = file.refresh_token, !token.isEmpty
    {
      return GoogleCredentials(clientID: id, clientSecret: file.client_secret, refreshToken: token)
    }
    throw GoogleError.invalidCredentials
  }
}
public enum GoogleError: Error, LocalizedError {
  case invalidCredentials, unauthorized, requestFailed, invalidCallback, cancelled, timedOut
  public var errorDescription: String? {
    switch self {
    case .invalidCredentials: return "デスクトップアプリ用のGoogle認証ファイルを選んでください。"
    case .unauthorized: return "Googleへの接続が切れました。もう一度接続してください。"
    case .requestFailed: return "Googleから予定を取得できませんでした。接続を確認し、再試行してください。"
    case .invalidCallback: return "Google認証の応答を確認できませんでした。"
    case .cancelled: return "Googleへの接続をキャンセルしました。"
    case .timedOut: return "Googleへの接続が時間切れになりました。もう一度接続してください。"
    }
  }
}
public enum OAuthCallback {
  public static func code(requestTarget: String, expectedState: String) throws -> String {
    guard requestTarget.hasPrefix("/"), !requestTarget.hasPrefix("//"),
      let parts = URLComponents(string: requestTarget), parts.scheme == nil, parts.host == nil,
      parts.fragment == nil, parts.path == "/oauth/callback",
      parts.queryItems?.filter({ $0.name == "state" }).count == 1,
      parts.queryItems?.first(where: { $0.name == "state" })?.value == expectedState
    else { throw GoogleError.invalidCallback }
    if parts.queryItems?.contains(where: { $0.name == "error" }) == true {
      throw GoogleError.cancelled
    }
    guard parts.queryItems?.filter({ $0.name == "code" }).count == 1,
      let code = parts.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty
    else { throw GoogleError.invalidCallback }
    return code
  }
}
public struct GoogleCalendarAPI {
  public let session: URLSession
  public init(session: URLSession = .shared) { self.session = session }
  public static func form(_ values: [String: String]) -> Data {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    return Data(
      values.sorted(by: { $0.key < $1.key }).map {
        "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
      }.joined(separator: "&").utf8)
  }
  public func token(values: [String: String]) async throws -> (access: String, refresh: String?) {
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Self.form(values)
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode)
    else { throw GoogleError.unauthorized }
    struct Token: Decodable {
      let access_token: String
      let refresh_token: String?
    }
    let result = try JSONDecoder().decode(Token.self, from: data)
    return (result.access_token, result.refresh_token)
  }
  public func events(
    credentials: GoogleCredentials, now: Date = Date(), calendar: Calendar = .current
  ) async throws -> [CalendarEvent] {
    guard let refresh = credentials.refreshToken else { throw GoogleError.unauthorized }
    var fields = [
      "client_id": credentials.clientID, "refresh_token": refresh, "grant_type": "refresh_token",
    ]
    if let secret = credentials.clientSecret { fields["client_secret"] = secret }
    let access = try await token(values: fields).access
    let day = calendar.dateInterval(of: .day, for: now)!
    let iso = ISO8601DateFormatter()
    var events: [CalendarEvent] = []
    var next: String?
    var seen = Set<String>()
    repeat {
      var url = URLComponents(
        string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
      url.queryItems = [
        URLQueryItem(name: "timeMin", value: iso.string(from: day.start)),
        URLQueryItem(name: "timeMax", value: iso.string(from: day.end)),
        URLQueryItem(name: "singleEvents", value: "true"),
        URLQueryItem(name: "orderBy", value: "startTime"),
        URLQueryItem(name: "maxResults", value: "2500"),
      ]
      if let next { url.queryItems!.append(URLQueryItem(name: "pageToken", value: next)) }
      var request = URLRequest(url: url.url!)
      request.timeoutInterval = 30
      request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
      let (data, response) = try await session.data(for: request)
      guard let response = response as? HTTPURLResponse else { throw GoogleError.requestFailed }
      if response.statusCode == 401 { throw GoogleError.unauthorized }
      guard (200..<300).contains(response.statusCode) else { throw GoogleError.requestFailed }
      struct Page: Decodable {
        let items: [CalendarEvent]?
        let nextPageToken: String?
      }
      let page = try JSONDecoder().decode(Page.self, from: data)
      events += page.items ?? []
      next = page.nextPageToken
      if let next, !seen.insert(next).inserted { throw GoogleError.requestFailed }
    } while next != nil
    return events
  }
}
