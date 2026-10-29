import AppKit

/// Full-screen overlays for choosing what to record: click a window, or drag out an area.
final class TargetPicker {
    enum Mode { case window, area }

    struct WindowCandidate {
        let id: CGWindowID
        /// Cocoa global coordinates.
        let frame: CGRect
        let name: String
    }

    private var overlays: [PickerWindow] = []
    private var continuation: CheckedContinuation<CaptureTarget?, Never>?
    private(set) var mode: Mode = .window
    private(set) var candidates: [WindowCandidate] = []

    var highlighted: WindowCandidate? { didSet { redraw() } }
    var selection: CGRect? { didSet { redraw() } }

    func pick(_ mode: Mode) async -> CaptureTarget? {
        self.mode = mode
        candidates = mode == .window ? Self.windowsFrontToBack() : []
        highlighted = nil
        selection = nil
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            for screen in NSScreen.screens {
                let window = PickerWindow(screen: screen, picker: self)
                window.orderFrontRegardless()
                overlays.append(window)
            }
            NSApp.activate()
            (overlays.first { $0.screen == NSScreen.underMouse } ?? overlays.first)?.makeKey()
            hover(at: NSEvent.mouseLocation)
        }
    }

    func hover(at point: CGPoint) {
        guard mode == .window else { return }
        let hit = candidates.first { $0.frame.contains(point) }
        if hit?.id != highlighted?.id { highlighted = hit }
    }

    func finish(_ target: CaptureTarget?) {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        continuation?.resume(returning: target)
        continuation = nil
    }

    func chooseHighlighted() {
        guard let window = highlighted else { return }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.underMouse
        guard let display = screen?.displayID else { return }
        finish(.window(window.id, frame: window.frame, display: display))
    }

    func chooseSelection(on screen: NSScreen) {
        guard let rect = selection?.integral, rect.width >= 40, rect.height >= 40, let display = screen.displayID else {
            selection = nil
            return
        }
        finish(.area(rect, display: display))
    }

    private func redraw() {
        overlays.forEach { $0.contentView?.needsDisplay = true }
    }

    /// Normal app windows on screen, frontmost first, leaving out Spyglass's own.
    private static func windowsFrontToBack() -> [WindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return info.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowOwnerPID as String] as? pid_t) != me,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width >= 60, rect.height >= 40 else { return nil }
            let owner = entry[kCGWindowOwnerName as String] as? String ?? "Window"
            let title = entry[kCGWindowName as String] as? String ?? ""
            return WindowCandidate(id: id, frame: rect.flippedToOtherGlobalSpace, name: title.isEmpty ? owner : "\(owner) — \(title)")
        }
    }
}

private final class PickerWindow: NSWindow {
    init(screen: NSScreen, picker: TargetPicker) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setFrame(screen.frame, display: false)
        contentView = PickerView(picker: picker, screen: screen)
    }

    override var canBecomeKey: Bool { true }
}

private final class PickerView: NSView {
    private let picker: TargetPicker
    private let pickerScreen: NSScreen
    private var dragStart: CGPoint?

    init(picker: TargetPicker, screen: NSScreen) {
        self.picker = picker
        self.pickerScreen = screen
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: picker.mode == .area ? .crosshair : .pointingHand)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { picker.finish(nil) } else { super.keyDown(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        picker.hover(at: NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {
        switch picker.mode {
        case .window: picker.chooseHighlighted()
        case .area: dragStart = clamped(NSEvent.mouseLocation)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard picker.mode == .area, let dragStart else { return }
        let point = clamped(NSEvent.mouseLocation)
        picker.selection = CGRect(
            x: min(dragStart.x, point.x), y: min(dragStart.y, point.y),
            width: abs(point.x - dragStart.x), height: abs(point.y - dragStart.y)
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard picker.mode == .area, dragStart != nil else { return }
        dragStart = nil
        picker.chooseSelection(on: pickerScreen)
    }

    override func rightMouseDown(with event: NSEvent) {
        picker.finish(nil)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        let frame = pickerScreen.frame
        return CGPoint(x: min(max(point.x, frame.minX), frame.maxX), y: min(max(point.y, frame.minY), frame.maxY))
    }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -pickerScreen.frame.minX, dy: -pickerScreen.frame.minY)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        let focus: CGRect?
        let label: String?
        switch picker.mode {
        case .window:
            focus = picker.highlighted.map { local($0.frame) }
            label = picker.highlighted?.name
        case .area:
            focus = picker.selection.map(local)
            label = picker.selection.map { "\(Int($0.width)) × \(Int($0.height))" }
        }

        if let focus, focus.intersects(bounds) {
            NSColor.clear.setFill()
            focus.fill(using: .copy)
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(roundedRect: focus.insetBy(dx: 1.5, dy: 1.5), xRadius: 8, yRadius: 8)
            outline.lineWidth = 3
            outline.stroke()
            if let label {
                drawBadge(label, centeredAt: CGPoint(x: focus.midX, y: min(focus.maxY - 26, bounds.maxY - 80)))
            }
        }

        let hint = picker.mode == .window
            ? "Click a window to record it  ·  Esc to cancel"
            : "Drag to choose an area  ·  Esc to cancel"
        drawBadge(hint, centeredAt: CGPoint(x: bounds.midX, y: bounds.maxY - 56))
    }

    private func drawBadge(_ text: String, centeredAt center: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let box = CGRect(x: center.x - size.width / 2 - 14, y: center.y - size.height / 2 - 7, width: size.width + 28, height: size.height + 14)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        string.draw(at: CGPoint(x: box.minX + 14, y: box.minY + 7))
    }
}
