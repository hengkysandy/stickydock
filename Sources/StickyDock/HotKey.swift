import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut, registered through Carbon.
///
/// Carbon rather than `NSEvent.addGlobalMonitorForEvents` on purpose. The
/// NSEvent route requires the Accessibility permission, which grants the right
/// to observe every keystroke on the machine. `RegisterEventHotKey` asks for one
/// specific combination and needs no permission at all. For a sticky-note app
/// that is the only defensible choice.
@MainActor
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextId: UInt32 = 1
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?
    private let id: UInt32

    /// - Parameters:
    ///   - keyCode: a `kVK_` virtual key code.
    ///   - modifiers: Carbon modifier mask, e.g. `UInt32(controlKey | optionKey)`.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        id = Self.nextId
        Self.nextId += 1
        Self.handlers[id] = action

        var hotKeyId = EventHotKeyID(signature: OSType(0x53544B44), id: id)  // 'STKD'
        var created: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyId, GetApplicationEventTarget(), 0, &created
        )
        _ = hotKeyId
        guard status == noErr, let created else {
            Self.handlers[id] = nil
            return nil
        }
        ref = created
    }

    /// Not a deinit: a nonisolated deinit cannot touch the non-Sendable Carbon
    /// handle. The app registers its hot key once for its whole life anyway, so
    /// there is nothing to lose by making teardown explicit.
    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                guard status == noErr else { return status }
                // Carbon delivers hot keys on the main run loop, so this is
                // already the main actor; it just cannot be proven statically.
                MainActor.assumeIsolated { HotKey.handlers[pressed.id]?() }
                return noErr
            },
            1, &spec, nil, nil
        )
    }
}
