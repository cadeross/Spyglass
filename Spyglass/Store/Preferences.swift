import Foundation
import Observation

/// Everything the user picks, remembered between launches.
@Observable
final class Preferences {
    var mode: CaptureMode { didSet { save(mode, for: "mode") } }
    var scope: CaptureScope { didSet { save(scope, for: "scope") } }
    /// `AVCaptureDevice.uniqueID`, or nil for the system default.
    var cameraID: String? { didSet { save(cameraID, for: "cameraID") } }
    var microphoneID: String? { didSet { save(microphoneID, for: "microphoneID") } }
    var recordsMicrophone: Bool { didSet { save(recordsMicrophone, for: "recordsMicrophone") } }
    var recordsSystemAudio: Bool { didSet { save(recordsSystemAudio, for: "recordsSystemAudio") } }
    var quality: OutputQuality { didSet { save(quality, for: "quality") } }
    var bubbleSize: BubbleSize { didSet { save(bubbleSize, for: "bubbleSize") } }
    var countsDown: Bool { didSet { save(countsDown, for: "countsDown") } }
    var folder: URL { didSet { save(folder.path, for: "folder") } }
    var toggleShortcut: Shortcut { didSet { save(toggleShortcut, for: "toggleShortcut") } }
    var discardShortcut: Shortcut { didSet { save(discardShortcut, for: "discardShortcut") } }

    static let defaultFolder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Movies", directoryHint: .isDirectory)
        .appending(path: "Spyglass", directoryHint: .isDirectory)

    /// Preview mode (used for screenshots) never writes.
    private let persists = !UserDefaults.standard.bool(forKey: "SpyglassPreview")
    private let defaults = UserDefaults.standard

    init() {
        func load<T: Decodable>(_ key: String, _ fallback: T) -> T {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
            return value
        }
        mode = load("mode", .screenAndCamera)
        scope = load("scope", .display)
        cameraID = load("cameraID", nil)
        microphoneID = load("microphoneID", nil)
        recordsMicrophone = load("recordsMicrophone", true)
        recordsSystemAudio = load("recordsSystemAudio", false)
        quality = load("quality", .h264HD)
        bubbleSize = load("bubbleSize", .medium)
        countsDown = load("countsDown", true)
        folder = load("folder", String?.none).map { URL(filePath: $0, directoryHint: .isDirectory) } ?? Self.defaultFolder
        toggleShortcut = load("toggleShortcut", .toggleDefault)
        discardShortcut = load("discardShortcut", .discardDefault)
    }

    private func save<T: Encodable>(_ value: T, for key: String) {
        guard persists, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
