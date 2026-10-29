import SwiftUI

@main
struct SpyglassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(AppModel.recorder)
                .environment(AppModel.library)
                .environment(AppModel.devices)
        } label: {
            MenuBarLabel()
                .environment(AppModel.recorder)
        }
        .menuBarExtraStyle(.window)
    }
}

enum AppModel {
    static let preferences = Preferences()
    static let library = Library(preferences: preferences)
    static let devices = Devices()
    static let recorder = Recorder(preferences: preferences, library: library)
}

private struct MenuBarLabel: View {
    @Environment(Recorder.self) private var recorder

    var body: some View {
        if recorder.isRecording {
            HStack(spacing: 4) {
                Image(nsImage: SpyglassGlyph.recordingDot)
                Text(verbatim: Recording.durationText(recorder.elapsed))
                    .monospacedDigit()
            }
            .accessibilityLabel("Spyglass, recording")
        } else {
            Image(nsImage: SpyglassGlyph.menuBarImage)
                .accessibilityLabel("Spyglass")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.recorder.registerShortcuts()
        AppModel.recorder.onFinished = { url in
            ReviewWindow.show(url, library: AppModel.library)
        }
        showPreviewIfAsked()
    }

    /// `open Spyglass.app --args -SpyglassPreview YES` shows the panel in a normal window,
    /// which is handy for screenshots. Add `-SpyglassAppearance light|dark` to force a theme.
    private func showPreviewIfAsked() {
        guard UserDefaults.standard.bool(forKey: "SpyglassPreview") else { return }
        switch UserDefaults.standard.string(forKey: "SpyglassAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        let host = NSHostingView(
            rootView: PanelView()
                .environment(AppModel.recorder)
                .environment(AppModel.library)
                .environment(AppModel.devices)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(48)
                .background(PreviewBackdrop())
        )
        let window = PreviewWindow(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        previewWindow = window
    }
}

/// Borderless windows can't become key by default; the preview should behave like the open panel.
private final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// A soft dusk-at-sea backdrop so the glass has something to refract in screenshots.
private struct PreviewBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.07, green: 0.08, blue: 0.24), Color(red: 0.03, green: 0.26, blue: 0.40)]
                    : [Color(red: 0.98, green: 0.80, blue: 0.62), Color(red: 0.40, green: 0.62, blue: 0.93)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(red: 1.0, green: 0.55, blue: 0.40).opacity(dark ? 0.3 : 0.45))
                .frame(width: 320)
                .blur(radius: 70)
                .offset(x: -130, y: 170)
            Circle()
                .fill(Color(red: 0.35, green: 0.85, blue: 0.80).opacity(dark ? 0.3 : 0.35))
                .frame(width: 260)
                .blur(radius: 70)
                .offset(x: 150, y: -180)
        }
    }
}
