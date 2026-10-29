import AppKit
import AVFoundation

/// Screen Recording, Camera and Microphone access, asked for the first time they're needed.
enum Permissions {
    enum Kind {
        case screen, camera, microphone

        var title: String {
            switch self {
            case .screen: "Screen Recording"
            case .camera: "Camera"
            case .microphone: "Microphone"
            }
        }

        var settingsAnchor: String {
            switch self {
            case .screen: "Privacy_ScreenCapture"
            case .camera: "Privacy_Camera"
            case .microphone: "Privacy_Microphone"
            }
        }
    }

    /// Returns the first permission that's missing, after asking for any that haven't been asked yet.
    static func request(screen: Bool, camera: Bool, microphone: Bool) async -> Kind? {
        if screen, !CGPreflightScreenCaptureAccess() {
            // Shows the system prompt the first time; after that it's a trip to System Settings.
            CGRequestScreenCaptureAccess()
            return .screen
        }
        if camera, !(await request(.video)) { return .camera }
        if microphone, !(await request(.audio)) { return .microphone }
        return nil
    }

    private static func request(_ media: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: media)
        default: false
        }
    }

    static func explainMissing(_ kind: Kind) {
        let alert = NSAlert()
        alert.messageText = "Spyglass needs \(kind.title) access"
        alert.informativeText = switch kind {
        case .screen: "Turn on Spyglass in System Settings › Privacy & Security › Screen & System Audio Recording, then try again. macOS may ask you to reopen Spyglass."
        case .camera: "Turn on Spyglass in System Settings › Privacy & Security › Camera, or record with Screen only."
        case .microphone: "Turn on Spyglass in System Settings › Privacy & Security › Microphone, or switch the microphone off."
        }
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsAnchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
