import AppKit
import AVFoundation
import Observation

/// The recordings folder: what's in it, newest first, with thumbnails loaded lazily.
@Observable
final class Library {
    private(set) var recordings: [Recording] = []
    private(set) var thumbnails: [URL: NSImage] = [:]

    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        refresh()
    }

    var folder: URL { preferences.folder }

    func ensureFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func refresh() {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []
        let known = Dictionary(uniqueKeysWithValues: recordings.map { ($0.url, $0) })
        recordings = urls
            .filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return Recording(url: url, date: date, duration: known[url]?.duration)
            }
            .sorted { $0.date > $1.date }
        thumbnails = thumbnails.filter { url, _ in recordings.contains { $0.url == url } }
        for recording in recordings.prefix(12) where recording.duration == nil || thumbnails[recording.url] == nil {
            Task { await loadDetails(for: recording.url) }
        }
    }

    /// The file name for a new recording, e.g. "Spyglass 2026-10-28 at 14.32.mp4", never clobbering one.
    func newRecordingURL(extension ext: String = "mp4") -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm"
        let base = "Spyglass \(formatter.string(from: .now))"
        return uniqueURL(named: base, extension: ext)
    }

    /// Renames the file, returning where it ended up (the name gets a number if it's taken).
    @discardableResult
    func rename(_ url: URL, to name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !trimmed.isEmpty, trimmed != url.deletingPathExtension().lastPathComponent else { return nil }
        let target = uniqueURL(named: trimmed, extension: url.pathExtension)
        defer { refresh() }
        do {
            try FileManager.default.moveItem(at: url, to: target)
            if let thumbnail = thumbnails.removeValue(forKey: url) { thumbnails[target] = thumbnail }
            return target
        } catch {
            NSSound.beep()
            return nil
        }
    }

    func trash(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        refresh()
    }

    /// Forget the cached thumbnail and duration, after the file has been rewritten (say, trimmed).
    func invalidate(_ url: URL) {
        thumbnails[url] = nil
        if let index = recordings.firstIndex(where: { $0.url == url }) { recordings[index].duration = nil }
        refresh()
    }

    private func uniqueURL(named base: String, extension ext: String) -> URL {
        var candidate = folder.appending(path: "\(base).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(base) (\(counter)).\(ext)")
            counter += 1
        }
        return candidate
    }

    private func loadDetails(for url: URL) async {
        let asset = AVURLAsset(url: url)
        if let duration = try? await asset.load(.duration),
           let index = recordings.firstIndex(where: { $0.url == url }) {
            recordings[index].duration = duration.seconds
        }
        guard thumbnails[url] == nil else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        if let image = try? await generator.image(at: time).image {
            thumbnails[url] = NSImage(cgImage: image, size: .zero)
        }
    }
}
