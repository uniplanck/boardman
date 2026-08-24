//
//  BoardManUpdatesPreferenceViewController.swift
//  Board-Man
//

import Cocoa
import Combine
import Sparkle

final class BoardManUpdatesPreferenceViewController: NSViewController {
    @IBOutlet private weak var lastUpdateCheckDateTextField: NSTextField!
    @IBOutlet private weak var versionTextField: NSTextField!

    private var subscriptions = Set<AnyCancellable>()

    private var updaterController: SPUStandardUpdaterController? {
        (NSApp.delegate as? AppDelegate)?.updaterController
    }

    override func loadView() {
        super.loadView()
        bindLastUpdateCheckDate()
        updateVersionLabel()
    }

    @IBAction private func checkForUpdates(_ sender: Any) {
        guard let updaterController,
              let feedURL = updateFeedURL() else {
            presentUnavailableFeedAlert()
            return
        }

        var request = URLRequest(url: feedURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                guard let self else { return }
                guard let statusCode, (200..<300).contains(statusCode) else {
                    self.presentUnavailableFeedAlert()
                    return
                }
                updaterController.checkForUpdates(sender)
            }
        }.resume()
    }

    private func bindLastUpdateCheckDate() {
        updaterController?.updater.publisher(for: \.lastUpdateCheckDate)
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .assign(to: \.objectValue, on: lastUpdateCheckDateTextField)
            .store(in: &subscriptions)
    }

    private func updateVersionLabel() {
        let version = Bundle.main.appVersion ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        versionTextField.stringValue = build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }

    private func updateFeedURL() -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else { return nil }
        return URL(string: value)
    }

    private func presentUnavailableFeedAlert() {
        let alert = NSAlert()
        alert.messageText = "Update feed is not published yet"
        alert.informativeText = "Updates will be delivered through GitHub Releases once an appcast is published."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
