import Combine
import Foundation

struct AppPreferences: Codable, Equatable, Sendable {
  var isEnabled = true
  var calendarDetectionEnabled = true
  var teamsDetectionEnabled = true
  var monitorAllCalendars = true
  var selectedCalendarIDs: Set<String> = []
  var transcriptAppBundleID = ""
  var transcriptAppName = "Transcription app"
  var ignoredBundleIDs: Set<String> = []
  var ignoredTitlePhrases: [String] = ["focus time", "lunch"]
  var positiveWindowTitlePhrases: [String] = ["meeting", "call"]
  var negativeWindowTitlePhrases: [String] = []
  var reminderOffsetSeconds: TimeInterval = 0
  var microphoneActivationDelay: TimeInterval = 3
  var teamsFocusGracePeriod: TimeInterval = 60
  var snoozeDurationsMinutes: [Int] = [5, 15]
  var promptVisibilitySeconds: TimeInterval = 20
  var duplicateCooldown: TimeInterval = 300
  var launchAtLogin = false
  var experimentalAutoStart = false
  var diagnosticsEnabled = true
  var diagnosticsRetentionDays = 7

  static let teamsBundleIDs: Set<String> = [
    "com.microsoft.teams2",
    "com.microsoft.teams",
  ]
}

@MainActor
final class PreferencesStore: ObservableObject {
  @Published var value: AppPreferences {
    didSet { save() }
  }

  private let defaults: UserDefaults
  private let key = "app-preferences-v1"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: key),
      let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data)
    {
      value = decoded
    } else {
      value = AppPreferences()
    }
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(value) else { return }
    defaults.set(data, forKey: key)
  }
}
