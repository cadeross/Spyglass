import AppKit
import Observation
import SwiftUI

/// Lights, camera, action: a springy 3-2-1 in a glass porthole before the recording starts.
final class CountdownOverlay {
    @Observable
    final class Model {
        var number = 3
        var stage = Stage.hidden
        var cancelled = false
    }

    enum Stage { case hidden, shown, leaving }

    private var panel: NSPanel?
    private var model: Model?

    /// Counts down on `screen`, returning false if the user cancelled. Returns only once the
    /// overlay has finished leaving, so none of it ends up in the first frames of the video.
    func run(on screen: NSScreen?, from start: Int = 3) async -> Bool {
        let model = Model()
        model.number = start
        self.model = model
        let panel = FloatingPanel(level: .screenSaver) { CountdownView(model: model) }
        let frame = (screen ?? NSScreen.main)?.frame ?? .zero
        panel.center(at: CGPoint(x: frame.midX, y: frame.midY), on: screen)
        panel.orderFrontRegardless()
        self.panel = panel

        withAnimation(.spring(duration: 0.5, bounce: 0.35)) { model.stage = .shown }

        // Ticks land on fixed deadlines, so the beat stays even however long each frame takes.
        let clock = ContinuousClock()
        let begin = clock.now
        for (index, number) in stride(from: start, through: 1, by: -1).enumerated() {
            if index > 0 {
                withAnimation(.spring(duration: 0.45, bounce: 0.45)) { model.number = number }
            }
            CountdownSounds.tick(isLast: number == 1)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            guard await wait(until: begin + .seconds(index + 1), unlessCancelled: model) else {
                await leave(model, duration: 0.15)
                return false
            }
        }
        await leave(model, duration: 0.2)
        return true
    }

    func cancel() {
        model?.cancelled = true
        model = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func wait(until deadline: ContinuousClock.Instant, unlessCancelled model: Model) async -> Bool {
        let clock = ContinuousClock()
        while clock.now < deadline {
            if model.cancelled { return false }
            try? await Task.sleep(for: min(.milliseconds(30), deadline - clock.now))
        }
        return !model.cancelled
    }

    private func leave(_ model: Model, duration: Double) async {
        withAnimation(.easeIn(duration: duration)) { model.stage = .leaving }
        try? await Task.sleep(for: .seconds(duration))
        cancel()
    }
}

private enum CountdownSounds {
    /// A soft tink on each beat and a brighter ding on the last, quiet enough not to startle.
    static func tick(isLast: Bool) {
        guard let sound = NSSound(named: isLast ? "Glass" : "Tink")?.copy() as? NSSound else { return }
        sound.volume = isLast ? 0.3 : 0.22
        sound.play()
    }
}

private struct CountdownView: View {
    let model: CountdownOverlay.Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let diameter: CGFloat = 150

    var body: some View {
        let style = BeatStyle(number: model.number)

        // The porthole sits dead center of the window (and so of the screen); the word and Cancel hang below it.
        ZStack {
            if !reduceMotion {
                Ripple(color: style.color, diameter: Self.diameter)
                    .id(model.number)
            }

            // The porthole stays put; only the number inside it is swapped on each beat.
            Color.clear
                .frame(width: Self.diameter, height: Self.diameter)
                .glassEffect(.regular.tint(style.color.opacity(0.22)), in: .circle)

            Text(verbatim: "\(model.number)")
                .font(.system(size: 80, weight: .heavy, design: .rounded))
                .foregroundStyle(style.color.gradient)
                .shadow(color: style.color.opacity(0.45), radius: 12)
                .id(model.number)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .scale(scale: 1.9).combined(with: .opacity).combined(with: .blur(radius: 14)),
                    removal: .scale(scale: 0.3).combined(with: .opacity).combined(with: .blur(radius: 8))
                ))

            SweepRing(color: style.color, diameter: Self.diameter + 16)
                .id(model.number)
        }
        .overlay {
            VStack(spacing: 12) {
                Text(style.word)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(style.color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .id(model.number)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))

                Button("Cancel") { model.cancelled = true }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
            }
            .offset(y: Self.diameter / 2 + 62)
        }
        .scaleEffect(scale)
        .opacity(model.stage == .shown ? 1 : 0)
        .blur(radius: model.stage == .shown || reduceMotion ? 0 : 10)
        // Plenty of room around the porthole so the springs and ripples never clip at the window edge.
        .frame(width: 380, height: 400)
    }

    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        return switch model.stage {
        case .hidden: 0.4
        case .shown: 1
        case .leaving: 1.35
        }
    }
}

/// The color and word for each beat: warming from sunset coral to go-green.
private struct BeatStyle {
    let color: Color
    let word: String

    init(number: Int) {
        switch number {
        case 3: (color, word) = (Color(red: 1.0, green: 0.42, blue: 0.38), "Lights")
        case 2: (color, word) = (Color(red: 1.0, green: 0.68, blue: 0.20), "Camera")
        case 1: (color, word) = (Color(red: 0.20, green: 0.80, blue: 0.55), "Action!")
        default: (color, word) = (.accentColor, "Get ready")
        }
    }
}

/// A ring that sweeps around the porthole over each one-second beat.
private struct SweepRing: View {
    let color: Color
    let diameter: CGFloat
    @State private var progress: CGFloat = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(color.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: diameter, height: diameter)
            .onAppear {
                withAnimation(.linear(duration: 1)) { progress = 1 }
            }
            .transition(.opacity)
    }
}

/// A sonar ping rolling out from the porthole on every beat.
private struct Ripple: View {
    let color: Color
    let diameter: CGFloat
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.7), lineWidth: 3)
            .frame(width: diameter, height: diameter)
            .scaleEffect(expanded ? 2.1 : 1)
            .opacity(expanded ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.9)) { expanded = true }
            }
            .transition(.identity)
            .allowsHitTesting(false)
    }
}

private extension AnyTransition {
    static func blur(radius: CGFloat) -> AnyTransition {
        .modifier(active: BlurModifier(radius: radius), identity: BlurModifier(radius: 0))
    }
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}
