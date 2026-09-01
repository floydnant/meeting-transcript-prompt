import Foundation

struct DiagnosticRecord: Codable, Identifiable, Sendable {
  let id: UUID
  let timestamp: Date
  let category: String
  let trigger: String?
  let bundleID: String?
  let eventID: String?
  let windowTitleMatched: Bool?
  let decision: String
  let detail: String?
}

@MainActor
final class DiagnosticsLogger: ObservableObject {
  @Published private(set) var recentRecords: [DiagnosticRecord] = []

  private let fileManager: FileManager
  private let directoryURL: URL
  private let fileURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
    let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    directoryURL = base.appendingPathComponent("MeetingTranscriptPrompt", isDirectory: true)
    fileURL = directoryURL.appendingPathComponent("diagnostics.jsonl")
    encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    loadRecent()
  }

  func log(
    category: String,
    trigger: DetectionTrigger? = nil,
    bundleID: String? = nil,
    eventID: String? = nil,
    windowTitleMatched: Bool? = nil,
    decision: String,
    detail: String? = nil,
    preferences: AppPreferences
  ) {
    guard preferences.diagnosticsEnabled else { return }

    let record = DiagnosticRecord(
      id: UUID(),
      timestamp: Date(),
      category: category,
      trigger: trigger?.rawValue,
      bundleID: bundleID,
      eventID: eventID,
      windowTitleMatched: windowTitleMatched,
      decision: decision,
      detail: detail
    )
    recentRecords.append(record)
    if recentRecords.count > 200 {
      recentRecords.removeFirst(recentRecords.count - 200)
    }
    append(record)
    prune(retentionDays: preferences.diagnosticsRetentionDays)
  }

  func exportURL() -> URL? {
    fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
  }

  func deleteAll() {
    try? fileManager.removeItem(at: fileURL)
    recentRecords = []
  }

  private func append(_ record: DiagnosticRecord) {
    do {
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      var data = try encoder.encode(record)
      data.append(0x0A)
      if !fileManager.fileExists(atPath: fileURL.path) {
        try data.write(to: fileURL, options: .atomic)
        return
      }
      let handle = try FileHandle(forWritingTo: fileURL)
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try handle.close()
    } catch {
      // Diagnostics must never interfere with meeting detection.
    }
  }

  private func loadRecent() {
    guard let data = try? Data(contentsOf: fileURL),
      let text = String(data: data, encoding: .utf8)
    else { return }
    recentRecords = text.split(separator: "\n").suffix(200).compactMap { line in
      try? decoder.decode(DiagnosticRecord.self, from: Data(line.utf8))
    }
  }

  private func prune(retentionDays: Int) {
    guard let data = try? Data(contentsOf: fileURL),
      let text = String(data: data, encoding: .utf8)
    else { return }

    let cutoff =
      Calendar.current.date(byAdding: .day, value: -max(1, retentionDays), to: Date())
      ?? .distantPast
    let records = text.split(separator: "\n").compactMap { line in
      try? decoder.decode(DiagnosticRecord.self, from: Data(line.utf8))
    }.filter { $0.timestamp >= cutoff }

    let rewritten = records.compactMap { record -> Data? in
      guard var encoded = try? encoder.encode(record) else { return nil }
      encoded.append(0x0A)
      return encoded
    }.reduce(into: Data()) { $0.append($1) }
    try? rewritten.write(to: fileURL, options: .atomic)
  }
}
