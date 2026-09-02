//
//  BoardManScreenshotObserver.swift
//  Board-Man
//

import Foundation

protocol BoardManScreenshotObserverDelegate: AnyObject {
    func screenshotObserver(_ observer: BoardManScreenshotObserver, addedFileAt path: String)
}

final class BoardManScreenshotObserver: NSObject {

    weak var delegate: BoardManScreenshotObserverDelegate?
    var isEnabled = false

    private var query: NSMetadataQuery?
    private var initialGatheringFinished = false

    func start() {
        guard query == nil else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = NSPredicate(format: "%K == 1", "kMDItemIsScreenCapture")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidFinishGathering(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        self.query = query
        initialGatheringFinished = false
        query.start()
    }

    func stop() {
        guard let query else { return }
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
        query.stop()
        self.query = nil
        initialGatheringFinished = false
    }

    deinit {
        stop()
    }

    @objc private func metadataQueryDidFinishGathering(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery, query === self.query else { return }
        initialGatheringFinished = true
        query.enableUpdates()
    }

    @objc private func metadataQueryDidUpdate(_ notification: Notification) {
        guard initialGatheringFinished, isEnabled else { return }
        guard let addedItems = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] else { return }

        for item in addedItems {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            delegate?.screenshotObserver(self, addedFileAt: path)
        }
    }
}
