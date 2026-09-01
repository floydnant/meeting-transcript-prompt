import EventKit
import Foundation

struct CalendarChoice: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let sourceTitle: String
}

@MainActor
final class CalendarService: ObservableObject {
  @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)
  @Published private(set) var calendars: [CalendarChoice] = []
  @Published private(set) var upcomingEvents: [CalendarEventSnapshot] = []

  private let store = EKEventStore()

  var hasFullAccess: Bool {
    authorizationStatus == .fullAccess
  }

  func requestAccess() async {
    do {
      _ = try await store.requestFullAccessToEvents()
    } catch {
      // The settings UI reports the resulting authorization state.
    }
    authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    refreshCalendars()
  }

  func refreshCalendars() {
    authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    guard hasFullAccess else {
      calendars = []
      upcomingEvents = []
      return
    }
    calendars = store.calendars(for: .event).map {
      CalendarChoice(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title)
    }.sorted {
      "\($0.sourceTitle)\u{0}\($0.title)".localizedStandardCompare(
        "\($1.sourceTitle)\u{0}\($1.title)"
      ) == .orderedAscending
    }
  }

  func refreshEvents(now: Date = Date()) {
    guard hasFullAccess else {
      upcomingEvents = []
      return
    }
    let start = now.addingTimeInterval(-120)
    let end = now.addingTimeInterval(6 * 60 * 60)
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    upcomingEvents = store.events(matching: predicate).map(Self.snapshot)
  }

  private static func snapshot(_ event: EKEvent) -> CalendarEventSnapshot {
    let currentParticipant = event.attendees?.first(where: \.isCurrentUser)
    let hasOtherAttendee = event.attendees?.contains(where: { !$0.isCurrentUser }) ?? false
    return CalendarEventSnapshot(
      id: event.eventIdentifier ?? event.calendarItemIdentifier,
      title: event.title ?? "Meeting",
      startDate: event.startDate,
      endDate: event.endDate,
      calendarID: event.calendar.calendarIdentifier,
      isAllDay: event.isAllDay,
      isCancelled: event.status == .canceled,
      isDeclined: currentParticipant?.participantStatus == .declined,
      isFree: event.availability == .free,
      hasOtherAttendee: hasOtherAttendee
    )
  }
}
