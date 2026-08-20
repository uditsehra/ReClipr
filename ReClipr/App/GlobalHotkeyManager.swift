//
//  GlobalHotkeyManager.swift
//  ReClipr
//
//  Uses Carbon RegisterEventHotKey for the global shortcut — no Input Monitoring
//  permission required. A local NSEvent monitor covers the case where the popover
//  itself is the key window (Carbon hotkeys don't fire to the active application).
//

import AppKit
import Carbon

final class GlobalHotkeyManager {
    nonisolated static let shared = GlobalHotkeyManager()
    private init() {}

    var onActivate: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?

    // MARK: - Public API

    func register(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        unregister()
        guard keyCode >= 0 else { return }

        // Install the Carbon event handler once; it persists for the app lifetime.
        if eventHandlerRef == nil { installCarbonHandler() }

        let hotKeyID = EventHotKeyID(signature: 0x52434C50, id: 1) // 'RCLP'
        RegisterEventHotKey(
            UInt32(keyCode),
            Self.carbonModifiers(from: modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        // Local monitor: handles the shortcut when the popover is key,
        // since Carbon events are not dispatched to the foreground app.
        let targetMods = modifiers.intersection(.deviceIndependentFlagsMask)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Int(event.keyCode) == keyCode,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == targetMods
            else { return event }
            self?.onActivate?()
            return nil
        }
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    // MARK: - Private

    private func installCarbonHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, _, userData) -> OSStatus in
                guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
                Unmanaged<GlobalHotkeyManager>
                    .fromOpaque(ptr)
                    .takeUnretainedValue()
                    .onActivate?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }
}
