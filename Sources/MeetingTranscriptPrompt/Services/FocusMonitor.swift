import AppKit
import CoreGraphics
import Foundation

@MainActor
final class FocusMonitor {
  private(set) var lastTeamsFocusDate: Date?
  private(set) var frontmostBundleID: String?

  func sample(now: Date = Date()) {
    frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    if isTeams(bundleID: frontmostBundleID) {
      lastTeamsFocusDate = now
    }
  }

  func teamsWasRecentlyFocused(now: Date, gracePeriod: TimeInterval) -> Bool {
    guard let lastTeamsFocusDate else { return false }
    return now.timeIntervalSince(lastTeamsFocusDate) <= gracePeriod
  }

  func matchingTeamsWindowTitle(preferences: AppPreferences) -> Bool {
    let titles = teamsWindowTitles().map { $0.lowercased() }
    guard !titles.isEmpty else { return false }

    let hasNegativeMatch = preferences.negativeWindowTitlePhrases.contains { phrase in
      let normalized = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return !normalized.isEmpty && titles.contains(where: { $0.contains(normalized) })
    }
    if hasNegativeMatch { return false }

    if preferences.positiveWindowTitlePhrases.isEmpty { return true }
    return preferences.positiveWindowTitlePhrases.contains { phrase in
      let normalized = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return !normalized.isEmpty && titles.contains(where: { $0.contains(normalized) })
    }
  }

  func isTeams(bundleID: String?) -> Bool {
    guard let bundleID else { return false }
    return AppPreferences.teamsBundleIDs.contains(bundleID)
  }

  private func teamsWindowTitles() -> [String] {
    guard
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else { return [] }

    let teamsPIDs = Set(
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.teams2").map(
        \.processIdentifier)
        + NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.teams").map(
          \.processIdentifier))

    return windows.compactMap { window in
      guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
        teamsPIDs.contains(ownerPID)
      else { return nil }
      return window[kCGWindowName as String] as? String
    }
  }
}
