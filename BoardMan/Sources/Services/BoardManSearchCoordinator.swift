//
//  BoardManSearchCoordinator.swift
//  Board-Man
//
//  Search orchestration extracted from BoardManPanel so the panel owns presentation,
//  while query eligibility, indexed lookup, compatibility matches, and ranking live here.
//

import Foundation

// MARK: - History Display Names

final class HistoryDisplayNameStore {
    static let shared = HistoryDisplayNameStore()

    private let defaults: UserDefaults
    private let namesKey = "com.uniplanck.BoardMan.historyDisplayNames"
    private let nameOnlyKey = "com.uniplanck.BoardMan.historyNameOnlyIdentifiers"

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
    }

    func name(for identifier: String) -> String? {
        let value = names[identifier]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    func matchingIdentifiers(containing query: String) -> Set<String> {
        Set(searchMatches(for: query).keys)
    }

    func searchMatches(for query: String) -> [String: Int] {
        var matches: [String: Int] = [:]
        for (identifier, value) in names {
            if let matchClass = BoardManSearchMatcher.matchClass(query: query, fields: [value]) {
                matches[identifier] = matchClass
            }
        }
        return matches
    }

    func setName(_ value: String, for identifier: String) {
        var values = names
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            values.removeValue(forKey: identifier)
            setNameOnly(false, for: identifier)
        } else {
            values[identifier] = trimmed
        }
        defaults.set(values, forKey: namesKey)
        notifyChange()
    }

    func isNameOnly(_ identifier: String) -> Bool {
        nameOnlyIdentifiers.contains(identifier) && name(for: identifier) != nil
    }

    func setNameOnly(_ enabled: Bool, for identifier: String) {
        var identifiers = nameOnlyIdentifiers
        if enabled, name(for: identifier) != nil {
            identifiers.insert(identifier)
        } else {
            identifiers.remove(identifier)
        }
        defaults.set(Array(identifiers).sorted(), forKey: nameOnlyKey)
        notifyChange()
    }

    func remove(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        let removed = Set(identifiers)
        var storedNames = names
        removed.forEach { storedNames.removeValue(forKey: $0) }
        defaults.set(storedNames, forKey: namesKey)
        defaults.set(Array(nameOnlyIdentifiers.subtracting(removed)).sorted(), forKey: nameOnlyKey)
        notifyChange()
    }

    private var names: [String: String] {
        defaults.dictionary(forKey: namesKey) as? [String: String] ?? [:]
    }

    private var nameOnlyIdentifiers: Set<String> {
        Set(defaults.stringArray(forKey: nameOnlyKey) ?? [])
    }

    private func notifyChange() {
        defaults.synchronize()
        NotificationCenter.default.post(
            name: Notification.Name(rawValue: Constants.Notification.closeSnippetEditor),
            object: nil
        )
    }
}

// MARK: - Search Coordination

struct BoardManSearchResolution {
    let items: [BoardManHistoryItem]
    let query: String
    let indexedHitCount: Int
    let performedSearch: Bool
    let hasStoreFilters: Bool
}

final class BoardManSearchCoordinator {
    private let store: BoardManStore
    private let displayNameStore: HistoryDisplayNameStore

    init(
        store: BoardManStore,
        displayNameStore: HistoryDisplayNameStore = .shared
    ) {
        self.store = store
        self.displayNameStore = displayNameStore
    }

    func resolve(
        parsedSearch: BoardManParsedSearchQuery,
        defaultScope: BoardManSearchScope,
        visibleItems: [BoardManHistoryItem],
        totalItemCount: Int,
        includeHistoryDisplayNames: Bool,
        benchmarkIsolation: Bool = false
    ) -> BoardManSearchResolution {
        let request = parsedSearch.request
        let query = request.text.lowercased()
        let scopedVisibleItems = visibleItems.filter { item in
            switch request.scope {
            case .all:
                return true
            case .history:
                return item.source == .clip
            case .snippets:
                return item.source == .snippet
            }
        }
        let eligibleVisibleItems = parsedSearch.pinnedOnly
            ? scopedVisibleItems.filter(\.isPinned)
            : scopedVisibleItems
        let hasExplicitSearch = !query.isEmpty || request.hasStoreFilters
            || parsedSearch.pinnedOnly || request.scope != defaultScope

        guard hasExplicitSearch, !query.isEmpty || request.hasStoreFilters else {
            return BoardManSearchResolution(
                items: eligibleVisibleItems,
                query: query,
                indexedHitCount: 0,
                performedSearch: false,
                hasStoreFilters: request.hasStoreFilters
            )
        }

        // Keep indexed search synchronous while the 10k-item FTS gate remains sub-millisecond.
        // There is no long-lived search task to supersede or cancel; add async cancellation only if profiling justifies it.
        let hits: [BoardManSearchHit]
        #if DEBUG
        if benchmarkIsolation && !request.hasStoreFilters {
            hits = benchmarkSearchHits(query: query, items: eligibleVisibleItems, scope: request.scope)
        } else {
            hits = store.search(request, limit: max(1, totalItemCount))
        }
        #else
        hits = store.search(request, limit: max(1, totalItemCount))
        #endif

        var visibleBySearchKey: [String: BoardManHistoryItem] = [:]
        var visibleOrderBySearchKey: [String: Int] = [:]
        for (order, item) in eligibleVisibleItems.enumerated() {
            guard let source = searchSource(for: item.source) else { continue }
            let key = searchKey(source: source, identifier: item.dataHash)
            visibleBySearchKey[key] = item
            visibleOrderBySearchKey[key] = order
        }

        var candidatesByKey: [String: BoardManSearchRankCandidate] = [:]
        for hit in hits {
            let key = searchKey(source: hit.source, identifier: hit.identifier)
            guard let item = visibleBySearchKey[key],
                  let baseOrder = visibleOrderBySearchKey[key] else { continue }
            candidatesByKey[key] = BoardManSearchRankCandidate(
                hit: hit,
                isPinned: item.isPinned,
                usageCount: item.pasteCount,
                baseOrder: baseOrder
            )
        }

        // Custom display names remain in UserDefaults for compatibility. Convert their
        // exact/prefix/contains match into the same deterministic ranking path as indexed hits.
        if includeHistoryDisplayNames, !query.isEmpty, !request.hasStoreFilters {
            for (identifier, matchClass) in displayNameStore.searchMatches(for: query) {
                let key = searchKey(source: .history, identifier: identifier)
                guard let item = visibleBySearchKey[key],
                      let baseOrder = visibleOrderBySearchKey[key] else { continue }
                let customHit = BoardManSearchHit(
                    identifier: identifier,
                    source: .history,
                    matchClass: matchClass,
                    relevance: 0
                )
                if let existing = candidatesByKey[key], existing.hit.matchClass <= matchClass {
                    continue
                }
                candidatesByKey[key] = BoardManSearchRankCandidate(
                    hit: customHit,
                    isPinned: item.isPinned,
                    usageCount: item.pasteCount,
                    baseOrder: baseOrder
                )
            }
        }

        let rankedHits = BoardManSearchRanker.rank(Array(candidatesByKey.values))
        let items = rankedHits.compactMap { hit in
            visibleBySearchKey[searchKey(source: hit.source, identifier: hit.identifier)]
        }
        return BoardManSearchResolution(
            items: items,
            query: query,
            indexedHitCount: hits.count,
            performedSearch: true,
            hasStoreFilters: request.hasStoreFilters
        )
    }

    private func searchSource(for source: BoardManPanelItemSource) -> BoardManSearchSource? {
        switch source {
        case .clip:
            return .history
        case .snippet:
            return .snippet
        case .selection:
            return nil
        case .favorite:
            return nil
        }
    }

    private func searchKey(source: BoardManSearchSource, identifier: String) -> String {
        "\(source.rawValue):\(identifier)"
    }

    #if DEBUG
    private func benchmarkSearchHits(
        query: String,
        items: [BoardManHistoryItem],
        scope: BoardManSearchScope
    ) -> [BoardManSearchHit] {
        items.compactMap { item in
            guard let source = searchSource(for: item.source) else { return nil }
            switch source {
            case .history where scope == .snippets:
                return nil
            case .snippet where scope == .history:
                return nil
            case .history, .snippet:
                break
            }
            guard let matchClass = BoardManSearchMatcher.matchClass(
                query: query,
                fields: [item.primaryTitle, item.title, item.previewTitle]
            ) else { return nil }
            return BoardManSearchHit(
                identifier: item.dataHash,
                source: source,
                matchClass: matchClass,
                relevance: Double(matchClass)
            )
        }
    }
    #endif
}
