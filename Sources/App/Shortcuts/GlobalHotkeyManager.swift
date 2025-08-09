import Foundation
import AppKit
import Carbon

/// Singleton responsible for registering and managing a single global hotkey.
///
/// The registration uses Carbon's `RegisterEventHotKey` API to bind a key code and
/// modifier mask to a callback.  If another application has already registered
/// the same hotkey the registration will silently fail and the previous hotkey
/// will remain in effect.  Errors are logged via `Logger` when available.
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    private init() {
        // Install a Carbon event handler for hot key presses
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) in
            var hkID = EventHotKeyID()
            GetEventParameter(theEvent,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hkID)
            // Only respond to our specific signature
            if hkID.signature == GlobalHotkeyManager.signature {
                FrontmostResolver.processFrontmost()
            }
            return noErr
        }, 1, &eventSpec, nil, &eventHandler)
    }

    /// Four character code used to identify our hot key when the handler fires.
    private static let signature: OSType = {
        let string = "MOCR" as NSString
        return OSType(string.character(at: 0)) << 24 |
               OSType(string.character(at: 1)) << 16 |
               OSType(string.character(at: 2)) << 8  |
               OSType(string.character(at: 3))
    }()

    /// Register a new hot key.  Any previously registered hot key is unregistered.  If the
    /// registration fails (for example due to a conflict with another application) the
    /// failure is logged via `Logger`.  `defaultKey` is the virtual key code and
    /// `modifiers` is a Carbon modifier mask (e.g. cmd = 1<<8, shift = 1<<17).
    func register(defaultKey: UInt32, modifiers: UInt32) {
        // Unregister the previous hotkey if present
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        // This identifier never changes; declare it as a constant to silence the
        // "never mutated" warning emitted by the compiler.
        let hotKeyID = EventHotKeyID(signature: GlobalHotkeyManager.signature, id: 1)
        let status = RegisterEventHotKey(defaultKey, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            Logger.shared.error("Failed to register global hotkey: status \(status)")
        }
    }
}