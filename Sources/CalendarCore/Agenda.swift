import Foundation

public struct CalendarEvent: Decodable, Equatable, Sendable {
  public struct Moment: Decodable, Equatable, Sendable {
    public let dateTime: String?
    public let date: String?
  }
  public struct Attendee: Decodable, Equatable, Sendable {
    public let isSelf: Bool?
    public let responseStatus: String?
    enum CodingKeys: String, CodingKey {
      case isSelf = "self"
      case responseStatus
    }
  }
  public let id: String
  public let summary: String?
  public let status: String?
  public let eventType: String?
  public let start: Moment?
  public let end: Moment?
  public let attendees: [Attendee]?
  public let hangoutLink: String?
  public let htmlLink: String?
}

public struct Agenda {
  public struct Entry {
    public enum State { case current, upcoming, completed }
    public let event: CalendarEvent
    public let start: Date
    public let end: Date
    public let state: State
    public let title: String
  }
  public let entries: [Entry]
  public let title: String

  public init(events: [CalendarEvent], now: Date, calendar: Calendar = .current) {
    let day = calendar.dateInterval(of: .day, for: now)!
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "HH:mm"
    let iso = ISO8601DateFormatter()
    func date(_ value: String?) -> Date? {
      guard let value else { return nil }
      iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let parsed = iso.date(from: value) { return parsed }
      iso.formatOptions = [.withInternetDateTime]
      return iso.date(from: value)
    }
    entries = events.compactMap { event -> Entry? in
      guard event.status != "cancelled", event.eventType != "workingLocation",
        !(event.attendees ?? []).contains(where: {
          $0.isSelf == true && $0.responseStatus == "declined"
        }),
        let start = date(event.start?.dateTime), let end = date(event.end?.dateTime),
        end > start, start < day.end, end > day.start
      else { return nil }
      let state: Entry.State = end <= now ? .completed : (start <= now ? .current : .upcoming)
      let mark = state == .current ? "▶" : (state == .completed ? "✓" : "・")
      return Entry(
        event: event, start: start, end: end, state: state,
        title:
          "\(mark) \(formatter.string(from: start))-\(formatter.string(from: end)) \(event.summary ?? "(無題)")"
      )
    }.sorted { $0.start == $1.start ? $0.event.id < $1.event.id : $0.start < $1.start }
    let fullTitle: String
    if let entry = entries.first(where: { $0.state == .current }) {
      fullTitle = "▶ \(entry.event.summary ?? "(無題)") 〜\(formatter.string(from: entry.end))"
    } else if let entry = entries.first(where: { $0.state == .upcoming }) {
      let minutes = Int(entry.start.timeIntervalSince(now) / 60)
      let when = minutes < 60 ? "あと\(minutes)分" : formatter.string(from: entry.start)
      fullTitle =
        "📅 \(formatter.string(from: entry.start)) \(entry.event.summary ?? "(無題)")（\(when)）"
    } else {
      fullTitle = "📅 今日は終了"
    }
    title = fullTitle.count > 40 ? String(fullTitle.prefix(39)) + "…" : fullTitle
  }
}

public enum CalendarLinks {
  public static func validated(_ text: String?, meet: Bool) -> URL? {
    guard let text, let url = URL(string: text), url.scheme == "https", url.user == nil,
      url.password == nil,
      url.port == nil || url.port == 443
    else { return nil }
    let hosts = meet ? ["meet.google.com"] : ["calendar.google.com", "www.google.com"]
    guard let host = url.host?.lowercased(), hosts.contains(host) else { return nil }
    if host == "www.google.com" && !url.path.hasPrefix("/calendar/") { return nil }
    return url
  }
}
