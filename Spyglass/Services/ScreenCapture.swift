import AVFoundation
@preconcurrency import ScreenCaptureKit

/// One ScreenCaptureKit stream writing straight to a movie file, with optional system audio and mic.
nonisolated final class ScreenCapture: NSObject, SCStreamDelegate, SCStreamOutput, SCRecordingOutputDelegate, @unchecked Sendable {
    struct Settings {
        var filter: SCContentFilter
        var sourceRect: CGRect?
        var pointSize: CGSize
        var scale: CGFloat
        var quality: OutputQuality
        var systemAudio: Bool
        var microphoneID: String?
    }

    enum CaptureError: LocalizedError {
        case stoppedUnexpectedly

        var errorDescription: String? { "The recording stopped before it could be saved." }
    }

    /// Called on the main actor if the system ends the stream, e.g. from the menu bar's screen-sharing indicator.
    var onInterrupted: (@MainActor (Error?) -> Void)?

    private var stream: SCStream?
    private var finished: CheckedContinuation<Void, Error>?
    private let lock = NSLock()
    private let samples = DispatchQueue(label: "Spyglass.capture")

    func start(_ settings: Settings, writingTo url: URL) async throws {
        let config = SCStreamConfiguration()
        let pixels = settings.quality.pixelSize(forPoints: settings.pointSize, scale: settings.scale)
        config.width = pixels.width
        config.height = pixels.height
        if let rect = settings.sourceRect { config.sourceRect = rect }
        config.minimumFrameInterval = CMTime(value: 1, timescale: settings.quality.framesPerSecond)
        config.queueDepth = 6
        config.showsCursor = true
        config.scalesToFit = true
        config.capturesAudio = settings.systemAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        if let mic = settings.microphoneID {
            config.captureMicrophone = true
            config.microphoneCaptureDeviceID = mic
        }

        let output = SCRecordingOutputConfiguration()
        output.outputURL = url
        output.outputFileType = .mp4
        let codec: AVVideoCodecType = settings.quality == .hevcNative ? .hevc : .h264
        output.videoCodecType = output.availableVideoCodecTypes.contains(codec) ? codec : .h264

        let stream = SCStream(filter: settings.filter, configuration: config, delegate: self)
        // The recording output does the writing; this no-op output just keeps the stream fed.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: samples)
        try stream.addRecordingOutput(SCRecordingOutput(configuration: output, delegate: self))
        try await stream.startCapture()
        self.stream = stream
    }

    /// Stops the stream and waits until the movie file is finalized.
    func stop() async throws {
        guard let stream else { return }
        self.stream = nil
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock { finished = continuation }
            stream.stopCapture { [weak self] error in
                if let error { self?.resume(throwing: error) }
            }
            // Belt and braces: if the file-finished callback never arrives, don't hang forever.
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) { [weak self] in self?.resume() }
        }
    }

    private func resume(throwing error: Error? = nil) {
        let continuation = lock.withLock {
            defer { finished = nil }
            return finished
        }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }

    // MARK: SCRecordingOutputDelegate

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        resume()
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        resume(throwing: error)
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let isOurs = self.stream === stream
        self.stream = nil
        resume(throwing: error)
        guard isOurs, let onInterrupted else { return }
        Task { @MainActor in onInterrupted(error) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}
}
