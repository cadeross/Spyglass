import Carbon.HIToolbox

/// System-wide shortcuts through Carbon's hot key API, which needs no Accessibility permission.
final class HotKeyCenter {
    enum Action: UInt32 {
        case toggleRecording = 1
        case discardRecording = 2
    }

    static let shared = HotKeyCenter()

    private var registered: [Action: EventHotKeyRef] = [:]
    private var handlers: [Action: () -> Void] = [:]

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey
            )
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated {
                if let action = HotKeyCenter.Action(rawValue: hotKey.id) { HotKeyCenter.shared.handlers[action]?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(_ action: Action, _ shortcut: Shortcut, handler: @escaping () -> Void) {
        unregister(action)
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5350_5947), id: action.rawValue) // "SPYG"
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return }
        registered[action] = ref
        handlers[action] = handler
    }

    func unregister(_ action: Action) {
        if let ref = registered.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        handlers[action] = nil
    }
}
