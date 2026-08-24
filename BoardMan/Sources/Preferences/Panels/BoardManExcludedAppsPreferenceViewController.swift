//
//  BoardManExcludedAppsPreferenceViewController.swift
//  Board-Man
//

import Cocoa
import UniformTypeIdentifiers

final class BoardManExcludedAppsPreferenceViewController: NSViewController {
    @IBOutlet private weak var tableView: NSTableView!

    @IBAction private func addApplications(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.prompt = String(localized: "Add")
        panel.directoryURL = applicationsDirectoryURL()

        guard panel.runModal() == .OK else { return }

        let service = AppEnvironment.current.excludeAppService
        for applicationURL in panel.urls {
            guard let bundle = Bundle(url: applicationURL),
                  let infoDictionary = bundle.infoDictionary,
                  let application = BoardManApplicationInfo(info: infoDictionary as [String: AnyObject]) else {
                continue
            }
            service.add(with: application)
        }
        tableView.reloadData()
    }

    @IBAction private func removeSelectedApplication(_ sender: Any) {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 else {
            NSSound.beep()
            return
        }

        AppEnvironment.current.excludeAppService.delete(with: selectedRow)
        tableView.reloadData()
    }

    private func applicationsDirectoryURL() -> URL {
        let paths = NSSearchPathForDirectoriesInDomains(.applicationDirectory, .localDomainMask, true)
        let path = paths.first ?? "/Applications"
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

extension BoardManExcludedAppsPreferenceViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        AppEnvironment.current.excludeAppService.applications.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        AppEnvironment.current.excludeAppService.applications[safe: row]?.name
    }
}
