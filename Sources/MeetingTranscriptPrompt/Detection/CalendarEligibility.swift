import Foundation

enum CalendarEligibility {
  static func isEligible(
    _ event: CalendarEventSnapshot,
    preferences: AppPreferences
  ) -> Bool {
    guard preferences.calendarDetectionEnabled,
      !event.isAllDay,
      !event.isCancelled,
      !event.isDeclined,
      !event.isFree,
      event.hasOtherAttendee
    else {
      return false
    }

    if !preferences.monitorAllCalendars,
      !preferences.selectedCalendarIDs.contains(event.calendarID)
    {
      return false
    }

    let title = event.title.lowercased()
    return !preferences.ignoredTitlePhrases.contains { phrase in
      let normalized = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return !normalized.isEmpty && title.contains(normalized)
    }
  }
}
