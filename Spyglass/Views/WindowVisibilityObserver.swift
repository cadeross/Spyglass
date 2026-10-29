import AppKit
import SwiftUI

/// Reports whether the hosting window is key, so the panel can refresh each time it opens.
struct WindowVisibilityObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        ObserverView(onChange: onChange)
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        let onChange: (Bool) -> Void

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return onChange(false) }
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(becameKey), name: NSWindow.didBecomeKeyNotification, object: window)
            center.addObserver(self, selector: #selector(resignedKey), name: NSWindow.didResignKeyNotification, object: window)
            onChange(window.isKeyWindow)
        }

        @objc private func becameKey() { onChange(true) }
        @objc private func resignedKey() { onChange(false) }
    }
}
