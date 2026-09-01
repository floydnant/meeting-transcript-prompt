// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "meeting-transcript-prompt",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "meeting-transcript-prompt", targets: ["MeetingTranscriptPrompt"])
  ],
  targets: [
    .executableTarget(
      name: "MeetingTranscriptPrompt",
      path: "Sources/MeetingTranscriptPrompt"
    ),
    .testTarget(
      name: "MeetingTranscriptPromptTests",
      dependencies: ["MeetingTranscriptPrompt"],
      path: "Tests/MeetingTranscriptPromptTests"
    ),
  ]
)
