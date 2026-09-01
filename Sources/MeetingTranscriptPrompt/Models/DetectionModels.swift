import Foundation

enum DetectionTrigger: String, Codable, Sendable {
  case calendar
  case teamsMicrophone
  case combined
}

struct MeetingCandidate: Equatable, Sendable {
  let id: String
  let title: String
  let startDate: Date
  let endDate: Date
  let trigger: DetectionTrigger
  let sourceBundleID: String?
  let windowTitleMatched: Bool
}

struct PromptRequest: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let trigger: DetectionTrigger
  let endDate: Date
}

enum DetectionDecision: Equatable, Sendable {
  case prompt(MeetingCandidate)
  case suppress(reason: String)
  case none
}

struct CalendarEventSnapshot: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let startDate: Date
  let endDate: Date
  let calendarID: String
  let isAllDay: Bool
  let isCancelled: Bool
  let isDeclined: Bool
  let isFree: Bool
  let hasOtherAttendee: Bool
}

struct AudioProcessSnapshot: Equatable, Sendable {
  let pid: pid_t
  let bundleID: String
  let localizedName: String
}
