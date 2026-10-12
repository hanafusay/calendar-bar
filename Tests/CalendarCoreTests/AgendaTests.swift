import CalendarCore
import Foundation

final class AgendaTests {
  func event(
    _ id: String = "a", start: String = "2026-10-12T09:00:00+09:00",
    end: String = "2026-10-12T10:00:00+09:00", extra: [String: Any] = [:]
  ) throws -> CalendarEvent {
    var object: [String: Any] = [
      "id": id, "summary": "Example meeting", "start": ["dateTime": start],
      "end": ["dateTime": end],
    ]
    object.merge(extra, uniquingKeysWith: { _, value in value })
    return try JSONDecoder().decode(
      CalendarEvent.self, from: JSONSerialization.data(withJSONObject: object))
  }
  var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return value
  }
  func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
  func testBoundaryAndCompleted() throws {
    let item = try event()
    let start = Agenda(events: [item], now: date("2026-10-12T09:00:00+09:00"), calendar: calendar)
    XCTAssertEqual(start.entries.first?.state, .current)
    XCTAssertEqual(start.title, "▶ Example meeting 〜10:00")
    let end = Agenda(events: [item], now: date("2026-10-12T10:00:00+09:00"), calendar: calendar)
    XCTAssertEqual(end.entries.first?.state, .completed)
    XCTAssertEqual(end.title, "📅 今日は終了")
  }
  func testFiltersAndMidnight() throws {
    let events = try [
      event("cancelled", extra: ["status": "cancelled"]),
      event("work", extra: ["eventType": "workingLocation"]),
      event("declined", extra: ["attendees": [["self": true, "responseStatus": "declined"]]]),
      event("all-day", extra: ["start": ["date": "2026-10-12"], "end": ["date": "2026-10-13"]]),
      event("overnight", start: "2026-10-11T23:30:00+09:00", end: "2026-10-12T00:30:00+09:00"),
    ]
    let agenda = Agenda(events: events, now: date("2026-10-12T00:00:00+09:00"), calendar: calendar)
    XCTAssertEqual(agenda.entries.map(\.event.id), ["overnight"])
    XCTAssertEqual(agenda.entries.first?.state, .current)
  }
  func testOrderingCountdownAndFullTitle() throws {
    let late = try event(
      "late", start: "2026-10-12T11:00:00+09:00", end: "2026-10-12T12:00:00+09:00")
    let early = try event("early", extra: ["summary": String(repeating: "会議", count: 40)])
    let agenda = Agenda(
      events: [late, early], now: date("2026-10-12T08:30:00+09:00"), calendar: calendar)
    XCTAssertEqual(agenda.entries.map(\.event.id), ["early", "late"])
    XCTAssertEqual(agenda.title.count, 40)
    XCTAssertTrue(agenda.entries[0].title.contains(String(repeating: "会議", count: 40)))
    XCTAssertEqual(
      Agenda(events: [late], now: date("2026-10-12T10:30:00+09:00"), calendar: calendar).title,
      "📅 11:00 Example meeting（あと30分）")
  }
  func testTimezoneAndLinkValidation() throws {
    var utc = calendar
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    let agenda = Agenda(events: [try event()], now: date("2026-10-12T00:00:00Z"), calendar: utc)
    XCTAssertEqual(agenda.title, "▶ Example meeting 〜01:00")
    XCTAssertNil(CalendarLinks.validated("https://meet.google.com.evil.example/", meet: true))
    XCTAssertNil(CalendarLinks.validated("http://meet.google.com/", meet: true))
    XCTAssertNil(CalendarLinks.validated("https://user@meet.google.com/", meet: true))
    XCTAssertNotNil(CalendarLinks.validated("https://meet.google.com/abc", meet: true))
  }
  func testCallbackSecurity() throws {
    XCTAssertEqual(
      try OAuthCallback.code(
        requestTarget: "/oauth/callback?state=expected&code=hello%20world",
        expectedState: "expected"), "hello world")
    XCTAssertThrowsError(
      try OAuthCallback.code(
        requestTarget: "/oauth/callback?state=wrong&code=x", expectedState: "expected"))
    XCTAssertThrowsError(
      try OAuthCallback.code(
        requestTarget: "/oauth/callback?state=expected&state=expected&code=x",
        expectedState: "expected"))
    XCTAssertThrowsError(
      try OAuthCallback.code(
        requestTarget: "https://evil.example/oauth/callback?state=expected&code=x",
        expectedState: "expected"))
    XCTAssertThrowsError(
      try OAuthCallback.code(
        requestTarget: "/oauth/callback?state=expected&code=x&code=y", expectedState: "expected"))
    XCTAssertThrowsError(
      try OAuthCallback.code(
        requestTarget: "/wrong?state=expected&code=x", expectedState: "expected"))
    XCTAssertThrowsError(
      try OAuthCallback.code(
        requestTarget: "/oauth/callback?state=expected&error=access_denied",
        expectedState: "expected"))
  }
  func testCredentialImportAndForm() throws {
    let data = Data(
      #"{"installed":{"client_id":"example.apps.googleusercontent.com","client_secret":"sample"}}"#
        .utf8)
    XCTAssertEqual(
      try GoogleCredentials.importing(data).clientID, "example.apps.googleusercontent.com")
    XCTAssertThrowsError(
      try GoogleCredentials.importing(
        Data(#"{"web":{"client_id":"example.apps.googleusercontent.com"}}"#.utf8)))
    XCTAssertEqual(
      String(data: GoogleCalendarAPI.form(["code": "a&b +"]), encoding: .utf8), "code=a%26b%20%2B")
  }
}
