//
//  BoardManClipboardTypesPreferenceViewController.swift
//  Board-Man
//

import Cocoa

final class BoardManClipboardTypesPreferenceViewController: NSViewController {
    @objc dynamic var storeTypes = NSMutableDictionary()

    override func loadView() {
        storeTypes = currentStoredTypes()
        super.loadView()
    }

    private func currentStoredTypes() -> NSMutableDictionary {
        guard let values = AppEnvironment.current.defaults.object(
            forKey: Constants.UserDefaults.storeTypes
        ) as? [String: Any] else {
            return NSMutableDictionary()
        }
        return NSMutableDictionary(dictionary: values)
    }
}
