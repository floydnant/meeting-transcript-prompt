import AppKit
import EventKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @ObservedObject var environment: AppEnvironment
  @ObservedObject private var preferences: PreferencesStore
  @ObservedObject private var calendarService: CalendarService
  @ObservedObject private var diagnostics: DiagnosticsLogger
  @State private var launchAtLoginError: String?
  @State private var automationTestStatus: String?
  @State private var isTestingAutomation = false

  init(environment: AppEnvironment) {
    self.environment = environment
    preferences = environment.preferences
    calendarService = environment.calendarService
    diagnostics = environment.diagnostics
  }

  var body: some View {
    TabView {
      generalTab
        .tabItem { Label("General", systemImage: "gear") }
      calendarTab
        .tabItem { Label("Calendars", systemImage: "calendar") }
      rulesTab
        .tabItem { Label("Rules", systemImage: "slider.horizontal.3") }
      diagnosticsTab
        .tabItem { Label("Diagnostics", systemImage: "doc.text.magnifyingglass") }
    }
    .frame(width: 620, height: 560)
    .padding()
    .task { environment.start() }
    .onAppear {
      bringSettingsToFront()
    }
  }

  private var generalTab: some View {
    Form {
      Section("Transcription app") {
        LabeledContent("Selected app") {
          Text(
            preferences.value.transcriptAppBundleID.isEmpty
              ? "Not selected" : preferences.value.transcriptAppName
          )
        }
        if !preferences.value.transcriptAppBundleID.isEmpty {
          Text(preferences.value.transcriptAppBundleID)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
        Button("Choose transcription app…") {
          chooseTranscriptApplication()
        }
      }

      Section("Detection") {
        Toggle("Enable meeting detection", isOn: $preferences.value.isEnabled)
        Toggle("Detect calendar meetings", isOn: $preferences.value.calendarDetectionEnabled)
        Toggle("Detect Microsoft Teams calls", isOn: $preferences.value.teamsDetectionEnabled)
      }

      Section("Timing") {
        LabeledContent("Calendar reminder") {
          Picker("", selection: $preferences.value.reminderOffsetSeconds) {
            Text("At start").tag(TimeInterval(0))
            Text("1 minute before").tag(TimeInterval(60))
            Text("5 minutes before").tag(TimeInterval(300))
          }
          .labelsHidden()
          .frame(width: 160)
        }
        LabeledContent("Teams microphone delay") {
          Stepper(
            "\(Int(preferences.value.microphoneActivationDelay)) seconds",
            value: $preferences.value.microphoneActivationDelay,
            in: 1...15,
            step: 1
          )
          .frame(width: 150)
        }
        LabeledContent("Recent Teams focus") {
          Stepper(
            "\(Int(preferences.value.teamsFocusGracePeriod)) seconds",
            value: $preferences.value.teamsFocusGracePeriod,
            in: 5...300,
            step: 5
          )
          .frame(width: 150)
        }
        LabeledContent("Prompt visibility") {
          Stepper(
            "\(Int(preferences.value.promptVisibilitySeconds)) seconds",
            value: $preferences.value.promptVisibilitySeconds,
            in: 5...120,
            step: 5
          )
          .frame(width: 150)
        }
        LabeledContent("Snooze options") {
          HStack {
            Stepper(
              "\(snoozeDurationBinding(0).wrappedValue) min",
              value: snoozeDurationBinding(0),
              in: 1...60
            )
            Stepper(
              "\(snoozeDurationBinding(1).wrappedValue) min",
              value: snoozeDurationBinding(1),
              in: 1...120
            )
          }
          .frame(width: 260)
        }
      }

      Section("Startup and automation") {
        Toggle("Launch at login", isOn: launchAtLoginBinding)
        Toggle("Experimental recording auto-start", isOn: $preferences.value.experimentalAutoStart)
        if preferences.value.experimentalAutoStart {
          Text(
            "A five-second countdown appears before the app tries to press the selected app's recording button."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Button("Grant Accessibility permission") {
            _ = environment.transcriptAppController.requestAccessibilityPermission()
          }
        }
        if let launchAtLoginError {
          Text(launchAtLoginError)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Section("Testing") {
        Button("Show test meeting prompt") {
          environment.showTestPrompt()
        }
        Text("This runs the same prompt and countdown flow as a detected meeting.")
          .font(.caption)
          .foregroundStyle(.secondary)

        HStack {
          Button("Check Record button") {
            checkRecordingButton()
          }
          .disabled(isTestingAutomation)
          if isTestingAutomation {
            ProgressView()
              .controlSize(.small)
          }
        }
        Text(
          "This opens the selected app and checks its accessibility tree without starting a recording."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        if let automationTestStatus {
          Text(automationTestStatus)
            .font(.caption)
            .foregroundStyle(automationTestStatus.hasPrefix("Found") ? .green : .red)
        }
      }
    }
    .formStyle(.grouped)
  }

  private var calendarTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      if calendarService.hasFullAccess {
        Text("Select the calendars that should trigger meeting prompts.")
          .foregroundStyle(.secondary)
        Toggle("Monitor all calendars", isOn: $preferences.value.monitorAllCalendars)
        List(calendarService.calendars) { calendar in
          Toggle(isOn: calendarSelectionBinding(calendar.id)) {
            VStack(alignment: .leading) {
              Text(calendar.title)
              Text(calendar.sourceTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .disabled(preferences.value.monitorAllCalendars)
        }
        Button("Refresh calendars") {
          calendarService.refreshCalendars()
        }
      } else {
        ContentUnavailableView(
          "Calendar access is off",
          systemImage: "calendar.badge.exclamationmark",
          description: Text(
            "Calendar access lets the app read event times and determine whether another attendee is invited."
          )
        )
        Button("Allow Calendar access") {
          Task { await calendarService.requestAccess() }
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding()
  }

  private var rulesTab: some View {
    Form {
      Section("Ignored applications") {
        ForEach(preferences.value.ignoredBundleIDs.sorted(), id: \.self) { bundleID in
          HStack {
            Text(bundleID)
            Spacer()
            Button("Remove") {
              preferences.value.ignoredBundleIDs.remove(bundleID)
            }
          }
        }
        Button("Choose application…") { chooseIgnoredApplication() }
      }

      Section("Calendar title exclusions") {
        PhraseListEditor(
          phrases: $preferences.value.ignoredTitlePhrases,
          placeholder: "Example: focus time"
        )
      }

      Section("Teams window titles") {
        Text("Window-title matches are a supporting signal. Recent Teams focus is still required.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("Positive phrases")
          .font(.caption)
        PhraseListEditor(
          phrases: $preferences.value.positiveWindowTitlePhrases,
          placeholder: "Example: meeting"
        )
        Text("Negative phrases")
          .font(.caption)
        PhraseListEditor(
          phrases: $preferences.value.negativeWindowTitlePhrases,
          placeholder: "Example: settings"
        )
      }
    }
    .formStyle(.grouped)
  }

  private var diagnosticsTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle("Keep local diagnostics", isOn: $preferences.value.diagnosticsEnabled)
      Text(
        "Logs expire after seven days. They contain trigger decisions and application identifiers, but no audio, attendee names, event titles, or transcripts."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      List(diagnostics.recentRecords.suffix(100).reversed()) { record in
        VStack(alignment: .leading, spacing: 3) {
          HStack {
            Text(record.decision)
              .font(.system(.body, design: .monospaced))
            Spacer()
            Text(record.timestamp, style: .time)
              .foregroundStyle(.secondary)
          }
          Text(
            [record.trigger, record.bundleID, record.detail].compactMap { $0 }.joined(
              separator: " • ")
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        }
      }

      HStack {
        Button("Export diagnostics") {
          if let url = diagnostics.exportURL() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
          }
        }
        .disabled(diagnostics.exportURL() == nil)
        Button("Delete diagnostics", role: .destructive) {
          diagnostics.deleteAll()
        }
        Spacer()
      }
    }
    .padding()
  }

  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { preferences.value.launchAtLogin },
      set: { enabled in
        do {
          try LaunchAtLoginService.setEnabled(enabled)
          preferences.value.launchAtLogin = enabled
          launchAtLoginError = nil
        } catch {
          launchAtLoginError = error.localizedDescription
        }
      }
    )
  }

  private func calendarSelectionBinding(_ id: String) -> Binding<Bool> {
    Binding(
      get: { preferences.value.selectedCalendarIDs.contains(id) },
      set: { selected in
        if selected {
          preferences.value.selectedCalendarIDs.insert(id)
        } else {
          preferences.value.selectedCalendarIDs.remove(id)
        }
      }
    )
  }

  private func snoozeDurationBinding(_ index: Int) -> Binding<Int> {
    Binding(
      get: {
        guard preferences.value.snoozeDurationsMinutes.indices.contains(index) else {
          return index == 0 ? 5 : 15
        }
        return preferences.value.snoozeDurationsMinutes[index]
      },
      set: { value in
        while preferences.value.snoozeDurationsMinutes.count <= index {
          preferences.value.snoozeDurationsMinutes.append(index == 0 ? 5 : 15)
        }
        preferences.value.snoozeDurationsMinutes[index] = value
      }
    )
  }

  private func chooseIgnoredApplication() {
    let panel = NSOpenPanel()
    panel.title = "Choose an application to ignore"
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    guard panel.runModal() == .OK,
      let url = panel.url,
      let bundleID = Bundle(url: url)?.bundleIdentifier
    else { return }
    preferences.value.ignoredBundleIDs.insert(bundleID)
  }

  private func chooseTranscriptApplication() {
    let panel = NSOpenPanel()
    panel.title = "Choose your transcription application"
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    guard panel.runModal() == .OK,
      let url = panel.url,
      let bundle = Bundle(url: url),
      let bundleID = bundle.bundleIdentifier
    else { return }
    preferences.value.transcriptAppBundleID = bundleID
    preferences.value.transcriptAppName =
      bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? url.deletingPathExtension().lastPathComponent
  }

  private func checkRecordingButton() {
    isTestingAutomation = true
    automationTestStatus = nil
    Task {
      do {
        automationTestStatus = try await environment.transcriptAppController.checkRecordingButton()
      } catch {
        automationTestStatus = error.localizedDescription
      }
      isTestingAutomation = false
      bringSettingsToFront()
    }
  }

  private func bringSettingsToFront() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    let settingsWindow = NSApplication.shared.windows.first {
      $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
    }
    settingsWindow?.makeKeyAndOrderFront(nil)
    settingsWindow?.orderFrontRegardless()
  }
}

private struct PhraseListEditor: View {
  @Binding var phrases: [String]
  let placeholder: String
  @State private var newPhrase = ""

  var body: some View {
    ForEach(Array(phrases.enumerated()), id: \.offset) { index, phrase in
      HStack {
        Text(phrase)
        Spacer()
        Button("Remove") { phrases.remove(at: index) }
      }
    }
    HStack {
      TextField(placeholder, text: $newPhrase)
        .onSubmit(addPhrase)
      Button("Add", action: addPhrase)
        .disabled(newPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  private func addPhrase() {
    let value = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    phrases.append(value)
    newPhrase = ""
  }
}
