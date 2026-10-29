import AVFoundation

/// Turns raw captures into the MP4s people share.
nonisolated enum MovieFinisher {
    enum FinishError: LocalizedError {
        case failed(Error?)

        var errorDescription: String? {
            switch self {
            case .failed(let error): error?.localizedDescription ?? "The video couldn't be written."
            }
        }
    }

    /// Moves a capture into place as an MP4 with a single audio track.
    ///
    /// ScreenCaptureKit and AVCaptureMovieFileOutput write the mic and system audio as separate
    /// tracks (and the camera as a QuickTime movie). Most players outside QuickTime only play the
    /// first audio track, so the tracks are mixed down into one. Video is copied, never re-encoded.
    @concurrent
    static func finish(_ source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if audioTracks.count <= 1 && source.pathExtension.lowercased() == "mp4" {
            try FileManager.default.moveItem(at: source, to: destination)
            return
        }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        var pumps: [Pump] = []

        if let video = try await asset.loadTracks(withMediaType: .video).first {
            let output = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            let format = try await video.load(.formatDescriptions).first
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
            input.transform = try await video.load(.preferredTransform)
            input.expectsMediaDataInRealTime = false
            reader.add(output)
            writer.add(input)
            pumps.append(Pump(output: output, input: input))
        }

        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 160_000,
            ])
            input.expectsMediaDataInRealTime = false
            reader.add(output)
            writer.add(input)
            pumps.append(Pump(output: output, input: input))
        }

        guard reader.startReading(), writer.startWriting() else {
            throw FinishError.failed(reader.error ?? writer.error)
        }
        writer.startSession(atSourceTime: .zero)
        // Both tracks have to flow at once: the writer interleaves them and stalls one waiting on the other.
        await withTaskGroup(of: Void.self) { group in
            for pump in pumps { group.addTask { await pump.run() } }
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw FinishError.failed(reader.error)
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw FinishError.failed(writer.error) }
        try? FileManager.default.removeItem(at: source)
    }

    /// Re-exports `url` keeping only `range`, then swaps it in place of the original.
    @concurrent
    static func trim(_ url: URL, to range: CMTimeRange) async throws {
        let asset = AVURLAsset(url: url)
        let codec = try await asset.loadTracks(withMediaType: .video).first?.load(.formatDescriptions).first
            .map(CMFormatDescriptionGetMediaSubType)
        let preset = codec == kCMVideoCodecType_HEVC ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw FinishError.failed(nil) }
        session.timeRange = range
        session.shouldOptimizeForNetworkUse = true
        let temporary = FileManager.default.temporaryDirectory.appending(path: "Spyglass-trim-\(UUID().uuidString).mp4")
        try await session.export(to: temporary, as: .mp4)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }

    /// Copies samples from one reader output into one writer input until the track runs dry.
    private struct Pump: @unchecked Sendable {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput

        func run() async {
            let queue = DispatchQueue(label: "Spyglass.finish.\(input.mediaType.rawValue)")
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                input.requestMediaDataWhenReady(on: queue) {
                    while input.isReadyForMoreMediaData {
                        guard let sample = output.copyNextSampleBuffer(), input.append(sample) else {
                            input.markAsFinished()
                            continuation.resume()
                            return
                        }
                    }
                }
            }
        }
    }
}
