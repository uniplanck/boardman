//
//  BoardManSQLiteShadowReplicator.swift
//  Board-Man
//
//  Keeps the SQLiteData history store synchronized while Realm remains authoritative.
//

import Foundation
import RealmSwift

final class BoardManSQLiteShadowReplicator {
    static let shared = BoardManSQLiteShadowReplicator()

    private let replicationQueue = DispatchQueue(
        label: "com.uniplanck.BoardMan.SQLiteShadowReplication",
        qos: .utility
    )
    private var notificationToken: NotificationToken?
    private var sqliteStore: SQLiteBoardManStore?

    private init() {}

    func start(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard notificationToken == nil else { return }
        guard !BoardManRuntimeEnvironment.isRunningTests(environment: environment) else { return }

        do {
            let sqliteStore = try SQLiteBoardManStore(
                fileURL: BoardManRuntimeSupport.sqliteHistoryFileURL(environment: environment)
            )
            let realm = try Realm()
            let clips = realm.objects(BoardManClip.self)

            self.sqliteStore = sqliteStore
            notificationToken = clips.observe { [weak self, weak sqliteStore] changes in
                guard let self, let sqliteStore else { return }

                switch changes {
                case .initial(let collection), .update(let collection, _, _, _):
                    let snapshots = Array(collection.map(BoardManClipSnapshot.init))
                    replicationQueue.async {
                        sqliteStore.replaceAllClips(with: snapshots)
                    }
                case .error(let error):
                    BoardManRuntimeSupport.sendDiagnosticLog(
                        "SQLite shadow replication failed: \(error.localizedDescription)"
                    )
                }
            }
        } catch {
            BoardManRuntimeSupport.sendDiagnosticLog(
                "SQLite shadow store initialization failed: \(error.localizedDescription)"
            )
        }
    }

    func stop() {
        notificationToken?.invalidate()
        notificationToken = nil
        sqliteStore = nil
    }
}
