import AppKit
import SwiftUI

/// Click, then press the new key combination. Esc cancels; the shortcut needs ⌘, ⌥ or ⌃.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    let fallback: Shortcut

    @Environment(Recorder.self) private var recorder
    @State private var isListening = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleListening) {
                Text(isListening ? "Type shortcut…" : shortcut.displayString)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isListening ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .frame(minWidth: 84)
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            if shortcut != fallback && !isListening {
                Button {
                    shortcut = fallback
                    recorder.registerShortcuts()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Back to \(fallback.displayString)")
            }
        }
        .onDisappear(perform: stopListening)
    }

    private func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    private func startListening() {
        // Free up the current shortcut so pressing it again can be recorded.
        recorder.unregisterShortcuts()
        isListening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopListening()
            } else if let new = Shortcut(event: event) {
                shortcut = new
                stopListening()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isListening else { return }
        isListening = false
        recorder.registerShortcuts()
    }
}
