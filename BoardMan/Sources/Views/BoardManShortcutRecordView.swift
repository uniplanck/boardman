//
//  BoardManShortcutRecordView.swift
//  Board-Man
//

import AppKit
import Carbon

@objc protocol RecordViewDelegate: AnyObject {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool
    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool
    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?)
    func recordViewDidEndRecording(_ recordView: RecordView)
}

final class RecordView: NSView {
    weak var delegate: RecordViewDelegate?

    var keyCombo: KeyCombo? {
        didSet { needsDisplay = true }
    }

    @objc dynamic var tintColor: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    @objc dynamic var backgroundColor: NSColor = .controlBackgroundColor { didSet { needsDisplay = true } }
    @objc dynamic var cornerRadius: CGFloat = 6 { didSet { needsDisplay = true } }
    @objc dynamic var borderColor: NSColor = .separatorColor { didSet { needsDisplay = true } }
    @objc dynamic var borderWidth: CGFloat = 1 { didSet { needsDisplay = true } }

    private var isRecordingShortcut = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard delegate?.recordViewShouldBeginRecording(self) ?? true else { return }
        isRecordingShortcut = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            return
        }
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            keyCombo = nil
            delegate?.recordView(self, didChangeKeyCombo: nil)
            finishRecording()
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let candidate = KeyCombo(QWERTYKeyCode: Int(event.keyCode), cocoaModifiers: modifiers) else {
            NSSound.beep()
            return
        }
        guard delegate?.recordView(self, canRecordKeyCombo: candidate) ?? true else { return }

        keyCombo = candidate
        delegate?.recordView(self, didChangeKeyCombo: candidate)
        finishRecording()
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted, isRecordingShortcut {
            isRecordingShortcut = false
            delegate?.recordViewDidEndRecording(self)
            needsDisplay = true
        }
        return accepted
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let outline = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        backgroundColor.setFill()
        outline.fill()
        (isRecordingShortcut ? tintColor : borderColor).setStroke()
        outline.lineWidth = max(0.5, borderWidth)
        outline.stroke()

        let text: String
        if isRecordingShortcut {
            text = "Press shortcut…"
        } else if let keyCombo {
            text = keyCombo.doubledModifiers
                ? keyCombo.keyEquivalentModifierMaskString + " ×2"
                : keyCombo.keyEquivalentModifierMaskString + keyCombo.keyEquivalent
        } else {
            text = "Not set"
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isRecordingShortcut ? tintColor : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: max(8, (bounds.width - size.width) / 2),
            y: max(0, (bounds.height - size.height) / 2)
        )
        text.draw(at: point, withAttributes: attributes)
    }

    private func finishRecording() {
        isRecordingShortcut = false
        delegate?.recordViewDidEndRecording(self)
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }
}
