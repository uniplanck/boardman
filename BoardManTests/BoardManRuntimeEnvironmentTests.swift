import Foundation
import Testing
@testable import Board_Man

@Suite(.serialized)
struct BoardManRuntimeEnvironmentTests {
    @Test
    func benchmarkProfileIsExplicitAndStorageIsIsolated() {
        let benchmarkEnvironment = [BoardManRuntimeEnvironment.benchmarkProfileEnvironmentKey: "1"]
        #expect(BoardManRuntimeEnvironment.isBenchmarkProfile(environment: benchmarkEnvironment))
        #expect(BoardManRuntimeEnvironment.isBenchmarkProfile(environment: [
            BoardManRuntimeEnvironment.benchmarkProfileEnvironmentKey: "TRUE"
        ]))
        #expect(!BoardManRuntimeEnvironment.isBenchmarkProfile(environment: [:]))
        #expect(!BoardManRuntimeEnvironment.isBenchmarkProfile(environment: [
            BoardManRuntimeEnvironment.benchmarkProfileEnvironmentKey: "0"
        ]))

        let normalSupport = BoardManRuntimeSupport.applicationSupportFolder(environment: [:])
        let benchmarkSupport = BoardManRuntimeSupport.applicationSupportFolder(environment: benchmarkEnvironment)
        #expect(normalSupport != benchmarkSupport)
        #expect(benchmarkSupport.hasSuffix("Benchmark"))
        #expect(BoardManRuntimeSupport.benchmarkRealmFileURL(environment: [:]) == nil)
        #expect(
            BoardManRuntimeSupport.benchmarkRealmFileURL(environment: benchmarkEnvironment)?
                .path.hasSuffix("benchmark.realm") == true
        )
        #expect(
            BoardManRuntimeSupport.performanceLogDirectory(environment: benchmarkEnvironment)
                .path.hasSuffix("Board-Man Benchmark")
        )
        #expect(
            !BoardManRuntimeSupport.performanceLogDirectory(environment: [:])
                .path.hasSuffix("Board-Man Benchmark")
        )

        let normalArchive = TextHistoryArchiveStore.defaultFileURL(environment: [:])
        let benchmarkArchive = TextHistoryArchiveStore.defaultFileURL(environment: benchmarkEnvironment)
        #expect(normalArchive != benchmarkArchive)
        #expect(benchmarkArchive.path.contains("Board-Man Benchmark Archive"))

        let normalLocalState = BoardManLocalStatePaths.directoryURL(environment: [:])
        let benchmarkLocalState = BoardManLocalStatePaths.directoryURL(environment: benchmarkEnvironment)
        #expect(normalLocalState != benchmarkLocalState)
        #expect(benchmarkLocalState.path.contains("Benchmark/Local State"))
        #expect(!benchmarkLocalState.path.contains("com.uniplanck.BoardMan"))

        #expect(
            !HotKeyService.shouldRegisterSystemHotKeys(
                environment: benchmarkEnvironment,
                arguments: [],
                bundlePaths: [],
                hasXCTestCase: false
            )
        )

        let key = "BoardManBenchmarkIsolation-\(UUID().uuidString)"
        let benchmarkDefaults = BoardManRuntimeSupport.runtimeDefaults(environment: benchmarkEnvironment)
        benchmarkDefaults.set("benchmark", forKey: key)
        defer { benchmarkDefaults.removeObject(forKey: key) }
        #expect(benchmarkDefaults.string(forKey: key) == "benchmark")
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }
}
