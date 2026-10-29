import AppKit
import Observation
import SwiftUI

/// A 3-2-1 in a glass circle before the recording starts.
final class CountdownOverlay {
    @Observable
    final class Model {
        var number = 3
        var cancelled = false
    }

    private var panel: NSPanel?
    private var model: Model?

    /// Counts down on `screen`, returning false if the user cancelled.
    func run(on screen: NSScreen?, from start: Int = 3) async -> Bool {
        let model = Model()
        model.number = start
        self.model = model
        let panel = FloatingPanel(level: .screenSaver) { CountdownView(model: model) }
        let frame = (screen ?? NSScreen.main)?.frame ?? .zero
        panel.center(at: CGPoint(x: frame.midX, y: frame.midY), on: screen)
        panel.orderFrontRegardless()
        self.panel = panel
        defer { cancel() }

        for number in stride(from: start, through: 1, by: -1) {
            withAnimation(.bouncy(duration: 0.35)) { model.number = number }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(100))
                if model.cancelled { return false }
            }
        }
        return true
    }

    func cancel() {
        model?.cancelled = true
        model = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct CountdownView: View {
    let model: CountdownOverlay.Model

    var body: some View {
        VStack(spacing: 14) {
            Text(verbatim: "\(model.number)")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .frame(width: 150, height: 150)
                .glassEffect(.regular, in: .circle)

            Button("Cancel") { model.cancelled = true }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(30)
    }
}
