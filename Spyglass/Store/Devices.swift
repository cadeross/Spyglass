import AVFoundation
import Observation

/// The cameras and microphones plugged in right now, kept current as they come and go.
@Observable
final class Devices {
    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
    }

    private(set) var cameras: [Device] = []
    private(set) var microphones: [Device] = []

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func refresh() {
        cameras = Self.cameraDiscovery().devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
        microphones = Self.microphoneDiscovery().devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    func cameraName(for id: String?) -> String {
        cameras.first { $0.id == id }?.name ?? cameras.first?.name ?? "No camera"
    }

    func microphoneName(for id: String?) -> String {
        microphones.first { $0.id == id }?.name ?? Devices.defaultMicrophone()?.localizedName ?? "No microphone"
    }

    nonisolated static func cameraDiscovery() -> AVCaptureDevice.DiscoverySession {
        .init(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified)
    }

    nonisolated static func microphoneDiscovery() -> AVCaptureDevice.DiscoverySession {
        .init(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
    }

    /// The chosen camera if it's still connected, otherwise the system's pick.
    nonisolated static func camera(_ id: String?) -> AVCaptureDevice? {
        id.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .video) ?? cameraDiscovery().devices.first
    }

    nonisolated static func microphone(_ id: String?) -> AVCaptureDevice? {
        id.flatMap { AVCaptureDevice(uniqueID: $0) } ?? defaultMicrophone()
    }

    nonisolated static func defaultMicrophone() -> AVCaptureDevice? {
        AVCaptureDevice.default(for: .audio)
    }
}
