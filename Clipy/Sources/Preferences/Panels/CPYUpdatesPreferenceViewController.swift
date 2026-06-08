//
//  CPYUpdatesPreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Combine
import Sparkle

class CPYUpdatesPreferenceViewController: NSViewController {

    // MARK: - Properties
    @IBOutlet private weak var lastUpdateCheckDateTextField: NSTextField!
    @IBOutlet private weak var versionTextField: NSTextField!

    private var updaterController: SPUStandardUpdaterController? {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return nil }
        return appDelegate.updaterController
    }
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Initialize
    override func loadView() {
        super.loadView()
        updaterController?.updater.publisher(for: \.lastUpdateCheckDate)
            .compactMap { $0 }
            .assign(to: \.objectValue, on: lastUpdateCheckDateTextField)
            .store(in: &cancellables)
        let version = Bundle.main.appVersion ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        versionTextField.stringValue = build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }

    @IBAction private func checkForUpdates(_ sender: Any) {
        guard let updaterController else {
            showUpdateFeedUnavailableMessage()
            return
        }
        guard let feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feedURLString) else {
            showUpdateFeedUnavailableMessage()
            return
        }
        var request = URLRequest(url: feedURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                guard let statusCode, (200..<300).contains(statusCode) else {
                    self.showUpdateFeedUnavailableMessage()
                    return
                }
                updaterController.checkForUpdates(sender)
            }
        }.resume()
    }

    private func showUpdateFeedUnavailableMessage() {
        let alert = NSAlert()
        alert.messageText = "Update feed is not published yet"
        alert.informativeText = "Updates will be delivered through GitHub Releases once an appcast is published."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
