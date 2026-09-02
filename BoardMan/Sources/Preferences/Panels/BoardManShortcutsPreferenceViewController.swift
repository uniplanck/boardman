//
//  BoardManShortcutsPreferenceViewController.swift
//  Board-Man
//

import Cocoa

final class BoardManShortcutsPreferenceViewController: NSViewController {
    @IBOutlet private weak var mainShortcutRecordView: RecordView!
    @IBOutlet private weak var historyShortcutRecordView: RecordView!
    @IBOutlet private weak var templatesShortcutRecordView: RecordView!
    @IBOutlet private weak var clearHistoryShortcutRecordView: RecordView!

    override func loadView() {
        super.loadView()
        configureRecordViews()
        refreshShortcutValues()
    }

    private func configureRecordViews() {
        [
            mainShortcutRecordView,
            historyShortcutRecordView,
            templatesShortcutRecordView,
            clearHistoryShortcutRecordView
        ].forEach { $0?.delegate = self }
    }

    private func refreshShortcutValues() {
        let hotKeys = AppEnvironment.current.hotKeyService
        mainShortcutRecordView.keyCombo = hotKeys.mainKeyCombo
        historyShortcutRecordView.keyCombo = hotKeys.historyKeyCombo
        templatesShortcutRecordView.keyCombo = hotKeys.snippetKeyCombo
        clearHistoryShortcutRecordView.keyCombo = hotKeys.clearHistoryKeyCombo
    }
}

extension BoardManShortcutsPreferenceViewController: RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool {
        true
    }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        true
    }

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        let hotKeys = AppEnvironment.current.hotKeyService
        if recordView === mainShortcutRecordView {
            hotKeys.change(with: .main, keyCombo: keyCombo)
        } else if recordView === historyShortcutRecordView {
            hotKeys.change(with: .history, keyCombo: keyCombo)
        } else if recordView === templatesShortcutRecordView {
            hotKeys.change(with: .snippet, keyCombo: keyCombo)
        } else if recordView === clearHistoryShortcutRecordView {
            hotKeys.changeClearHistoryKeyCombo(keyCombo)
        }
    }

    func recordViewDidEndRecording(_ recordView: RecordView) {}
}
