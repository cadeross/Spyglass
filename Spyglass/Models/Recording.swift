import Foundation

/// A finished video in the recordings folder.
struct Recording: Identifiable, Hashable {
    let url: URL
    let date: Date
    var duration: TimeInterval?

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = total / 60 % 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
