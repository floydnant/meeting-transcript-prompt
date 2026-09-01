import SwiftUI

@main
struct MeetingTranscriptPromptApp: App {
  @StateObject private var environment = AppEnvironment()

  var body: some Scene {
    MenuBarExtra {
      MenuBarContent(environment: environment)
    } label: {
      Label(
        "Meeting Transcript Prompt",
        systemImage: environment.promptCoordinator.needsAttention
          ? "waveform.badge.mic"
          : "waveform"
      )
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(environment: environment)
    }
  }
}

private struct MenuBarContent: View {
  @Environment(\.openSettings) private var openSettings
  @ObservedObject var environment: AppEnvironment
  @ObservedObject private var preferences: PreferencesStore
  @ObservedObject private var promptCoordinator: PromptCoordinator

  init(environment: AppEnvironment) {
    self.environment = environment
    preferences = environment.preferences
    promptCoordinator = environment.promptCoordinator
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Meeting Transcript Prompt")
            .font(.headline)
          Text(preferences.value.isEnabled ? "Detection is on" : "Detection is off")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Toggle("", isOn: $preferences.value.isEnabled)
          .labelsHidden()
      }

      if let request = promptCoordinator.currentRequest {
        Button {
          promptCoordinator.showCurrentPrompt()
        } label: {
          Label(request.title, systemImage: "bell.badge")
            .lineLimit(1)
        }
        .buttonStyle(.borderedProminent)
      }

      Divider()

      Button {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
        Task { @MainActor in
          await bringSettingsToFront()
        }
      } label: {
        Label("Settings…", systemImage: "gear")
      }
      Button("Show test meeting prompt") {
        environment.showTestPrompt()
      }
      Button("Open transcription app") {
        try? environment.transcriptAppController.open()
      }
      .disabled(preferences.value.transcriptAppBundleID.isEmpty)
      Divider()
      Button("Quit") { NSApplication.shared.terminate(nil) }
    }
    .padding(14)
    .frame(width: 290)
    .task { environment.start() }
  }

  @MainActor
  private func bringSettingsToFront() async {
    for _ in 0..<15 {
      if let settingsWindow = NSApplication.shared.windows.first(where: {
        $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
      }) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()
        return
      }
      try? await Task.sleep(for: .milliseconds(100))
    }
  }
}
