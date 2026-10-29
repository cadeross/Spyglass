import AppKit
import Observation
@preconcurrency import ScreenCaptureKit

/// Runs a recording from start to finish: permissions, picking a target, the countdown,
/// the camera bubble and control pill, capturing, and writing the final MP4.
@Observable
final class Recorder {
    enum Phase {
        case idle
        /// Asking for permissions, picking a window or area, warming up the camera.
        case preparing
        case countingDown
        case recording
        /// Writing the file.
        case finishing
    }

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0

    var isRecording: Bool { phase == .recording }
    var isIdle: Bool { phase == .idle }

    let preferences: Preferences
    let library: Library
    /// Called with each finished recording, already in the library and on the clipboard.
    @ObservationIgnored var onFinished: ((URL) -> Void)?

    @ObservationIgnored private let camera = CameraSession()
    @ObservationIgnored private let bubble = CameraBubble()
    @ObservationIgnored private let pill = ControlPill()
    @ObservationIgnored private let regionFrame = RegionFrame()
    @ObservationIgnored private let countdown = CountdownOverlay()
    @ObservationIgnored private let picker = TargetPicker()
    @ObservationIgnored private var capture: ScreenCapture?
    @ObservationIgnored private var target: CaptureTarget?
    @ObservationIgnored private var temporaryURL: URL?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(preferences: Preferences, library: Library) {
        self.preferences = preferences
        self.library = library
    }

    func registerShortcuts() {
        HotKeyCenter.shared.register(.toggleRecording, preferences.toggleShortcut) { [weak self] in self?.toggle() }
    }

    func unregisterShortcuts() {
        HotKeyCenter.shared.unregister(.toggleRecording)
        HotKeyCenter.shared.unregister(.discardRecording)
    }

    /// The one-button behavior behind the menu bar and the hotkey.
    func toggle() {
        switch phase {
        case .idle: Task { await start() }
        case .countingDown: countdown.cancel()
        case .recording: Task { await stop() }
        case .preparing, .finishing: break
        }
    }

    // MARK: - Starting

    func start() async {
        guard phase == .idle else { return }
        phase = .preparing
        let mode = preferences.mode

        if let missing = await Permissions.request(
            screen: mode.usesScreen, camera: mode.usesCamera, microphone: preferences.recordsMicrophone
        ) {
            phase = .idle
            Permissions.explainMissing(missing)
            return
        }
        if mode.usesCamera, Devices.camera(preferences.cameraID) == nil {
            phase = .idle
            present("No camera found", detail: "Plug one in, or switch to Screen only.")
            return
        }
        do {
            try library.ensureFolder()
        } catch {
            phase = .idle
            present("Couldn't create the recordings folder", detail: error.localizedDescription)
            return
        }

        let picked: CaptureTarget? = switch (mode, preferences.scope) {
        case (.camera, _): .camera
        case (_, .display): NSScreen.underMouse?.displayID.map { .display($0) }
        case (_, .window): await picker.pick(.window)
        case (_, .area): await picker.pick(.area)
        }
        guard let picked else {
            phase = .idle
            return
        }
        target = picked

        if mode.usesCamera {
            await camera.start(
                cameraID: preferences.cameraID,
                recording: mode == .camera,
                microphone: preferences.recordsMicrophone,
                microphoneID: preferences.microphoneID,
                quality: preferences.quality
            )
            if mode == .camera {
                bubble.showStage(session: camera.session, on: NSScreen.underMouse)
            } else {
                bubble.show(session: camera.session, preferences: preferences, in: region(of: picked))
            }
        }
        switch picked {
        case .window(_, let frame, _), .area(let frame, _): regionFrame.show(around: frame)
        case .display, .camera: break
        }
        await begin()
    }

    /// Counts down, then starts writing. Also used to start over.
    private func begin() async {
        guard let target else { return }
        pill.prepare(recorder: self)
        let screen = screen(of: target)
        if preferences.countsDown {
            phase = .countingDown
            guard await countdown.run(on: screen) else {
                await tearDown()
                return
            }
        }

        do {
            if case .camera = target {
                let url = temporaryFile("mov")
                temporaryURL = url
                await camera.startRecording(to: url)
            } else {
                let url = temporaryFile("mp4")
                temporaryURL = url
                try await startScreenCapture(of: target, writingTo: url)
            }
        } catch {
            await tearDown()
            present("Couldn't start recording", detail: error.localizedDescription)
            return
        }

        phase = .recording
        startedAt = .now
        elapsed = 0
        startTicking()
        pill.show(on: screen)
        HotKeyCenter.shared.register(.discardRecording, preferences.discardShortcut) { [weak self] in
            Task { await self?.discard() }
        }
    }

    private func startScreenCapture(of target: CaptureTarget, writingTo url: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let displayID = target.displayID,
              let display = content.displays.first(where: { $0.displayID == displayID }),
              let screen = NSScreen.with(displayID: displayID) else {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "That display isn't available any more."])
        }

        // The pill and the outline stay out of the video; the camera bubble stays in.
        let hidden = Set([pill.windowID, regionFrame.windowID].compactMap(\.self))
        let excluded = content.windows.filter { hidden.contains($0.windowID) }
        let bounds = CGRect(origin: .zero, size: screen.frame.size)

        let filter: SCContentFilter
        var sourceRect: CGRect?
        switch target {
        case .window(let id, let picked, _):
            let shown = Set([id, bubble.windowID].compactMap(\.self))
            filter = SCContentFilter(display: display, including: content.windows.filter { shown.contains($0.windowID) })
            let frame = content.windows.first { $0.windowID == id }?.frame.flippedToOtherGlobalSpace ?? picked
            sourceRect = screen.displayLocal(frame).intersection(bounds)
        case .area(let rect, _):
            filter = SCContentFilter(display: display, excludingWindows: excluded)
            sourceRect = screen.displayLocal(rect).intersection(bounds)
        case .display, .camera:
            filter = SCContentFilter(display: display, excludingWindows: excluded)
        }

        let capture = ScreenCapture()
        capture.onInterrupted = { [weak self] _ in
            // The system ended the stream (say, from the screen-sharing menu): keep what was recorded.
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                await self?.stop()
            }
        }
        let micID = preferences.recordsMicrophone
            ? Devices.microphone(preferences.microphoneID)?.uniqueID
            : nil
        try await capture.start(
            .init(
                filter: filter,
                sourceRect: sourceRect,
                pointSize: sourceRect?.size ?? screen.frame.size,
                scale: screen.backingScaleFactor,
                quality: preferences.quality,
                systemAudio: preferences.recordsSystemAudio,
                microphoneID: micID
            ),
            writingTo: url
        )
        self.capture = capture
    }

    // MARK: - Stopping

    func stop() async {
        guard phase == .recording else { return }
        phase = .finishing
        stopTicking()
        HotKeyCenter.shared.unregister(.discardRecording)
        pill.hide()
        regionFrame.hide()

        do {
            try await endCapture()
            bubble.hide()
            await camera.stop()
            guard let source = temporaryURL else { throw CocoaError(.fileNoSuchFile) }
            let destination = library.newRecordingURL()
            try await MovieFinisher.finish(source, to: destination)
            temporaryURL = nil
            await tearDown()
            library.refresh()
            FileActions.copy(destination)
            onFinished?(destination)
        } catch {
            await tearDown()
            present("Couldn't save the recording", detail: error.localizedDescription)
        }
    }

    func discard() async {
        guard phase == .recording || phase == .countingDown else { return }
        countdown.cancel()
        try? await endCapture()
        await tearDown()
        NSSound(named: "Pop")?.play()
    }

    /// Throws away what's been recorded and counts down again, keeping the same target.
    func restart() async {
        guard phase == .recording else { return }
        phase = .preparing
        stopTicking()
        HotKeyCenter.shared.unregister(.discardRecording)
        pill.hide()
        try? await endCapture()
        removeTemporaryFile()
        await begin()
    }

    private func endCapture() async throws {
        if case .camera = target {
            try await camera.stopRecording()
        } else {
            let capture = self.capture
            self.capture = nil
            try await capture?.stop()
        }
    }

    /// Puts everything away and goes back to idle, deleting any unsaved capture.
    private func tearDown() async {
        stopTicking()
        HotKeyCenter.shared.unregister(.discardRecording)
        countdown.cancel()
        pill.hide()
        regionFrame.hide()
        bubble.hide()
        await camera.stop()
        capture = nil
        target = nil
        removeTemporaryFile()
        phase = .idle
    }

    // MARK: - Helpers

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date.now.timeIntervalSince(startedAt)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
        startedAt = nil
    }

    private func removeTemporaryFile() {
        if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
        temporaryURL = nil
    }

    private func temporaryFile(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "Spyglass-\(UUID().uuidString).\(ext)")
    }

    private func screen(of target: CaptureTarget) -> NSScreen? {
        target.displayID.flatMap(NSScreen.with(displayID:)) ?? NSScreen.underMouse
    }

    /// Where the camera bubble starts out: the bottom-left corner of whatever's being recorded.
    private func region(of target: CaptureTarget) -> CGRect {
        switch target {
        case .window(_, let frame, _), .area(let frame, _): frame
        case .display, .camera: (screen(of: target)?.visibleFrame) ?? .zero
        }
    }

    private func present(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate()
        alert.runModal()
    }
}
