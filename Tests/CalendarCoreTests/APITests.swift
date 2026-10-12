import CalendarCore
import Foundation

final class MockGoogle: URLProtocol {
  static var requests: [URLRequest] = []
  static var bodies: [String] = []
  static var statuses: [Int] = []
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.requests.append(request)
    let body = Self.bodies.removeFirst()
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: request.url!, statusCode: Self.statuses.isEmpty ? 200 : Self.statuses.removeFirst(),
        httpVersion: nil, headerFields: nil)!,
      cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
final class APITests {
  func testPaginationUsesNativeGoogleEndpointsAndBearer() async throws {
    MockGoogle.requests = []
    MockGoogle.bodies = [
      #"{"access_token":"sample-access"}"#,
      #"{"items":[{"id":"first"}],"nextPageToken":"next+page"}"#, #"{"items":[{"id":"second"}]}"#,
    ]
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockGoogle.self]
    let api = GoogleCalendarAPI(session: URLSession(configuration: config))
    let events = try await api.events(
      credentials: GoogleCredentials(
        clientID: "sample.apps.googleusercontent.com", refreshToken: "sample-refresh"))
    XCTAssertEqual(events.map(\.id), ["first", "second"])
    XCTAssertEqual(MockGoogle.requests.count, 3)
    XCTAssertEqual(MockGoogle.requests[0].url?.host, "oauth2.googleapis.com")
    XCTAssertEqual(MockGoogle.requests[1].url?.host, "www.googleapis.com")
    XCTAssertEqual(
      MockGoogle.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer sample-access")
    XCTAssertEqual(
      URLComponents(url: MockGoogle.requests[2].url!, resolvingAgainstBaseURL: false)?.queryItems?
        .first(where: { $0.name == "pageToken" })?.value, "next+page")
  }
  func testFailedAuthorizationAndRepeatedPageToken() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockGoogle.self]
    let api = GoogleCalendarAPI(session: URLSession(configuration: config))
    let credentials = GoogleCredentials(
      clientID: "sample.apps.googleusercontent.com", refreshToken: "sample-refresh")
    MockGoogle.bodies = ["{}"]
    MockGoogle.statuses = [400]
    do {
      _ = try await api.events(credentials: credentials)
      preconditionFailure("Rejected refresh token must fail")
    } catch GoogleError.unauthorized {}
    MockGoogle.bodies = [
      #"{"access_token":"sample-access"}"#, #"{"items":[],"nextPageToken":"repeat"}"#,
      #"{"items":[],"nextPageToken":"repeat"}"#,
    ]
    do {
      _ = try await api.events(credentials: credentials)
      preconditionFailure("Repeated page token must fail")
    } catch GoogleError.requestFailed {}
  }

}
