//
//  BoardManHotKeyRegistry.swift
//  Board-Man
//
//  Registers only shortcuts explicitly configured by the user.
//

import AppKit
import Carbon

final class HotKey: NSObject {
    let identifier: String
    let keyCombo: KeyCombo
    weak var target: NSObject?
    let action: Selector

    init(identifier: String, keyCombo: KeyCombo, target: NSObject, action: Selector) {
        self.identifier = identifier
        self.keyCombo = keyCombo
        self.target = target
        self.action = action
        super.init()
    }

    @discardableResult
    func register() -> Bool {
        HotKeyCenter.shared.register(self)
    }

    fileprivate func invoke() {
        guard let target else { return }
        if NSStringFromSelector(action).hasSuffix(":") {
            _ = target.perform(action, with: self)
        } else {
            _ = target.perform(action)
        }
    }
}

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Registration {
        let hotKey: HotKey
        let carbonRef: EventHotKeyRef
        let numericID: UInt32
    }

    private static let signature: OSType = 0x424D414E // BMAN
    private var registrations: [String: Registration] = [:]
    private var registrationsByID: [UInt32: HotKey] = [:]
    private var nextID: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?

    private init() {
        installEventHandler()
    }

    deinit {
        registrations.values.forEach { UnregisterEventHotKey($0.carbonRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    @discardableResult
    func register(_ hotKey: HotKey) -> Bool {
        unregisterHotKey(with: hotKey.identifier)
        guard !hotKey.keyCombo.doubledModifiers else { return false }

        let numericID = nextID
        nextID &+= 1
        var carbonRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: numericID)
        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCombo.currentKeyCode),
            UInt32(hotKey.keyCombo.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &carbonRef
        )
        guard status == noErr, let carbonRef else { return false }

        let registration = Registration(hotKey: hotKey, carbonRef: carbonRef, numericID: numericID)
        registrations[hotKey.identifier] = registration
        registrationsByID[numericID] = hotKey
        return true
    }

    func unregisterHotKey(with identifier: String) {
        guard let registration = registrations.removeValue(forKey: identifier) else { return }
        registrationsByID.removeValue(forKey: registration.numericID)
        UnregisterEventHotKey(registration.carbonRef)
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                center.registrationsByID[hotKeyID.id]?.invoke()
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandlerRef
        )
    }
}
