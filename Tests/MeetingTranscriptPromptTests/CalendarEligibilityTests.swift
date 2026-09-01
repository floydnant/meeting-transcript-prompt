import Foundation
import Testing

@testable import MeetingTranscriptPrompt

struct CalendarEligibilityTests {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  @Test func acceptsMeetingWithAnotherAttendee() {
    let event = makeEvent()
    #expect(CalendarEligibility.isEligible(event, preferences: AppPreferences()))
  }

  @Test func rejectsSoloEvent() {
    let event = makeEvent(hasOtherAttendee: false)
    #expect(!CalendarEligibility.isEligible(event, preferences: AppPreferences()))
  }

  @Test func rejectsIgnoredTitleCaseInsensitively() {
    let event = makeEvent(title: "Product Focus Time")
    #expect(!CalendarEligibility.isEligible(event, preferences: AppPreferences()))
  }

  @Test func respectsSelectedCalendars() {
    var preferences = AppPreferences()
    preferences.monitorAllCalendars = false
    preferences.selectedCalendarIDs = ["work"]
    #expect(CalendarEligibility.isEligible(makeEvent(calendarID: "work"), preferences: preferences))
    #expect(
      !CalendarEligibility.isEligible(makeEvent(calendarID: "personal"), preferences: preferences))
  }

  @Test func rejectsCancelledDeclinedFreeAndAllDayEvents() {
    let preferences = AppPreferences()
    #expect(!CalendarEligibility.isEligible(makeEvent(isAllDay: true), preferences: preferences))
    #expect(!CalendarEligibility.isEligible(makeEvent(isCancelled: true), preferences: preferences))
    #expect(!CalendarEligibility.isEligible(makeEvent(isDeclined: true), preferences: preferences))
    #expect(!CalendarEligibility.isEligible(makeEvent(isFree: true), preferences: preferences))
  }

  private func makeEvent(
    title: String = "Weekly sync",
    calendarID: String = "work",
    isAllDay: Bool = false,
    isCancelled: Bool = false,
    isDeclined: Bool = false,
    isFree: Bool = false,
    hasOtherAttendee: Bool = true
  ) -> CalendarEventSnapshot {
    CalendarEventSnapshot(
      id: "event-1",
      title: title,
      startDate: now,
      endDate: now.addingTimeInterval(1800),
      calendarID: calendarID,
      isAllDay: isAllDay,
      isCancelled: isCancelled,
      isDeclined: isDeclined,
      isFree: isFree,
      hasOtherAttendee: hasOtherAttendee
    )
  }

  @Test func allowsSelectingNoCalendars() {
    var preferences = AppPreferences()
    preferences.monitorAllCalendars = false
    preferences.selectedCalendarIDs = []
    #expect(
      !CalendarEligibility.isEligible(
        makeEvent(calendarID: "work"), preferences: preferences))
  }

  @Test func ignoresBlankExclusionPhrases() {
    var preferences = AppPreferences()
    preferences.ignoredTitlePhrases = ["", "   "]
    #expect(CalendarEligibility.isEligible(makeEvent(), preferences: preferences))
  }
}
