import Foundation

@MainActor
final class MeetingDetectionEngine: ObservableObject {
  private let preferences: PreferencesStore
  private let calendarService: CalendarService
  private let audioMonitor: AudioProcessMonitor
  private let focusMonitor: FocusMonitor
  private let diagnostics: DiagnosticsLogger

  private var timer: Timer?
  private var lastCalendarRefresh = Date.distantPast
  private var teamsMicStartedAt: Date?
  private var teamsSessionID: String?
  private var lastTeamsMicDate: Date?
  private var promptedIDs: Set<String> = []
  private var snoozedUntil: [String: Date] = [:]
  private var dismissedUntil: [String: Date] = [:]
  private var lastPromptDate: Date?

  var onPrompt: ((PromptRequest) -> Void)?

  init(
    preferences: PreferencesStore,
    calendarService: CalendarService,
    audioMonitor: AudioProcessMonitor,
    focusMonitor: FocusMonitor,
    diagnostics: DiagnosticsLogger
  ) {
    self.preferences = preferences
    self.calendarService = calendarService
    self.audioMonitor = audioMonitor
    self.focusMonitor = focusMonitor
    self.diagnostics = diagnostics
  }

  func start() {
    guard timer == nil else { return }
    calendarService.refreshCalendars()
    calendarService.refreshEvents()
    lastCalendarRefresh = Date()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.tick()
      }
    }
    tick()
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    resetTeamsSession()
  }

  func snooze(_ request: PromptRequest, minutes: Int) {
    let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
    snoozedUntil[request.id] = until
    promptedIDs.remove(request.id)
    diagnostics.log(
      category: "prompt_action",
      trigger: request.trigger,
      eventID: safeEventID(for: request),
      decision: "snoozed",
      detail: "minutes=\(minutes)",
      preferences: preferences.value
    )
  }

  func dismiss(_ request: PromptRequest) {
    dismissedUntil[request.id] = request.endDate
    promptedIDs.insert(request.id)
    diagnostics.log(
      category: "prompt_action",
      trigger: request.trigger,
      eventID: safeEventID(for: request),
      decision: "dismissed",
      preferences: preferences.value
    )
  }

  private func tick(now: Date = Date()) {
    let config = preferences.value
    focusMonitor.sample(now: now)
    cleanupSuppression(now: now)

    guard config.isEnabled else {
      resetTeamsSession()
      return
    }

    if now.timeIntervalSince(lastCalendarRefresh) >= 30 {
      calendarService.refreshEvents(now: now)
      lastCalendarRefresh = now
    }

    let audioProcesses = audioMonitor.processesUsingMicrophone()
    let calendarCandidate = currentCalendarCandidate(now: now, preferences: config)
    let teamsCandidate = currentTeamsCandidate(
      now: now,
      audioProcesses: audioProcesses,
      calendarCandidate: calendarCandidate,
      preferences: config
    )

    if let teamsCandidate {
      consider(teamsCandidate, now: now, preferences: config)
    } else if let calendarCandidate {
      consider(calendarCandidate, now: now, preferences: config)
    }
  }

  private func currentCalendarCandidate(
    now: Date,
    preferences: AppPreferences
  ) -> MeetingCandidate? {
    guard preferences.calendarDetectionEnabled else { return nil }
    return calendarService.upcomingEvents
      .filter { CalendarEligibility.isEligible($0, preferences: preferences) }
      .filter { event in
        let triggerDate = event.startDate.addingTimeInterval(-preferences.reminderOffsetSeconds)
        return triggerDate <= now && event.endDate > now
      }
      .sorted { $0.startDate > $1.startDate }
      .first
      .map { event in
        MeetingCandidate(
          id: "calendar:\(event.id):\(Int(event.startDate.timeIntervalSince1970))",
          title: event.title,
          startDate: event.startDate,
          endDate: event.endDate,
          trigger: .calendar,
          sourceBundleID: nil,
          windowTitleMatched: false
        )
      }
  }

  private func currentTeamsCandidate(
    now: Date,
    audioProcesses: [AudioProcessSnapshot],
    calendarCandidate: MeetingCandidate?,
    preferences: AppPreferences
  ) -> MeetingCandidate? {
    guard preferences.teamsDetectionEnabled else {
      resetTeamsSession()
      return nil
    }

    let teamsProcess = audioProcesses.first { process in
      AppPreferences.teamsBundleIDs.contains(process.bundleID)
        || process.localizedName.localizedCaseInsensitiveContains("Microsoft Teams")
    }
    guard let teamsProcess else {
      if let lastTeamsMicDate, now.timeIntervalSince(lastTeamsMicDate) > 5 {
        resetTeamsSession()
      }
      return nil
    }

    lastTeamsMicDate = now
    if teamsMicStartedAt == nil {
      teamsMicStartedAt = now
      teamsSessionID = "teams:\(UUID().uuidString)"
    }
    guard let teamsMicStartedAt,
      now.timeIntervalSince(teamsMicStartedAt) >= preferences.microphoneActivationDelay
    else {
      return nil
    }

    let ignoredAppIsActive = audioProcesses.contains { process in
      preferences.ignoredBundleIDs.contains(process.bundleID)
        && focusMonitor.frontmostBundleID == process.bundleID
    }
    if ignoredAppIsActive {
      diagnostics.log(
        category: "detection",
        trigger: .teamsMicrophone,
        bundleID: teamsProcess.bundleID,
        decision: "suppressed",
        detail: "ignored_app_active",
        preferences: preferences
      )
      return nil
    }

    let focusMatched = focusMonitor.teamsWasRecentlyFocused(
      now: now,
      gracePeriod: preferences.teamsFocusGracePeriod
    )
    let windowTitleMatched = focusMonitor.matchingTeamsWindowTitle(preferences: preferences)
    guard focusMatched else { return nil }

    if let calendarCandidate {
      return MeetingCandidate(
        id: calendarCandidate.id,
        title: calendarCandidate.title,
        startDate: calendarCandidate.startDate,
        endDate: calendarCandidate.endDate,
        trigger: .combined,
        sourceBundleID: teamsProcess.bundleID,
        windowTitleMatched: windowTitleMatched
      )
    }

    return MeetingCandidate(
      id: teamsSessionID ?? "teams:unknown",
      title: "Microsoft Teams call",
      startDate: teamsMicStartedAt,
      endDate: now.addingTimeInterval(8 * 60 * 60),
      trigger: .teamsMicrophone,
      sourceBundleID: teamsProcess.bundleID,
      windowTitleMatched: windowTitleMatched
    )
  }

  private func consider(_ candidate: MeetingCandidate, now: Date, preferences: AppPreferences) {
    if promptedIDs.contains(candidate.id) { return }
    if let until = snoozedUntil[candidate.id], until > now { return }
    if let until = dismissedUntil[candidate.id], until > now { return }
    if let lastPromptDate, now.timeIntervalSince(lastPromptDate) < preferences.duplicateCooldown {
      return
    }

    promptedIDs.insert(candidate.id)
    lastPromptDate = now
    diagnostics.log(
      category: "detection",
      trigger: candidate.trigger,
      bundleID: candidate.sourceBundleID,
      eventID: candidate.trigger == .teamsMicrophone ? nil : candidate.id,
      windowTitleMatched: candidate.windowTitleMatched,
      decision: "prompted",
      preferences: preferences
    )
    onPrompt?(
      PromptRequest(
        id: candidate.id,
        title: candidate.title,
        trigger: candidate.trigger,
        endDate: candidate.endDate
      )
    )
  }

  private func cleanupSuppression(now: Date) {
    snoozedUntil = snoozedUntil.filter { $0.value > now }
    dismissedUntil = dismissedUntil.filter { $0.value > now }
  }

  private func resetTeamsSession() {
    teamsMicStartedAt = nil
    teamsSessionID = nil
    lastTeamsMicDate = nil
  }

  private func safeEventID(for request: PromptRequest) -> String? {
    request.trigger == .teamsMicrophone ? nil : request.id
  }
}
