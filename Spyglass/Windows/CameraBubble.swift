import AppKit
import AVFoundation
import SwiftUI

/// The round webcam bubble with a glass rim. It's a real window on screen, so a screen
/// recording picks it up exactly where you've dragged it.
final class CameraBubble {
    private var panel: NSPanel?

    var windowID: CGWindowID? { panel.map { CGWindowID($0.windowNumber) } }

    /// Shows the bubble in the bottom-left corner of `region` (Cocoa screen coordinates).
    func show(session: AVCaptureSession, preferences: Preferences, in region: CGRect) {
        hide()
        let panel = FloatingPanel(level: .statusBar) {
            BubbleView(session: session, preferences: preferences)
        }
        let size = panel.frame.size
        let inset: CGFloat = 20
        let origin = CGPoint(x: region.minX + inset - BubbleView.margin, y: region.minY + inset - BubbleView.margin)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Camera-only mode: a bigger, rectangular preview so you can see yourself.
    func showStage(session: AVCaptureSession, on screen: NSScreen?) {
        hide()
        let panel = FloatingPanel(level: .statusBar) {
            StageView(session: session)
        }
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.center(at: CGPoint(x: visible.midX, y: visible.midY + 40), on: screen)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct BubbleView: View {
    static let margin: CGFloat = 14

    let session: AVCaptureSession
    @Bindable var preferences: Preferences
    @State private var isHovering = false
    @State private var window: NSWindow?

    var body: some View {
        let diameter = preferences.bubbleSize.diameter
        CameraPreview(session: session)
            .frame(width: diameter, height: diameter)
            .clipShape(.circle)
            .padding(5)
            .glassEffect(.regular, in: .circle)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .overlay(alignment: .bottom) {
                if isHovering {
                    SizePicker(selection: $preferences.bubbleSize)
                        .padding(.bottom, diameter > 160 ? 14 : 6)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .contentShape(.circle)
            .dragsWindow()
            .onHover { hovering in withAnimation(.snappy(duration: 0.2)) { isHovering = hovering } }
            .padding(Self.margin)
            .background(WindowReader { window = $0 })
            .onChange(of: preferences.bubbleSize) { old, new in
                // Grow and shrink around the bubble's center rather than its corner.
                guard let window else { return }
                let delta = new.diameter - old.diameter
                var frame = window.frame
                frame.origin.x -= delta / 2
                frame.origin.y -= delta / 2
                frame.size.width += delta
                frame.size.height += delta
                window.setFrame(frame, display: true, animate: false)
            }
            .help("Drag to move")
    }
}

private struct SizePicker: View {
    @Binding var selection: BubbleSize

    var body: some View {
        HStack(spacing: 2) {
            ForEach(BubbleSize.allCases) { size in
                Button {
                    withAnimation(.bouncy) { selection = size }
                } label: {
                    Text(size.title)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .frame(width: 20, height: 20)
                        .foregroundStyle(selection == size ? .primary : .secondary)
                        .background(selection == size ? AnyShapeStyle(.white.opacity(0.25)) : AnyShapeStyle(.clear), in: .circle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
    }
}

private struct StageView: View {
    let session: AVCaptureSession

    var body: some View {
        CameraPreview(session: session)
            .frame(width: 480, height: 270)
            .clipShape(.rect(cornerRadius: 22))
            .padding(6)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .contentShape(.rect(cornerRadius: 28))
            .dragsWindow()
            .padding(16)
            .help("Drag to move")
    }
}

/// The live camera feed, mirrored like a mirror (and like FaceTime).
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        private let preview: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            preview = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            preview.videoGravity = .resizeAspectFill
            preview.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
            if let connection = preview.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            layer = preview
            wantsLayer = true
        }

        required init?(coder: NSCoder) { fatalError() }

        // Let SwiftUI handle the mouse (dragging, hover) on top of the feed.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
