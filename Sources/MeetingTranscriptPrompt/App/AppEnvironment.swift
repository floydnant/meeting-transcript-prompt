import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
  let preferences: PreferencesStore
  let calendarService: CalendarService
  let diagnostics: DiagnosticsLogger
  let transcriptAppController: TranscriptAppController
  let promptCoordinator: PromptCoordinator
  let detectionEngine: MeetingDetectionEngine

  private var started = false

  init() {
    let preferences = PreferencesStore()
    let calendarService = CalendarService()
    let diagnostics = DiagnosticsLogger()
    let transcriptAppController = TranscriptAppController(preferences: preferences)
    let promptCoordinator = PromptCoordinator(
      transcriptAppController: transcriptAppController,
      diagnostics: diagnostics,
      preferences: preferences
    )
    let detectionEngine = MeetingDetectionEngine(
      preferences: preferences,
      calendarService: calendarService,
      audioMonitor: AudioProcessMonitor(),
      focusMonitor: FocusMonitor(),
      diagnostics: diagnostics
    )

    self.preferences = preferences
    self.calendarService = calendarService
    self.diagnostics = diagnostics
    self.transcriptAppController = transcriptAppController
    self.promptCoordinator = promptCoordinator
    self.detectionEngine = detectionEngine

    detectionEngine.onPrompt = { [weak promptCoordinator] request in
      promptCoordinator?.present(request)
    }
    promptCoordinator.onSnooze = { [weak detectionEngine] request, minutes in
      detectionEngine?.snooze(request, minutes: minutes)
    }
    promptCoordinator.onDismiss = { [weak detectionEngine] request in
      detectionEngine?.dismiss(request)
    }
    start()
  }

  func start() {
    guard !started else { return }
    started = true
    detectionEngine.start()
  }

  func showTestPrompt() {
    promptCoordinator.present(
      PromptRequest(
        id: "test:\(UUID().uuidString)",
        title: "Test meeting",
        trigger: .combined,
        endDate: Date().addingTimeInterval(30 * 60)
      )
    )
  }
}
