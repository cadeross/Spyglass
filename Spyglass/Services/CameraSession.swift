import AVFoundation

/// The camera feed behind the bubble, and in camera-only mode the recorder too.
/// All session work happens on a private queue, as AVFoundation asks.
nonisolated final class CameraSession: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "Spyglass.camera")
    private var cameraInput: AVCaptureDeviceInput?
    private var microphoneInput: AVCaptureDeviceInput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var finished: CheckedContinuation<Void, Error>?

    /// Starts (or reconfigures) the session. With `recording` it can also record a movie, with sound when `microphone` is on.
    func start(cameraID: String?, recording: Bool, microphone: Bool, microphoneID: String?, quality: OutputQuality) async {
        await perform { [self] in
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            if let input = cameraInput { session.removeInput(input) }
            if let input = microphoneInput { session.removeInput(input) }
            if let output = movieOutput { session.removeOutput(output) }
            cameraInput = nil
            microphoneInput = nil
            movieOutput = nil

            let preset: AVCaptureSession.Preset = quality == .h264HD && session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
            session.sessionPreset = preset

            if let camera = Devices.camera(cameraID), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) {
                session.addInput(input)
                cameraInput = input
            }
            guard recording else { return }
            if microphone, let mic = Devices.microphone(microphoneID),
               let input = try? AVCaptureDeviceInput(device: mic), session.canAddInput(input) {
                session.addInput(input)
                microphoneInput = input
            }
            let output = AVCaptureMovieFileOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                movieOutput = output
                if let connection = output.connection(with: .video) {
                    // Match the mirrored preview, so the video looks the way it did on screen.
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = true
                    }
                    let codec: AVVideoCodecType = quality == .hevcNative ? .hevc : .h264
                    output.setOutputSettings([AVVideoCodecKey: codec], for: connection)
                }
            }
        }
        await perform { [self] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() async {
        await perform { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    var hasCamera: Bool { queue.sync { cameraInput != nil } }

    func startRecording(to url: URL) async {
        await perform { [self] in
            movieOutput?.startRecording(to: url, recordingDelegate: self)
        }
    }

    /// Stops recording and waits until the movie file is written.
    func stopRecording() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let output = movieOutput, output.isRecording else { return continuation.resume() }
                finished = continuation
                output.stopRecording()
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        queue.async { [self] in
            let continuation = finished
            finished = nil
            // AVFoundation reports an "error" for some clean stops; trust it only if nothing was written.
            if let error, (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
                continuation?.resume(throwing: error)
            } else {
                continuation?.resume()
            }
        }
    }

    private func perform(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                work()
                continuation.resume()
            }
        }
    }
}
