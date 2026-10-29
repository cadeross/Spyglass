import AppKit
import SwiftUI

/// A dashed outline around the window or area being recorded. It ignores the mouse and is left out of the video.
final class RegionFrame {
    private var panel: NSPanel?

    var windowID: CGWindowID? { panel.map { CGWindowID($0.windowNumber) } }

    func show(around rect: CGRect) {
        hide()
        let inset: CGFloat = 4
        let panel = FloatingPanel(level: .statusBar) { FrameView() }
        panel.ignoresMouseEvents = true
        panel.setFrame(rect.insetBy(dx: -inset, dy: -inset), display: false)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct FrameView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(.red.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
