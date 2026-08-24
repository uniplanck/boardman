import AppKit
import Foundation
import RealmSwift
import Testing
@testable import Board_Man

@MainActor @Suite(.serialized)
final class BoardManPerformanceBaselineTests {
    private struct Metric: Codable {
        let name: String
        let fixture: String
        let iterations: Int
        let p50Milliseconds: Double
        let p95Milliseconds: Double
        let averageMilliseconds: Double
        let maxMilliseconds: Double
    }

    private struct Report: Codable {
        let schemaVersion: Int
        let capturedAt: String
        let buildConfiguration: String
        let architecture: String
        let operatingSystem: String
        let processorCount: Int
        let physicalMemoryBytes: UInt64
        let fixtureHistoryCounts: [Int]
        let fixtureTemplateCounts: [Int]
        let metrics: [Metric]
    }

    @Test
    func phase1DeterministicPanelBaseline() throws {
        let originalRealmConfiguration = Realm.Configuration.defaultConfiguration
        Realm.Configuration.defaultConfiguration = Realm.Configuration(
            inMemoryIdentifier: "BoardManPhase1Benchmark-\(UUID().uuidString)"
        )
        defer { Realm.Configuration.defaultConfiguration = originalRealmConfiguration }

        let realm = try Realm()
        let folders = makeBenchmarkFolders(count: 10)
        try realm.write { realm.add(folders) }

        var metrics = benchmarkHistoryMetrics()
        metrics.append(contentsOf: benchmarkTemplateMetrics(folders: folders))

        #expect(metrics.allSatisfy { metric in
            metric.iterations > 0
                && metric.p50Milliseconds.isFinite
                && metric.p95Milliseconds.isFinite
                && metric.averageMilliseconds.isFinite
                && metric.maxMilliseconds.isFinite
        })

        let report = Report(
            schemaVersion: 1,
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            buildConfiguration: "Debug test host; baseline only, not an SLO gate",
            architecture: architectureName,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            processorCount: ProcessInfo.processInfo.processorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            fixtureHistoryCounts: [0, 100, 1_000, 10_000],
            fixtureTemplateCounts: [100, 1_000],
            metrics: metrics
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        let json = try #require(String(data: data, encoding: .utf8))
        print("BOARDMAN_PHASE1_BENCHMARK_JSON=\(json)")

        let requestedOutputPath = ProcessInfo.processInfo.environment["BOARDMAN_BENCHMARK_OUTPUT"]
        let outputPath = requestedOutputPath?.isEmpty == false
            ? requestedOutputPath!
            : "/tmp/boardman-phase1-benchmark.json"
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print("BOARDMAN_PHASE1_BENCHMARK_OUTPUT=\(outputPath)")
    }

    private func makeBenchmarkFolders(count: Int) -> [BoardManFolder] {
        return (0..<count).map { index in
            let folder = BoardManFolder()
            folder.index = index
            folder.identifier = "benchmark-group-\(index)"
            folder.title = "Benchmark Group \(index)"
            folder.enable = true
            return folder
        }
    }

    private func benchmarkHistoryMetrics() -> [Metric] {
        let history100 = makeHistoryItems(count: 100)
        let history1k = makeHistoryItems(count: 1_000)
        let history10k = makeHistoryItems(count: 10_000)
        let pinned1k = makeHistoryItems(count: 1_000, pinnedEvery: 2)
        let longText100 = makeHistoryItems(count: 100, longText: true)
        var metrics = [Metric]()

        for (fixture, items, iterations) in [
            ("empty", [BoardManHistoryItem](), 8),
            ("100", history100, 8),
            ("1000", history1k, 6),
            ("10000", history10k, 4)
        ] {
            metrics.append(measure(name: "history_load", fixture: fixture, iterations: iterations) {
                let panel = BoardManPanel()
                panel.setBenchmarkIsolationForTesting(true)
                panel.loadItemsForTesting(items)
            })
        }

        let searchPanel = BoardManPanel()
        searchPanel.setBenchmarkIsolationForTesting(true)
        searchPanel.loadItemsForTesting(history10k)
        metrics.append(measure(name: "search_full_result", fixture: "history-10000-single-hit", iterations: 12) {
            searchPanel.setSearchQueryForTesting("needle-9999")
        })
        #expect(searchPanel.visibleItemCountForTesting == 1)

        searchPanel.setSearchQueryForTesting("")
        searchPanel.selectItemForTesting(at: 0)
        metrics.append(measure(
            name: "keyboard_row_navigation",
            fixture: "history-10000",
            iterations: 40,
            performsWarmup: false
        ) {
            _ = searchPanel.moveVerticalSelectionForTesting(delta: 1)
        })
        #expect(searchPanel.selectedIndexForTesting == 40)

        let pinnedPanel = BoardManPanel()
        pinnedPanel.setBenchmarkIsolationForTesting(true)
        metrics.append(measure(name: "history_load", fixture: "1000-half-pinned", iterations: 6) {
            pinnedPanel.loadItemsForTesting(pinned1k)
        })
        #expect(pinnedPanel.visibleItemCountForTesting == pinned1k.count)

        let longTextPanel = BoardManPanel()
        longTextPanel.setBenchmarkIsolationForTesting(true)
        longTextPanel.loadItemsForTesting(longText100)
        metrics.append(measure(name: "search_full_result", fixture: "100-long-text", iterations: 8) {
            longTextPanel.setSearchQueryForTesting("needle-99")
        })
        #expect(longTextPanel.visibleItemCountForTesting == 1)
        return metrics
    }

    private func benchmarkTemplateMetrics(folders: [BoardManFolder]) -> [Metric] {
        let templates100 = makeTemplateItems(count: 100, groupCount: folders.count)
        let templates1k = makeTemplateItems(count: 1_000, groupCount: folders.count)
        var metrics = [Metric]()

        let templates100Panel = BoardManPanel()
        templates100Panel.setBenchmarkIsolationForTesting(true)
        templates100Panel.openSnippetsManagerMode()
        metrics.append(measure(name: "template_load", fixture: "100", iterations: 8) {
            templates100Panel.loadItemsForTesting(templates100)
        })

        let templates1kPanel = BoardManPanel()
        templates1kPanel.setBenchmarkIsolationForTesting(true)
        templates1kPanel.openSnippetsManagerMode()
        metrics.append(measure(name: "template_load", fixture: "1000", iterations: 6) {
            templates1kPanel.loadItemsForTesting(templates1k)
        })
        templates1kPanel.loadItemsForTesting(templates1k)
        metrics.append(measure(name: "template_search", fixture: "1000-single-hit", iterations: 10) {
            templates1kPanel.setSearchQueryForTesting("template-999")
        })
        #expect(templates1kPanel.visibleItemCountForTesting == 1)

        templates1kPanel.setSearchQueryForTesting("")
        metrics.append(measure(name: "template_group_filter", fixture: "1000-10-groups", iterations: 8) {
            templates1kPanel.setSnippetGroupIdentifiersForTesting([folders[0].identifier])
        })
        #expect(templates1kPanel.visibleItemCountForTesting == 100)

        let horizontalPanel = BoardManPanel()
        horizontalPanel.setBenchmarkIsolationForTesting(true)
        horizontalPanel.loadItemsForTesting(templates1k)
        metrics.append(measure(name: "horizontal_group_traversal", fixture: "10-groups", iterations: 5) {
            horizontalPanel.selectHistoryTab()
            for _ in 0...folders.count {
                horizontalPanel.moveHorizontalNavigationForTesting(delta: 1)
            }
        })
        return metrics
    }

    private func measure(
        name: String,
        fixture: String,
        iterations: Int,
        performsWarmup: Bool = true,
        operation: () -> Void
    ) -> Metric {
        if performsWarmup {
            operation()
        }
        var samples = [Double]()
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let startedAt = CFAbsoluteTimeGetCurrent()
            operation()
            samples.append((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
        }
        let sorted = samples.sorted()
        let p50Index = max(0, min(sorted.count - 1, Int((Double(sorted.count - 1) * 0.50).rounded())))
        let p95Index = max(0, min(sorted.count - 1, Int((Double(sorted.count - 1) * 0.95).rounded(.up))))
        return Metric(
            name: name,
            fixture: fixture,
            iterations: iterations,
            p50Milliseconds: roundedMilliseconds(sorted[p50Index]),
            p95Milliseconds: roundedMilliseconds(sorted[p95Index]),
            averageMilliseconds: roundedMilliseconds(samples.reduce(0, +) / Double(samples.count)),
            maxMilliseconds: roundedMilliseconds(sorted.last ?? 0)
        )
    }

    private func roundedMilliseconds(_ value: Double) -> Double {
        return (value * 1_000).rounded() / 1_000
    }

    private func makeHistoryItems(
        count: Int,
        pinnedEvery: Int? = nil,
        longText: Bool = false
    ) -> [BoardManHistoryItem] {
        let longPayload = longText ? String(repeating: "boardman-long-payload-0123456789 ", count: 512) : ""
        return (0..<count).map { index in
            let title = index == count - 1 ? "needle-\(index)" : "history-\(index)"
            let typeLabel: String
            switch index % 4 {
            case 0: typeLabel = "Text • Safari"
            case 1: typeLabel = "URL • Google Chrome"
            case 2: typeLabel = "Image • Finder"
            default: typeLabel = "File • Terminal"
            }
            return BoardManHistoryItem(
                title: title,
                primaryTitle: title,
                compactTitle: title,
                metadataText: typeLabel,
                timestampText: "1m",
                countText: "",
                previewTitle: longText ? "\(longPayload)\(title)" : "fixture payload \(title)",
                dataHash: "history-hash-\(index)",
                imageDataPath: index % 4 == 2 ? "/tmp/boardman-benchmark-image-\(index).png" : "",
                inlineThumbnail: nil,
                pasteCount: index % 17,
                isPinned: pinnedEvery.map { index % $0 == 0 } ?? false,
                isMasked: false,
                isEnabled: true,
                source: .clip,
                categoryIdentifier: nil,
                categoryTitle: nil
            )
        }
    }

    private func makeTemplateItems(count: Int, groupCount: Int) -> [BoardManHistoryItem] {
        return (0..<count).map { index in
            let title = "template-\(index)"
            let groupIndex = index % max(1, groupCount)
            return BoardManHistoryItem(
                title: title,
                primaryTitle: title,
                compactTitle: title,
                metadataText: "Benchmark Group \(groupIndex)",
                timestampText: "",
                countText: "",
                previewTitle: "Template body \(title) with reusable local text",
                dataHash: "template-hash-\(index)",
                imageDataPath: "",
                inlineThumbnail: nil,
                pasteCount: index % 13,
                isPinned: false,
                isMasked: false,
                isEnabled: true,
                source: .snippet,
                categoryIdentifier: "benchmark-group-\(groupIndex)",
                categoryTitle: "Benchmark Group \(groupIndex)"
            )
        }
    }

    private var architectureName: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
