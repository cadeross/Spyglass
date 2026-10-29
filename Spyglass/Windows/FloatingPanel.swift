import AppKit
import SwiftUI

/// A borderless, see-through panel that floats over everything without stealing focus:
/// the home for the camera bubble, the control pill and the countdown.
final class FloatingPanel<Content: View>: NSPanel {
    init(level: NSWindow.Level = .floating, @ViewBuilder content: () -> Content) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = FirstMouseHostingView(rootView: content())
        // Measure first: with sizing options off, the hosting view reports a fitting size of zero.
        let size = host.fittingSize
        host.sizingOptions = []
        contentView = host
        setContentSize(size)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var screenCaptureID: CGWindowID { CGWindowID(windowNumber) }
}

extension NSWindow {
    /// Places the window's center at `point`, nudged so it stays on `screen`.
    func center(at point: CGPoint, on screen: NSScreen?) {
        var frame = NSRect(origin: .zero, size: frame.size)
        frame.origin = CGPoint(x: point.x - frame.width / 2, y: point.y - frame.height / 2)
        if let visible = screen?.frame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        setFrameOrigin(frame.origin)
    }
}

/// Lets the first click on a floating panel press its button, instead of only waking the window up.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension View {
    /// Drags the hosting window around with the mouse.
    func dragsWindow() -> some View {
        modifier(WindowDragModifier())
    }
}

private struct WindowDragModifier: ViewModifier {
    @State private var window: NSWindow?
    @State private var start: (mouse: CGPoint, origin: CGPoint)?

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window = $0 })
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { _ in
                        guard let window else { return }
                        let mouse = NSEvent.mouseLocation
                        if start == nil { start = (mouse, window.frame.origin) }
                        guard let start else { return }
                        window.setFrameOrigin(CGPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
                    }
                    .onEnded { _ in start = nil }
            )
    }
}

/// Hands back the NSWindow a SwiftUI view lives in.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReaderView { ReaderView(onWindow: onWindow) }
    func updateNSView(_ nsView: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        let onWindow: (NSWindow?) -> Void

        init(onWindow: @escaping (NSWindow?) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow(window)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func with(displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }

    /// The screen under the mouse pointer.
    static var underMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }

    /// Converts a rect in Cocoa global coordinates (bottom-left origin) to this display's
    /// top-left-origin point space, which is what ScreenCaptureKit's `sourceRect` uses.
    func displayLocal(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX - frame.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

extension CGRect {
    /// Flips between Cocoa global coordinates and Core Graphics global coordinates (top-left of the main display).
    var flippedToOtherGlobalSpace: CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: minX, y: height - maxY, width: width, height: self.height)
    }
}
