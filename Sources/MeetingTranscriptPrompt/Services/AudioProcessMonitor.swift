import AppKit
import CoreAudio
import Foundation

struct AudioProcessMonitor {
  func processesUsingMicrophone() -> [AudioProcessSnapshot] {
    guard #available(macOS 14.2, *) else { return [] }
    return processObjectIDs().compactMap { objectID in
      guard property(objectID, selector: kAudioProcessPropertyIsRunningInput, as: UInt32.self) == 1,
        let pid = property(objectID, selector: kAudioProcessPropertyPID, as: pid_t.self),
        let app = NSRunningApplication(processIdentifier: pid)
      else {
        return nil
      }
      return AudioProcessSnapshot(
        pid: pid,
        bundleID: app.bundleIdentifier ?? "unknown.\(pid)",
        localizedName: app.localizedName ?? "Unknown application"
      )
    }
  }

  @available(macOS 14.2, *)
  private func processObjectIDs() -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var byteCount: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &byteCount
      ) == noErr
    else { return [] }

    let count = Int(byteCount) / MemoryLayout<AudioObjectID>.size
    var values = [AudioObjectID](repeating: 0, count: count)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &byteCount,
        &values
      ) == noErr
    else { return [] }
    return values
  }

  @available(macOS 14.2, *)
  private func property<T>(
    _ objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    as type: T.Type
  ) -> T? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(MemoryLayout<T>.size)
    let pointer = UnsafeMutableRawPointer.allocate(
      byteCount: MemoryLayout<T>.size,
      alignment: MemoryLayout<T>.alignment
    )
    defer { pointer.deallocate() }
    pointer.initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<T>.size)
    let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
    return status == noErr ? pointer.load(as: T.self) : nil
  }
}
