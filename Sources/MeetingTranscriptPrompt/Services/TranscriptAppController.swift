import AppKit
import ApplicationServices
import Foundation

@MainActor
final class TranscriptAppController {
  enum AutomationError: LocalizedError {
    case appNotInstalled
    case accessibilityDenied
    case recordingButtonNotFound

    var errorDescription: String? {
      switch self {
      case .appNotInstalled: "Choose an installed transcription app in Settings."
      case .accessibilityDenied:
        "Accessibility permission is required to press the transcription app's recording button."
      case .recordingButtonNotFound:
        "The transcription app's recording button could not be found."
      }
    }
  }

  private let preferences: PreferencesStore

  init(preferences: PreferencesStore) {
    self.preferences = preferences
  }

  func open() throws {
    guard
      !preferences.value.transcriptAppBundleID.isEmpty,
      let appURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: preferences.value.transcriptAppBundleID)
    else {
      throw AutomationError.appNotInstalled
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
  }

  func openAndStartRecording() async throws {
    try open()
    guard AXIsProcessTrusted() else { throw AutomationError.accessibilityDenied }
    let button = try await waitForRecordingButton()
    guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
      throw AutomationError.recordingButtonNotFound
    }
  }

  func checkRecordingButton() async throws -> String {
    try open()
    guard AXIsProcessTrusted() else { throw AutomationError.accessibilityDenied }
    let button = try await waitForRecordingButton()
    let label = searchableText(for: button)
    return label.isEmpty ? "Record button found" : "Found: \(label)"
  }

  func requestAccessibilityPermission() -> Bool {
    AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  }

  private func waitForRecordingButton() async throws -> AXUIElement {
    for _ in 0..<20 {
      if let app = NSRunningApplication.runningApplications(
        withBundleIdentifier: preferences.value.transcriptAppBundleID
      ).first {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        if let button = findRecordingButton(in: root) {
          return button
        }
      }
      try await Task.sleep(for: .milliseconds(500))
    }
    throw AutomationError.recordingButtonNotFound
  }

  private func findRecordingButton(in root: AXUIElement) -> AXUIElement? {
    var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
    var visited: Set<CFHashCode> = []
    var index = 0

    while index < queue.count && index < 2_000 {
      let item = queue[index]
      index += 1
      guard item.depth <= 20 else { continue }
      let identity = CFHash(item.element)
      guard visited.insert(identity).inserted else { continue }

      let searchable = searchableText(for: item.element).lowercased()
      if hasPressAction(item.element), isRecordingButtonLabel(searchable) {
        return item.element
      }

      for child in children(of: item.element) {
        queue.append((child, item.depth + 1))
      }
    }
    return nil
  }

  private func isRecordingButtonLabel(_ text: String) -> Bool {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized == "record" || normalized.contains("start recording")
      || normalized.contains("start meeting") || normalized.contains("record meeting")
  }

  private func searchableText(for element: AXUIElement) -> String {
    [
      stringAttribute(kAXTitleAttribute, of: element),
      stringAttribute(kAXDescriptionAttribute, of: element),
      stringAttribute(kAXValueAttribute, of: element),
      stringAttribute(kAXHelpAttribute, of: element),
      stringAttribute(kAXIdentifierAttribute, of: element),
    ].compactMap { $0 }.joined(separator: " ")
  }

  private func hasPressAction(_ element: AXUIElement) -> Bool {
    var actions: CFArray?
    guard AXUIElementCopyActionNames(element, &actions) == .success,
      let names = actions as? [String]
    else { return false }
    return names.contains(kAXPressAction as String)
  }

  private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
      return nil
    }
    return value as? String
  }

  private func children(of element: AXUIElement) -> [AXUIElement] {
    let attributes: [String] = [
      kAXChildrenAttribute as String,
      kAXVisibleChildrenAttribute as String,
      kAXContentsAttribute as String,
    ]
    return attributes.flatMap { attribute -> [AXUIElement] in
      var value: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
        let children = value as? [AXUIElement]
      else { return [] }
      return children
    }
  }
}
