import AppKit
import AVKit
import Observation
import SwiftUI

/// The window that opens after a recording: watch it back, trim the ends, rename, share.
final class ReviewWindow: NSObject, NSWindowDelegate {
    private static var open: [URL: ReviewWindow] = [:]

    private let window: NSWindow
    private let model: ReviewModel

    static func show(_ url: URL, library: Library) {
        if let existing = open[url] {
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let review = ReviewWindow(url: url, library: library)
        open[url] = review
        review.window.center()
        review.window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private init(url: URL, library: Library) {
        model = ReviewModel(url: url, library: library)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 380)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ReviewView(model: model) { [weak self] in self?.window.close() })
        model.onRename = { [weak self] old, new in
            guard let self else { return }
            Self.open[old] = nil
            Self.open[new] = self
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.player.pause()
        Self.open[model.url] = nil
    }
}

@Observable
final class ReviewModel {
    private(set) var url: URL
    var name: String
    private(set) var isTrimming = false
    private(set) var status: String? = "Copied to clipboard"

    let player: AVPlayer
    @ObservationIgnored let playerView = AVPlayerView()
    @ObservationIgnored var onRename: ((URL, URL) -> Void)?
    private let library: Library

    init(url: URL, library: Library) {
        self.url = url
        self.library = library
        name = url.deletingPathExtension().lastPathComponent
        player = AVPlayer(url: url)
        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.showsSharingServiceButton = true
        playerView.allowsPictureInPicturePlayback = true
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if status == "Copied to clipboard" { withAnimation { status = nil } }
        }
    }

    func copy() {
        FileActions.copy(url)
        flash("Copied to clipboard")
    }

    func commitName() {
        let old = url
        let time = player.currentTime()
        guard let renamed = library.rename(old, to: name) else {
            name = old.deletingPathExtension().lastPathComponent
            return
        }
        url = renamed
        name = renamed.deletingPathExtension().lastPathComponent
        reload(seekingTo: time)
        onRename?(old, renamed)
        flash("Renamed")
    }

    func beginTrimming() {
        guard playerView.canBeginTrimming else { return }
        player.pause()
        playerView.beginTrimming { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, result == .okButton, let item = self.player.currentItem else { return }
                let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
                let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : item.duration
                Task { await self.trim(CMTimeRange(start: start, end: end)) }
            }
        }
    }

    private func trim(_ range: CMTimeRange) async {
        withAnimation { isTrimming = true; status = "Trimming…" }
        player.replaceCurrentItem(with: nil)
        do {
            try await MovieFinisher.trim(url, to: range)
            library.invalidate(url)
            FileActions.copy(url)
            reload(seekingTo: .zero)
            withAnimation { isTrimming = false }
            flash("Trimmed and copied")
        } catch {
            reload(seekingTo: .zero)
            withAnimation { isTrimming = false }
            flash("Couldn't trim: \(error.localizedDescription)")
        }
    }

    func reveal() { FileActions.reveal(url) }

    func trash() {
        player.pause()
        library.trash(url)
    }

    private func reload(seekingTo time: CMTime) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.seek(to: time)
    }

    private func flash(_ message: String) {
        withAnimation(.snappy) { status = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if status == message { withAnimation(.smooth) { status = nil } }
        }
    }
}

private struct ReviewView: View {
    @Bindable var model: ReviewModel
    let close: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PlayerViewHost(playerView: model.playerView)
                .overlay {
                    if model.isTrimming {
                        ProgressView().controlSize(.large)
                    }
                }

            HStack(spacing: 10) {
                TextField("Name", text: $model.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .focused($nameFocused)
                    .onSubmit { model.commitName() }
                    .onChange(of: nameFocused) { _, focused in if !focused { model.commitName() } }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                    .frame(maxWidth: 300)

                if let status = model.status {
                    Text(status)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                        .transition(.blurReplace)
                }

                Spacer(minLength: 8)

                GlassEffectContainer {
                    HStack(spacing: 8) {
                        Button("Trim", systemImage: "scissors", action: model.beginTrimming)
                            .help("Trim the start and end")
                        Button("Copy", systemImage: "doc.on.doc", action: model.copy)
                            .help("Copy the video to the clipboard")
                        Button("Show in Finder", systemImage: "folder", action: model.reveal)
                            .labelStyle(.iconOnly)
                            .help("Show in Finder")
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            model.trash()
                            close()
                        }
                        .labelStyle(.iconOnly)
                        .help("Move to Trash")
                    }
                    .buttonStyle(.glass)
                }
                .disabled(model.isTrimming)

                Button("Done", action: close)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(14)
        }
        .background(.background)
        .ignoresSafeArea(edges: .top)
    }
}

private struct PlayerViewHost: NSViewRepresentable {
    let playerView: AVPlayerView

    func makeNSView(context: Context) -> AVPlayerView { playerView }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
