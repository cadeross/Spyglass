import AppKit
import SwiftUI

/// The little glass bar that floats over everything while you record. It's left out of the video.
final class ControlPill {
    private var panel: NSPanel?

    var windowID: CGWindowID? { panel.map { CGWindowID($0.windowNumber) } }

    /// Creates the panel off screen, so its window can be excluded from the capture before anyone sees it.
    func prepare(recorder: Recorder) {
        guard panel == nil else { return }
        let panel = FloatingPanel(level: .statusBar) { PillView(recorder: recorder) }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func show(on screen: NSScreen?) {
        guard let panel else { return }
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.center(at: CGPoint(x: visible.midX, y: visible.minY + 44), on: screen)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct PillView: View {
    let recorder: Recorder

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                RecordingDot(isLive: recorder.isRecording)
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text(Recording.durationText(recorder.elapsed))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .leading)
                }
            }
            .padding(.leading, 4)
            .contentShape(.rect)
            .dragsWindow()
            .help("Drag to move")

            Divider().frame(height: 18)

            PillButton(symbol: "arrow.counterclockwise", help: "Start over") { Task { await recorder.restart() } }
            PillButton(symbol: "trash", help: "Discard") { Task { await recorder.discard() } }

            Button {
                Task { await recorder.stop() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 2)
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .controlSize(.regular)
            .help("Stop and save (\(recorder.preferences.toggleShortcut.displayString))")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .padding(16)
        .disabled(!recorder.isRecording)
    }
}

private struct PillButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(help)
    }
}

struct RecordingDot: View {
    var isLive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .background {
                Circle()
                    .fill(.red.opacity(0.45))
                    .scaleEffect(pulsing ? 2.2 : 1)
                    .opacity(pulsing ? 0 : 1)
            }
            .opacity(isLive ? 1 : 0.4)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulsing = true }
            }
    }
}
