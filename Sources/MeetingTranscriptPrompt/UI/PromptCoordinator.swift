import AppKit
import SwiftUI

@MainActor
final class PromptCoordinator: ObservableObject {
  @Published private(set) var currentRequest: PromptRequest?
  @Published private(set) var needsAttention = false
  @Published private(set) var countdown: Int?
  @Published var errorMessage: String?

  private let transcriptAppController: TranscriptAppController
  private let diagnostics: DiagnosticsLogger
  private let preferences: PreferencesStore
  private var panel: NSPanel?
  private var visibilityTask: Task<Void, Never>?
  private var countdownTask: Task<Void, Never>?

  var onSnooze: ((PromptRequest, Int) -> Void)?
  var onDismiss: ((PromptRequest) -> Void)?

  var snoozeDurations: [Int] {
    preferences.value.snoozeDurationsMinutes
  }

  init(
    transcriptAppController: TranscriptAppController,
    diagnostics: DiagnosticsLogger,
    preferences: PreferencesStore
  ) {
    self.transcriptAppController = transcriptAppController
    self.diagnostics = diagnostics
    self.preferences = preferences
  }

  func present(_ request: PromptRequest) {
    currentRequest = request
    needsAttention = true
    errorMessage = nil
    createPanelIfNeeded()
    positionPanel()
    panel?.orderFrontRegardless()
    schedulePanelHide()

    if preferences.value.experimentalAutoStart {
      beginAutoStartCountdown()
    }
  }

  func showCurrentPrompt() {
    guard currentRequest != nil else { return }
    createPanelIfNeeded()
    positionPanel()
    panel?.orderFrontRegardless()
  }

  func openTranscriptApp() {
    guard let request = currentRequest else { return }
    do {
      try transcriptAppController.open()
      diagnostics.log(
        category: "prompt_action",
        trigger: request.trigger,
        decision: "opened_transcript_app",
        preferences: preferences.value
      )
      finish()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func snooze(minutes: Int) {
    guard let request = currentRequest else { return }
    cancelCountdown()
    onSnooze?(request, minutes)
    finish()
  }

  func dismiss() {
    guard let request = currentRequest else { return }
    cancelCountdown()
    onDismiss?(request)
    finish()
  }

  func cancelCountdown() {
    countdownTask?.cancel()
    countdownTask = nil
    countdown = nil
  }

  private func beginAutoStartCountdown() {
    countdownTask?.cancel()
    countdown = 5
    countdownTask = Task { [weak self] in
      guard let self else { return }
      for remaining in stride(from: 5, through: 1, by: -1) {
        guard !Task.isCancelled else { return }
        countdown = remaining
        try? await Task.sleep(for: .seconds(1))
      }
      guard !Task.isCancelled, let request = currentRequest else { return }
      countdown = nil
      do {
        try await transcriptAppController.openAndStartRecording()
        diagnostics.log(
          category: "prompt_action",
          trigger: request.trigger,
          decision: "auto_started_recording",
          preferences: preferences.value
        )
        finish()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func schedulePanelHide() {
    visibilityTask?.cancel()
    let duration = preferences.value.promptVisibilitySeconds
    visibilityTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(duration))
      guard !Task.isCancelled else { return }
      self?.panel?.orderOut(nil)
    }
  }

  private func finish() {
    visibilityTask?.cancel()
    cancelCountdown()
    panel?.orderOut(nil)
    currentRequest = nil
    needsAttention = false
  }

  private func createPanelIfNeeded() {
    guard panel == nil else { return }
    let content = PromptPanelView(coordinator: self)
    let panel = ActionPanel(
      contentRect: NSRect(x: 0, y: 0, width: 390, height: 220),
      styleMask: [.titled, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.contentView = NSHostingView(rootView: content)
    self.panel = panel
  }

  private func positionPanel() {
    guard let panel, let screen = NSScreen.main else { return }
    let visible = screen.visibleFrame
    panel.setFrameOrigin(
      NSPoint(
        x: visible.maxX - panel.frame.width - 16,
        y: visible.maxY - panel.frame.height - 16
      ))
  }
}

private final class ActionPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

private struct PromptPanelView: View {
  @ObservedObject var coordinator: PromptCoordinator

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Image(systemName: "waveform.badge.mic")
          .font(.title2)
        VStack(alignment: .leading, spacing: 2) {
          Text("Meeting detected")
            .font(.headline)
          Text(coordinator.currentRequest?.title ?? "Meeting")
            .font(.subheadline)
            .lineLimit(2)
        }
        Spacer()
      }

      if let countdown = coordinator.countdown {
        HStack {
          ProgressView()
            .controlSize(.small)
          Text("Starting recording in \(countdown)…")
          Spacer()
          Button("Cancel") { coordinator.cancelCountdown() }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .font(.caption)
      }

      if let error = coordinator.errorMessage {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Button("Open transcription app") { coordinator.openTranscriptApp() }
          .buttonStyle(.borderedProminent)
        Menu("Snooze") {
          ForEach(coordinator.snoozeDurations, id: \.self) { minutes in
            Button("\(minutes) minutes") { coordinator.snooze(minutes: minutes) }
          }
        }
        Button("Dismiss") { coordinator.dismiss() }
        Spacer()
      }
    }
    .padding(20)
    .frame(width: 390)
    .frame(minHeight: 190)
    .background(.regularMaterial)
  }
}
