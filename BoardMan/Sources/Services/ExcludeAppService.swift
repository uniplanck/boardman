//
//  ExcludeAppService.swift
//  Board-Man
//

import AppKit
import Foundation
import RxCocoa
import RxSwift

final class ExcludeAppService {
    fileprivate(set) var applications: [BoardManApplicationInfo]
    fileprivate var frontApplication = BehaviorRelay<NSRunningApplication?>(value: nil)
    fileprivate var disposeBag = DisposeBag()

    init(applications: [BoardManApplicationInfo]) {
        self.applications = applications
    }

    func startMonitoring() {
        disposeBag = DisposeBag()
        NSWorkspace.shared.notificationCenter.rx
            .notification(NSWorkspace.didActivateApplicationNotification)
            .map { $0.userInfo?["NSWorkspaceApplicationKey"] as? NSRunningApplication }
            .bind(to: frontApplication)
            .disposed(by: disposeBag)
    }

    func frontProcessIsExcludedApplication() -> Bool {
        guard !applications.isEmpty,
              let identifier = currentFrontApplication()?.bundleIdentifier else { return false }
        return applications.contains { $0.identifier == identifier }
    }

    func frontApplicationSearchMetadata() -> (name: String, bundleIdentifier: String)? {
        guard let application = currentFrontApplication(),
              let bundleIdentifier = application.bundleIdentifier else { return nil }
        return (application.localizedName ?? bundleIdentifier, bundleIdentifier)
    }

    private func currentFrontApplication() -> NSRunningApplication? {
        return frontApplication.value ?? NSWorkspace.shared.frontmostApplication
    }

    func add(with appInfo: BoardManApplicationInfo) {
        guard !applications.contains(appInfo) else { return }
        applications.append(appInfo)
        save()
    }

    func delete(with appInfo: BoardManApplicationInfo) {
        applications.removeAll { $0 == appInfo }
        save()
    }

    func delete(with index: Int) {
        guard applications.indices.contains(index) else { return }
        delete(with: applications[index])
    }

    func copiedProcessIsExcludedApplications(pasteboard: NSPasteboard) -> Bool {
        guard let pasteboardTypes = pasteboard.types,
              let specialApplication = pasteboardTypes.compactMap({ SpecialApplication(rawValue: $0.rawValue) }).first else {
            return false
        }
        return specialApplication.isExcluded(applications: applications)
    }

    private func save() {
        let data = applications.archive()
        AppEnvironment.current.defaults.set(data, forKey: Constants.UserDefaults.excludeApplications)
        AppEnvironment.current.defaults.synchronize()
    }
}

private extension ExcludeAppService {
    enum SpecialApplication: String {
        case onePassword = "com.agilebits.onepassword"

        private var macApplicationIdentifiers: Set<String> {
            switch self {
            case .onePassword:
                return ["com.agilebits.onepassword-osx", "com.agilebits.onepassword7"]
            }
        }

        func isExcluded(applications: [BoardManApplicationInfo]) -> Bool {
            applications.contains { macApplicationIdentifiers.contains($0.identifier) }
        }
    }
}
